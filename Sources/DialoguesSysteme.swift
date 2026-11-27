// Les fenêtres de macOS (mot de passe d'un serveur, trousseau, Touch ID, autorisations…) toujours devant Side (26/11/2026).
// Ces fenêtres appartiennent à de petits programmes de macOS et s'ouvrent au niveau des fenêtres ordinaires : la carte de
// Side, qui flotte au-dessus de tout, les cachait (la connexion au Mac mini semblait tourner sans fin).
// Tant qu'une de ces fenêtres est à l'écran, les fenêtres flottantes de Side redescendent au niveau ordinaire, et la
// fenêtre de macOS reçoit le clavier. Elles remontent dès qu'elle se ferme.
// 27/11/2026 : élargi à TOUTE fenêtre de dialogue d'une autre application (Finder : « Forcer l'éjection ? », « Remplacer ? »,
// « Placer dans la corbeille ? »…). La confirmation d'éjection d'un SSD restait cachée sous la carte et bloquait le Mac.
// Side écoute (Accessibilité) l'application au premier plan : dès qu'elle ouvre un dialogue, une alerte ou une feuille,
// les fenêtres de Side redescendent jusqu'à sa fermeture.
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
            self?.ecouter(app)
        }
        ecouter(NSWorkspace.shared.frontmostApplication)
    }

    // MARK: Les dialogues des autres applications (Finder…)

    private var observateur: AXObserver?
    private var pidEcoute: pid_t = 0

    /// Écoute les fenêtres qui s'ouvrent dans l'application au premier plan (une seule à la fois, pas de minuterie).
    private func ecouter(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != getpid(), app.processIdentifier != pidEcoute, AXIsProcessTrusted() else { return }
        if let o = observateur {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        }
        observateur = nil
        pidEcoute = app.processIdentifier
        var o: AXObserver?
        guard AXObserverCreate(app.processIdentifier, { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<DialoguesSysteme>.fromOpaque(refcon).takeUnretainedValue().surveiller(pendant: 1.5)
        }, &o) == .success, let o else { return }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        let moi = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXSheetCreatedNotification] {
            AXObserverAddNotification(o, el, n as CFString, moi)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        observateur = o
        if dialogueEtranger() != nil { surveiller(pendant: 1.5) }
    }

    /// L'application au premier plan (autre que Side) qui affiche un dialogue, une alerte ou une feuille, s'il y en a une.
    private func dialogueEtranger() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(),
              AXIsProcessTrusted() else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.2)          // une application figée ne doit jamais figer Side
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &v) == .success,
              let fenetres = v as? [AXUIElement] else { return nil }
        for f in fenetres {
            AXUIElementSetMessagingTimeout(f, 0.2)
            if Self.texte(f, kAXSubroleAttribute) == "AXDialog" || Self.texte(f, kAXSubroleAttribute) == "AXSystemDialog" { return app }
            var modal: CFTypeRef?
            if AXUIElementCopyAttributeValue(f, kAXModalAttribute as CFString, &modal) == .success,
               (modal as? Bool) == true { return app }
            var enfants: CFTypeRef?
            if AXUIElementCopyAttributeValue(f, kAXChildrenAttribute as CFString, &enfants) == .success,
               let liste = enfants as? [AXUIElement],
               liste.contains(where: { Self.texte($0, kAXRoleAttribute) == (kAXSheetRole as String) }) { return app }
        }
        return nil
    }

    private static func texte(_ e: AXUIElement, _ attribut: String) -> String? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, attribut as CFString, &v) == .success ? v as? String : nil
    }

    /// Guette une fenêtre de macOS pendant quelques secondes (par exemple au début d'une connexion à un serveur).
    func surveiller(pendant secondes: TimeInterval) {
        jusquA = max(jusquA, Date().addingTimeInterval(secondes))
        guard minuteur == nil else { return }
        regarder()
        minuteur = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.regarder() }
    }

    private func regarder() {
        if let agent = agentALEcran() ?? dialogueEtranger() {
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
