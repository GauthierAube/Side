// Ouvrir et fermer la carte, et la faire suivre les quatre doigts.
// Partie de AppDelegate (Side.swift), rangée à part le 15/11/2026 sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

extension AppDelegate {
    // MARK: Affichage
    /// macOS réserve la place du Dock même sur un bureau en plein écran, où il est pourtant masqué.
    /// On reconnaît le plein écran (ou le Split View) à une fenêtre qui occupe toute la hauteur de
    /// l'écran, jusqu'à son bord bas : sur un bureau normal, aucune fenêtre ne passe sous le Dock ainsi.
    func dockMasque(sur e: NSScreen) -> Bool {
        guard let numero = e.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let liste = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let ecran = CGDisplayBounds(numero)
        let moi = ProcessInfo.processInfo.processIdentifier
        for fenetre in liste {
            guard (fenetre[kCGWindowLayer as String] as? Int) == 0,
                  (fenetre[kCGWindowOwnerPID as String] as? pid_t) != moi,
                  let dico = fenetre[kCGWindowBounds as String] as? NSDictionary,
                  let cadre = CGRect(dictionaryRepresentation: dico), ecran.intersects(cadre) else { continue }
            if cadre.maxY >= ecran.maxY - 1 && cadre.height >= ecran.height - 60 && cadre.width >= ecran.width * 0.2 {
                return true
            }
        }
        return false
    }

    /// La carte flotte à quelques points des bords de l'écran, sous la barre des menus et l'encoche.
    /// La fenêtre, elle, va jusqu'au bord d'où vient la carte, pour que celle-ci glisse depuis ce bord.
    func placer(sur e: NSScreen, anime: Bool) {
        let f = e.frame, m = Reglages.margeCarte, s = Reglages.debord
        let plafond = min(f.maxY - e.safeAreaInsets.top, e.visibleFrame.maxY)
        // La partie « Finder » garde sa largeur ; chaque colonne épinglée élargit la carte.
        // La carte a la même forme quel que soit le côté d'où elle arrive : seule sa position change.
        let dispo = f.width - 2 * m
        if store.largeurMax != dispo { store.largeurMax = dispo }
        let lw = Disposition.carte(store.columns.count, dispo)
        let h = (f.height * config.tailleHauteur).rounded()
        // Place du mini-Dock, de chaque côté de la carte (un seul côté à la fois).
        let d = Disposition.dock, p = config.apps ? config.dockPosition : ""
        let dG = p == "gauche" ? d : 0, dD = p == "droite" ? d : 0
        let dH = p == "haut" ? d : 0, dB = p == "bas" ? d : 0
        // Quand le Dock de macOS est visible, la carte se pose juste au-dessus (ou à côté) de lui.
        // En plein écran le Dock est masqué : la carte va alors jusqu'au bord de l'écran, comme avant.
        let v = dockMasque(sur: e) ? f : e.visibleFrame
        let x: CGFloat, y: CGFloat   // coin bas-gauche de la carte elle-même
        switch config.bord {
        case .plein:   // même taille que d'habitude, au milieu de l'écran (mini-Dock compris)
            if let libre = positionLibre, f.insetBy(dx: -1, dy: -1).contains(libre) {
                // Là où tu l'as posée, sans jamais sortir de l'écran.
                x = max(v.minX + m + dG, min(libre.x, v.maxX - m - lw - dD))
                y = max(v.minY + m + dB, min(libre.y - h, plafond - m - h - dH))
            } else {
                x = f.minX + ((f.width - lw - dG - dD) / 2).rounded() + dG
                y = v.minY + ((plafond - v.minY - h - dH - dB) / 2).rounded() + dB
            }
        case .haut: x = f.minX + ((f.width - lw) / 2).rounded(); y = plafond - m - h - dH
        case .bas: x = f.minX + ((f.width - lw) / 2).rounded(); y = v.minY + m + dB
        case .gauche: x = v.minX + m + dG; y = v.minY + ((plafond - v.minY - h) / 2).rounded()
        case .droite: x = v.maxX - m - lw - dD; y = v.minY + ((plafond - v.minY - h) / 2).rounded()
        }
        // Les zones de dépôt ont leur propre fenêtre. On retient où la placer : à droite de la carte,
        // sinon à gauche, sinon par-dessus son coin haut-droit.
        let g = Reglages.carreDepot + 8
        // Carte venue du haut : les zones s'alignent sur le bas de la carte (et grandissent vers le haut).
        let yz = zonesVersHaut ? y : y + h
        if f.maxX - m - (x + lw + dD) >= g {
            ancreDepot = NSPoint(x: x + lw + dD + 8, y: yz)
        } else if (x - dG) - (f.minX + m) >= g {
            ancreDepot = NSPoint(x: x - dG - g, y: yz)
        } else {
            ancreDepot = NSPoint(x: f.maxX - m - g, y: zonesVersHaut ? yz + 56 : yz - 56)
        }
        if !store.depotDehors { store.depotDehors = true }
        cadreSeule = NSRect(x: x, y: y, width: lw, height: h)
        // ens = la carte et son mini-Dock
        let ens = NSRect(x: x - dG, y: y - dB, width: lw + dG + dD, height: h + dH + dB)
        // Carte en haut et mini-Dock dessous (ou l'inverse) : la liste du presse-papiers se déroule à l'opposé
        // de la carte, si l'écran a la place. La fenêtre s'allonge de ce côté pour la contenir.
        // S'il reste moins de place que la liste entière, elle raccourcit ; en dessous de 200 points, elle
        // repasse par-dessus la carte.
        let liste: CGFloat = 400 + 16   // hauteur maximale de la liste, et son écart avec le mini-Dock
        var pd: CGFloat = 0
        if config.historique {
            var place: CGFloat = 0
            if config.bord == .haut, p == "bas" { place = ens.minY - v.minY - m }
            if config.bord == .bas, p == "haut" { place = plafond - ens.maxY - m }
            if place >= 200 { pd = min(liste, place.rounded(.down)) }
        }
        if config.presseDehors != pd { config.presseDehors = pd }
        let fenetre: NSRect
        switch config.bord {
        case .haut: fenetre = NSRect(x: ens.minX, y: ens.minY - pd - s, width: ens.width, height: f.maxY - ens.minY + pd + s)
        case .bas: fenetre = NSRect(x: ens.minX, y: f.minY, width: ens.width, height: ens.maxY - f.minY + pd + s)
        case .gauche: fenetre = NSRect(x: f.minX, y: ens.minY, width: ens.maxX - f.minX + s, height: ens.height)
        case .droite: fenetre = NSRect(x: ens.minX - s, y: ens.minY, width: f.maxX - ens.minX + s, height: ens.height)
        case .plein: fenetre = ens   // pas de glissement : la fenêtre a la taille de la carte
        }
        if store.margeHaut != 0 { store.margeHaut = 0 }
        // La vue contient aussi la place gardée pour la liste : sous la carte si elle vient du haut.
        repos = NSPoint(x: ens.minX - fenetre.minX, y: ens.minY - fenetre.minY - (config.bord == .haut ? pd : 0))
        cadreCarte = ens
        panel.setFrame(fenetre, display: true)
        host.setFrameSize(NSSize(width: ens.width, height: ens.height + pd))
        if !anime { host.setFrameOrigin(repos) }
        panel.invalidateShadow()
        majDepot()
    }

    /// Vrai si le glisser en cours transporte un fichier ou une image (et pas du simple texte).
    func glisseContientFichier() -> Bool {
        let types = NSPasteboard(name: .drag).types ?? []
        return types.contains(.fileURL) || types.contains(.tiff) || types.contains(.png) || types.contains(.pdf)
            || types.contains(NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"))
    }

    /// Vrai si le glisser en cours transporte au moins un dossier, ou une entrée de la barre latérale.
    func glisseContientDossier() -> Bool {
        let pb = NSPasteboard(name: .drag)
        if pb.string(forType: .string)?.hasPrefix(Glissable.prefixe) == true { return true }
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.contains { Fichiers.item($0).isFolder }
    }

    /// Position libre : la carte suit la souris pendant qu'on tire son en-tête.
    func deplacerCarte() {
        guard config.bord == .plein, visible, let e = ecran else { return }
        let ici = NSEvent.mouseLocation
        if prise == nil { prise = (ici, panel.frame.origin, cadreCarte) }
        guard let prise else { return }
        // On retient la carte dans l'écran, sous la barre des menus.
        let m = Reglages.margeCarte, f = e.frame
        let plafond = min(f.maxY - e.safeAreaInsets.top, e.visibleFrame.maxY)
        let dx = max(f.minX + m - prise.carte.minX, min(ici.x - prise.souris.x, f.maxX - m - prise.carte.maxX))
        let dy = max(f.minY + m - prise.carte.minY, min(ici.y - prise.souris.y, plafond - m - prise.carte.maxY))
        panel.setFrameOrigin(NSPoint(x: prise.fenetre.x + dx, y: prise.fenetre.y + dy))
        cadreSeule = cadreSeule.offsetBy(dx: prise.carte.minX + dx - cadreCarte.minX, dy: prise.carte.minY + dy - cadreCarte.minY)
        cadreCarte = prise.carte.offsetBy(dx: dx, dy: dy)
    }

    /// Fin du déplacement : Side retient l'endroit (coin haut-gauche de la carte, hors mini-Dock).
    func finDeplacement() {
        guard prise != nil, let e = ecran else { return }
        prise = nil
        let d = Disposition.dock, p = config.apps ? config.dockPosition : ""
        let coin = NSPoint(x: cadreCarte.minX + (p == "gauche" ? d : 0), y: cadreCarte.maxY - (p == "haut" ? d : 0))
        positionLibre = coin
        UserDefaults.standard.set([Double(coin.x), Double(coin.y)], forKey: "cartePosition")
        placer(sur: e, anime: false)   // replace aussi les zones de dépôt à côté
    }

    /// Oublie l'endroit choisi : la carte revient au centre de l'écran.
    func recentrerCarte() {
        positionLibre = nil
        UserDefaults.standard.removeObject(forKey: "cartePosition")
        if visible, let e = ecran { placer(sur: e, anime: false) }
    }

    /// Carte entièrement cachée derrière son bord d'écran : point de départ du vrai glissement
    /// (raccourci, souris, et surtout quatre doigts, où elle suit le geste).
    var loin: NSPoint {
        let t = panel.frame.size, c = host.frame.size
        switch config.bord {
        case .haut: return NSPoint(x: repos.x, y: t.height)
        case .bas: return NSPoint(x: repos.x, y: -c.height)
        case .gauche: return NSPoint(x: -c.width, y: repos.y)
        case .droite: return NSPoint(x: t.width, y: repos.y)
        case .plein: return repos
        }
    }

    // MARK: Suivre les quatre doigts
    var captureVisible: Bool { ProcessInfo.processInfo.systemUptime < captureJusqua }
    /// Durée et courbe pour finir un trajet en partant à la vitesse donnée (fraction du trajet par seconde),
    /// puis en ralentissant jusqu'à l'arrêt. La pente de départ de la courbe = la vitesse des doigts.
    static func elan(reste: CGFloat, vitesse: CGFloat) -> (duree: TimeInterval, courbe: CAMediaTimingFunction) {
        let v = max(0, vitesse)
        guard reste > 0.001 else { return (0.15, CAMediaTimingFunction(name: .easeOut)) }
        // Assez de temps pour ralentir en douceur, sans traîner : la durée suit la vitesse.
        let duree = v > 0.01 ? min(0.4, max(0.18, Double(2.2 * reste / v))) : 0.3
        let pente = v * CGFloat(duree) / reste        // vitesse de départ, rapportée à la courbe
        let x1: CGFloat = 0.3
        let y1 = min(1, pente * x1)
        return (duree, CAMediaTimingFunction(controlPoints: Float(x1), Float(y1), 0.35, 1))
    }

    /// Quatre doigts commencent à glisser : pour ouvrir, la carte arrive cachée, prête à suivre ;
    /// pour fermer, elle quitte sa place avec eux.
    func commencerSuivi(fermeture: Bool = false) {
        if fermeture {
            guard visible else { return }
            journal("déclencheur : quatre doigts (suivi de fermeture)")
            suiviDoigts = true
            // Cadenas ouvert : la zone de dépôt part avec la carte, au même rythme que les doigts.
            if let zone = depotPanel, zone.isVisible, !config.depotReste, !store.glisse {
                zoneSuivie = zone.frame
                animationDepot = true
            }
            return
        }
        guard !visible, let e = ecranSous(NSEvent.mouseLocation) else { return }
        journal("déclencheur : quatre doigts (suivi)")
        epingle = true
        show(sur: e, suivi: true)
        suiviDoigts = true
    }

    /// p : 0 = cachée, 1 = à sa place. Au-delà, elle résiste, comme un élastique.
    func suivreDoigts(_ p: CGFloat) {
        guard suiviDoigts, visible else { return }
        let q = p <= 1 ? max(0, p) : 1 + min(0.5, p - 1) * 0.12
        qSuivi = q
        let a = loin, b = repos
        if config.bord == .plein {
            panel.alphaValue = min(1, q)
        } else {
            host.setFrameOrigin(NSPoint(x: a.x + (b.x - a.x) * q, y: a.y + (b.y - a.y) * q))
            panel.alphaValue = min(1, q * 3)
        }
        // La zone de dépôt suit, décalée exactement comme la carte, avec la même transparence.
        if let r = zoneSuivie, let zone = depotPanel {
            zone.setFrameOrigin(NSPoint(x: r.minX + (a.x - b.x) * (1 - q), y: r.minY + (a.y - b.y) * (1 - q)))
            zone.alphaValue = panel.alphaValue
        }
        let maintenant = ProcessInfo.processInfo.systemUptime
        if maintenant - ombreSuivi > 0.05 { ombreSuivi = maintenant; panel.invalidateShadow() }
    }

    /// Doigts levés : la carte finit de s'ouvrir (ou revient à sa place), sinon elle repart derrière le bord.
    /// elan : vitesse de la carte au moment du lâcher (en « carte entière par seconde », sens d'ouverture).
    /// La suite du mouvement part exactement à cette vitesse, puis ralentit : pas d'à-coup.
    func lacherDoigts(ouvrir: Bool, elan: CGFloat = 0) {
        guard suiviDoigts else { return }
        suiviDoigts = false
        guard visible else { return }
        let reste = ouvrir ? abs(1 - qSuivi) : qSuivi          // chemin restant, en fraction du trajet
        let vers = ouvrir ? elan * (qSuivi <= 1 ? 1 : -1) : -elan   // vitesse dans le sens où elle va finir
        let suite = AppDelegate.elan(reste: reste, vitesse: vers)
        let zoneArrivee = zoneSuivie
        zoneSuivie = nil
        guard ouvrir else { hide(suite: suite); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = suite.duree
            ctx.timingFunction = suite.courbe
            host.animator().setFrameOrigin(repos)
            panel.animator().alphaValue = 1
            if let r = zoneArrivee, let zone = depotPanel {
                zone.animator().setFrame(r, display: true)
                zone.animator().alphaValue = 1
            }
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.invalidateShadow()
            if zoneArrivee != nil {
                self.animationDepot = false
                self.depotPanel?.invalidateShadow()
                self.majDepot()
            }
        })
    }

    var duree: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
    }

    /// La fenêtre des zones de dépôt. Indépendante de la carte : elle reste à l'écran, sur tous les
    /// bureaux, tant qu'une zone contient quelque chose — même quand Side est fermé.
    func creerDepot() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Reglages.carreDepot, height: Reglages.hauteurDepot),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.animationBehavior = .none
        // Contenu : la poignée en haut, les zones en dessous.
        let conteneur = NSView(frame: p.contentView!.bounds)
        let zones = NSHostingView(rootView: ZonesFlottantes(store: store))
        zones.frame = conteneur.bounds          // toute la fenêtre : l'ancienne poignée n'existe plus
        zones.autoresizingMask = [.width, .height]
        let poignee = PoigneeDepot(frame: NSRect(x: 0, y: conteneur.bounds.height - PoigneeDepot.hauteur,
                                                 width: conteneur.bounds.width, height: PoigneeDepot.hauteur))
        poignee.autoresizingMask = [.width, .minYMargin]
        conteneur.addSubview(zones)
        _ = poignee   // plus affichée : la zone se déplace en l'attrapant par son fond
        p.contentView = conteneur
        depotPanel = p
        if let xy = UserDefaults.standard.array(forKey: "depotPosition2") as? [Double], xy.count == 2 {
            ancrePerso = NSPoint(x: xy[0], y: xy[1])
        }
        // Quand tu la déplaces, Side retient l'endroit (coin haut-gauche) et ne la replace plus tout seul.
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            guard let self, !self.placementAuto, !self.animationDepot else { return }
            let coin = NSPoint(x: p.frame.minX, y: self.zonesVersHaut ? p.frame.minY : p.frame.maxY)
            self.ancrePerso = coin; self.journal("zone déplacée, position retenue : \(coin)")
            UserDefaults.standard.set([Double(coin.x), Double(coin.y)], forKey: "depotPosition2")
        }
        // Mise à jour dès que quelque chose change : glisser en cours, zone remplie ou vidée, zone ajoutée.
        suiviDepot = [
            config.$depotReste.sink { [weak self] _ in DispatchQueue.main.async { self?.majDepot() } },
            store.$glisse.sink { [weak self] _ in DispatchQueue.main.async { self?.majDepot() } },
            store.$depotRempli.sink { [weak self] _ in DispatchQueue.main.async { self?.majDepot() } },
            store.$etageres.sink { [weak self] _ in DispatchQueue.main.async { self?.majDepot() } },
            store.$depotDeplie.sink { [weak self] _ in DispatchQueue.main.async { self?.majDepot() } },
        ]
    }

    /// Affiche, place ou cache la fenêtre des zones de dépôt.
    func majDepot() {
        guard let depotPanel else { return }
        // Hors glisser, une zone vide en plus ne sert à rien : elle est retirée (il en reste toujours une).
        if !store.glisse, store.etageres.count > 1, store.etageres.contains(where: { $0.items.isEmpty }) {
            store.nettoyerZones()
            return            // nettoyerZones change la liste des zones, ce qui rappelle majDepot
        }
        // Visibles : pendant un glisser, ou si une zone est remplie — et, cadenas ouvert, seulement tant que Side est ouvert.
        let remplies = store.etageres.filter { !$0.items.isEmpty }.count
        let visibles = store.glisse ? store.etageres.count : ((visible || config.depotReste || captureVisible) ? remplies : 0)
        guard visibles > 0 else {
            // On laisse l'animation de disparition se terminer avant de retirer la fenêtre.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                let encore = self.store.glisse
                    || ((self.visible || self.config.depotReste || self.captureVisible) && self.store.etageres.contains { !$0.items.isEmpty })
                if !encore {
                    depotPanel.orderOut(nil)
                    // Vide et disparue : la prochaine fois, elle revient à sa place, à droite de la carte.
                    if !self.store.etageres.contains(where: { !$0.items.isEmpty }) {
                        self.ancrePerso = nil
                        UserDefaults.standard.removeObject(forKey: "depotPosition2")
                    }
                }
            }
            return
        }
        // Une zone dépliée (la grille) est plus large et plus haute que les autres.
        let deplie = store.depotDeplie.flatMap { i in store.etageres.indices.contains(i) && !store.etageres[i].items.isEmpty ? i : nil }
        // Empilées, les zones ne dépassent jamais la hauteur du Finder de Side : elles rapetissent ensemble s'il le faut.
        let n = CGFloat(store.etageres.count)
        let place = cadreSeule.height > 100 ? cadreSeule.height : n * (Reglages.hauteurDepot + 8)
        let e = min(1, max(0.5, (place - 8 * (n - 1)) / (n * Reglages.hauteurDepot)))
        if abs(store.echelleDepot - e) > 0.001 { store.echelleDepot = e }
        let largeur = deplie != nil ? DepotFlottant.depliee.width : (Reglages.carreDepot * e).rounded(.up)
        let hauteur = (n * Reglages.hauteurDepot * e + 8 * (n - 1)).rounded(.up)
            + (deplie != nil ? DepotFlottant.depliee.height - Reglages.hauteurDepot * e : 0)
        // À l'endroit où tu l'as posée, sinon à côté de la carte ; toujours dans l'écran.
        var coin = ancrePerso ?? ancreDepot
        if let ecran = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(coin) }) ?? NSScreen.main {
            let unique = min(hauteur, ecran.frame.height - 8)
            coin.x = min(max(coin.x, ecran.frame.minX + 4), ecran.frame.maxX - largeur - 4)
            coin.y = zonesVersHaut
                ? min(max(coin.y, ecran.frame.minY + 4), ecran.frame.maxY - unique - 4)
                : min(max(coin.y, ecran.frame.minY + unique + 4), ecran.frame.maxY - 4)
        }
        let cadre = NSRect(x: coin.x, y: zonesVersHaut ? coin.y : coin.y - hauteur, width: largeur, height: hauteur)
        if depotPanel.frame != cadre {
            placementAuto = true
            depotPanel.setFrame(cadre, display: true)
            DispatchQueue.main.async { self.placementAuto = false }
        }
        // Filet de sécurité : une zone affichée n'est jamais laissée transparente (hors animation d'arrivée).
        if !animationDepot && depotPanel.alphaValue < 1 { depotPanel.alphaValue = 1 }
        depotPanel.orderFrontRegardless()
        journal("zones affichées à \(cadre) | transparence=\(depotPanel.alphaValue) animation=\(animationDepot) ancrePerso=\(String(describing: ancrePerso)) visible=\(depotPanel.isVisible)")
        depotPanel.invalidateShadow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { depotPanel.invalidateShadow() }
    }

    func deplacerDepot() {
        guard let zone = depotPanel else { return }
        let ici = NSEvent.mouseLocation
        if priseDepot == nil { priseDepot = (ici, zone.frame.origin) }
        guard let prise = priseDepot else { return }
        zone.setFrameOrigin(NSPoint(x: prise.origine.x + ici.x - prise.souris.x, y: prise.origine.y + ici.y - prise.souris.y))
    }
    func finDeplacementDepot() {
        priseDepot = nil
        majDepot()   // la garde dans l'écran
    }

    /// Oublie l'endroit choisi à la main : la fenêtre des zones revient à côté de la carte.
    func replacerDepot() {
        ancrePerso = nil
        UserDefaults.standard.removeObject(forKey: "depotPosition2")
        majDepot()
    }

    /// Le voile de flou : une fenêtre de la taille de l'écran, juste sous la carte.
    /// Elle laisse passer les clics et les glisser-déposer : on peut toujours attraper un fichier dans l'app derrière.
    func montrerFlou(sur e: NSScreen) {
        guard config.flou else { cacherFlou(); return }
        if voile == nil {
            let v = NSPanel(contentRect: e.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            v.isOpaque = false
            v.backgroundColor = .clear
            v.hasShadow = false
            v.ignoresMouseEvents = true
            v.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
            v.animationBehavior = .none
            let effet = NSVisualEffectView(frame: NSRect(origin: .zero, size: e.frame.size))
            effet.material = .hudWindow   // un flou qui laisse deviner ce qu'il y a derrière
            effet.blendingMode = .behindWindow
            effet.state = .active
            effet.autoresizingMask = [.width, .height]
            // Par-dessus le flou, une teinte : sombre en mode sombre, claire en mode clair.
            let teinte = NSView(frame: effet.bounds)
            teinte.wantsLayer = true
            teinte.autoresizingMask = [.width, .height]
            effet.addSubview(teinte)
            teinteVoile = teinte
            v.contentView = effet
            voile = v
        }
        guard let voile else { return }
        let sombre = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        voile.appearance = NSAppearance(named: sombre ? .darkAqua : .aqua)
        teinteVoile?.layer?.backgroundColor = (sombre ? NSColor.black : NSColor.white).withAlphaComponent(0.16).cgColor
        voile.collectionBehavior = panel.collectionBehavior
        voile.setFrame(e.frame, display: true)
        if !voile.isVisible { voile.alphaValue = 0 }
        voile.orderFrontRegardless()
        panel.orderFrontRegardless()   // la carte reste au-dessus du voile
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            voile.animator().alphaValue = CGFloat(config.flouForce)
        }
    }

    func cacherFlou(immediat: Bool = false) {
        guard let voile, voile.isVisible else { return }
        if immediat { voile.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            voile.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.visible else { return }
            voile.orderOut(nil)
        })
    }

    /// Avec l'argument --journal, note dans la sortie d'erreur chaque ouverture et fermeture (pour diagnostiquer).
    /// La forme de la fenêtre vient de changer (liste du presse-papiers ouverte ou refermée hors de la carte) :
    /// macOS recalcule son ombre, tout de suite puis une fois l'animation finie.
    func rafraichirOmbre() {
        guard config.presseDehors > 0 else { return }
        for delai in [0.02, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delai) { [weak self] in self?.panel.invalidateShadow() }
        }
    }

    func noter(_ texte: String) { journal(texte) }
    func journal(_ texte: String) {
        guard CommandLine.arguments.contains("--journal") else { return }
        fputs(String(format: "%.1f ", ProcessInfo.processInfo.systemUptime - lancement) + texte + "\n", stderr)
    }

    func show(sur e: NSScreen, suivi: Bool = false) {
        guard Partie.finder.active else { journal("Finder coupé dans les réglages : pas d'ouverture"); return }
        // Pendant une capture d'écran, Side ne s'ouvre par aucun geste : on doit pouvoir viser un coin sans rien déclencher.
        if !visible, CaptureEcran.enCours { journal("ouverture ignorée : capture d'écran en cours"); return }
        journal("ouverture (déjà visible : \(visible))")
        ecran = e
        debutDehors = nil
        store.reloadAll()
        if visible { placer(sur: e, anime: false); return }
        visible = true
        captureJusqua = 0   // Side ouvert : la zone suit de nouveau la carte
        dernierBasculement = ProcessInfo.processInfo.systemUptime
        aQuitteCoin = false
        suivreBureaux(doitSuivre())
        Selection.shared.choisir(nil, nil)
        // Le cercle ne peut refermer qu'après un arrêt de la souris : la fin du geste d'ouverture ne compte pas.
        attendrePause = true
        derniereSecousse = ProcessInfo.processInfo.systemUptime
        trace = []
        // Toute première ouverture : la présentation de bienvenue.
        // (La présentation de bienvenue est maintenant une fenêtre à part, affichée au premier lancement : voir Presentation.swift.)
        placer(sur: e, anime: true)
        let reduit = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // La carte part de derrière le bord de l'écran et glisse jusqu'à sa place.
        // « Réduire les animations » : fondu seul.
        host.setFrameOrigin(reduit && !suivi ? repos : loin)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        montrerFlou(sur: e)
        // Cadenas ouvert : la zone de dépôt arrive avec la carte, dans le même mouvement.
        var arrivee: NSRect?
        if let zone = depotPanel, zone.isVisible, !config.depotReste, !store.glisse {
            animationDepot = true
            arrivee = zone.frame
            zone.alphaValue = 0
            // Elle part du même endroit que la carte, décalée d'autant : les deux arrivent ensemble.
            if !reduit || suivi { zone.setFrame(zone.frame.offsetBy(dx: host.frame.origin.x - repos.x, dy: host.frame.origin.y - repos.y), display: false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.zoneSuivie == nil else { return }   // les doigts la tiennent encore
                self.animationDepot = false
                zone.invalidateShadow()
            }
        }
        Doigts.carteOuverte = true
        if suivi {   // ce sont les doigts qui font avancer la carte, et la zone de dépôt avec elle
            zoneSuivie = arrivee
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            // Un vrai glissement depuis le bord : part avec élan, puis ralentit longuement pour se poser en douceur.
            ctx.duration = reduit ? 0.15 : 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            if let arrivee, let zone = depotPanel {
                zone.animator().setFrame(arrivee, display: true)
                zone.animator().alphaValue = 1
            }
            host.animator().setFrameOrigin(repos)
            panel.animator().alphaValue = 1
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.panel.invalidateShadow() }
    }

    func hide(immediat: Bool = false, suite: (duree: TimeInterval, courbe: CAMediaTimingFunction)? = nil) {
        guard visible else { return }
        if CommandLine.arguments.contains("--journal") {     // la pile d'appels coûte cher : seulement quand on la lit
            journal("fermeture <- " + Thread.callStackSymbols.dropFirst().prefix(3).map { $0.split(separator: " ").dropFirst(3).first.map(String.init) ?? "?" }.joined(separator: " <- "))
        }
        visible = false
        // Plus rien n'est sous la souris : sinon Espace ou un clic droit à la réouverture viseraient l'ancien élément.
        survole = nil; survoleColonne = nil; pileSurvolee = nil
        suiviDoigts = false
        Doigts.carteOuverte = false
        dernierBasculement = ProcessInfo.processInfo.systemUptime
        store.lanceurOuvert = false   // le panneau des applications part avec la carte
        epingle = false
        arme = false
        store.memoriser()
        cacherFlou(immediat: immediat)
        // Cadenas ouvert : la zone de dépôt part avec la carte, dans le même mouvement, comme une seule fenêtre.
        let zone = depotPanel
        let ensemble = !immediat && !config.depotReste && !store.glisse && zone?.isVisible == true
        if !ensemble { majDepot() }
        if immediat { panel.orderOut(nil); return }
        let reduit = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fondu = config.bord == .plein
        let glisse = !reduit && !fondu
        if ensemble { animationDepot = true }
        zoneSuivie = nil
        // La zone fait le même trajet que la carte, jusque derrière le bord : elles partent ensemble.
        let trajet = NSPoint(x: loin.x - host.frame.origin.x, y: loin.y - host.frame.origin.y)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduit ? 0.12 : 0.26   // la fermeture est plus brève que l'ouverture
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0.4)
            // Lâchée par les doigts en pleine course : elle continue sur sa lancée, sans s'arrêter.
            if let suite, glisse { ctx.duration = suite.duree; ctx.timingFunction = suite.courbe }
            if glisse { host.animator().setFrameOrigin(loin) }
            panel.animator().alphaValue = 0
            if ensemble, let zone {
                if glisse {
                    zone.animator().setFrame(zone.frame.offsetBy(dx: trajet.x, dy: trajet.y), display: true)
                }
                zone.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            guard let self else { return }
            if ensemble, let zone {
                if !self.visible { zone.orderOut(nil) }
                zone.alphaValue = 1
                self.animationDepot = false
                self.majDepot()   // la remet à sa place (et l'affiche si la carte a été rouverte entre-temps)
            }
            guard !self.visible else { return }
            self.panel.orderOut(nil)
        })
    }

    /// Normalement la carte appartient à son bureau et part avec lui. Tant que Commande est enfoncée,
    /// elle est au contraire présente sur tous les bureaux : elle reste donc en place pendant le
    /// changement, sans disparaître puis réapparaître.
    /// La carte doit-elle suivre au changement de bureau ? Dépend du réglage et de la touche Commande.
    func doitSuivre(_ commande: Bool = NSEvent.modifierFlags.contains(.command)) -> Bool {
        switch config.suivi {
        case "toujours": return true
        case "jamais": return false
        default: return commande
        }
    }

    func suivreBureaux(_ oui: Bool) {
        suitBureaux = oui
        panel.collectionBehavior = oui
            ? [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            : [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        voile?.collectionBehavior = panel.collectionBehavior
    }
}
