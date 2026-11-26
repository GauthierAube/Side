// Les fenêtres de macOS (mot de passe d'un serveur, trousseau, Touch ID, autorisations…) toujours devant Side (26/11/2026).
// Ces fenêtres appartiennent à de petits programmes de macOS et s'ouvrent au niveau des fenêtres ordinaires : la carte de
// Side, qui flotte au-dessus de tout, les cachait (la connexion au Mac mini semblait tourner sans fin).
// Tant qu'une de ces fenêtres est à l'écran, les fenêtres flottantes de Side redescendent au niveau ordinaire, et la
// fenêtre de macOS reçoit le clavier. Elles remontent dès qu'elle se ferme.
import AppKit

final class DialoguesSysteme {
    static let commun = DialoguesSysteme()

    /// Les programmes de macOS qui affichent ces fenêtres.
    private static let agents: Set<String> = [
        "com.apple.NetAuthAgent",                       // nom et mot de passe d'un serveur (SMB, AFP)
        "com.apple.SecurityAgent",                      // mot de passe administrateur, trousseau
        "com.apple.LocalAuthentication.UIAgent",        // Touch ID
        "com.apple.coreservices.uiagent",               // « Ouvrir une app téléchargée sur Internet ? »
        "com.apple.UserNotificationCenter",             // alertes du système
        "com.apple.accessibility.universalAccessAuthWarn", // autorisation Accessibilité
        "com.apple.CoreLocationAgent",                  // autorisation de localisation
        "com.apple.tcc.AuthorizationPromptService",     // « Side souhaite accéder à… » (autorisations)
        "com.apple.IOUIAgent",                          // alertes des disques
        "com.apple.authorizationhost",                  // mot de passe administrateur (autre forme)
    ]

    private var minuteur: Timer?
    private var jusquA = Date.distantPast
    /// Les fenêtres de Side abaissées, avec leur niveau d'avant.
    private var abaissees: [(fenetre: NSWindow, niveau: NSWindow.Level)] = []

    /// À appeler une fois au lancement : surveille les programmes de macOS qui passent au premier plan.
    func brancher() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let id = app?.bundleIdentifier, Self.agents.contains(id) { self?.surveiller(pendant: 3) }
        }
    }

    /// Guette une fenêtre de macOS pendant quelques secondes (par exemple au début d'une connexion à un serveur).
    func surveiller(pendant secondes: TimeInterval) {
        jusquA = max(jusquA, Date().addingTimeInterval(secondes))
        guard minuteur == nil else { return }
        regarder()
        minuteur = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.regarder() }
    }

    private func regarder() {
        if let agent = agentALEcran() {
            if abaissees.isEmpty { abaisser(); agent.activate() }
            jusquA = max(jusquA, Date().addingTimeInterval(1))
        } else {
            if !abaissees.isEmpty { remonter() }
            if Date() > jusquA { minuteur?.invalidate(); minuteur = nil }
        }
    }

    /// Le programme de macOS dont une fenêtre est à l'écran, s'il y en a un.
    private func agentALEcran() -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier.map(Self.agents.contains) ?? false }
        guard !apps.isEmpty,
              let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for info in infos {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let app = apps.first(where: { $0.processIdentifier == pid }),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let cadre = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (cadre["Width"] ?? 0) > 60, (cadre["Height"] ?? 0) > 60 else { continue }
            return app
        }
        return nil
    }

    private func abaisser() {
        for f in NSApp.windows where f.isVisible && f.level > .normal {
            abaissees.append((f, f.level))
            f.level = .normal
        }
    }

    private func remonter() {
        for (f, niveau) in abaissees where f.level == .normal { f.level = niveau }
        abaissees = []
    }
}
