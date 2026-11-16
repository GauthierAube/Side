// Présentation « Arborescence », comme l'Explorateur de Windows (16/11/2026) : à gauche, l'arbre des dossiers, que l'on
// déplie par leur chevron ; à droite, le contenu du dossier choisi, en liste détaillée (nom, date, taille).
// Un clic sur un dossier de l'arbre l'affiche à droite ; son chevron le déplie sans changer de dossier.
// Entrer dans un dossier à droite (double-clic) déplie l'arbre jusqu'à lui.

import AppKit
import SwiftUI

/// Les sous-dossiers de chaque dossier déplié, lus hors du fil principal et gardés en mémoire.
final class ArbreModele: ObservableObject {
    /// Change à chaque lecture terminée, pour redessiner l'arbre.
    @Published var version = 0
    private var cache: [String: [FileItem]] = [:]
    private var enCours: Set<String> = []

    /// Les sous-dossiers de ce dossier, ou rien s'ils ne sont pas encore lus.
    /// Sur le disque du Mac, la lecture est immédiate : l'arbre s'affiche complet du premier coup.
    /// Sur un disque externe ou un serveur, elle se fait à part, pour ne jamais figer la carte.
    func sousDossiers(_ url: URL) -> [FileItem]? {
        let cle = url.standardizedFileURL.path
        if let d = cache[cle] { return d }
        if !cle.hasPrefix("/Volumes/") {
            let d = Fichiers.contenu(url, tri: .nom).filter(\.isFolder)
            cache[cle] = d
            return d
        }
        relire(url)
        return nil
    }

    /// Relit ce dossier hors du fil principal (son contenu a pu changer).
    func relire(_ url: URL) {
        let cle = url.standardizedFileURL.path
        guard !enCours.contains(cle) else { return }
        enCours.insert(cle)
        DispatchQueue.global(qos: .userInitiated).async {
            let dossiers = Fichiers.contenu(url, tri: .nom).filter(\.isFolder)
            DispatchQueue.main.async {
                self.enCours.remove(cle)
                if self.cache[cle] != dossiers { self.cache[cle] = dossiers; self.version += 1 }
            }
        }
    }
}

struct ArbreView: View {
    @ObservedObject var column: Column
    @StateObject private var modele = ArbreModele()
    /// Les dossiers dépliés à la main (ceux du chemin affiché le sont toujours).
    @State private var deplies: Set<String> = []
    /// Les dossiers du chemin affiché que l'on a repliés à la main.
    @State private var replies: Set<String> = []
    @AppStorage("largeurArbre") private var largeur: Double = 230

    private struct Ligne: Identifiable {
        let url: URL
        let nom: String
        let niveau: Int
        var id: String { url.standardizedFileURL.path }
    }

    private func cle(_ u: URL) -> String { u.standardizedFileURL.path }
    private var chemin: Set<String> { Set(column.pile.dropLast().map(cle)) }
    private func estDeplie(_ u: URL, racine: URL) -> Bool {
        let c = cle(u)
        if c == cle(racine) { return !replies.contains(c) }
        return (deplies.contains(c) || chemin.contains(c)) && !replies.contains(c)
    }

    /// L'arbre mis à plat : chaque dossier visible, avec sa profondeur.
    private func lignes(_ racine: URL) -> [Ligne] {
        var resultat: [Ligne] = []
        func ajouter(_ u: URL, _ nom: String, _ niveau: Int) {
            resultat.append(Ligne(url: u, nom: nom, niveau: niveau))
            guard estDeplie(u, racine: racine), niveau < 40 else { return }
            for e in modele.sousDossiers(u) ?? [] { ajouter(e.url, e.name, niveau + 1) }
        }
        ajouter(racine, FileManager.default.displayName(atPath: racine.path), 0)
        return resultat
    }

    /// Affiche ce dossier de l'arbre à droite : le chemin depuis la racine devient le chemin de la colonne.
    private func afficher(_ u: URL, racine: URL) {
        var pile: [URL] = []
        var d = racine.standardizedFileURL
        for composant in u.standardizedFileURL.pathComponents.dropFirst(d.pathComponents.count) {
            d = d.appendingPathComponent(composant)
            pile.append(d)
        }
        column.filtre = ""
        column.pile = pile
        column.reload()
        Selection.shared.choisir(nil, nil)
    }

    private func basculer(_ u: URL, racine: URL) {
        let c = cle(u)
        if estDeplie(u, racine: racine) { deplies.remove(c); replies.insert(c) }
        else { replies.remove(c); deplies.insert(c) }
    }

    var body: some View {
        if let racine = column.racine {
            let courant = cle(column.courant ?? racine)
            HStack(spacing: 0) {
                ScrollViewReader { defilement in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(lignes(racine)) { l in
                                LigneArbre(nom: l.nom, url: l.url, niveau: l.niveau, choisi: l.id == courant,
                                           deplie: estDeplie(l.url, racine: racine),
                                           vide: modele.sousDossiers(l.url).map(\.isEmpty) ?? false,
                                           basculer: { basculer(l.url, racine: racine) },
                                           afficher: { afficher(l.url, racine: racine) })
                                    .id(l.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: courant) { _, c in withAnimation(Mouvement.bascule) { defilement.scrollTo(c) } }
                }
                .frame(width: CGFloat(largeur))
                .layoutPriority(1)
                Poignee(valeur: $largeur, mini: 150, maxi: 520)
                GeometryReader { geo in
                // Liste détaillée (date et taille) quand la place le permet ; sinon les noms seuls.
                let details = geo.size.width >= 380
                VStack(spacing: 0) {
                    // Les en-têtes de la liste détaillée, comme dans l'Explorateur.
                    HStack(spacing: 8) {
                        Text("Nom").frame(maxWidth: .infinity, alignment: .leading)
                        if details {
                            Text("Modifié le").frame(width: 86, alignment: .trailing)
                            Text("Taille").frame(width: 64, alignment: .trailing)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 14).padding(.trailing, 30).padding(.vertical, 5)
                    Divider()
                    if column.visibles.isEmpty {
                        Text(column.charge ? "Chargement…" : "Aucun élément")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollViewReader { defilement in
                            ScrollView {
                                LazyVStack(spacing: 1) {
                                    ForEach(column.visibles) { item in RowView(item: item, column: column, large: details) }
                                }
                                .padding(6)
                            }
                            .onReceive(Selection.shared.changements) { url in
                                if let url, Selection.shared.colonne === column { defilement.scrollTo(url) }
                            }
                        }
                    }
                }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear { chargerLeChemin(racine) }
            .onChange(of: column.pile) { _, _ in chargerLeChemin(racine) }
            .onChange(of: column.items) { _, _ in if let c = column.courant { modele.relire(c) } }
        }
    }

    /// Les dossiers du chemin affiché sont dépliés : leurs sous-dossiers sont lus.
    private func chargerLeChemin(_ racine: URL) {
        for u in column.pile.dropLast() { replies.remove(cle(u)) }
    }
}

private struct LigneArbre: View {
    let nom: String
    let url: URL
    let niveau: Int
    let choisi: Bool
    let deplie: Bool
    let vide: Bool
    let basculer: () -> Void
    let afficher: () -> Void
    @State private var survol = false
    @State private var depot = false

    var body: some View {
        HStack(spacing: 4) {
            // Le chevron déplie ou replie, sans changer de dossier (rien pour un dossier sans sous-dossier).
            Image(systemName: deplie ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(choisi ? Color.white.opacity(0.85) : Color.secondary)
                .frame(width: 16, height: 18)
                .contentShape(Rectangle())
                .opacity(vide ? 0 : 1)
                .onTapGesture { if !vide { basculer() } }
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
            Text(nom).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .foregroundStyle(choisi ? Color.white : Color.primary)
        .padding(.leading, CGFloat(niveau) * 16 + 4).padding(.trailing, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: Rayon.ligne).fill(
            depot ? Color.accentColor.opacity(0.35) : (choisi ? Selection.bleu : (survol ? Gris.moyen : .clear))))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture { afficher() }
        .simultaneousGesture(TapGesture(count: 2).onEnded { if !vide { basculer() } })
        // On peut déposer des fichiers sur un dossier de l'arbre, comme dans l'Explorateur.
        .modifier(Depot(action: { AppDelegate.shared.deposer($0, dans: url) }, cible: $depot))
        .help(nom)
    }
}
