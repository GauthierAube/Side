// Le lecteur Spotify du panneau du bas, présenté comme l'application d'un téléphone : Accueil, Lecture, Recherche, Bibliothèque.
// La lecture passe par l'application Spotify du Mac (AppleScript). L'accueil, la recherche et la bibliothèque passent
// par le compte Spotify, auquel on se connecte une fois (accès développeur Spotify, sans mot de passe stocké ici).
import AppKit
import CryptoKit
import Network
import Security

/// Une ligne à afficher : un titre, une playlist, un album, un artiste, un podcast.
struct ElementSpotify {
    var titre: String
    var sousTitre: String
    var image: String
    var uri: String
    var contexte: String? = nil      // la playlist ou l'album où lire ce titre, pour que la suite s'enchaîne
    var rond = false                 // un artiste : image ronde
}

// MARK: - Compte Spotify

final class SpotifyCompte {
    static let commun = SpotifyCompte()
    static let redirection = "http://127.0.0.1:8765/callback"
    private let port: UInt16 = 8765
    private let portees = "user-library-read playlist-read-private playlist-read-collaborative user-read-recently-played user-top-read"
    private let service = "com.gauthieraube.side.spotify"

    /// L'identifiant de l'accès développeur (« Client ID »). Ce n'est pas un secret.
    var identifiant: String {
        get { UserDefaults.standard.string(forKey: "spotifyIdentifiantClient") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "spotifyIdentifiantClient") }
    }
    private var jeton: String?
    private var expire = Date.distantPast
    private var verificateur = ""
    private var etat = ""
    private var ecoute: NWListener?
    private var finConnexion: ((String?) -> Void)?

    var connecte: Bool { lireTrousseau() != nil }

    // Le jeton de renouvellement est rangé dans le trousseau du Mac, pas dans un fichier.
    private func lireTrousseau() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: "renouvellement", kSecReturnData as String: true]
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func ecrireTrousseau(_ valeur: String?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: "renouvellement"]
        SecItemDelete(q as CFDictionary)
        guard let valeur else { return }
        var a = q
        a[kSecValueData as String] = Data(valeur.utf8)
        SecItemAdd(a as CFDictionary, nil)
    }

    private func url64(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func hasard(_ n: Int) -> String {
        var octets = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &octets)
        return url64(Data(octets))
    }

    private func formulaire(_ champs: [String: String]) -> Data {
        var permis = CharacterSet.alphanumerics
        permis.insert(charactersIn: "-._~")
        return Data(champs.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: permis) ?? "")" }
            .joined(separator: "&").utf8)
    }

    /// Ouvre la page d'autorisation de Spotify dans le navigateur. `fin` reçoit nil si tout s'est bien passé, sinon l'explication.
    func connecter(_ fin: @escaping (String?) -> Void) {
        guard !identifiant.isEmpty else { fin(String(localized: "Collez d'abord l'identifiant (Client ID).")); return }
        verificateur = hasard(48)
        etat = hasard(12)
        finConnexion = fin
        guard demarrerEcoute() else { fin(String(localized: "Le port 8765 du Mac est déjà pris. Fermez l'application qui l'utilise et réessayez.")); return }
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: identifiant), URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyCompte.redirection),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: url64(Data(SHA256.hash(data: Data(verificateur.utf8))))),
            URLQueryItem(name: "scope", value: portees), URLQueryItem(name: "state", value: etat),
        ]
        NSWorkspace.shared.open(c.url!)
    }

    /// Attend, sur ce Mac uniquement, le retour du navigateur après l'autorisation.
    private func demarrerEcoute() -> Bool {
        ecoute?.cancel()
        let reglages = NWParameters.tcp
        reglages.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        reglages.allowLocalEndpointReuse = true
        guard let e = try? NWListener(using: reglages) else { return false }
        e.newConnectionHandler = { [weak self] lien in
            lien.start(queue: .main)
            lien.receive(minimumIncompleteLength: 1, maximumLength: 8192) { donnees, _, _, _ in
                let ligne = donnees.flatMap { String(data: $0, encoding: .utf8) }?.components(separatedBy: "\r\n").first ?? ""
                let chemin = ligne.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let champs = URLComponents(string: "http://127.0.0.1" + chemin)?.queryItems ?? []
                let code = champs.first { $0.name == "code" }?.value
                let bonEtat = champs.first { $0.name == "state" }?.value == self?.etat
                let refus = champs.first { $0.name == "error" }?.value
                let message = (code != nil && bonEtat) ? String(localized: "Connexion réussie. Vous pouvez fermer cette page et revenir au panneau.")
                                                       : String(localized: "La connexion n'a pas abouti. Vous pouvez fermer cette page et réessayer depuis le panneau.")
                let page = "<html><head><meta charset=\"utf-8\"></head><body style=\"font: 18px -apple-system; padding: 48px\">\(message)</body></html>"
                let reponse = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n" + page
                lien.send(content: Data(reponse.utf8), completion: .contentProcessed { _ in lien.cancel() })
                guard chemin.hasPrefix("/callback") else { return }
                self?.ecoute?.cancel()
                self?.ecoute = nil
                if let code, bonEtat { self?.echanger(code) }
                else { self?.terminer(refus == "access_denied" ? String(localized: "Vous avez refusé l'autorisation dans Spotify.") : String(localized: "Spotify n'a pas renvoyé d'autorisation.")) }
            }
        }
        e.start(queue: .main)
        ecoute = e
        return true
    }

    private func terminer(_ erreur: String?) {
        let fin = finConnexion
        finConnexion = nil
        DispatchQueue.main.async { fin?(erreur) }
    }

    private func jetons(_ champs: [String: String], _ fin: @escaping (String?) -> Void) {
        var r = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = formulaire(champs)
        URLSession.shared.dataTask(with: r) { [weak self] d, _, _ in
            let json = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            DispatchQueue.main.async {
                guard let self, let acces = json?["access_token"] as? String else {
                    fin((json?["error_description"] as? String) ?? String(localized: "Spotify n'a pas répondu."))
                    return
                }
                self.jeton = acces
                self.expire = Date().addingTimeInterval(((json?["expires_in"] as? Double) ?? 3600) - 60)
                if let suite = json?["refresh_token"] as? String { self.ecrireTrousseau(suite) }
                fin(nil)
            }
        }.resume()
    }

    private func echanger(_ code: String) {
        jetons(["grant_type": "authorization_code", "code": code, "redirect_uri": SpotifyCompte.redirection,
                "client_id": identifiant, "code_verifier": verificateur]) { [weak self] erreur in self?.terminer(erreur) }
    }

    private func renouveler(_ fin: @escaping (String?) -> Void) {
        guard let suite = lireTrousseau() else { fin(String(localized: "Le compte Spotify n'est pas connecté.")); return }
        jetons(["grant_type": "refresh_token", "refresh_token": suite, "client_id": identifiant]) { [weak self] erreur in
            // Autorisation retirée ou expirée : il faudra se reconnecter.
            if erreur != nil { self?.ecrireTrousseau(nil) }
            fin(erreur)
        }
    }

    func deconnecter() {
        ecrireTrousseau(nil)
        jeton = nil
        expire = .distantPast
    }

    /// Interroge Spotify (lecture seule). Exemple : appel("me/playlists?limit=50").
    func appel(_ chemin: String, _ fin: @escaping ([String: Any]?, String?) -> Void) {
        guard let jeton, Date() < expire else {
            renouveler { [weak self] erreur in
                if let erreur { fin(nil, erreur) } else { self?.appel(chemin, fin) }
            }
            return
        }
        var r = URLRequest(url: URL(string: "https://api.spotify.com/v1/" + chemin)!)
        r.setValue("Bearer " + jeton, forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r) { d, reponse, _ in
            let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
            let json = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            DispatchQueue.main.async {
                if code == 200 { fin(json, nil); return }
                let detail = ((json?["error"] as? [String: Any])?["message"] as? String) ?? String(localized: "pas de réponse")
                journalBas("Spotify : %@ → %d %@", chemin.components(separatedBy: "?").first ?? chemin, code, detail)
                fin(nil, code == 403 ? String(localized: "Spotify refuse cet accès (\(detail)).") : String(localized: "Spotify ne répond pas (\(detail))."))
            }
        }.resume()
    }

    // MARK: Lecture des réponses de Spotify

    private static func image(_ o: [String: Any]) -> String {
        (((o["images"] as? [[String: Any]]) ?? []).first?["url"] as? String) ?? ""
    }

    static func titre(_ t: [String: Any], contexte: String? = nil) -> ElementSpotify? {
        guard let nom = t["name"] as? String, let uri = t["uri"] as? String else { return nil }
        let artistes = ((t["artists"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
        let album = t["album"] as? [String: Any]
        return ElementSpotify(titre: nom, sousTitre: artistes, image: album.map(image) ?? image(t), uri: uri,
                              contexte: contexte ?? (album?["uri"] as? String))
    }

    static func recueil(_ o: [String: Any], genre: String) -> ElementSpotify? {
        guard let nom = o["name"] as? String, let uri = o["uri"] as? String else { return nil }
        var sous = genre
        if let p = (o["owner"] as? [String: Any])?["display_name"] as? String { sous = "\(genre) · \(p)" }
        if let a = ((o["artists"] as? [[String: Any]]) ?? []).first?["name"] as? String { sous = "\(genre) · \(a)" }
        if let e = o["publisher"] as? String { sous = "\(genre) · \(e)" }
        return ElementSpotify(titre: nom, sousTitre: sous, image: image(o), uri: uri, rond: genre == String(localized: "Artiste"))
    }

    static func liste(_ json: [String: Any]?, _ cle: String? = nil) -> [[String: Any]] {
        let racine = cle.flatMap { json?[$0] as? [String: Any] } ?? json
        return ((racine?["items"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
    }
}

// MARK: - Listes

/// Vue dont l'origine est en haut, pour empiler les lignes d'une liste de haut en bas.
final class PileRenverseeBas: NSView { override var isFlipped: Bool { true } }

/// Une ligne : image, titre, sous-titre. Un clic la lance.
final class LigneSpotifyBas: NSView {
    var auClic: (() -> Void)?
    private let image = NSImageView()
    private static let cache = NSCache<NSString, NSImage>()

    init(_ e: ElementSpotify) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        image.wantsLayer = true
        image.layer?.cornerRadius = e.rond ? 24 : 4
        image.layer?.masksToBounds = true
        image.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        image.imageScaling = .scaleProportionallyUpOrDown
        let titre = NSTextField(labelWithString: e.titre)
        titre.font = .systemFont(ofSize: 14, weight: .medium)
        titre.textColor = .labelColor
        titre.lineBreakMode = .byTruncatingTail
        let sous = NSTextField(labelWithString: e.sousTitre)
        sous.font = .systemFont(ofSize: 12)
        sous.textColor = NSColor(white: 0.7, alpha: 1)
        sous.lineBreakMode = .byTruncatingTail
        let textes = NSStackView(views: e.sousTitre.isEmpty ? [titre] : [titre, sous])
        textes.orientation = .vertical
        textes.alignment = .leading
        textes.spacing = 2
        for v in [titre, sous] { v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
        let rangee = NSStackView(views: [image, textes])
        rangee.spacing = 12
        rangee.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rangee)
        NSLayoutConstraint.activate([
            rangee.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rangee.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rangee.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 48), image.heightAnchor.constraint(equalToConstant: 48),
        ])
        if let img = LigneSpotifyBas.cache.object(forKey: e.image as NSString) {
            image.image = img
        } else if let u = URL(string: e.image) {
            URLSession.shared.dataTask(with: u) { [weak self] d, _, _ in
                guard let d, let img = NSImage(data: d) else { return }
                LigneSpotifyBas.cache.setObject(img, forKey: e.image as NSString)
                DispatchQueue.main.async { self?.image.image = img }
            }.resume()
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // La ligne s'éclaire seulement pendant qu'on appuie dessus.
    override func mouseDown(with event: NSEvent) { layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor }
    override func mouseUp(with event: NSEvent) {
        layer?.backgroundColor = nil
        if bounds.contains(convert(event.locationInWindow, from: nil)) { auClic?() }
    }
}

/// Une liste défilante, découpée en rubriques.
final class ListeSpotifyBas: NSView {
    var auChoix: ((ElementSpotify) -> Void)?
    private let defilant = NSScrollView()
    private let pile = PileRenverseeBas()
    // Les lignes remplissent la largeur disponible : une colonne quand c'est étroit, deux ou trois quand il y a la place.
    private var rubriques: [(String, [ElementSpotify])] = []
    private var message: String?
    private var largeurPosee: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        defilant.drawsBackground = false
        defilant.hasVerticalScroller = true
        defilant.scrollerStyle = .overlay
        defilant.documentView = pile
        defilant.translatesAutoresizingMaskIntoConstraints = false
        addSubview(defilant)
        NSLayoutConstraint.activate([
            defilant.leadingAnchor.constraint(equalTo: leadingAnchor), defilant.trailingAnchor.constraint(equalTo: trailingAnchor),
            defilant.topAnchor.constraint(equalTo: topAnchor), defilant.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Affiche un simple message (chargement, erreur, liste vide).
    func dire(_ message: String) { montrer([], message: message) }

    func montrer(_ rubriques: [(String, [ElementSpotify])], message: String? = nil) {
        self.rubriques = rubriques
        self.message = message
        poser()
        defilant.contentView.scroll(to: .zero)
    }

    override func layout() {
        super.layout()
        if abs(bounds.width - largeurPosee) > 1 { poser() }      // la tuile a changé de largeur : on redistribue les colonnes
    }

    private func poser() {
        let largeur = max(240, bounds.width)
        largeurPosee = bounds.width
        let colonnes = max(1, Int(largeur / 300))
        let pas = (largeur / CGFloat(colonnes)).rounded(.down)
        pile.subviews.forEach { $0.removeFromSuperview() }
        var y: CGFloat = 0
        if let message {
            let t = NSTextField(wrappingLabelWithString: message)
            t.font = .systemFont(ofSize: 12)
            t.textColor = .secondaryLabelColor
            t.alignment = .center
            t.frame = NSRect(x: 12, y: 24, width: largeur - 24, height: 80)
            pile.addSubview(t)
            y = 110
        }
        for (nom, elements) in rubriques where !elements.isEmpty {
            if !nom.isEmpty {
                let t = NSTextField(labelWithString: nom)
                t.font = .systemFont(ofSize: 17, weight: .bold)
                t.textColor = .labelColor
                t.frame = NSRect(x: 8, y: y + 12, width: largeur - 16, height: 22)
                pile.addSubview(t)
                y += 42
            }
            for (i, e) in elements.enumerated() {
                let ligne = LigneSpotifyBas(e)
                ligne.frame = NSRect(x: CGFloat(i % colonnes) * pas, y: y + CGFloat(i / colonnes) * 62, width: pas - 4, height: 60)
                ligne.auClic = { [weak self] in self?.auChoix?(e) }
                pile.addSubview(ligne)
            }
            y += CGFloat((elements.count + colonnes - 1) / colonnes) * 62
        }
        pile.frame = NSRect(x: 0, y: 0, width: largeur, height: max(y + 6, 1))
    }
}

/// Une rangée de pastilles (Playlists, Albums…) : celle qui est choisie est en vert.
final class PastillesBas: NSView {
    var auChoix: ((Int) -> Void)?
    private(set) var choisie = 0
    private var boutons: [BoutonBas] = []
    private let vert = NSColor(red: 0.11, green: 0.73, blue: 0.33, alpha: 1)

    init(_ noms: [String]) {
        super.init(frame: .zero)
        boutons = noms.enumerated().map { i, nom in
            let b = BoutonBas(title: nom, target: self, action: #selector(clic(_:)))
            b.isBordered = false
            b.tag = i
            b.wantsLayer = true
            b.layer?.cornerRadius = 14
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 28).isActive = true
            b.widthAnchor.constraint(equalToConstant: nom.size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width + 17).isActive = true
            return b
        }
        let rangee = NSStackView(views: boutons)
        rangee.spacing = 5
        rangee.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rangee)
        NSLayoutConstraint.activate([
            rangee.leadingAnchor.constraint(equalTo: leadingAnchor), rangee.topAnchor.constraint(equalTo: topAnchor),
            rangee.bottomAnchor.constraint(equalTo: bottomAnchor), rangee.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        peindre()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func peindre() {
        for (i, b) in boutons.enumerated() {
            let oui = i == choisie
            b.layer?.backgroundColor = (oui ? vert : NSColor(white: 1, alpha: 0.10)).cgColor
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: oui ? NSColor.black : NSColor.white])
        }
    }
    @objc private func clic(_ b: NSButton) {
        choisie = b.tag
        peindre()
        auChoix?(b.tag)
    }
}

// MARK: - Le lecteur

final class LecteurSpotifyBas: NSView, NSSearchFieldDelegate {
    private enum Onglet: Int { case accueil, lecture, recherche, bibliotheque }

    private let pageLecture = NSView(), pageAccueil = ListeSpotifyBas(), pageRecherche = NSView(), pageBiblio = NSView()
    private let pageConnexion = NSView()
    private let resultats = ListeSpotifyBas(), biblio = ListeSpotifyBas()
    private let champ = NSSearchField()
    private let genres = PastillesBas([String(localized: "Playlists"), String(localized: "Albums"), String(localized: "Podcasts"), String(localized: "Titres")])
    private let champIdentifiant = NSTextField()
    private let etatConnexion = NSTextField(wrappingLabelWithString: "")
    private var onglets: [BoutonBas] = []
    private var onglet = Onglet.lecture
    // En large (520 points et plus), comme l'application Spotify du Mac : un lecteur tout simple reste à gauche,
    // et l'accueil, la recherche ou la bibliothèque s'affichent à droite. En étroit : un écran à la fois, comme sur un téléphone.
    private var enLarge = false
    private var contraintesEtroites: [NSLayoutConstraint] = [], contraintesLarges: [NSLayoutConstraint] = []
    private var largeurLecture: NSLayoutConstraint?                      // la largeur du lecteur de gauche, selon la place
    private var contraintesBord: [(NSLayoutConstraint, CGFloat)] = []    // ce qui commence juste après lui
    private var recherchePrevue: DispatchWorkItem?

    private let pochette = NSImageView()
    private let titre = NSTextField(labelWithString: "")
    private let artiste = NSTextField(labelWithString: "")
    private let ecoule = NSTextField(labelWithString: "0:00"), total = NSTextField(labelWithString: "0:00")
    private let avance = CurseurBas()
    private var lecture: BoutonBas!, aleatoire: BoutonBas!, repete: BoutonBas!
    private var adressePochette = ""
    private var etat = SpotifyBas.Etat()
    private let accent = NSColor(red: 0.11, green: 0.73, blue: 0.33, alpha: 1)   // le vert de Spotify

    // Une tuile comme les autres, aux couleurs de Spotify : fond presque noir, texte blanc, touches de vert.
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor
        layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.masksToBounds = true
        construireLecture()
        construireRecherche()
        construireBiblio()
        construireConnexion()
        for liste in [pageAccueil, resultats, biblio] { liste.auChoix = { [weak self] e in self?.lancer(e) } }

        onglets = [onglet("house.fill", String(localized: "Accueil"), 0), onglet("play.circle.fill", String(localized: "Lecture"), 1),
                   onglet("magnifyingglass", String(localized: "Recherche"), 2), onglet("books.vertical.fill", String(localized: "Bibliothèque"), 3)]
        // Clic droit sur « Bibliothèque » : se déconnecter du compte.
        let menuCompte = NSMenu()
        let sortie = menuCompte.addItem(withTitle: String(localized: "Déconnecter le compte Spotify"), action: #selector(deconnecter), keyEquivalent: "")
        sortie.target = self
        onglets[3].menu = menuCompte
        let barre = NSStackView(views: onglets)
        barre.distribution = .fillEqually
        barre.spacing = 0
        // Un trait fin sépare la barre d'onglets du reste, comme sur un téléphone.
        let trait = NSView()
        trait.wantsLayer = true
        trait.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
        let pages: [NSView] = [pageAccueil, pageLecture, pageRecherche, pageBiblio, pageConnexion]
        for v in pages + [trait, barre] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            barre.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            barre.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8), barre.heightAnchor.constraint(equalToConstant: 44),
            trait.trailingAnchor.constraint(equalTo: trailingAnchor),
            trait.bottomAnchor.constraint(equalTo: barre.topAnchor, constant: -6), trait.heightAnchor.constraint(equalToConstant: 1),
        ])
        let bord: CGFloat = 322      // en large, le lecteur occupe la gauche : le reste commence ici
        contraintesEtroites = [barre.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), trait.leadingAnchor.constraint(equalTo: leadingAnchor)]
        contraintesLarges = [barre.leadingAnchor.constraint(equalTo: leadingAnchor, constant: bord), trait.leadingAnchor.constraint(equalTo: leadingAnchor, constant: bord - 6)]
        contraintesBord = [(contraintesLarges[0], 22), (contraintesLarges[1], 16)]
        for page in pages {
            page.topAnchor.constraint(equalTo: topAnchor, constant: 14).isActive = true
            if page === pageLecture {
                page.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7).isActive = true
                contraintesEtroites += [page.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
                                        page.bottomAnchor.constraint(equalTo: trait.topAnchor, constant: -4)]
                let l = page.widthAnchor.constraint(equalToConstant: 300)
                largeurLecture = l
                contraintesLarges += [l, page.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)]
            } else {
                page.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7).isActive = true
                page.bottomAnchor.constraint(equalTo: trait.topAnchor, constant: -4).isActive = true
                contraintesEtroites.append(page.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7))
                let c = page.leadingAnchor.constraint(equalTo: leadingAnchor, constant: bord)
                contraintesLarges.append(c)
                contraintesBord.append((c, 22))
            }
        }
        NSLayoutConstraint.activate(contraintesEtroites)
        montrer(.lecture)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        let large = bounds.width >= 520
        // Le lecteur de gauche prend un bon tiers de la tuile, entre 210 et 300 points ; le reste va aux listes.
        let lecteur = min(300, max(210, (bounds.width * 0.34).rounded()))
        if largeurLecture?.constant != lecteur {
            largeurLecture?.constant = lecteur
            for (c, ecart) in contraintesBord { c.constant = lecteur + ecart }
        }
        if large != enLarge {
            enLarge = large
            NSLayoutConstraint.deactivate(large ? contraintesEtroites : contraintesLarges)
            NSLayoutConstraint.activate(large ? contraintesLarges : contraintesEtroites)
            onglets[1].isHidden = large          // l'onglet « Lecture » ne sert plus : le lecteur est toujours là, à gauche
            montrer(onglet)
        }
        super.layout()
    }


    // MARK: Petits outils

    private func symbole(_ nom: String, _ taille: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: nom, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: taille, weight: .semibold))
    }

    private func bouton(_ nom: String, _ taille: CGFloat, _ action: Selector) -> BoutonBas {
        let b = BoutonBas(frame: .zero)
        b.isBordered = false
        b.image = symbole(nom, taille)
        b.contentTintColor = .labelColor
        b.target = self
        b.action = action
        return b
    }

    private func onglet(_ nom: String, _ texte: String, _ rang: Int) -> BoutonBas {
        let b = bouton(nom, 17, #selector(choisirOnglet(_:)))
        b.title = texte
        b.font = .systemFont(ofSize: 10, weight: .medium)
        b.imagePosition = .imageAbove
        b.tag = rang
        return b
    }

    private func texte(_ t: NSTextField, _ taille: CGFloat, _ poids: NSFont.Weight, _ couleur: NSColor) {
        t.font = .systemFont(ofSize: taille, weight: poids)
        t.textColor = couleur
        t.alignment = .center
        t.lineBreakMode = .byTruncatingTail
    }

    private func remplir(_ page: NSView, titre nom: String, haut: NSView, liste: NSView) {
        let grand = NSTextField(labelWithString: nom)
        grand.font = .systemFont(ofSize: 22, weight: .bold)
        grand.textColor = .white
        for v in [grand, haut, liste] {
            v.translatesAutoresizingMaskIntoConstraints = false
            page.addSubview(v)
        }
        NSLayoutConstraint.activate([
            grand.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 8), grand.topAnchor.constraint(equalTo: page.topAnchor),
            haut.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 6), haut.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -6),
            haut.topAnchor.constraint(equalTo: grand.bottomAnchor, constant: 10),
            liste.leadingAnchor.constraint(equalTo: page.leadingAnchor), liste.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            liste.topAnchor.constraint(equalTo: haut.bottomAnchor, constant: 8), liste.bottomAnchor.constraint(equalTo: page.bottomAnchor),
        ])
    }

    // MARK: Construction des écrans

    private func construireLecture() {
        pochette.wantsLayer = true
        pochette.layer?.cornerRadius = 8
        pochette.layer?.masksToBounds = true
        pochette.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        pochette.imageScaling = .scaleProportionallyUpOrDown
        texte(titre, 17, .bold, .white)
        texte(artiste, 13, .regular, NSColor(white: 0.7, alpha: 1))
        texte(ecoule, 10, .regular, .secondaryLabelColor)
        texte(total, 10, .regular, .secondaryLabelColor)
        avance.controlSize = .small; avance.isContinuous = false; avance.target = self; avance.trackFillColor = .white
        avance.minValue = 0; avance.maxValue = 1; avance.action = #selector(chercherPosition)

        let progression = NSStackView(views: [ecoule, avance, total])
        progression.spacing = 6
        aleatoire = bouton("shuffle", 14, #selector(basculerAleatoire))
        let avant = bouton("backward.end.fill", 20, #selector(precedent))
        lecture = bouton("play.circle.fill", 50, #selector(basculer))
        lecture.contentTintColor = .white
        let apres = bouton("forward.end.fill", 20, #selector(suivant))
        repete = bouton("repeat", 14, #selector(basculerRepete))
        let commandes = NSStackView(views: [aleatoire, avant, lecture, apres, repete])
        commandes.distribution = .equalSpacing
        // La vidéo d'un podcast ne peut pas s'afficher ici : ce bouton ouvre la fenêtre de Spotify en grand, où elle se regarde.
        let video = BoutonBas(title: "", target: self, action: #selector(voirVideo))
        video.isBordered = false
        video.wantsLayer = true
        video.layer?.cornerRadius = 14
        video.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
        video.image = symbole("play.rectangle.fill", 12)
        video.imagePosition = .imageLeading
        video.contentTintColor = .white
        video.attributedTitle = NSAttributedString(string: " " + String(localized: "Voir la vidéo"), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
        video.toolTip = String(localized: "Ouvre Spotify en grand pour regarder la vidéo")
        let pile = NSStackView(views: [pochette, titre, artiste, progression, commandes, video])
        pile.orientation = .vertical
        pile.spacing = 8
        pile.setCustomSpacing(14, after: pochette)
        pile.setCustomSpacing(12, after: artiste)
        pile.setCustomSpacing(14, after: commandes)
        pile.translatesAutoresizingMaskIntoConstraints = false
        pageLecture.addSubview(pile)
        let cote = pochette.heightAnchor.constraint(equalToConstant: 250)
        cote.priority = .defaultHigh
        NSLayoutConstraint.activate([
            pile.centerXAnchor.constraint(equalTo: pageLecture.centerXAnchor),
            pile.centerYAnchor.constraint(equalTo: pageLecture.centerYAnchor),
            pile.widthAnchor.constraint(equalTo: pageLecture.widthAnchor, constant: -26),
            pile.heightAnchor.constraint(lessThanOrEqualTo: pageLecture.heightAnchor),
            cote, pochette.widthAnchor.constraint(equalTo: pochette.heightAnchor),
            pochette.widthAnchor.constraint(lessThanOrEqualTo: pile.widthAnchor),      // dans un lecteur étroit, la pochette rétrécit
            titre.widthAnchor.constraint(equalTo: pile.widthAnchor), artiste.widthAnchor.constraint(equalTo: pile.widthAnchor),
            progression.widthAnchor.constraint(equalTo: pile.widthAnchor), commandes.widthAnchor.constraint(equalTo: pile.widthAnchor),
            video.widthAnchor.constraint(equalToConstant: 132), video.heightAnchor.constraint(equalToConstant: 28),
            ecoule.widthAnchor.constraint(equalToConstant: 46), total.widthAnchor.constraint(equalToConstant: 46),
        ])
    }

    private func construireRecherche() {
        champ.placeholderString = String(localized: "Titres, artistes, albums, playlists")
        champ.delegate = self
        champ.sendsSearchStringImmediately = false
        champ.controlSize = .large
        remplir(pageRecherche, titre: String(localized: "Recherche"), haut: champ, liste: resultats)
        resultats.dire(String(localized: "Tapez pour chercher dans Spotify."))
    }

    private func construireBiblio() {
        genres.auChoix = { [weak self] _ in self?.chargerBiblio() }
        remplir(pageBiblio, titre: String(localized: "Bibliothèque"), haut: genres, liste: biblio)
    }

    private func construireConnexion() {
        let titre = NSTextField(labelWithString: String(localized: "Connecter Spotify"))
        titre.font = .systemFont(ofSize: 17, weight: .bold)
        let etapes = NSTextField(wrappingLabelWithString: String(localized: """
        1. Ouvrez le site développeur de Spotify et connectez-vous.
        2. « Create app » : un nom au choix, et dans « Redirect URIs » : \(SpotifyCompte.redirection). Cochez « Web API ».
        3. Copiez le « Client ID » de cette app et collez-le ci-dessous.
        4. « Se connecter », puis « Accepter » dans la page Spotify qui s'ouvre.
        """))
        etapes.font = .systemFont(ofSize: 11.5)
        etapes.textColor = .secondaryLabelColor
        etapes.isSelectable = true
        let site = BoutonBas(title: String(localized: "Ouvrir le site Spotify"), target: self, action: #selector(ouvrirSite))
        let adresse = BoutonBas(title: String(localized: "Copier l'adresse de redirection"), target: self, action: #selector(copierRedirection))
        champIdentifiant.placeholderString = "Client ID"
        champIdentifiant.stringValue = SpotifyCompte.commun.identifiant
        champIdentifiant.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let connecter = BoutonBas(title: String(localized: "Se connecter"), target: self, action: #selector(connecter))
        connecter.keyEquivalent = "\r"
        for b in [site, adresse, connecter] { b.bezelStyle = .rounded; b.controlSize = .small }
        etatConnexion.font = .systemFont(ofSize: 11)
        etatConnexion.textColor = .secondaryLabelColor
        let pile = NSStackView(views: [titre, etapes, site, adresse, champIdentifiant, connecter, etatConnexion])
        pile.orientation = .vertical
        pile.alignment = .leading
        pile.spacing = 9
        pile.translatesAutoresizingMaskIntoConstraints = false
        pageConnexion.addSubview(pile)
        NSLayoutConstraint.activate([
            pile.leadingAnchor.constraint(equalTo: pageConnexion.leadingAnchor, constant: 8),
            pile.trailingAnchor.constraint(equalTo: pageConnexion.trailingAnchor, constant: -8),
            pile.topAnchor.constraint(equalTo: pageConnexion.topAnchor, constant: 4),
            etapes.widthAnchor.constraint(equalTo: pile.widthAnchor), champIdentifiant.widthAnchor.constraint(equalTo: pile.widthAnchor),
            etatConnexion.widthAnchor.constraint(equalTo: pile.widthAnchor),
        ])
    }

    // MARK: Onglets

    @objc private func choisirOnglet(_ b: NSButton) { montrer(Onglet(rawValue: b.tag) ?? .lecture) }

    private func montrer(_ choix: Onglet) {
        // En large, le lecteur est toujours affiché à gauche : à droite, « Lecture » laisse la place à l'accueil.
        let o: Onglet = enLarge && choix == .lecture ? .accueil : choix
        onglet = o
        // Accueil, Recherche et Bibliothèque passent par le compte : sans connexion, on montre comment se connecter.
        let besoinCompte = o != .lecture && !SpotifyCompte.commun.connecte
        pageConnexion.isHidden = !besoinCompte
        pageAccueil.isHidden = besoinCompte || o != .accueil
        pageLecture.isHidden = !enLarge && o != .lecture
        pageRecherche.isHidden = besoinCompte || o != .recherche
        pageBiblio.isHidden = besoinCompte || o != .bibliotheque
        for (i, b) in onglets.enumerated() {
            let oui = i == o.rawValue
            b.contentTintColor = oui ? .white : NSColor(white: 0.62, alpha: 1)
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: oui ? .semibold : .medium),
                .foregroundColor: oui ? NSColor.white : NSColor(white: 0.62, alpha: 1)])
        }
        guard !besoinCompte else { return }
        switch o {
        case .accueil: chargerAccueil()
        case .bibliotheque: chargerBiblio()
        case .recherche: window?.makeFirstResponder(champ)
        case .lecture: break
        }
    }

    // MARK: Connexion

    @objc private func ouvrirSite() { NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!) }

    @objc private func copierRedirection() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SpotifyCompte.redirection, forType: .string)
        etatConnexion.stringValue = String(localized: "Adresse copiée : collez-la dans « Redirect URIs ».")
    }

    @objc private func connecter() {
        SpotifyCompte.commun.identifiant = champIdentifiant.stringValue
        etatConnexion.stringValue = String(localized: "La page de Spotify s'ouvre dans votre navigateur…")
        SpotifyCompte.commun.connecter { [weak self] erreur in
            guard let self else { return }
            if let erreur { self.etatConnexion.stringValue = erreur; return }
            self.etatConnexion.stringValue = ""
            journalBas("compte Spotify connecté")
            self.montrer(self.onglet)
        }
    }

    @objc private func deconnecter() {
        SpotifyCompte.commun.deconnecter()
        montrer(onglet)
    }

    // MARK: Accueil, Bibliothèque, Recherche

    private func chargerAccueil() {
        pageAccueil.dire(String(localized: "Chargement…"))
        var recents: [ElementSpotify] = [], favoris: [ElementSpotify] = [], artistes: [ElementSpotify] = []
        var attendus = 3, erreurVue: String?
        func fini(_ erreur: String?) {
            attendus -= 1
            if let erreur { erreurVue = erreur }
            guard attendus == 0, onglet == .accueil else { return }
            let rubriques = [(String(localized: "Écoutés récemment"), recents), (String(localized: "Vos titres du moment"), favoris), (String(localized: "Vos artistes du moment"), artistes)]
            if rubriques.allSatisfy({ $0.1.isEmpty }) { pageAccueil.dire(erreurVue ?? String(localized: "Rien à afficher pour l'instant.")) }
            else { pageAccueil.montrer(rubriques) }
        }
        SpotifyCompte.commun.appel("me/player/recently-played?limit=30") { json, erreur in
            var vus = Set<String>()
            for i in SpotifyCompte.liste(json) {
                guard let t = i["track"] as? [String: Any],
                      let e = SpotifyCompte.titre(t, contexte: (i["context"] as? [String: Any])?["uri"] as? String),
                      !vus.contains(e.uri), recents.count < 8 else { continue }
                vus.insert(e.uri)
                recents.append(e)
            }
            fini(erreur)
        }
        SpotifyCompte.commun.appel("me/top/tracks?limit=8&time_range=short_term") { json, erreur in
            favoris = SpotifyCompte.liste(json).compactMap { SpotifyCompte.titre($0) }
            fini(erreur)
        }
        SpotifyCompte.commun.appel("me/top/artists?limit=6&time_range=short_term") { json, erreur in
            artistes = SpotifyCompte.liste(json).compactMap { SpotifyCompte.recueil($0, genre: String(localized: "Artiste")) }
            fini(erreur)
        }
    }

    private func chargerBiblio() {
        let rang = genres.choisie
        biblio.dire(String(localized: "Chargement…"))
        let chemin = ["me/playlists?limit=50", "me/albums?limit=50", "me/shows?limit=50", "me/tracks?limit=50"][max(0, min(3, rang))]
        SpotifyCompte.commun.appel(chemin) { [weak self] json, erreur in
            guard let self, self.genres.choisie == rang else { return }
            let lignes = SpotifyCompte.liste(json)
            let elements: [ElementSpotify]
            switch rang {
            case 0: elements = lignes.compactMap { SpotifyCompte.recueil($0, genre: String(localized: "Playlist")) }
            case 1: elements = lignes.compactMap { ($0["album"] as? [String: Any]).flatMap { SpotifyCompte.recueil($0, genre: String(localized: "Album")) } }
            case 2: elements = lignes.compactMap { ($0["show"] as? [String: Any]).flatMap { SpotifyCompte.recueil($0, genre: String(localized: "Podcast")) } }
            default: elements = lignes.compactMap { ($0["track"] as? [String: Any]).flatMap { SpotifyCompte.titre($0) } }
            }
            if elements.isEmpty { self.biblio.dire(erreur ?? String(localized: "Rien dans cette rubrique.")) } else { self.biblio.montrer([("", elements)]) }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        recherchePrevue?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.chercher() }
        recherchePrevue = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    private func chercher() {
        let mots = champ.stringValue.trimmingCharacters(in: .whitespaces)
        guard !mots.isEmpty else { resultats.dire(String(localized: "Tapez pour chercher dans Spotify.")); return }
        var permis = CharacterSet.alphanumerics
        permis.insert(charactersIn: "-._~")
        let q = mots.addingPercentEncoding(withAllowedCharacters: permis) ?? ""
        SpotifyCompte.commun.appel("search?q=\(q)&type=track,artist,album,playlist&limit=5") { [weak self] json, erreur in
            guard let self, self.champ.stringValue.trimmingCharacters(in: .whitespaces) == mots else { return }
            let rubriques: [(String, [ElementSpotify])] = [
                (String(localized: "Titres"), SpotifyCompte.liste(json, "tracks").compactMap { SpotifyCompte.titre($0) }),
                (String(localized: "Artistes"), SpotifyCompte.liste(json, "artists").compactMap { SpotifyCompte.recueil($0, genre: String(localized: "Artiste")) }),
                (String(localized: "Albums"), SpotifyCompte.liste(json, "albums").compactMap { SpotifyCompte.recueil($0, genre: String(localized: "Album")) }),
                (String(localized: "Playlists"), SpotifyCompte.liste(json, "playlists").compactMap { SpotifyCompte.recueil($0, genre: String(localized: "Playlist")) }),
            ]
            if rubriques.allSatisfy({ $0.1.isEmpty }) { self.resultats.dire(erreur ?? String(localized: "Aucun résultat pour « \(mots) ».")) }
            else { self.resultats.montrer(rubriques) }
        }
    }

    /// Lance ce qu'on vient de choisir dans l'application Spotify du Mac, puis revient à l'écran de lecture.
    private func lancer(_ e: ElementSpotify) {
        let ordre = e.contexte.map { "play track \"\(e.uri)\" in context \"\($0)\"" } ?? "play track \"\(e.uri)\""
        SpotifyBas.commande(ordre) { [weak self] in self?.rafraichir() }
        montrer(.lecture)
    }

    // MARK: Lecture

    @objc private func precedent() { SpotifyBas.commande("previous track") { [weak self] in self?.rafraichir() } }
    @objc private func suivant() { SpotifyBas.commande("next track") { [weak self] in self?.rafraichir() } }
    @objc private func basculer() { SpotifyBas.commande("playpause") { [weak self] in self?.rafraichir() } }
    @objc private func basculerAleatoire() {
        SpotifyBas.commande("set shuffling to \(etat.aleatoire ? "false" : "true")") { [weak self] in self?.rafraichir() }
    }
    @objc private func basculerRepete() {
        SpotifyBas.commande("set repeating to \(etat.repete ? "false" : "true")") { [weak self] in self?.rafraichir() }
    }
    @objc private func chercherPosition() {
        SpotifyBas.commande("set player position to \(Int(avance.doubleValue * etat.duree))") { [weak self] in self?.rafraichir() }
    }
    @objc private func voirVideo() { PanneauBas.commun.montrerSpotifyEnGrand() }

    private func minutes(_ s: Double) -> String {
        let t = Int(max(0, s))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    func rafraichir() {
        SpotifyBas.lire { [weak self] e in
            guard let self else { return }
            self.etat = e
            self.titre.stringValue = e.enCours ? (e.titre.isEmpty ? String(localized: "Rien en lecture") : e.titre) : String(localized: "Spotify est fermé")
            self.artiste.stringValue = e.enCours ? e.artiste : String(localized: "Le bouton lecture l'ouvre")
            self.lecture.image = self.symbole(e.joue ? "pause.circle.fill" : "play.circle.fill", 50)
            self.aleatoire.contentTintColor = e.aleatoire ? self.accent : .secondaryLabelColor
            self.repete.contentTintColor = e.repete ? self.accent : .secondaryLabelColor
            // Pendant que vous tenez un curseur, on ne le déplace pas sous votre doigt.
            if NSEvent.pressedMouseButtons == 0 {
                self.avance.doubleValue = e.duree > 0 ? min(1, e.position / e.duree) : 0
            }
            self.ecoule.stringValue = self.minutes(e.position)
            self.total.stringValue = self.minutes(e.duree)
            guard e.pochette != self.adressePochette else { return }
            self.adressePochette = e.pochette
            guard let url = URL(string: e.pochette) else { self.pochette.image = nil; return }
            URLSession.shared.dataTask(with: url) { d, _, _ in
                guard let d, let img = NSImage(data: d) else { return }
                DispatchQueue.main.async { if self.adressePochette == e.pochette { self.pochette.image = img } }
            }.resume()
        }
    }
}
