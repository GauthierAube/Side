// L'historique du copier-coller (le contenu ; le volet est dans PresseVolet.swift).
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Un élément copié.
struct Copie: Identifiable {
    var id = UUID()   // gardé sur le disque : c'est lui qui relie un même élément sur tes deux Mac
    var date: Date
    var texte: String?
    var fichiers: [URL] = []
    var image: NSImage?
    var fichierImage: String?   // nom du fichier PNG où l'image est gardée, pour la retrouver après un redémarrage
    var secret = false   // marqué « mot de passe » par l'app d'origine : affiché masqué
    var epingle = false  // épinglé : reste en haut de la liste, et survit à « Effacer »
    var modifie = Date() // dernier changement (copié, recopié, épinglé) : le plus récent l'emporte entre deux Mac
}

final class PressePapiers: ObservableObject {
    static let shared = PressePapiers()
    static let maximum = 300
    static let duree: TimeInterval = 7 * 86400   // l'historique est gardé sept jours
    @Published var elements: [Copie] = PressePapiers.charger()
    private var compte = NSPasteboard.general.changeCount

    /// Les éléments épinglés d'abord, puis les autres du plus récent au plus ancien.
    var tries: [Copie] { elements.filter(\.epingle) + elements.filter { !$0.epingle } }

    /// Au-delà, les images les plus anciennes sont oubliées (elles pèsent lourd, en mémoire comme sur le disque).
    static let maximumImages = 40

    /// Ce qui est écrit sur le disque : les textes, les fichiers et les images copiés, jamais les mots de passe.
    private struct Ligne: Codable { var date: Date; var texte: String?; var fichiers: [String]; var epingle: Bool; var image: String?; var id: UUID?; var modifie: Date? }
    private static var fichier: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Side/presse-papiers.json")
    }
    /// Le dossier des images copiées, lisible par toi seul.
    static var dossierImages: URL { fichier.deletingLastPathComponent().appendingPathComponent("images", isDirectory: true) }
    private static func charger() -> [Copie] {
        var copies: [Copie] = []
        if let data = try? Data(contentsOf: fichier), let lignes = try? JSONDecoder().decode([Ligne].self, from: data) {
            let limite = Date().addingTimeInterval(-duree)
            copies = lignes.filter { $0.epingle || $0.date > limite }.compactMap { l in
                var c = Copie(id: l.id ?? UUID(), date: l.date, texte: l.texte, fichiers: l.fichiers.map { URL(fileURLWithPath: $0) }, epingle: l.epingle, modifie: l.modifie ?? l.date)
                if let nom = l.image {
                    guard let image = NSImage(contentsOf: dossierImages.appendingPathComponent(nom)) else { return nil }
                    c.image = image
                    c.fichierImage = nom
                }
                return c
            }
        } else {
            // Ancienne version : seuls les textes épinglés étaient gardés, dans les réglages.
            copies = (UserDefaults.standard.stringArray(forKey: "presseEpingles") ?? []).map { Copie(date: Date(), texte: $0, epingle: true) }
        }
        return copies
    }
    /// `partager` : prévenir l'autre Mac (faux quand on écrit justement ce qui vient de lui).
    func sauver(partager: Bool = true) {
        let fm = FileManager.default
        // Les images nouvelles : écrites en PNG, à côté, sans faire attendre l'interface.
        for i in elements.indices where elements[i].image != nil && elements[i].fichierImage == nil && !elements[i].secret {
            let nom = UUID().uuidString + ".png", image = elements[i].image!
            elements[i].fichierImage = nom
            let dossier = Self.dossierImages
            DispatchQueue.global(qos: .utility).async {
                guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { return }
                try? fm.createDirectory(at: dossier, withIntermediateDirectories: true)
                try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dossier.path)
                let url = dossier.appendingPathComponent(nom)
                try? png.write(to: url, options: .atomic)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        }
        // Les images qui ne sont plus dans l'historique : effacées du disque.
        let gardees = Set(elements.compactMap(\.fichierImage))
        for f in (try? fm.contentsOfDirectory(atPath: Self.dossierImages.path)) ?? [] where !gardees.contains(f) {
            try? fm.removeItem(at: Self.dossierImages.appendingPathComponent(f))
        }
        let lignes = elements.filter { !$0.secret && ($0.texte != nil || !$0.fichiers.isEmpty || $0.fichierImage != nil) }
            .map { Ligne(date: $0.date, texte: $0.texte, fichiers: $0.fichiers.map(\.path), epingle: $0.epingle, image: $0.fichierImage, id: $0.id, modifie: $0.modifie) }
        let url = Self.fichier
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(lignes) else { return }
        try? data.write(to: url, options: .atomic)
        // Lisible par toi seul.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        UserDefaults.standard.removeObject(forKey: "presseEpingles")
        if partager { SynchroPresse.commun.plusTard() }
    }
    /// Oublie ce qui a plus de sept jours (sauf les épinglés).
    func purger() {
        let limite = Date().addingTimeInterval(-Self.duree)
        elements.removeAll { !$0.epingle && $0.date < limite }
    }
    func epingler(_ c: Copie) {
        guard let i = elements.firstIndex(where: { $0.id == c.id }) else { return }
        elements[i].epingle.toggle()
        elements[i].modifie = Date()
        sauver()
    }
    /// Historique désactivé : tout est effacé, y compris sur le disque.
    func toutEffacer() {
        elements = []
        try? FileManager.default.removeItem(at: Self.fichier)
        try? FileManager.default.removeItem(at: Self.dossierImages)
        UserDefaults.standard.removeObject(forKey: "presseEpingles")
    }

    /// Appelé régulièrement : enregistre ce qui vient d'être copié.
    func verifier() {
        let pb = NSPasteboard.general
        guard pb.changeCount != compte else { return }
        compte = pb.changeCount
        guard Config.shared.historique else { return }
        let types = pb.types?.map(\.rawValue) ?? []
        // Convention des gestionnaires de mots de passe : « éphémère » = à ne jamais garder, « caché » = secret.
        if types.contains("org.nspasteboard.TransientType") { return }
        let secret = types.contains("org.nspasteboard.ConcealedType")
        if secret && !Config.shared.historiqueSecrets { return }
        var copie = Copie(date: Date(), secret: secret)
        // Une image copiée depuis un navigateur arrive souvent avec son adresse en texte : c'est l'image qu'on garde.
        // (Un texte véritable, lui, l'emporte sur l'image que certaines applis joignent, comme un tableur.)
        let typesImage: Set<String> = ["public.png", "public.tiff", "public.jpeg", "com.compuserve.gif", "public.heic", "org.webmproject.webp"]
        let texteBrut = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let texteEstUneAdresse = !texteBrut.contains(where: \.isWhitespace) && (URL(string: texteBrut)?.scheme.map { ["http", "https", "file", "data"].contains($0.lowercased()) } ?? false)
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            copie.fichiers = urls
        } else if types.contains(where: typesImage.contains), texteBrut.isEmpty || texteEstUneAdresse, let image = NSImage(pasteboard: pb) {
            copie.image = image
        } else if let texte = pb.string(forType: .string), !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Un texte énorme (un journal de plusieurs Mo) n'entre pas dans l'historique : il serait réécrit sur le disque
            // à chaque copie pendant sept jours, et ralentirait le volet.
            guard texte.utf8.count < 1_000_000 else { return }
            copie.texte = texte
        } else if let image = NSImage(pasteboard: pb) {
            copie.image = image
        } else { return }
        // Recopier la même chose ne crée pas de doublon : l'élément remonte en tête.
        if let i = elements.firstIndex(where: { $0.texte == copie.texte && $0.fichiers == copie.fichiers && $0.image == nil && copie.image == nil }) {
            copie.epingle = elements[i].epingle   // un élément épinglé le reste
            elements.remove(at: i)
        }
        elements.insert(copie, at: 0)
        // Au-delà de la limite, on oublie les plus anciens — jamais les épinglés.
        while elements.count > Self.maximum, let i = elements.lastIndex(where: { !$0.epingle }) { elements.remove(at: i) }
        while elements.filter({ $0.image != nil && !$0.epingle }).count > Self.maximumImages,
              let i = elements.lastIndex(where: { $0.image != nil && !$0.epingle }) { elements.remove(at: i) }
        purger()
        sauver()
    }

    /// Remet un élément dans le presse-papiers, prêt à être collé.
    func recopier(_ c: Copie) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if !c.fichiers.isEmpty { pb.writeObjects(c.fichiers as [NSURL]) }
        else if let image = c.image { pb.writeObjects([image]) }
        else if let texte = c.texte { pb.setString(texte, forType: .string) }
        compte = pb.changeCount
        if let i = elements.firstIndex(where: { $0.id == c.id }) {
            var repris = elements.remove(at: i)
            repris.date = Date()   // réutilisé : il repart pour sept jours
            repris.modifie = repris.date
            elements.insert(repris, at: 0)
            sauver()
        }
    }

    /// Met un texte dans le presse-papiers sans l'ajouter à l'historique (un lien gardé, par exemple).
    func ecrireSansHistorique(_ texte: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(texte, forType: .string)
        compte = pb.changeCount
    }

    func supprimer(_ c: Copie) {
        SynchroPresse.commun.oublier([c.id])   // pour que l'autre Mac l'efface aussi
        elements.removeAll { $0.id == c.id }; sauver()
    }
    func vider() {
        SynchroPresse.commun.oublier(elements.filter { !$0.epingle }.map(\.id))
        elements.removeAll { !$0.epingle }; sauver()
    }
}
