// La carte du Finder : sa vue principale, la présentation de bienvenue, les onglets.
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct DrawerView: View {
    @ObservedObject var store: Store
    @ObservedObject var config = Config.shared
    @State private var depotAjout = false

    var body: some View {
        // Autour de la carte : le mini-Dock (du côté choisi dans les réglages) et les zones de dépôt
        // flottantes (à droite, ou à gauche si la carte est collée à droite).
        let p = config.apps ? config.dockPosition : ""
        HStack(alignment: .top, spacing: 8) {
            // Le mini-Dock passe devant la carte : la liste du presse-papiers se déroule par-dessus elle.
            if p == "gauche" { AppsView(vertical: true).zIndex(1) }
            VStack(spacing: 8) {
                if p == "haut" { AppsView(vertical: false).zIndex(1) }
                carte
                if p == "bas" { AppsView(vertical: false).zIndex(1) }
            }
            if p == "droite" { AppsView(vertical: true).zIndex(1) }
        }
        // Place vide gardée pour la liste du presse-papiers, du côté opposé à la carte.
        .padding(config.bord == .bas ? .top : .bottom, config.presseDehors)
    }

    private var carte: some View {
        GeometryReader { geo in
                let barre: CGFloat = 210
                let fixes = barre + 10
                // La grande zone garde la largeur qu'elle a sans colonne épinglée.
                let zone = max(300, min(Disposition.base(store.largeurMax), geo.size.width) - fixes)
                let largeur = Disposition.colonne(store.columns.count, store.largeurMax)
                // Glisser le trait à droite de la grande zone partage la place entre elle et les colonnes épinglées :
                // ce que gagne l'une, les autres le perdent, et la carte garde sa largeur.
                // (Sans colonne épinglée, ce trait est le bord de la carte : il change alors sa largeur.)
                let n = store.columns.count
                let reglage = Binding<Double>(
                    get: { Double(zone) },
                    set: { nouvelle in
                        let ecart = CGFloat(nouvelle) - zone
                        if n > 0 {
                            let col = CGFloat(config.tailleColonne) - ecart / CGFloat(n)
                            guard col >= 160 else { return }   // une colonne épinglée garde une largeur lisible
                            config.tailleColonne = Double(col)
                        }
                        config.largeurSeule = Double((CGFloat(nouvelle) + fixes) / max(store.largeurMax, 1))
                    })
                HStack(spacing: 0) {
                    SidebarView(store: store).frame(width: barre)
                    Divider()
                    // La zone de dépôt n'occupe plus de colonne : elle apparaît par-dessus la grande zone
                    // pendant un glisser-déposer, puis reste en fine bande tant qu'elle contient des fichiers.
                    ZStack(alignment: .trailing) {
                        ColumnView(column: store.navigateur, store: store, large: zone > 430, fixe: true)
                            .id(store.navigateur.id)
                            .padding(.trailing, store.depotRempli && !store.depotDehors ? ZonesView.bande + 12 : 0)
                        if !store.depotDehors && (store.glisse || store.depotRempli) {
                            ZonesView(store: store, etendu: store.glisse)
                                .padding(6)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(width: zone)
                    .animation(Mouvement.ressort, value: store.glisse)
                    .animation(Mouvement.ressort, value: store.depotRempli)
                    Poignee(valeur: reglage, mini: 300, maxi: store.largeurMax - fixes)
                    if !store.columns.isEmpty {
                        ScrollView(.horizontal, showsIndicators: !config.ajuster) {
                            HStack(spacing: 0) {
                                ForEach(store.columns) { column in
                                    ColumnView(column: column, store: store, large: largeur > 430,
                                               dernier: column.id == store.columns.last?.id)
                                        .frame(width: largeur)
                                    Divider()
                                }
                            }
                            .frame(height: geo.size.height)
                        }
                    }
                }
                // Le bord droit de la carte devient une cible pendant un glisser : y déposer un dossier l'épingle.
                .overlay(alignment: .trailing) {
                    if store.glisse && store.glisseDossier {
                        BordEpingle().transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(Mouvement.ressort, value: store.glisse)
        }
        .padding(.top, store.margeHaut)
        .background(ZStack {
            VisualEffect()
            Color(nsColor: .windowBackgroundColor).opacity(config.opacite)
            // La barre latérale reste translucide ; le contenu, à sa droite, est blanc comme dans le Finder.
            HStack(spacing: 0) {
                Color.clear.frame(width: 211)
                Color(nsColor: .textBackgroundColor)
            }
        })
        .overlay {
            if let etape = store.accueil {
                AccueilView(store: store, etape: etape).transition(.opacity)
            }
        }
        .animation(Mouvement.bascule, value: store.accueil)
        .clipShape(forme)
        .overlay(forme.strokeBorder(Gris.filet, lineWidth: 1))
    }

    private var boutonAjout: some View {
        Button { AppDelegate.shared.choisirDossier() } label: {
            Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: Rayon.carte)
            .fill(depotAjout ? Color.accentColor.opacity(0.35) : .clear).padding(4))
        // Déposer un dossier ici crée une colonne avec son contenu.
        .onDrop(of: [UTType.fileURL, UTType.utf8PlainText], isTargeted: $depotAjout) { fournisseurs in
            AppDelegate.shared.epingler(fournisseurs)
            return true
        }
        .help("Épingler un dossier en colonne (clique, ou dépose un dossier ici)")
        .accessibilityLabel("Épingler un dossier en colonne")
    }

    /// Une carte flottante : les quatre coins sont arrondis.
    private var forme: RoundedRectangle { RoundedRectangle(cornerRadius: Reglages.rayonCarte, style: .continuous) }
}

/// La barre d'onglets de la grande zone (affichée dès qu'il y en a deux).
/// La présentation de bienvenue : cinq bulles posées sur la carte, qui montrent chacune une partie de Side.
struct AccueilView: View {
    @ObservedObject var store: Store
    @ObservedObject var config = Config.shared
    let etape: Int
    static let nombre = 5

    var body: some View {
        GeometryReader { geo in
            let l = geo.size.width, h = geo.size.height
            let zone = max(300, min(Disposition.base(store.largeurMax), l) - 220)
            // La partie de la carte mise en lumière, et l'endroit où poser la bulle.
            let cible: CGRect? = [nil,
                                  CGRect(x: 0, y: 0, width: 211, height: h),
                                  CGRect(x: 211, y: 0, width: zone, height: h),
                                  nil,   // la zone de dépôt flotte à côté de la carte : elle s'affiche pour de vrai
                                  nil][min(etape, 4)]
            let x: CGFloat = [l / 2, 211 + 170, 211 + zone / 2, l - 170, l / 2][min(etape, 4)]
            let y: CGFloat = etape == 2 ? h * 0.6 : h / 2
            ZStack(alignment: .topLeading) {
                // Un voile sombre, troué à l'endroit qu'on montre.
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    if let c = cible { p.addRoundedRect(in: c.insetBy(dx: 5, dy: 5), cornerSize: CGSize(width: 12, height: 12)) }
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                if let c = cible {
                    RoundedRectangle(cornerRadius: Rayon.carte).strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .frame(width: c.width - 10, height: c.height - 10)
                        .offset(x: c.minX + 5, y: c.minY + 5)
                }
                bulle
                    .frame(width: 290)
                    .position(x: min(max(x, 160), l - 160), y: y)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {}   // les clics ne traversent pas le voile
    }

    private var bulle: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<Self.nombre, id: \.self) { i in
                    Capsule().fill(i == etape ? Color.accentColor : Gris.fort)
                        .frame(width: i == etape ? 18 : 6, height: 6)
                }
                Spacer()
                Text("\(etape + 1) sur \(Self.nombre)").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(titre).font(.title3.weight(.semibold))
                Spacer()
                // Une flèche montre où regarder : la zone de dépôt à droite, le mini-Dock autour de la carte.
                if let fleche { Image(systemName: fleche).font(.title2.weight(.bold)).foregroundStyle(Color.accentColor) }
            }
            contenu.font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            HStack {
                if etape < Self.nombre - 1 {
                    Button("Passer") { store.finAccueil() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer()
                if etape == 0 {
                    Button("Changer…") { AppDelegate.shared.ouvrirReglages() }
                }
                Button(etape < Self.nombre - 1 ? "Suivant" : "Voir le tiroir") {
                    if etape < Self.nombre - 1 { store.accueil = etape + 1 } else {
                        // Fin de la visite du Finder : il se referme, et le tiroir s'ouvre pour se présenter à son tour.
                        store.finAccueil()
                        if AppDelegate.shared.estOuvert { AppDelegate.shared.basculer() }
                        PanneauBas.commun.présenter()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Rayon.panneau, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: Rayon.panneau, style: .continuous).strokeBorder(Gris.filet, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
    }

    private var titre: String {
        [String(localized: "Bienvenue dans Side"), String(localized: "Tes dossiers"), String(localized: "Tes fichiers"),
         String(localized: "La zone de dépôt"), String(localized: "Le tiroir")][min(etape, 4)]
    }

    private var fleche: String? {
        if etape == 3 { return "arrow.right" }
        return etape == 4 ? (ConfigTiroir.enHaut ? "arrow.up" : "arrow.down") : nil      // le bord d'où arrive le tiroir
    }

    private func geste(_ symbole: String, _ texte: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbole).foregroundStyle(Color.accentColor).frame(width: 20)
            Text(texte)
        }
    }

    @ViewBuilder private var contenu: some View {
        switch etape {
        case 0:
            VStack(alignment: .leading, spacing: 7) {
                Text("Pour ouvrir et fermer le Finder :").foregroundStyle(.secondary)
                if config.coin != .aucun { geste("arrow.up.left.and.arrow.down.right", String(localized: "Le coin \(config.coin.titre.lowercased())")) }
                if config.secouer {
                    geste("cursorarrow.motionlines", config.cercle ? String(localized: "Un cercle avec la souris") : String(localized: "Une secousse de souris"))
                }
                if config.touche != -1 { geste("keyboard", config.libelle) }
            }
        case 1:
            Text("Glisse un dossier sur « Favoris » pour l'ajouter.")
        case 2:
            VStack(alignment: .leading, spacing: 7) {
                geste("space", String(localized: "Espace : aperçu"))
                geste("cursorarrow.click.2", String(localized: "Double-clic : ouvrir"))
            }
        case 3:
            Text("Glisse un fichier : elle apparaît ici. Ce que tu y poses reste sous la main, même Side fermé.")
        default:
            VStack(alignment: .leading, spacing: 7) {
                Text("Side a aussi un tiroir, pour tes applications à usage rapide. Il va s'ouvrir pour se présenter.").foregroundStyle(.secondary)
                geste("menubar.arrow.up.rectangle", String(localized: "Réglages : icône Side, barre des menus"))
            }
        }
    }
}

struct OngletsView: View {
    @ObservedObject var store: Store

    var body: some View {
        if store.onglets.count > 1 {
            HStack(spacing: 4) {
                ForEach(Array(store.onglets.enumerated()), id: \.element.id) { i, onglet in
                    OngletView(column: onglet, actif: i == store.ongletActif,
                               choisir: { store.ongletActif = i }, fermer: { store.fermerOnglet(i) })
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

struct OngletView: View {
    @ObservedObject var column: Column
    let actif: Bool
    let choisir: () -> Void
    let fermer: () -> Void
    @State private var survol = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: fermer) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Gris.moyen))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(survol ? 1 : 0)
            .help("Fermer l'onglet")
            .accessibilityLabel("Fermer l'onglet")
            Text(column.titre).font(.callout).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity)
            Color.clear.frame(width: 16, height: 16)
        }
        .foregroundStyle(actif ? Color.primary : Color.secondary)
        .padding(.horizontal, 6)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Color.primary.opacity(actif ? 0.16 : (survol ? 0.09 : 0.05))))
        .contentShape(Capsule())
        .onHover { survol = $0 }
        .onTapGesture(perform: choisir)
        .accessibilityAddTraits(actif ? [.isButton, .isSelected] : .isButton)
    }
}
