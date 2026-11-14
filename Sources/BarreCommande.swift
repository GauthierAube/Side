// La barre de commande du Finder de Side (13/11/2026), inspirée de Substage : elle se colle sous le Finder, on y écrit en
// français ce qu'on veut faire des fichiers sélectionnés (« convertis en JPG », « réduis à 1080 px de haut », « zippe tout »,
// « fusionne ces PDF », « enlève le fond »…). Apple Intelligence, sur le Mac, sans Internet ni compte, comprend la demande ;
// les mots simples (jpg, zip, mp4…) sont compris tout de suite, sans elle.
//
// Sécurité : la barre ne lance jamais de commande inventée. Elle choisit une action dans une liste connue, montre ce qu'elle
// va faire, et n'agit qu'après Entrée. Les originaux ne sont jamais modifiés : les résultats sont de nouveaux fichiers,
// posés à côté.
import AppKit
import SwiftUI
import PDFKit
import Vision
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreImage
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Les actions possibles

enum ActionFichier: Equatable {
    case convertirImage(format: String)                   // jpg, png, heic, tiff
    case redimensionner(pixels: Int, dimension: String)   // hauteur, largeur, cote
    case pivoter(angle: Int)
    case retirerFond
    case imagesEnPDF
    case fusionnerPDF
    case extraireTexte
    case zipper
    case convertirVideo(hauteur: Int)                     // 0 : même taille
    case extraireAudio

    /// Ce que l'action va faire, en une phrase, pour la confirmation.
    func description(_ n: Int) -> String {
        let f = n > 1 ? String(localized: "\(n) fichiers") : String(localized: "le fichier")
        switch self {
        case .convertirImage(let format): return String(localized: "Convertir \(f) en \(format.uppercased())")
        case .redimensionner(let px, let dim):
            let quoi = dim == "hauteur" ? String(localized: "\(px) px de haut") : (dim == "largeur" ? String(localized: "\(px) px de large") : String(localized: "\(px) px au plus grand côté"))
            return String(localized: "Réduire \(f) à \(quoi)")
        case .pivoter(let a): return String(localized: "Pivoter \(f) de \(a)°")
        case .retirerFond: return String(localized: "Retirer le fond (\(f), en PNG transparent)")
        case .imagesEnPDF: return String(localized: "Réunir les images en un seul PDF")
        case .fusionnerPDF: return String(localized: "Fusionner les PDF en un seul")
        case .extraireTexte: return String(localized: "Extraire le texte (\(f)) dans un fichier texte")
        case .zipper: return String(localized: "Compresser en une archive ZIP")
        case .convertirVideo(let h): return h > 0 ? String(localized: "Convertir \(f) en MP4 \(h)p") : String(localized: "Convertir \(f) en MP4")
        case .extraireAudio: return String(localized: "Extraire le son (\(f)) en M4A")
        }
    }

    /// Les fichiers sur lesquels l'action a un sens.
    func garde(_ urls: [URL]) -> [URL] {
        switch self {
        case .convertirImage, .redimensionner, .pivoter, .retirerFond, .imagesEnPDF: return urls.filter { Genre.de($0) == .image }
        case .fusionnerPDF: return urls.filter { Genre.de($0) == .pdf }
        case .extraireTexte: return urls.filter { [.pdf, .image].contains(Genre.de($0)) }
        case .zipper: return urls
        case .convertirVideo, .extraireAudio: return urls.filter { Genre.de($0) == .video }
        }
    }
}

enum Genre { case image, pdf, video, autre
    static func de(_ u: URL) -> Genre {
        guard let t = UTType(filenameExtension: u.pathExtension.lowercased()) else { return .autre }
        if t.conforms(to: .image) { return .image }
        if t.conforms(to: .pdf) { return .pdf }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return .video }
        return .autre
    }
}

// MARK: - Comprendre la demande

enum Comprendre {
    /// Les demandes courtes et sans ambiguïté sont comprises tout de suite, sans Apple Intelligence.
    static func directement(_ texte: String, _ urls: [URL]) -> ActionFichier? {
        let t = " " + texte.lowercased().folding(options: .diacriticInsensitive, locale: .current) + " "
        func a(_ mots: String...) -> Bool { mots.contains { t.contains($0) } }
        let px = Int(t.components(separatedBy: CharacterSet.decimalDigits.inverted).first { ($0.count >= 3 && $0.count <= 5) } ?? "") ?? 0
        if a(" zip", "archive", "compresse") { return .zipper }
        if a("fond", "detour") { return .retirerFond }
        if a("fusionne", "assemble", "combine") { return urls.contains { Genre.de($0) == .pdf } ? .fusionnerPDF : .imagesEnPDF }
        if a(" texte", " ocr") { return .extraireTexte }
        if a(" audio", " son ", " m4a", " mp3") { return .extraireAudio }
        if a(" mp4", " video") { return .convertirVideo(hauteur: [2160, 1080, 720, 480].first { t.contains("\($0)") } ?? 0) }
        if a(" pdf") && urls.allSatisfy({ Genre.de($0) == .image }) { return .imagesEnPDF }
        if a("pivote", "tourne") {
            return .pivoter(angle: a("gauche") ? 270 : (a("180", "retourne") ? 180 : 90))
        }
        if px > 0, a("redimensionne", "reduis", "reduit", "taille", " px", "pixel") {
            return .redimensionner(pixels: px, dimension: a("haut") ? "hauteur" : (a("large") ? "largeur" : "cote"))
        }
        for f in ["jpg", "jpeg", "png", "heic", "tiff"] where t.contains(" \(f)") || t.trimmingCharacters(in: .whitespaces) == f {
            return .convertirImage(format: f == "jpeg" ? "jpg" : f)
        }
        return nil
    }

    static var appleIntelligence: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    /// Les autres demandes passent par Apple Intelligence, sur le Mac : elle choisit une action dans la liste, rien d'autre.
    static func avecAppleIntelligence(_ texte: String, _ urls: [URL]) async -> ActionFichier? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), appleIntelligence else { return nil }
        let resume = Dictionary(grouping: urls) { $0.pathExtension.lowercased() }.map { "\($0.value.count) .\($0.key)" }.joined(separator: ", ")
        let s = LanguageModelSession(instructions: """
            Tu traduis une demande en français, sur des fichiers sélectionnés dans le Finder, en une seule action parmi la liste.
            Si la demande ne correspond à aucune action de la liste, choisis « inconnue ». N'invente rien.
            """)
        guard let r = try? await s.respond(to: "Fichiers sélectionnés : \(resume). Demande : \(texte)", generating: IntentionFichier.self) else { return nil }
        let i = r.content
        switch i.action {
        case "convertirImage": return .convertirImage(format: ["jpg", "png", "heic", "tiff"].contains(i.format) ? i.format : "jpg")
        case "redimensionner": return i.pixels > 0 ? .redimensionner(pixels: i.pixels, dimension: i.dimension) : nil
        case "pivoter": return .pivoter(angle: [90, 180, 270].contains(i.angle) ? i.angle : 90)
        case "retirerFond": return .retirerFond
        case "imagesEnPDF": return .imagesEnPDF
        case "fusionnerPDF": return .fusionnerPDF
        case "extraireTexte": return .extraireTexte
        case "zipper": return .zipper
        case "convertirVideo": return .convertirVideo(hauteur: [2160, 1080, 720, 480].contains(i.resolution) ? i.resolution : 0)
        case "extraireAudio": return .extraireAudio
        default: return nil
        }
        #else
        return nil
        #endif
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct IntentionFichier {
    @Guide(description: "L'action demandée", .anyOf(["convertirImage", "redimensionner", "zipper", "fusionnerPDF", "extraireTexte",
                                                        "convertirVideo", "extraireAudio", "imagesEnPDF", "retirerFond", "pivoter", "inconnue"]))
    var action: String
    @Guide(description: "Format d'image voulu : jpg, png, heic ou tiff ; vide si non précisé")
    var format: String
    @Guide(description: "Nombre de pixels demandé, 0 si non précisé")
    var pixels: Int
    @Guide(description: "Ce que mesurent les pixels : hauteur, largeur, ou cote (le plus grand côté)", .anyOf(["hauteur", "largeur", "cote"]))
    var dimension: String
    @Guide(description: "Hauteur vidéo voulue : 2160, 1080, 720 ou 480 ; 0 si non précisé")
    var resolution: Int
    @Guide(description: "Rotation en degrés dans le sens des aiguilles d'une montre : 90, 180 ou 270 ; 0 sinon")
    var angle: Int
}
#endif

// MARK: - Faire

enum Faire {
    struct Erreur: LocalizedError { let errorDescription: String? }

    /// Un nom libre à côté de l'original : « photo.jpg », sinon « photo 2.jpg »…
    static func libre(_ dossier: URL, _ nom: String, _ ext: String) -> URL {
        var u = dossier.appendingPathComponent(nom).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) {
            u = dossier.appendingPathComponent("\(nom) \(n)").appendingPathExtension(ext); n += 1
        }
        return u
    }
    private static func base(_ u: URL) -> String { u.deletingPathExtension().lastPathComponent }

    /// Lance l'action ; renvoie les fichiers créés.
    static func executer(_ action: ActionFichier, _ urls: [URL]) async throws -> [URL] {
        guard let premier = urls.first else { return [] }
        let dossierCommun = premier.deletingLastPathComponent()
        switch action {
        case .convertirImage(let format):
            return try urls.map { try ecrireImage(source: $0, vers: libre(dossierDe($0), base($0), format), format: format, tailleMax: nil) }
        case .redimensionner(let px, let dim):
            return try urls.map { u in
                let taille = tailleMax(u, px, dim)
                let ext = u.pathExtension.lowercased() == "heic" ? "heic" : (u.pathExtension.isEmpty ? "png" : u.pathExtension.lowercased())
                return try ecrireImage(source: u, vers: libre(dossierDe(u), base(u) + " \(px)px", ext), format: ext, tailleMax: taille)
            }
        case .pivoter(let angle):
            return try urls.map { u in
                let sortie = libre(dossierDe(u), base(u) + " pivotée", u.pathExtension)
                try lancer("/usr/bin/sips", ["-r", "\(angle)", u.path, "--out", sortie.path])
                return sortie
            }
        case .retirerFond:
            return try urls.map { try sansFond($0) }
        case .imagesEnPDF:
            let doc = PDFDocument()
            for u in urls { if let img = NSImage(contentsOf: u), let page = PDFPage(image: img) { doc.insert(page, at: doc.pageCount) } }
            let sortie = libre(dossierCommun, urls.count == 1 ? base(premier) : String(localized: "Images réunies"), "pdf")
            guard doc.pageCount > 0, doc.write(to: sortie) else { throw Erreur(errorDescription: String(localized: "Impossible de créer le PDF.")) }
            return [sortie]
        case .fusionnerPDF:
            let doc = PDFDocument()
            for u in urls { if let d = PDFDocument(url: u) { for i in 0..<d.pageCount { if let p = d.page(at: i) { doc.insert(p, at: doc.pageCount) } } } }
            let sortie = libre(dossierCommun, String(localized: "PDF fusionnés"), "pdf")
            guard doc.pageCount > 0, doc.write(to: sortie) else { throw Erreur(errorDescription: String(localized: "Impossible de fusionner ces PDF.")) }
            return [sortie]
        case .extraireTexte:
            return try urls.map { u in
                let texte = Genre.de(u) == .pdf ? (PDFDocument(url: u)?.string ?? "") : try lireTexte(u)
                let sortie = libre(dossierDe(u), base(u), "txt")
                try texte.write(to: sortie, atomically: true, encoding: .utf8)
                return sortie
            }
        case .zipper:
            let nom = urls.count == 1 ? premier.lastPathComponent : String(localized: "Archive")
            let sortie = libre(dossierCommun, nom, "zip")
            if urls.count == 1 {
                try lancer("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", premier.path, sortie.path])
            } else {
                try lancer("/usr/bin/zip", ["-r", "-X", "-q", sortie.path] + urls.map(\.lastPathComponent), dans: dossierCommun)
            }
            return [sortie]
        case .convertirVideo(let h):
            var faits: [URL] = []
            for u in urls {
                let preset = [2160: AVAssetExportPreset3840x2160, 1080: AVAssetExportPreset1920x1080, 720: AVAssetExportPreset1280x720,
                              480: AVAssetExportPreset640x480][h] ?? AVAssetExportPresetHighestQuality
                faits.append(try await exporter(u, preset: preset, vers: libre(dossierDe(u), base(u) + (h > 0 ? " \(h)p" : ""), "mp4"), type: .mp4))
            }
            return faits
        case .extraireAudio:
            var faits: [URL] = []
            for u in urls { faits.append(try await exporter(u, preset: AVAssetExportPresetAppleM4A, vers: libre(dossierDe(u), base(u), "m4a"), type: .m4a)) }
            return faits
        }
    }

    private static func dossierDe(_ u: URL) -> URL { u.deletingLastPathComponent() }

    private static func tailleMax(_ u: URL, _ px: Int, _ dim: String) -> Int {
        guard dim != "cote", let s = CGImageSourceCreateWithURL(u as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Double, let h = p[kCGImagePropertyPixelHeight] as? Double, w > 0, h > 0 else { return px }
        // « 1080 px de haut » : le plus grand côté qui donne cette hauteur (ou cette largeur).
        let r = dim == "hauteur" ? max(w, h) / h : max(w, h) / w
        return Int((Double(px) * r).rounded())
    }

    private static func ecrireImage(source: URL, vers sortie: URL, format: String, tailleMax: Int?) throws -> URL {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw Erreur(errorDescription: String(localized: "Image illisible : \(source.lastPathComponent)")) }
        var options: [CFString: Any] = [kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceCreateThumbnailFromImageAlways: true]
        let image: CGImage?
        if let m = tailleMax {
            options[kCGImageSourceThumbnailMaxPixelSize] = m
            image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        let type: UTType = ["jpg": .jpeg, "jpeg": .jpeg, "png": .png, "heic": .heic, "tiff": .tiff, "tif": .tiff, "gif": .gif][format] ?? .png
        guard let image, let dest = CGImageDestinationCreateWithURL(sortie as CFURL, type.identifier as CFString, 1, nil) else {
            throw Erreur(errorDescription: String(localized: "Conversion impossible : \(source.lastPathComponent)"))
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Erreur(errorDescription: String(localized: "Conversion impossible : \(source.lastPathComponent)")) }
        return sortie
    }

    private static func sansFond(_ u: URL) throws -> URL {
        guard let ci = CIImage(contentsOf: u, options: [.applyOrientationProperty: true]) else { throw Erreur(errorDescription: String(localized: "Image illisible : \(u.lastPathComponent)")) }
        let req = VNGenerateForegroundInstanceMaskRequest()
        let h = VNImageRequestHandler(ciImage: ci)
        try h.perform([req])
        guard let obs = req.results?.first else { throw Erreur(errorDescription: String(localized: "Aucun sujet trouvé dans \(u.lastPathComponent).")) }
        let masque = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: h, croppedToInstancesExtent: false)
        let sortie = libre(u.deletingLastPathComponent(), base(u) + " sans fond", "png")
        let ctx = CIContext()
        try ctx.writePNGRepresentation(of: CIImage(cvPixelBuffer: masque), to: sortie, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return sortie
    }

    private static func lireTexte(_ u: URL) throws -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLanguages = ["fr-FR", "en-US"]
        req.usesLanguageCorrection = true
        try VNImageRequestHandler(url: u).perform([req])
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func exporter(_ u: URL, preset: String, vers sortie: URL, type: AVFileType) async throws -> URL {
        let asset = AVURLAsset(url: u)
        guard let s = AVAssetExportSession(asset: asset, presetName: preset) else { throw Erreur(errorDescription: String(localized: "Conversion impossible : \(u.lastPathComponent)")) }
        s.outputURL = sortie
        s.outputFileType = type
        s.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in s.exportAsynchronously { c.resume() } }
        guard s.status == .completed else { throw Erreur(errorDescription: s.error?.localizedDescription ?? String(localized: "Conversion impossible : \(u.lastPathComponent)")) }
        return sortie
    }

    private static func lancer(_ outil: String, _ args: [String], dans dossier: URL? = nil) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: outil)
        p.arguments = args
        if let dossier { p.currentDirectoryURL = dossier }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Erreur(errorDescription: String(localized: "L'opération a échoué.")) }
    }
}

// MARK: - La barre

final class ModeleBarre: ObservableObject {
    enum Etat: Equatable { case attente, reflexion, proposition(ActionFichier, [URL]), travail(String), fini(String, [URL]), erreur(String) }
    @Published var texte = ""
    @Published var etat: Etat = .attente
    @Published var selection: [URL] = []
    /// Chaque demande a son numéro : une réponse d'Apple Intelligence qui arrive après une nouvelle demande est ignorée.
    private var numero = 0
    var enEssai = false

    var resumeSelection: String {
        guard !selection.isEmpty else { return String(localized: "Sélectionne des fichiers dans le Finder") }
        let g = Dictionary(grouping: selection) { Genre.de($0) }
        var morceaux: [String] = []
        if let n = g[.image]?.count { morceaux.append(n > 1 ? String(localized: "\(n) images") : String(localized: "1 image")) }
        if let n = g[.pdf]?.count { morceaux.append(n > 1 ? String(localized: "\(n) PDF") : String(localized: "1 PDF")) }
        if let n = g[.video]?.count { morceaux.append(n > 1 ? String(localized: "\(n) vidéos") : String(localized: "1 vidéo")) }
        if let n = g[.autre]?.count { morceaux.append(n > 1 ? String(localized: "\(n) autres fichiers") : String(localized: "1 autre fichier")) }
        return morceaux.joined(separator: " · ")
    }

    /// Les actions rapides proposées pour cette sélection (un clic, sans rien écrire).
    var suggestions: [(String, ActionFichier)] {
        let g = Set(selection.map { Genre.de($0) })
        var s: [(String, ActionFichier)] = []
        if g == [.image] {
            s += [("JPG", .convertirImage(format: "jpg")), ("PNG", .convertirImage(format: "png")),
                  (String(localized: "1080 px"), .redimensionner(pixels: 1080, dimension: "cote")), (String(localized: "Sans fond"), .retirerFond),
                  ("PDF", .imagesEnPDF)]
        }
        if g == [.pdf] { s += [(String(localized: "Fusionner"), .fusionnerPDF), (String(localized: "Texte"), .extraireTexte)] }
        if g == [.video] { s += [("MP4 1080p", .convertirVideo(hauteur: 1080)), ("MP4 720p", .convertirVideo(hauteur: 720)), (String(localized: "Son"), .extraireAudio)] }
        if !selection.isEmpty { s.append(("ZIP", .zipper)) }
        return s
    }

    func envoyer() {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .proposition(let a, let u) = etat { lancer(a, u); return }
        guard !t.isEmpty, !selection.isEmpty else { return }
        let urls = selection
        numero += 1
        let n = numero
        if let a = Comprendre.directement(t, urls) { proposer(a, urls); return }
        guard Comprendre.appleIntelligence else {
            etat = .erreur(String(localized: "Je n'ai pas compris. Essaie avec un mot simple : jpg, png, zip, mp4, pdf, texte, fond…"))
            return
        }
        etat = .reflexion
        Task { @MainActor in
            let a = await Comprendre.avecAppleIntelligence(t, urls)
            guard n == self.numero else { return }          // une autre demande est arrivée entre-temps
            if let a { self.proposer(a, urls) }
            else { self.etat = .erreur(String(localized: "Je ne sais pas encore faire ça. Essaie : convertir, réduire, pivoter, retirer le fond, fusionner, extraire le texte, zipper, MP4, son.")) }
        }
    }

    func proposer(_ a: ActionFichier, _ urls: [URL]) {
        let gardes = a.garde(urls)
        guard !gardes.isEmpty else { etat = .erreur(String(localized: "Cette action ne s'applique pas aux fichiers sélectionnés.")); return }
        etat = .proposition(a, gardes)
    }

    func lancer(_ a: ActionFichier, _ urls: [URL]) {
        etat = .travail(a.description(urls.count))
        Task { @MainActor in
            do {
                let faits = try await Faire.executer(a, urls)
                self.texte = ""
                self.etat = .fini(faits.count > 1 ? String(localized: "\(faits.count) fichiers créés") : String(localized: "Fichier créé : \(faits.first?.lastPathComponent ?? "")"), faits)
                AppDelegate.shared.store.reloadAll()
                if let f = faits.first { Selection.shared.url = f }
            } catch {
                self.etat = .erreur(error.localizedDescription)
            }
        }
    }
}

struct VueBarre: View {
    @ObservedObject var m: ModeleBarre
    @ObservedObject var config = Config.shared
    @FocusState private var champ: Bool

    /// Une seule ligne en temps normal (une pilule) ; une seconde ligne seulement pour une proposition, un résultat ou
    /// une erreur.
    private var compacte: Bool { switch m.etat { case .attente, .reflexion, .travail: return true; default: return false } }

    /// Ce que dit le champ vide : d'abord qu'il faut sélectionner, puis un exemple qui va avec la sélection.
    private var invite: String {
        if m.selection.isEmpty { return String(localized: "Aucun fichier sélectionné : sélectionne des fichiers dans le Finder") }
        if case .reflexion = m.etat { return String(localized: "Apple Intelligence cherche ce que tu veux faire…") }
        let genres = Set(m.selection.map { Genre.de($0) })
        let exemple: String
        if genres == [.image] { exemple = String(localized: "convertis en JPG, réduis à 1080 px, enlève le fond…") }
        else if genres == [.pdf] { exemple = String(localized: "fusionne, extrais le texte…") }
        else if genres == [.video] { exemple = String(localized: "convertis en MP4 720p, extrais le son…") }
        else { exemple = String(localized: "zippe tout…") }
        return m.selection.count > 1 ? String(localized: "\(m.selection.count) fichiers — par exemple : \(exemple)")
                                     : String(localized: "1 fichier — par exemple : \(exemple)")
    }

    var body: some View {
        let rayon: CGFloat = compacte ? 19 : 16
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: Comprendre.appleIntelligence ? "apple.intelligence" : "wand.and.stars")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                TextField(invite, text: $m.texte)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .disabled(m.selection.isEmpty)
                    .focused($champ)
                    .onSubmit { m.envoyer() }
                    .onChange(of: m.texte) { _, nouveau in
                        // On réécrit la demande : la proposition ou l'erreur d'avant n'ont plus lieu d'être.
                        guard !nouveau.isEmpty else { return }
                        switch m.etat { case .proposition, .erreur, .fini: m.etat = .attente; default: break }
                    }
                // Les actions rapides, sur la même ligne, quand le champ est vide.
                if case .attente = m.etat, m.texte.isEmpty {
                    ForEach(Array(m.suggestions.prefix(4).enumerated()), id: \.offset) { _, s in
                        Button(s.0) { m.proposer(s.1, m.selection) }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
                switch m.etat {
                case .reflexion, .travail: ProgressView().controlSize(.small)
                default:
                    Button { m.envoyer() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 18)) }
                        .buttonStyle(.plain).foregroundStyle(m.texte.isEmpty ? Color.secondary : Color.accentColor)
                        .disabled(m.texte.isEmpty && !estProposition)
                }
            }
            if !compacte { ligneBas }
        }
        .padding(.horizontal, 14).padding(.vertical, compacte ? 0 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compacte ? .center : .top)
        .background(ZStack { VisualEffect(); Color(nsColor: .windowBackgroundColor).opacity(config.opacite) })
        .clipShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: rayon, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
    }

    private var estProposition: Bool { if case .proposition = m.etat { return true }; return false }

    @ViewBuilder private var ligneBas: some View {
        switch m.etat {
        case .attente:
            HStack(spacing: 6) {
                Text(m.resumeSelection).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                ForEach(Array(m.suggestions.prefix(5).enumerated()), id: \.offset) { _, s in
                    Button(s.0) { m.proposer(s.1, m.selection) }
                        .buttonStyle(.plain).font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
        case .reflexion:
            Text("Apple Intelligence cherche ce que tu veux faire…").font(.caption).foregroundStyle(.secondary)
        case .proposition(let a, let urls):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle").foregroundStyle(Color.accentColor)
                Text(a.description(urls.count)).font(.callout.weight(.medium))
                Spacer()
                Button("Annuler") { m.etat = .attente }.controlSize(.small)
                Button("Lancer") { m.lancer(a, urls) }.controlSize(.small).keyboardShortcut(.defaultAction)
            }
            Text("Les originaux ne sont pas touchés : le résultat est un nouveau fichier, à côté.").font(.caption2).foregroundStyle(.secondary)
        case .travail(let quoi):
            Text(quoi + "…").font(.caption).foregroundStyle(.secondary)
        case .fini(let quoi, let faits):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text(quoi).font(.callout).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Afficher") { NSWorkspace.shared.activateFileViewerSelecting(faits) }.controlSize(.small)
                Button("OK") { m.etat = .attente }.controlSize(.small)
            }
        case .erreur(let quoi):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(quoi).font(.caption).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("OK") { m.etat = .attente }.controlSize(.small)
            }
        }
    }
}

/// La fenêtre de la barre : collée sous le Finder de Side (au-dessus s'il arrive du bas), elle le suit et part avec lui.
final class BarreCommande {
    static let commun = BarreCommande()
    static var active: Bool {
        get { UserDefaults.standard.object(forKey: "barreCommande") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "barreCommande") }
    }
    let modele = ModeleBarre()
    private var panneau: NSPanel?
    private var veille: Timer?

    private final class PanneauClavier: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    /// Le cadre de la barre à l'écran (pour que Side ne se referme pas quand on clique dedans).
    var cadre: NSRect? { panneau?.isVisible == true ? panneau?.frame : nil }

    private var enMouvement = false

    /// Le Finder arrive ou repart : la barre se cale sur sa position à l'écran, image par image, pendant tout son
    /// glissement. Elle reste ainsi collée sous lui (une animation à part n'allait pas au même rythme : elle se retrouvait
    /// au milieu de l'écran pendant que le Finder descendait encore).
    /// Le Finder arrive : la barre est posée à sa place décalée du même écart que la carte, invisible. Side l'anime
    /// ensuite dans la même animation que la carte (comme la zone de dépôt), jusqu'à `arrivee`.
    func preparerArrivee(decalage: NSPoint) -> (panneau: NSPanel, arrivee: NSRect)? {
        guard BarreCommande.active, Partie.finder.active else { return nil }
        let p = panneau ?? creer()
        panneau = p
        switch modele.etat { case .fini, .erreur, .proposition: modele.etat = .attente; default: break }     // on repart d'une barre vide
        modele.selection = Array(Selection.shared.urls).sorted { $0.path < $1.path }
        veille?.invalidate(); veille = nil
        guard let cible = cadreCible() else { return nil }
        enMouvement = true
        p.alphaValue = 0
        p.setFrame(cible.offsetBy(dx: decalage.x, dy: decalage.y), display: false)
        p.orderFrontRegardless()
        return (p, cible)
    }
    func arrivee() {
        enMouvement = false
        panneau?.alphaValue = 1
        placer()
        suivre()
    }
    /// Le Finder repart : Side anime la barre avec lui. Renvoie sa fenêtre si elle est à l'écran.
    func preparerDepart() -> NSPanel? {
        veille?.invalidate(); veille = nil
        guard let p = panneau, p.isVisible else { return nil }
        enMouvement = true
        return p
    }
    func departFini() { enMouvement = false }

    /// Fermeture sans animation du Finder : la barre s'efface aussitôt (sauf si elle est déjà en train de partir avec lui).
    func cacherSiImmobile() { if !enMouvement { cacher() } }

    private func suivre() {
        veille?.invalidate()
        veille = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            let sel = Array(Selection.shared.urls).sorted { $0.path < $1.path }
            if !self.modele.enEssai, sel != self.modele.selection {
                self.modele.selection = sel
                if case .proposition = self.modele.etat { self.modele.etat = .attente }
            }
            self.placer()
        }
    }

    func cacher() {
        veille?.invalidate(); veille = nil
        guard let p = panneau, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.12; p.animator().alphaValue = 0 }) { p.orderOut(nil) }
    }

    /// Pour les essais : la demande est comprise puis lancée sans attendre Entrée ; le résultat va au journal du tiroir.
    func essai(_ demande: String, _ fichiers: [URL]) {
        modele.enEssai = true
        modele.selection = fichiers
        modele.texte = demande
        modele.envoyer()
        func attendre(_ n: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                switch self.modele.etat {
                case .proposition(let a, let u): journalBas("barre : « %@ » → %@", demande, a.description(u.count)); self.modele.lancer(a, u); attendre(n - 1)
                case .fini(let quoi, let faits): journalBas("barre : %@ — %@", quoi, faits.map(\.lastPathComponent).joined(separator: ", ")); self.modele.enEssai = false
                case .erreur(let quoi): journalBas("barre : « %@ » → erreur : %@", demande, quoi); self.modele.enEssai = false
                default: if n > 0 { attendre(n - 1) }
                }
            }
        }
        attendre(100)
    }

    private func hauteur() -> CGFloat {
        switch modele.etat {
        case .proposition: return 84
        case .erreur: return 78
        case .fini: return 70
        default: return 38              // une pilule, une seule ligne
        }
    }

    private func cadreCible() -> NSRect? {
        let c = AppDelegate.shared.cadreFinder
        guard c.width > 100 else { return nil }
        let h = hauteur()
        let enDessous = Config.shared.bord != .bas
        return NSRect(x: c.minX, y: enDessous ? c.minY - 10 - h : c.maxY + 10, width: c.width, height: h)
    }

    private func placer() {
        guard let p = panneau, !enMouvement, let f = cadreCible() else { return }
        if p.frame != f { p.setFrame(f, display: true) }
    }

    private func creer() -> NSPanel {
        let p = PanneauClavier(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.animationBehavior = .none
        p.contentView = NSHostingView(rootView: VueBarre(m: modele))
        return p
    }
}
