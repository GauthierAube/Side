// Le tiroir montre une application à la fois (mini carrousel, colonne d'icônes).
// Partie de PanneauBas (PanneauBas.swift), rangée à part le 15/11/2026 sans changement.

import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

extension PanneauBas {
    // MARK: Une application à la fois (13/11/2026)
    // Le tiroir montre le coin multimédia, puis UNE application sur toute la place restante. Les autres sont rangées au-dessus
    // ou au-dessous, comme des cartes : on passe de l'une à l'autre en prolongeant le geste à quatre doigts (la carte suit les doigts),
    // ou par la colonne d'icônes à droite. L'ancienne bande de tuiles reste disponible dans les réglages.
    var uneApp: Bool { ConfigTiroir.commun.uneApp }
    /// Sens de l'empilement à l'écran : les cartes suivent les doigts (vers le haut pour un tiroir du bas, vers le bas sinon).
    var sensV: CGFloat { enHaut ? -1 : 1 }
    /// La carte regardée (le rang le plus proche du défilement).
    var rangCourant: Int {
        guard let p = panneau else { return 0 }
        let h = bande(p.frame).height + marge
        return max(0, min(emprunts.count - 1, Int((défilement / max(h, 1)).rounded())))
    }

    /// Emplacement du panneau (coordonnées AppKit) : collé au bas (ou au haut) de l'écran, à la hauteur choisie.
    func cadre(_ ecran: NSScreen) -> CGRect {
        let z = ecran.visibleFrame
        let voulue = hauteurChoisie > 0 ? hauteurChoisie : (z.height * 0.52).rounded()
        // Jamais plus bas que l'application la plus haute du tiroir (elle dépasserait), ni que le minimum habituel.
        let hApps = (emprunts.compactMap { hauteursMini[$0.bundle] }.max() ?? 0) + 2 * marge
        let h = min(max(voulue, hauteurMini, hApps), (z.height * 0.94).rounded())
        // Réduit, le tiroir reste centré ; jamais moins que le coin multimédia et une application (720 points au moins).
        let w = min(z.width, max(min(largeurTiroirMini, z.width), (z.width * largeurChoisie).rounded()))
        return CGRect(x: (z.midX - w / 2).rounded(), y: enHaut ? z.maxY - h : z.minY, width: w, height: h)
    }

    /// Le panneau en coordonnées globales (origine en haut à gauche), comme les fenêtres des autres applications.
    func panneauGlobal(_ c: CGRect) -> CGRect {
        Ecrans.versAX(c)
    }

    /// La bande où tout défile, sur toute la largeur du panneau (coordonnées globales) : le lecteur Spotify d'abord, puis les tuiles.
    func bande(_ c: CGRect) -> CGRect {
        let g = panneauGlobal(c)
        let x0 = g.minX + marge
        let x1 = g.maxX - marge
        return CGRect(x: x0, y: g.minY + marge, width: max(100, x1 - x0), height: g.height - 2 * marge)
    }

    /// Taille de chaque fenêtre et hauteur où elle se pose, telles que vous les avez laissées : [—, décalage vertical, largeur, hauteur].
    var disposition: [String: [Double]] {
        get { (UserDefaults.standard.dictionary(forKey: "panneauBasDisposition") as? [String: [Double]]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "panneauBasDisposition") }
    }

    /// Place de chaque tuile, l'une après l'autre le long de la bande (coordonnées globales).
    func zones(_ c: CGRect) -> [CGRect] {
        if uneApp {
            let b = bande(c), h = b.height
            let x = b.minX + débutTuiles, w = max(200, b.width - débutTuiles - largeurColonne - marge)
            let maxi = taillesMaxi
            return emprunts.indices.map { i in
                let y = b.minY + sensV * (CGFloat(i) * (h + marge) - défilement)
                // Une application qui refuse de grandir est centrée dans sa place.
                guard let m = maxi[emprunts[i].bundle], m.count == 2 else { return CGRect(x: x, y: y, width: w, height: h) }
                let wi = min(w, CGFloat(m[0])), hi = min(h, CGFloat(m[1]))
                return CGRect(x: (x + (w - wi) / 2).rounded(), y: (y + (h - hi) / 2).rounded(), width: wi, height: hi)
            }
        }
        let b = bande(c), retenue = disposition
        var x = b.minX - défilement + débutTuiles      // le coin multimédia ouvre la bande
        let haut = b.minY
        return emprunts.map { e in
            // Un carrousel : toutes les tuiles ont la même hauteur et sont alignées ; seule la largeur change de l'une à l'autre.
            var l: CGFloat = e.note != nil ? 430 : 720
            if let r = retenue[e.nom], r.count == 4 { l = r[2] }
            l = min(max(l, 200), b.width)
            let h = b.maxY - haut, y = haut
            defer { x += l + marge }
            return CGRect(x: x, y: y, width: l, height: h)
        }
    }

    /// Les décalages où une tuile commence pile au début de la bande, et le plus grand décalage possible.
    func arrêts(_ c: CGRect) -> (débuts: [CGFloat], maxi: CGFloat) {
        if uneApp {
            let h = bande(c).height + marge
            return (emprunts.indices.map { CGFloat($0) * h }, max(0, CGFloat(emprunts.count - 1) * h))
        }
        let b = bande(c), ancien = défilement
        défilement = 0
        let zs = zones(c)
        défilement = ancien
        let bout = (zs.last?.maxX ?? (b.minX + largeurTête)) + marge + largeurPlus     // jusqu'à la case « + »
        let maxi = max(0, bout - b.minX - b.width)
        return (zs.map { min($0.minX - b.minX, maxi) }, maxi)
    }

    /// Les tuiles entièrement visibles : ce sont les seules dont la vraie fenêtre est à l'écran.
    func entières(_ c: CGRect) -> [(EmpruntBas, CGRect)] {
        let b = bande(c)
        if uneApp {
            let pas = b.height + marge
            return zip(emprunts, zones(c)).enumerated().filter { abs(CGFloat($0.offset) * pas - défilement) < 1 }.map { ($0.element.0, $0.element.1) }
        }
        return zip(emprunts, zones(c)).filter { $0.1.minX >= b.minX - 1 && $0.1.maxX <= b.maxX + 1 }.map { ($0.0, $0.1) }
    }

    /// À la fermeture ou avant de défiler : retient la taille que vous avez donnée à chaque fenêtre.
    func retenir() {
        guard let p = panneau else { return }
        let g = panneauGlobal(p.frame)
        var d = disposition
        for (e, _) in entières(p.frame) where posées.contains(e.nom) {
            guard let f = fenetre(e), let c = AXBas.cadre(f), c.intersects(g), c.width >= 150, c.height >= 100 else { continue }
            d[e.nom] = [0, Double(c.minY - g.minY), Double(c.width), Double(c.height)]
        }
        disposition = d
    }

    func construire() -> NSPanel {
        let p = FenetrePanneauBas(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .normal                         // les fenêtres empruntées doivent pouvoir passer devant
        p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        p.animationBehavior = .none
        // Comme la carte de Side : la fenêtre ne bouge pas, c'est son contenu qui glisse depuis le bord de l'écran.
        let support = NSView()
        support.wantsLayer = true
        support.layer?.masksToBounds = true
        p.contentView = support
        let fond = FondPanneauBas()
        // Le même fond que le mini-Dock de Side : flou « popover », puis la teinte de fenêtre par-dessus.
        fond.material = .popover
        fond.blendingMode = .behindWindow
        fond.state = .active
        fond.wantsLayer = true
        fond.layer?.cornerRadius = Rayon.panneau
        fond.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        fond.layer?.masksToBounds = true
        fond.autoresizingMask = []
        let teinte = TeinteBas()
        teinte.wantsLayer = true
        teinte.autoresizingMask = [.width, .height]
        teinte.frame = fond.bounds
        fond.addSubview(teinte)
        self.teinte = teinte
        fond.registerForDraggedTypes([.fileURL])
        fond.auDépôt = { [weak self] urls in urls.forEach { self?.ajouter($0) } }
        support.addSubview(fond)
        self.fond = fond
        majFond()
        bandeVue.wantsLayer = true
        bandeVue.layer?.masksToBounds = true
        fond.addSubview(bandeVue)
        bandeVue.addSubview(lecteur)             // le lecteur défile avec les tuiles
        bandeVue.addSubview(choixMédia)
        // Le bord droit du coin multimédia se tire pour l'élargir ou le rétrécir (même largeur pour Spotify et YouTube).
        bandeVue.addSubview(poignéeMédia)
        poignéeMédia.auDebut = { [weak self] in
            guard let self else { return }
            self.largeurMédiaAuDépart = self.largeurTête
            _ = self.commencerDéfilement()
        }
        poignéeMédia.auTirage = { [weak self] d in
            guard let self else { return }
            LecteurYouTubeBas.largeurCommune = min(max(self.largeurMédiaAuDépart + d, LecteurYouTubeBas.largeurMini), 2400)
            self.déplacerImages(animé: false)
        }
        poignéeMédia.aLaFin = { [weak self] in
            guard let self, let p = self.panneau else { return }
            LecteurYouTubeBas.largeurCommune = self.largeurTête        // la largeur vraiment obtenue (bornée à la bande)
            self.finDéfilement?.cancel()
            if self.défile { self.finirDéfilement(vers: min(self.défilement, self.arrêts(p.frame).maxi)) } else { self.recharger(versLaFin: false) }
        }
        // Clic droit et glisser sur la barre des lecteurs : la liste des réglages est modifiée, le tiroir se met à jour tout seul.
        choixMédia.auRetrait = { cle in ConfigTiroir.commun.medias.removeAll { $0.id == cle } }
        choixMédia.auAjout = { m in if !ConfigTiroir.commun.medias.contains(where: { $0.id == m.id }) { ConfigTiroir.commun.medias.append(m) } }
        choixMédia.auxReglages = { [weak self] in self?.ouvrirLesRéglages() }
        choixMédia.auNouvelOrdre = { ordre in
            let actuels = ConfigTiroir.commun.medias
            let ranges = ordre.compactMap { cle in actuels.first { $0.id == cle } }
            if ranges.count == actuels.count { ConfigTiroir.commun.medias = ranges }
        }
        choixMédia.auChoix = { [weak self] m in
            guard let self else { return }
            self.média = m
            journalBas("coin multimédia : %@", m)
            if self.ouvert, self.panneau != nil { self.recharger(versLaFin: false) } else { self.placerLecteurs(hauteur: self.bandeVue.bounds.height, animé: false) }
        }
        plus.isBordered = false
        plus.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: String(localized: "Ajouter une application"))?
            .withSymbolConfiguration(.init(pointSize: 30, weight: .regular))
        plus.contentTintColor = .secondaryLabelColor
        plus.toolTip = String(localized: "Ajouter ou retirer une application du panneau")
        plus.target = self
        plus.action = #selector(ouvrirMenu(_:))
        bandeVue.addSubview(plus)                // la case « + » ferme la bande, après la dernière tuile
        // Le bandeau d'explication, affiché seulement par-dessus un plein écran d'Apple.
        banniere.wantsLayer = true
        banniere.layer?.cornerRadius = Rayon.carte
        banniere.layer?.backgroundColor = NSColor(white: 0, alpha: 0.78).cgColor
        let message = messageBanniere
        message.font = .systemFont(ofSize: 13, weight: .medium)
        message.textColor = .white
        let sortie = BoutonBas(title: String(localized: "Passer en faux plein écran"), target: self, action: #selector(sortirDuPleinÉcran))
        sortie.bezelStyle = .rounded
        sortie.controlSize = .regular
        boutonBanniere = sortie
        let rangee = NSStackView(views: [message, sortie])
        rangee.spacing = 14
        rangee.translatesAutoresizingMaskIntoConstraints = false
        banniere.addSubview(rangee)
        NSLayoutConstraint.activate([
            rangee.centerXAnchor.constraint(equalTo: banniere.centerXAnchor), rangee.centerYAnchor.constraint(equalTo: banniere.centerYAnchor),
        ])
        banniere.isHidden = true
        fond.addSubview(banniere)
        poignee.auDebut = { [weak self] in self?.commencerHauteur() }
        poignee.auTirage = { [weak self] d in self?.tirerHauteur(d) }
        poignee.aLaFin = { [weak self] in self?.finirHauteur() }
        fond.addSubview(poignee)
        // Après chaque clic dans le tiroir, ses tuiles repassent devant lui (voir repasserSousLesTuiles).
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] ev in
            if let self, ev.window === self.panneau {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.repasserSousLesTuiles() }
            }
            return ev
        }
        roue.isBordered = false
        roue.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: String(localized: "Réglages"))?
            .withSymbolConfiguration(.init(pointSize: 26, weight: .regular))      // la même taille que la case « + »
        roue.contentTintColor = .secondaryLabelColor
        roue.toolTip = String(localized: "Réglages de Side")
        roue.target = self
        roue.action = #selector(ouvrirLesRéglages)
        bandeVue.addSubview(roue)                // au bout de la bande, sous la case « + », alignée sur le bas des tuiles
        return p
    }
}
