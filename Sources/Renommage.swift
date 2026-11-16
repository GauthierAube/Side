// Renommer sur place, comme dans le Finder (16/11/2026) : Entrée (ou « Renommer » du clic droit) rend le nom modifiable
// là où il est affiché, surligné en bleu sans son extension. Entrée valide, Échap annule, un clic ailleurs valide.
// Avant, une fenêtre de question s'ouvrait, et elle passait derrière la carte.

import AppKit
import SwiftUI

/// Le fichier en train d'être renommé (un seul à la fois).
final class Renommage: ObservableObject {
    static let shared = Renommage()
    @Published var url: URL?
}

/// Le nom d'un fichier tel que la vue l'affiche, ou le champ pour le renommer quand c'est son tour.
struct NomFichier<Etiquette: View>: View {
    let item: FileItem
    @ViewBuilder let etiquette: () -> Etiquette
    @ObservedObject private var renommage = Renommage.shared

    var body: some View {
        if renommage.url == item.url {
            ChampRenommage(url: item.url).frame(minWidth: 80)
        } else {
            etiquette()
        }
    }
}

struct ChampRenommage: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinateur { Coordinateur(url) }

    func makeNSView(context: Context) -> NSTextField {
        let t = NSTextField(string: url.lastPathComponent)
        t.delegate = context.coordinator
        t.isBordered = true
        t.drawsBackground = true
        t.backgroundColor = .textBackgroundColor
        t.focusRingType = .exterior
        t.font = .systemFont(ofSize: NSFont.systemFontSize)
        t.cell?.isScrollable = true
        t.cell?.wraps = false
        // Le champ prend le clavier dès qu'il est posé, avec le nom choisi sans son extension (comme le Finder).
        DispatchQueue.main.async {
            guard let w = t.window else { return }
            w.makeFirstResponder(t)
            let nom = url.lastPathComponent as NSString
            let ext = url.pathExtension as NSString
            let longueur = ext.length == 0 || url.hasDirectoryPath ? nom.length : nom.length - ext.length - 1
            t.currentEditor()?.selectedRange = NSRange(location: 0, length: max(0, longueur))
        }
        return t
    }

    func updateNSView(_ t: NSTextField, context: Context) {}

    final class Coordinateur: NSObject, NSTextFieldDelegate {
        let url: URL
        private var fini = false
        init(_ url: URL) { self.url = url }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selecteur: Selector) -> Bool {
            if selecteur == #selector(NSResponder.insertNewline(_:)) { valider(control.stringValue); return true }
            if selecteur == #selector(NSResponder.cancelOperation(_:)) { annuler(); return true }
            return false
        }
        /// Clic ailleurs, ou la carte change de sélection : le nom tapé est gardé, comme dans le Finder.
        func controlTextDidEndEditing(_ note: Notification) {
            if let t = note.object as? NSTextField { valider(t.stringValue) }
        }

        private func valider(_ nom: String) {
            guard !fini else { return }
            fini = true
            Renommage.shared.url = nil
            AppDelegate.shared.renommer(url, en: nom)
        }
        private func annuler() {
            guard !fini else { return }
            fini = true
            Renommage.shared.url = nil
        }
    }
}
