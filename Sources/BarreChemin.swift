import SwiftUI

/// Le fil d'Ariane en bas de la grande zone, comme la barre du chemin du Finder
/// (Présentation › Afficher la barre du chemin) : où l'on se trouve, du dossier de départ
/// (le dossier personnel, iCloud Drive ou le disque) jusqu'au dossier ouvert, ou jusqu'à
/// l'élément sélectionné. Cliquer un dossier du chemin l'affiche.
struct BarreChemin: View {
    @ObservedObject var column: Column
    let store: Store
    @ObservedObject private var selection = Selection.shared

    /// Le chemin affiché, du plus haut au plus bas.
    private var chemin: [URL] {
        let bout: URL?
        if selection.colonne === column, let choisi = selection.url, column.resultats == nil { bout = choisi }
        else { bout = column.courant }
        guard let bout else { return [] }
        return Fichiers.ascendants(bout).reversed()
    }

    var body: some View {
        let liste = chemin
        if !liste.isEmpty { barre(liste) }
    }

    private func barre(_ liste: [URL]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(liste.enumerated()), id: \.offset) { rang, url in
                if rang > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                morceau(url, dernier: rang == liste.count - 1)
                    // Le dernier élément garde son nom en entier ; les dossiers du milieu se raccourcissent d'abord.
                    .layoutPriority(rang == liste.count - 1 ? 2 : (rang == 0 ? 1 : 0))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { Divider() }
    }

    private func morceau(_ url: URL, dernier: Bool) -> some View {
        Button { ouvrir(url) } label: {
            HStack(spacing: 4) {
                Image(nsImage: Icones.petite(url.path))
                    .resizable().frame(width: 14, height: 14)
                Text(Fichiers.nom(url))
                    .font(.system(size: 11))
                    .foregroundStyle(dernier ? Color.primary : Color.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 4)
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(url.path)
        .accessibilityLabel("Aller à \(Fichiers.nom(url))")
    }

    /// Affiche ce dossier. S'il fait déjà partie du chemin ouvert, on y remonte (Précédent et Suivant
    /// restent utilisables) ; sinon il s'ouvre dans la grande zone. Un fichier s'ouvre comme dans le Finder.
    private func ouvrir(_ url: URL) {
        var dossier: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &dossier) else { return }
        let estDossier = dossier.boolValue && !NSWorkspace.shared.isFilePackage(atPath: url.path)
        guard estDossier else { AppDelegate.shared.ouvrir(url); return }
        let u = url.standardizedFileURL
        if let i = column.pile.firstIndex(where: { $0.standardizedFileURL == u }) {
            column.tronquer(i + 1)
        } else if column.racine?.standardizedFileURL == u {
            column.tronquer(0)
        } else if let ici = column.courant, u.deletingLastPathComponent() == ici.standardizedFileURL {
            column.entrer(url)   // le dossier sélectionné : on y entre, sans perdre Précédent
        } else {
            store.naviguer(.folder(url))
        }
        Selection.shared.url = nil
    }
}
