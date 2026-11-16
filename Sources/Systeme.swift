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
    private var vues: Set<String> = []   // captures déjà traitées depuis le lancement

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
        for url in urls where !vues.contains(url.path) {
            vues.insert(url.path)
            guard Config.shared.capturesAuto, FileManager.default.fileExists(atPath: url.path) else { continue }
            AppDelegate.shared.recevoirCapture(url)
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
