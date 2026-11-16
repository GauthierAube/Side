// Les zones de dépôt et les colonnes épinglées (étagères), côté affichage.
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Ce qu'on lâche sur une icône du mini-Dock : un fichier (ouvert avec cette app), ou une autre icône du
/// mini-Dock (elle prend cette place : c'est ainsi qu'on range les apps dans l'ordre voulu).
struct DepotIcone: DropDelegate {
    static let typeApp = UTType(exportedAs: "com.gauthieraube.side.app")
    let item: AppItem
    @Binding var cible: Bool

    private var glissee: AppItem? { AppDelegate.shared.appGlissee }

    func dropEntered(info: DropInfo) {
        if let g = glissee {
            // L'ordre change dès le survol : les icônes s'écartent pour montrer la nouvelle place.
            if g.id != item.id {
                withAnimation(Mouvement.glissement) { Apps.shared.deplacer(g.id, sur: item.id, Config.shared) }
            }
        } else if let app = AppDelegate.appsGlissees().first {
            // Une app venue d'ailleurs (Finder, carte) : elle se glisse ici, les autres lui font de la place.
            withAnimation(Mouvement.glissement) { AppDelegate.shared.previsualiserApp(app, sur: item.id) }
        } else { cible = true }
    }
    func dropExited(info: DropInfo) { cible = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: glissee != nil ? .move : .copy) }
    func performDrop(info: DropInfo) -> Bool {
        cible = false
        if glissee != nil { return true }   // l'ordre est déjà le bon
        if !AppDelegate.appsGlissees().isEmpty {   // une app déposée : elle reste là où on l'a lâchée
            AppDelegate.shared.confirmerApp()
            AppDelegate.shared.ajouterApps(info.itemProviders(for: [UTType.fileURL]))
            return true
        }
        AppDelegate.shared.ouvrirAvec(info.itemProviders(for: [UTType.fileURL]), item.url)
        return true
    }
}

/// Un trait de séparation qu'on glisse pour changer une largeur (grande zone, colonnes du Finder).
struct Poignee: View {
    @Binding var valeur: Double
    let mini: CGFloat
    let maxi: CGFloat
    @State private var depart: Double?
    @State private var survol = false

    var body: some View {
        let actif = survol || depart != nil
        Color.clear
            .frame(width: 9)
            .frame(maxHeight: .infinity)
            .overlay(Rectangle()
                .fill(actif ? Color.accentColor : Color(nsColor: .separatorColor))
                .frame(width: actif ? 3 : 1))
            .contentShape(Rectangle())
            .onHover { dedans in
                survol = dedans
                if dedans { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    if depart == nil { depart = valeur }
                    valeur = Double(min(max(CGFloat(depart ?? valeur) + v.translation.width, mini), maxi))
                }
                .onEnded { _ in depart = nil })
            .help("Glisse pour changer la largeur")
            .accessibilityLabel("Changer la largeur")
    }
}

/// Les zones de dépôt flottantes : des carrés arrondis à droite de la carte, façon Dropover.
/// Un carré apparaît pendant un glisser-déposer, et reste tant qu'il contient des fichiers.
struct ZonesFlottantes: View {
    @ObservedObject var store: Store
    @ObservedObject var config = Config.shared

    var body: some View {
        // Carte venue du haut : la première zone est en bas, les suivantes s'empilent au-dessus.
        let versHaut = config.bord == .haut
        VStack(spacing: 8) {
            ForEach(versHaut ? store.etageres.reversed() : store.etageres) { zone in
                ZoneCarree(column: zone, store: store, glisse: store.glisse, deplie: store.depotDeplie == zone.indexEtagere)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: versHaut ? .bottomLeading : .topLeading)
        .animation(Mouvement.ressort, value: store.depotDeplie)
        .animation(Mouvement.ressort, value: store.glisse)
        .animation(Mouvement.ressort, value: store.depotRempli)
    }
}

struct ZoneCarree: View {
    @ObservedObject var column: Column
    let store: Store
    let glisse: Bool
    var deplie = false
    @ObservedObject var config = Config.shared

    var body: some View {
        if glisse || !column.items.isEmpty {
            let forme = RoundedRectangle(cornerRadius: DepotFlottant.rayon, style: .continuous)
            let grande = deplie && !column.items.isEmpty
            let e = grande ? 1 : store.echelleDepot
            let l = grande ? DepotFlottant.depliee.width : Reglages.carreDepot
            let h = grande ? DepotFlottant.depliee.height : Reglages.hauteurDepot
            EtagereFlottante(column: column, store: store)
                .frame(width: l, height: h)
                .background(ZStack {
                    VisualEffect()
                    Color(nsColor: .windowBackgroundColor).opacity(config.opacite)
                }.clipShape(forme))
                // Réduite d'un bloc quand plusieurs zones doivent tenir sur la hauteur du Finder.
                .scaleEffect(e, anchor: .topLeading)
                .frame(width: l * e, height: h * e, alignment: .topLeading)
                .transition(.opacity)
        }
    }
}

/// Les zones de dépôt. `etendu` : grandes cartes « Dépose ici » (pendant un glisser-déposer).
/// Sinon : une fine bande de vignettes, seulement pour les zones qui contiennent quelque chose.
struct ZonesView: View {
    static let taille = CGSize(width: 150, height: 150)   // largeur des cartes / hauteur de la rangée
    static let bande: CGFloat = 56
    @ObservedObject var store: Store
    let etendu: Bool
    var lateral = false

    var body: some View {
        if lateral {
            GeometryReader { geo in
                let n = CGFloat(store.etageres.count)
                let place = geo.size.width - 16 - 8 * (n - 1)
                HStack(spacing: 8) {
                    ForEach(store.etageres) { zone in
                        EtagereView(column: zone, store: store).frame(width: max(60, place / n))
                    }
                }
                .padding(8)
            }
        } else if etendu {
            VStack(spacing: 8) {
                ForEach(store.etageres) { zone in EtagereView(column: zone, store: store) }
            }
            .padding(8)
            .frame(width: Self.taille.width + 16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Rayon.fenetre, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 14, y: 4)
        } else {
            VStack(spacing: 6) {
                ForEach(store.etageres) { zone in EtagereCompacte(column: zone, store: store) }
            }
            .frame(width: Self.bande)
        }
    }
}

/// Une zone de dépôt réduite : une bande arrondie de vignettes, qu'on peut emmener ailleurs.
struct EtagereCompacte: View {
    @ObservedObject var column: Column
    let store: Store
    @State private var depot = false

    var body: some View {
        if !column.items.isEmpty {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(column.items) { item in
                        IconView(item: item, column: column, taille: 38, legende: false)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Rayon.panneau, style: .continuous)
                .fill(depot ? Color.accentColor.opacity(0.3) : Gris.moyen))
            .overlay(RoundedRectangle(cornerRadius: Rayon.panneau, style: .continuous)
                .strokeBorder(depot ? Color.accentColor : Gris.filet, lineWidth: depot ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Rayon.panneau))
            .modifier(Depot(action: { AppDelegate.shared.poser($0, column.indexEtagere) }, cible: $depot, deplace: false))
            .contextMenu {
                Button("Afficher dans le Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(column.items.map(\.url))
                }
                Button("Vider la zone") { Etagere.vider(column.indexEtagere); column.reload() }
                if store.etageres.count > 1 {
                    Button("Supprimer cette zone") { store.supprimerZone(column.indexEtagere) }
                }
            }
            .help("Zone de dépôt : glisse ces fichiers où tu veux")
        }
    }
}

/// Le bord droit de la carte pendant un glisser-déposer : y lâcher un dossier l'épingle en colonne.
struct BordEpingle: View {
    @State private var cible = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
            Text("Épingler").font(.caption)
        }
        .foregroundStyle(cible ? Color.white : Color.accentColor)
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Rayon.panneau, style: .continuous)
            .fill(Color.accentColor.opacity(cible ? 0.75 : 0.2)))
        .overlay(RoundedRectangle(cornerRadius: Rayon.panneau, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1.5))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Rayon.panneau, style: .continuous))
        .padding(8)
        .onDrop(of: [UTType.fileURL, UTType.utf8PlainText], isTargeted: $cible) { fournisseurs in
            AppDelegate.shared.epingler(fournisseurs)
            return true
        }
        .accessibilityLabel("Épingler un dossier en colonne")
    }
}

/// L'étagère : une carte arrondie où poser des fichiers le temps de les emmener ailleurs.
struct EtagereView: View {
    @ObservedObject var column: Column
    let store: Store
    @ObservedObject var config = Config.shared
    @State private var depot = false

    var body: some View {
        let vide = column.items.isEmpty
        ZStack {
            // Le fond de la zone : l'attraper et tirer déplace la zone, comme une petite fenêtre.
            // (Attraper un fichier, lui, le fait glisser hors de la zone.)
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .onChanged { _ in AppDelegate.shared.deplacerDepot() }
                    .onEnded { _ in AppDelegate.shared.finDeplacementDepot() })
            if vide {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.title2).foregroundStyle(.secondary)
                    Text("Dépose ici")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 10)
            } else if column.items.count == 1, let seul = column.items.first {
                IconView(item: seul, column: column, taille: 56, legende: false)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 4)], spacing: 4) {
                        ForEach(column.items) { item in
                            IconView(item: item, column: column, taille: 38, legende: false)
                        }
                    }
                }
                .padding(.top, 36).padding(.bottom, 32).padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if !vide {
                Button { Etagere.vider(column.indexEtagere); column.reload() } label: { rond("xmark") }
                    .buttonStyle(.plain).padding(8)
                    .help("Vider l'étagère").accessibilityLabel("Vider l'étagère")
            }
        }
        .overlay(alignment: .topTrailing) {
            if !vide {
                Menu {
                    Button("Afficher dans le Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(column.items.map(\.url))
                    }
                    Button("Vider l'étagère") { Etagere.vider(column.indexEtagere); column.reload() }
                    if store.etageres.count > 1 {
                        Button("Supprimer cette zone") { store.supprimerZone(column.indexEtagere) }
                    }
                    Divider()
                    Button("Replacer à côté de Side") { AppDelegate.shared.replacerDepot() }
                } label: { rond("chevron.down") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(8)
                .accessibilityLabel("Actions de l'étagère")
            }
        }
        // Le cadenas : fermé, la zone reste à l'écran quand Side se ferme ; ouvert, elle se cache avec lui.
        .overlay(alignment: .top) {
            if !vide {
                Button { config.depotReste.toggle() } label: {
                    rond(config.depotReste ? "lock.fill" : "lock.open.fill")
                        .foregroundStyle(config.depotReste ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain).padding(8)
                .help(config.depotReste ? "Verrouillée : reste à l'écran quand Side se ferme. Clique pour qu'elle se cache avec Side."
                                         : "Déverrouillée : se cache quand Side se ferme. Clique pour la garder à l'écran.")
                .accessibilityLabel(config.depotReste ? "Zone verrouillée à l'écran" : "Zone qui se cache avec Side")
            }
        }
        .overlay(alignment: .bottom) {
            if !vide {
                Text(column.items.count == 1 ? column.items[0].name : String(localized: "\(column.items.count) éléments"))
                    .font(.caption).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Gris.fort))
                    .padding(.horizontal, 10).padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: Rayon.fenetre)
            .fill(depot ? Color.accentColor.opacity(0.28) : Color.clear))   // même matière que la barre latérale
        .overlay(RoundedRectangle(cornerRadius: Rayon.fenetre).strokeBorder(
            depot ? Color.accentColor : Gris.moyen, lineWidth: depot ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: Rayon.fenetre))
        .modifier(Depot(action: { AppDelegate.shared.poser($0, column.indexEtagere) }, cible: $depot, deplace: false))
        .contextMenu {
            if store.etageres.count > 1 {
                Button("Supprimer cette zone") { store.supprimerZone(column.indexEtagere) }
            }
        }
    }

    private func rond(_ symbole: String) -> some View {
        Image(systemName: symbole)
            .font(.system(size: 10, weight: .bold))
            .frame(width: 24, height: 24)
            .background(Circle().fill(Gris.fort))
            .contentShape(Circle())
    }
}
