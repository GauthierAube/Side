import AppKit

/// Le Dock de macOS pendant la grille (24/11/2026) : s'il se masque automatiquement, la grille le fait sortir le temps
/// qu'elle est ouverte, puis le remasque. Le réglage de macOS est changé pour de vrai (comme Réglages Système › Bureau
/// et Dock), donc on note qu'il faut le remettre : si Side s'arrête grille ouverte, il le remet au lancement suivant.
///
/// Pour que rien ne saute :
/// - la grille réserve la place du Dock dès son ouverture (hauteur apprise la fois d'avant), sans attendre qu'il arrive ;
/// - tant que le Dock est sorti pour la grille (et un instant après), « agrandir » une fenêtre vise l'écran SANS le Dock,
///   comme d'habitude : l'application retrouvée garde toute la hauteur une fois le Dock reparti.
enum DockNatif {
    private static let cleARendre = "dockNatifAutoMasqueARendre"
    private static let cleHauteur = "dockNatifHauteur"
    /// Le Dock est sorti pour la grille.
    private(set) static var sorti = false
    /// Les zones utiles des écrans relevées Dock masqué, juste avant de le faire sortir.
    private static var zonesSansDock: [String: NSRect] = [:]
    private static var sansDockJusquÀ = Date.distantPast
    private static var sortiÀ = Date.distantPast
    /// Les fenêtres qui occupaient tout l'écran à l'ouverture de la grille. Certaines applications (Claude, Safari…) se
    /// rétrécissent d'elles-mêmes quand le Dock apparaît, et ne regrandissent pas toujours quand il repart : on leur rend
    /// leur taille une fois le Dock reparti.
    private static var pleines: [(pid: pid_t, wid: CGWindowID, cadre: CGRect)] = []

    /// Relu à chaque fois sur le disque (une lecture gardée en mémoire peut être en retard sur le vrai réglage).
    private static var seMasque: Bool { CoreDockGetAutoHideEnabled() }

    /// La hauteur du Dock sorti, apprise à chaque sortie (une estimation tirée de la taille des icônes la première fois).
    static var hauteur: CGFloat {
        let apprise = UserDefaults.standard.double(forKey: cleHauteur)
        if apprise > 10 { return apprise }
        let icones = UserDefaults(suiteName: "com.apple.dock")?.double(forKey: "tilesize") ?? 0
        return (icones > 10 ? icones : 48) + 18
    }

    /// La zone utile de l'écran comme si le Dock était masqué, tant que c'est la grille qui l'a fait sortir.
    static func zoneSansDock(_ e: NSScreen) -> NSRect? {
        guard sorti || Date() < sansDockJusquÀ else { return nil }
        return zonesSansDock[Ecrans.identifiant(e)]
    }

    /// Avant d'afficher la grille. `fini` est appelé sur le fil principal une fois le Dock sorti.
    static func sortir(fini: @escaping () -> Void) {
        // Un Dock que la grille d'avant n'a pas encore fini de remasquer compte comme masqué.
        let dette = UserDefaults.standard.bool(forKey: cleARendre)
        guard !sorti, seMasque || dette else { return }
        if !dette || zonesSansDock.isEmpty {
            zonesSansDock = Dictionary(NSScreen.screens.map { (Ecrans.identifiant($0), $0.visibleFrame) }, uniquingKeysWith: { a, _ in a })
            pleines = relever()
        }
        sorti = true
        sortiÀ = Date()
        UserDefaults.standard.set(true, forKey: cleARendre)
        regler(masque: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                apprendreHauteur()
                fini()
            }
        }
    }

    /// Dès que la grille s'efface (avant même la fin de son animation) : le Dock repart pendant qu'elle se referme.
    static func rentrer() {
        guard sorti else { return }
        sorti = false
        sansDockJusquÀ = Date().addingTimeInterval(4)        // le temps que macOS rende sa place à l'écran
        // Remasqué pendant qu'il est encore en train de sortir, le Dock reste parfois affiché, figé : on lui laisse finir.
        let attente = max(0, (sansAnimation ? 0.12 : 0.5) - Date().timeIntervalSince(sortiÀ))
        let remasquer = {
            guard !sorti else { return }
            CoreDockSetAutoHideEnabled(true)
            // Tout de suite, avant que l'application choisie ne s'affiche : les fenêtres que le Dock a fait rétrécir
            // (celles de derrière aussi) retrouvent tout l'écran. Sinon l'application arrivait tronquée, puis sautait.
            rendreLesTailles()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { verifier(tour: 0, vu: 0, coups: 0) }
        }
        if attente <= 0 { remasquer() } else { DispatchQueue.main.asyncAfter(deadline: .now() + attente, execute: remasquer) }
    }

    /// Après la grille, on regarde le Dock lui-même (sa position, par l'Accessibilité) toutes les 0,4 s : resté affiché
    /// alors que la souris n'est pas dessus, il est figé (24/11/2026) ; on le fait ressortir puis rentrer, ce qui le
    /// décoince. Une fois le Dock vraiment parti, les fenêtres rétrécies par leur application retrouvent tout l'écran.
    private static func verifier(tour: Int, vu: Int, coups: Int) {
        guard !sorti else { return }                          // la grille s'est rouverte entre-temps
        let suite = { (vu: Int, coups: Int, dans: Double) in
            DispatchQueue.main.asyncAfter(deadline: .now() + dans) { verifier(tour: tour + 1, vu: vu, coups: coups) }
        }
        guard tour < 60 else { journal("Dock de macOS : toujours affiché, on abandonne"); finir(); return }
        if !seMasque {
            journal("Dock de macOS : réglage revenu à « affiché », on le remasque")
            regler(masque: true) { suite(0, coups, 0.6) }
            return
        }
        guard dockAffiché() else { finir(); return }
        sansDockJusquÀ = Date().addingTimeInterval(4)
        if sourisSurLeDock() { suite(0, coups, 0.4); return }          // affiché parce qu'on le survole : normal
        if vu < 2 { suite(vu + 1, coups, 0.4); return }                // il est peut-être juste en train de partir
        guard coups < 4 else { journal("Dock de macOS : figé malgré 4 relances"); finir(); return }
        journal("Dock de macOS : figé après la grille, relance %d", coups + 1)
        regler(masque: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard !sorti else { return }
                regler(masque: true) { suite(0, coups + 1, 0.7) }
            }
        }
    }

    private static func finir() {
        UserDefaults.standard.removeObject(forKey: cleARendre)
        rendreLesTailles()
        // Une application lente à réagir peut se rétrécir un peu plus tard : un second passage.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { if !sorti { rendreLesTailles(); pleines = [] } }
    }

    /// Le Dock est-il à l'écran ? Masqué, sa barre est rangée juste sous le bas de l'écran (ou hors d'un côté).
    private static func dockAffiché() -> Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let ecran = NSScreen.screens.first else { return false }
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(dock.processIdentifier), kAXChildrenAttribute as CFString, &v)
        guard let barre = (v as? [AXUIElement])?.first, let c = AX.cadre(barre) else { return false }
        let f = CGRect(origin: .zero, size: ecran.frame.size)
        return c.maxY <= f.maxY + 2 && c.minX >= f.minX - 2 && c.maxX <= f.maxX + 2
    }

    private static func sourisSurLeDock() -> Bool {
        guard let ecran = NSScreen.screens.first else { return false }
        let s = NSEvent.mouseLocation
        return ecran.frame.contains(s) && s.y - ecran.frame.minY < hauteur + 40      // avec la loupe du Dock
    }

    private static func rendreLesTailles() {
        let actuels = relever(toutes: true)
        let parNumero = Dictionary(actuels.map { ($0.wid, $0.cadre) }, uniquingKeysWith: { a, _ in a })
        var faites: Set<CGWindowID> = []
        for f in pleines {
            guard let c = parNumero[f.wid], c != f.cadre, let el = AX.fenetre(pid: f.pid, wid: f.wid) else { continue }
            journal("Dock de macOS : fenêtre %d rendue à tout l'écran", Int(f.wid))
            AX.placer(el, f.cadre)
            faites.insert(f.wid)
        }
        // Et toute fenêtre qui s'arrête pile au-dessus de la place du Dock (rétrécie par son application à un moment où
        // on ne l'avait pas relevée, ou pas tout à fait aussi large que l'écran, comme Horizon) : rallongée jusqu'en bas.
        let h = hauteur
        for e in NSScreen.screens {
            guard let sans = zonesSansDock[Ecrans.identifiant(e)].map(Ecrans.versAX) else { continue }
            for f in actuels where !faites.contains(f.wid) {
                let c = f.cadre
                guard abs(c.minY - sans.minY) < 3, abs(c.maxY - (sans.maxY - h)) < 3, c.width >= 0.9 * sans.width,
                      c.minX >= sans.minX - 3, c.maxX <= sans.maxX + 3, let el = AX.fenetre(pid: f.pid, wid: f.wid) else { continue }
                journal("Dock de macOS : fenêtre %d rallongée jusqu'en bas", Int(f.wid))
                AX.placer(el, CGRect(x: c.minX, y: c.minY, width: c.width, height: sans.maxY - c.minY))
            }
        }
    }

    /// Les fenêtres affichées (cadres en coordonnées AX). Sans `toutes`, seulement celles qui couvrent presque toute la
    /// zone utile d'un écran (une application Flutter comme Horizon s'arrête à quelques points du bord).
    private static func relever(toutes: Bool = false) -> [(pid: pid_t, wid: CGWindowID, cadre: CGRect)] {
        let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let zones = NSScreen.screens.map { Ecrans.versAX($0.visibleFrame) }
        let moi = ProcessInfo.processInfo.processIdentifier
        return infos.compactMap { i in
            guard (i[kCGWindowLayer as String] as? Int) == 0,
                  let pid = i[kCGWindowOwnerPID as String] as? pid_t, pid != moi,
                  let wid = i[kCGWindowNumber as String] as? CGWindowID,
                  let d = i[kCGWindowBounds as String] as? NSDictionary,
                  let cadre = CGRect(dictionaryRepresentation: d) else { return nil }
            if !toutes, !zones.contains(where: { z in
                let commun = z.intersection(cadre)
                return !commun.isNull && commun.width * commun.height >= 0.97 * z.width * z.height
                    && abs(z.minY - cadre.minY) < 3 && abs(z.maxY - cadre.maxY) < 3
            }) { return nil }
            return (pid, wid, cadre)
        }
    }

    /// Le Dock glisse-t-il sans animation ? (réglages cachés de macOS `autohide-time-modifier` et `autohide-delay` à 0)
    private static var sansAnimation: Bool {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let v = CFPreferencesCopyAppValue("autohide-time-modifier" as CFString, "com.apple.dock" as CFString) as? Double
        return v == 0
    }

    /// Demandé par Gauthier (24/11/2026) : le Dock doit apparaître et disparaître d'un coup avec la grille. On coupe son
    /// animation de masquage (elle vaut aussi pour le survol du bas de l'écran). Fait une seule fois par Mac, et seulement
    /// si le Dock se masque automatiquement : il faut relancer le Dock pour que ce soit pris.
    private static func couperLAnimation() {
        guard seMasque, !sansAnimation else { return }
        journal("Dock de macOS : animation de masquage coupée (le Dock redémarre une fois)")
        CFPreferencesSetAppValue("autohide-time-modifier" as CFString, 0.0 as CFNumber, "com.apple.dock" as CFString)
        CFPreferencesSetAppValue("autohide-delay" as CFString, 0.0 as CFNumber, "com.apple.dock" as CFString)
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Dock"]
        try? p.run()
    }

    /// Au lancement de Side : un Dock laissé sorti par une grille interrompue se remasque.
    static func reprendre() {
        defer { couperLAnimation() }
        guard UserDefaults.standard.bool(forKey: cleARendre) else { return }
        UserDefaults.standard.removeObject(forKey: cleARendre)
        regler(masque: true) {}
    }

    private static func apprendreHauteur() {
        guard sorti else { return }
        for e in NSScreen.screens {
            let bas = e.visibleFrame.minY - e.frame.minY
            if bas > 10 { UserDefaults.standard.set(Double(bas), forKey: cleHauteur); return }
        }
    }

    /// Directement auprès du Dock (fonction de macOS non documentée, sans autorisation à donner) : le réglage est pris
    /// tout de suite et il tient. Événements système, essayé d'abord, laissait le Dock reprendre l'ancien réglage quelques
    /// secondes plus tard, une fois sur trois (24/11/2026).
    private static func regler(masque: Bool, fini: @escaping () -> Void) {
        DispatchQueue.main.async {
            CoreDockSetAutoHideEnabled(masque)
            if CoreDockGetAutoHideEnabled() != masque { journal("Dock de macOS : réglage non pris (%@)", "\(masque)") }
            fini()
        }
    }
}

@_silgen_name("CoreDockSetAutoHideEnabled") private func CoreDockSetAutoHideEnabled(_ flag: Bool)
@_silgen_name("CoreDockGetAutoHideEnabled") private func CoreDockGetAutoHideEnabled() -> Bool
