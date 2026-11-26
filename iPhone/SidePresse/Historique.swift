// L'historique affiché dans l'app. Le stockage (iCloud, boîte, aperçu du widget) est dans Commun/Stockage.swift.
import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class Presse: ObservableObject {
    @Published private(set) var elements: [Element] = []
    @Published private(set) var liens: [Lien] = []
    @Published private(set) var choisi: Bool
    @Published var message = ""
    @Published var annonce: String?

    private let file = DispatchQueue(label: "presse")
    private let d = UserDefaults.standard
    private var aCopier: UUID?   // demandé par le widget avant que l'historique soit chargé

    init() {
        // Le marque-page de la version 1.0 était rangé dans l'app seule : on le passe au trousseau (widget, Partager).
        if Trousseau.lire(Stockage.cle) == nil, let vieux = d.data(forKey: "dossierSide") {
            Trousseau.ecrire(vieux, Stockage.cle)
        }
        choisi = Stockage.dossier() != nil
    }

    func choisir(_ url: URL) {
        guard Stockage.garder(url) else { message = "Impossible de garder ce dossier."; return }
        choisi = true
        recharger()
    }

    // MARK: Lire et écrire (hors de l'écran principal : un fichier pas encore descendu d'iCloud peut prendre du temps)

    private func enFond<T>(_ travail: @escaping () -> T, puis: @escaping @MainActor (T) -> Void) {
        file.async {
            let r = travail()
            DispatchQueue.main.async { MainActor.assumeIsolated { puis(r) } }
        }
    }

    func recharger() {
        guard choisi else { return }
        enFond({ () -> (Historique?, Liens?, Bool) in
            Boite.vider()
            return Stockage.acceder { d -> (Historique?, Liens?, Bool) in
                let h = Stockage.historique(dans: d)
                let change = h.map { Apercu.construire(Stockage.visibles($0), dossier: d) } ?? false
                return (h, Stockage.liens(dans: d), change)
            } ?? (nil, nil, false)
        }, puis: { [weak self] (h, l, change) in
            guard let self else { return }
            if let h { self.publier(h) }
            if let l, l.liens != self.liens { self.liens = l.liens }
            if change { WidgetCenter.shared.reloadAllTimelines() }
            self.message = h == nil ? "Pas encore d'historique dans ce dossier." : ""
        })
    }

    private func publier(_ h: Historique) {
        let visibles = Stockage.visibles(h)
        if visibles != elements { elements = visibles }
        if let id = aCopier, let e = elements.first(where: { $0.id == id }) { aCopier = nil; copier(e) }
    }

    private func modifier(_ changement: @escaping (inout Historique, URL) -> Void) {
        enFond({ () -> Historique? in
            Stockage.acceder { d in
                let h = Stockage.modifier(dans: d, changement)
                if let h, Apercu.construire(Stockage.visibles(h), dossier: d) { WidgetCenter.shared.reloadAllTimelines() }
                return h
            }
        }, puis: { [weak self] h in
            if let h { self?.publier(h) } else { self?.message = "Impossible d'écrire dans iCloud Drive." }
        })
    }

    // MARK: Les gestes

    func ajouter(texte: String) {
        guard !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        annoncer("Ajouté : " + texte.prefix(40))
        modifier(Stockage.ajout(texte: texte))
    }

    func ajouter(image: UIImage) {
        guard let png = image.pngData() else { return }
        annoncer("Image ajoutée")
        modifier(Stockage.ajout(png: png))
    }

    func effacer(_ e: Element) {
        elements.removeAll { $0.id == e.id }
        modifier { h, _ in
            h.supprimes[e.id.uuidString] = Date()
            h.elements.removeAll { $0.id == e.id }
        }
    }

    func epingler(_ e: Element) {
        modifier { h, _ in
            guard let i = h.elements.firstIndex(where: { $0.id == e.id }) else { return }
            h.elements[i].epingle.toggle(); h.elements[i].modifie = Date()
        }
    }

    /// Recopié : remonte en haut ici et sur les Mac (comme quand on recolle un élément dans Side).
    private func remonter(_ e: Element) {
        modifier { h, _ in
            guard let i = h.elements.firstIndex(where: { $0.id == e.id }) else { return }
            h.elements[i].date = Date(); h.elements[i].modifie = Date()
        }
    }

    private func annoncer(_ texte: String) {
        withAnimation { annonce = texte }
        Task { try? await Task.sleep(for: .seconds(2)); withAnimation { if annonce == texte { annonce = nil } } }
    }

    // MARK: Les images

    private var cache: [String: UIImage] = [:]
    func image(_ nom: String) -> UIImage? {
        if let i = cache[nom] { return i }
        let i = Stockage.acceder { d -> UIImage? in
            let url = d.appendingPathComponent("Presse-papiers images").appendingPathComponent(nom)
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return UIImage(contentsOfFile: url.path)
        }
        if let i { cache[nom] = i }
        return i
    }

    // MARK: Le presse-papiers de l'iPhone

    /// À l'ouverture : ce qui a été copié sur l'iPhone depuis la dernière fois rejoint l'historique.
    /// (iOS demande la permission de coller ; Réglages > Side > « Coller depuis d'autres apps » : Autoriser, pour ne plus la voir.)
    func capturer() {
        guard choisi else { return }
        let pb = UIPasteboard.general
        let compte = pb.changeCount
        guard compte != d.integer(forKey: "dernierCompte") else { return }
        d.set(compte, forKey: "dernierCompte")
        if pb.hasStrings, let t = pb.string { ajouter(texte: t) }
        else if pb.hasImages, let i = pb.image { ajouter(image: i) }
    }

    func copier(_ e: Element) {
        let pb = UIPasteboard.general
        if let t = e.texte { pb.string = t } else if let nom = e.image, let i = image(nom) { pb.image = i }
        d.set(pb.changeCount, forKey: "dernierCompte")   // c'est nous : pas à recapturer
        annoncer(e.texte.map { "Copié : " + $0.prefix(40) } ?? "Image copiée")
        remonter(e)
    }

    func copier(_ l: Lien) {
        UIPasteboard.general.string = l.texte
        d.set(UIPasteboard.general.changeCount, forKey: "dernierCompte")
        annoncer("Copié : " + (l.titre.isEmpty ? l.texte : l.titre).prefix(40))
    }

    /// side-presse://copier?id=… (une ligne du widget)
    func ouvrir(_ url: URL) {
        guard url.host == "copier",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
              let uuid = UUID(uuidString: id) else { return }
        if let e = elements.first(where: { $0.id == uuid }) { copier(e) } else { aCopier = uuid; recharger() }
    }
}
