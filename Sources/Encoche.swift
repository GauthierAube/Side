// L'île de l'encoche (17/11/2026), d'après les meilleures applications du genre (Alcove, Boring Notch, MediaMate, Droppy) :
// l'encoche du MacBook devient une île noire qui vit. Au repos elle épouse l'encoche ; la musique en cours l'élargit
// (pochette à gauche, petite onde à droite) ; le pointeur l'ouvre (elle gonfle d'abord un instant), comme un clic, deux
// doigts vers le bas ou un fichier qu'on approche. Ouverte, elle montre une seule vue à la fois (le 17/11, à la demande de
// Gauthier) : aujourd'hui, le calendrier du mois, la lecture en cours, le bac à fichiers ; deux doigts de côté passent de
// l'une à l'autre. Le Finder de Side en descend (Descente.swift). Les touches du volume et de la luminosité s'y affichent
// à la place du carré gris de macOS (EncocheTouches.swift).
// Ici : les réglages, la fenêtre, la souris. Le dessin est dans EncocheVues.swift, les sources dans EncocheSources.swift.
import AppKit
import SwiftUI

/// Les choix de l'utilisateur pour l'île (Réglages > Encoche).
final class ConfigEncoche: ObservableObject {
    static let commun = ConfigEncoche()

    /// La musique en cours élargit l'île au repos.
    @Published var activite: Bool { didSet { UserDefaults.standard.set(activite, forKey: "encocheActivite") } }
    /// Le volume et la luminosité s'affichent dans l'île (au lieu du carré de macOS).
    @Published var touches: Bool {
        didSet { UserDefaults.standard.set(touches, forKey: "encocheTouches"); ToucheIle.majActivation() }
    }
    /// L'agenda du jour, à droite de la lecture.
    @Published var calendrier: Bool { didSet { UserDefaults.standard.set(calendrier, forKey: "encocheCalendrier") } }
    /// Le bac à fichiers : un fichier approché de l'encoche l'ouvre.
    @Published var bac: Bool { didSet { UserDefaults.standard.set(bac, forKey: "encocheBac.actif") } }
    /// Le pointeur ouvre l'île (sinon, il la fait seulement gonfler et il faut cliquer).
    @Published var survolOuvre: Bool { didSet { UserDefaults.standard.set(survolOuvre, forKey: "encocheSurvolOuvre") } }
    /// Deux doigts vers le bas sur l'encoche l'ouvrent, vers le haut la referment, de côté changent de vue.
    @Published var geste: Bool { didSet { UserDefaults.standard.set(geste, forKey: "encocheGeste") } }
    /// Le Finder de Side descend de l'encoche, quelle que soit la façon de l'ouvrir (raccourci, coin, secousse).
    @Published var finderDescend: Bool { didSet { UserDefaults.standard.set(finderDescend, forKey: "encocheFinder") } }
    /// Sur un Mac sans encoche (Mac mini, écran externe), une fausse encoche en haut, au milieu de l'écran principal.
    @Published var sansEncoche: Bool {
        didSet { UserDefaults.standard.set(sansEncoche, forKey: "encocheSansEncoche"); Ile.commun.placer() }
    }

    private init() {
        let d = UserDefaults.standard
        func oui(_ cle: String) -> Bool { d.object(forKey: cle) as? Bool ?? true }
        activite = oui("encocheActivite")
        touches = oui("encocheTouches")
        calendrier = oui("encocheCalendrier")
        bac = oui("encocheBac.actif")
        geste = oui("encocheGeste")
        survolOuvre = oui("encocheSurvolOuvre")
        finderDescend = oui("encocheFinder")
        sansEncoche = oui("encocheSansEncoche")
    }
}

enum EtatIle { case repos, hud, ouvert }
/// Les vues de l'île ouverte, une à la fois, dans cet ordre (deux doigts de côté pour passer de l'une à l'autre).
enum PageIle: CaseIterable {
    case aujourdhui, calendrier, lecture, bac

    var nom: String {
        switch self {
        case .aujourdhui: return String(localized: "Aujourd'hui")
        case .calendrier: return String(localized: "Calendrier")
        case .lecture: return String(localized: "Lecture")
        case .bac: return String(localized: "Bac")
        }
    }
    var symbole: String {
        switch self {
        case .aujourdhui: return "sun.horizon.fill"
        case .calendrier: return "calendar"
        case .lecture: return "music.note"
        case .bac: return "tray.fill"
        }
    }
}

/// Ce que l'île montre quand on touche au volume ou à la luminosité.
struct HudIle: Equatable {
    enum Genre { case volume, luminosite }
    var genre: Genre
    var niveau: Double
    var muet = false
    /// Augmente à chaque appui : l'icône rebondit à chaque fois.
    var coup = 0
}

/// L'île : son état, sa taille, sa fenêtre. Une seule, sur l'écran qui a une encoche.
final class Ile: ObservableObject {
    static let commun = Ile()

    @Published private(set) var etat: EtatIle = .repos
    @Published var survol = false
    @Published private(set) var page: PageIle = .aujourdhui
    /// Le sens du dernier changement de vue (1 : vers la droite de la liste), pour que la vue glisse du bon côté.
    @Published private(set) var sens: CGFloat = 1
    @Published private(set) var hud: HudIle?
    @Published var cibleDepot = false
    /// La taille de l'encoche elle-même (celle d'un MacBook Air 13 pouces par défaut).
    @Published private(set) var encoche = CGSize(width: 185, height: 32)

    /// L'écran qui a une encoche (aucun : écran du MacBook fermé, ou Mac sans encoche).
    private(set) var ecran: NSScreen?
    private var panneau: NSPanel?
    private var centreX: CGFloat = 0
    private var finHud: Timer?
    private var departFermeture: Timer?
    private var departOuverture: Timer?
    private var changementGlisse = 0
    private var surveillances: [Any] = []

    /// La fenêtre de l'île reste fixe ; c'est l'île dessinée dedans qui change de taille (animations SwiftUI, bien plus
    /// fluides que de redimensionner une fenêtre). La fenêtre laisse passer les clics partout ailleurs que sur l'île.
    static let largeurFenetre: CGFloat = 840
    static let hauteurFenetre: CGFloat = 300
    static let largeurOuverte: CGFloat = 460
    static let hauteurContenu: CGFloat = 166

    var ouverte: Bool { etat == .ouvert }

    /// La musique en cours élargit l'île au repos.
    var activite: Bool { ConfigEncoche.commun.activite && LectureIle.commun.enActivite }

    /// La taille de l'île, sans les petits évasements du haut (qui la raccordent au bord de l'écran).
    var taille: CGSize {
        let n = encoche
        switch etat {
        case .ouvert: return CGSize(width: Ile.largeurOuverte, height: n.height + Ile.hauteurContenu)
        case .hud: return CGSize(width: n.width + 2 * Ile.aileHud, height: n.height)
        case .repos:
            var w = n.width, h = n.height
            if activite { w += 2 * aile }
            if survol { w += 18; h += 6 }
            return CGSize(width: w, height: h)
        }
    }
    /// Largeur de chaque côté de l'encoche quand la musique joue.
    var aile: CGFloat { encoche.height + 10 }
    static let aileHud: CGFloat = 96

    /// L'île à l'écran, en coordonnées d'AppKit.
    var cadre: NSRect {
        guard let e = ecran else { return .zero }
        let t = taille
        return NSRect(x: centreX - t.width / 2, y: e.frame.maxY - t.height, width: t.width, height: t.height)
    }
    /// L'encoche seule, en coordonnées d'AppKit : le point de départ du Finder et des applications qui en descendent.
    var cadreEncoche: NSRect {
        guard let e = ecran else { return .zero }
        return NSRect(x: centreX - encoche.width / 2, y: e.frame.maxY - encoche.height, width: encoche.width, height: encoche.height)
    }

    // MARK: - Mise en place

    func brancher() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.placer() }
        NotificationCenter.default.addObserver(forName: Partie.changement, object: nil, queue: .main) { [weak self] _ in
            self?.placer()
        }
        LectureIle.commun.demarrer()
        placer()
    }

    /// Trouve l'encoche et y pose la fenêtre (ou la retire s'il n'y a plus d'encoche, ou si la partie est coupée).
    func placer() {
        // L'écran qui a une encoche ; sinon (19/11/2026, Mac mini), l'écran principal, avec une fausse encoche.
        let vraie = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        let e = vraie ?? (ConfigEncoche.commun.sansEncoche ? NSScreen.screens.first : nil)
        guard Partie.encoche.active, let e else {
            if ouverte { fermer() }
            panneau?.orderOut(nil)
            ecran = nil
            arreterSurveillance()
            ToucheIle.majActivation()
            return
        }
        ecran = e
        if vraie != nil {
            let gauche = e.auxiliaryTopLeftArea?.width ?? (e.frame.width - encoche.width) / 2
            let droite = e.auxiliaryTopRightArea?.width ?? (e.frame.width - encoche.width) / 2
            let largeur = max(120, e.frame.width - gauche - droite)
            encoche = CGSize(width: largeur, height: e.safeAreaInsets.top)
            centreX = e.frame.minX + gauche + largeur / 2
        } else {
            // La fausse encoche : la largeur de celle d'un MacBook Air, la hauteur de la barre des menus.
            let barre = e.frame.maxY - e.visibleFrame.maxY
            encoche = CGSize(width: 185, height: max(24, min(barre > 0 ? barre : 32, 40)))
            centreX = e.frame.midX
        }
        let p = panneau ?? creerPanneau()
        p.setFrame(NSRect(x: (centreX - Ile.largeurFenetre / 2).rounded(), y: e.frame.maxY - Ile.hauteurFenetre,
                          width: Ile.largeurFenetre, height: Ile.hauteurFenetre), display: true)
        p.orderFrontRegardless()
        surveiller()
        ToucheIle.majActivation()
    }

    private func creerPanneau() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        // Au-dessus de la barre des menus et de la carte du Finder, sur tous les bureaux, plein écran compris.
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.animationBehavior = .none
        p.ignoresMouseEvents = true
        p.contentView = HoteIle(rootView: VueIle())
        panneau = p
        return p
    }

    // MARK: - Souris et clavier

    private func surveiller() {
        guard surveillances.isEmpty else { return }
        let genres: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .keyDown]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: genres, handler: { [weak self] e in self?.evenement(e, local: false) }) {
            surveillances.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: genres, handler: { [weak self] e in
            self?.evenement(e, local: true)
            return e
        }) { surveillances.append(l) }
    }

    private func arreterSurveillance() {
        surveillances.forEach { NSEvent.removeMonitor($0) }
        surveillances = []
    }

    private func evenement(_ e: NSEvent, local: Bool) {
        let p = NSEvent.mouseLocation
        switch e.type {
        case .keyDown:
            if ouverte, e.keyCode == 53 { fermer() }                 // Échap
            return
        case .leftMouseDown, .rightMouseDown:
            changementGlisse = NSPasteboard(name: .drag).changeCount
            // Un clic ailleurs referme l'île (les clics dans d'autres fenêtres de Side aussi).
            if ouverte, !cadre.insetBy(dx: -4, dy: -4).contains(p), !(local && e.window === panneau) { fermer() }
        case .leftMouseDragged:
            // Un fichier qu'on approche de l'encoche l'ouvre, sur le bac.
            let glisse = NSPasteboard(name: .drag)
            if ConfigEncoche.commun.bac, !ouverte, glisse.changeCount != changementGlisse,
               glisse.types?.contains(.fileURL) == true, cadre.insetBy(dx: -70, dy: -50).contains(p) {
                ouvrir(.bac)
            }
        default: break
        }
        suivreSouris(p)
    }

    /// La fenêtre ne prend la souris qu'au-dessus de l'île ; au repos, l'île gonfle sous le pointeur.
    private func suivreSouris(_ p: NSPoint) {
        guard let fenetre = panneau, ecran != nil else { return }
        let dedans = cadre.insetBy(dx: -3, dy: -3).contains(p)
        if fenetre.ignoresMouseEvents == dedans { fenetre.ignoresMouseEvents = !dedans }
        switch etat {
        case .repos, .hud:
            if dedans != survol {
                if dedans { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                withAnimation(Mouvement.ileSurvol) { survol = dedans }
                // L'île gonfle, puis s'ouvre si le pointeur reste un instant (un passage rapide vers un menu ne l'ouvre pas).
                departOuverture?.invalidate(); departOuverture = nil
                if dedans, ConfigEncoche.commun.survolOuvre, NSEvent.pressedMouseButtons == 0 {
                    departOuverture = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: false) { [weak self] _ in
                        guard let self else { return }
                        self.departOuverture = nil
                        guard !self.ouverte, self.survol, NSEvent.pressedMouseButtons == 0 else { return }
                        self.ouvrir()
                    }
                }
            }
        case .ouvert:
            // Ouverte, elle se referme quand le pointeur s'en éloigne (pas pendant un glisser, ni bouton enfoncé).
            if cadre.insetBy(dx: -28, dy: -28).contains(p) || NSEvent.pressedMouseButtons != 0 {
                departFermeture?.invalidate(); departFermeture = nil
            } else if departFermeture == nil {
                departFermeture = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                    self?.departFermeture = nil
                    guard let self, NSEvent.pressedMouseButtons == 0,
                          !self.cadre.insetBy(dx: -28, dy: -28).contains(NSEvent.mouseLocation) else { return }
                    self.fermer()
                }
            }
        }
    }

    // MARK: - Ouvrir et fermer

    /// Les vues proposées, selon les réglages.
    var pages: [PageIle] {
        let c = ConfigEncoche.commun
        return PageIle.allCases.filter { p in
            switch p {
            case .aujourdhui, .calendrier: return c.calendrier
            case .lecture: return true
            case .bac: return c.bac
            }
        }
    }

    func ouvrir(_ p: PageIle? = nil) {
        guard ecran != nil else { return }
        departOuverture?.invalidate(); departOuverture = nil
        if ouverte {
            if let p { allerA(p) }
            return
        }
        // Par défaut, ce qu'il y a à faire aujourd'hui.
        page = p ?? pages.first ?? .lecture
        if ConfigEncoche.commun.calendrier { CalendrierIle.commun.revenirAujourdhui() }
        LectureIle.commun.rafraichir()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        finHud?.invalidate()
        withAnimation(Mouvement.ile) {
            etat = .ouvert
            survol = false
            hud = nil
        }
        panneau?.ignoresMouseEvents = false
    }

    /// Passe à une autre vue ; elle glisse du côté où elle se trouve dans la liste.
    func allerA(_ p: PageIle) {
        guard p != page else { return }
        let l = pages
        sens = (l.firstIndex(of: p) ?? 0) > (l.firstIndex(of: page) ?? 0) ? 1 : -1
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        // Le sens est posé d'abord, pour que la vue qui part l'emporte avec elle.
        DispatchQueue.main.async { [self] in withAnimation(Mouvement.ile) { page = p } }
    }

    /// La vue suivante (+1) ou précédente (-1).
    func feuilleter(_ d: Int) {
        let l = pages
        guard let i = l.firstIndex(of: page) else { if let p = l.first { allerA(p) }; return }
        guard l.indices.contains(i + d) else { return }
        allerA(l[i + d])
    }

    func fermer() {
        departFermeture?.invalidate(); departFermeture = nil
        departOuverture?.invalidate(); departOuverture = nil
        guard ouverte else { return }
        withAnimation(Mouvement.ileRetour) {
            etat = .repos
            cibleDepot = false
            survol = cadreRepos.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation)
        }
        panneau?.ignoresMouseEvents = !cadre.contains(NSEvent.mouseLocation)
    }

    func basculer() { ouverte ? fermer() : ouvrir() }

    /// L'île au repos, sans survol (pour savoir si le pointeur est dessus au moment de la refermer).
    private var cadreRepos: NSRect {
        guard let e = ecran else { return .zero }
        let w = encoche.width + (activite ? 2 * aile : 0)
        return NSRect(x: centreX - w / 2, y: e.frame.maxY - encoche.height, width: w, height: encoche.height)
    }

    // MARK: - Volume et luminosité

    func montrerHud(_ genre: HudIle.Genre, niveau: Double, muet: Bool = false) {
        guard ecran != nil else { return }
        finHud?.invalidate()
        let suivant = HudIle(genre: genre, niveau: niveau, muet: muet, coup: (hud?.coup ?? 0) + 1)
        // Premier appui : l'île s'étire avec son rebond. Les suivants : seule la jauge bouge.
        withAnimation(etat == .repos ? Mouvement.ile : Mouvement.ileSurvol) {
            hud = suivant
            if etat == .repos { etat = .hud }
        }
        finHud = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            guard let self else { return }
            withAnimation(Mouvement.ileRetour) {
                self.hud = nil
                if self.etat == .hud { self.etat = .repos }
            }
        }
    }
}

/// La vue de l'île dans sa fenêtre : réagit au premier clic (Side n'est jamais l'application active) et aux deux doigts.
final class HoteIle: NSHostingView<VueIle> {
    private var gesteFait = false
    private var cumulX: CGFloat = 0
    private var cumulY: CGFloat = 0

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with e: NSEvent) {
        super.scrollWheel(with: e)
        guard ConfigEncoche.commun.geste else { return }
        // Trackpad : un geste commence quand les doigts se posent. Molette d'une souris : chaque cran compte seul.
        let molette = !e.hasPreciseScrollingDeltas
        if e.phase == .began || molette { cumulX = 0; cumulY = 0; gesteFait = false }
        guard !gesteFait, e.momentumPhase == [] else { return }
        // Le sens des doigts, quel que soit le sens de défilement choisi dans les réglages du Mac :
        // vers le bas et vers la droite comptent en positif.
        let inverse = e.isDirectionInvertedFromDevice
        let dy = inverse ? e.scrollingDeltaY : -e.scrollingDeltaY
        let dx = inverse ? e.scrollingDeltaX : -e.scrollingDeltaX
        cumulY += molette ? dy * 10 : dy
        cumulX += molette ? dx * 10 : dx
        let ile = Ile.commun
        if abs(cumulX) > abs(cumulY) {
            // De côté : la vue suivante (doigts vers la gauche) ou précédente, comme les pages de l'iPhone.
            if abs(cumulX) > 26, ile.ouverte { gesteFait = true; ile.feuilleter(cumulX < 0 ? 1 : -1) }
        } else if cumulY > 18, !ile.ouverte { gesteFait = true; ile.ouvrir() }
        else if cumulY < -18, ile.ouverte { gesteFait = true; ile.fermer() }
    }
}

/// Réglages > Encoche.
struct ReglagesEncoche: View {
    @ObservedObject private var config = ConfigEncoche.commun

    var body: some View {
        Section {
            Toggle("Montrer la musique en cours autour de l'encoche", isOn: $config.activite)
            Toggle("Afficher l'agenda (aujourd'hui et le calendrier)", isOn: $config.calendrier)
            Toggle("Bac à fichiers", isOn: $config.bac)
        } header: { Text("Ce que montre l'île") } footer: {
            Text("Approche un fichier de l'encoche : elle s'ouvre sur le bac. Les fichiers restent où ils sont ; le bac n'en garde que le chemin.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Toggle("Le pointeur ouvre l'île", isOn: $config.survolOuvre)
            Toggle("Gestes à deux doigts", isOn: $config.geste)
            Toggle("Le Finder de Side descend de l'encoche", isOn: $config.finderDescend)
        } header: { Text("Ouvrir") } footer: {
            Text("Sans « Le pointeur ouvre l'île », elle gonfle seulement et un clic l'ouvre. Deux doigts : vers le bas pour ouvrir, de côté pour changer de vue, vers le haut pour refermer. Le Finder descend de l'encoche quelle que soit la façon de l'ouvrir : raccourci, coin, secousse.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Toggle("Afficher l'île sur les écrans sans encoche", isOn: $config.sansEncoche)
        } footer: {
            Text("Une fausse encoche apparaît en haut, au milieu de l'écran principal.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Toggle("Volume et luminosité dans l'encoche", isOn: $config.touches)
        } footer: {
            Text("Remplace le carré gris de macOS. Maintiens ⇧⌥ pour des pas plus fins. Demande l'autorisation Accessibilité, que Side a déjà.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
