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
    private static let file = DispatchQueue(label: "side.dock-natif")
    /// Le Dock est sorti pour la grille.
    private(set) static var sorti = false
    /// Les zones utiles des écrans relevées Dock masqué, juste avant de le faire sortir.
    private static var zonesSansDock: [String: NSRect] = [:]
    private static var sansDockJusquÀ = Date.distantPast

    private static var seMasque: Bool { UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false }

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
        guard !sorti, seMasque else { return }
        zonesSansDock = Dictionary(NSScreen.screens.map { (Ecrans.identifiant($0), $0.visibleFrame) }, uniquingKeysWith: { a, _ in a })
        sorti = true
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
        sansDockJusquÀ = Date().addingTimeInterval(2.5)      // le temps que macOS rende sa place à l'écran
        UserDefaults.standard.removeObject(forKey: cleARendre)
        regler(masque: true) {}
    }

    /// Au lancement de Side : un Dock laissé sorti par une grille interrompue se remasque.
    static func reprendre() {
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

    /// Passe par Événements système, comme le réglage de macOS : le Dock glisse, sans redémarrer.
    private static func regler(masque: Bool, fini: @escaping () -> Void) {
        file.async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "tell application \"System Events\" to set autohide of dock preferences to \(masque)"]
            do { try p.run(); p.waitUntilExit() } catch { journal("Dock de macOS : réglage impossible (%@)", "\(error)") }
            if p.terminationStatus != 0 { journal("Dock de macOS : Événements système a refusé (autorisation ?)") }
            fini()
        }
    }
}
