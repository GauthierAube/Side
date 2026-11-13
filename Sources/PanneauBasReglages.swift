// Les réglages du tiroir du bas : son coin actif, son raccourci clavier, son geste, sa fermeture, ses applications.
// Et les morceaux de la fenêtre Réglages qui parlent du tiroir (coins actifs, raccourci, volet « Tiroir du bas »).
import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

/// Un élément du coin multimédia : le lecteur Spotify maison, YouTube, ou n'importe quel site web.
struct MediaBas: Identifiable, Equatable {
    var id: String
    var nom: String
    var genre: String        // "spotify", "youtube" ou "web"
    var adresse: String
    var enTexte: [String: String] { ["id": id, "nom": nom, "genre": genre, "adresse": adresse] }
    init(id: String, nom: String, genre: String, adresse: String) { self.id = id; self.nom = nom; self.genre = genre; self.adresse = adresse }
    init?(_ d: [String: String]) {
        guard let id = d["id"], let nom = d["nom"], let genre = d["genre"] else { return nil }
        self.init(id: id, nom: nom, genre: genre, adresse: d["adresse"] ?? "")
    }
    static let spotify = MediaBas(id: "spotify", nom: "Spotify", genre: "spotify", adresse: "")
    static let youtube = MediaBas(id: "youtube", nom: "YouTube", genre: "youtube", adresse: "https://www.youtube.com/")
    /// Ce qu'on propose d'ajouter en un clic.
    static let proposes: [MediaBas] = [
        .spotify, .youtube,
        MediaBas(id: "youtube-music", nom: "YouTube Music", genre: "web", adresse: "https://music.youtube.com/"),
        MediaBas(id: "apple-music", nom: "Apple Music", genre: "web", adresse: "https://music.apple.com/"),
        MediaBas(id: "apple-podcasts", nom: "Apple Podcasts", genre: "web", adresse: "https://podcasts.apple.com/"),
        MediaBas(id: "deezer", nom: "Deezer", genre: "web", adresse: "https://www.deezer.com/"),
        MediaBas(id: "soundcloud", nom: "SoundCloud", genre: "web", adresse: "https://soundcloud.com/"),
        MediaBas(id: "twitch", nom: "Twitch", genre: "web", adresse: "https://www.twitch.tv/"),
        MediaBas(id: "radio-france", nom: "Radio France", genre: "web", adresse: "https://www.radiofrance.fr/"),
        MediaBas(id: "arte", nom: "Arte", genre: "web", adresse: "https://www.arte.tv/fr/"),
    ]
}

final class ConfigTiroir: ObservableObject {
    static let commun = ConfigTiroir()
    private let d = UserDefaults.standard

    /// Le coin de l'écran qui ouvre et referme le tiroir (aucun au départ).
    @Published var coin: Coin { didSet { d.set(coin.rawValue, forKey: "tiroirCoin") } }
    /// Raccourci clavier : -1 = aucun, sinon le code de la touche. Au départ : Contrôle + Option + Espace.
    @Published var touche: Int { didSet { d.set(touche, forKey: "tiroirTouche") } }
    @Published var mods: Int { didSet { d.set(mods, forKey: "tiroirMods") } }
    @Published var libelle: String { didSet { d.set(libelle, forKey: "tiroirLibelle") } }
    /// Quatre doigts vers le haut ouvrent le tiroir (quand le Finder de Side est fermé).
    @Published var quatreDoigts: Bool { didSet { d.set(quatreDoigts, forKey: "tiroirQuatreDoigts"); GestePanneauBas.actif = quatreDoigts } }
    @Published var fermerAuClic: Bool { didSet { d.set(fermerAuClic, forKey: "tiroirFermerAuClic") } }
    /// Le tiroir montre une application à la fois (les autres défilent au geste), ou toutes en bande.
    @Published var uneApp: Bool { didSet { d.set(uneApp, forKey: "tiroirUneApp"); GestePanneauBas.navigation = uneApp; PanneauBas.commun.majDisposition() } }
    /// Le fond flouté derrière les tuiles. Retiré au départ depuis le 13/11/2026 : les tuiles flottent seules, plus légères.
    @Published var fond: Bool { didSet { d.set(fond, forKey: "tiroirFond"); PanneauBas.commun.majFond() } }
    /// Couper les publicités dans la page YouTube du tiroir. Désactivé au départ : c'est contraire aux conditions de YouTube,
    /// chacun décide pour soi. Pris en compte au prochain lancement de Side.
    @Published var couperPubs: Bool { didSet { d.set(couperPubs, forKey: "tiroirCouperPubs") } }
    /// Masquer les Shorts de YouTube (rangées de Shorts, onglet, vidéos courtes). Appliqué tout de suite, sans recharger.
    @Published var masquerShorts: Bool { didSet { d.set(masquerShorts, forKey: "tiroirMasquerShorts"); PanneauBas.commun.appliquerShorts() } }
    /// Les éléments du coin multimédia, dans l'ordre. Au départ : Spotify et YouTube. La liste peut être vide.
    @Published var medias: [MediaBas] {
        didSet { d.set(medias.map { $0.enTexte }, forKey: "tiroirMedias"); PanneauBas.commun.médiasChangés() }
    }

    private init() {
        coin = d.string(forKey: "tiroirCoin").flatMap(Coin.init) ?? .aucun
        touche = d.object(forKey: "tiroirTouche") as? Int ?? kVK_Space
        mods = d.object(forKey: "tiroirMods") as? Int ?? (controlKey | optionKey)
        libelle = d.string(forKey: "tiroirLibelle") ?? String(localized: "⌃⌥Espace")
        quatreDoigts = d.object(forKey: "tiroirQuatreDoigts") as? Bool ?? true
        fermerAuClic = d.object(forKey: "tiroirFermerAuClic") as? Bool ?? true
        let une = d.object(forKey: "tiroirUneApp") as? Bool ?? true
        uneApp = une
        GestePanneauBas.navigation = une
        fond = d.object(forKey: "tiroirFond") as? Bool ?? false
        couperPubs = d.bool(forKey: "tiroirCouperPubs")
        masquerShorts = d.bool(forKey: "tiroirMasquerShorts")
        // Au départ : YouTube, qui marche sans rien installer, et Spotify seulement si l'application est sur ce Mac.
        let spotifyInstalle = FileManager.default.fileExists(atPath: "/Applications/Spotify.app")
        medias = (d.array(forKey: "tiroirMedias") as? [[String: String]])?.compactMap { MediaBas($0) }
            ?? (spotifyInstalle ? [.spotify, .youtube] : [.youtube])
        GestePanneauBas.actif = quatreDoigts
    }

    private var ecouteur: Any?

    // Le tiroir se règle sur le Finder de Side : il arrive du bord opposé, et son geste à quatre doigts va dans l'autre sens.
    /// Vrai : le tiroir descend du haut de l'écran (le Finder vient du bas). Faux : il monte du bas.
    static var enHaut: Bool { Config.shared.bord == .bas }
    /// Le geste du tiroir, en toutes lettres.
    static var sensGeste: String { enHaut ? String(localized: "vers le bas") : String(localized: "vers le haut") }
    /// Le geste du tiroir n'est libre que si le Finder s'ouvre avec quatre doigts dans l'autre sens.
    /// Choisir d'où arrive le Finder règle tout le reste : le tiroir prend le bord opposé, et les gestes à quatre doigts suivent
    /// (un panneau qui vient du bas s'ouvre en glissant vers le haut, et inversement).
    static func reglerBord(_ b: Bord) {
        let c = Config.shared
        if c.bord != b { c.bord = b }
        if b == .bas, c.sensDoigts == "bas" { c.sensDoigts = "haut" }
        if b == .haut, c.sensDoigts == "haut" { c.sensDoigts = "bas" }
    }
    static var gestePossible: Bool { Config.shared.quatreDoigts && Config.shared.sensDoigts == (enHaut ? "haut" : "bas") }

    func definirRaccourci(touche: Int, mods: Int, libelle: String) {
        self.touche = touche
        self.mods = mods
        self.libelle = libelle
        PanneauBas.commun.installerRaccourci()
    }

    /// Attend la prochaine combinaison de touches tapée dans la fenêtre Réglages (Échap annule).
    func ecouterRaccourci(fin: @escaping () -> Void) {
        PanneauBas.commun.suspendreRaccourci()
        if let e = ecouteur { NSEvent.removeMonitor(e) }
        ecouteur = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self else { return ev }
            let f = ev.modifierFlags
            let annule = ev.keyCode == 53
            guard annule || !f.intersection([.command, .control, .option]).isEmpty else { NSSound.beep(); return nil }
            if let e = self.ecouteur { NSEvent.removeMonitor(e); self.ecouteur = nil }
            if annule { PanneauBas.commun.installerRaccourci(); fin(); return nil }
            var mods = 0, texte = ""
            if f.contains(.control) { mods |= controlKey; texte += "⌃" }
            if f.contains(.option) { mods |= optionKey; texte += "⌥" }
            if f.contains(.shift) { mods |= shiftKey; texte += "⇧" }
            if f.contains(.command) { mods |= cmdKey; texte += "⌘" }
            texte += ev.keyCode == UInt16(kVK_Space) ? String(localized: "Espace") : (ev.charactersIgnoringModifiers ?? "?").uppercased()
            self.definirRaccourci(touche: Int(ev.keyCode), mods: mods, libelle: texte)
            fin()
            return nil
        }
    }
}

// MARK: - Coins actifs (comme la feuille « Coins actifs » de macOS : un écran, un menu par coin)

/// La grille de Square dans un coin actif de Side (quand Square est installé). Side surveille le coin et demande la grille à Square ;
/// Square, voyant ce réglage, grise le sien et renvoie ici.
final class ConfigSquare: ObservableObject {
    static let commun = ConfigSquare()
    static let bundle = "com.gauthieraube.square"
    /// La grille fait partie de l'app depuis la fusion : elle est toujours là.
    static var installe: Bool { true }
    private let d = UserDefaults.standard

    @Published var coin: Coin { didSet { d.set(coin.rawValue, forKey: "coinSquare") } }

    private init() {
        if let r = d.string(forKey: "coinSquare"), let c = Coin(rawValue: r) {
            coin = c
        } else {
            // La première fois : on reprend le coin réglé dans Square (en haut à droite au départ), s'il est libre ici.
            coin = .aucun
            guard Self.installe else { return }
            let code = (CFPreferencesCopyAppValue("coinGrille" as CFString, Self.bundle as CFString) as? String) ?? "hd"
            let c: Coin = ["hd": .hautDroite, "hg": .hautGauche, "bd": .basDroite, "bg": .basGauche][code] ?? .aucun
            if c != .aucun, Config.shared.coin != c, ConfigTiroir.commun.coin != c, ConfigPresse.commun.coin != c { coin = c }
            d.set(coin.rawValue, forKey: "coinSquare")
        }
    }

    private var arme = true
    private var debut: Date?

    /// Appelé plusieurs fois par seconde par Side, avec la place du pointeur.
    func surveillerCoin(_ p: NSPoint, _ e: NSScreen, taille: CGFloat) {
        guard coin != .aucun else { return }
        func dans(_ marge: CGFloat) -> Bool {
            let t = taille + marge, f = e.frame
            let gauche = p.x <= f.minX + t, droite = p.x >= f.maxX - t, haut = p.y >= f.maxY - t, bas = p.y <= f.minY + t
            switch coin {
            case .aucun: return false
            case .hautGauche: return haut && gauche
            case .hautDroite: return haut && droite
            case .basGauche: return bas && gauche
            case .basDroite: return bas && droite
            }
        }
        // Comme dans Square : il faut ressortir du coin avant de pouvoir le déclencher de nouveau.
        if !dans(40) { arme = true; debut = nil; return }
        guard dans(0) else { debut = nil; return }
        guard arme, NSEvent.pressedMouseButtons == 0, !CaptureEcran.enCours else { return }
        if debut == nil { debut = Date() }
        guard Date().timeIntervalSince(debut!) >= 0.05 else { return }
        arme = false
        debut = nil
        Programme.appli.grilleParLeCoin()
    }
}

struct CoinsActifsView: View {
    @ObservedObject var config = Config.shared
    @ObservedObject var tiroir = ConfigTiroir.commun
    @ObservedObject var presse = ConfigPresse.commun
    @ObservedObject var square = ConfigSquare.commun

    private func choix(_ c: Coin) -> Binding<String> {
        Binding(get: { config.coin == c ? "finder" : (tiroir.coin == c ? "tiroir" : (presse.coin == c ? "presse" : (square.coin == c ? "square" : ""))) },
                set: { v in
                    // Un coin ne fait qu'une chose, et le Finder, le tiroir et le presse-papiers n'ont qu'un coin chacun.
                    if config.coin == c { config.coin = .aucun }
                    if tiroir.coin == c { tiroir.coin = .aucun }
                    if presse.coin == c { presse.coin = .aucun }
                    if square.coin == c { square.coin = .aucun }
                    switch v {
                    case "finder": config.coin = c
                    case "tiroir": tiroir.coin = c
                    case "presse": presse.coin = c
                    case "square": square.coin = c
                    default: break
                    }
                })
    }

    private func menu(_ c: Coin) -> some View {
        Picker("", selection: choix(c)) {
            Text("–").tag("")
            Label("Finder", systemImage: "folder.fill").tag("finder")
            Label("Tiroir", systemImage: "rectangle.bottomthird.inset.filled").tag("tiroir")
            Label("Presse-papiers", systemImage: "doc.on.clipboard.fill").tag("presse")
            if true {
                Label("Grille des applications", systemImage: "square.grid.2x2.fill").tag("square")
            }
        }
        .labelsHidden()
        .frame(width: 150)
        .accessibilityLabel(c.titre)
    }

    private func couleur(_ c: Coin) -> Color {
        if config.coin == c { return .blue }
        if tiroir.coin == c { return .pink }
        if presse.coin == c { return .yellow }
        if square.coin == c { return .green }
        return Color.white.opacity(0.35)
    }

    private var ecran: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.purple.opacity(0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
            VStack {
                HStack { Circle().fill(couleur(.hautGauche)).frame(width: 12, height: 12); Spacer()
                         Circle().fill(couleur(.hautDroite)).frame(width: 12, height: 12) }
                Spacer()
                HStack { Circle().fill(couleur(.basGauche)).frame(width: 12, height: 12); Spacer()
                         Circle().fill(couleur(.basDroite)).frame(width: 12, height: 12) }
            }
            .padding(7)
        }
        .frame(width: 190, height: 118)
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 62) { menu(.hautGauche); menu(.basGauche) }
            ecran
            VStack(spacing: 62) { menu(.hautDroite); menu(.basDroite) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

// MARK: - Largeur du tiroir

/// La largeur du tiroir, en part de l'écran : la même que celle obtenue en tirant un de ses côtés (il reste centré).
struct LargeurTiroirLigne: View {
    @AppStorage("tiroirLargeur") private var largeur: Double = 1

    var body: some View {
        LabeledContent("Largeur du tiroir") {
            HStack {
                Slider(value: Binding(get: { largeur <= 0 ? 1 : largeur }, set: { largeur = $0 }), in: 0.3...1)
                    .frame(width: 190)
                Text(verbatim: "\(Int(((largeur <= 0 ? 1 : largeur) * 100).rounded())) %").monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
            }
        }
        .help("Se règle aussi en tirant le bord gauche ou droit du tiroir ouvert.")
    }
}

// MARK: - Raccourci clavier du tiroir

struct RaccourciTiroirLigne: View {
    @ObservedObject var tiroir = ConfigTiroir.commun
    @State private var ecoute = false

    var body: some View {
        LabeledContent("Ouvrir et fermer le tiroir") {
            HStack {
                Button(ecoute ? String(localized: "Tape le raccourci…") : tiroir.libelle) {
                    ecoute = true
                    tiroir.ecouterRaccourci { ecoute = false }
                }
                Button("Effacer") { tiroir.definirRaccourci(touche: -1, mods: 0, libelle: String(localized: "Aucun")) }
                    .disabled(tiroir.touche == -1)
            }
        }
    }
}

// MARK: - Les trois volets du tiroir : ouverture et fermeture, coin multimédia, applications

struct SectionsTiroir: View {
    enum Partie { case ouverture, multimedia, applications }
    let partie: Partie
    @ObservedObject var tiroir = ConfigTiroir.commun
    @ObservedObject var config = Config.shared
    @State private var tuiles = PanneauBas.commun.tuiles
    @State private var spotify = SpotifyCompte.commun.connecte
    @State private var nomSite = ""
    @State private var adresseSite = ""

    private func note(_ texte: String) -> some View { Text(texte).font(.caption).foregroundStyle(.secondary) }

    var body: some View {
        switch partie {
        case .ouverture:
            Section {
                Picker("Le tiroir arrive", selection: Binding(
                    get: { ConfigTiroir.enHaut },
                    set: { haut in
                        // Le tiroir et le Finder ne partagent jamais un bord : placer l'un déplace l'autre.
                        if haut { ConfigTiroir.reglerBord(.bas) } else if config.bord == .bas { ConfigTiroir.reglerBord(.haut) }
                    })) {
                    Text("Du bas").tag(false)
                    Text("Du haut").tag(true)
                }
                .pickerStyle(.segmented)
            } footer: { note(String(localized: "Attention : si le tiroir arrive du haut, le Finder arrivera du bas.")) }
            Section {
                Toggle("Fermer d'un clic en dehors", isOn: $tiroir.fermerAuClic)
                Toggle("Une application à la fois", isOn: $tiroir.uneApp)
                    .help("Le tiroir montre une seule application ; prolonge le geste à quatre doigts pour passer aux autres.")
                LargeurTiroirLigne()
                Toggle("Bouton jaune : ranger l'application dans le tiroir", isOn: Binding(get: { BoutonVert.jauneVersTiroir }, set: { BoutonVert.jauneVersTiroir = $0 }))
                    .help("Option + clic sur le bouton jaune : l'application se range dans le Dock, comme d'habitude.")
                Toggle("Fond derrière les tuiles", isOn: $tiroir.fond)
            }
        case .multimedia:
            Section {
                if tiroir.medias.isEmpty { Text("Aucun lecteur : cette partie n'apparaît pas dans le tiroir.").foregroundStyle(.secondary) }
                ForEach(tiroir.medias) { m in
                    HStack {
                        Text(m.nom)
                        if m.genre == "web" { Text(m.adresse).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        Button("Retirer") { tiroir.medias.removeAll { $0.id == m.id } }
                    }
                }
                Menu("Ajouter…") {
                    ForEach(MediaBas.proposes.filter { p in !tiroir.medias.contains { $0.id == p.id } }) { p in
                        Button(p.nom) { tiroir.medias.append(p) }
                    }
                }
                .frame(width: 130)
            } header: { Text("Lecteurs affichés") }
            Section {
                TextField("Nom", text: $nomSite, prompt: Text("Mon site"))
                TextField("Adresse", text: $adresseSite, prompt: Text("https://…"))
                Button("Ajouter ce site") {
                    var adresse = adresseSite.trimmingCharacters(in: .whitespaces)
                    if !adresse.lowercased().hasPrefix("http") { adresse = "https://" + adresse }
                    let nom = nomSite.trimmingCharacters(in: .whitespaces)
                    guard URL(string: adresse)?.host != nil, !nom.isEmpty else { NSSound.beep(); return }
                    tiroir.medias.append(MediaBas(id: "site-" + UUID().uuidString.prefix(8).lowercased(), nom: nom, genre: "web", adresse: adresse))
                    nomSite = ""; adresseSite = ""
                }
                .disabled(nomSite.isEmpty || adresseSite.isEmpty)
            } header: { Text("Un autre site web") } footer: {
                note(String(localized: "Une application du Mac se range plutôt dans « Applications »."))
            }
            if tiroir.medias.contains(where: { $0.genre == "youtube" }) {
                Section {
                    Toggle("Masquer les Shorts", isOn: $tiroir.masquerShorts)
                    Toggle("Couper les publicités", isOn: $tiroir.couperPubs)
                } header: { Text("YouTube") } footer: {
                    note(String(localized: "Masquer les Shorts retire leurs rangées, leur onglet et les vidéos courtes, tout de suite. Couper les publicités est contraire aux conditions d'utilisation de YouTube : à activer en connaissance de cause, pris en compte au prochain lancement de Side."))
                }
            }
            if tiroir.medias.contains(where: { $0.genre == "spotify" }) {
                Section {
                    LabeledContent("Spotify") {
                        HStack {
                            Text(spotify ? String(localized: "Connecté") : String(localized: "Non connecté")).foregroundStyle(.secondary)
                            Button("Déconnecter") { SpotifyCompte.commun.deconnecter(); spotify = false }.disabled(!spotify)
                        }
                    }
                } header: { Text("Compte") }
            }
        case .applications:
            Section {
                if tuiles.isEmpty { Text("Aucune application.").foregroundStyle(.secondary) }
                ForEach(tuiles, id: \.nom) { t in
                    HStack(spacing: 9) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: t.chemin)).resizable().frame(width: 22, height: 22)
                        Text(t.nom)
                        Spacer()
                        Button("Retirer") {
                            PanneauBas.commun.retirerTuile(nom: t.nom)
                            tuiles = PanneauBas.commun.tuiles
                        }
                    }
                }
                Button("Ajouter une application…") {
                    let p = NSOpenPanel()
                    p.directoryURL = URL(fileURLWithPath: "/Applications")
                    p.allowedContentTypes = [.application]
                    p.allowsMultipleSelection = false
                    if Devant.panneau(p) == .OK, let u = p.url {
                        PanneauBas.commun.ajouter(u)
                        tuiles = PanneauBas.commun.tuiles
                    }
                }
            } footer: { note(String(localized: "Ces applications restent à leur taille : elles ne remplissent jamais l'écran toutes seules.")) }
        }
    }
}

// MARK: - Le mot d'accueil du tiroir, à sa première ouverture

final class BienvenueTiroirBas: NSView {
    var auCompris: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        shadow = NSShadow()
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -5)

        let titre = NSTextField(labelWithString: String(localized: "Bienvenue dans le tiroir"))
        titre.font = .systemFont(ofSize: 17, weight: .semibold)
        // Les façons de l'ouvrir qui sont réglées en ce moment.
        let t = ConfigTiroir.commun
        var facons: [String] = []
        if t.touche != -1 { facons.append(t.libelle) }
        if t.quatreDoigts && ConfigTiroir.gestePossible { facons.append(String(localized: "quatre doigts \(ConfigTiroir.sensGeste)")) }
        if t.coin != .aucun { facons.append(String(localized: "le coin \(t.coin.titre.lowercased())")) }
        var lignes: [NSView] = [titre,
            ligne("keyboard", facons.isEmpty ? String(localized: "Choisis comment l'ouvrir dans les réglages.")
                                             : String(localized: "Pour l'ouvrir et le fermer : \(facons.joined(separator: String(localized: ", ou "))).")),
            ligne("play.rectangle.fill", String(localized: "À gauche, la musique et la vidéo : YouTube, Spotify ou le site de ton choix.")),
            ligne("plus.circle.fill", String(localized: "La case « + » range une application dans le tiroir : elle y reste, à portée de main.")),
            ligne("gearshape.fill", String(localized: "La roue dentée, sous la case « + », ouvre les réglages.")),
        ]
        // Sans l'autorisation Accessibilité, Side ne peut pas déplacer la fenêtre d'une autre application.
        if !AXIsProcessTrusted() {
            lignes.append(ligne("hand.raised.fill", String(localized: "Pour ranger des applications, Side a besoin de l'autorisation Accessibilité.")))
            let acces = BoutonBas(title: String(localized: "Ouvrir les réglages d'accessibilité"), target: self, action: #selector(ouvrirAccessibilite))
            acces.bezelStyle = .rounded
            lignes.append(acces)
        }
        let compris = BoutonBas(title: String(localized: "Compris"), target: self, action: #selector(compris))
        compris.bezelStyle = .rounded
        compris.keyEquivalent = "\r"
        lignes.append(compris)
        let pile = NSStackView(views: lignes)
        pile.orientation = .vertical
        pile.alignment = .leading
        pile.spacing = 10
        pile.setCustomSpacing(14, after: titre)
        pile.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pile)
        NSLayoutConstraint.activate([
            pile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), pile.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            pile.topAnchor.constraint(equalTo: topAnchor, constant: 18), pile.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            compris.trailingAnchor.constraint(equalTo: pile.trailingAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func ligne(_ symbole: String, _ texte: String) -> NSView {
        let image = NSImageView(image: NSImage(systemSymbolName: symbole, accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = .controlAccentColor
        image.translatesAutoresizingMaskIntoConstraints = false
        image.widthAnchor.constraint(equalToConstant: 20).isActive = true
        let t = NSTextField(wrappingLabelWithString: texte)
        t.font = .systemFont(ofSize: 13)
        t.preferredMaxLayoutWidth = 370
        let rangee = NSStackView(views: [image, t])
        rangee.spacing = 8
        rangee.alignment = .firstBaseline
        return rangee
    }

    @objc private func compris() { auCompris?() }
    @objc private func ouvrirAccessibilite() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(u) }
    }
}

// MARK: - Les applications compagnes (Réglages > Général)

/// Side et Mulot sont faits pour aller ensemble : Side signale Mulot, avec l'adresse où l'installer.
/// (Square, l'ancienne app du plein écran, fait partie de Side depuis le 13/11/2026.)
struct SectionCompagnes: View {
    private struct Compagne: Identifiable {
        let id: String, nom: String, role: String, adresse: String
        var installee: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil }
    }
    private let compagnes = [
        Compagne(id: "app.mulot", nom: "Mulot", role: String(localized: "Les boutons et les gestes de la souris MX Master, sans le logiciel de Logitech."),
                 adresse: "https://github.com/GauthierAube/Mulot"),
    ]

    var body: some View {
        Section {
            ForEach(compagnes) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.nom)
                        Text(c.role).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if c.installee {
                        Text("Installée").foregroundStyle(.secondary)
                    } else if let u = URL(string: c.adresse) {
                        Link("Installer depuis GitHub", destination: u)
                    }
                }
            }
        } header: { Text("Application compagne") } footer: {
            Text("Side et Mulot sont deux petites applications gratuites, faites pour aller ensemble.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
