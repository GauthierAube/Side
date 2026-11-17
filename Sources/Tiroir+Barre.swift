// La barre du tiroir : réorganiser au glisser, clic droit.
// Partie de PanneauBas (PanneauBas.swift), rangée à part le 15/11/2026 sans changement.

import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

extension PanneauBas {
    // MARK: La barre du tiroir : réorganiser au glisser, clic droit
    func cadreIcône(rang: Int) -> NSRect {
        let côté: CGFloat = 34
        return NSRect(x: xIcônes + (largeurPlus - côté) / 2, y: hautIcônes - CGFloat(rang + 1) * pasIcônes + (pasIcônes - côté) / 2,
                      width: côté, height: côté)
    }

    /// Met en avant l'icône de ce rang dans la colonne de droite, sans attendre que l'application soit en place :
    /// pendant le geste à quatre doigts, elle suit l'application qui passe au centre du mini carrousel.
    func marquerIcône(_ rang: Int) {
        guard uneApp, glisseIcône == nil, icônesColonne.indices.contains(rang), !repèreColonne.isHidden else { return }
        let f = cadreIcône(rang: rang).insetBy(dx: -4, dy: -4)
        guard repèreColonne.frame != f else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            repèreColonne.animator().frame = f
        }
    }

    /// L'icône suit la souris ; les autres s'écartent pour lui faire place, comme dans le Dock.
    func glisserIcône(_ i: Int, _ dy: CGFloat) {
        guard icônesColonne.indices.contains(i) else { return }
        let n = icônesColonne.count
        let vers = max(0, min(n - 1, i - Int((dy / pasIcônes).rounded())))
        let avant = glisseIcône?.vers
        glisseIcône = (i, vers)
        let v = icônesColonne[i]
        var r = cadreIcône(rang: i)
        r.origin.y += dy
        v.frame = r
        v.layer?.zPosition = 10
        repèreColonne.isHidden = true
        guard avant != vers else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            for (j, autre) in icônesColonne.enumerated() where j != i {
                // Le rang de cette icône une fois la glissée insérée à sa nouvelle place.
                var rang = j
                if i < vers, j > i, j <= vers { rang -= 1 }
                if i > vers, j >= vers, j < i { rang += 1 }
                autre.animator().frame = cadreIcône(rang: rang)
            }
        }
    }

    func lâcherIcône() {
        guard let g = glisseIcône else { return }
        glisseIcône = nil
        guard g.de != g.vers, emprunts.indices.contains(g.de) else { déplacerImages(animé: true); return }
        // L'application affichée reste affichée : seul l'ordre change.
        let affichée = emprunts.indices.contains(rangCourant) ? emprunts[rangCourant].nom : nil
        var liste = emprunts
        let e = liste.remove(at: g.de)
        liste.insert(e, at: g.vers)
        emprunts = liste
        journalBas("%@ passe au rang %d (barre)", e.nom, g.vers + 1)
        if let affichée, let i = emprunts.firstIndex(where: { $0.nom == affichée }), let p = panneau {
            défilement = arrêts(p.frame).débuts[i]
        }
        cheminsColonne = []                                 // les icônes se refont dans le nouvel ordre
        déplacerImages(animé: false)
    }

    /// Clic droit sur une icône de la barre : ses actions.
    func menuIcône(_ i: Int, _ ev: NSEvent, _ vue: NSView) {
        guard emprunts.indices.contains(i) else { return }
        let e = emprunts[i]
        journalBas("clic droit sur l'icône de %@", e.nom)
        let m = NSMenu()
        var actions: [ActionMenuBas] = []
        func ajouter(_ titre: String, _ symbole: String, _ f: @escaping () -> Void) {
            let a = ActionMenuBas(f)
            actions.append(a)
            let it = m.addItem(withTitle: titre, action: #selector(ActionMenuBas.agir), keyEquivalent: "")
            it.target = a
            it.representedObject = a
            it.image = NSImage(systemSymbolName: symbole, accessibilityDescription: nil)
        }
        if i != rangCourant { ajouter(String(localized: "Afficher"), "eye", { [weak self] in self?.montrerTuile(i) }) }
        if e.note == nil {
            ajouter(String(localized: "Passer en plein écran"), "arrow.up.left.and.arrow.down.right", { [weak self] in self?.passerEnPleinEcran(nom: e.nom) })
        }
        ajouter(String(localized: "Retirer du tiroir"), "minus.circle", { [weak self] in self?.retirerSansFermer(nom: e.nom) })
        m.addItem(.separator())
        ajouter(String(localized: "Quitter \(e.nom)"), "xmark.circle", { [weak self] in
            guard let self else { return }
            if let a = self.app(e) { if e.note != nil { self.retirerSansFermer(nom: e.nom) } else { a.terminate() } }
        })
        NSMenu.popUpContextMenu(m, with: ev, for: vue)
        _ = actions
    }

    func déplacerImages(animé: Bool) {
        guard let p = panneau else { return }
        let b = bande(p.frame)
        placerPlus(animé: animé)
        placerLecteurs(hauteur: b.height, animé: animé)
        for (e, r) in zip(emprunts, zones(p.frame)) {
            guard let v = images[e.nom] else { continue }
            v.isHidden = false
            if animé { v.animator().frame = dansLaBande(r, b) } else { v.frame = dansLaBande(r, b) }
        }
    }

    func disposerLeFond(_ fin: CGRect) {
        fond?.setFrameSize(fin.size)
        let b = bande(fin), g = panneauGlobal(fin)
        bandeVue.frame = NSRect(x: b.minX - g.minX, y: marge, width: b.width, height: b.height)
        placerLecteurs(hauteur: b.height, animé: false)
        placerPlus(animé: false)
        // La poignée de hauteur et les coins arrondis sont du côté qui regarde l'écran : en haut pour un tiroir du bas, et l'inverse.
        poignee.frame = NSRect(x: 0, y: enHaut ? 0 : fin.height - marge, width: fin.width, height: marge)
        fond?.layer?.maskedCorners = enHaut ? [.layerMinXMinYCorner, .layerMaxXMinYCorner] : [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        GestePanneauBas.enHaut = enHaut
        banniere.frame = NSRect(x: (fin.width - 640) / 2, y: marge + 14, width: 640, height: 46)
        // Première ouverture : un mot d'accueil, au milieu du tiroir, jusqu'à ce qu'on clique « Compris ».
        // (Le mot d'accueil du tiroir n'apparaît plus de lui-même : la présentation de Side montre le tiroir, depuis le 13/11/2026.)
        if bienvenue == nil, !UserDefaults.standard.bool(forKey: "tiroirBienvenueVue"), PanneauBas.motDAccueil, let fond {
            let b = BienvenueTiroirBas()
            b.auCompris = { [weak self] in
                UserDefaults.standard.set(true, forKey: "tiroirBienvenueVue")
                self?.bienvenue?.removeFromSuperview()
                self?.bienvenue = nil
                if let self, self.ouvert, self.enPlace { self.installer(déjàArrivé: true) }      // les vraies fenêtres arrivent
            }
            fond.addSubview(b)
            bienvenue = b
        }
        if let b = bienvenue {
            let t = b.fittingSize
            let l = max(t.width, 440)
            // À droite du lecteur multimédia quand il y a la place, sinon au milieu.
            let libre = fin.width - (marge + débutTuiles)
            let x = libre >= l + 40 ? marge + débutTuiles + (libre - l) / 2 : (fin.width - l) / 2
            b.frame = NSRect(x: x, y: (fin.height - t.height) / 2, width: l, height: t.height)
        }
        PanneauBas.cadreBrut = g
    }
}
