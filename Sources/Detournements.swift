// Tout ce qui allait au Finder ou à Safari et que Side prend à sa place (21/11/2026).
//
// 1. « Toujours Side, jamais le Finder » (Réglages > Finder). Être le visualiseur de fichiers de macOS (voir
//    Enregistrements.swift) ne suffit pas : AirDrop, « Afficher dans le Finder » de Safari, un disque qu'on branche…
//    s'adressent au Finder par son nom. Side surveille donc les fenêtres du Finder : dès qu'il en ouvre une, Side lit
//    son dossier (et le fichier choisi), la referme, et montre la même chose dans sa carte.
// 2. « Ouvrir les liens YouTube dans le tiroir » (Réglages > Tiroir > Multimédia). Le seul moyen, sur un Mac, de
//    recevoir les liens cliqués dans les autres applications est d'être le navigateur par défaut. Side le devient,
//    garde les liens de vidéos YouTube pour son tiroir, et passe tous les autres au vrai navigateur, sans rien afficher.

import AppKit
import ApplicationServices

// MARK: - Jamais le Finder

enum FinderJamais {
    private static let cle = "finderJamais"
    static var actif: Bool {
        get { UserDefaults.standard.bool(forKey: cle) }
        set { UserDefaults.standard.set(newValue, forKey: cle); demarrer() }
    }
    private static var observateur: AXObserver?
    private static var ecoute = false
    private static let file = DispatchQueue(label: "side.finder-jamais")
    /// Jusqu'à cet instant, les fenêtres du Finder sont laissées tranquilles : « Afficher dans le Finder » de Side lui-même.
    static var laisserPasserJusqua = Date.distantPast

    /// (Re)commence à surveiller les fenêtres du Finder : au lancement de Side, au changement du réglage, et quand le
    /// Finder est relancé.
    static func demarrer() {
        if let o = observateur {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
            observateur = nil
        }
        if !ecoute {
            ecoute = true
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
                let a = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if a?.bundleIdentifier == VisualiseurFichiers.finder { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { demarrer() } }
            }
        }
        guard actif, AXIsProcessTrusted(),
              let finder = NSRunningApplication.runningApplications(withBundleIdentifier: VisualiseurFichiers.finder).first else { return }
        var o: AXObserver?
        let rappel: AXObserverCallback = { _, fenetre, _, _ in FinderJamais.fenetreOuverte(fenetre) }
        guard AXObserverCreate(finder.processIdentifier, rappel, &o) == .success, let o else { return }
        AXObserverAddNotification(o, AXUIElementCreateApplication(finder.processIdentifier), kAXWindowCreatedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        observateur = o
        journalBas("jamais le Finder : ses fenêtres sont surveillées")
    }

    /// Le Finder vient d'ouvrir une fenêtre.
    private static func fenetreOuverte(_ fenetre: AXUIElement) {
        guard actif, Partie.finder.active, Date() > laisserPasserJusqua, !CaptureEcran.enCours else { return }
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(fenetre, kAXTitleAttribute as CFString, &v)
        guard let titre = v as? String, !titre.isEmpty else { return }
        // Un instant, le temps que le Finder y choisisse le fichier à montrer (AirDrop, un téléchargement).
        file.asyncAfter(deadline: .now() + 0.3) {
            guard let (dossier, choisi) = lireEtFermer(titre) else { return }
            DispatchQueue.main.async {
                journalBas("jamais le Finder : « %@ » repris par Side", titre)
                AppDelegate.shared.montrerDansLaCarte(choisi ?? dossier)
            }
        }
    }

    /// Demande au Finder le dossier (et le fichier choisi) de sa fenêtre de ce nom, et la lui fait refermer.
    /// Rien si ce n'est pas une fenêtre de dossier (Lire les informations, Réglages, AirDrop, Récents…) : elle reste.
    private static func lireEtFermer(_ titre: String) -> (URL, URL?)? {
        let nom = titre.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Finder"
            set lesFenetres to (every Finder window whose name is "\(nom)")
            if (count of lesFenetres) is 0 then return ""
            set w to item 1 of lesFenetres
            try
                set dossier to POSIX path of (target of w as alias)
            on error
                return ""
            end try
            set choisi to ""
            try
                set s to selection
                if (count of s) > 0 then set choisi to POSIX path of (item 1 of s as alias)
            end try
            close w
            return dossier & linefeed & choisi
        end tell
        """
        var erreur: NSDictionary?
        guard let r = NSAppleScript(source: source)?.executeAndReturnError(&erreur).stringValue, !r.isEmpty else {
            if let erreur { journalBas("jamais le Finder : le Finder n'a pas répondu (%@)", "\(erreur[NSAppleScript.errorMessage] ?? "")") }
            return nil
        }
        let lignes = r.components(separatedBy: "\n")
        let dossier = URL(fileURLWithPath: lignes[0])
        // Le fichier choisi ne compte que s'il est bien dans ce dossier (la sélection est celle de la fenêtre de devant).
        let choisi = lignes.count > 1 && !lignes[1].isEmpty ? URL(fileURLWithPath: lignes[1]) : nil
        let dedans = choisi.map { $0.deletingLastPathComponent().standardizedFileURL.path == dossier.standardizedFileURL.path } ?? false
        return (dossier, dedans ? choisi : nil)
    }
}

// MARK: - Les liens YouTube dans le tiroir

enum LiensWeb {
    private static let cleNavigateur = "navigateurReel"
    static let side = VisualiseurFichiers.side
    private static let essai = URL(string: "https://example.com")!

    /// L'application qui ouvre les liens web en ce moment (son identifiant).
    private static var parDefaut: String? {
        NSWorkspace.shared.urlForApplication(toOpen: essai).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }
    /// Side reçoit-il les liens web (il est le navigateur par défaut du Mac) ?
    static var actif: Bool { parDefaut == side }

    /// Le vrai navigateur, à qui Side passe tout ce qui n'est pas pour le tiroir : celui d'avant, sinon Safari.
    static var navigateur: URL {
        let retenu = UserDefaults.standard.string(forKey: cleNavigateur) ?? "com.apple.Safari"
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: retenu)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
            ?? URL(fileURLWithPath: "/Applications/Safari.app")
    }
    static var nomNavigateur: String { FileManager.default.displayName(atPath: navigateur.path).replacingOccurrences(of: ".app", with: "") }

    /// Coche ou décoche le réglage. macOS demande lui-même confirmation avant de changer de navigateur par défaut.
    static func choisir(_ oui: Bool, puis fin: @escaping () -> Void = {}) {
        if oui, let avant = parDefaut, avant != side { UserDefaults.standard.set(avant, forKey: cleNavigateur) }
        let cible = oui ? Bundle.main.bundleURL : navigateur
        NSWorkspace.shared.setDefaultApplication(at: cible, toOpenURLsWithScheme: "http") { erreur in
            if let erreur { journalBas("liens web : changement de navigateur refusé (%@)", erreur.localizedDescription) }
            NSWorkspace.shared.setDefaultApplication(at: cible, toOpenURLsWithScheme: "https") { _ in
                DispatchQueue.main.async { journalBas("liens web : navigateur par défaut = %@", parDefaut ?? "?"); fin() }
            }
        }
    }

    /// Un lien de vidéo, de chaîne ou de recherche YouTube, à regarder dans le tiroir. Pas YouTube Music ni YouTube
    /// Studio (music.youtube.com, studio.youtube.com) ni la connexion au compte : ceux-là restent au navigateur.
    static func pourLeTiroir(_ u: URL) -> Bool {
        guard let h = u.host?.lowercased(), u.scheme == "http" || u.scheme == "https" else { return false }
        return ["youtu.be", "youtube.com", "www.youtube.com", "m.youtube.com", "www.youtube-nocookie.com"].contains(h)
    }

    /// Des liens web que macOS demande à Side d'ouvrir. `deSide` : c'est Side lui-même qui les ouvre (« Ouvrir dans le
    /// navigateur » de sa tuile YouTube, un lien de sa carte…) : ils vont au navigateur, sinon ils reviendraient ici.
    static func recevoir(_ liens: [URL], deSide: Bool) {
        var dehors: [URL] = []
        for u in liens {
            let tiroir = PanneauBas.commun
            if !deSide, actif, pourLeTiroir(u), Partie.tiroir.active, tiroir.médias.contains(where: { $0.genre == "youtube" }) {
                journalBas("liens web : YouTube dans le tiroir (%@)", u.absoluteString)
                tiroir.montrerYouTube(u)
            } else {
                dehors.append(u)
            }
        }
        guard !dehors.isEmpty else { return }
        NSWorkspace.shared.open(dehors, withApplicationAt: navigateur, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}

extension PanneauBas {
    /// Ouvre le tiroir sur sa tuile YouTube, et y lance ce lien.
    func montrerYouTube(_ lien: URL) {
        guard let m = médias.first(where: { $0.genre == "youtube" }) else { return }
        let lancer = { [weak self] in
            if TuilePeinard.disponible { TuilePeinard.ouvrir(lien) }
            else { self?.lecteursWeb.first(where: { $0.estUnYouTube })?.ouvrir(lienYouTubeBas(lien) ?? lien) }
        }
        if média != m.id {
            média = m.id
            if ouvert, panneau != nil { recharger(versLaFin: false) }
        }
        if ouvert { lancer(); return }
        ouvrir()
        // La tuile YouTube est créée à l'ouverture du tiroir : le lien part une fois qu'elle est là.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { lancer() }
    }
}
