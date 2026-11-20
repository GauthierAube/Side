// Le défilement horizontal de la bande de tuiles.
// Partie de PanneauBas (PanneauBas.swift), rangée à part le 15/11/2026 sans changement.

import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

extension PanneauBas {
    // MARK: Défilement horizontal de la bande
    /// Un défilement horizontal au-dessus du panneau fait glisser les tuiles au lieu d'aller à l'application sous le pointeur.
    func écouterDéfilement() {
        guard PanneauBas.filtre == nil else { return }
        let masque = CGEventMask(1 << CGEventType.scrollWheel.rawValue) | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue) | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        // Side n'est pas l'application de devant quand le tiroir est ouvert : macOS ne le laisse changer le pointeur
        // (la double flèche, sur le bord du tiroir) que si on le demande expressément.
        _ = CGSSetConnectionPropertyBas(CGSMainConnectionID(), CGSMainConnectionID(), "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        PanneauBas.filtre = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: masque, callback: { _, type, ev, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let f = PanneauBas.filtre { CGEvent.tapEnable(tap: f, enable: true) }
                return Unmanaged.passUnretained(ev)
            }
            // Pendant une capture d'écran, le tiroir ne touche à aucun clic ni au pointeur.
            if CaptureEcran.enCours, !PanneauBas.tirageHauteur { return Unmanaged.passUnretained(ev) }
            // Relais en cours : le geste continue sur le bord de la fenêtre de l'application, le tiroir suit.
            if let d = PanneauBas.relais {
                if type == .leftMouseDragged || type == .leftMouseUp {
                    ev.location = CGPoint(x: ev.location.x + d.x, y: ev.location.y + d.y)
                    if type == .leftMouseUp {
                        PanneauBas.relais = nil
                        DispatchQueue.main.async { PanneauBas.commun.finirRelais() }
                    } else if !PanneauBas.recalculPrévu {
                        PanneauBas.recalculPrévu = true
                        DispatchQueue.main.async {
                            PanneauBas.recalculPrévu = false
                            PanneauBas.commun.suivreRelais()
                        }
                    }
                    return Unmanaged.passUnretained(ev)
                }
            }
            // Le bord du tiroir qu'on tire pour régler sa hauteur. Les fenêtres des tuiles sont posées juste dessous, devant
            // le tiroir, et leur propre zone de redimensionnement déborde sur ce bord : sans ce filtre, c'est une fenêtre
            // qui attrapait le clic et se redimensionnait à la place du tiroir. Ici, le clic sur le bord est pour le tiroir.
            if PanneauBas.tirageHauteur {
                if type == .leftMouseDragged {
                    NSCursor.resizeUpDown.set()          // la double flèche reste pendant tout le geste
                    PanneauBas.écartEnAttente = PanneauBas.departHauteur - ev.location.y        // l'écran global compte vers le bas
                    if !PanneauBas.recalculPrévu {
                        PanneauBas.recalculPrévu = true
                        DispatchQueue.main.async {
                            PanneauBas.recalculPrévu = false
                            PanneauBas.commun.tirerHauteur(PanneauBas.écartEnAttente)
                        }
                    }
                    return nil
                }
                if type == .leftMouseUp {
                    PanneauBas.tirageHauteur = false
                    DispatchQueue.main.async { PanneauBas.commun.finirHauteur() }
                    return nil
                }
            }
            // Un côté du tiroir qu'on tire pour régler sa largeur (le tiroir reste centré).
            if PanneauBas.tirageLargeur != 0 {
                if type == .leftMouseDragged {
                    NSCursor.resizeLeftRight.set()
                    PanneauBas.écartEnAttente = (ev.location.x - PanneauBas.departLargeur) * CGFloat(-PanneauBas.tirageLargeur)
                    // Un seul recalcul à la fois : s'il y en a déjà un en route, il prendra la dernière position.
                    if !PanneauBas.recalculPrévu {
                        PanneauBas.recalculPrévu = true
                        DispatchQueue.main.async {
                            PanneauBas.recalculPrévu = false
                            PanneauBas.commun.tirerLargeur(PanneauBas.écartEnAttente)
                        }
                    }
                    return nil
                }
                if type == .leftMouseUp {
                    PanneauBas.tirageLargeur = 0
                    DispatchQueue.main.async { PanneauBas.commun.finirLargeur() }
                    return nil
                }
            }
            if type == .leftMouseDragged { return Unmanaged.passUnretained(ev) }
            if type == .mouseMoved || type == .leftMouseDown {
                // Le pointeur dans le trou : le tiroir laisse passer les clics à l'application (macOS ne le fait pas
                // de lui-même pour une zone transparente, quand le tiroir est passé devant elle).
                let dans = (PanneauBas.trouÉcran?.contains(ev.location) ?? false) && !(PanneauBas.pastilleÉcran?.contains(ev.location) ?? false)
                if dans != PanneauBas.pointeurDansLeTrou {
                    PanneauBas.pointeurDansLeTrou = dans
                    DispatchQueue.main.async { PanneauBas.commun.majClicsDansLeTrou(ev.location) }
                }
            }
            if type == .mouseMoved {
                // Au-dessus du bord : le pointeur devient une double flèche, pour montrer qu'on peut le tirer.
                let dessus = PanneauBas.estOuvertBrut && PanneauBas.surLeBord(ev.location)
                let côté = !dessus && PanneauBas.estOuvertBrut && PanneauBas.surUnCôté(ev.location) != 0
                if dessus { NSCursor.resizeUpDown.set() } else if côté { NSCursor.resizeLeftRight.set() }
                else if PanneauBas.curseurBord || PanneauBas.curseurCôté { NSCursor.arrow.set() }
                PanneauBas.curseurBord = dessus
                PanneauBas.curseurCôté = côté
                return Unmanaged.passUnretained(ev)
            }
            if type == .leftMouseDown, PanneauBas.estOuvertBrut {
                let p = ev.location
                // Double-clic sur le bord du tiroir : agrandir ou réduire, comme la barre de titre d'une fenêtre du Mac.
                // (Reconnu par Side lui-même : deux clics rapprochés au même endroit du bord. Le compteur de clics de macOS
                // n'arrive pas toujours jusqu'ici.)
                if ConfigTiroir.commun.uneApp, PanneauBas.surLeBord(p, mêmeFigé: true) {
                    let maintenant = ProcessInfo.processInfo.systemUptime
                    let d = PanneauBas.dernierClicBord
                    PanneauBas.dernierClicBord = (maintenant, p)
                    if maintenant - d.0 < NSEvent.doubleClickInterval, abs(p.x - d.1.x) < 8, abs(p.y - d.1.y) < 8 {
                        PanneauBas.dernierClicBord = (0, .zero)
                        // (Le petit redimensionnement commencé par le premier clic s'est terminé à son relâcher, juste avant.)
                        DispatchQueue.main.async { PanneauBas.commun.basculerAgrandi() }
                        return nil
                    }
                }
                let côté = PanneauBas.surUnCôté(p)
                // Une application redimensionnable est affichée : le clic sur le bord du tiroir est relayé sur le bord de sa fenêtre.
                if ConfigTiroir.commun.uneApp, let c = PanneauBas.fenêtreRelayable, côté != 0 || PanneauBas.surLeBord(p), c.width > 120, c.height > 120,
                   PanneauBas.surLeBord(p) || !PanneauBas.relaisHauteurSeule {
                    let cible: CGPoint
                    if PanneauBas.surLeBord(p) {
                        cible = CGPoint(x: min(max(p.x, c.minX + 50), c.maxX - 50), y: ConfigTiroir.enHaut ? c.maxY - 1 : c.minY + 1)
                        PanneauBas.relaisCôté = 0
                    } else {
                        cible = CGPoint(x: côté < 0 ? c.minX + 1 : c.maxX - 1, y: min(max(p.y, c.minY + 50), c.maxY - 50))
                        PanneauBas.relaisCôté = côté < 0 ? -1 : 1
                    }
                    PanneauBas.relais = CGPoint(x: cible.x - p.x, y: cible.y - p.y)
                    ev.location = cible
                    DispatchQueue.main.async { PanneauBas.commun.commencerRelais() }
                    return Unmanaged.passUnretained(ev)
                }
                if côté != 0, !PanneauBas.surLeBord(p) {
                    PanneauBas.tirageLargeur = côté
                    PanneauBas.departLargeur = p.x
                    DispatchQueue.main.async { PanneauBas.commun.commencerLargeur() }
                    return nil
                }
                if PanneauBas.surLeBord(p) {
                    PanneauBas.tirageHauteur = true
                    PanneauBas.departHauteur = p.y
                    DispatchQueue.main.async { PanneauBas.commun.commencerHauteur() }
                    return nil
                }
            }
            // Bouton vert d'une tuile : au lieu du plein écran d'Apple, la fenêtre sort du panneau en grand.
            if type == .leftMouseUp {
                guard PanneauBas.clicAvalé else { return Unmanaged.passUnretained(ev) }
                PanneauBas.clicAvalé = false
                return nil
            }
            if type == .leftMouseDown {
                guard PanneauBas.estOuvertBrut else { return Unmanaged.passUnretained(ev) }
                // Seulement si c'est bien la fenêtre de la tuile qui est sous le clic : une boîte de dialogue de l'application,
                // posée par-dessus, reçoit son clic normalement.
                let bouton = { (c: CGRect) in c.contains(ev.location) && PanneauBas.tiroirSous(ev.location, sansSide: true) }
                if let vert = PanneauBas.boutonsVerts.first(where: { bouton($0.cadre) }) {
                    PanneauBas.clicAvalé = true
                    // Le bouton vert sort l'application du tiroir, à sa taille, au centre de l'écran : ce sont de petites
                    // applications, pas faites pour remplir l'écran. Elle reviendra dans le tiroir à sa prochaine ouverture.
                    DispatchQueue.main.async { PanneauBas.commun.sortirAuCentre(nom: vert.nom) }
                    return nil
                }
                if PanneauBas.boutonsJaunes.contains(where: { bouton($0.cadre) }) {
                    PanneauBas.clicAvalé = true
                    // Le bouton jaune range, comme partout dans macOS : le tiroir se referme, l'application y reste.
                    DispatchQueue.main.async { PanneauBas.commun.fermerParLeJaune() }
                    return nil
                }
                return Unmanaged.passUnretained(ev)
            }
            guard PanneauBas.estOuvertBrut, PanneauBas.cadreBrut.contains(ev.location) else { return Unmanaged.passUnretained(ev) }
            // Une app à la fois : plus de bande à faire défiler de côté. Le glissement horizontal à deux doigts revient
            // à l'application (balayer un message dans Messages ou Mail, revenir en arrière dans Safari…).
            guard !ConfigTiroir.commun.uneApp else { return Unmanaged.passUnretained(ev) }
            let dx = ev.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            let dy = ev.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            guard dx != 0, abs(dx) > abs(dy) * 1.2 else { return Unmanaged.passUnretained(ev) }
            DispatchQueue.main.async { PanneauBas.commun.défiler(CGFloat(dx)) }
            return nil
        }, userInfo: nil)
        guard let filtre = PanneauBas.filtre else { return }   // sans l'autorisation Accessibilité, pas de défilement
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, filtre, 0), .commonModes)
        CGEvent.tapEnable(tap: filtre, enable: true)
    }

    /// Passe en mode défilement : toutes les tuiles deviennent des photos, les vraies fenêtres sont rangées.
    func commencerDéfilement() -> Bool {
        selecteur.fermer()
        guard ouvert, enPlace, !suiviDoigts, panneau != nil else { return false }
        if !défile {
            défile = true
            serie += 1
            if !sansFenêtres { retenir(); poserImages(); ranger(sauf: []) }
        }
        return true
    }

    func défiler(_ dx: CGFloat) {
        guard !uneApp else { return }                // une app à la fois : on change d'app au geste à quatre doigts ou par la colonne
        guard let p = panneau, commencerDéfilement() else { return }
        défilement = min(max(0, défilement - dx), arrêts(p.frame).maxi)
        déplacerImages(animé: false)
        finDéfilement?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.finirDéfilement() }
        finDéfilement = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: w)
    }

    /// Le défilement s'arrête : la bande se cale sur la tuile la plus proche, puis les vraies fenêtres reviennent.
    func finirDéfilement(vers cible: CGFloat? = nil) {
        guard let p = panneau, ouvert, défile else { return }
        let a = arrêts(p.frame)
        défilement = cible ?? ([0, a.maxi] + a.débuts).min(by: { abs($0 - défilement) < abs($1 - défilement) }) ?? 0
        défilement = min(max(0, défilement), a.maxi)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            déplacerImages(animé: true)
        }, completionHandler: { [weak self] in
            guard let self, self.ouvert, self.défile else { return }
            self.défile = false
            self.installer(déjàArrivé: true)
        })
    }

    /// Clic sur la photo d'une tuile à moitié cachée : elle vient en entier dans le panneau.
    func montrerTuile(_ i: Int) {
        guard let p = panneau, emprunts.indices.contains(i), commencerDéfilement() else { return }
        finDéfilement?.cancel()
        let a = arrêts(p.frame), b = bande(p.frame), r = zones(p.frame)[i]
        // Déjà à gauche de la bande : on l'amène au début. À droite : juste assez pour qu'elle tienne en entier.
        let cible = uneApp ? a.débuts[i] : (r.minX < b.minX ? a.débuts[i] : min(a.maxi, défilement + (r.maxX - b.maxX)))
        finirDéfilement(vers: cible)
    }
}
