// Ce que Side lit de macOS : captures d'écran en cours, raccourcis du système.
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Repère chaque nouvelle capture d'écran grâce à l'index du Mac (Spotlight marque les captures comme telles,
/// où qu'elles soient enregistrées), et la range dans une zone de dépôt.
final class Captures: NSObject {
    static let shared = Captures()
    private let requete = NSMetadataQuery()
    private var depart = Date()
    private var vues: Set<String> = []   // captures déjà traitées depuis le lancement (emplacement, et identité du fichier)
    /// Les noms se demandent un par un, hors du fil principal : le modèle met plusieurs secondes à répondre.
    private let fileDesNoms = DispatchQueue(label: "side.captures.noms", qos: .utility)

    func demarrer() {
        depart = Date()
        requete.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemContentCreationDate >= %@", depart as NSDate)
        requete.searchScopes = [NSMetadataQueryLocalComputerScope]
        NotificationCenter.default.addObserver(self, selector: #selector(nouveautes), name: .NSMetadataQueryDidUpdate, object: requete)
        NotificationCenter.default.addObserver(self, selector: #selector(nouveautes), name: .NSMetadataQueryDidFinishGathering, object: requete)
        requete.start()
    }

    @objc private func nouveautes() {
        requete.disableUpdates()
        defer { requete.enableUpdates() }
        let urls = (requete.results as? [NSMetadataItem] ?? []).compactMap { item -> URL? in
            guard let chemin = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            return URL(fileURLWithPath: chemin)
        }
        for url in urls where !vues.contains(Self.cle(url)) {
            vues.insert(Self.cle(url))
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            // Une capture que Side vient de renommer revient ici sous son nouveau nom : c'est le même fichier, déjà traité.
            if let identite = Self.identite(url) {
                if vues.contains(identite) { continue }
                vues.insert(identite)
            }
            // D'abord la zone de dépôt, tout de suite ; le nouveau nom arrive quelques secondes plus tard.
            if Config.shared.capturesAuto { AppDelegate.shared.recevoirCapture(url) }
            if ConfigIA.commun.renommerCaptures { renommer(url) }
        }
    }

    /// Un emplacement, écrit toujours de la même façon (les accents ont deux écritures possibles sur le disque).
    private static func cle(_ url: URL) -> String { url.standardizedFileURL.path.precomposedStringWithCanonicalMapping }
    /// Ce qui ne change pas quand un fichier est renommé : son numéro sur le disque et sa date de création.
    private static func identite(_ url: URL) -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let numero = a[.systemFileNumber] as? NSNumber, let creation = a[.creationDate] as? Date else { return nil }
        return "fichier \(numero) \(creation.timeIntervalSince1970)"
    }

    /// Demande à l'IA locale un nom qui décrit la capture, puis renomme le fichier sur place et prévient la zone de dépôt.
    /// Serveur éteint, réponse refusée, fichier déplacé entre-temps : la capture garde son nom, sans rien dire.
    private func renommer(_ url: URL) {
        guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true else { return }   // pas les vidéos de l'écran
        let adresses = ConfigIA.adresses(ConfigIA.commun.serveurs)
        let modele = ConfigIA.modele(ConfigIA.commun.modele)
        fileDesNoms.async {
            guard let nom = NomDeCapture.proposer(url, adresses: adresses, modele: modele),
                  FileManager.default.fileExists(atPath: url.path) else { return }
            let cible = NomDeCapture.cible(pour: url, nom: nom)
            // Avant de renommer : le nouvel emplacement est noté comme déjà vu, et on retient la zone où la capture est rangée.
            let zone: Int? = DispatchQueue.main.sync {
                self.vues.insert(Self.cle(cible))
                return AppDelegate.shared.zoneDeLaCapture(url)
            }
            guard (try? FileManager.default.moveItem(at: url, to: cible)) != nil else { return }   // n'écrase jamais un fichier
            DispatchQueue.main.async { AppDelegate.shared.captureRenommee(url, cible, zone) }
        }
    }

    /// Les captures rangées par Side, pour les regrouper dans la même zone.
    static var rangees: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "capturesRangees") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "capturesRangees") }
    }
}

// MARK: - Raccourcis de macOS

/// Les raccourcis de l'app « Raccourcis », lus et lancés avec la commande `shortcuts` de macOS.
final class Raccourcis: ObservableObject {
    static let shared = Raccourcis()
    @Published var tous: [String] = []
    @Published var enCours: String?

    private init() { actualiser() }

    func actualiser() {
        DispatchQueue.global(qos: .utility).async {
            let noms = Self.commande(["list"]).split(separator: "\n").map(String.init)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            DispatchQueue.main.async { self.tous = noms }
        }
    }

    /// Lance un raccourci ; `fichiers` lui sont passés en entrée (par exemple une image à redimensionner).
    func lancer(_ nom: String, fichiers: [URL] = []) {
        enCours = nom
        DispatchQueue.global(qos: .userInitiated).async {
            var arguments = ["run", nom]
            for f in fichiers { arguments += ["-i", f.path] }
            _ = Self.commande(arguments)
            DispatchQueue.main.async { if self.enCours == nom { self.enCours = nil } }
        }
    }

    private static func commande(_ arguments: [String]) -> String {
        let p = Process(), sortie = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = arguments
        p.standardOutput = sortie
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "" }
        let data = sortie.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Les journaux de diagnostic de Side (~/Library/Logs) : au lancement, un journal de plus de 2 Mo est ramené
/// à son dernier demi-mégaoctet. Avant le 15/11/2026, ils grossissaient sans fin.
enum Journaux {
    static func raccourcir() {
        let dossier = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        for nom in ["Square.log", "Side-panneau.log"] {
            let url = dossier.appendingPathComponent(nom)
            guard let taille = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
                  taille > 2_000_000, let h = try? FileHandle(forReadingFrom: url) else { continue }
            try? h.seek(toOffset: UInt64(taille - 500_000))
            let fin = h.readDataToEndOfFile()
            try? h.close()
            // On repart au début d'une ligne.
            let reste = fin.firstIndex(of: 0x0A).map { fin[fin.index(after: $0)...] } ?? fin[...]
            try? Data(reste).write(to: url, options: .atomic)
        }
    }
}
