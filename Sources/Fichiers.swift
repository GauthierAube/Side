// Les fichiers : lecture des dossiers, zones de dépôt (étagères), colonnes et le magasin de la carte (Store).
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// La partie « Finder » (barre latérale, grande zone, zones de dépôt) garde toujours la même largeur.
/// Chaque colonne épinglée s'ajoute à droite et élargit la carte, jusqu'à la largeur de l'écran.
enum Disposition {
    /// Largeur de la carte sans colonne épinglée.
    static func base(_ maxi: CGFloat) -> CGFloat {
        (maxi * CGFloat(min(max(Config.shared.largeurSeule, 0.35), 1))).rounded()
    }
    /// Largeur d'une colonne épinglée. En mode « rétrécir », elles se serrent quand la place manque.
    static func colonne(_ n: Int, _ maxi: CGFloat) -> CGFloat {
        let voulue = CGFloat(Config.shared.tailleColonne)
        guard n > 0, Config.shared.ajuster else { return voulue }
        return max(80, min(voulue, ((maxi - base(maxi)) / CGFloat(n)).rounded(.down) - 1))
    }
    /// Épaisseur occupée par le mini-Dock (icône, point, marges et espace avec la carte) ; 0 s'il est masqué.
    static var dock: CGFloat { Config.shared.apps ? CGFloat(Config.shared.tailleDock) + 20 : 0 }   // icône + 12 de marges + 8 d'espace
    static func carte(_ n: Int, _ maxi: CGFloat) -> CGFloat {
        min(maxi, base(maxi) + CGFloat(n) * (colonne(n, maxi) + 1))
    }
}

// MARK: - Fichiers

enum Tri: String, CaseIterable {
    case nom, date, taille, type
    var titre: String {
        switch self {
        case .nom: return String(localized: "Nom")
        case .date: return String(localized: "Date (les plus récents d'abord)")
        case .taille: return String(localized: "Taille")
        case .type: return String(localized: "Type")
        }
    }
}

enum Presentation: String { case liste, icones, colonnes, arbre }

/// Où en est un fichier d'iCloud Drive : sur le Mac, resté dans le nuage, en cours de téléchargement ou d'envoi.
enum Nuage { case aucun, aTelecharger, telechargement, envoi }

struct FileItem: Identifiable, Hashable {
    let url: URL
    let isFolder: Bool
    let date: Date
    var taille: Int = 0
    var nuage: Nuage = .aucun
    var id: URL { url }
    /// Nom affiché. Avec « Afficher toutes les extensions », les fichiers gardent leur extension ;
    /// les dossiers gardent leur nom traduit (Documents, Téléchargements…).
    var name: String {
        if !isFolder && Fichiers.extensions { return url.lastPathComponent }
        return FileManager.default.displayName(atPath: url.path)
    }
}

enum Fichiers {
    // Copies de deux réglages, lues pendant les tris (les réglages eux-mêmes ne sont pas encore prêts au lancement).
    static var extensions = UserDefaults.standard.object(forKey: "extensions") as? Bool ?? true
    static var nombreDossiers = UserDefaults.standard.object(forKey: "nombreDossiers") as? Int ?? 6
    static var dossiersEnHaut = UserDefaults.standard.object(forKey: "dossiersEnHaut") as? Bool ?? true
    static let home = FileManager.default.homeDirectoryForCurrentUser
    /// Vrai pour un serveur ou un dossier partagé du réseau, faux pour un disque branché au Mac.
    static func estReseau(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal == false
    }
    /// Les disques branchés (externes, images disque…) et les serveurs connectés, sans le disque de démarrage.
    static func disques() -> [URL] {
        (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [])
            .filter { $0.path != "/" }
    }
    /// Peut-on éjecter ce disque ? Disques externes (DD, SSD, clés), images disque, cartes mémoire et serveurs connectés.
    static func ejectable(_ url: URL) -> Bool {
        guard url.path != "/", let v = try? url.resourceValues(forKeys: [.volumeIsEjectableKey, .volumeIsRemovableKey,
                                                                        .volumeIsInternalKey, .volumeIsLocalKey]) else { return false }
        return v.volumeIsEjectable == true || v.volumeIsRemovable == true || v.volumeIsInternal == false || v.volumeIsLocal == false
    }

    /// Éjecte le disque, comme le bouton ⏏ du Finder. L'éjection peut prendre quelques secondes (le disque finit d'écrire) :
    /// elle se fait à part, et un disque encore utilisé par une application le dit dans une fenêtre.
    static func ejecter(_ url: URL) {
        let store = AppDelegate.shared.store
        // La carte qui affiche ce disque passe au dossier personnel : Side ne doit pas le garder occupé.
        if let c = store.navigateur.courant, c.path == url.path || c.path.hasPrefix(url.path + "/") { store.naviguer(.folder(home)) }
        store.columns.filter { $0.racine.map { $0.path == url.path || $0.path.hasPrefix(url.path + "/") } ?? false }
            .forEach { store.retirer($0) }
        let nom = Fichiers.nom(url)
        DialoguesSysteme.commun.surveiller(pendant: 20)   // une fenêtre de macOS sur ce disque doit passer devant Side
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                DispatchQueue.main.async { store.objectWillChange.send() }
            } catch {
                DispatchQueue.main.async {
                    let a = NSAlert()
                    a.alertStyle = .warning
                    a.messageText = String(localized: "Impossible d'éjecter « \(nom) »")
                    a.informativeText = String(localized: "Une application utilise peut-être encore un fichier de ce disque. Ferme-la, puis réessaie.")
                        + "\n\n" + error.localizedDescription
                    AppDelegate.shared.epingle = true
                    Devant.alerte(a)
                }
            }
        }
    }

    static let documents = home.appendingPathComponent("Documents")
    /// Le dossier Téléchargements : celui d'iCloud Drive s'il existe, sinon celui du Mac.
    static let downloads: URL = {
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Downloads")
        return FileManager.default.fileExists(atPath: icloud.path) ? icloud : home.appendingPathComponent("Downloads")
    }()
    static let desktop = home.appendingPathComponent("Desktop")
    static let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")

    /// Nom affiché d'un dossier (le dossier Téléchargements d'iCloud s'appelle « Downloads » sur le disque).
    static func nom(_ url: URL) -> String {
        if url.standardizedFileURL == downloads.standardizedFileURL { return String(localized: "Téléchargements") }
        if url.standardizedFileURL == icloud.standardizedFileURL { return "iCloud Drive" }
        return FileManager.default.displayName(atPath: url.path)
    }

    static let cles: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .contentModificationDateKey, .addedToDirectoryDateKey, .fileSizeKey,
        .isAliasFileKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemIsUploadingKey,
    ]

    /// Le dossier lui-même, puis ceux qui le contiennent, en remontant jusqu'au dossier personnel
    /// (ou jusqu'au disque pour un dossier situé ailleurs).
    static func ascendants(_ url: URL) -> [URL] {
        var liste: [URL] = [], u = url.standardizedFileURL
        while liste.count < 30 {
            liste.append(u)
            if u.path == "/" || u.path == home.path || u.path == icloud.path { break }
            u = u.deletingLastPathComponent()
        }
        return liste
    }

    /// Si c'est un alias ou un lien vers un dossier, rend ce dossier ; sinon rend l'adresse telle quelle.
    static func resoudre(_ url: URL) -> URL {
        guard (try? url.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true,
              let cible = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]),
              let v = try? cible.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
              v.isDirectory == true, v.isPackage != true else { return url }
        return cible
    }

    static func item(_ url: URL) -> FileItem {
        let v = try? url.resourceValues(forKeys: Set(cles))
        var dossier = (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
        // Un alias (ou un lien) vers un dossier se comporte comme ce dossier : on l'ouvre dans Side, pas dans le Finder.
        if !dossier, v?.isAliasFile == true { dossier = resoudre(url) != url }
        let date = max(v?.contentModificationDate ?? .distantPast, v?.addedToDirectoryDate ?? .distantPast)
        // iCloud Drive : le fichier est-il vraiment sur le Mac ?
        var nuage = Nuage.aucun
        if v?.isUbiquitousItem == true {
            if v?.ubiquitousItemIsDownloading == true { nuage = .telechargement }
            else if v?.ubiquitousItemDownloadingStatus == .notDownloaded { nuage = .aTelecharger }
            else if v?.ubiquitousItemIsUploading == true { nuage = .envoi }
        }
        return FileItem(url: url, isFolder: dossier, date: date, taille: v?.fileSize ?? 0, nuage: nuage)
    }

    static func contenu(_ url: URL, tri: Tri) -> [FileItem] {
        var urls = (try? FileManager.default.contentsOfDirectory(
            at: resoudre(url), includingPropertiesForKeys: cles, options: [.skipsHiddenFiles])) ?? []
        // Comme le Finder : le dossier Applications montre aussi les apps d'Apple (Mail, Notes, Photos…),
        // que macOS range à part, dans le dossier Système. Pareil pour Utilitaires.
        let chemin = resoudre(url).standardizedFileURL.path
        if chemin == "/Applications" || chemin == "/Applications/Utilities" {
            let noms = Set(urls.map(\.lastPathComponent))
            let apple = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: "/System" + chemin), includingPropertiesForKeys: cles, options: [.skipsHiddenFiles])) ?? []
            urls += apple.filter { !noms.contains($0.lastPathComponent) }
        }
        let items = urls.map(item)
        func parNom(_ a: FileItem, _ b: FileItem) -> Bool {
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        switch tri {
        case .date: return items.sorted { $0.date > $1.date }
        case .taille: return items.sorted { $0.taille > $1.taille }
        case .type:
            return items.sorted {
                let (x, y) = ($0.url.pathExtension.lowercased(), $1.url.pathExtension.lowercased())
                return x == y ? parNom($0, $1) : x < y
            }
        case .nom:
            return items.sorted { dossiersEnHaut && $0.isFolder != $1.isFolder ? $0.isFolder : parNom($0, $1) }
        }
    }

    /// Les dossiers favoris de la barre latérale du Finder, dans son ordre.
    /// Lus par l'ancien service d'Apple (déconseillé mais toujours là) : le fichier où macOS les range est
    /// protégé, et le lire directement demanderait l'autorisation « Accès complet au disque ».
    static func favorisFinder() -> [URL] {
        guard let liste = LSSharedFileListCreate(nil, kLSSharedFileListFavoriteItems.takeUnretainedValue(), nil)?.takeRetainedValue()
        else { return [] }
        var graine: UInt32 = 0
        let elements = LSSharedFileListCopySnapshot(liste, &graine)?.takeRetainedValue() as? [LSSharedFileListItem] ?? []
        var vus = Set<String>()
        return elements.compactMap { e -> URL? in
            // On ne garde que les vrais dossiers encore présents (pas AirDrop, ni un serveur débranché).
            guard let url = LSSharedFileListItemCopyResolvedURL(e, 0, nil)?.takeRetainedValue() as URL?, url.isFileURL else { return nil }
            var dossier: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &dossier), dossier.boolValue,
                  url.pathExtension != "app", vus.insert(url.standardizedFileURL.path).inserted else { return nil }
            return url.standardizedFileURL
        }
    }

    /// Les dossiers Inbox + PARA : ceux de Documents qui commencent par deux chiffres.
    static func para() -> [FileItem] {
        contenu(documents, tri: .nom).filter { item in
            let n = item.url.lastPathComponent
            return item.isFolder && n.count > 2 && n.prefix(2).allSatisfy(\.isNumber)
        }
    }

    private static let verrou = NSLock()
    private static var cache: (date: Date, items: [FileItem])?

    /// Tous les fichiers modifiés ou reçus récemment, du plus récent au plus ancien.
    /// Le résultat est gardé quelques secondes : deux colonnes s'en servent.
    private static func fichiersRecents() -> [FileItem] {
        verrou.lock()
        defer { verrou.unlock() }
        if let c = cache, Date().timeIntervalSince(c.date) < 5 { return c.items }
        let limite = Date().addingTimeInterval(-Reglages.joursRecents * 86400)
        var trouves: [FileItem] = []
        for racine in [documents, downloads, desktop] {
            guard let e = FileManager.default.enumerator(
                at: racine, includingPropertiesForKeys: cles,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                let it = item(url)
                if it.isFolder {
                    if url.lastPathComponent == "node_modules" { e.skipDescendants() }
                    continue
                }
                if it.date > limite { trouves.append(it) }
            }
        }
        trouves.sort { $0.date > $1.date }
        cache = (Date(), trouves)
        return trouves
    }

    static func recents() -> [FileItem] { Array(fichiersRecents().prefix(Reglages.nombreRecents)) }

    /// Recherche Spotlight dans un dossier et ses sous-dossiers. Les noms qui contiennent le texte passent en premier.
    static func chercher(_ texte: String, dans dossier: URL?) -> [FileItem] {
        // Un texte qui commence par un tiret serait pris pour une option de la commande de recherche : on l'en débarrasse.
        let texte = String(texte.drop { $0 == "-" })
        guard !texte.isEmpty else { return [] }
        let p = Process(), sortie = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = dossier.map { ["-onlyin", resoudre($0).path, texte] } ?? [texte]   // sans dossier : tout le Mac
        p.standardOutput = sortie
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        let data = sortie.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let items = String(decoding: data, as: UTF8.self).split(separator: "\n").prefix(300)
            .map { item(URL(fileURLWithPath: String($0))) }
        func parNom(_ i: FileItem) -> Bool { i.name.localizedCaseInsensitiveContains(texte) }
        return items.sorted { a, b in parNom(a) != parNom(b) ? parNom(a) : a.date > b.date }
    }

    /// Les fichiers et dossiers qui portent un tag du Finder (recherche Spotlight).
    static func avecTag(_ nom: String) -> [FileItem] {
        let p = Process(), sortie = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["kMDItemUserTags == \"" + nom.replacingOccurrences(of: "\"", with: "\\\"") + "\""]
        p.standardOutput = sortie
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        let data = sortie.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let chemins = String(decoding: data, as: UTF8.self).split(separator: "\n").prefix(300)
        return chemins.map { item(URL(fileURLWithPath: String($0))) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Si ce dossier est un paquet, ou se trouve à l'intérieur d'un paquet, rend le dossier qui contient le paquet.
    static func horsPaquet(_ url: URL) -> URL {
        var resultat = url, u = url
        while u.path != "/" && u.path != home.path {
            if (try? u.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { resultat = u.deletingLastPathComponent() }
            u = u.deletingLastPathComponent()
        }
        return resultat
    }

    /// Les dossiers où il s'est passé quelque chose récemment, du plus récent au plus ancien.
    static func dossiersRecents() -> [FileItem] {
        var vus = Set<URL>(), resultat: [FileItem] = []
        for f in fichiersRecents() {
            // Un projet Logic, une bibliothèque Photos… sont des « paquets » : des dossiers que macOS montre comme
            // un seul fichier. On ne les liste pas comme des dossiers : on remonte au vrai dossier qui les contient.
            let dossier = horsPaquet(f.url.deletingLastPathComponent())
            guard vus.insert(dossier).inserted else { continue }
            resultat.append(FileItem(url: dossier, isFolder: true, date: f.date))
            if resultat.count >= nombreDossiers { break }
        }
        return resultat
    }
}

// MARK: - Étagère

/// L'étagère garde des fichiers sous la main sans les déplacer : elle ne retient que leur emplacement.
enum Etagere {
    static let maximum = 4          // quatre zones au plus : empilées, elles tiennent sur la hauteur du Finder
    /// Nombre de zones de dépôt : une seule au départ, on peut en ajouter en dessous.
    static var nombre: Int {
        get {
            if let n = UserDefaults.standard.object(forKey: "etagereNombre") as? Int { return min(max(n, 1), maximum) }
            return max(1, ((0..<3).last { !chemins($0).isEmpty } ?? 0) + 1)   // garde les zones déjà remplies
        }
        set { UserDefaults.standard.set(newValue, forKey: "etagereNombre") }
    }
    /// Supprime une zone : les suivantes remontent d'un cran.
    static func supprimer(_ i: Int) {
        let n = nombre
        guard n > 1 else { return }
        for j in i..<(n - 1) { ecrire(chemins(j + 1), j) }
        ecrire([], n - 1)
        nombre = n - 1
    }
    private static func cle(_ i: Int) -> String { i == 0 ? "etagere" : "etagere\(i)" }
    private static func chemins(_ i: Int) -> [String] { UserDefaults.standard.stringArray(forKey: cle(i)) ?? [] }
    private static func ecrire(_ c: [String], _ i: Int) { UserDefaults.standard.set(c, forKey: cle(i)) }

    /// Un fichier d'un disque débranché (ou d'un serveur déconnecté) : il n'existe pas en ce moment, mais il reviendra.
    /// Side ne doit pas l'oublier pour autant (avant le 15/11/2026, la zone se vidait à l'éjection du disque).
    static func surDisqueAbsent(_ chemin: String) -> Bool {
        let parties = chemin.split(separator: "/", omittingEmptySubsequences: true)
        guard parties.count >= 2, parties[0] == "Volumes" else { return false }
        return !FileManager.default.fileExists(atPath: "/Volumes/" + parties[1])
    }
    /// La zone ne contient plus rien, ni à l'écran ni sur un disque débranché.
    static func estVide(_ i: Int) -> Bool {
        !chemins(i).contains { FileManager.default.fileExists(atPath: $0) || surDisqueAbsent($0) }
    }

    static func items(_ i: Int) -> [FileItem] {
        chemins(i).filter { FileManager.default.fileExists(atPath: $0) }
            .map { Fichiers.item(URL(fileURLWithPath: $0)) }
    }
    /// Identité d'un fichier sur le disque : la même quel que soit le chemin par lequel on y arrive.
    private static func identite(_ chemin: String) -> NSObject? {
        (try? URL(fileURLWithPath: chemin).resourceValues(forKeys: [.fileResourceIdentifierKey]))?
            .fileResourceIdentifier as? NSObject
    }

    /// Ajoute un élément à une zone. Le même fichier déposé deux fois n'apparaît qu'une fois.
    @discardableResult
    static func ajouter(_ url: URL, _ i: Int) -> Bool {
        let c = url.resolvingSymlinksInPath().standardizedFileURL.path
        let existants = chemins(i)
        if existants.contains(c) || existants.contains(url.path) { return false }
        if let nouvelle = identite(c), existants.contains(where: { identite($0)?.isEqual(nouvelle) == true }) { return false }
        ecrire(existants + [c], i)
        return true
    }

    /// Retire les doublons déjà présents dans une zone : même fichier, ou même contenu.
    static func dedoublonner(_ i: Int) {
        var gardes: [String] = []
        for chemin in chemins(i) {
            let double = gardes.contains { autre in
                if let a = identite(chemin), let b = identite(autre), a.isEqual(b) { return true }
                // Même contenu : seulement pour les fichiers que Side a créés lui-même (une image déposée deux fois).
                // Deux fichiers à toi qui se ressemblent restent tous les deux.
                let depot = AppDelegate.dossierDepot.path + "/"
                guard chemin.hasPrefix(depot), autre.hasPrefix(depot) else { return false }
                return FileManager.default.contentsEqual(atPath: chemin, andPath: autre)
            }
            if !double { gardes.append(chemin) }
        }
        if gardes.count != chemins(i).count { ecrire(gardes, i) }
    }

    /// Les fichiers déjà présents dans une zone (pour reconnaître une image déposée une seconde fois).
    static func fichiers(_ i: Int) -> [URL] { chemins(i).map { URL(fileURLWithPath: $0) } }
    static func retirer(_ url: URL, _ i: Int) {
        ecrire(chemins(i).filter { $0 != url.standardizedFileURL.path && $0 != url.path }, i)
    }
    static func vider(_ i: Int) { ecrire([], i) }
    /// Un fichier rangé dans une zone vient d'être renommé : la zone retient son nouvel emplacement, à la même place.
    /// Rend faux si aucune zone ne le contenait.
    @discardableResult
    static func renommer(_ ancien: URL, _ nouveau: URL) -> Bool {
        let anciens: Set<String> = [ancien.path, ancien.standardizedFileURL.path, ancien.resolvingSymlinksInPath().standardizedFileURL.path]
        let c = nouveau.resolvingSymlinksInPath().standardizedFileURL.path
        var trouve = false
        for i in 0..<maximum where chemins(i).contains(where: anciens.contains) {
            ecrire(chemins(i).map { anciens.contains($0) ? c : $0 }, i)
            trouve = true
        }
        return trouve
    }
    /// Oublie les fichiers qui ne sont plus à l'endroit retenu (déplacés ou supprimés depuis).
    static func purger(_ i: Int) {
        let restants = chemins(i).filter { FileManager.default.fileExists(atPath: $0) || surDisqueAbsent($0) }
        if restants.count != chemins(i).count { ecrire(restants, i) }
    }
}

// MARK: - Colonnes

final class Column: ObservableObject, Identifiable {
    enum Kind: Hashable {
        case hub, recents, dossiers, etagere, presse, folder(URL), tag(String)
        var code: String {
            switch self {
            case .hub: return "hub"
            case .recents: return "recents"
            case .etagere: return "etagere"
            case .dossiers: return "dossiers"
            case .presse: return "presse"
            case .tag(let nom): return "tag:" + nom
            case .folder(let u): return "folder:" + u.path
            }
        }
        init?(code: String) {
            if code == "hub" { self = .hub }
            else if code == "recents" { self = .recents }
            else if code == "etagere" { self = .etagere }
            else if code == "dossiers" { self = .dossiers }
            else if code == "presse" { self = .presse }
            else if code.hasPrefix("tag:") { self = .tag(String(code.dropFirst(4))) }
            else if code.hasPrefix("folder:") { self = .folder(URL(fileURLWithPath: String(code.dropFirst(7)))) }
            else { return nil }
        }
    }

    let id = UUID()
    let kind: Kind
    var indexEtagere = 0                     // laquelle des zones de dépôt (si c'en est une)
    @Published var pile: [URL] = []          // dossiers ouverts dans la colonne
    @Published var items: [FileItem] = []
    @Published var charge = false
    /// Présentation en colonnes : le contenu de chaque niveau, du dossier de départ au dossier ouvert.
    @Published var niveaux: [[FileItem]] = []
    private let cleVue: String
    @Published var tri: Tri {
        didSet { UserDefaults.standard.set(tri.rawValue, forKey: "tri2:" + kind.code); reload() }
    }
    @Published var presentation: Presentation {
        didSet { UserDefaults.standard.set(presentation.rawValue, forKey: cleVue); reload() }
    }
    /// Nombre de colonnes que la grille affiche en ce moment (pour les flèches haut et bas).
    var colonnesVisibles = 1
    /// Présentation en icônes : nombre de colonnes de la grille (0 = autant que la place le permet).
    @Published var colonnesGrille: Int = 0 {
        didSet { UserDefaults.standard.set(colonnesGrille, forKey: "grille:" + cleVue) }
    }
    private var generation = 0

    /// `navigateur` : la grande zone garde la même présentation d'un dossier à l'autre.
    init(kind: Kind, navigateur: Bool = false) {
        self.kind = kind
        // Les dossiers récents gardent leur propre présentation, même dans la grande zone : en grille par défaut.
        cleVue = navigateur && kind != .dossiers ? "vue:navigateur" : "vue:" + kind.code
        let d = UserDefaults.standard
        tri = d.string(forKey: "tri2:" + kind.code).flatMap(Tri.init)
            ?? (kind == .folder(Fichiers.downloads) ? .date : .nom)
        presentation = d.string(forKey: cleVue).flatMap(Presentation.init)
            ?? (cleVue == "vue:navigateur" ? .colonnes : (kind == .dossiers || kind == .recents ? .icones : .liste))
        colonnesGrille = d.integer(forKey: "grille:" + cleVue)
    }

    var racine: URL? { if case .folder(let u) = kind { return u } else { return nil } }
    var courant: URL? { pile.last ?? racine }
    var estEtagere: Bool { kind == .etagere && pile.isEmpty }
    var peutRevenir: Bool { !pile.isEmpty }
    var peutTrier: Bool { kind != .recents && courant != nil }

    var titre: String {
        if let u = pile.last { return FileManager.default.displayName(atPath: u.path) }
        switch kind {
        case .hub: return "Inbox & PARA"
        case .recents: return String(localized: "Fichiers récents")
        case .etagere: return String(localized: "Étagère")
        case .dossiers: return String(localized: "Dossiers récents")
        case .presse: return String(localized: "Presse-papiers")
        case .tag(let nom): return nom
        case .folder(let u):
            return u == Fichiers.downloads ? String(localized: "Téléchargements") : FileManager.default.displayName(atPath: u.path)
        }
    }
    var symbole: String {
        if !pile.isEmpty { return "folder" }
        switch kind {
        case .hub: return "tray.full"
        case .recents: return "clock"
        case .etagere: return "tray.and.arrow.down"
        case .dossiers: return "clock.arrow.circlepath"
        case .presse: return "doc.on.clipboard"
        case .tag: return "tag"
        case .folder(let u): return u == Fichiers.downloads ? "arrow.down.circle" : "folder"
        }
    }

    private var avant: [URL] = []            // dossiers quittés avec « Précédent », pour « Suivant »
    var peutAvancer: Bool { !avant.isEmpty }
    /// Texte tapé dans « Rechercher » : ne garde que les éléments dont le nom le contient.
    @Published var filtre = "" { didSet { if filtre != oldValue { lancerRecherche() } } }
    /// Résultats de la recherche Spotlight (nil = pas de recherche en cours d'affichage).
    @Published var resultats: [FileItem]?
    @Published var rechercheEnCours = false
    private var rechercheGen = 0
    private var dernierTexte = ""
    var visibles: [FileItem] { resultats ?? items }
    func filtrer(_ liste: [FileItem]) -> [FileItem] { liste }

    /// Cherche avec Spotlight dans le dossier affiché et tous ses sous-dossiers
    /// (noms et contenu des fichiers), après une courte pause pour laisser taper.
    private func lancerRecherche() {
        let texte = filtre.trimmingCharacters(in: .whitespaces)
        // Même texte (à un espace près) : on garde les résultats affichés ou la recherche en cours, sans relancer
        // (et sans annuler la recherche en cours : le numéro ne change qu'après).
        if texte.count >= 2, texte == dernierTexte, resultats != nil || rechercheEnCours { return }
        rechercheGen += 1
        let g = rechercheGen
        guard texte.count >= 2 else { dernierTexte = ""; resultats = nil; rechercheEnCours = false; return }
        dernierTexte = texte
        rechercheEnCours = true
        let dossier: URL? = Config.shared.rechercheMac ? nil : (courant ?? Fichiers.home)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
            let encore = DispatchQueue.main.sync { g == self.rechercheGen }
            guard encore else { return }
            let trouves = Fichiers.chercher(texte, dans: dossier)
            DispatchQueue.main.async {
                guard g == self.rechercheGen else { return }
                self.resultats = trouves
                self.rechercheEnCours = false
            }
        }
    }

    func entrer(_ url: URL) { avant = []; filtre = ""; pile.append(url); reload() }
    func revenir() { if let u = pile.popLast() { avant.append(u) }; filtre = ""; reload() }
    func avancer() { if let u = avant.popLast() { filtre = ""; pile.append(u); reload() } }
    /// Présentation en colonnes : ouvre un dossier à partir du niveau cliqué (les niveaux suivants se referment).
    func ouvrirNiveau(_ url: URL, _ niveau: Int) { avant = []; filtre = ""; pile = Array(pile.prefix(niveau)) + [url]; reload() }
    func tronquer(_ niveau: Int) { if pile.count > niveau { pile = Array(pile.prefix(niveau)); reload() } }

    func reload() {
        generation += 1
        let g = generation
        let kind = self.kind, courant = self.courant, tri = self.tri, zoneDepot = self.indexEtagere
        let racine = self.racine, pile = self.pile, enColonnes = presentation == .colonnes
        charge = items.isEmpty
        DispatchQueue.global(qos: .userInitiated).async {
            func depart() -> [FileItem] {
                if let racine { return Fichiers.contenu(racine, tri: tri) }
                switch kind {
                case .recents: return Fichiers.recents()
                case .etagere: return Etagere.items(zoneDepot)
                case .dossiers: return Fichiers.dossiersRecents()
                case .tag(let nom): return Fichiers.avecTag(nom)
                case .presse: return []
                default: return Fichiers.para()
                }
            }
            let resultat = courant.map { Fichiers.contenu($0, tri: tri) } ?? depart()
            let niveaux = enColonnes ? [pile.isEmpty ? resultat : depart()] + pile.map { Fichiers.contenu($0, tri: tri) } : []
            DispatchQueue.main.async {
                guard g == self.generation else { return }
                self.items = resultat
                self.niveaux = niveaux
                self.charge = false
            }
        }
    }
}

final class Store: ObservableObject {
    /// ⌘F : le champ « Rechercher » de la grande zone s'ouvre (chaque demande incrémente ce nombre).
    @Published var demandeRecherche = 0
    @Published var columns: [Column] = []
    @Published var largeurMax: CGFloat = 1400   // largeur disponible sur l'écran de la carte
    @Published var margeHaut: CGFloat = 0   // place laissée à l'encoche de l'écran
    private let cle = "colonnes"

    /// Barre latérale : les favoris, le dossier affiché dans la grande zone, et l'étagère.
    @Published var favoris: [URL] = []
    /// Les onglets de la grande zone, comme dans le Finder. `navigateur` est l'onglet affiché.
    @Published var onglets: [Column] = [Column(kind: .recents, navigateur: true)]
    @Published var ongletActif = 0
    var navigateur: Column {
        get { onglets[min(ongletActif, onglets.count - 1)] }
        set { onglets[min(ongletActif, onglets.count - 1)] = newValue }
    }
    var courante: Column.Kind { navigateur.kind }

    func nouvelOnglet() {
        let ici = navigateur.courant.map { Column.Kind.folder($0) } ?? navigateur.kind
        let c = Column(kind: ici, navigateur: true)
        onglets.append(c)
        ongletActif = onglets.count - 1
        c.reload()
    }
    func fermerOnglet(_ i: Int) {
        guard onglets.count > 1, onglets.indices.contains(i) else { return }
        onglets.remove(at: i)
        if ongletActif >= i { ongletActif = max(0, ongletActif - 1) }
    }
    @Published var etageres: [Column] = Store.zones()
    /// Un glisser-déposer est en cours : c'est le moment de montrer les cibles de dépôt.
    @Published var glisse = false
    /// Le panneau des applications est ouvert, sous le mini-Dock.
    @Published var lanceurOuvert = false
    /// Largeur du mini-Dock, pour que le panneau des applications ait la même.
    @Published var largeurDock: CGFloat = 0
    /// L'icône du mini-Dock qu'on est en train de glisser : elle n'est plus affichée dans le mini-Dock.
    @Published var appEnGlisse: URL?
    /// L'icône glissée est sortie du mini-Dock : elle le quitte, et le lâcher la retirera.
    @Published var appHorsDock = false
    /// Présentation de bienvenue : numéro de l'étape affichée par-dessus la carte (nil = pas de présentation).
    @Published var accueil: Int?
    func finAccueil() {
        accueil = nil
        UserDefaults.standard.set(true, forKey: "accueilVu")
    }
    /// Ce qu'on fait glisser contient un dossier (ou une entrée de la barre latérale) : on peut l'épingler en colonne.
    @Published var glisseDossier = false
    /// Au moins une zone de dépôt contient quelque chose : elle reste alors affichée, en petit.
    @Published var depotRempli = false
    /// La zone de dépôt flottante dépliée en grille (son numéro), s'il y en a une.
    @Published var depotDeplie: Int? = nil
    /// Taille des zones flottantes (1 = 198 × 207 points) : réduite pour que la pile de zones tienne sur la hauteur du Finder.
    @Published var echelleDepot: CGFloat = 1
    /// Il y a de la place à droite de la carte : les zones de dépôt y flottent, en carrés.
    /// Sinon (carte en pleine largeur, ou sur le côté), elles s'affichent dans la grande zone.
    @Published var depotDehors = false
    @Published var depotAGauche = false
    private var suiviZones: [AnyCancellable] = []

    func surveillerZones() {
        suiviZones = etageres.map { zone in
            zone.$items.receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                let rempli = self.etageres.contains { !$0.items.isEmpty }
                if rempli != self.depotRempli { self.depotRempli = rempli }
            }
        }
    }

    private static func zones() -> [Column] {
        (0..<Etagere.nombre).map { i in
            let c = Column(kind: .etagere)
            c.indexEtagere = i
            return c
        }
    }
    func ajouterZone() {
        guard Etagere.nombre < Etagere.maximum else { return }
        Etagere.nombre += 1
        etageres = Store.zones()
        surveillerZones()
        etageres.forEach { $0.reload() }
    }
    /// Retire les zones de dépôt vides, en en gardant toujours au moins une.
    func nettoyerZones() {
        var change = false
        for i in stride(from: etageres.count - 1, through: 0, by: -1)
        where Etagere.nombre > 1 && Etagere.estVide(i) {
            Etagere.supprimer(i)
            change = true
        }
        guard change else { return }
        etageres = Store.zones()
        surveillerZones()
        etageres.forEach { $0.reload() }
    }
    func supprimerZone(_ i: Int) {
        Etagere.supprimer(i)
        etageres = Store.zones()
        surveillerZones()
        etageres.forEach { $0.reload() }
    }

    init() {
        let d = UserDefaults.standard
        if let enregistres = d.stringArray(forKey: "favoris") {
            favoris = enregistres.map { URL(fileURLWithPath: $0) }
        } else {
            // Premier lancement : on reprend les favoris de la barre latérale du Finder. S'il n'y en a pas,
            // les dossiers classiques. Enregistré tout de suite : ensuite, les favoris de Side vivent leur vie.
            let finder = Fichiers.favorisFinder()
            favoris = finder.isEmpty
                ? [.desktopDirectory, .documentDirectory, .downloadsDirectory].compactMap {
                    FileManager.default.urls(for: $0, in: .userDomainMask).first }
                : finder
            d.set(favoris.map(\.path), forKey: "favoris")
        }
        // À droite : des dossiers, ou des entrées de la barre latérale qu'on a choisi d'épingler.
        var kinds = (d.stringArray(forKey: cle) ?? []).compactMap { Column.Kind(code: $0) }
        kinds = kinds.filter { $0 != .etagere && $0 != .hub }
        if !d.bool(forKey: "migrationFinder") {   // une fois : pas de doublon avec les favoris
            d.set(true, forKey: "migrationFinder")
            kinds.removeAll { k in favoris.contains { .folder($0) == k } }
            d.set(kinds.map(\.code), forKey: cle)
        }
        columns = kinds.map { Column(kind: $0) }
        let depart = Config.shared.ouverture.isEmpty
            ? d.string(forKey: "dernier").flatMap { Column.Kind(code: $0) } ?? .recents
            : .folder(URL(fileURLWithPath: Config.shared.ouverture))
        let premier = Column(kind: depart, navigateur: true)
        // « Le dernier dossier consulté » : on retrouve aussi les sous-dossiers où l'on était entré.
        if Config.shared.ouverture.isEmpty {
            premier.pile = (d.stringArray(forKey: "dernierChemin") ?? []).map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        onglets = [premier]
        surveillerZones()
    }

    /// Affiche un dossier (ou les récents) dans la grande zone.
    func naviguer(_ kind: Column.Kind) {
        navigateur = Column(kind: kind, navigateur: true)
        navigateur.reload()
        UserDefaults.standard.set(kind.code, forKey: "dernier")
        // Le chemin retenu était celui de l'ancien dossier : sans cela, un arrêt de Side carte ouverte les mélangeait.
        UserDefaults.standard.set([String](), forKey: "dernierChemin")
    }
    /// Retient où l'on se trouve, pour le retrouver au prochain lancement de Side.
    func memoriser() {
        UserDefaults.standard.set(navigateur.kind.code, forKey: "dernier")
        UserDefaults.standard.set(navigateur.pile.map(\.path), forKey: "dernierChemin")
    }
    func ajouterFavori(_ url: URL) {
        let u = url.standardizedFileURL
        guard !favoris.contains(where: { $0.standardizedFileURL == u }) else { return }
        favoris.append(u)
        UserDefaults.standard.set(favoris.map(\.path), forKey: "favoris")
    }
    func retirerFavori(_ url: URL) {
        favoris.removeAll { $0 == url }
        UserDefaults.standard.set(favoris.map(\.path), forKey: "favoris")
    }

    func contient(_ kind: Column.Kind) -> Bool { columns.contains { $0.kind == kind } }

    func ajouter(_ kind: Column.Kind) {
        guard !contient(kind) else { return }
        let c = Column(kind: kind)
        columns.append(c)
        c.reload()
        sauver()
    }
    func retirer(_ column: Column) {
        columns.removeAll { $0.id == column.id }
        sauver()
    }
    var glissee: Column?   // colonne en cours de déplacement

    func deplacer(_ colonne: Column, vers cible: Column) {
        guard let de = columns.firstIndex(where: { $0.id == colonne.id }),
              let vers = columns.firstIndex(where: { $0.id == cible.id }), de != vers else { return }
        columns.move(fromOffsets: IndexSet(integer: de), toOffset: vers > de ? vers + 1 : vers)
        sauver()
    }
    func reloadAll() { (columns + onglets + etageres).forEach { $0.reload() } }
    private func sauver() { UserDefaults.standard.set(columns.map(\.kind.code), forKey: cle) }
}
