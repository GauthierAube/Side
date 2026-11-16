// Les boutons rouge, jaune et vert des fenêtres du tiroir.
// Partie de PanneauBas (PanneauBas.swift), rangée à part le 15/11/2026 sans changement.

import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

extension PanneauBas {
    // MARK: Boutons rouge et vert des tuiles
    /// Plusieurs fois par seconde, tant que le panneau est ouvert :
    /// - une fenêtre fermée par son bouton rouge retire sa tuile ;
    /// - une fenêtre que vous élargissez pousse ses voisines (c'est un carrousel : rien ne se chevauche) ;
    /// - une fenêtre que vous déplacez change de rang dans la bande quand vous la lâchez ;
    /// - on repère les boutons jaune et vert, pour les intercepter.
    func veiller() {
        // Pendant une capture d'écran : Échap doit annuler la capture (pas refermer le tiroir), et aucune fenêtre ne doit
        // être ramenée devant. Le tiroir rend donc sa touche Échap et ne fait plus rien, jusqu'à la fin de la capture.
        let capture = ouvert && CaptureEcran.enCours
        if capture != enCapture {
            enCapture = capture
            if capture { TouchesBas.retirer(idEchap) }
            else if ouvert { TouchesBas.ajouter(idEchap, touche: UInt32(kVK_Escape), modifs: 0) { [weak self] in self?.fermer(rendreLaMain: true) } }
        }
        if capture { return }
        guard ouvert, enPlace, !défile, !enDirect, !suiviDoigts, !sansFenêtres, let p = panneau else {
            PanneauBas.boutonsVerts = []; PanneauBas.boutonsJaunes = []; enMain = nil; return
        }
        tic += 1
        let appuyé = NSEvent.pressedMouseButtons & 1 != 0
        if appuyé, !étaitAppuyé { pointAppui = NSEvent.mouseLocation }      // où le bouton a été enfoncé
        étaitAppuyé = appuyé
        if appuyé { dernierAppui = Date() }
        // C'est bien vous qui bougez la fenêtre (et pas le tiroir qu'on vient de redimensionner, dont la fenêtre se pose encore).
        let geste = (appuyé || Date().timeIntervalSince(dernierAppui) < 1) && Date().timeIntervalSince(finDirectÀ) > 1.5
        let b = bande(p.frame)
        var verts: [(nom: String, cadre: CGRect)] = [], jaunes: [(nom: String, cadre: CGRect)] = []
        // Pour le relais : la fenêtre de l'application affichée, si elle se redimensionne (pas une taille fixe) et qu'elle
        // est bien à sa place dans le tiroir.
        if uneApp, tic % 3 == 0 {
            var relayable: CGRect?
            // (Largeur fixe mais hauteur libre : le relais vaut pour le bord du haut seulement.)
            let maxi = entières(p.frame).first.flatMap { taillesMaxi[$0.0.bundle] }
            PanneauBas.relaisHauteurSeule = (maxi?.first ?? 100_000) < 50_000
            if let (e, zone) = entières(p.frame).first, (maxi?.last ?? 100_000) > 50_000, let f = fenetre(e), let c = AXBas.cadre(f),
               abs(c.minX - zone.minX) < 30, abs(c.maxY - zone.maxY) < 30 || abs(c.minY - zone.minY) < 30, Self.redimensionnable(f) {
                relayable = c
            }
            PanneauBas.fenêtreRelayable = relayable
        }
        for (e, zone) in entières(p.frame) where posées.contains(e.nom) {
            if let a = app(e), a.isHidden { continue }
            // Certaines applications quittent quand on ferme leur fenêtre (Réglages Système) : c'est aussi un bouton rouge.
            guard app(e) != nil, let f = fenetre(e) else {
                if sansRéponse { continue }       // application figée : sa tuile reste
                // Absente depuis plus d'une demi-seconde : la fenêtre a bien été fermée (et pas seulement en train de se recréer).
                absences[e.nom, default: 0] += 1
                // Sa fenêtre n'existe plus du tout pour macOS : c'est sûr, elle a été fermée. On n'attend pas davantage.
                let disparue = numéros[e.nom].map { n in
                    ((CGWindowListCopyWindowInfo([.optionIncludingWindow], n) as? [[String: Any]]) ?? []).isEmpty
                } ?? false
                if absences[e.nom, default: 0] >= (disparue ? 2 : 5), let i = emprunts.firstIndex(where: { $0.nom == e.nom }) {
                    journalBas("%@ fermée par son bouton rouge", e.nom)
                    if enMain == e.nom { enMain = nil }
                    retirer(i)
                    return
                }
                continue
            }
            absences[e.nom] = 0
            var numéro: CGWindowID = 0
            if _AXUIElementGetWindow(f, &numéro) == .success, numéro != 0 { numéros[e.nom] = numéro }
            guard let c = AXBas.cadre(f) else { continue }
            let retaillée = abs(c.width - zone.width) > 3
            // La hauteur d'une tuile est celle du panneau : étirée à la main, elle y revient au lâcher.
            // (Sauf pour une application qui refuse cette hauteur : on n'insiste pas.)
            let hauteurChangée = abs(c.height - zone.height) > 3 && !refusHauteur.contains(e.nom)
            let bougée = abs(c.minX - zone.minX) > 3 || abs(c.minY - zone.minY) > 3 || hauteurChangée
            if (retaillée || bougée), enMain == nil, geste { enMain = e.nom; enMainRetaillée = false }
            if enMain == e.nom {
                if retaillée {
                    // Sa nouvelle largeur est retenue tout de suite, et les voisines se poussent pendant que vous tirez.
                    enMainRetaillée = true
                    // Une app à la fois : le tiroir suit la fenêtre pendant qu'on la tire, la barre d'icônes est poussée.
                    if uneApp, appuyé, appuiSurUnBord(c) { suivreLaFenêtre(c); suiviFenêtre = true }
                    var d = disposition
                    d[e.nom] = [0, 0, Double(min(max(c.width, 200), b.width)), 0]
                    disposition = d
                }
                if appuyé {
                    if enMainRetaillée { pousser(sauf: e.nom) }
                    else if !uneApp, abs(c.midX - zone.midX) > 30 {
                        // Comme dans la grille de Square : pendant qu'on la déplace, la tuile prend sa nouvelle place
                        // et les autres se poussent tout de suite pour la lui laisser.
                        let avant = emprunts.map(\.nom)
                        changerDeRang(e, milieu: c.midX)
                        if emprunts.map(\.nom) != avant { pousser(sauf: e.nom) }
                    }
                } else {
                    // Lâchée : déplacée sans être élargie, elle prend le rang où vous l'avez posée. Puis tout se réaligne.
                    if !uneApp, !enMainRetaillée, abs(c.midX - zone.midX) > 30 { changerDeRang(e, milieu: c.midX) }
                    if uneApp, suiviFenêtre { suiviFenêtre = false; enMain = nil; recentrerAprèsLaFenêtre(); return }
                    enMain = nil
                    recaler()
                    return
                }
                continue
            }
            guard tic % 3 == 0 else { continue }
            var v: CFTypeRef?
            AXUIElementCopyAttributeValue(f, kAXFullScreenButtonAttribute as CFString, &v)
            if let v, CFGetTypeID(v) == AXUIElementGetTypeID(), let r = AXBas.cadre(v as! AXUIElement) {
                verts.append((e.nom, r.insetBy(dx: -2, dy: -2)))
            }
            var j: CFTypeRef?
            AXUIElementCopyAttributeValue(f, kAXMinimizeButtonAttribute as CFString, &j)
            if let j, CFGetTypeID(j) == AXUIElementGetTypeID(), let r = AXBas.cadre(j as! AXUIElement) {
                jaunes.append((e.nom, r.insetBy(dx: -2, dy: -2)))
            }
        }
        if enMain != nil, !emprunts.contains(where: { $0.nom == enMain }) { enMain = nil }
        if tic % 3 == 0, enMain == nil {
            PanneauBas.boutonsVerts = verts
            PanneauBas.boutonsJaunes = jaunes
        }
    }

    /// Pendant que vous élargissez une fenêtre : les autres tuiles visibles suivent, sans attendre que vous lâchiez.
    func pousser(sauf nom: String) {
        guard let p = panneau else { return }
        for (e, zone) in zip(emprunts, zones(p.frame)) where e.nom != nom && posées.contains(e.nom) {
            guard let f = fenetre(e), let c = AXBas.cadre(f), c.minX < Ecrans.bordGarage - 2,
                  abs(c.minX - zone.minX) > 1 else { continue }
            AXBas.placer(f, zone)
        }
    }

    /// La tuile lâchée ailleurs prend le rang qui correspond à l'endroit où elle a été posée.
    func changerDeRang(_ e: EmpruntBas, milieu: CGFloat) {
        guard let p = panneau, let depuis = emprunts.firstIndex(where: { $0.nom == e.nom }) else { return }
        let autres = zip(emprunts, zones(p.frame)).filter { $0.0.nom != e.nom }
        let vers = autres.filter { $0.1.midX < milieu }.count
        guard vers != depuis else { return }
        var liste = emprunts
        liste.remove(at: depuis)
        liste.insert(e, at: min(vers, liste.count))
        emprunts = liste
        journalBas("%@ passe au rang %d", e.nom, vers + 1)
    }

    /// Réaligne toute la bande : photos refaites, puis vraies fenêtres réinstallées à leur place.
    func recaler() {
        poserImages()
        installer(déjàArrivé: true)
    }

    /// Bouton « Voir la vidéo » du lecteur : la fenêtre de Spotify s'affiche en grand (c'est là que la vidéo se regarde).
    func montrerSpotifyEnGrand() {
        if let i = emprunts.firstIndex(where: { $0.bundle == "com.spotify.client" }) { sortirEnGrand(i); return }
        journalBas("Spotify ouvert en grand pour la vidéo")
        fermer(rendreLaMain: false)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Spotify.app"), configuration: config) { app, _ in
            guard let pid = app?.processIdentifier else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard let ecran = NSScreen.main, let principal = NSScreen.screens.first else { return }
                var v: CFTypeRef?
                AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &v)
                guard let f = (v as? [AXUIElement])?.first else { return }
                let z = ecran.visibleFrame
                AXBas.placer(f, CGRect(x: z.minX, y: principal.frame.height - z.maxY, width: z.width, height: z.height))
                AXBas.lever(f)
            }
        }
    }

    /// Bouton jaune : la tuile quitte le panneau pour de bon, mais sa fenêtre reste ouverte, rendue à son application.
    func retirerSansFermer(nom: String) {
        guard let i = emprunts.firstIndex(where: { $0.nom == nom }) else { return }
        journalBas("%@ retirée par son bouton jaune", nom)
        retirer(i)
    }

    /// Bouton jaune d'une tuile : le tiroir se referme, l'application y reste rangée.
    func fermerParLeJaune() {
        journalBas("bouton jaune : le tiroir se referme")
        fermer(rendreLaMain: true)
    }

    /// Bouton vert d'une tuile : l'application sort du tiroir, à sa taille, au milieu de l'écran (sans dépasser les trois quarts
    /// de l'écran). Sa photo glisse de sa place dans le tiroir jusqu'au centre pendant que le tiroir s'en va.
    /// Elle reste une application du tiroir : elle y retourne à sa prochaine ouverture.
    func sortirAuCentre(nom: String) {
        guard let i = emprunts.firstIndex(where: { $0.nom == nom }), let principal = NSScreen.screens.first,
              let ecran = panneau?.screen ?? NSScreen.main else { return }
        let e = emprunts[i]
        guard let f = fenetre(e), let c = AXBas.cadre(f) else { return }
        journalBas("%@ sort du tiroir au centre", nom)
        let image = photo(e, taille: c.size, fraîche: true)
        let v = ecran.visibleFrame
        let taille = Self.redimensionnable(f) ? CGSize(width: min(c.width, v.width * 0.75), height: min(c.height, v.height * 0.75)) : c.size
        let centre = CGRect(x: (v.midX - taille.width / 2).rounded(), y: (v.midY - taille.height / 2).rounded(),
                            width: taille.width, height: taille.height)                     // origine en bas à gauche
        let cible = CGRect(x: centre.minX, y: principal.frame.height - centre.maxY, width: taille.width, height: taille.height)
        fermer(rendreLaMain: false)
        TransitionFenetre.animer(image, de: TransitionFenetre.versÉcran(c), vers: centre, durée: 0.32,
                                 arrondiDépart: 12, arrondiArrivée: 12) { [weak self] in
            guard let self else { return }
            if let a = self.app(e), a.isHidden { a.unhide() }
            if let f = self.fenetre(e) { AXBas.placer(f, cible); AXBas.lever(f) }
            self.app(e)?.activate(options: [])
            TransitionFenetre.effacer(après: 0.12)
        }
    }

    /// Bouton vert : la fenêtre quitte le panneau et remplit l'écran
    /// (un faux plein écran, sans changement d'espace). Elle reviendra dans le panneau à sa prochaine ouverture.
    func sortirEnGrand(nom: String) {
        if let i = emprunts.firstIndex(where: { $0.nom == nom }) { sortirEnGrand(i) }
    }

    func sortirEnGrand(_ i: Int) {
        guard ouvert, emprunts.indices.contains(i), let ecran = NSScreen.main, let principal = NSScreen.screens.first else { return }
        let e = emprunts[i]
        journalBas("%@ sort du panneau en grand", e.nom)
        enGrand = e.nom
        libérée = e.nom
        fermer(rendreLaMain: false)
        libérée = nil
        let v = ecran.visibleFrame
        let plein = CGRect(x: v.minX, y: principal.frame.height - v.maxY, width: v.width, height: v.height)
        // L'application peut ne pas être ouverte encore : on l'ouvre, puis on agrandit sa fenêtre dès qu'elle existe.
        if fenetre(e) == nil {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: e.chemin), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
        func essayer(_ reste: Int) {
            if let f = fenetre(e) {
                AXBas.placer(f, plein)
                AXBas.lever(f)
                app(e)?.activate(options: [])
            } else if reste > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { essayer(reste - 1) }
            }
        }
        essayer(16)
    }
}
