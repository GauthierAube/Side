// La recherche sur le web (17/11/2026) : un raccourci fait descendre de l'encoche une pilule noire avec un champ, comme
// Spotlight. On tape, on valide : la pilule s'élargit et s'étire vers le bas (le ressort de l'île) et montre la page, avec le
// moteur de Safari. Échap ou un clic ailleurs la referme ; la page reste en mémoire, on la retrouve à la prochaine ouverture.
// Ce n'est pas un onglet de Safari (Apple ne permet pas d'afficher Safari dans une autre application) : un bouton y envoie
// la page.
// La fenêtre reste fixe ; c'est la forme dessinée dedans qui change de taille, comme pour l'île. La page web, elle, garde
// toujours sa taille finale et n'apparaît qu'une fois la forme arrivée : la redimensionner à chaque image saccaderait.
import AppKit
import Carbon.HIToolbox
import SwiftUI
import WebKit

enum MoteurRecherche: String, CaseIterable, Identifiable {
    case google, duckduckgo, ecosia, qwant, bing
    var id: String { rawValue }

    var nom: String {
        switch self {
        case .google: return "Google"
        case .duckduckgo: return "DuckDuckGo"
        case .ecosia: return "Ecosia"
        case .qwant: return "Qwant"
        case .bing: return "Bing"
        }
    }
    var adresse: String {
        switch self {
        case .google: return "https://www.google.com/search"
        case .duckduckgo: return "https://duckduckgo.com/"
        case .ecosia: return "https://www.ecosia.org/search"
        case .qwant: return "https://www.qwant.com/"
        case .bing: return "https://www.bing.com/search"
        }
    }
}

/// Les choix de l'utilisateur pour la recherche (Réglages > Raccourcis clavier).
final class ConfigRecherche: ObservableObject {
    static let commun = ConfigRecherche()
    private let d = UserDefaults.standard

    @Published var moteur: MoteurRecherche { didSet { d.set(moteur.rawValue, forKey: "rechercheMoteur") } }
    /// Raccourci clavier : -1 = aucun, sinon le code de la touche. Au départ : Majuscule + Commande + Espace
    /// (Option + Espace est l'espace insécable du clavier français, Commande + Espace est Spotlight).
    @Published var touche: Int { didSet { d.set(touche, forKey: "rechercheTouche") } }
    @Published var mods: Int { didSet { d.set(mods, forKey: "rechercheMods") } }
    @Published var libelle: String { didSet { d.set(libelle, forKey: "rechercheLibelle") } }

    /// Pourquoi le dernier raccourci tapé n'a pas été pris (vide s'il l'a été).
    @Published var refus = ""

    func definirRaccourci(touche: Int, mods: Int, libelle: String) {
        let ancien = (self.touche, self.mods, self.libelle)
        self.touche = touche
        self.mods = mods
        self.libelle = libelle
        refus = ""
        guard !Recherche.commun.installerRaccourci() else { return }
        // macOS refuse la combinaison : une autre partie de Side ou une autre application la tient. On garde l'ancien.
        let autre = RaccourcisGlobaux.propriétaire(touche: UInt32(touche), modifs: UInt32(mods)).map { nom -> String in
            if nom == "finder" { return String(localized: "le Finder") }
            if nom.hasPrefix("tiroir") { return String(localized: "le tiroir") }
            if nom.hasPrefix("pleinEcran") { return String(localized: "le plein écran") }
            return nom
        }
        refus = autre.map { String(localized: "\(libelle) ouvre déjà \($0) dans Side. L'ancien raccourci est gardé.") }
            ?? String(localized: "\(libelle) est déjà pris par macOS ou par une autre application. L'ancien raccourci est gardé.")
        (self.touche, self.mods, self.libelle) = ancien
        Recherche.commun.installerRaccourci()
    }

    /// Attend la prochaine combinaison de touches tapée dans la fenêtre Réglages (Échap annule).
    func ecouterRaccourci(fin: @escaping () -> Void) {
        SaisieRaccourci.attendre(suspendre: { RaccourcisGlobaux.retirer(Recherche.nomRaccourci) },
                                 reprendre: { Recherche.commun.installerRaccourci() },
                                 choisi: { [weak self] in self?.definirRaccourci(touche: $0, mods: $1, libelle: $2) },
                                 fin: fin)
    }

    private init() {
        moteur = d.string(forKey: "rechercheMoteur").flatMap(MoteurRecherche.init) ?? .google
        touche = d.object(forKey: "rechercheTouche") as? Int ?? kVK_Space
        mods = d.object(forKey: "rechercheMods") as? Int ?? (shiftKey | cmdKey)
        libelle = d.string(forKey: "rechercheLibelle") ?? ("⇧⌘" + String(localized: "Espace"))
    }
}

enum EtatRecherche { case ferme, pilule, page }

private final class PanneauRecherche: NSPanel {
    override var canBecomeKey: Bool { true }       // pour taper dans le champ et dans la page, sans activer Side
}

final class Recherche: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let commun = Recherche()
    static let nomRaccourci = "recherche"
    static let largeurPilule: CGFloat = 620
    static let hauteurBarre: CGFloat = 52
    /// La marge de la fenêtre autour de la page : la place de l'ombre et du rebond du ressort.
    private static let marge: CGFloat = 80

    @Published private(set) var etat: EtatRecherche = .ferme
    @Published var texte = ""
    @Published private(set) var titre = ""
    @Published private(set) var progression: Double = 0
    @Published private(set) var charge = false
    @Published private(set) var peutReculer = false
    @Published private(set) var peutAvancer = false
    /// Une page est restée en mémoire depuis la dernière fois : on peut la reprendre.
    @Published private(set) var aUnePage = false
    /// Augmente quand le champ doit reprendre le clavier.
    @Published private(set) var appelChamp = 0
    @Published private(set) var opacite: Double = 1

    // La géométrie, en coordonnées de la vue (origine en haut à gauche de la fenêtre).
    @Published private(set) var depart: CGRect = .zero
    @Published private(set) var haut: CGFloat = 120
    @Published private(set) var taillePage = CGSize(width: 1000, height: 640)
    @Published private(set) var zone = CGSize(width: 1160, height: 800)

    private var panneau: PanneauRecherche?
    private var cadreWeb: NSView?
    private var page: WKWebView?
    private var observations: [NSKeyValueObservation] = []
    private var ecoutes: [Any] = []
    private var tour = 0
    /// Elle part de l'encoche (sinon, du bord haut de l'écran, en fondu).
    private var depuisEncoche = false
    /// Pour les essais : ouverte sans prendre le clavier à l'application en cours.
    private var sansClavier = false

    var ouverte: Bool { etat != .ferme }

    /// La forme à l'écran selon l'état : dans l'encoche, en pilule, ou étirée autour de la page.
    var cadre: CGRect {
        switch etat {
        case .ferme: return depart
        case .pilule:
            return CGRect(x: (zone.width - Recherche.largeurPilule) / 2, y: haut, width: Recherche.largeurPilule, height: Recherche.hauteurBarre)
        case .page:
            return CGRect(x: (zone.width - taillePage.width) / 2, y: haut, width: taillePage.width, height: taillePage.height)
        }
    }

    // MARK: - Mise en place

    func brancher() { installerRaccourci() }

    /// (Ré)installe le raccourci clavier choisi dans les réglages (aucun si on l'a effacé). Faux si macOS le refuse.
    @discardableResult
    func installerRaccourci() -> Bool {
        RaccourcisGlobaux.retirer(Recherche.nomRaccourci)
        let c = ConfigRecherche.commun
        guard c.touche >= 0 else { return true }
        return RaccourcisGlobaux.ajouter(Recherche.nomRaccourci, touche: UInt32(c.touche), modifs: UInt32(c.mods)) { [weak self] in
            self?.basculer()
        }
    }

    func basculer() { ouverte ? fermer() : ouvrir() }

    /// Pose la fenêtre sur cet écran et calcule d'où part la forme, où se tient la pilule et la taille de la page.
    private func placer(sur e: NSScreen) {
        let f = e.frame, visible = e.visibleFrame
        let hautPilule = max((f.height * 0.12).rounded(), e.safeAreaInsets.top + 44)
        let largeur = min(1080, f.width - 96)
        let hauteur = max(320, (f.maxY - hautPilule) - visible.minY - 28)
        let l = largeur + 2 * Recherche.marge, h = hautPilule + hauteur + Recherche.marge
        let cadreFenetre = NSRect(x: (f.midX - l / 2).rounded(), y: f.maxY - h, width: l, height: h)
        let ile = Ile.commun
        depuisEncoche = ile.ecran == e
        if depuisEncoche {
            let n = ile.cadreEncoche
            depart = CGRect(x: n.minX - cadreFenetre.minX, y: 0, width: n.width, height: n.height)
        } else {
            depart = CGRect(x: l / 2 - 90, y: 0, width: 180, height: 10)
        }
        haut = hautPilule
        taillePage = CGSize(width: largeur, height: hauteur)
        zone = CGSize(width: l, height: h)

        let p = panneau ?? creerPanneau()
        p.setFrame(cadreFenetre, display: false)
        cadreWeb?.frame = NSRect(x: (l - largeur) / 2, y: h - hautPilule - hauteur, width: largeur,
                                 height: hauteur - Recherche.hauteurBarre)
    }

    private func creerPanneau() -> PanneauRecherche {
        let p = PanneauRecherche(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        // Sous l'île (elle garde l'encoche noire pendant que la forme en sort), au-dessus de tout le reste.
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.animationBehavior = .none

        let fond = NSView()
        let hote = NSHostingView(rootView: VueRecherche())
        hote.autoresizingMask = [.width, .height]
        fond.addSubview(hote)

        // La page, dans un cadre aux coins du bas arrondis comme la forme.
        let cadre = NSView()
        cadre.wantsLayer = true
        cadre.layer?.cornerRadius = Rayon.fenetre
        cadre.layer?.cornerCurve = .continuous
        cadre.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        cadre.layer?.masksToBounds = true
        cadre.isHidden = true
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true
        let web = WKWebView(frame: .zero, configuration: config)
        // Se présenter comme Safari : les sites servent alors leur page habituelle.
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
        web.allowsBackForwardNavigationGestures = true
        web.allowsMagnification = true
        web.navigationDelegate = self
        web.uiDelegate = self
        web.autoresizingMask = [.width, .height]
        cadre.addSubview(web)
        fond.addSubview(cadre)
        observations = [
            web.observe(\.estimatedProgress) { [weak self] w, _ in DispatchQueue.main.async { self?.progression = w.estimatedProgress } },
            web.observe(\.title) { [weak self] w, _ in DispatchQueue.main.async { self?.titre = w.title ?? "" } },
            web.observe(\.isLoading) { [weak self] w, _ in DispatchQueue.main.async { self?.charge = w.isLoading } },
            web.observe(\.canGoBack) { [weak self] w, _ in DispatchQueue.main.async { self?.peutReculer = w.canGoBack } },
            web.observe(\.canGoForward) { [weak self] w, _ in DispatchQueue.main.async { self?.peutAvancer = w.canGoForward } },
        ]
        p.contentView = fond
        panneau = p
        cadreWeb = cadre
        page = web
        return p
    }

    // MARK: - Ouvrir et fermer

    func ouvrir(sansClavier: Bool = false) {
        guard !ouverte, !CaptureEcran.enCours, let e = Ecrans.deTravail else { return }
        self.sansClavier = sansClavier
        placer(sur: e)
        guard let p = panneau else { return }
        tour += 1
        let ce = tour
        texte = ""
        cadreWeb?.isHidden = true
        var sans = Transaction()
        sans.disablesAnimations = true
        withTransaction(sans) { etat = .ferme; opacite = depuisEncoche ? 1 : 0 }
        p.orderFrontRegardless()
        if !sansClavier { p.makeKey() }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        DispatchQueue.main.async { [self] in
            guard tour == ce else { return }
            withAnimation(Mouvement.ile) { etat = .pilule; opacite = 1 }
            appelChamp += 1
        }
        ecouter()
    }

    func fermer() {
        guard ouverte, let p = panneau else { return }
        tour += 1
        let ce = tour
        arreterEcoute()
        page?.pauseAllMediaPlayback()
        // La page s'efface d'abord (un instant), puis la forme remonte dans l'encoche.
        let avaitPage = etat == .page
        if avaitPage {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Mouvement.duree(0.08)
                cadreWeb?.animator().alphaValue = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (avaitPage ? Mouvement.duree(0.07) : 0)) { [self] in
            guard tour == ce else { return }
            cadreWeb?.isHidden = true
            withAnimation(Mouvement.ileRetour) { etat = .ferme; opacite = depuisEncoche ? 1 : 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + Mouvement.duree(0.36)) { [self] in
                if tour == ce { p.orderOut(nil) }
            }
        }
    }

    /// Entrée dans le champ : une adresse, une recherche, ou (champ vide) la dernière page.
    func valider() {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            if aUnePage { montrerPage() }
            return
        }
        guard let url = Recherche.adresse(pour: t, moteur: ConfigRecherche.commun.moteur) else { return }
        page?.load(URLRequest(url: url))
        aUnePage = true
        montrerPage()
    }

    /// Rouvre la page restée en mémoire.
    func reprendre() { if aUnePage { montrerPage() } }

    private func montrerPage() {
        guard etat != .page else { donnerClavierALaPage(); return }
        let ce = tour
        withAnimation(Mouvement.ile) { etat = .page }
        // La page arrive en fondu une fois la forme presque en place (elle garde sa taille finale tout du long).
        DispatchQueue.main.asyncAfter(deadline: .now() + Mouvement.duree(0.2)) { [self] in
            guard tour == ce, etat == .page, let c = cadreWeb else { return }
            c.alphaValue = 0
            c.isHidden = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Mouvement.duree(0.28)
                c.animator().alphaValue = 1
            }
            donnerClavierALaPage()
        }
    }

    private func donnerClavierALaPage() {
        guard !sansClavier, let p = panneau, let w = page else { return }
        p.makeFirstResponder(w)
    }

    func reculer() { page?.goBack() }
    func avancer() { page?.goForward() }
    func recharger() { page?.reload() }

    /// Envoie la page dans un vrai onglet de Safari, et referme.
    func ouvrirDansSafari() {
        guard let u = page?.url else { return }
        if let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            NSWorkspace.shared.open([u], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(u)
        }
        fermer()
    }

    /// Ce que le champ ouvre : l'adresse telle quelle si c'en est une, sinon une recherche avec le moteur choisi.
    static func adresse(pour t: String, moteur: MoteurRecherche) -> URL? {
        if t.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil, let u = URL(string: t) { return u }
        // « wakademy.com », « fr.wikipedia.org/wiki/Didgeridoo », « localhost:3000 » : pas d'espace, et un domaine au bout.
        let domaine = "^([a-z0-9-]+\\.)+[a-z]{2,}(:[0-9]+)?(/.*)?$|^localhost(:[0-9]+)?(/.*)?$"
        if !t.contains(" "), t.range(of: domaine, options: [.regularExpression, .caseInsensitive]) != nil,
           let u = URL(string: (t.lowercased().hasPrefix("localhost") ? "http://" : "https://") + t) { return u }
        var c = URLComponents(string: moteur.adresse)
        c?.queryItems = [URLQueryItem(name: "q", value: t)]
        return c?.url
    }

    // MARK: - Clavier et souris

    private func ecouter() {
        arreterEcoute()
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { [weak self] e in
            guard let self else { return e }
            if e.type == .keyDown { return self.touche(e) ? nil : e }
            if !self.dansLaForme(NSEvent.mouseLocation) { self.fermer() }
            return e
        }) { ecoutes.append(l) }
        // Un clic dans une autre application referme, comme Spotlight.
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self, !CaptureEcran.enCours, !self.dansLaForme(NSEvent.mouseLocation) else { return }
            self.fermer()
        }) { ecoutes.append(g) }
    }

    private func arreterEcoute() {
        ecoutes.forEach { NSEvent.removeMonitor($0) }
        ecoutes = []
    }

    private func dansLaForme(_ p: NSPoint) -> Bool {
        guard let f = panneau?.frame else { return false }
        let c = cadre
        return NSRect(x: f.minX + c.minX, y: f.maxY - c.maxY, width: c.width, height: c.height).insetBy(dx: -6, dy: -6).contains(p)
    }

    /// Les touches de la pilule. Vrai si la touche est prise.
    private func touche(_ e: NSEvent) -> Bool {
        guard e.window === panneau else { return false }
        let commande = e.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
        switch Int(e.keyCode) {
        case kVK_Escape: fermer(); return true
        case kVK_ANSI_L where commande: appelChamp += 1; return true
        case kVK_ANSI_R where commande && etat == .page: recharger(); return true
        case kVK_ANSI_W where commande: fermer(); return true
        case kVK_Return where commande && etat == .page: ouvrirDansSafari(); return true
        default: return false
        }
    }

    // MARK: - La page

    /// Un lien qui voudrait une nouvelle fenêtre s'ouvre ici.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil { webView.load(action.request) }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    // MARK: - Essais

    /// « Side --test-recherche » : ce que le champ ferait de quelques saisies, puis quitte.
    static func essais() {
        for t in ["didgeridoo", "wakademy.com", "fr.wikipedia.org/wiki/Didgeridoo", "https://example.com/a?b=c", "3.14",
                  "prix du café", "localhost:3000", "fin de phrase.", "a.b c"] {
            print(t.padding(toLength: 34, withPad: " ", startingAt: 0), "→", adresse(pour: t, moteur: .google)?.absoluteString ?? "rien")
        }
        exit(0)
    }

    /// Pour les essais (commande « recherche:texte ») : ouvre sans prendre le clavier, et lance la recherche.
    func essai(_ t: String) {
        if !ouverte { ouvrir(sansClavier: true) }
        guard !t.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [self] in
            texte = t
            valider()
        }
    }
}

// MARK: - Le dessin

struct VueRecherche: View {
    @ObservedObject private var r = Recherche.commun
    @FocusState private var champ: Bool

    var body: some View {
        let c = r.cadre
        let ouverte = r.etat != .ferme
        let rayonHaut: CGFloat = r.etat == .ferme ? 0 : r.etat == .pilule ? Recherche.hauteurBarre / 2 : Rayon.fenetre
        let rayonBas: CGFloat = r.etat == .ferme ? 10 : r.etat == .pilule ? Recherche.hauteurBarre / 2 : Rayon.fenetre
        let forme = UnevenRoundedRectangle(topLeadingRadius: rayonHaut, bottomLeadingRadius: rayonBas,
                                           bottomTrailingRadius: rayonBas, topTrailingRadius: rayonHaut, style: .continuous)
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                barre
                    .frame(height: Recherche.hauteurBarre)
                    .opacity(ouverte ? 1 : 0)
                    .blur(radius: ouverte ? 0 : 6)
                Spacer(minLength: 0)
            }
            .frame(width: c.width, height: c.height, alignment: .top)
            .clipShape(forme)
            .background(forme.fill(Color.black).shadow(color: .black.opacity(ouverte ? 0.4 : 0), radius: 28, y: 12))
            .overlay(forme.strokeBorder(Color.white.opacity(ouverte ? 0.1 : 0), lineWidth: 1))
            .offset(x: c.minX, y: c.minY)
            .opacity(r.opacite)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .onChange(of: r.appelChamp) {
            // Le champ reprend le clavier (même s'il croit l'avoir encore), et son texte est sélectionné.
            champ = false
            DispatchQueue.main.async {
                champ = true
                DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
            }
        }
    }

    private var barre: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            TextField("Rechercher ou saisir une adresse", text: $r.texte)
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .foregroundStyle(.white)
                .focused($champ)
                .onSubmit { r.valider() }
            if r.etat == .page {
                HStack(spacing: 2) {
                    bouton("chevron.left", String(localized: "Page précédente")) { r.reculer() }.disabled(!r.peutReculer)
                    bouton("chevron.right", String(localized: "Page suivante")) { r.avancer() }.disabled(!r.peutAvancer)
                    bouton("safari", String(localized: "Ouvrir dans Safari (⌘ Entrée)")) { r.ouvrirDansSafari() }
                    bouton("xmark", String(localized: "Fermer (Échap)")) { r.fermer() }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else if r.aUnePage {
                Button { r.reprendre() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 11, weight: .semibold))
                        Text(r.titre.isEmpty ? String(localized: "Dernière page") : r.titre).font(.callout).lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Gris.moyen))
                    .frame(maxWidth: 190, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .help("Reprendre la dernière page (Entrée, champ vide)")
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, r.etat == .page ? 12 : 14)
        .overlay(alignment: .bottomLeading) {
            // Le chargement : un trait qui avance sous la barre.
            GeometryReader { g in
                Rectangle().fill(Color.accentColor)
                    .frame(width: g.size.width * r.progression, height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(r.charge && r.etat == .page ? 1 : 0)
                    .animation(Mouvement.bascule, value: r.progression)
            }
            .allowsHitTesting(false)
        }
    }

    private func bouton(_ symbole: String, _ aide: String, _ action: @escaping () -> Void) -> some View {
        BoutonRecherche(symbole: symbole, aide: aide, action: action)
    }
}

private struct BoutonRecherche: View {
    let symbole: String
    let aide: String
    let action: () -> Void
    @State private var survol = false
    @Environment(\.isEnabled) private var actif

    var body: some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(actif ? 0.8 : 0.25))
                .frame(width: 30, height: 30)
                .background(Circle().fill(survol && actif ? Gris.moyen : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { s in withAnimation(Mouvement.survol) { survol = s } }
        .help(aide)
    }
}

// MARK: - Réglages

/// Réglages > Raccourcis clavier : le raccourci de la recherche et son moteur.
struct SectionRecherche: View {
    @ObservedObject private var config = ConfigRecherche.commun
    @State private var ecoute = false

    var body: some View {
        Section {
            LabeledContent("Ouvrir et fermer la recherche") {
                HStack {
                    Button(ecoute ? String(localized: "Tape le raccourci…") : (config.touche == -1 ? String(localized: "Aucun") : config.libelle)) {
                        ecoute = true
                        config.ecouterRaccourci { ecoute = false }
                    }
                    Button("Effacer") { config.definirRaccourci(touche: -1, mods: 0, libelle: String(localized: "Aucun")) }
                        .disabled(config.touche == -1)
                }
            }
            if !config.refus.isEmpty {
                Text(config.refus).font(.caption).foregroundStyle(.red)
            }
            Picker("Moteur de recherche", selection: $config.moteur) {
                ForEach(MoteurRecherche.allCases) { Text(verbatim: $0.nom).tag($0) }
            }
        } header: { Text("Recherche sur le web") } footer: {
            Text("Une pilule descend de l'encoche : tape ta recherche ou une adresse, puis Entrée. Échap referme ; la page reste en mémoire pour la prochaine fois. ⌘ Entrée l'envoie dans Safari. Clique sur le raccourci, puis tape la nouvelle combinaison (avec Commande, Contrôle ou Option). Si rien ne se passe, la combinaison est déjà prise par macOS ou par une autre application : libère-la dans Réglages Système > Clavier > Raccourcis clavier (⌘ Espace : Spotlight), ou choisis-en une autre.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
