// Les colonnes de fichiers : listes, icônes, colonnes (Miller), aperçu, sélection.
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct ColumnView: View {
    @ObservedObject var column: Column
    let store: Store
    let large: Bool
    var fixe = false   // la grande zone : ni retirable, ni déplaçable
    var dernier = false   // dernière colonne épinglée : porte le petit bouton « + »
    @State private var depot = false
    @State private var recherche = false          // le champ de recherche est déplié
    @FocusState private var champRecherche: Bool
    @ObservedObject private var config = Config.shared

    var body: some View {
        contenu
            .contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: Rayon.vignette).strokeBorder(Color.accentColor, lineWidth: depot ? 2 : 0).padding(2))
            .modifier(Depot(action: actionDepot, cible: $depot))
            .onReceive(store.$demandeRecherche.dropFirst()) { _ in
                guard fixe else { return }                    // la grande zone seulement
                recherche = true
                DispatchQueue.main.async { champRecherche = true }
            }
    }

    /// Sur l'étagère, on pose une référence ; dans un dossier, on range le fichier.
    private var actionDepot: (([NSItemProvider]) -> Void)? {
        if column.estEtagere { return { AppDelegate.shared.poser($0, column.indexEtagere) } }
        if let dossier = column.courant { return { AppDelegate.shared.deposer($0, dans: dossier) } }
        return nil
    }

    private var contenu: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // Précédent / Suivant, toujours présents comme dans le Finder (grisés quand ils ne servent pas).
                // Les colonnes épinglées, plus étroites, ont les mêmes en un peu plus petit.
                HStack(spacing: 0) {
                    navBouton("chevron.left", column.peutRevenir, String(localized: "Dossier précédent"), etroit: !fixe) { column.revenir() }
                    Divider().frame(height: 14)
                    navBouton("chevron.right", column.peutAvancer, String(localized: "Dossier suivant"), etroit: !fixe) { column.avancer() }
                }
                .background(Capsule().fill(Gris.moyen))
                if fixe, let ici = column.courant {
                    // Cliquer le nom du dossier déroule le chemin qui y mène, comme Commande-clic sur le titre dans le Finder.
                    Menu {
                        ForEach(Array(Fichiers.ascendants(ici).enumerated()), id: \.offset) { rang, dossier in
                            Button {
                                if rang > 0 { store.naviguer(.folder(dossier)) }
                            } label: {
                                Label { Text(Fichiers.nom(dossier)) } icon: {
                                    Image(nsImage: Icones.petite(dossier.path))
                                }
                            }
                            .disabled(rang == 0)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(column.titre).font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                    .frame(minWidth: 90, alignment: .leading)   // le nom reste lisible, même sur une carte étroite
                    .layoutPriority(2)
                    .help("Afficher le chemin de ce dossier")
                    .accessibilityLabel("Chemin du dossier \(column.titre)")
                } else {
                    Text(column.titre).font(fixe ? .title3.weight(.semibold) : .headline).layoutPriority(1).lineLimit(1).truncationMode(.middle)
                        .contentShape(Rectangle())
                        .onTapGesture { if column.peutRevenir { column.revenir() } }   // cliquer le nom = revenir en arrière
                        .help(column.peutRevenir ? String(localized: "Revenir au dossier précédent") : column.titre)
                }
                Spacer(minLength: 4)
                // Colonnes épinglées, plus étroites : les boutons de présentation passent dans le menu « … »,
                // pour laisser toute la place au nom du dossier.
                if fixe {
                    HStack(spacing: 2) {
                        boutonVue(.icones, "square.grid.2x2", String(localized: "Afficher en icônes"))
                        boutonVue(.liste, "list.bullet", String(localized: "Afficher en liste"))
                        boutonVue(.colonnes, "rectangle.split.3x1", String(localized: "Afficher en colonnes"))
                        boutonVue(.arbre, "list.bullet.indent", String(localized: "Afficher en arborescence, comme l'Explorateur de Windows"))
                    }
                    .padding(3)
                    .background(Capsule().fill(Gris.moyen))
                }
                // Dans la corbeille : le bouton « Vider », comme dans le Finder.
                if case .folder(let d) = column.kind, Corbeille.est(d) {
                    Button { Corbeille.vider() } label: {
                        Text("Vider")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 11)
                            .frame(height: 28)
                            .background(Capsule().fill(Gris.moyen))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Vider la corbeille")
                    .accessibilityLabel("Vider la corbeille")
                }
                Menu {
                    if !fixe {
                        Picker("Présentation", selection: $column.presentation) {
                            Label("Icônes", systemImage: "square.grid.2x2").tag(Presentation.icones)
                            Label("Liste", systemImage: "list.bullet").tag(Presentation.liste)
                        }
                        .pickerStyle(.inline)
                        if column.presentation == .icones {
                            Picker("Colonnes de la grille", selection: $column.colonnesGrille) {
                                Text("Automatique").tag(0)
                                ForEach(1...4, id: \.self) { n in Text(n == 1 ? "1 colonne" : "\(n) colonnes").tag(n) }
                            }
                        }
                        Divider()
                    } else if column.presentation == .icones {
                        Picker("Colonnes de la grille", selection: $column.colonnesGrille) {
                            Text("Automatique").tag(0)
                            ForEach(1...6, id: \.self) { n in Text(n == 1 ? "1 colonne" : "\(n) colonnes").tag(n) }
                        }
                        Divider()
                    }
                    if column.peutTrier {
                        Picker("Trier par", selection: $column.tri) {
                            ForEach(Tri.allCases, id: \.self) { Text($0.titre).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                    if let u = column.courant {
                        Button("Ouvrir dans le Finder") { AppDelegate.shared.ouvrir(u) }
                    }
                    Divider()
                    if fixe {
                        Button("Nouvel onglet (⌘T)") { store.nouvelOnglet() }
                        if let u = column.courant {
                            Button("Épingler ce dossier en colonne") { store.ajouter(.folder(u)) }
                            Button("Épingler un autre dossier…") { AppDelegate.shared.choisirDossier() }
                            Button("Ajouter aux favoris") { store.ajouterFavori(u) }
                        }
                    } else {
                        Button("Épingler un autre dossier…") { AppDelegate.shared.choisirDossier() }
                        Button("Retirer cette colonne") { store.retirer(column) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 28)
                        .background(Capsule().fill(Gris.moyen))
                        .contentShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Autres actions")
                if fixe {
                    if recherche || !column.filtre.isEmpty {
                        // Le champ ne s'ouvre que sur demande ; fermé, il laisse la place au nom du dossier.
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Rechercher", text: $column.filtre).textFieldStyle(.plain).focused($champRecherche)
                                .onExitCommand { column.filtre = ""; recherche = false }
                            Button { column.filtre = ""; recherche = false } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Fermer la recherche")
                        }
                        .padding(.horizontal, 10)
                        .frame(width: large ? 180 : 140, height: 28)
                        .background(Capsule().fill(Gris.moyen))
                        .transition(.opacity)
                    } else {
                        Button {
                            recherche = true
                            DispatchQueue.main.async { champRecherche = true }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 30, height: 28)
                                .background(Capsule().fill(Gris.moyen))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Rechercher")
                        .accessibilityLabel("Rechercher")
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .contentShape(Rectangle())
            .modifier(Reorganisable(column: column, store: store, actif: !fixe))
            .modifier(Deplacable(actif: fixe))

            if fixe { OngletsView(store: store) }   // sous l'en-tête, comme dans le Finder

            Divider()

            if column.kind == .presse && column.pile.isEmpty {
                PressePapiersView()
            } else if fixe && column.presentation == .colonnes && column.resultats == nil && !column.rechercheEnCours {
                MillerView(column: column)
            } else if fixe && column.presentation == .arbre && column.racine != nil && column.resultats == nil && !column.rechercheEnCours {
                ArbreView(column: column)
            } else if column.visibles.isEmpty {
                Text(column.rechercheEnCours ? "Recherche…" : column.resultats != nil ? "Aucun résultat" : column.charge ? "Chargement…"
                     : (column.estEtagere ? "Dépose ici des fichiers pour les garder sous la main, puis glisse-les où tu veux." : "Aucun élément"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { defilement in
                ScrollView {
                    if column.presentation == .icones {
                        let grille = column.colonnesGrille > 0
                            ? Array(repeating: GridItem(.flexible(), spacing: CGFloat(config.espacement)), count: column.colonnesGrille)
                            : [GridItem(.adaptive(minimum: CGFloat(config.tailleIcones) + (config.texteADroite ? 150 : 56)),
                                        spacing: CGFloat(config.espacement))]
                        LazyVGrid(columns: grille, spacing: CGFloat(config.espacement) + 2) {
                            ForEach(column.visibles) { item in
                                IconView(item: item, column: column)
                            }
                        }
                        .padding(8)
                        // On retient combien d'icônes tiennent par ligne : la flèche du bas descend d'une ligne entière.
                        .background(GeometryReader { g in
                            let place = g.size.width - 16, pas = CGFloat(config.espacement)
                            let mini = CGFloat(config.tailleIcones) + (config.texteADroite ? 150 : 56)
                            let n = column.colonnesGrille > 0 ? column.colonnesGrille : max(1, Int((place + pas) / (mini + pas)))
                            Color.clear.onAppear { column.colonnesVisibles = n }.onChange(of: n) { _, v in column.colonnesVisibles = v }
                        })
                    } else {
                        LazyVStack(spacing: 1) {
                            ForEach(column.visibles) { item in
                                RowView(item: item, column: column, large: large)
                            }
                        }
                        .padding(6)
                    }
                }
                .onReceive(Selection.shared.changements) { url in
                    if let url, Selection.shared.colonne === column { defilement.scrollTo(url) }
                }
                }
            }

            // Le fil d'Ariane, en bas de la grande zone (comme la barre du chemin du Finder).
            if fixe && !(column.kind == .presse && column.pile.isEmpty) {
                BarreChemin(column: column, store: store)
            }
        }
    }

    private func navBouton(_ symbole: String, _ actif: Bool, _ aide: String, etroit: Bool = false,
                           _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: etroit ? 11 : 12, weight: .semibold))
                .foregroundStyle(actif ? Color.primary : Color.secondary.opacity(0.5))
                .frame(width: etroit ? 24 : 30, height: etroit ? 24 : 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!actif)
        .help(aide)
        .accessibilityLabel(aide)
    }

    private func boutonVue(_ p: Presentation, _ symbole: String, _ aide: String) -> some View {
        let actif = column.presentation == p
        return Button { column.presentation = p } label: {
            Image(systemName: symbole)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(actif ? Color.primary : Color.secondary)
                .frame(width: 30, height: 22)
                .background(Capsule().fill(actif ? Gris.fort : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(aide)
        .accessibilityLabel(aide)
    }
}

/// Réorganise les colonnes pendant qu'on en glisse une sur une autre.
struct DeplacementColonne: DropDelegate {
    let cible: Column
    let store: Store

    func validateDrop(info: DropInfo) -> Bool { store.glissee != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func dropEntered(info: DropInfo) {
        guard let g = store.glissee, g !== cible else { return }
        withAnimation(Mouvement.bascule) { store.deplacer(g, vers: cible) }
    }
    func performDrop(info: DropInfo) -> Bool {
        store.glissee = nil
        return true
    }
}

/// L'élément sélectionné (un seul à la fois, comme un clic simple dans le Finder).
/// Un fichier montré dans l'aperçu sous un autre nom que le sien (l'image tirée d'un SVG garde le nom du SVG).
final class ElementApercu: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?
    init(url: URL, titre: String) { previewItemURL = url; previewItemTitle = titre }
}

final class Selection: ObservableObject {
    static let shared = Selection()
    /// Le bleu de sélection du Finder (il suit la couleur d'accentuation choisie dans les Réglages Système).
    static let bleu = Color(nsColor: .selectedContentBackgroundColor)
    /// L'élément « au focus » : le dernier choisi (c'est de lui que partent les flèches, l'aperçu, Entrée pour renommer).
    /// L'interface est prévenue APRÈS le changement : prévenue avant (le fonctionnement par défaut), elle se redessinait
    /// parfois avec l'ancienne valeur, et l'affichage avait une flèche de retard.
    var url: URL? {
        didSet {
            guard url != oldValue else { return }
            // Changé directement (sans passer par les fonctions ci-dessous) : la sélection se réduit à lui.
            if let u = url { if !urls.contains(u) { urls = [u]; ancre = u } } else { urls = []; ancre = nil }
            objectWillChange.send()
            changements.send(url)
        }
    }
    /// Tous les éléments sélectionnés, comme dans le Finder (⌘-clic, Maj-clic, ⌘A, Maj + flèches).
    private(set) var urls: Set<URL> = []
    /// L'élément d'où part une sélection étendue avec Maj.
    private(set) var ancre: URL?
    /// Annonce chaque nouvelle sélection (pour faire défiler la liste jusqu'à elle).
    let changements = PassthroughSubject<URL?, Never>()
    weak var colonne: Column?

    func contient(_ u: URL) -> Bool { urls.contains(u) }
    var nombre: Int { urls.count }

    /// Un clic simple : cet élément seul.
    func choisir(_ url: URL?, _ colonne: Column?) {
        self.colonne = colonne
        urls = url.map { [$0] } ?? []
        ancre = url
        let avant = self.url
        self.url = url
        if avant == url { objectWillChange.send() }
        // Sélectionner un élément sort du champ « Rechercher » : Espace sert alors au Coup d'œil,
        // au lieu d'ajouter un espace au texte recherché.
        if url != nil { AppDelegate.shared.lacherChamp() }
    }
    /// ⌘-clic : ajoute l'élément à la sélection, ou l'en retire.
    func basculer(_ u: URL, _ colonne: Column?) {
        if self.colonne !== colonne { choisir(u, colonne); return }
        if urls.contains(u) {
            urls.remove(u)
            if url == u { let reste = urls.first; ancre = reste; changerFocus(reste) } else { objectWillChange.send() }
        } else {
            urls.insert(u)
            ancre = u
            changerFocus(u)
        }
        AppDelegate.shared.lacherChamp()
    }
    /// Maj-clic ou Maj + flèche : tout ce qui va de l'ancre à cet élément, dans l'ordre de la liste affichée.
    func etendre(jusqua u: URL, dans liste: [URL], _ colonne: Column?) {
        guard self.colonne === colonne, let a = ancre, let i = liste.firstIndex(of: a), let j = liste.firstIndex(of: u) else {
            choisir(u, colonne); return
        }
        urls = Set(liste[min(i, j)...max(i, j)])
        changerFocus(u)
        AppDelegate.shared.lacherChamp()
    }
    /// ⌘A : tout ce qui est affiché.
    func toutChoisir(_ liste: [URL], _ colonne: Column?) {
        guard !liste.isEmpty else { return }
        self.colonne = colonne
        urls = Set(liste)
        ancre = liste.first
        changerFocus(url.flatMap { liste.contains($0) ? $0 : nil } ?? liste.first)
    }
    /// Les éléments sélectionnés, dans l'ordre de la liste donnée (les autres à la fin).
    func dansLOrdre(_ liste: [URL]) -> [URL] {
        liste.filter { urls.contains($0) } + urls.filter { !liste.contains($0) }.sorted { $0.path < $1.path }
    }
    private func changerFocus(_ u: URL?) {
        if url == u { objectWillChange.send() } else { url = u }
    }
}

/// Présentation en colonnes, comme dans le Finder : chaque dossier ouvert ajoute une colonne à droite.
struct MillerView: View {
    @ObservedObject var column: Column
    @ObservedObject var config = Config.shared
    @ObservedObject private var selection = Selection.shared

    /// Le fichier sélectionné dans cette vue (nil pour un dossier : lui s'ouvre dans la colonne suivante).
    private var fichierChoisi: FileItem? {
        guard let url = selection.url, selection.colonne === column else { return nil }
        for items in column.niveaux {
            if let item = items.first(where: { $0.url == url }) { return item.isFolder ? nil : item }
        }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
        ScrollViewReader { defilement in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 0) {
                    ForEach(Array(column.niveaux.enumerated()), id: \.offset) { niveau, items in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(niveau == column.niveaux.count - 1 ? column.filtrer(items) : items) { item in
                                    MillerRow(item: item, column: column, niveau: niveau)
                                }
                            }
                            .padding(6)
                        }
                        .frame(width: CGFloat(config.largeurMiller))
                        .modifier(DepotNiveau(dossier: dossier(niveau)))
                        .id(niveau)
                        // Glisser ce trait change la largeur des colonnes.
                        Poignee(valeur: $config.largeurMiller, mini: 140, maxi: 520)
                    }
                    // Comme dans le Finder : le fichier sélectionné s'affiche à droite, avec ses informations.
                    if let fichier = fichierChoisi {
                        let prise = CGFloat(column.niveaux.count) * (CGFloat(config.largeurMiller) + 9)
                        ApercuFichier(item: fichier)
                            .frame(width: max(300, geo.size.width - prise))
                            .id("apercu")
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .onChange(of: column.niveaux.count) { _, n in
                withAnimation(Mouvement.bascule) {
                    if fichierChoisi != nil { defilement.scrollTo("apercu", anchor: .trailing) }
                    else { defilement.scrollTo(n - 1, anchor: .trailing) }
                }
            }
            .onChange(of: fichierChoisi?.url) { _, url in
                guard url != nil else { return }
                withAnimation(Mouvement.bascule) { defilement.scrollTo("apercu", anchor: .trailing) }
            }
            // Sélectionner un élément dans une colonne à moitié masquée la fait glisser entièrement dans la vue.
            .onReceive(Selection.shared.changements) { url in
                guard let url, Selection.shared.colonne === column,
                      let niveau = column.niveaux.firstIndex(where: { $0.contains { $0.url == url } }) else { return }
                guard !(column.niveaux[niveau].first { $0.url == url }.map { !$0.isFolder } ?? false) else { return }
                withAnimation(Mouvement.bascule) { defilement.scrollTo(niveau) }
            }
        }
        }
    }
}

/// Ce que le Finder affiche à droite d'un fichier sélectionné, en présentation « colonnes ».
struct InfosFichier {
    var type = ""
    var taille = ""
    var lignes: [(String, String)] = []
    var tags: [String] = []

    static func lire(_ url: URL) -> InfosFichier {
        var infos = InfosFichier()
        let v = try? url.resourceValues(forKeys: [
            .localizedTypeDescriptionKey, .totalFileSizeKey, .fileSizeKey, .creationDateKey,
            .contentModificationDateKey, .tagNamesKey])
        infos.type = v?.localizedTypeDescription ?? ""
        if let octets = v?.totalFileSize ?? v?.fileSize {
            infos.taille = ByteCountFormatter.string(fromByteCount: Int64(octets), countStyle: .file)
        }
        infos.tags = v?.tagNames ?? []
        let dates = DateFormatter()
        dates.dateStyle = .full
        dates.timeStyle = .short
        if let d = v?.creationDate { infos.lignes.append((String(localized: "Créé le"), dates.string(from: d))) }
        if let d = v?.contentModificationDate { infos.lignes.append((String(localized: "Modifié le"), dates.string(from: d))) }
        // Le reste vient de Spotlight, comme dans le Finder : dernière ouverture, dimensions, durée.
        if let md = MDItemCreateWithURL(nil, url as CFURL) {
            func valeur(_ cle: CFString) -> Any? { MDItemCopyAttribute(md, cle) }
            if let d = valeur(kMDItemLastUsedDate) as? Date { infos.lignes.append((String(localized: "Ouvert le"), dates.string(from: d))) }
            if let l = valeur(kMDItemPixelWidth) as? Int, let h = valeur(kMDItemPixelHeight) as? Int {
                infos.lignes.append((String(localized: "Dimensions"), "\(l) × \(h)"))
            }
            if let s = valeur(kMDItemDurationSeconds) as? Double, s > 0 {
                let f = DateComponentsFormatter()
                f.allowedUnits = s >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
                f.zeroFormattingBehavior = .pad
                if let texte = f.string(from: s) { infos.lignes.append((String(localized: "Durée"), texte)) }
            }
            if let n = valeur(kMDItemNumberOfPages) as? Int { infos.lignes.append((String(localized: "Pages"), "\(n)")) }
        }
        return infos
    }
}

struct ApercuFichier: View {
    let item: FileItem
    @State private var image: NSImage?
    @State private var infos = InfosFichier()

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Rayon.ligne))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 128, maxHeight: 128)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { AppDelegate.shared.ouvrir(item.url) }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.title3.weight(.semibold)).lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
                Text([infos.type, infos.taille].filter { !$0.isEmpty }.joined(separator: " - "))
                    .foregroundStyle(.secondary)
                if !infos.lignes.isEmpty {
                    Text("Informations").fontWeight(.semibold).padding(.top, 6)
                    ForEach(Array(infos.lignes.enumerated()), id: \.offset) { n, ligne in
                        if n > 0 { Divider() }
                        HStack(alignment: .firstTextBaseline) {
                            Text(ligne.0).foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Text(ligne.1).multilineTextAlignment(.trailing)
                        }
                        .font(.callout)
                    }
                }
                if !infos.tags.isEmpty {
                    Text("Tags").fontWeight(.semibold).padding(.top, 6)
                    Text(infos.tags.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .task(id: item.url) {
            let url = item.url
            image = nil
            infos = await Task.detached { InfosFichier.lire(url) }.value
            let demande = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: 900, height: 900),
                scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: demande),
               !Task.isCancelled {
                image = rep.nsImage
            }
        }
    }
}

extension MillerView {
    /// Le dossier que montre la colonne numéro `niveau` (nil si ce n'est pas un vrai dossier : récents, tags…).
    func dossier(_ niveau: Int) -> URL? {
        if niveau > 0 { return niveau - 1 < column.pile.count ? column.pile[niveau - 1] : nil }
        if let premier = column.pile.first {
            if case .folder = column.kind { return premier.deletingLastPathComponent() }
            return nil
        }
        return column.courant
    }
}

/// Une colonne de la présentation en colonnes accepte les fichiers pour son propre dossier.
struct DepotNiveau: ViewModifier {
    let dossier: URL?
    @State private var cible = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Rayon.vignette).fill(Color.accentColor.opacity(cible ? 0.12 : 0)))
            .modifier(Depot(action: dossier.map { d in { AppDelegate.shared.deposer($0, dans: d) } }, cible: $cible))
    }
}

struct MillerRow: View {
    let item: FileItem
    let column: Column
    let niveau: Int
    @State private var survol = false
    @State private var depot = false
    @ObservedObject private var selection = Selection.shared
    @ObservedObject private var config = Config.shared   // pour se redessiner quand un réglage change

    var body: some View {
        let ouvert = niveau < column.pile.count && column.pile[niveau] == item.url
        let choisi = selection.contient(item.url)
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 18, height: 18)
            NomFichier(item: item) { Text(item.name).lineLimit(1).truncationMode(.middle) }
            Spacer(minLength: 4)
            NuageIcone(item: item, blanc: choisi)
            // Flèche réservée aux dossiers : sur un fichier, le nuage se cale ainsi au bord droit, comme dans le Finder.
            if item.isFolder {
                Image(systemName: "chevron.right").font(.caption)
                    .foregroundStyle(choisi ? Color.white.opacity(0.85) : Color.secondary.opacity(0.6))
            }
        }
        .foregroundStyle(choisi ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)   // lignes resserrées, presque comme dans le Finder
        .background(RoundedRectangle(cornerRadius: Rayon.ligne).fill(
            depot ? Color.accentColor.opacity(0.35)
                : (choisi ? Selection.bleu
                    : (ouvert ? Gris.fort : (survol ? Gris.moyen : .clear)))))
        .contentShape(Rectangle())
        .onHover { survol = $0; AppDelegate.shared.survoler(item, column, $0) }
        // Un clic sur un dossier l'ouvre dans la colonne suivante ; sur un fichier, il le sélectionne.
        .onTapGesture {
            // Avec ⌘ ou Maj, le clic ajoute à la sélection, sans ouvrir de dossier.
            guard !AppDelegate.shared.cliquer(item.url, column, liste: column.niveaux.indices.contains(niveau) ? column.niveaux[niveau].map(\.url) : []) else { return }
            if item.isFolder { column.ouvrirNiveau(item.url, niveau) } else { column.tronquer(niveau) }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if !item.isFolder { AppDelegate.shared.ouvrir(item.url) }
        })
        .modifier(Depot(
            action: item.isFolder ? { AppDelegate.shared.deposer($0, dans: item.url) } : nil,
            cible: $depot))
        .help(item.name)
    }
}

/// Le petit nuage du Finder, à côté d'un fichier d'iCloud Drive qui n'est pas (encore) sur le Mac.
/// Un clic dessus lance le téléchargement.
struct NuageIcone: View {
    let item: FileItem
    var blanc = false   // sur une ligne sélectionnée (fond bleu)

    var body: some View {
        if item.nuage != .aucun {
            let couleur = blanc ? Color.white.opacity(0.9) : Color.secondary
            Group {
                switch item.nuage {
                case .aTelecharger:
                    Image(systemName: "icloud.and.arrow.down")
                        .contentShape(Rectangle())
                        .onTapGesture { AppDelegate.shared.telecharger(item.url) }
                        .help("Dans iCloud, pas encore sur ce Mac. Clique pour le télécharger.")
                        .accessibilityLabel("Télécharger depuis iCloud")
                        .accessibilityAddTraits(.isButton)
                case .telechargement:
                    Image(systemName: "icloud.and.arrow.down.fill").symbolEffect(.pulse)
                        .help("Téléchargement en cours…")
                        .accessibilityLabel("Téléchargement en cours")
                default:
                    Image(systemName: "icloud.and.arrow.up").symbolEffect(.pulse)
                        .help("Envoi vers iCloud en cours…")
                        .accessibilityLabel("Envoi vers iCloud en cours")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(couleur)
        }
    }
}

/// Clic, glisser-déposer et survol : communs à la liste et aux icônes.
struct Interactions: ViewModifier {
    let item: FileItem
    let column: Column
    @Binding var survol: Bool
    var fond = true   // faux pour les icônes : elles dessinent leur sélection elles-mêmes, comme dans le Finder
    @State private var depot = false
    @ObservedObject private var selection = Selection.shared

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Rayon.ligne).fill(
                depot ? Color.accentColor.opacity(0.35)
                    : (fond && selection.contient(item.url) ? Selection.bleu
                        : (survol && !selection.contient(item.url) ? Gris.moyen : .clear))))
            .contentShape(Rectangle())
            .onHover { survol = $0; AppDelegate.shared.survoler(item, column, $0) }
            // Comme dans le Finder : un clic sélectionne, un double-clic ouvre.
            .onTapGesture { _ = AppDelegate.shared.cliquer(item.url, column, liste: column.visibles.map(\.url)) }
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                if !item.isFolder { AppDelegate.shared.ouvrir(item.url) }
                else if column.kind == .etagere { AppDelegate.shared.store.naviguer(.folder(item.url)) }
                else { column.entrer(item.url) }
            })
            .modifier(Depot(
                action: item.isFolder && !column.estEtagere ? { AppDelegate.shared.deposer($0, dans: item.url) } : nil,
                cible: $depot))
            .help(item.name)
    }
}

/// Accepte les fichiers qu'on dépose et les confie à `action` (rien si `action` est absent).
struct Depot: ViewModifier {
    /// Fichiers, mais aussi images, PDF, vidéos et sons qui n'existent pas encore sur le disque.
    static let types: [UTType] = [.fileURL, .image, .pdf, .movie, .audio]
    let action: (([NSItemProvider]) -> Void)?
    @Binding var cible: Bool
    var deplace = true   // faux pour les zones de dépôt : elles ne déplacent jamais le fichier

    func body(content: Content) -> some View {
        if let action {
            content.onDrop(of: Depot.types, delegate: Arrivee(action: action, cible: $cible, deplace: deplace))
        } else {
            content
        }
    }

    /// Dit à macOS ce que fera le dépôt, pour qu'il montre le bon pointeur :
    /// un déplacement par défaut, une copie (avec le « + » vert) quand Option est maintenue.
    struct Arrivee: DropDelegate {
        let action: ([NSItemProvider]) -> Void
        @Binding var cible: Bool
        let deplace: Bool

        func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: Depot.types) }
        func dropEntered(info: DropInfo) { cible = true }
        func dropExited(info: DropInfo) { cible = false }
        func dropUpdated(info: DropInfo) -> DropProposal? {
            // Un vrai fichier peut être déplacé ; une image tirée d'une page web ne peut qu'être copiée.
            let fichier = NSPasteboard(name: .drag).types?.contains(.fileURL) == true
            let copie = !deplace || !fichier || NSEvent.modifierFlags.contains(.option)
            return DropProposal(operation: copie ? .copy : .move)
        }
        func performDrop(info: DropInfo) -> Bool {
            cible = false
            action(info.itemProviders(for: Depot.types))
            return true
        }
    }
}

/// Le départ d'un glisser de fichier, confié à macOS : la destination choisit entre déplacer et copier,
/// comme pour un fichier tiré depuis le Finder (déplacer par défaut, copier avec Option).
final class DepartGlisser: NSObject, NSDraggingSource {
    static let shared = DepartGlisser()
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.move, .copy, .link, .generic]
    }
    /// Ce qui est parti d'une zone de dépôt flottante : une fois déposé ailleurs, la zone l'oublie (comme l'étagère de Dropover).
    var sortis: (urls: [URL], zone: Int)?
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if let s = sortis {
            sortis = nil
            AppDelegate.shared.noter("zone de dépôt : glisser terminé en \(screenPoint), opération \(operation.rawValue), \(s.urls.count) fichier(s)")
            if operation != [], !(AppDelegate.shared.cadreDepot?.contains(screenPoint) ?? false) {
                s.urls.forEach { Etagere.retirer($0, s.zone) }
            }
        }
        // Le fichier est peut-être parti ailleurs : on rafraîchit, et la zone de dépôt oublie ce qui n'est plus là.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { AppDelegate.shared.apresGlisser() }
    }
}

enum Vignettes {
    static let cache = NSCache<NSURL, NSImage>()
}

struct IconView: View {
    let item: FileItem
    let column: Column
    var taille: CGFloat?   // nil = la taille choisie dans les réglages
    var legende = true
    @State private var survol = false
    @State private var vignette: NSImage?
    @State private var info = ""
    @ObservedObject private var selection = Selection.shared
    @ObservedObject private var config = Config.shared

    var body: some View {
        let choisi = selection.contient(item.url)
        let cote = taille ?? CGFloat(config.tailleIcones)
        let droite = legende && config.texteADroite
        let image = Image(nsImage: (config.apercus ? vignette : nil) ?? NSWorkspace.shared.icon(forFile: item.url.path))
            .resizable().aspectRatio(contentMode: .fit)
            .frame(width: cote, height: cote)
            .padding(3)
            // Comme dans le Finder : l'icône choisie se pose sur un carré gris, son nom sur du bleu.
            .background(RoundedRectangle(cornerRadius: Rayon.ligne).fill(
                choisi ? (legende ? Gris.moyen : Selection.bleu.opacity(0.3)) : .clear))
            // Sans nom sous l'icône (zone de dépôt) : un cadre bleu montre clairement ce qui est sélectionné.
            .overlay(RoundedRectangle(cornerRadius: Rayon.ligne).strokeBorder(Selection.bleu, lineWidth: choisi && !legende ? 2.5 : 0))
        let texte = VStack(alignment: droite ? .leading : .center, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                NuageIcone(item: item, blanc: choisi)
                NomFichier(item: item) {
                    Text(item.name)
                        .font(.system(size: CGFloat(config.tailleTexte)))
                        .multilineTextAlignment(droite ? .leading : .center)
                        .lineLimit(2).truncationMode(.middle)
                        .foregroundStyle(choisi ? Color.white : Color.primary)
                }
            }
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: Rayon.puce).fill(choisi ? Selection.bleu : .clear))
            if config.infos && !info.isEmpty {
                Text(info).font(.system(size: max(9, CGFloat(config.tailleTexte) - 2)))
                    .foregroundStyle(Color.accentColor).lineLimit(1)
            }
        }
        Group {
            if !legende {
                image
            } else if droite {
                HStack(spacing: 6) { image; texte; Spacer(minLength: 0) }
            } else {
                VStack(spacing: 4) {
                    image
                    texte.frame(maxWidth: .infinity, minHeight: CGFloat(config.tailleTexte) * 2.7, alignment: .top)
                }
            }
        }
        .padding(legende ? 4 : 0)
        .modifier(Interactions(item: item, column: column, survol: $survol, fond: false))
        .onAppear(perform: charger)
    }

    private func charger() {
        if legende && info.isEmpty { renseigner() }
        guard !item.isFolder, vignette == nil else { return }
        if let img = Vignettes.cache.object(forKey: item.url as NSURL) { vignette = img; return }
        let demande = QLThumbnailGenerator.Request(
            fileAt: item.url, size: CGSize(width: 128, height: 128),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: demande) { rep, _ in
            guard let img = rep?.nsImage else { return }
            Vignettes.cache.setObject(img, forKey: item.url as NSURL)
            DispatchQueue.main.async { vignette = img }
        }
    }

    /// « Afficher les informations » : le poids d'un fichier, le nombre d'éléments d'un dossier.
    private func renseigner() {
        if !item.isFolder {
            info = ByteCountFormatter.string(fromByteCount: Int64(item.taille), countStyle: .file)
            return
        }
        let url = item.url
        DispatchQueue.global(qos: .utility).async {
            let n = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") }.count
            DispatchQueue.main.async { info = n == 0 ? String(localized: "Vide") : (n == 1 ? String(localized: "1 élément") : String(localized: "\(n) éléments")) }
        }
    }
}

struct RowView: View {
    let item: FileItem
    let column: Column
    let large: Bool
    @State private var survol = false
    @ObservedObject private var selection = Selection.shared
    @ObservedObject private var config = Config.shared   // pour se redessiner quand un réglage change

    private static let jour: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current   // la langue de Side : français ou anglais
        f.dateFormat = "d MMM yyyy"
        return f
    }()
    private static let dates: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale.current   // la langue de Side : français ou anglais
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        // Ligne choisie : fond bleu du Finder, textes en blanc.
        let choisi = selection.contient(item.url)
        let discret = choisi ? Color.white.opacity(0.85) : Color.secondary
        return HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                NomFichier(item: item) { Text(item.name).lineLimit(1).truncationMode(.middle) }
                if ((column.kind == .recents || column.kind == .dossiers) && column.pile.isEmpty) || column.resultats != nil {
                    Text(detail).font(.caption).foregroundStyle(discret).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            NuageIcone(item: item, blanc: choisi)
            if large {
                Group {
                    Text(Self.jour.string(from: item.date))
                        .frame(width: 86, alignment: .trailing)
                    Text(item.isFolder ? "--" : ByteCountFormatter.string(fromByteCount: Int64(item.taille), countStyle: .file))
                        .frame(width: 64, alignment: .trailing)
                }
                .font(.caption).foregroundStyle(discret)
            }
            // Flèche réservée aux dossiers : sur un fichier, le nuage se cale ainsi au bord droit, comme dans le Finder.
            if item.isFolder {
                Image(systemName: "chevron.right").font(.caption)
                    .foregroundStyle(choisi ? Color.white.opacity(0.85) : Color.secondary.opacity(0.6))
            }
        }
        .foregroundStyle(choisi ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)   // lignes resserrées, presque comme dans le Finder
        .modifier(Interactions(item: item, column: column, survol: $survol))
    }

    private var detail: String {
        let parent = item.url.deletingLastPathComponent()
        let dossier = parent.standardizedFileURL == Fichiers.downloads.standardizedFileURL
            ? String(localized: "Téléchargements") : FileManager.default.displayName(atPath: parent.path)
        return dossier + " · " + Self.dates.localizedString(for: item.date, relativeTo: Date())
    }
}
