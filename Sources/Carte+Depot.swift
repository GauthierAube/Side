// Fichiers et applications déposés sur la carte et dans le mini-Dock.
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
    // MARK: Dépôt de fichiers dans la carte
    /// Crée une colonne pour ce qui est déposé sur le bouton « + » :
    /// un dossier, ou une entrée de la barre latérale (Fichiers récents, Dossiers récents, un tag).
    func epingler(_ fournisseurs: [NSItemProvider]) {
        for f in fournisseurs {
            if f.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = f.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL, Fichiers.item(url).isFolder else { return }
                    DispatchQueue.main.async { self.store.ajouter(.folder(url.standardizedFileURL)) }
                }
            } else {
                _ = f.loadObject(ofClass: NSString.self) { texte, _ in
                    guard let texte = texte as? String, texte.hasPrefix(Glissable.prefixe),
                          let kind = Column.Kind(code: String(texte.dropFirst(Glissable.prefixe.count))) else { return }
                    DispatchQueue.main.async { self.store.ajouter(kind) }
                }
            }
        }
    }

    /// Ajoute aux favoris les dossiers déposés sur le titre « Favoris ».
    func ajouterFavoris(_ fournisseurs: [NSItemProvider]) {
        for f in fournisseurs {
            _ = f.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL, Fichiers.item(url).isFolder else { return }
                DispatchQueue.main.async { self.store.ajouterFavori(url) }
            }
        }
    }

    /// Au lancement : supprime du dossier de dépôt ce qui n'est plus dans aucune zone.
    func nettoyerDepot() {
        (0..<Etagere.maximum).forEach { Etagere.dedoublonner($0) }
        let gardes = Set((0..<Etagere.maximum).flatMap { Etagere.items($0).map { $0.url.standardizedFileURL.path } })
        let contenu = (try? FileManager.default.contentsOfDirectory(at: Self.dossierDepot, includingPropertiesForKeys: nil)) ?? []
        for fichier in contenu where !gardes.contains(fichier.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: fichier)
        }
    }

    /// Transforme ce qu'on dépose en fichier. `temporaire` est vrai quand Side a dû l'enregistrer lui-même.
    /// Les vrais fichiers du glisser en cours, lus directement là où macOS les note.
    /// (Ce que l'interface transmet au moment du dépôt est parfois une copie du fichier, pas le fichier :
    /// le ranger créait alors un doublon « nom 2 », même en le lâchant dans son propre dossier.)
    func fichiersGlisses() -> [URL] {
        let lus = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return lus.map { ($0 as NSURL).filePathURL ?? $0 }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Reçoit tout ce qui vient d'être lâché : les vrais fichiers s'il y en a, sinon ce que l'interface fournit
    /// (une image tirée d'une page web, une capture d'écran…), dont Side enregistre alors une copie.
    func recevoirTout(_ fournisseurs: [NSItemProvider], _ suite: @escaping (_ url: URL, _ temporaire: Bool) -> Void) {
        let directs = fichiersGlisses()
        if !directs.isEmpty { directs.forEach { suite($0, false) }; return }
        fournisseurs.forEach { recevoir($0, suite) }
    }

    func recevoir(_ f: NSItemProvider, _ suite: @escaping (_ url: URL, _ temporaire: Bool) -> Void) {
        if f.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = f.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                // macOS transmet parfois une « référence » au fichier plutôt que son chemin : on revient au chemin,
                // sinon Side ne reconnaît pas le dossier d'origine et crée un doublon.
                let chemin = (url as NSURL).filePathURL ?? url
                DispatchQueue.main.async { suite(chemin, false) }
            }
            return
        }
        let acceptes: [UTType] = [.image, .pdf, .movie, .audio]
        guard let type = f.registeredTypeIdentifiers.first(where: { id in
            guard let t = UTType(id) else { return false }
            return acceptes.contains { t.conforms(to: $0) }
        }) else { return }
        let nomPropose = f.suggestedName
        f.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
            // Le fichier fourni disparaît à la fin de ce bloc : on le copie tout de suite.
            guard let url else { return }
            let ext = url.pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? "") : url.pathExtension
            var nom = nomPropose ?? url.deletingPathExtension().lastPathComponent
            if nom.isEmpty { nom = String(localized: "Élément déposé") }
            var cible = Self.dossierDepot.appendingPathComponent(nom).appendingPathExtension(ext)
            var n = 2
            while FileManager.default.fileExists(atPath: cible.path) {
                cible = Self.dossierDepot.appendingPathComponent("\(nom) \(n)").appendingPathExtension(ext)
                n += 1
            }
            guard (try? FileManager.default.copyItem(at: url, to: cible)) != nil else { return }
            DispatchQueue.main.async { suite(cible, true) }
        }
    }

    /// Une capture d'écran vient d'être enregistrée : elle va dans sa propre zone (une zone vide, sinon une nouvelle),
    /// jamais dans une zone qui contient déjà quelque chose. Seulement s'il n'y a plus de place pour une zone de plus,
    /// elle rejoint la zone des captures précédentes.
    func recevoirCapture(_ url: URL) {
        // Déjà déposée à la main depuis la vignette de macOS (même nom) : on ne la met pas deux fois.
        let nom = url.lastPathComponent
        if (0..<store.etageres.count).contains(where: { Etagere.fichiers($0).contains { $0.lastPathComponent == nom } }) { return }
        let rangees = Captures.rangees
        let n = store.etageres.count
        var zone = (0..<n).first { Etagere.items($0).isEmpty }
        if zone == nil, Etagere.nombre < Etagere.maximum { store.ajouterZone(); zone = store.etageres.count - 1 }
        if zone == nil {
            zone = (0..<n).last { i in
                let f = Etagere.fichiers(i)
                return !f.isEmpty && f.allSatisfy { rangees.contains($0.path) }
            }
        }
        let i = zone ?? max(0, n - 1)
        let chemin = url.resolvingSymlinksInPath().standardizedFileURL.path
        Captures.rangees = rangees.filter { FileManager.default.fileExists(atPath: $0) }.union([chemin])
        Etagere.ajouter(url, i)
        journal("capture rangée dans la zone \(i) : \(nom)")
        store.reloadAll()
        // Side fermé : la zone se montre tout de suite, comme la vignette de macOS, mais reste plus longtemps.
        if !visible { captureJusqua = ProcessInfo.processInfo.systemUptime + 60 }
        majDepot()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.majDepot() }
    }

    /// La zone où une capture est rangée (aucune si elle n'y est pas, ou plus).
    func zoneDeLaCapture(_ url: URL) -> Int? {
        let chemins: Set<String> = [url.path, url.resolvingSymlinksInPath().standardizedFileURL.path]
        return (0..<store.etageres.count).first { Etagere.fichiers($0).contains { chemins.contains($0.path) } }
    }

    /// L'IA locale vient de renommer une capture (voir `Captures.renommer`) : la zone de dépôt suit le fichier.
    /// `zone` est celle où elle était rangée juste avant d'être renommée.
    func captureRenommee(_ ancien: URL, _ nouveau: URL, _ zone: Int?) {
        let avant = ancien.resolvingSymlinksInPath().standardizedFileURL.path
        var rangees = Captures.rangees
        if rangees.remove(avant) != nil || rangees.remove(ancien.path) != nil {
            rangees.insert(nouveau.resolvingSymlinksInPath().standardizedFileURL.path)
            Captures.rangees = rangees
        }
        // Si la zone a oublié l'ancien emplacement pendant le changement de nom (elle oublie les fichiers disparus),
        // la capture y est remise sous son nouveau nom.
        if !Etagere.renommer(ancien, nouveau), let zone, zone < store.etageres.count { Etagere.ajouter(nouveau, zone) }
        journal("capture renommée : \(ancien.lastPathComponent) → \(nouveau.lastPathComponent)")
        store.reloadAll()
        majDepot()
    }

    /// Pose des éléments sur l'étagère. Les vrais fichiers ne sont pas déplacés : seul leur emplacement est retenu.
    func poser(_ fournisseurs: [NSItemProvider], _ zone: Int) {
        // Option maintenue au moment de lâcher : Side reste ouvert, pour enchaîner.
        let garder = NSEvent.modifierFlags.contains(.option)
        // Entre le lâcher et l'arrivée du fichier dans la zone, celle-ci reste affichée (sinon elle clignote).
        depotEnCours = ProcessInfo.processInfo.systemUptime
        if !store.glisse { store.glisse = true }
        do {
            recevoirTout(fournisseurs) { url, temporaire in
                // Une image ou capture déposée une seconde fois : Side vient d'en enregistrer une copie.
                // Si la zone contient déjà exactement le même contenu, on jette la copie.
                if temporaire, Etagere.fichiers(zone).contains(where: { $0.path != url.path
                    && FileManager.default.contentsEqual(atPath: $0.path, andPath: url.path) }) {
                    try? FileManager.default.removeItem(at: url)
                } else if !Etagere.ajouter(url, zone), temporaire {
                    try? FileManager.default.removeItem(at: url)
                }
                self.store.reloadAll()
                self.depotEnCours = ProcessInfo.processInfo.systemUptime - 1.2   // le fichier est là : encore un court instant
                guard self.config.fermerApresDepot, !garder else { return }
                // Un court instant avant de fermer : si la souris est revenue sur la carte, c'est qu'on n'a pas fini.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !self.cadreCarte.contains(NSEvent.mouseLocation) { self.hide() }
                }
            }
        }
    }

    func deposer(_ fournisseurs: [NSItemProvider], dans dossier: URL) {
        recevoirTout(fournisseurs) { url, _ in self.ranger(url, dans: dossier) }
    }

    /// Comme le Finder : déplace sur le même disque, copie sinon (ou si Option est enfoncée).
    func ranger(_ source: URL, dans dossier: URL) {
        let source = (source as NSURL).filePathURL ?? source
        let src = source.standardizedFileURL, dst = Fichiers.resoudre(dossier).standardizedFileURL   // un alias de dossier : on range dans le vrai dossier
        // Lâché dans le dossier où il se trouve déjà (ou sur lui-même, ou dans un de ses sous-dossiers) : on ne fait rien.
        // On compare les vrais chemins : deux écritures du même dossier ne doivent pas créer un doublon.
        let ici = src.resolvingSymlinksInPath().path, parent = src.deletingLastPathComponent().resolvingSymlinksInPath().path
        let la = dst.resolvingSymlinksInPath().path
        guard ici != la, parent != la, !(la + "/").hasPrefix(ici + "/") else { return }
        // Dernière vérification, par l'identité du dossier sur le disque plutôt que par son nom.
        let idParent = try? URL(fileURLWithPath: parent).resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        let idCible = try? URL(fileURLWithPath: la).resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        if let idParent, let idCible, idParent.isEqual(idCible) { return }
        var cible = dst.appendingPathComponent(src.lastPathComponent)
        if FileManager.default.fileExists(atPath: cible.path) { cible = nomLibre(cible, suffixe: " 2") }
        let v1 = try? src.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let v2 = try? dst.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let memeDisque = v1 != nil && v2 != nil && v1!.isEqual(v2!)
        // En arrière-plan : une grosse copie (autre disque, serveur) figerait Side et retiendrait les clics de tout le Mac.
        let copier = !memeDisque || NSEvent.modifierFlags.contains(.option)
        DispatchQueue.global(qos: .userInitiated).async {
            var echec: Error?
            do {
                if copier { try FileManager.default.copyItem(at: src, to: cible) }
                else { try FileManager.default.moveItem(at: src, to: cible) }
            } catch { echec = error }
            DispatchQueue.main.async {
                if let echec { self.erreur(String(localized: "Impossible de ranger « \(src.lastPathComponent) »"), echec) }
                self.store.reloadAll()
            }
        }
    }

    @objc func afficherEpingle() {
        guard let e = Ecrans.deTravail else { return }
        epingle = true
        show(sur: e)
    }

    @objc func choisirDossier() {
        hide()
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = String(localized: "Ajouter")
        p.message = String(localized: "Choisis le dossier à épingler dans Side")
        if Devant.panneau(p) == .OK, let url = p.url {
            store.ajouter(.folder(url.standardizedFileURL))
            afficherEpingle()
        }
    }

    // MARK: Mini-Dock
    /// Passe à une app (ou la lance), y compris quand elle est en plein écran sur un autre bureau.
    /// Activer une app ne suffit pas à rejoindre son bureau quand le réglage Mission Control
    /// correspondant est désactivé. Le moyen sûr est celui que tu utilises à la main : cliquer sur son
    /// icône dans le Dock de macOS. Side le fait à ta place (il lui faut l'accès « Accessibilité »).
    func allerA(_ url: URL) {
        hide()
        let chemin = url.standardizedFileURL.path
        let ouverte = NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL.path == chemin }
        if ouverte, AXIsProcessTrusted() {
            DispatchQueue.global(qos: .userInitiated).async {
                if !Self.cliquerDansLeDock(chemin) { DispatchQueue.main.async { Self.activer(url) } }
            }
        } else {
            // Sans l'accès « Accessibilité », Side ne peut qu'activer l'app (sans changer de bureau).
            // On le demande une fois par lancement : macOS affiche alors sa fenêtre d'autorisation.
            if ouverte, !accesDemande {
                accesDemande = true
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            }
            Self.activer(url)
        }
    }

    static func activer(_ url: URL) {
        let reglage = NSWorkspace.OpenConfiguration()
        reglage.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: reglage) { _, _ in }
    }

    /// Appuie sur l'icône de l'app dans le Dock de macOS. Renvoie faux si elle n'y est pas trouvée.
    static func cliquerDansLeDock(_ chemin: String) -> Bool {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else { return false }
        let racine = AXUIElementCreateApplication(dock.processIdentifier)
        func enfants(_ e: AXUIElement) -> [AXUIElement] {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v) == .success else { return [] }
            return v as? [AXUIElement] ?? []
        }
        for liste in enfants(racine) {
            for icone in enfants(liste) {
                var v: CFTypeRef?
                guard AXUIElementCopyAttributeValue(icone, kAXURLAttribute as CFString, &v) == .success,
                      let url = v as? URL, url.standardizedFileURL.path == chemin else { continue }
                return AXUIElementPerformAction(icone, kAXPressAction as CFString) == .success
            }
        }
        return false
    }

    static func ouvrirApp(_ url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", url.path]
        try? p.run()
    }

    /// Lance un raccourci macOS avec les fichiers déposés dessus.
    func lancerRaccourci(_ nom: String, _ fournisseurs: [NSItemProvider]) {
        hide()   // la carte passe au-dessus de tout : on la ferme pour laisser voir ce que le raccourci ouvre
        let groupe = DispatchGroup()
        var fichiers: [URL] = []
        for f in fournisseurs {
            groupe.enter()
            _ = f.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { DispatchQueue.main.async { fichiers.append(url) } }
                DispatchQueue.main.async { groupe.leave() }
            }
        }
        groupe.notify(queue: .main) { Raccourcis.shared.lancer(nom, fichiers: fichiers) }
    }

    /// Ouvre les fichiers déposés sur une icône avec cette app. Une app déposée devient une favorite.
    func ouvrirAvec(_ fournisseurs: [NSItemProvider], _ app: URL) {
        for f in fournisseurs {
            _ = f.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async {
                    if url.pathExtension == "app" { self.favoriser(url); return }
                    self.hide()
                    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
    }
    /// Ajoute aux favorites les apps déposées sur le mini-Dock.
    // MARK: Déposer une app à un endroit précis du mini-Dock
    /// Les apps que transporte le glisser en cours (lues tout de suite, sans attendre le lâcher).
    static func appsGlissees() -> [URL] {
        let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { $0.pathExtension == "app" }.map(\.standardizedFileURL)
    }
    func previsualiserApp(_ url: URL, sur cible: String) {
        let chemin = url.path
        if apercuApp != chemin {
            annulerApercuApp()
            apercuApp = chemin
            apercuAjoutee = !Apps.shared.elements(config).contains { $0.id == chemin }
            if apercuAjoutee {
                config.appsMasquees.removeAll { $0 == chemin }
                if !config.appsFavorites.contains(chemin) { config.appsFavorites.append(chemin) }
            }
            store.appHorsDock = false
            store.appEnGlisse = URL(fileURLWithPath: chemin)
        }
        Apps.shared.deplacer(chemin, sur: cible, config)
    }
    /// L'app a été lâchée dans le mini-Dock : elle y reste, à cette place.
    func confirmerApp() {
        guard apercuApp != nil else { return }
        apercuApp = nil
        store.appEnGlisse = nil
    }
    /// Le glisser est reparti ailleurs : le mini-Dock redevient comme avant.
    func annulerApercuApp() {
        guard let chemin = apercuApp else { return }
        apercuApp = nil
        store.appEnGlisse = nil
        if apercuAjoutee {
            config.appsFavorites.removeAll { $0 == chemin }
            config.appsOrdre.removeAll { $0 == chemin }
        }
    }

    func ajouterApps(_ fournisseurs: [NSItemProvider]) {
        for f in fournisseurs {
            _ = f.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL, url.pathExtension == "app" else { return }
                DispatchQueue.main.async { self.favoriser(url) }
            }
        }
    }
    func favoriser(_ url: URL) {
        let chemin = url.standardizedFileURL.path
        if !config.appsFavorites.contains(chemin) { config.appsFavorites.append(chemin) }
        config.appsMasquees.removeAll { $0 == chemin }
    }
}
