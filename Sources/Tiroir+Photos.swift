// Les photos des tuiles qui voyagent avec le tiroir pendant qu'il glisse.
// Partie de PanneauBas (PanneauBas.swift), rangée à part le 15/11/2026 sans changement.

import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

extension PanneauBas {
    // MARK: Glissement, comme la carte de Side
    /// Place du contenu pour un avancement donné (0 : caché sous le bord ; 1 : à sa place).
    func origine(_ q: CGFloat) -> NSPoint {
        NSPoint(x: 0, y: (enHaut ? 1 : -1) * (panneau?.frame.height ?? 0) * (1 - min(1, max(0, q))))      // caché au-delà de son bord
    }

    func poser(_ q: CGFloat) {
        self.q = q
        fond?.setFrameOrigin(origine(q))
        panneau?.alphaValue = min(1, q * 3)
    }

    func glisser(vers cible: CGFloat, duree: TimeInterval, courbe: CAMediaTimingFunction, fin: @escaping () -> Void) {
        q = cible
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duree
            ctx.timingFunction = courbe
            fond?.animator().setFrameOrigin(origine(cible))
            panneau?.animator().alphaValue = cible > 0 ? 1 : 0
        }, completionHandler: fin)
    }

    var reduit: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Photos des tuiles
    /// La photo d'une tuile, à la pleine résolution de l'écran : on ne doit pas la distinguer de la vraie fenêtre.
    /// `fraîche` : on la refait maintenant. Sinon on reprend la dernière, prise quand la fenêtre a quitté l'écran :
    /// l'ouverture du panneau n'attend ainsi aucune photo.
    func photo(_ e: EmpruntBas, taille: CGSize, fraîche: Bool) -> NSImage {
        if !fraîche, let gardée = photos[e.nom] {
            gardée.size = taille
            return gardée
        }
        var wid: CGWindowID = 0
        if CGPreflightScreenCaptureAccess(), let f = fenetre(e), _AXUIElementGetWindow(f, &wid) == .success,
           let cg = photoFenetreBas(.null, 8, wid, 1 | 8)?.takeRetainedValue(), cg.width > 8 {
            let img = NSImage(cgImage: cg, size: taille)
            photos[e.nom] = img
            return img
        }
        if let gardée = photos[e.nom] { gardée.size = taille; return gardée }
        // Pas d'autorisation, ou application pas encore ouverte : une carte claire avec son icône.
        return NSImage(size: taille, flipped: false) { r in
            NSColor(white: 0.93, alpha: 1).setFill()
            NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
            let c: CGFloat = 72
            NSWorkspace.shared.icon(forFile: e.chemin).draw(in: NSRect(x: r.midX - c / 2, y: r.midY - c / 2, width: c, height: c))
            return true
        }
    }

    /// Place d'une tuile dans la bande (coordonnées de la vue), à partir de sa place à l'écran.
    func dansLaBande(_ r: CGRect, _ b: CGRect) -> NSRect {
        NSRect(x: r.minX - b.minX, y: b.height - (r.minY - b.minY) - r.height, width: r.width, height: r.height)
    }

    /// Refait la photo de chaque tuile et la pose à sa place dans la bande.
    /// `fraîches` : les tuiles à l'écran sont rephotographiées (elles ont pu changer) ; les autres gardent leur dernière photo.
    func poserImages(fraîches: Bool = true) {
        let àLÉcran = Set((panneau.map { entières($0.frame) } ?? []).map { $0.0.nom })
        trouer(nil)                      // les photos reviennent : plus de trou dessous
        images.values.forEach { $0.removeFromSuperview() }
        images = [:]
        guard let p = panneau else { return }
        let b = bande(p.frame)
        placerLecteurs(hauteur: b.height, animé: false)
        placerPlus(animé: false)
        for (i, (e, r)) in zip(emprunts, zones(p.frame)).enumerated() {
            let v = ImageTuileBas(frame: dansLaBande(r, b))
            v.image = photo(e, taille: r.size, fraîche: fraîches && àLÉcran.contains(e.nom))
            v.imageScaling = .scaleAxesIndependently
            v.wantsLayer = true
            v.layer?.cornerRadius = Rayon.tuile
            v.layer?.cornerCurve = .continuous
            v.layer?.masksToBounds = true
            v.auClic = { [weak self] in self?.montrerTuile(i) }
            v.auMenu = { [weak self, weak v] ev in if let v { self?.menuIcône(i, ev, v) } }   // le même menu que l'icône de la barre
            bandeVue.addSubview(v)
            images[e.nom] = v
        }
    }

    /// Les deux lecteurs maison, au début de la bande : Spotify, puis YouTube.
    func placerLecteurs(hauteur: CGFloat, animé: Bool) {
        // Le coin multimédia, au début de la bande : un petit sélecteur en haut (s'il y a le choix), et dessous l'élément choisi.
        let liste = médias, choisi = média
        // Les pages des éléments retirés dans les réglages s'en vont (et se taisent).
        for (id, vue) in pagesWeb where !liste.contains(where: { $0.id == id && $0.genre != "spotify" }) {
            // Sans cela la page restait en mémoire et le son continuait, sans moyen de l'arrêter.
            if let lecteur = vue as? LecteurYouTubeBas { lecteur.fermer() } else { TuilePeinard.mettreEnPause() }
            vue.removeFromSuperview()
            pagesWeb[id] = nil
        }
        let seul = liste.count <= 1
        choixMédia.isHidden = seul
        choixMédia.montrer(liste.map { ($0.id, $0.nom) }, choisi: choisi)
        // Tiroir agrandi : le coin multimédia se replie (la musique ou la vidéo continue, cachée) pour laisser toute la largeur.
        let replié = agrandi && uneApp
        if replié { choixMédia.isHidden = true }
        poignéeMédia.isHidden = liste.isEmpty || replié
        let h = max(0, seul ? hauteur : hauteur - hauteurChoix - 6)
        let x0 = uneApp ? 0 : -défilement          // une app à la fois : le coin multimédia reste fixe
        let s = NSRect(x: x0, y: 0, width: largeurTête, height: h)
        let c = NSRect(x: x0, y: hauteur - hauteurChoix, width: largeurTête, height: hauteurChoix)
        poignéeMédia.frame = NSRect(x: s.maxX - 9, y: 0, width: 9, height: h)
        let courant = liste.first { $0.id == choisi }
        lecteur.isHidden = courant?.genre != "spotify" || replié
        // La page de l'élément choisi est créée à sa première apparition, tiroir ouvert.
        if let m = courant, m.genre != "spotify", pagesWeb[m.id] == nil, ouvert, let adresse = URL(string: m.adresse) {
            // YouTube : Peinard, quand Side a été compilé avec lui. Les autres sites : le lecteur web.
            if m.genre == "youtube", let tuile = TuilePeinard.creer() {
                bandeVue.addSubview(tuile, positioned: .below, relativeTo: choixMédia)
                pagesWeb[m.id] = tuile
            } else {
                let vue = LecteurYouTubeBas(accueil: adresse, youtube: m.genre == "youtube")
                bandeVue.addSubview(vue, positioned: .below, relativeTo: choixMédia)
                pagesWeb[m.id] = vue
                vue.réveiller()
            }
        }
        for (id, vue) in pagesWeb { vue.isHidden = id != choisi || replié }
        if animé {
            lecteur.animator().frame = s; choixMédia.animator().frame = c
            pagesWeb.values.forEach { $0.animator().frame = s }
        } else {
            lecteur.frame = s; choixMédia.frame = c
            pagesWeb.values.forEach { $0.frame = s }
        }
    }

    /// La liste du coin multimédia a changé dans les réglages.
    func médiasChangés() {
        if ouvert, panneau != nil { recharger(versLaFin: false) } else { placerLecteurs(hauteur: bandeVue.bounds.height, animé: false) }
    }

    /// La case « + », juste après la dernière tuile.
    func placerPlus(animé: Bool) {
        guard let p = panneau else { return }
        let b = bande(p.frame)
        if uneApp, agrandi {
            // Agrandi : la colonne s'en va, il ne reste que le bouton « réduire », au milieu du bord droit, au-dessus de l'application.
            icônesColonne.forEach { $0.isHidden = true }
            repèreColonne.isHidden = true
            barreColonne.isHidden = true
            plus.isHidden = true
            roue.isHidden = true
            let cadreBouton = NSRect(x: b.width - largeurPlus - 12, y: ((b.height - largeurPlus) / 2).rounded(), width: largeurPlus + 8, height: largeurPlus)
            barreAgrandir.isHidden = false
            barreAgrandir.frame = cadreBouton
            barreAgrandir.subviews.first?.frame = barreAgrandir.bounds
            boutonAgrandir.isHidden = false
            boutonAgrandir.frame = cadreBouton
            if let fenêtre = bandeVue.window {
                PanneauBas.pastilleÉcran = Ecrans.versAX(fenêtre.convertToScreen(bandeVue.convert(cadreBouton, to: nil))).insetBy(dx: -6, dy: -6)
            }
            return
        }
        plus.isHidden = false
        roue.isHidden = false
        if uneApp {
            // La colonne de droite, réunie dans une seule barre flottante comme le Dock de la grille : le « + » en haut,
            // une icône par application, la roue dentée en bas. Elle est centrée en hauteur et ne prend que sa place.
            let x = b.width - largeurColonne + (largeurColonne - largeurPlus) / 2
            let n = CGFloat(emprunts.count)
            // (La place de la petite barre « agrandir », posée au-dessus, est comptée : 44 points et un écart.)
            let pasIcône: CGFloat = min(44, max(34, (b.height - 3 * largeurPlus - 60) / max(n, 1)))
            let hauteurBarre = 2 * largeurPlus + n * pasIcône + 24
            let écartAgrandir: CGFloat = 10
            let bas0 = ((b.height - hauteurBarre - largeurPlus - écartAgrandir) / 2).rounded()
            let r = NSRect(x: x, y: bas0 + hauteurBarre - largeurPlus - 4, width: largeurPlus, height: largeurPlus)
            let bas = NSRect(x: x, y: bas0 + 4, width: largeurPlus, height: largeurPlus)
            if animé { plus.animator().frame = r; roue.animator().frame = bas } else { plus.frame = r; roue.frame = bas }
            // Le bouton « agrandir » : seul dans sa petite barre, au-dessus de la colonne (20/11/2026).
            let cadreAgrandir = NSRect(x: x - 4, y: bas0 + hauteurBarre + écartAgrandir, width: largeurPlus + 8, height: largeurPlus)
            barreAgrandir.isHidden = false
            barreAgrandir.frame = cadreAgrandir
            barreAgrandir.subviews.first?.frame = barreAgrandir.bounds
            boutonAgrandir.isHidden = false
            boutonAgrandir.frame = cadreAgrandir
            let fond = NSRect(x: x - 4, y: bas0, width: largeurPlus + 8, height: hauteurBarre)
            barreColonne.isHidden = false
            barreColonne.frame = fond
            barreColonne.subviews.first?.frame = barreColonne.bounds      // la teinte couvre toute la barre
            placerColonne(x: x, haut: r.minY - 8, pas: pasIcône, animé: animé)
            return
        }
        icônesColonne.forEach { $0.isHidden = true }
        boutonAgrandir.isHidden = true
        barreAgrandir.isHidden = true
        repèreColonne.isHidden = true
        barreColonne.isHidden = true
        let fin = (zones(p.frame).last?.maxX ?? (b.minX - défilement + largeurTête)) + marge
        let r = NSRect(x: fin - b.minX, y: (b.height - largeurPlus) / 2, width: largeurPlus, height: largeurPlus)
        // La roue dentée : même colonne et même taille que la case « + », posée en bas, au niveau du bas des tuiles.
        let bas = NSRect(x: r.minX, y: 0, width: largeurPlus, height: largeurPlus)
        if animé { plus.animator().frame = r; roue.animator().frame = bas } else { plus.frame = r; roue.frame = bas }
    }

    /// Les icônes des applications du tiroir, dans la colonne de droite. Un clic amène l'application.
    func placerColonne(x: CGFloat, haut: CGFloat, pas: CGFloat, animé: Bool) {
        let chemins = emprunts.map(\.chemin)
        if chemins != cheminsColonne {
            cheminsColonne = chemins
            icônesColonne.forEach { $0.removeFromSuperview() }
            icônesColonne = emprunts.indices.map { i in
                let v = IcôneBarreBas(frame: .zero)
                v.imageScaling = .scaleProportionallyUpOrDown
                v.image = NSWorkspace.shared.icon(forFile: emprunts[i].chemin)
                v.toolTip = emprunts[i].nom
                v.auClic = { [weak self] in self?.montrerTuile(i) }
                v.auGlisser = { [weak self] dy in self?.glisserIcône(i, dy) }
                v.auLâcher = { [weak self] in self?.lâcherIcône() }
                v.auMenu = { [weak self] ev in self?.menuIcône(i, ev, v) }
                bandeVue.addSubview(v)
                return v
            }
        }
        if repèreColonne.superview == nil {
            repèreColonne.wantsLayer = true
            repèreColonne.layer?.cornerRadius = Rayon.encadre
            repèreColonne.layer?.cornerCurve = .continuous
            bandeVue.addSubview(repèreColonne, positioned: .above, relativeTo: barreColonne)
        }
        // La mise en avant suit le mode clair ou sombre, comme la sélection d'un élément du Dock.
        var teinte = NSColor.clear.cgColor
        bandeVue.effectiveAppearance.performAsCurrentDrawingAppearance { teinte = NSColor.labelColor.withAlphaComponent(0.14).cgColor }
        repèreColonne.layer?.backgroundColor = teinte
        let côté: CGFloat = 34
        let courant = rangCourant
        pasIcônes = pas; hautIcônes = haut; xIcônes = x
        guard glisseIcône == nil else { return }          // pendant un glisser, c'est lui qui place les icônes
        for (i, v) in icônesColonne.enumerated() {
            v.isHidden = false
            let y = haut - CGFloat(i + 1) * pas + (pas - côté) / 2
            let r = NSRect(x: x + (largeurPlus - côté) / 2, y: y, width: côté, height: côté)
            if animé { v.animator().frame = r } else { v.frame = r }
            v.alphaValue = 1                       // toutes nettes : seule la mise en avant distingue l'application affichée
            if i == courant {
                let f = r.insetBy(dx: -4, dy: -4)
                if animé { repèreColonne.animator().frame = f } else { repèreColonne.frame = f }
            }
        }
        repèreColonne.isHidden = emprunts.isEmpty
    }
}
