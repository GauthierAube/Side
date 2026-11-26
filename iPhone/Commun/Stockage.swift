// Ce que l'app, le widget et l'extension « Partager » ont en commun (26/11/2026).
// - Le dossier Side d'iCloud Drive (choisi une fois dans l'app, marque-page rangé dans le groupe d'apps).
// - L'historique : même format que PresseSynchro.swift sur le Mac.
// - La boîte : ce que l'extension « Partager » n'a pas pu écrire dans iCloud, versé dans l'historique à la prochaine ouverture.
// - L'aperçu : les derniers éléments (et leurs vignettes) pour le widget.
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Ce que l'app, le widget et l'extension se partagent passe par le trousseau (groupe commun, sans réglage sur le
/// compte développeur) : le marque-page du dossier Side et la boîte. Chacun garde ses autres fichiers chez lui.
enum Trousseau {
    private static func requete(_ cle: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "fr.gauthieraube.side-presse",
         kSecAttrAccount as String: cle]
    }
    static func lire(_ cle: String) -> Data? {
        var q = requete(cle)
        q[kSecReturnData as String] = true
        var r: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess ? r as? Data : nil
    }
    static func ecrire(_ data: Data?, _ cle: String) {
        SecItemDelete(requete(cle) as CFDictionary)
        guard let data else { return }
        var q = requete(cle)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}

enum Groupe {
    /// Le dossier propre à l'app ou à l'extension qui tourne (aperçu et vignettes du widget).
    static var conteneur: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("Side", isDirectory: true)
    }
}

struct Element: Codable, Identifiable, Equatable {
    var id: UUID; var date: Date; var modifie: Date; var texte: String?; var image: String?; var epingle: Bool
}
struct Historique: Codable { var elements: [Element]; var supprimes: [String: Date] }
struct Lien: Codable, Identifiable, Equatable { var id: UUID; var titre: String; var texte: String; var groupe: String? }
struct Liens: Codable { var liens: [Lien]; var date: Date }

enum Stockage {
    static let duree: TimeInterval = 7 * 86400
    static let maximum = 300
    static let cle = "side.dossierSide"

    // MARK: Le dossier Side

    static func dossier() -> URL? {
        guard let data = Trousseau.lire(cle) ?? UserDefaults.standard.data(forKey: "dossierSide") else { return nil }
        var perime = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &perime) else { return nil }
        if perime { _ = garder(url) }
        return url
    }

    @discardableResult
    static func garder(_ url: URL) -> Bool {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData() else { return false }
        Trousseau.ecrire(data, cle)
        return true
    }

    /// Ouvre le dossier le temps du travail. nil si le dossier n'est pas choisi ou inaccessible.
    static func acceder<T>(_ travail: (URL) -> T?) -> T? {
        guard let d = dossier() else { return nil }
        let ok = d.startAccessingSecurityScopedResource()
        defer { if ok { d.stopAccessingSecurityScopedResource() } }
        return travail(d)
    }

    // MARK: Lire et écrire

    static func lireJSON<T: Decodable>(_ url: URL, _ type: T.Type) -> T? {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var resultat: T?
        var erreur: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &erreur) { u in
            if let data = try? Data(contentsOf: u) { resultat = try? JSONDecoder().decode(T.self, from: data) }
        }
        return resultat
    }

    static func historique(dans d: URL) -> Historique? { lireJSON(d.appendingPathComponent("Presse-papiers.json"), Historique.self) }
    static func liens(dans d: URL) -> Liens? { lireJSON(d.appendingPathComponent("Liens enregistrés.json"), Liens.self) }

    static func visibles(_ h: Historique) -> [Element] {
        let limite = Date().addingTimeInterval(-duree)
        return h.elements
            .filter { e in (e.epingle || e.date > limite) && !(h.supprimes[e.id.uuidString].map { $0 >= e.modifie } ?? false) }
            .sorted { $0.date > $1.date }
    }

    /// Relit le fichier, applique le changement, le réécrit : ce que les Mac ont ajouté entre-temps n'est jamais perdu.
    static func modifier(dans d: URL, _ changement: (inout Historique, URL) -> Void) -> Historique? {
        let url = d.appendingPathComponent("Presse-papiers.json")
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var resultat: Historique?
        var erreur: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &erreur) { u in
            var h = Historique(elements: [], supprimes: [:])
            if let data = try? Data(contentsOf: u) {
                guard let lu = try? JSONDecoder().decode(Historique.self, from: data) else { return }   // illisible : on n'écrase rien
                h = lu
            }
            changement(&h, d)
            let limite = Date().addingTimeInterval(-duree)
            h.supprimes = h.supprimes.filter { $0.value > limite }
            h.elements.sort { $0.date > $1.date }
            while h.elements.count > maximum, let i = h.elements.lastIndex(where: { !$0.epingle }) { h.elements.remove(at: i) }
            if (try? JSONEncoder().encode(h).write(to: u, options: .atomic)) != nil { resultat = h }
        }
        return resultat
    }

    // MARK: Les ajouts

    static func ajout(texte: String) -> (inout Historique, URL) -> Void {
        { h, _ in
            let maintenant = Date()
            if let i = h.elements.firstIndex(where: { $0.texte == texte && $0.image == nil }) {
                h.elements[i].date = maintenant; h.elements[i].modifie = maintenant   // déjà là : remonte en haut
            } else {
                h.elements.append(Element(id: UUID(), date: maintenant, modifie: maintenant, texte: texte, image: nil, epingle: false))
            }
        }
    }

    static func ajout(png: Data) -> (inout Historique, URL) -> Void {
        { h, d in
            let nom = UUID().uuidString + ".png"
            let images = d.appendingPathComponent("Presse-papiers images", isDirectory: true)
            try? FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            guard (try? png.write(to: images.appendingPathComponent(nom))) != nil else { return }
            let maintenant = Date()
            h.elements.append(Element(id: UUID(), date: maintenant, modifie: maintenant, texte: nil, image: nom, epingle: false))
        }
    }

    /// Ajoute tout de suite dans iCloud ; sinon dans la boîte (l'app la videra à sa prochaine ouverture).
    static func ajouter(texte: String) {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if acceder({ modifier(dans: $0, ajout(texte: texte)) }) == nil { Boite.deposer(texte: texte, png: nil) }
    }

    static func ajouter(png: Data) {
        if acceder({ modifier(dans: $0, ajout(png: png)) }) == nil { Boite.deposer(texte: nil, png: png) }
    }
}

// MARK: La boîte (en attente d'iCloud)

/// Les textes que l'extension « Partager » n'a pas pu écrire dans iCloud, versés dans l'historique par l'app.
enum Boite {
    private static let cle = "side.boite"
    private static func lire() -> [String] {
        Trousseau.lire(cle).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    }
    static func deposer(texte: String?, png: Data?) {
        guard let texte else { return }   // une image ne tient pas dans le trousseau
        Trousseau.ecrire(try? JSONEncoder().encode(lire() + [texte]), cle)
    }
    static func vider() {
        var reste = lire()
        guard !reste.isEmpty else { return }
        while let t = reste.first {
            guard Stockage.acceder({ Stockage.modifier(dans: $0, Stockage.ajout(texte: t)) }) != nil else { break }
            reste.removeFirst()
        }
        Trousseau.ecrire(reste.isEmpty ? nil : try? JSONEncoder().encode(reste), cle)
    }
}

// MARK: L'aperçu pour le widget

struct ApercuElement: Codable, Identifiable, Equatable {
    var id: UUID; var texte: String?; var vignette: String?; var epingle: Bool
    var lien: URL { URL(string: "side-presse://copier?id=\(id.uuidString)")! }
}

enum Apercu {
    static let nombre = 8
    private static var fichier: URL? { Groupe.conteneur?.appendingPathComponent("Apercu.json") }
    private static var vignettes: URL? { Groupe.conteneur?.appendingPathComponent("Vignettes", isDirectory: true) }

    static func lire() -> [ApercuElement] {
        guard let fichier, let data = try? Data(contentsOf: fichier) else { return [] }
        return (try? JSONDecoder().decode([ApercuElement].self, from: data)) ?? []
    }

    static func vignette(_ nom: String) -> URL? { vignettes?.appendingPathComponent(nom) }

    /// Construit l'aperçu à partir de l'historique (dossier Side déjà ouvert) et l'enregistre. Renvoie true s'il a changé.
    @discardableResult
    static func construire(_ elements: [Element], dossier d: URL) -> Bool {
        guard let fichier, let vignettes else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.createDirectory(at: vignettes, withIntermediateDirectories: true)
        var apercu: [ApercuElement] = []
        for e in elements.prefix(nombre) {
            var a = ApercuElement(id: e.id, texte: e.texte.map { String($0.prefix(300)) }, vignette: nil, epingle: e.epingle)
            if let nom = e.image {
                let cible = vignettes.appendingPathComponent(nom)
                if !fm.fileExists(atPath: cible.path) {
                    let source = d.appendingPathComponent("Presse-papiers images").appendingPathComponent(nom)
                    try? fm.startDownloadingUbiquitousItem(at: source)
                    if let png = reduire(source) { try? png.write(to: cible) }
                }
                if fm.fileExists(atPath: cible.path) { a.vignette = nom } else if e.texte == nil { a.texte = "Image" }
            }
            apercu.append(a)
        }
        let gardees = Set(apercu.compactMap(\.vignette))
        for f in (try? fm.contentsOfDirectory(atPath: vignettes.path)) ?? [] where !gardees.contains(f) {
            try? fm.removeItem(at: vignettes.appendingPathComponent(f))
        }
        guard apercu != lire() else { return false }
        try? JSONEncoder().encode(apercu).write(to: fichier, options: .atomic)
        return true
    }

    private static func reduire(_ url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 400,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
