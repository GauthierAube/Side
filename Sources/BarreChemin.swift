import SwiftUI

/// Le fil d'Ariane en bas de la grande zone, comme la barre du chemin du Finder
/// et la barre d'adresse de l'Explorateur de Windows : où l'on se trouve, du dossier de départ
/// (le dossier personnel, iCloud Drive ou le disque) jusqu'au dossier ouvert, ou jusqu'à
/// l'élément sélectionné.
/// - Cliquer un dossier du chemin l'affiche.
/// - La flèche vers le haut, à gauche, remonte au dossier parent.
/// - Le chevron après un dossier déroule ses sous-dossiers, comme sous Windows.
struct BarreChemin: View {
    @ObservedObject var column: Column
    let store: Store
    @ObservedObject private var selection = Selection.shared

    static let hauteur: CGFloat = 40

    /// Le chemin affiché, du plus haut au plus bas.
    private var chemin: [URL] {
        let bout: URL?
        if selection.colonne === column, let choisi = selection.url, column.resultats == nil { bout = choisi }
        else { bout = column.courant }
        guard let bout else { return [] }
        return Fichiers.ascendants(bout).reversed()
    }

    /// Le dossier parent du dossier ouvert (rien quand on est déjà au départ du chemin).
    private var parent: URL? {
        guard let ici = column.courant else { return nil }
        let haut = Fichiers.ascendants(ici)
        return haut.count > 1 ? haut[1] : nil
    }

    var body: some View {
        let liste = chemin
        if !liste.isEmpty { barre(liste) }
    }

    private func barre(_ liste: [URL]) -> some View {
        // Tout le fil tient dans une pastille, posée en bas de la grande zone.
        HStack(spacing: 1) {
            boutonParent
            ForEach(Array(liste.enumerated()), id: \.offset) { rang, url in
                let dernier = rang == liste.count - 1
                if rang > 0 { sousDossiers(liste[rang - 1]) }
                morceau(url, dernier: dernier)
                    // Le dernier élément garde son nom en entier ; les dossiers du milieu se raccourcissent d'abord.
                    .layoutPriority(dernier ? 2 : (rang == 0 ? 1 : 0))
                if dernier && estDossier(url) { sousDossiers(url) }
            }
        }
        .padding(.leading, 3)
        .padding(.trailing, 6)
        .frame(height: 28)
        .background(Capsule().fill(Gris.leger))
        .overlay(Capsule().strokeBorder(Gris.filet, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10)
        .frame(height: Self.hauteur)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Remonter au dossier parent (la flèche « Haut » de l'Explorateur de Windows).
    private var boutonParent: some View {
        let actif = parent != nil
        let aide = parent.map { String(localized: "Dossier parent : \(Fichiers.nom($0))") } ?? String(localized: "Dossier parent")
        return Button { if let p = parent { aller(p) } } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(actif ? Color.primary : Color.secondary.opacity(0.5))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Gris.moyen))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!actif)
        .help(aide)
        .accessibilityLabel(aide)
    }

    private func morceau(_ url: URL, dernier: Bool) -> some View {
        MorceauChemin(url: url, dernier: dernier) { ouvrir(url) }
    }

    /// Le chevron entre deux dossiers : il déroule les sous-dossiers de celui qui le précède.
    /// La liste n'est lue qu'au clic (un menu SwiftUI la relirait à chaque affichage de la barre).
    private func sousDossiers(_ dossier: URL) -> some View {
        Button { deroulerSousDossiers(dossier) } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sous-dossiers de \(Fichiers.nom(dossier))")
        .accessibilityLabel("Sous-dossiers de \(Fichiers.nom(dossier))")
    }

    private func deroulerSousDossiers(_ dossier: URL) {
        let menu = NSMenu()
        let enfants = Fichiers.contenu(dossier, tri: .nom).filter(\.isFolder)
        if enfants.isEmpty {
            let vide = NSMenuItem(title: String(localized: "Aucun sous-dossier"), action: nil, keyEquivalent: "")
            vide.isEnabled = false
            menu.addItem(vide)
        }
        for item in enfants {
            let ligne = ElementMenu(item.name) { aller(item.url) }
            let icone = Icones.petite(item.url.path).copy() as! NSImage
            icone.size = NSSize(width: 16, height: 16)
            ligne.image = icone
            menu.addItem(ligne)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func estDossier(_ url: URL) -> Bool {
        var dossier: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dossier)
            && dossier.boolValue && !NSWorkspace.shared.isFilePackage(atPath: url.path)
    }

    /// Un élément du chemin : un dossier s'affiche, un fichier s'ouvre comme dans le Finder.
    private func ouvrir(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if estDossier(url) { aller(url) } else { AppDelegate.shared.ouvrir(url) }
    }

    /// Affiche ce dossier en gardant, si possible, le chemin déjà ouvert : on y remonte, ou l'on
    /// entre dans un sous-dossier d'un dossier du chemin (Précédent et Suivant restent utilisables).
    /// Sinon, il s'ouvre dans la grande zone.
    private func aller(_ url: URL) {
        let u = url.standardizedFileURL
        let haut = u.deletingLastPathComponent()
        let pile = column.pile.map(\.standardizedFileURL)
        if let i = pile.firstIndex(of: u) {
            column.tronquer(i + 1)
        } else if column.racine?.standardizedFileURL == u {
            column.tronquer(0)
        } else if let i = pile.firstIndex(of: haut) {
            column.tronquer(i + 1); column.entrer(url)
        } else if column.racine?.standardizedFileURL == haut {
            column.tronquer(0); column.entrer(url)
        } else {
            store.naviguer(.folder(url))
        }
        Selection.shared.url = nil
    }
}

/// Une ligne de menu qui lance une action Swift.
final class ElementMenu: NSMenuItem {
    private let geste: () -> Void
    init(_ titre: String, _ geste: @escaping () -> Void) {
        self.geste = geste
        super.init(title: titre, action: #selector(lancer), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func lancer() { geste() }
}

/// Un dossier du fil d'Ariane : son icône (une maison pour le dossier personnel) et son nom,
/// surligné au passage de la souris.
private struct MorceauChemin: View {
    let url: URL
    let dernier: Bool
    let action: () -> Void
    @State private var survol = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if url.standardizedFileURL.path == Fichiers.home.standardizedFileURL.path {
                    Image(systemName: "house.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 16, height: 16)
                } else {
                    Image(nsImage: Icones.petite(url.path))
                        .resizable().frame(width: 16, height: 16)
                }
                Text(Fichiers.nom(url))
                    .font(.system(size: 12, weight: dernier ? .medium : .regular))
                    .foregroundStyle(dernier ? Color.primary : Color.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill(survol ? Gris.moyen : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .animation(Mouvement.survol, value: survol)
        .help(url.path)
        .accessibilityLabel("Aller à \(Fichiers.nom(url))")
    }
}
