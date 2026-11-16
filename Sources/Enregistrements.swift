// La carte du Finder et les fichiers enregistrés ailleurs (16/11/2026).
//
// 1. La carte se rouvre là où l'on était, sauf quand un fichier vient d'être enregistré (un export de Logic Pro vers la
//    bibliothèque de sons, un téléchargement…) : elle s'ouvre alors sur le dossier de ce fichier, le fichier choisi.
//    Side le repère avec FSEvents, le journal des changements de fichiers de macOS (dossier personnel et disques branchés).
// 2. Réglages > Finder > « Ouvrir les dossiers dans Side » : Side devient le visualiseur de fichiers de macOS. « Afficher
//    dans le Finder » d'une autre application, et l'ouverture d'un dossier, montrent alors la carte de Side.

import AppKit
import CoreServices

enum Enregistrements {
    /// Le dernier fichier enregistré repéré, et quand.
    private(set) static var dernier: (url: URL, date: Date)?
    /// Un fichier enregistré compte pendant 10 minutes : au-delà, la carte retrouve simplement le dernier dossier.
    static let duree: TimeInterval = 600
    private static var flux: FSEventStreamRef?
    private static var observe = false

    /// Commence à repérer les fichiers enregistrés (au lancement de Side, et quand un disque est branché ou débranché).
    static func demarrer() {
        arreter()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Les disques branchés que l'on voit dans le Finder, sans les disques de sauvegarde (Time Machine) ni de secours.
        let disques = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [])
            .map(\.path).filter { chemin in
                let nom = (chemin as NSString).lastPathComponent.lowercased()
                let fm = FileManager.default
                return chemin.hasPrefix("/Volumes/") && nom != "recovery" && !nom.contains("time machine")
                    && !nom.hasPrefix("com.apple") && !fm.fileExists(atPath: chemin + "/Backups.backupdb")
                    && !fm.fileExists(atPath: chemin + "/.timemachine")
            }
        let chemins = [home] + disques
        var contexte = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        let rappel: FSEventStreamCallback = { _, _, n, chemins, drapeaux, _ in
            guard let liste = unsafeBitCast(chemins, to: NSArray.self) as? [String] else { return }
            for i in 0..<n {
                let f = drapeaux[i]
                let fichier = f & UInt32(kFSEventStreamEventFlagItemIsFile) != 0
                let nouveau = f & UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed) != 0
                guard fichier, nouveau, i < liste.count else { continue }
                Enregistrements.noter(liste[i])
            }
        }
        let options = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, rappel, &contexte, chemins as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.4, options) else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        flux = s
        journalBas("fichiers enregistrés : surveillance de %@", chemins.joined(separator: ", "))
        guard !observe else { return }
        observe = true
        let c = NSWorkspace.shared.notificationCenter
        c.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { _ in demarrer() }
        c.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { _ in demarrer() }
    }

    private static func arreter() {
        guard let s = flux else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        flux = nil
    }

    /// Un fichier vient d'apparaître : est-ce un vrai fichier enregistré par quelqu'un (et pas un fichier de travail
    /// d'une application, un cache, un fichier caché) ?
    private static func noter(_ chemin: String) {
        let u = URL(fileURLWithPath: chemin)
        guard FileManager.default.fileExists(atPath: chemin), estUnEnregistrement(u) else { return }
        if dernier?.url != u { journalBas("fichier enregistré repéré : %@", chemin) }
        dernier = (u, Date())
    }

    static func estUnEnregistrement(_ u: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let chemin = u.path
        let nom = u.lastPathComponent
        // Fichiers cachés, temporaires ou en cours de téléchargement.
        if nom.hasPrefix(".") || nom.hasPrefix("~$") || nom == "Icon\r" { return false }
        let temporaires: Set<String> = ["tmp", "temp", "part", "crdownload", "download", "partial", "sb", "lock", "swp"]
        if temporaires.contains(u.pathExtension.lowercased()) { return false }
        // Un dossier caché sur le chemin (.git, .Trash…).
        if u.pathComponents.dropLast().contains(where: { $0.hasPrefix(".") }) { return false }
        // La bibliothèque du dossier personnel ne compte pas, sauf iCloud Drive.
        if chemin.hasPrefix(home + "/Library/") && !chemin.hasPrefix(home + "/Library/Mobile Documents/com~apple~CloudDocs/") { return false }
        // Les fichiers de Side elle-même (zones de dépôt, historique).
        if chemin.contains("/Application Support/Side/") { return false }
        // À l'intérieur d'un paquet (un projet Logic, une photothèque, une app) : ce sont ses fichiers de travail.
        var parent = u.deletingLastPathComponent()
        while parent.path.count > 1 && parent.path != home {
            if NSWorkspace.shared.isFilePackage(atPath: parent.path) { return false }
            parent = parent.deletingLastPathComponent()
        }
        return true
    }

    /// Le fichier sur lequel ouvrir la carte, s'il y en a un : enregistré depuis la dernière ouverture, il y a moins de 10 minutes.
    static func aMontrer(depuis derniereOuverture: Date) -> URL? {
        guard let d = dernier, d.date > derniereOuverture, Date().timeIntervalSince(d.date) < duree,
              FileManager.default.fileExists(atPath: d.url.path) else { return nil }
        return d.url
    }
}

// MARK: - Side comme visualiseur de fichiers

enum VisualiseurFichiers {
    static let side = "com.gauthieraube.side"
    static let finder = "com.apple.finder"

    /// Side est-il le visualiseur de fichiers de macOS ?
    static var actif: Bool {
        (CFPreferencesCopyValue("NSFileViewer" as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                                kCFPreferencesAnyHost) as? String) == side
    }

    /// Change le visualiseur de fichiers (réglage du Mac pour cet utilisateur) : Side, ou de nouveau le Finder.
    static func choisir(_ oui: Bool) {
        CFPreferencesSetValue("NSFileViewer" as CFString, oui ? side as CFString : nil, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        // Les dossiers ouverts par les autres applications (et par « open » dans le Terminal) s'ouvrent dans Side.
        LSSetDefaultRoleHandlerForContentType("public.folder" as CFString, .all, (oui ? side : finder) as CFString)
    }

    /// Écoute « Afficher dans le Finder » : macOS envoie au visualiseur de fichiers la demande de montrer ces fichiers.
    static func ecouter() {
        let m = NSAppleEventManager.shared()
        let gestion = Gestionnaire.commun
        // 'misc' 'mvis' : rendre visibles (« Afficher dans le Finder »). 'fndr' 'rvl ' : la même demande, adressée au Finder.
        m.setEventHandler(gestion, andSelector: #selector(Gestionnaire.montrer(_:reponse:)),
                          forEventClass: AEEventClass(kAEMiscStandards), andEventID: AEEventID(kAEMakeObjectsVisible))
        m.setEventHandler(gestion, andSelector: #selector(Gestionnaire.montrer(_:reponse:)),
                          forEventClass: fourCC("fndr"), andEventID: fourCC("rvl "))
    }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    /// Les fichiers d'un événement Apple (un fichier seul, ou une liste).
    static func fichiers(_ e: NSAppleEventDescriptor) -> [URL] {
        guard let d = e.paramDescriptor(forKeyword: keyDirectObject) else { return [] }
        let liste = d.numberOfItems > 0 ? (1...d.numberOfItems).compactMap { d.atIndex($0) } : [d]
        return liste.compactMap { $0.coerce(toDescriptorType: typeFileURL)?.fileURLValue }
    }

    final class Gestionnaire: NSObject {
        static let commun = Gestionnaire()
        @objc func montrer(_ e: NSAppleEventDescriptor, reponse: NSAppleEventDescriptor) {
            guard let u = VisualiseurFichiers.fichiers(e).first else { return }
            AppDelegate.shared.montrerDansLaCarte(u)
        }
    }

    /// Montre ce fichier dans le vrai Finder (pour « Afficher dans le Finder » de Side lui-même, qui sinon reviendrait ici).
    static func revelerDansLeFinder(_ u: URL) {
        let chemin = u.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var err: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\"\nreveal (POSIX file \"\(chemin)\" as alias)\nactivate\nend tell")?
            .executeAndReturnError(&err)
        if err != nil { NSWorkspace.shared.activateFileViewerSelecting([u]) }
    }
}

extension AppDelegate {
    /// Ouvre la carte sur ce fichier (son dossier, le fichier choisi), ou sur ce dossier.
    func montrerDansLaCarte(_ u: URL) {
        var dossier: ObjCBool = false
        FileManager.default.fileExists(atPath: u.path, isDirectory: &dossier)
        let lieu = dossier.boolValue && !NSWorkspace.shared.isFilePackage(atPath: u.path) ? u : u.deletingLastPathComponent()
        if !visible, let e = Ecrans.deTravail { epingle = true; show(sur: e) }
        store.naviguer(.folder(lieu))
        guard lieu != u else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Selection.shared.choisir(u, self.store.navigateur) }
    }

    /// Les dossiers ou fichiers que macOS demande à Side d'ouvrir (Side visualiseur de fichiers, ou « open -a Side »).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let u = urls.first else { return }
        montrerDansLaCarte(u)
    }
}
