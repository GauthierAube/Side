// L'IA locale : un modèle qui tourne sur ton Mac (ou sur un Mac de ton réseau) avec Ollama.
// Side ne parle qu'à ce serveur-là : aucune image, aucun texte ne part sur Internet.
// Premier usage (16/11/2026) : donner à chaque capture d'écran un nom qui dit ce qu'on y voit.

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Réglages

/// Les réglages de l'IA locale. Les clés « ia… » n'appartiennent qu'à lui.
final class ConfigIA: ObservableObject {
    static let commun = ConfigIA()
    static let serveursParDefaut = "http://localhost:11434, http://mac-mini-de-gauthier.local:11434"
    static let modeleParDefaut = "gemma4:26b"
    private let d = UserDefaults.standard

    /// Chaque nouvelle capture d'écran est renommée d'après ce qu'elle montre.
    @Published var renommerCaptures: Bool { didSet { d.set(renommerCaptures, forKey: "iaRenommerCaptures") } }
    /// Les adresses du serveur, séparées par des virgules : essayées dans l'ordre, la première qui répond sert.
    @Published var serveurs: String { didSet { d.set(serveurs, forKey: "iaServeurs"); IALocale.oublierServeur() } }
    /// Le modèle demandé à Ollama (il doit savoir lire les images).
    @Published var modele: String { didSet { d.set(modele, forKey: "iaModele") } }

    private init() {
        renommerCaptures = d.object(forKey: "iaRenommerCaptures") as? Bool ?? true
        serveurs = d.string(forKey: "iaServeurs") ?? Self.serveursParDefaut
        modele = d.string(forKey: "iaModele") ?? Self.modeleParDefaut
    }

    /// Les adresses à essayer, dans l'ordre. Un champ vidé revient aux adresses de départ.
    static func adresses(_ texte: String) -> [URL] {
        func lire(_ t: String) -> [URL] {
            t.split(separator: ",").compactMap { morceau -> URL? in
                var a = morceau.trimmingCharacters(in: .whitespacesAndNewlines)
                while a.hasSuffix("/") { a.removeLast() }
                guard !a.isEmpty else { return nil }
                if !a.contains("://") { a = "http://" + a }
                guard let u = URL(string: a), u.host != nil else { return nil }
                return u
            }
        }
        let lues = lire(texte)
        return lues.isEmpty ? lire(serveursParDefaut) : lues
    }
    /// Le nom du modèle. Un champ vidé revient au modèle de départ.
    static func modele(_ texte: String) -> String {
        let m = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? modeleParDefaut : m
    }
}

// MARK: - Le serveur

/// Parle au serveur Ollama. Tout ici attend une réponse du réseau : jamais sur le fil principal.
enum IALocale {
    private static let verrou = NSLock()
    private static var gagnant: (url: URL, quand: Date)?
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral     // ni cache ni cookies : rien n'est gardé sur le disque
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// Les adresses ont changé dans les réglages : le serveur retenu ne vaut plus.
    static func oublierServeur() { verrou.lock(); gagnant = nil; verrou.unlock() }

    /// Envoie une requête et attend sa réponse (ou la fin du délai).
    private static func attendre(_ requete: URLRequest) -> Data? {
        dispatchPrecondition(condition: .notOnQueue(.main))
        var resultat: Data?
        let fini = DispatchSemaphore(value: 0)
        session.dataTask(with: requete) { donnees, reponse, _ in
            if (reponse as? HTTPURLResponse)?.statusCode == 200 { resultat = donnees }
            fini.signal()
        }.resume()
        fini.wait()
        return resultat
    }

    /// Le premier serveur de la liste qui répond (1,5 s au plus chacun). Le gagnant est retenu cinq minutes.
    static func serveur(parmi adresses: [URL]) -> URL? {
        verrou.lock()
        let retenu = gagnant
        verrou.unlock()
        if let retenu, Date().timeIntervalSince(retenu.quand) < 300, adresses.contains(retenu.url) { return retenu.url }
        for base in adresses {
            var r = URLRequest(url: base.appendingPathComponent("api/version"))
            r.timeoutInterval = 1.5
            guard attendre(r) != nil else { continue }
            verrou.lock(); gagnant = (base, Date()); verrou.unlock()
            return base
        }
        return nil
    }

    /// Pose une question au modèle, avec une image si besoin. Rend sa réponse, ou rien si le serveur ne répond pas.
    static func demander(_ question: String, image: Data? = nil, adresses: [URL], modele: String) -> String? {
        guard let base = serveur(parmi: adresses) else { return nil }
        var message: [String: Any] = ["role": "user", "content": question]
        if let image { message["images"] = [image.base64EncodedString()] }
        let corps: [String: Any] = ["model": modele, "stream": false, "think": false,
                                    "options": ["temperature": 0.2], "messages": [message]]
        var r = URLRequest(url: base.appendingPathComponent("api/chat"))
        r.httpMethod = "POST"
        r.timeoutInterval = 90
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: corps)
        guard let donnees = attendre(r) else { oublierServeur(); return nil }
        let reponse = (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any]
        return (reponse?["message"] as? [String: Any])?["content"] as? String
    }

    /// Pour le bouton « Tester » : quel serveur répond, et le modèle y est-il installé ?
    static func tester(adresses: [URL], modele: String) -> (serveur: URL?, modeleInstalle: Bool) {
        oublierServeur()
        guard let base = serveur(parmi: adresses) else { return (nil, false) }
        var r = URLRequest(url: base.appendingPathComponent("api/tags"))
        r.timeoutInterval = 5
        let liste = attendre(r).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let noms = (liste?["models"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        // Ollama ajoute « :latest » quand le nom n'a pas d'étiquette.
        return (base, noms.contains(modele) || noms.contains(modele + ":latest"))
    }

    /// L'image réduite (1280 points au plus sur son grand côté) en JPEG : assez pour la lire, et bien plus rapide à envoyer.
    static func imageReduite(_ fichier: URL, cote: Int = 1280) -> Data? {
        guard let source = CGImageSourceCreateWithURL(fichier as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: cote]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let sortie = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(sortie, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? sortie as Data : nil
    }
}

// MARK: - Le nom d'une capture d'écran

/// Trouve le nouveau nom d'une capture d'écran. Ne touche à aucun fichier : c'est `Captures` qui renomme.
enum NomDeCapture {
    static let question = """
    Voici une capture d'écran. Propose un nom de fichier court en français qui décrit ce qu'on y voit \
    (application ou site, sujet). 3 à 6 mots, minuscules, sans extension, sans date, sans guillemets, \
    sans ponctuation. Réponds uniquement par le nom.
    """

    /// Demande au modèle un nom pour cette image. Rien si le serveur ne répond pas ou si la réponse ne convient pas.
    static func proposer(_ fichier: URL, adresses: [URL], modele: String) -> String? {
        guard let image = IALocale.imageReduite(fichier),
              let reponse = IALocale.demander(question, image: image, adresses: adresses, modele: modele) else { return nil }
        return nettoyer(reponse)
    }

    /// Fait d'une réponse du modèle un nom de fichier sûr : une ligne, des lettres, des chiffres, des espaces, des tirets
    /// et des apostrophes, 60 caractères au plus. Rend rien pour une réponse vide ou absurde (une phrase, « capture d'écran »).
    static func nettoyer(_ reponse: String) -> String? {
        // La première ligne qui contient quelque chose.
        guard var t = reponse.components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { $0.contains(where: \.isLetter) }) else { return nil }
        t = t.precomposedStringWithCanonicalMapping.lowercased()
        // « Nom de fichier : … » : on ne garde que la suite.
        if let r = t.range(of: #"^[\W_]*(nom( de fichier| du fichier)?|fichier|réponse)\s*:\s*"#, options: .regularExpression) {
            t.removeSubrange(r)
        }
        // Une extension ajoutée malgré la consigne.
        if let r = t.range(of: #"\.(png|jpe?g|heic|tiff?|gif|pdf|webp)[\W_]*$"#, options: .regularExpression) { t.removeSubrange(r) }
        t = t.replacingOccurrences(of: "’", with: "'")
        // Tout ce qui n'est ni lettre, ni chiffre, ni tiret, ni apostrophe devient une espace : guillemets, ponctuation,
        // barres obliques, deux-points, points (pas de fichier caché), caractères invisibles.
        let propre = String(t.map { c -> Character in
            (c.isLetter || c.isNumber || c == "-" || c == "'") ? c : " "
        })
        // Tirets et apostrophes seulement à l'intérieur d'un mot.
        let mots = propre.split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-'")) }.filter { !$0.isEmpty }
        guard !mots.isEmpty, mots.count <= 8 else { return nil }
        // Un nom qui ne dit rien de plus que « capture d'écran ».
        let creux: Set<String> = ["capture", "captures", "d'écran", "d'ecran", "écran", "ecran", "screenshot", "image",
                                  "de", "d", "du", "une", "un", "la", "le", "l", "sans", "titre", "nom", "fichier"]
        guard mots.contains(where: { !creux.contains($0) }) else { return nil }
        // 60 caractères au plus, coupé entre deux mots.
        var nom = ""
        for mot in mots {
            let suite = nom.isEmpty ? mot : nom + " " + mot
            if suite.count > 60 { break }
            nom = suite
        }
        guard nom.count >= 3, nom.contains(where: \.isLetter) else { return nil }
        return nom
    }

    /// La date et l'heure d'une capture : celles de son nom d'origine (« Capture d'écran 2026-11-16 à 14.32.05 »),
    /// sinon la date de création du fichier.
    static func date(_ fichier: URL) -> String {
        let nom = fichier.deletingPathExtension().lastPathComponent
        let motif = #"(\d{4}-\d{2}-\d{2})\D{1,5}?(\d{1,2})[.:h](\d{2})(?:[.:](\d{2}))?(?:\s*(AM|PM))?"#
        if let regex = try? NSRegularExpression(pattern: motif, options: .caseInsensitive),
           let m = regex.firstMatch(in: nom, range: NSRange(nom.startIndex..., in: nom)) {
            func groupe(_ i: Int) -> String? { Range(m.range(at: i), in: nom).map { String(nom[$0]) } }
            if let jour = groupe(1), var heure = groupe(2).flatMap({ Int($0) }), let minute = groupe(3) {
                if let demi = groupe(5)?.uppercased() {      // Mac réglé sur douze heures
                    if demi == "PM", heure < 12 { heure += 12 }
                    if demi == "AM", heure == 12 { heure = 0 }
                }
                return jour + String(format: " %02d.", heure) + minute + (groupe(4).map { "." + $0 } ?? "")
            }
        }
        let creation = (try? fichier.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return f.string(from: creation)
    }

    /// Le nouvel emplacement : « nom date.ext », dans le même dossier. Jamais celui d'un fichier qui existe (« 2 », « 3 »…).
    static func cible(pour fichier: URL, nom: String) -> URL {
        let dossier = fichier.deletingLastPathComponent()
        let base = nom + " " + date(fichier)
        let ext = fichier.pathExtension
        func url(_ b: String) -> URL { ext.isEmpty ? dossier.appendingPathComponent(b) : dossier.appendingPathComponent(b).appendingPathExtension(ext) }
        var cible = url(base)
        var n = 2
        while FileManager.default.fileExists(atPath: cible.path) { cible = url("\(base) \(n)"); n += 1 }
        return cible
    }

    // MARK: Essais

    /// `Side --test-capture fichier` : demande un nom pour cette image, l'affiche, et ne renomme rien.
    static func essai(_ chemin: String) -> Never {
        let fichier = URL(fileURLWithPath: chemin)
        let adresses = ConfigIA.adresses(ConfigIA.commun.serveurs)
        let modele = ConfigIA.modele(ConfigIA.commun.modele)
        DispatchQueue.global(qos: .userInitiated).async {
            let debut = Date()
            guard let image = IALocale.imageReduite(fichier) else { print("image illisible : \(chemin)"); exit(1) }
            guard let serveur = IALocale.serveur(parmi: adresses) else {
                print("aucun serveur ne répond : " + adresses.map(\.absoluteString).joined(separator: ", ")); exit(2)
            }
            print("serveur : \(serveur.absoluteString) — modèle : \(modele) — image envoyée : \(image.count / 1024) Ko")
            guard let reponse = IALocale.demander(question, image: image, adresses: adresses, modele: modele) else {
                print("pas de réponse du modèle"); exit(3)
            }
            print("réponse brute : \(reponse.debugDescription)")
            print(String(format: "durée : %.1f s", Date().timeIntervalSince(debut)))
            guard let nom = nettoyer(reponse) else { print("réponse refusée : le fichier garderait son nom"); exit(4) }
            print("nom proposé : \(cible(pour: fichier, nom: nom).lastPathComponent)")
            exit(0)
        }
        dispatchMain()
    }

    /// `Side --test-nom-capture` : le nettoyage des réponses et la date, sur des cas difficiles, sans serveur.
    static func essaiNettoyage() -> Int32 {
        let cas: [(String, String?)] = [
            ("safari page github side", "safari page github side"),
            ("  \"Safari : Page GitHub de Side.\"\n", "safari page github de side"),
            ("**Nom de fichier :** `finder_dossier_documents.png`", "finder dossier documents"),
            ("« réglages système – écran d’accueil »", "réglages système écran d'accueil"),
            ("../../etc/passwd", "etc passwd"),
            ("/Users/moi/Desktop:secret", "users moi desktop secret"),
            (".cache caché", "cache caché"),
            ("\n\nmail boîte de réception\nVoici pourquoi j'ai choisi ce nom.", "mail boîte de réception"),
            ("Capture d'écran", nil),
            ("capture d’écran.png", nil),
            ("", nil),
            ("   \n \t ", nil),
            ("!!! ??? ...", nil),
            ("Cette capture d'écran montre une fenêtre du Finder avec plusieurs dossiers ouverts", nil),
            ("tableur budget\u{0000}\u{202E} 2026\u{0007}", "tableur budget 2026"),
            ("-- l'aperçu - d'une image --", "l'aperçu d'une image"),
            ("terminal compilation swift erreur fenêtre réglages apparence clair sombre", nil),
            (String(repeating: "abcdefghi ", count: 8), "abcdefghi abcdefghi abcdefghi abcdefghi abcdefghi abcdefghi"),
            ("e\u{0301}cran de re\u{0301}glages spotify", "écran de réglages spotify"),
            ("xcode 🚀 projet side", "xcode projet side"),
        ]
        var echecs = 0
        for (entree, attendu) in cas {
            let obtenu = nettoyer(entree)
            let bon = obtenu == attendu
            if !bon { echecs += 1 }
            print((bon ? "ok    " : "ÉCHEC ") + entree.debugDescription + " → " + (obtenu ?? "refusé")
                  + (bon ? "" : "   (attendu : \(attendu ?? "refusé"))"))
        }
        let dates: [(String, String)] = [
            ("Capture d’écran 2026-11-16 à 14.32.05.png", "2026-11-16 14.32.05"),
            ("Screenshot 2026-11-16 at 9.05.41 PM.png", "2026-11-16 21.05.41"),
            ("Screenshot 2026-11-16 at 12.05.41 AM.png", "2026-11-16 00.05.41"),
            ("Capture d’écran 2026-11-16 à 08.07.09 (2).png", "2026-11-16 08.07.09"),
        ]
        for (nom, attendu) in dates {
            let obtenu = date(URL(fileURLWithPath: "/tmp/" + nom))
            if obtenu != attendu { echecs += 1 }
            print((obtenu == attendu ? "ok    " : "ÉCHEC ") + nom + " → " + obtenu)
        }
        print(echecs == 0 ? "Tout est bon." : "\(echecs) échec(s).")
        return echecs == 0 ? 0 : 1
    }
}

// MARK: - Réglages > IA locale

struct SectionsIA: View {
    @ObservedObject var config = ConfigIA.commun
    private enum Etat: Equatable { case inconnu, enCours, pret(String), sansModele(String, String), absent }
    @State private var etat: Etat = .inconnu

    var body: some View {
        Section {
            Toggle("Renommer mes captures d'écran d'après leur contenu", isOn: $config.renommerCaptures)
        } header: { Text("Captures d'écran") } footer: {
            note("Quelques secondes après une capture, son nom dit ce qu'on y voit, suivi de la date : « safari page github side 2026-11-16 14.32.05 ». Si le serveur ne répond pas, la capture garde son nom.")
        }
        Section {
            TextField("Adresses du serveur", text: $config.serveurs, prompt: Text(verbatim: ConfigIA.serveursParDefaut))
            TextField("Modèle", text: $config.modele, prompt: Text(verbatim: ConfigIA.modeleParDefaut))
            LabeledContent("Connexion") {
                HStack(spacing: 8) {
                    resultat
                    Button("Tester") { tester() }.disabled(etat == .enCours)
                }
            }
        } header: { Text("Serveur Ollama") } footer: {
            note("Les images ne sont envoyées qu'à ton propre Mac, ou à un Mac de ton réseau : rien ne part sur Internet. Plusieurs adresses, séparées par des virgules : Side les essaie dans l'ordre et garde la première qui répond.")
        }
    }

    @ViewBuilder private var resultat: some View {
        switch etat {
        case .inconnu: EmptyView()
        case .enCours: ProgressView().controlSize(.small)
        case .pret(let hote):
            Label("Le serveur répond (\(hote))", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
        case .sansModele(let hote, let modele):
            Label("Le serveur répond (\(hote)), mais le modèle « \(modele) » n'y est pas installé", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
        case .absent:
            Label("Aucun serveur ne répond", systemImage: "xmark.circle.fill").foregroundStyle(.secondary)
        }
    }

    private func tester() {
        etat = .enCours
        let adresses = ConfigIA.adresses(config.serveurs)
        let modele = ConfigIA.modele(config.modele)
        DispatchQueue.global(qos: .userInitiated).async {
            let r = IALocale.tester(adresses: adresses, modele: modele)
            DispatchQueue.main.async {
                guard let serveur = r.serveur else { etat = .absent; return }
                let hote = serveur.host ?? serveur.absoluteString
                etat = r.modeleInstalle ? .pret(hote) : .sansModele(hote, modele)
            }
        }
    }

    private func note(_ texte: LocalizedStringKey) -> some View {
        Text(texte).font(.caption).foregroundStyle(.secondary)
    }
}
