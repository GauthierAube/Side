import UIKit
import UniformTypeIdentifiers

/// « Side » dans le menu Partager : le texte, le lien ou l'image partagés rejoignent l'historique (sur le Mac aussi).
final class PartageViewController: UIViewController {
    private let etiquette = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let carte = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        carte.layer.cornerRadius = 18
        carte.clipsToBounds = true
        carte.translatesAutoresizingMaskIntoConstraints = false
        etiquette.text = "Ajout à Side…"
        etiquette.font = .preferredFont(forTextStyle: .headline)
        etiquette.textAlignment = .center
        etiquette.translatesAutoresizingMaskIntoConstraints = false
        carte.contentView.addSubview(etiquette)
        view.addSubview(carte)
        NSLayoutConstraint.activate([
            carte.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            carte.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            carte.widthAnchor.constraint(equalToConstant: 220),
            carte.heightAnchor.constraint(equalToConstant: 80),
            etiquette.centerXAnchor.constraint(equalTo: carte.contentView.centerXAnchor),
            etiquette.centerYAnchor.constraint(equalTo: carte.contentView.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            let nombre = await enregistrer()
            etiquette.text = nombre == 0 ? "Rien à ajouter" : "Ajouté à Side"
            if nombre > 0 { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            try? await Task.sleep(for: .milliseconds(700))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func enregistrer() async -> Int {
        let pieces = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var nombre = 0
        for piece in pieces {
            if piece.hasItemConformingToTypeIdentifier(UTType.image.identifier), let png = await image(piece) {
                Stockage.ajouter(png: png); nombre += 1
            } else if piece.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let url = try? await piece.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !url.isFileURL {
                Stockage.ajouter(texte: url.absoluteString); nombre += 1
            } else if piece.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let texte = try? await piece.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                Stockage.ajouter(texte: texte); nombre += 1
            }
        }
        return nombre
    }

    private func image(_ piece: NSItemProvider) async -> Data? {
        guard let objet = try? await piece.loadItem(forTypeIdentifier: UTType.image.identifier) else { return nil }
        var image: UIImage?
        if let i = objet as? UIImage { image = i }
        else if let url = objet as? URL, let data = try? Data(contentsOf: url) { image = UIImage(data: data) }
        else if let data = objet as? Data { image = UIImage(data: data) }
        return image?.pngData()
    }
}
