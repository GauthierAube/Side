// La zone de dépôt flottante, refaite sur le modèle de l'étagère de Dropover (13/11/2026) :
// – repliée : une tuile de 198 × 207 points. Les fichiers y sont empilés, en vignettes ; attraper la pile les emmène tous
//   d'un coup. En haut, la croix (vider) et le menu ; en bas, la pastille « 3 éléments › » qui déplie la tuile ;
// – dépliée : 400 × 304 points, la grille des fichiers avec leur nom et leur poids, à prendre un par un ;
// – ce qu'on fait glisser hors de la zone la quitte, et une zone vidée disparaît.
// Elle reste à côté du Finder de Side (ou là où on l'a posée).
import AppKit
import SwiftUI
import QuickLookThumbnailing

enum DepotFlottant {
    static let depliee = CGSize(width: 400, height: 304)
    static let rayon: CGFloat = 32
}

/// La vignette d'un fichier (son aperçu, sinon son icône), dans un carré de `cote` points.
struct VignetteDepot: View {
    let url: URL
    let cote: CGFloat
    var ombre = true
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable().aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: image == nil ? 0 : 5, style: .continuous))
            .shadow(color: .black.opacity(ombre && image != nil ? 0.28 : 0), radius: 4, y: 2)
            .frame(width: cote, height: cote)
            .onAppear(perform: charger)
            .onChange(of: url) { _, _ in image = nil; charger() }
    }

    private func charger() {
        let cle = url.appendingPathComponent("#grand") as NSURL
        if let img = Vignettes.cache.object(forKey: cle) { image = img; return }
        let demande = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 256, height: 256),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: demande) { rep, _ in
            guard let img = rep?.nsImage else { return }
            Vignettes.cache.setObject(img, forKey: cle)
            DispatchQueue.main.async { image = img }
        }
    }
}

/// Un bouton rond de la tuile (croix, menu, retour).
private struct RondDepot: View {
    let symbole: String
    var body: some View {
        Image(systemName: symbole)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.8))
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.primary.opacity(0.10)))
            .contentShape(Circle())
    }
}

/// Une zone de dépôt flottante : repliée (la pile) ou dépliée (la grille).
struct EtagereFlottante: View {
    @ObservedObject var column: Column
    @ObservedObject var store: Store
    @ObservedObject var config = Config.shared
    @State private var depot = false
    @State private var survolPile = false
    @State private var survolSeul = false

    private var deplie: Bool { store.depotDeplie == column.indexEtagere && !column.items.isEmpty }

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: DepotFlottant.rayon, style: .continuous)
        ZStack {
            // Le fond : l'attraper et tirer déplace la zone, comme une petite fenêtre.
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .onChanged { _ in AppDelegate.shared.deplacerDepot() }
                    .onEnded { _ in AppDelegate.shared.finDeplacementDepot() })
            if column.items.isEmpty { vide } else if deplie { grille } else { pile }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(forme.fill(depot ? Color.accentColor.opacity(0.28) : Color.clear))
        .overlay(forme.strokeBorder(depot ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: depot ? 2 : 1))
        .contentShape(forme)
        .modifier(Depot(action: { AppDelegate.shared.poser($0, column.indexEtagere) }, cible: $depot, deplace: false))
        .onChange(of: column.items.isEmpty) { _, vide in
            if vide, store.depotDeplie == column.indexEtagere { store.depotDeplie = nil }
        }
    }

    // MARK: Vide

    private var vide: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 26, weight: .regular)).foregroundStyle(.secondary)
            Text("Dépose ici").font(.callout).foregroundStyle(.secondary)
        }
        .allowsHitTesting(false)
    }

    // MARK: Repliée : la pile

    private var titre: String {
        column.items.count == 1 ? column.items[0].name : String(localized: "\(column.items.count) éléments")
    }

    private var pile: some View {
        ZStack {
            if column.items.count == 1, let seul = column.items.first {
                // Un seul fichier : il se comporte comme dans le Finder (glisser, double-clic pour ouvrir).
                VignetteDepot(url: seul.url, cote: 96)
                    .modifier(Interactions(item: seul, column: column, survol: $survolSeul, fond: false))
            } else {
                // Plusieurs : une pile. Les derniers déposés sont dessus ; l'attraper les emmène tous.
                let dessus = Array(column.items.suffix(3))
                ZStack {
                    ForEach(Array(dessus.enumerated()), id: \.element.id) { i, item in
                        let rang = dessus.count - 1 - i                       // 0 : la carte du dessus
                        VignetteDepot(url: item.url, cote: 92)
                            .rotationEffect(.degrees(rang == 0 ? 0 : (rang == 1 ? -7 : 6)))
                            .offset(x: rang == 0 ? 0 : (rang == 1 ? -5 : 6), y: rang == 0 ? 0 : 4)
                            .opacity(rang == 0 ? 1 : 0.9)
                    }
                }
                .frame(width: 104, height: 104)
                .scaleEffect(survolPile ? 1.04 : 1)
                .animation(.easeOut(duration: 0.15), value: survolPile)
                .contentShape(Rectangle())
                .onHover { survolPile = $0; AppDelegate.shared.survolerPile(column, $0) }
                .onTapGesture(count: 2) { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { store.depotDeplie = column.indexEtagere } }
                .help("Glisse la pile pour emmener tous les fichiers")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            Button { fermer() } label: { RondDepot(symbole: "xmark") }
                .buttonStyle(.plain).padding(9)
                .help("Vider la zone").accessibilityLabel("Vider la zone")
        }
        .overlay(alignment: .topTrailing) { menu.padding(9) }
        .overlay(alignment: .bottom) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { store.depotDeplie = column.indexEtagere }
            } label: {
                HStack(spacing: 5) {
                    Text(titre).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.10)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.bottom, 11)
            .help("Voir les fichiers un par un")
        }
    }

    // MARK: Dépliée : la grille

    private var poids: String {
        ByteCountFormatter.string(fromByteCount: column.items.reduce(Int64(0)) { $0 + Int64($1.taille) }, countStyle: .file)
    }

    private var grille: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { store.depotDeplie = nil }
                } label: { RondDepot(symbole: "chevron.left") }
                    .buttonStyle(.plain).help("Replier").accessibilityLabel("Replier la zone")
                VStack(alignment: .leading, spacing: 0) {
                    Text(titre).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(poids).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                menu
            }
            .padding(.horizontal, 10).padding(.top, 9).padding(.bottom, 4)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(118), spacing: 6), count: 3), spacing: 6) {
                    ForEach(column.items) { item in CaseDepot(item: item, column: column) }
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
            }
        }
    }

    // MARK: Menu et fermeture

    private var menu: some View {
        Menu {
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting(column.items.map(\.url)) }
            Button("Vider la zone") { fermer() }
            if store.etageres.count > 1 {
                Button("Supprimer cette zone") { store.supprimerZone(column.indexEtagere) }
            }
            Divider()
            Toggle("Garder à l'écran quand Side est fermé", isOn: $config.depotReste)
            Button("Replacer à côté de Side") { AppDelegate.shared.replacerDepot() }
        } label: { RondDepot(symbole: "chevron.down") }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Actions de la zone")
    }

    /// La croix : la zone se vide et disparaît (sauf la dernière, qui reste prête pour le prochain dépôt).
    private func fermer() {
        store.depotDeplie = nil
        if store.etageres.count > 1 { store.supprimerZone(column.indexEtagere); return }
        Etagere.vider(column.indexEtagere)
        column.reload()
    }
}

/// Un fichier dans la grille dépliée : sa vignette, son nom, son poids. Il se glisse, s'ouvre et se sélectionne comme ailleurs.
private struct CaseDepot: View {
    let item: FileItem
    let column: Column
    @State private var survol = false
    @ObservedObject private var selection = Selection.shared

    var body: some View {
        let choisi = selection.contient(item.url)
        VStack(spacing: 3) {
            VignetteDepot(url: item.url, cote: 70)
            Text(item.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Text(item.isFolder ? String(localized: "Dossier") : ByteCountFormatter.string(fromByteCount: Int64(item.taille), countStyle: .file))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
        .frame(width: 118)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Selection.bleu, lineWidth: choisi ? 2 : 0))
        .modifier(Interactions(item: item, column: column, survol: $survol, fond: false))
    }
}
