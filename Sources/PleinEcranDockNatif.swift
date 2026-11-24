import AppKit

/// Le Dock de macOS pendant la grille (24/11/2026) : s'il se masque automatiquement, la grille le fait sortir le temps
/// qu'elle est ouverte, puis le remasque. Le réglage de macOS est changé pour de vrai (comme Réglages Système › Bureau
/// et Dock), donc on note qu'il faut le remettre : si Side s'arrête grille ouverte, il le remet au lancement suivant.
enum DockNatif {
    private static let cleARendre = "dockNatifAutoMasqueARendre"
    private static let file = DispatchQueue(label: "side.dock-natif")
    private static var sorti = false

    private static var seMasque: Bool { UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false }

    /// À l'ouverture de la grille. `fini` est appelé sur le fil principal une fois le Dock sorti (pour ranger les cases).
    static func sortir(fini: @escaping () -> Void) {
        guard !sorti, seMasque else { return }
        sorti = true
        UserDefaults.standard.set(true, forKey: cleARendre)
        regler(masque: false) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: fini) }
    }

    /// À la fermeture de la grille.
    static func rentrer() {
        guard sorti else { return }
        sorti = false
        UserDefaults.standard.removeObject(forKey: cleARendre)
        regler(masque: true) {}
    }

    /// Au lancement de Side : un Dock laissé sorti par une grille interrompue se remasque.
    static func reprendre() {
        guard UserDefaults.standard.bool(forKey: cleARendre) else { return }
        UserDefaults.standard.removeObject(forKey: cleARendre)
        regler(masque: true) {}
    }

    /// Passe par Événements système, comme le réglage de macOS : le Dock glisse en douceur, sans redémarrer.
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
