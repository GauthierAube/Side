// Le mini-Dock et le lanceur d'applications de la carte.
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Une icône du mini-Dock.
struct AppItem: Identifiable, Equatable {
    let url: URL
    let nom: String
    let ouverte: Bool
    let active: Bool
    let favori: Bool
    var id: String { url.path }
}

extension AppItem {
    /// Une favorite quitte les favorites ; une app simplement ouverte est masquée.
    func retirer() {
        let c = Config.shared
        if favori { c.appsFavorites.removeAll { $0 == url.path } }
        else if !c.appsMasquees.contains(url.path) { c.appsMasquees.append(url.path) }
    }
}

/// Les apps ouvertes (celles qui ont une icône dans le Dock), tenues à jour.
final class Apps: ObservableObject {
    static let shared = Apps()
    @Published var liste: [NSRunningApplication] = []
    @Published var active: pid_t = 0

    private init() {
        let centre = NSWorkspace.shared.notificationCenter
        for nom in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                    NSWorkspace.didActivateApplicationNotification] {
            centre.addObserver(forName: nom, object: nil, queue: .main) { [weak self] _ in self?.rafraichir() }
        }
        rafraichir()
    }

    func rafraichir() {
        liste = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        active = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    }

    /// Ce que le mini-Dock affiche : d'abord les favorites, puis les apps ouvertes (sauf les masquées).
    func elements(_ c: Config) -> [AppItem] {
        var vus = Set<String>(), resultat: [AppItem] = []
        let enCours = liste.compactMap { app in app.bundleURL.map { ($0.standardizedFileURL.path, app) } }
        if c.appsFavoris {
            for chemin in c.appsFavorites where FileManager.default.fileExists(atPath: chemin) && vus.insert(chemin).inserted {
                let app = enCours.first { $0.0 == chemin }?.1
                let nom = FileManager.default.displayName(atPath: chemin).replacingOccurrences(of: ".app", with: "")
                resultat.append(AppItem(url: URL(fileURLWithPath: chemin), nom: nom, ouverte: app != nil,
                                        active: app?.processIdentifier == active, favori: true))
            }
        }
        if c.appsOuvertes {
            for (chemin, app) in enCours where !c.appsMasquees.contains(chemin) && vus.insert(chemin).inserted {
                resultat.append(AppItem(url: URL(fileURLWithPath: chemin), nom: app.localizedName ?? "App", ouverte: true,
                                        active: app.processIdentifier == active, favori: false))
            }
        }
        // L'ordre choisi à la main passe avant tout ; les apps jamais déplacées restent à la suite.
        guard !c.appsOrdre.isEmpty else { return resultat }
        let rang = Dictionary(c.appsOrdre.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return resultat.enumerated().sorted { a, b in
            let ra = rang[a.element.id] ?? Int.max, rb = rang[b.element.id] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// Glisser une icône sur une autre : elle prend sa place, les suivantes se décalent.
    func deplacer(_ chemin: String, sur cible: String, _ c: Config) {
        var ordre = elements(c).map(\.id)
        guard chemin != cible, let de = ordre.firstIndex(of: chemin), let vers = ordre.firstIndex(of: cible) else { return }
        ordre.remove(at: de)
        ordre.insert(chemin, at: vers)
        // Les apps fermées en ce moment gardent leur rang pour plus tard, à la suite.
        c.appsOrdre = ordre + c.appsOrdre.filter { !ordre.contains($0) }
    }
}

/// Le mini-Dock : une pastille flottante avec les apps ouvertes et/ou favorites, puis les raccourcis.
/// Les icônes grossissent en douceur à l'approche du pointeur, comme dans le Dock de macOS.
/// Un clic passe à l'app ; déposer un fichier sur une icône l'ouvre avec cette app ;
/// déposer une app sur la pastille l'ajoute aux favorites.
struct AppsView: View {
    @ObservedObject var apps = Apps.shared
    @ObservedObject var config = Config.shared
    @ObservedObject var store = AppDelegate.shared.store
    let vertical: Bool

    var body: some View {
        // La liste des apps n'est recalculée que lorsqu'une app s'ouvre, se ferme ou qu'un réglage change.
        // L'icône qu'on glisse quitte le mini-Dock : elle est sous la souris, pas en double.
        // Tant qu'elle reste au-dessus du mini-Dock, sa place y est gardée vide : on voit où elle va se poser.
        RangeeDock(items: apps.elements(config).filter { $0.url != store.appEnGlisse || !store.appHorsDock },
                   fantome: store.appEnGlisse, vertical: vertical)
    }
}

/// Les icônes d'apps, gardées en mémoire : les relire à chaque mouvement de souris faisait saccader.
enum Icones {
    private static let cache = NSCache<NSString, NSImage>()
    /// Une icône à la taille d'une ligne de menu.
    static func petite(_ chemin: String) -> NSImage {
        let image = de(chemin).copy() as? NSImage ?? de(chemin)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
    static func de(_ chemin: String) -> NSImage {
        if let image = cache.object(forKey: chemin as NSString) { return image }
        let image = NSWorkspace.shared.icon(forFile: chemin)
        cache.setObject(image, forKey: chemin as NSString)
        return image
    }
}

/// La rangée d'icônes du mini-Dock. Volontairement simple : rien ne bouge sauf l'icône survolée,
/// qui grossit un peu avec l'animation standard de macOS.
struct RangeeDock: View {
    let items: [AppItem]
    var fantome: URL? = nil   // l'icône en cours de glisser : sa place reste vide
    @ObservedObject var config = Config.shared
    let vertical: Bool
    @State private var cible = false
    // La loupe : où est le pointeur le long du mini-Dock, et à quel point elle est « allumée » (0 à 1).
    @State private var souris: CGFloat = 0
    @State private var force: CGFloat = 0
    @State private var longueur: CGFloat = 0   // longueur de la bande où le mini-Dock est centré

    static let marge: CGFloat = 6, ecart: CGFloat = 6
    static let entre: CGFloat = 8   // espace entre le mini-Dock et la pastille du presse-papiers

    /// Les cases du mini-Dock au repos, dans l'ordre : leur longueur, et si c'est une icône (un trait ne grossit pas).
    private func cases(_ t: CGFloat) -> [(l: CGFloat, icone: Bool)] {
        var c: [(l: CGFloat, icone: Bool)] = []
        if config.lanceur { c += [(t, true), (1, false)] }
        c += Array(repeating: (t, true), count: max(1, items.count))
        if !config.raccourcis.isEmpty { c += [(1, false)] + Array(repeating: (t, true), count: config.raccourcis.count) }
        return c
    }

    /// Le grossissement de chaque case quand le pointeur vise le point `m` du mini-Dock au repos.
    /// Comme dans le Dock de macOS : maximal sous le pointeur, il retombe en douceur (courbe en cosinus)
    /// jusqu'à disparaître à deux icônes et demie de distance.
    private func echelles(_ c: [(l: CGFloat, icone: Bool)], _ m: CGFloat, _ t: CGFloat, _ f: CGFloat) -> [CGFloat] {
        let plus = (CGFloat(config.grossissement) - 1) * f, portee = 2.5 * (t + Self.ecart)
        var debut = Self.marge
        return c.map { k in
            defer { debut += k.l + Self.ecart }
            guard k.icone, plus > 0 else { return 1 }
            let d = min(1, abs(debut + k.l / 2 - m) / portee)
            return 1 + plus * 0.5 * (1 + cos(.pi * d))
        }
    }

    /// Où se retrouve, dans le mini-Dock grossi, le point `m` du mini-Dock au repos (mesuré depuis le début du
    /// mini-Dock au repos ; le mini-Dock grossi déborde autant des deux côtés, puisqu'il reste centré).
    private func position(_ c: [(l: CGFloat, icone: Bool)], _ m: CGFloat, _ t: CGFloat, _ f: CGFloat) -> CGFloat {
        let e = echelles(c, m, t, f)
        let enPlus = zip(c, e).reduce(0) { $0 + $1.0.l * ($1.1 - 1) }
        var repos = Self.marge, grossi = Self.marge
        for (k, s) in zip(c, e) {
            if m <= repos { return grossi - (repos - m) - enPlus / 2 }
            if m <= repos + k.l { return grossi + (m - repos) * s - enPlus / 2 }
            repos += k.l + Self.ecart; grossi += k.l * s + Self.ecart
        }
        return grossi - (repos - m) - enPlus / 2
    }

    /// La longueur du mini-Dock au repos, et la loupe de chaque case.
    private func loupe(_ t: CGFloat) -> (CGFloat, [LoupeDock]) {
        // Le calcul de la loupe. Les icônes se décalent en grossissant : on cherche donc quel point du mini-Dock
        // au repos se trouve sous le pointeur maintenant (par approches successives), puis on grossit autour de lui.
        // Sans cela, l'icône visée glisserait sous la souris et tout tremblerait.
        let c = cases(t)
        let repos = 2 * Self.marge + c.reduce(0) { $0 + $1.l } + Self.ecart * CGFloat(max(0, c.count - 1))
        let f = fantome == nil ? force : 0
        let vise: CGFloat = {
            guard f > 0 else { return 0 }
            // Le mini-Dock et la pastille du presse-papiers sont centrés ensemble dans la bande.
            let annexe = config.historique ? Self.entre + t + 2 * Self.marge : 0
            let x = souris - (longueur - repos - annexe) / 2
            var bas: CGFloat = 0, haut = repos
            for _ in 0..<14 {
                let milieu = (bas + haut) / 2
                if position(c, milieu, t, f) < x { bas = milieu } else { haut = milieu }
            }
            return (bas + haut) / 2
        }()
        let e = echelles(c, vise, t, f)
        // L'icône grossit vers la carte : le bord du mini-Dock tourné vers l'extérieur ne bouge pas.
        let ancre: UnitPoint = ["haut": .top, "bas": .bottom, "gauche": .leading, "droite": .trailing][config.dockPosition] ?? .center
        return (repos, e.map { LoupeDock(echelle: $0, marge: t * ($0 - 1) / 2, vertical: vertical, ancre: ancre) })
    }

    var body: some View {
        let t = CGFloat(config.tailleDock)
        let epaisseur = Disposition.dock - 8
        let forme = RoundedRectangle(cornerRadius: min(22, epaisseur / 2.6), style: .continuous)
        let (repos, loupes) = loupe(t)
        let c = cases(t)
        // Numéro de la première case de chaque groupe.
        let debutApps = config.lanceur ? 2 : 0
        let debutRaccourcis = debutApps + max(1, items.count) + 1
        let contenu = Group {
            // Tout à gauche : le bouton « Apps », puis un trait.
            if config.lanceur {
                LanceurIcone(taille: t).environment(\.loupeDock, loupes[min(0, loupes.count - 1)])
                if vertical { Divider().frame(width: t * 0.7) } else { Divider().frame(height: t * 0.7) }
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                AppIcone(item: item, taille: t)
                    .environment(\.loupeDock, loupes[min(debutApps + i, loupes.count - 1)])
                    .opacity(item.url == fantome ? 0 : 1)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))   // apparition / disparition animée
            }
            if items.isEmpty {
                Image(systemName: "plus.app").font(.system(size: t * 0.6)).foregroundStyle(.secondary)
                    .frame(width: t, height: t)
                    .help("Dépose une app ici pour l'ajouter au mini-Dock")
            }
            // Après un séparateur : les raccourcis macOS choisis dans les réglages.
            if !config.raccourcis.isEmpty {
                if vertical { Divider().frame(width: t * 0.7) } else { Divider().frame(height: t * 0.7) }
                ForEach(Array(config.raccourcis.enumerated()), id: \.element) { i, nom in
                    RaccourciIcone(nom: nom, taille: t)
                        .environment(\.loupeDock, loupes[min(debutRaccourcis + i, loupes.count - 1)])
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
        }
        let fond = ZStack {
            VisualEffect()
            Color(nsColor: .windowBackgroundColor).opacity(config.opacite)
        }.clipShape(forme)
        let pastille = Group {
            if vertical { VStack(spacing: Self.ecart) { contenu }.padding(Self.marge) }
            else { HStack(spacing: Self.ecart) { contenu }.padding(Self.marge) }
        }
        // Le pointeur sur le mini-Dock : la loupe s'allume en douceur, puis le suit sans retard.
        .onContinuousHover(coordinateSpace: .named("miniDock")) { phase in
            switch phase {
            case .active(let p):
                souris = vertical ? p.y : p.x
                if force < 1 { withAnimation(Mouvement.bascule) { force = 1 } }
            case .ended:
                withAnimation(Mouvement.bascule) { force = 0 }
            }
        }
        .background(fond)
        .overlay(forme.strokeBorder(cible ? Color.accentColor : Gris.filet, lineWidth: cible ? 2 : 1))
        .onDrop(of: [UTType.fileURL], isTargeted: $cible) { fournisseurs in
            AppDelegate.shared.confirmerApp()
            AppDelegate.shared.ajouterApps(fournisseurs)
            return true
        }
        .contextMenu { Button("Masquer le mini-Dock") { config.apps = false } }
        // Side retient la place exacte du mini-Dock : un clic juste à côté de lui compte comme un clic en dehors.
        .background(Repere(dock: true))
        // À côté, dans sa propre pastille : le presse-papiers, dont la liste se déroule au survol.
        // Il reste à l'écart de la loupe : son icône ne grossit pas et ne bouge pas quand les apps s'écartent.
        let annexe = PresseIcone(taille: t)
            .padding(Self.marge)
            .background(fond)
            .overlay(forme.strokeBorder(Gris.filet, lineWidth: 1))
            .background(Repere())
        Group {
            if !config.historique { pastille }
            else if vertical { VStack(spacing: Self.entre) { pastille; annexe } }
            else { HStack(spacing: Self.entre) { pastille; annexe } }
        }
        // Largeur du mini-Dock au repos (la loupe ne compte pas) : le panneau des apps s'aligne dessus.
        .onAppear { AppDelegate.shared.store.largeurDock = vertical ? 0 : repos }
        .onChange(of: repos) { _, l in AppDelegate.shared.store.largeurDock = vertical ? 0 : l }
        .frame(maxWidth: vertical ? nil : .infinity, maxHeight: vertical ? .infinity : nil)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { longueur = vertical ? g.size.height : g.size.width }
                .onChange(of: g.size) { _, n in longueur = vertical ? n.height : n.width }
        })
        .coordinateSpace(.named("miniDock"))
        .animation(Mouvement.glissement, value: items)
        .animation(Mouvement.glissement, value: config.raccourcis)
        .accessibilityLabel("Mini-Dock")
    }
}

/// La loupe du mini-Dock, vue par une icône : de combien elle grossit, et de quel côté elle s'ancre.
struct LoupeDock: Equatable {
    var echelle: CGFloat = 1
    var marge: CGFloat = 0          // place en plus de chaque côté de l'icône, le long du mini-Dock
    var vertical = false
    var ancre: UnitPoint = .center  // le bord qui ne bouge pas : celui du côté opposé à la carte
}
private struct CleLoupeDock: EnvironmentKey { static let defaultValue = LoupeDock() }
extension EnvironmentValues {
    var loupeDock: LoupeDock {
        get { self[CleLoupeDock.self] }
        set { self[CleLoupeDock.self] = newValue }
    }
}

/// Le grossissement d'une icône du mini-Dock, façon Dock de macOS : elle grossit d'autant plus que le pointeur
/// est proche, et prend réellement plus de place — ses voisines s'écartent. Le calcul est fait par RangeeDock.
struct SurvolDock: ViewModifier {
    @Environment(\.loupeDock) private var loupe
    func body(content: Content) -> some View {
        content
            .scaleEffect(loupe.echelle, anchor: loupe.ancre)
            .padding(loupe.vertical ? .vertical : .horizontal, loupe.marge)
    }
}

/// La petite croix dans un cercle, en haut à gauche d'une icône, comme sur iOS : elle la retire du mini-Dock.
/// Un raccourci macOS dans le mini-Dock : une tuile colorée avec ses initiales.
/// Un clic le lance ; déposer des fichiers dessus le lance avec ces fichiers en entrée.
/// Un repère invisible : la vue qui le porte (mini-Dock, panneau) compte comme une partie de Side pour les clics.
struct Repere: NSViewRepresentable {
    var lanceur = false   // le panneau des applications : un clic hors de lui le referme
    var dock = false      // le mini-Dock : sert à savoir si une icône glissée en est sortie
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        AppDelegate.shared.reperes.add(v)
        if lanceur { AppDelegate.shared.vueLanceur = v }
        if dock { AppDelegate.shared.vueDock = v }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

/// Toutes les applications installées, lues une fois (puis relues à chaque ouverture du panneau, en arrière-plan).
final class Applis: ObservableObject {
    static let shared = Applis()
    struct Appli: Identifiable, Hashable { let url: URL; let nom: String; var id: URL { url } }
    @Published var toutes: [Appli] = []
    private var enCours = false

    func charger() {
        guard !enCours else { return }
        enCours = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let racines = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                           fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
            var vues = Set<String>(), liste: [Appli] = []
            func ajouter(_ u: URL) {
                let chemin = u.resolvingSymlinksInPath().path
                guard u.pathExtension == "app", vues.insert(chemin).inserted else { return }
                liste.append(Appli(url: u, nom: fm.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")))
            }
            for racine in racines {
                let contenu = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: racine), includingPropertiesForKeys: [.isDirectoryKey],
                                                           options: [.skipsHiddenFiles])) ?? []
                for u in contenu {
                    if u.pathExtension == "app" { ajouter(u); continue }
                    // Un dossier d'éditeur (« Adobe… », « Microsoft… ») : on regarde aussi dedans.
                    if (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true, u.lastPathComponent != "Utilities" {
                        ((try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []).forEach(ajouter)
                    }
                }
            }
            liste.sort { $0.nom.localizedStandardCompare($1.nom) == .orderedAscending }
            DispatchQueue.main.async { self.toutes = liste; self.enCours = false }
        }
    }

    /// Les apps dont le nom contient le texte ; celles dont le nom commence par lui d'abord.
    func filtrer(_ texte: String) -> [Appli] {
        let t = texte.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return toutes }
        let trouvees = toutes.filter { $0.nom.localizedStandardContains(t) }
        let debut = trouvees.filter { $0.nom.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .hasPrefix(t.lowercased().folding(options: .diacriticInsensitive, locale: nil)) }
        return debut + trouvees.filter { !debut.contains($0) }
    }
}

/// Le bouton « Apps », tout à gauche du mini-Dock : un clic ouvre la liste de toutes les applications.
struct LanceurIcone: View {
    let taille: CGFloat
    @ObservedObject var store = AppDelegate.shared.store

    private static let icone: NSImage = {
        let apps = "/System/Applications/Apps.app"
        return NSWorkspace.shared.icon(forFile: FileManager.default.fileExists(atPath: apps) ? apps : "/Applications")
    }()

    var body: some View {
        let cote = Config.shared.dockPosition
        // Le panneau part de l'icône : vers le bas si le mini-Dock est en haut, vers le haut s'il est en bas…
        let ancre: Alignment = ["haut": .topLeading, "bas": .bottomLeading, "gauche": .topLeading, "droite": .topTrailing][cote] ?? .topLeading
        let pointDepart: UnitPoint = ["haut": .topLeading, "bas": .bottomLeading, "gauche": .topLeading, "droite": .topTrailing][cote] ?? .topLeading
        let ecart = taille + 16 + taille * (CGFloat(Config.shared.grossissement) - 1)
        let ouvert = store.lanceurOuvert || ProcessInfo.processInfo.arguments.contains("--lanceur")
        Image(nsImage: Self.icone)
            .resizable().frame(width: taille, height: taille)
            .modifier(SurvolDock())
            .contentShape(Rectangle())
            .onTapGesture { store.lanceurOuvert.toggle() }
            .contextMenu {
                Button("Masquer le bouton Apps") { store.lanceurOuvert = false; Config.shared.lanceur = false }
            }
            .overlay(alignment: ancre) {
                if ouvert {
                    LanceurPanneau { store.lanceurOuvert = false }
                        .offset(x: cote == "gauche" ? ecart : (cote == "droite" ? -ecart : -6),
                                y: cote == "haut" ? ecart : (cote == "bas" ? -ecart : -6))
                        .transition(.scale(scale: 0.15, anchor: pointDepart).combined(with: .opacity))
                }
            }
            .animation(Mouvement.ressort, value: store.lanceurOuvert)
            .help("Toutes les applications")
            .accessibilityLabel("Toutes les applications")
            .accessibilityAddTraits(.isButton)
    }
}

/// Le panneau des applications : une recherche déjà prête à taper, et la grille des apps.
/// Entrée lance la première trouvée. On peut aussi glisser une app vers le mini-Dock pour l'y garder.
struct LanceurPanneau: View {
    let fermer: () -> Void
    @ObservedObject var applis = Applis.shared
    @ObservedObject var store = AppDelegate.shared.store
    @State private var texte = ""
    @FocusState private var champ: Bool

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: Rayon.panneau, style: .continuous)
        let trouvees = applis.filtrer(texte)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher une app", text: $texte)
                    .textFieldStyle(.plain).focused($champ)
                    .onSubmit { if let premiere = trouvees.first { lancer(premiere) } }
                    .onExitCommand { fermer() }
                if !texte.isEmpty {
                    Button { texte = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Effacer la recherche")
                }
            }
            .padding(.horizontal, 9).frame(height: 26)
            .background(Capsule().fill(Gris.moyen))
            .padding(8)
            Divider()
            if trouvees.isEmpty {
                Text(applis.toutes.isEmpty ? "Chargement…" : "Aucune app").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 4)], spacing: 6) {
                        ForEach(Array(trouvees.enumerated()), id: \.element.id) { rang, app in
                            CaseAppli(app: app, premiere: rang == 0 && !texte.isEmpty) { lancer(app) }
                        }
                    }
                    .padding(10)
                }
            }
        }
        // Aussi large que le mini-Dock, sans descendre sous 330 points.
        .frame(width: max(330, store.largeurDock), height: 300)
        .background(Repere(lanceur: true))
        .background(ZStack { VisualEffect(); Color(nsColor: .windowBackgroundColor).opacity(0.55) })
        .clipShape(forme)
        .overlay(forme.strokeBorder(Gris.filet, lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
        .onAppear {
            applis.charger()
            DispatchQueue.main.async { champ = true }
        }
        .onTapGesture {}   // un clic dans le panneau ne le referme pas
    }

    private func lancer(_ app: Applis.Appli) {
        fermer()
        AppDelegate.shared.allerA(app.url)
    }
}

/// Une app dans la grille : un clic la lance ; glissée sur le mini-Dock, elle y reste.
struct CaseAppli: View {
    let app: Applis.Appli
    let premiere: Bool   // celle qu'Entrée lancera
    let action: () -> Void
    @State private var survol = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: Icones.de(app.url.path)).resizable().frame(width: 38, height: 38)
            Text(app.nom).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .top)
        }
        .padding(.vertical, 6).padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: Rayon.encadre).fill(
            premiere ? Selection.bleu.opacity(0.22) : (survol ? Gris.moyen : .clear)))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture(perform: action)
        .onDrag { NSItemProvider(object: app.url as NSURL) }
        .help(app.nom)
        .accessibilityLabel(app.nom)
        .accessibilityAddTraits(.isButton)
    }
}

/// Le presse-papiers dans le mini-Dock : passer la souris dessus déroule l'historique,
/// un clic sur une ligne la recopie. Aucun clic pour regarder, un seul pour reprendre.
struct PresseIcone: View {
    let taille: CGFloat
    @ObservedObject var config = Config.shared
    @ObservedObject var presse = PressePapiers.shared
    @State private var surIcone = false
    @State private var surListe = false
    @State private var ouvert = false
    @State private var filtre = ""

    var body: some View {
        // La liste se déroule vers la carte : sous le Dock s'il est en haut, au-dessus s'il est en bas…
        // Sauf si la place est libre de l'autre côté : elle part alors à l'opposé, sans cacher la carte.
        let dehors = config.presseDehors > 0
        let cote = dehors ? (config.dockPosition == "bas" ? "haut" : "bas") : config.dockPosition
        let ancre: Alignment = ["haut": .top, "bas": .bottom, "gauche": .bottomLeading, "droite": .bottomTrailing][cote] ?? .top
        // Vers la carte, l'icône grossit aussi : la liste s'écarte d'autant pour ne pas être recouverte.
        let ecart = taille + 14 + (dehors ? 0 : taille * (CGFloat(config.grossissement) - 1))
        ZStack {
            RoundedRectangle(cornerRadius: taille * 0.24, style: .continuous)
                .fill(Color.primary.opacity(ouvert ? 0.22 : 0.12))
                .padding(taille * 0.06)
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: taille * 0.42, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(width: taille, height: taille)
        .modifier(SurvolDock())
        .contentShape(Rectangle())
        .onHover { surIcone = $0; suivre() }
        .onTapGesture { ouvert.toggle() }
        .overlay(alignment: ancre) {
            if ouvert || ProcessInfo.processInfo.arguments.contains("--presse") {
                PresseListe(filtre: $filtre) { fermer() }
                    // Un petit triangle relie la liste à son icône.
                    .overlay(alignment: ancre) {
                        PointeListe()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .frame(width: 18, height: 9)
                            .rotationEffect(.degrees(["haut": 0, "bas": 180, "gauche": -90, "droite": 90][cote] ?? 0))
                            .offset(x: cote == "gauche" ? -13 : (cote == "droite" ? 13 : 0),
                                    y: cote == "haut" ? -8 : (cote == "bas" ? 8 : -(taille / 2 - 4.5)))
                    }
                    .onHover { surListe = $0; suivre() }
                    .offset(x: cote == "gauche" ? ecart : (cote == "droite" ? -ecart : 0),
                            y: cote == "haut" ? ecart : (cote == "bas" ? -ecart : 0))
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: cote == "bas" ? .bottom : .top)))
            }
        }
        .animation(Mouvement.survol, value: ouvert)
        .onChange(of: ouvert) { _, _ in AppDelegate.shared.rafraichirOmbre() }
        .help("Presse-papiers")
        .accessibilityLabel("Historique du presse-papiers")
        .accessibilityAddTraits(.isButton)
    }

    private func fermer() { ouvert = false; filtre = "" }

    /// La liste s'ouvre dès que la souris arrive sur l'icône. À la sortie, un court délai laisse
    /// le temps d'aller de l'icône à la liste sans qu'elle se referme.
    private func suivre() {
        if surIcone || surListe { ouvert = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if !surIcone && !surListe && filtre.isEmpty { ouvert = false }
        }
    }
}

/// Le triangle qui pointe de la liste vers l'icône du presse-papiers (dessiné pointe en haut).
struct PointeListe: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// La liste déroulée : une recherche (seulement quand l'historique est long) et les éléments copiés.
struct PresseListe: View {
    @Binding var filtre: String
    let fermer: () -> Void
    @ObservedObject var presse = PressePapiers.shared
    @ObservedObject var config = Config.shared
    @State private var recherche = false
    @FocusState private var champ: Bool

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: Rayon.interieur, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if recherche {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Rechercher", text: $filtre).textFieldStyle(.plain).focused($champ)
                    Button { filtre = ""; recherche = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Fermer la recherche")
                } else {
                    Text("Presse-papiers · 7 jours").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    // La petite loupe : un clic ouvre le champ de recherche.
                    Button { recherche = true; champ = true } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Gris.moyen))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain).help("Rechercher dans le presse-papiers").accessibilityLabel("Rechercher dans le presse-papiers")
                }
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(recherche ? Gris.leger : Color.clear)
            PressePapiersView(filtre: filtre, apresCopie: fermer)
        }
        // Déroulée à l'opposé de la carte, elle ne dépasse pas la place libre de ce côté de l'écran.
        .frame(width: 320, height: min(config.presseDehors > 0 ? config.presseDehors - 16 : 400,
                                       max(120, CGFloat(presse.elements.count) * 52 + 44)))
        .background(Repere())
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(forme)
        .overlay(forme.strokeBorder(Gris.filet, lineWidth: 1))
        // Hors de la carte, c'est l'ombre de la fenêtre qui la détache du fond. Garder aussi l'ombre dessinée ici
        // ferait apparaître un liseré : macOS tracerait le contour de ce halo.
        .shadow(color: .black.opacity(config.presseDehors > 0 ? 0 : 0.28), radius: 16, y: 6)
        .onDisappear { recherche = false }
    }
}

struct RaccourciIcone: View {
    let nom: String
    let taille: CGFloat
    @ObservedObject var raccourcis = Raccourcis.shared
    @State private var cible = false

    /// Les initiales des deux premiers mots, et une couleur toujours la même pour un nom donné.
    private var initiales: String {
        let mots = nom.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let lettres = mots.prefix(2).compactMap(\.first).map(String.init).joined()
        return (lettres.isEmpty ? String(nom.prefix(1)) : lettres).uppercased()
    }
    private var couleur: Color {
        let teinte = nom.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }
        return Color(hue: Double(teinte) / 360, saturation: 0.62, brightness: 0.82)
    }

    var body: some View {
        let actif = raccourcis.enCours == nom
        ZStack {
            RoundedRectangle(cornerRadius: taille * 0.24, style: .continuous).fill(couleur.gradient)
                .padding(taille * 0.06)
            if actif {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Text(initiales)
                    .font(.system(size: taille * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: taille, height: taille)
        .modifier(SurvolDock())
        .background(Circle().fill(Color.accentColor.opacity(cible ? 0.45 : 0)).padding(-3))
        .contentShape(Rectangle())
        .onTapGesture { AppDelegate.shared.lancerRaccourci(nom, []) }
        .onDrop(of: [UTType.fileURL], isTargeted: $cible) { fournisseurs in
            AppDelegate.shared.lancerRaccourci(nom, fournisseurs)
            return true
        }
        .contextMenu { Button("Retirer du mini-Dock") { Config.shared.raccourcis.removeAll { $0 == nom } } }
        .help("Raccourci « \(nom) ». Dépose un fichier pour le lui passer.")
        .accessibilityLabel("Raccourci \(nom)")
        .accessibilityAddTraits(.isButton)
    }
}

struct AppIcone: View {
    let item: AppItem
    let taille: CGFloat
    @State private var cible = false

    var body: some View {
        let cote = Config.shared.dockPosition
        Image(nsImage: Icones.de(item.url.path))
            .resizable().interpolation(.high)
            .frame(width: taille, height: taille)
            .modifier(SurvolDock())
            // Comme dans le Dock : un petit point sous les apps ouvertes, sur le bord extérieur du mini-Dock.
            .overlay(alignment: ["haut": .top, "bas": .bottom, "gauche": .leading, "droite": .trailing][cote] ?? .bottom) {
                if item.ouverte {
                    // Juste contre l'icône, à bonne distance du liseré du mini-Dock.
                    Circle().fill(Color.primary.opacity(0.85)).frame(width: 3.5, height: 3.5)
                        .offset(x: cote == "gauche" ? -3 : (cote == "droite" ? 3 : 0),
                                y: cote == "haut" ? -3 : (cote == "bas" ? 3 : 0))
                        .allowsHitTesting(false)
                }
            }
            .background(Circle().fill(Color.accentColor.opacity(cible ? 0.45 : 0)).padding(-3))
            .contentShape(Rectangle())
            .onTapGesture { AppDelegate.shared.allerA(item.url) }
            // Comme dans le Dock : glisser l'icône hors du mini-Dock et la lâcher la retire.
            // Le glisser porte un type que seul Side connaît, pour qu'aucune autre app ne l'accepte.
            .onDrag {
                AppDelegate.shared.appGlissee = item
                DispatchQueue.main.async { AppDelegate.shared.store.appEnGlisse = item.url }
                let colis = NSItemProvider()
                colis.registerDataRepresentation(forTypeIdentifier: "com.gauthieraube.side.app", visibility: .ownProcess) { fini in
                    fini(Data(), nil)
                    return nil
                }
                return colis
            }
            .onDrop(of: [UTType.fileURL, DepotIcone.typeApp], delegate: DepotIcone(item: item, cible: $cible))
            .contextMenu {
                if item.favori {
                    Button("Retirer des favorites") { item.retirer() }
                } else {
                    Button("Garder dans le mini-Dock") { Config.shared.appsFavorites.append(item.url.path) }
                    Button("Masquer cette app") { item.retirer() }
                }
                Divider()
                Button("Masquer le mini-Dock") { Config.shared.apps = false }
            }
            .help(item.nom)
            .accessibilityLabel(item.nom)
            .accessibilityAddTraits(.isButton)
    }
}
