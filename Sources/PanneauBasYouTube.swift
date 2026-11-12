// Le lecteur YouTube du panneau du bas : le site YouTube pour téléphone, affiché dans une tuile.
// On s'y connecte une fois avec son compte (la connexion est retenue par macOS, rien n'est stocké ici),
// et on peut y déposer un lien de vidéo glissé depuis Safari, ou coller un lien copié.
import AppKit
import WebKit

/// Transforme n'importe quel lien YouTube (youtube.com, youtu.be, lien intégré) en lien pour le site téléphone. Sinon : rien.
func lienYouTubeBas(_ url: URL) -> URL? {
    guard let hote = url.host?.lowercased(), var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    c.scheme = "https"
    if hote == "youtu.be" || hote.hasSuffix(".youtu.be") {
        let id = url.pathComponents.dropFirst().first ?? ""
        guard !id.isEmpty else { return nil }
        let temps = c.queryItems?.first { $0.name == "t" }
        c.host = "m.youtube.com"
        c.path = "/watch"
        c.queryItems = [URLQueryItem(name: "v", value: id)] + (temps.map { [$0] } ?? [])
        return c.url
    }
    guard hote == "youtube.com" || hote.hasSuffix(".youtube.com") || hote.hasSuffix("youtube-nocookie.com") else { return nil }
    c.host = "m.youtube.com"
    if url.path.hasPrefix("/embed/") {
        c.path = "/watch"
        c.queryItems = [URLQueryItem(name: "v", value: url.lastPathComponent)]
    }
    return c.url
}

/// La page YouTube elle-même. Un lien YouTube déposé dessus s'ouvre dans le lecteur.
final class PageYouTubeBas: WKWebView {
    var auLien: ((URL) -> Void)?

    private func lien(_ info: NSDraggingInfo) -> URL? {
        let pb = info.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for u in urls where !u.isFileURL { if let l = lienYouTubeBas(u) { return l } }
        }
        if let texte = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let u = URL(string: texte), let l = lienYouTubeBas(u) { return l }
        return nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        lien(sender) != nil ? .copy : super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        lien(sender) != nil ? .copy : super.draggingUpdated(sender)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        lien(sender) != nil ? true : super.prepareForDragOperation(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let l = lien(sender) else { return super.performDragOperation(sender) }
        auLien?(l)
        return true
    }
}

/// Le bord droit de la tuile YouTube : on le tire pour l'élargir ou la rétrécir.
final class PoigneeLargeurBas: NSView {
    var auDebut: (() -> Void)?
    var auTirage: ((CGFloat) -> Void)?
    var aLaFin: (() -> Void)?
    private var depart: CGFloat = 0
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 1, alpha: 0.35).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 1.5, y: bounds.midY - 18, width: 3, height: 36), xRadius: 1.5, yRadius: 1.5).fill()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func mouseDown(with event: NSEvent) { depart = NSEvent.mouseLocation.x; auDebut?() }
    override func mouseDragged(with event: NSEvent) { auTirage?(NSEvent.mouseLocation.x - depart) }
    override func mouseUp(with event: NSEvent) { aLaFin?() }
}

final class LecteurYouTubeBas: NSView, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, NSWindowDelegate {
    static let largeurEtroite: CGFloat = 400
    static let largeurLarge: CGFloat = 1100

    /// La largeur de la tuile, choisie en tirant son bord droit, retenue d'une fois sur l'autre.
    static var largeurCommune: CGFloat {
        get { let l = UserDefaults.standard.double(forKey: "panneauBasYouTubeLargeur"); return l > 0 ? max(CGFloat(l), LecteurYouTubeBas.largeurMini) : LecteurYouTubeBas.largeurLarge }
        set { UserDefaults.standard.set(Double(newValue), forKey: "panneauBasYouTubeLargeur") }
    }
    var largeur: CGFloat { get { Self.largeurCommune } set { Self.largeurCommune = newValue } }

    // Ce lecteur sert à YouTube (avec ses réglages propres : publicités coupées, plein écran ramené à la tuile)
    // et à n'importe quel autre site ajouté au coin multimédia (Deezer, Apple Music, Twitch… : la page telle quelle).
    private let adresseAccueil: URL
    private let estYouTube: Bool
    /// La présentation suit la largeur :
    /// - large : le YouTube d'un ordinateur (vidéo à gauche, commentaires dessous, vidéos à voir à droite quand il y a la place) ;
    /// - étroite : le YouTube d'un téléphone, tout en une colonne.
    /// Depuis le 12/11 au soir, la tuile affiche toujours le YouTube d'un ordinateur, quelle que soit sa largeur :
    /// changer de site en cours de route rechargeait la page et coupait la vidéo, et le plein écran ne marchait pas
    /// sur le site pour téléphone. Le site d'ordinateur se réorganise tout seul (une ou deux colonnes).
    var large: Bool { true }
    static let largeurMini: CGFloat = 460
    /// Pendant qu'on tire le bord droit : début, à chaque mouvement, fin. Le panneau déplace les tuiles voisines.
    var auDébutDuTirage: (() -> Void)?
    var auTirage: (() -> Void)?
    var àLaFinDuTirage: (() -> Void)?
    private let poignée = PoigneeLargeurBas()
    private var largeurAuDépart: CGFloat = 0
    private var largeAuDépart = true
    /// Appelé quand la tuile change de largeur : le panneau refait sa bande.
    var auChangementDeLargeur: (() -> Void)?

    private var hôte: String { large ? "www.youtube.com" : "m.youtube.com" }
    private var accueil: URL { adresseAccueil }
    // Se présente comme Safari : sur Mac pour la tuile large (site d'ordinateur, à deux colonnes), sur iPhone pour l'étroite.
    // Dans les deux cas, Google accepte la connexion.
    private let safariMac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
    private let safariIPhone = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
    private let barre = NSView()
    private var page: PageYouTubeBas!
    private var retour: BoutonBas!, taille: BoutonBas!
    private var chargée = false
    /// La petite barre de Side (retour, accueil, commandes vidéo, lien, largeur) est masquée : on ne garde que la page YouTube.
    /// Pour la faire revenir : mettre 36 ici.
    private let hauteurBarre: CGFloat = 0

    init(accueil: URL, youtube: Bool) {
        adresseAccueil = accueil
        estYouTube = youtube
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor
        layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        appearance = NSAppearance(named: .darkAqua)      // YouTube s'affiche en sombre, comme la tuile Spotify

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []      // une vidéo déposée démarre toute seule
        config.allowsAirPlayForMediaPlayback = true
        let reglage = "window.__sideCouperPubs = \(ConfigTiroir.commun.couperPubs ? "true" : "false"); window.__sideSansShorts = \(ConfigTiroir.commun.masquerShorts ? "true" : "false");"
        let scripts = youtube ? [reglage, LecteurYouTubeBas.scriptSansPub, LecteurYouTubeBas.scriptPleinCadre] : [LecteurYouTubeBas.scriptToujoursAffiche]
        for s in scripts {
            config.userContentController.addUserScript(WKUserScript(source: s, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if !youtube { config.preferences.isElementFullscreenEnabled = true }      // un autre site garde son vrai plein écran
        if youtube { config.userContentController.add(self, name: "sidePlein") }  // le bouton plein écran de YouTube prévient Side
        page = PageYouTubeBas(frame: .zero, configuration: config)
        page.customUserAgent = large ? safariMac : safariIPhone
        page.navigationDelegate = self
        page.uiDelegate = self
        page.allowsBackForwardNavigationGestures = false          // le glissement horizontal sert à faire défiler la bande
        if youtube { page.auLien = { [weak self] l in self?.ouvrir(l) } }      // un lien YouTube déposé ne s'ouvre que dans YouTube
        addSubview(page)

        barre.wantsLayer = true
        barre.layer?.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor
        addSubview(barre)
        poignée.auDebut = { [weak self] in
            guard let self else { return }
            self.largeurAuDépart = self.bounds.width
            self.largeAuDépart = self.large
            self.auDébutDuTirage?()
        }
        poignée.auTirage = { [weak self] d in
            guard let self else { return }
            self.largeur = min(max(self.largeurAuDépart + d, LecteurYouTubeBas.largeurMini), 2400)
            self.auTirage?()
        }
        poignée.aLaFin = { [weak self] in
            guard let self else { return }
            self.largeur = max(LecteurYouTubeBas.largeurMini, self.bounds.width)      // la largeur vraiment obtenue (le panneau la borne à sa bande)
            self.àLaFinDuTirage?()
            self.suivreLaLargeur(étaitLarge: self.largeAuDépart)
        }
        addSubview(poignée)
        poignée.isHidden = true      // la largeur se règle maintenant sur le coin multimédia entier (Spotify comme YouTube)
        retour = bouton("chevron.left", String(localized: "Page précédente"), #selector(reculer))
        let maison = bouton("house.fill", String(localized: "Accueil de YouTube"), #selector(allerAccueil))
        let coller = bouton("link", String(localized: "Ouvrir le lien YouTube copié"), #selector(collerLien))
        taille = bouton("arrow.left.and.right", String(localized: "Élargir ou rétrécir le lecteur"), #selector(changerLargeur))
        // Les commandes du site pour téléphone sont faites pour le doigt : celles-ci marchent toujours à la souris.
        let moins = bouton("gobackward.10", String(localized: "Reculer de 10 secondes"), #selector(reculerDansLaVidéo))
        let pause = bouton("playpause.fill", String(localized: "Lecture / pause"), #selector(lecturePause))
        let plus = bouton("goforward.10", String(localized: "Avancer de 10 secondes"), #selector(avancerDansLaVidéo))
        let passer = bouton("forward.end.fill", String(localized: "Passer la publicité (quand YouTube le propose)"), #selector(passerLaPub))
        let gauche = NSStackView(views: [retour, maison])
        let milieu = NSStackView(views: [moins, pause, plus, passer])
        let cadre = bouton("arrow.up.left.and.arrow.down.right", String(localized: "La vidéo remplit la tuile (ou reprend sa place)"), #selector(pleinCadre))
        let droite = NSStackView(views: [coller, cadre, taille])
        for pile in [gauche, milieu, droite] {
            pile.spacing = 10
            pile.translatesAutoresizingMaskIntoConstraints = false
            barre.addSubview(pile)
            pile.centerYAnchor.constraint(equalTo: barre.centerYAnchor).isActive = true
        }
        gauche.leadingAnchor.constraint(equalTo: barre.leadingAnchor, constant: 12).isActive = true
        milieu.centerXAnchor.constraint(equalTo: barre.centerXAnchor).isActive = true
        droite.trailingAnchor.constraint(equalTo: barre.trailingAnchor, constant: -12).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private func bouton(_ symbole: String, _ aide: String, _ action: Selector) -> BoutonBas {
        let b = BoutonBas(frame: .zero)
        b.isBordered = false
        b.image = NSImage(systemSymbolName: symbole, accessibilityDescription: aide)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        b.contentTintColor = NSColor(white: 1, alpha: 0.85)
        b.toolTip = aide
        b.target = self
        b.action = action
        return b
    }

    override func layout() {
        super.layout()
        barre.isHidden = hauteurBarre == 0
        barre.frame = NSRect(x: 0, y: bounds.height - hauteurBarre, width: bounds.width, height: hauteurBarre)
        // La page n'est placée ici que si elle est dans la tuile (en plein écran, elle est dans sa propre fenêtre).
        if page.superview === self { page.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - hauteurBarre)) }
        attente?.frame = bounds
        poignée.frame = NSRect(x: bounds.width - 9, y: 0, width: 9, height: max(0, bounds.height - hauteurBarre))
    }

    /// À l'ouverture du panneau : la première fois, charge l'accueil de YouTube.
    func réveiller() {
        guard !chargée else { return }
        chargée = true
        page.load(URLRequest(url: accueil))
    }

    func ouvrir(_ lien: URL) {
        chargée = true
        // Le lien est ramené au site qui correspond à la présentation en cours (ordinateur ou téléphone).
        var c = URLComponents(url: lien, resolvingAgainstBaseURL: false)
        if estYouTube, let h = c?.host?.lowercased(), h.hasSuffix("youtube.com") { c?.host = hôte }
        let adresse = c?.url ?? lien
        journalBas("YouTube : lien ouvert %@", adresse.absoluteString)
        page.load(URLRequest(url: adresse))
    }

    @objc private func reculer() { if page.canGoBack { page.goBack() } }
    @objc private func allerAccueil() { ouvrir(accueil) }

    @objc private func collerLien() {
        guard let texte = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let u = URL(string: texte), let l = lienYouTubeBas(u) else { NSSound.beep(); return }
        ouvrir(l)
    }

    /// Le « plein écran » de YouTube, ramené à la tuile : la vidéo remplit toute la tuile, avec ses commandes, sans sortir
    /// du panneau. Le bouton plein écran du lecteur YouTube fait la même chose que celui de la petite barre.
    static let scriptPleinCadre = """
    (function(){
      if (window.__sidePlein) return; window.__sidePlein = true;
      var css = 'html.side-plein #player-container-id{position:fixed!important;left:0!important;top:0!important;width:100vw!important;height:100vh!important;z-index:2147483646!important;background:#000!important;padding:0!important;margin:0!important}'
        + 'html.side-plein #player,html.side-plein #movie_player,html.side-plein .html5-video-container{position:absolute!important;left:0!important;top:0!important;width:100%!important;height:100%!important;padding:0!important;margin:0!important}'
        + 'html.side-plein video.html5-main-video{width:100%!important;height:100%!important;left:0!important;top:0!important;object-fit:contain!important}'
        + 'html.side-plein body{overflow:hidden!important}'
        + 'html.side-plein ytd-app #movie_player{position:fixed!important;left:0!important;top:0!important;width:100vw!important;height:100vh!important;z-index:2147483646!important;background:#000!important}'
        + 'html.side-plein ytd-app #movie_player .html5-video-container{position:static!important}'
        + 'html.side-plein ytd-app #masthead-container{display:none!important}'
        + 'html.side-plein ytd-app #secondary,html.side-plein ytd-app #below,html.side-plein ytd-app #comments,html.side-plein ytd-app ytd-watch-metadata{visibility:hidden!important}'
        // En plein écran, la colonne des vidéos suivantes (bouton en haut à droite de la fenêtre) : la vidéo se resserre à gauche.
        + 'html.side-plein.side-suggestions ytd-app #movie_player,html.side-plein.side-suggestions #player-container-id{width:calc(100vw - 440px)!important}'
        + 'html.side-plein.side-suggestions ytd-watch-flexy #secondary{visibility:visible!important;display:block!important;position:fixed!important;top:0!important;right:0!important;width:440px!important;max-width:440px!important;min-width:0!important;height:100vh!important;overflow-y:auto!important;z-index:2147483647!important;background:#0f0f0f!important;padding:52px 12px 12px 12px!important;margin:0!important;box-sizing:border-box!important}'
        + 'html.side-plein.side-suggestions ytd-watch-flexy #secondary-inner{width:auto!important;padding:0!important}';
      function poser(){ if (document.getElementById('side-plein-css') || !document.documentElement) return;
        var s = document.createElement('style'); s.id = 'side-plein-css'; s.textContent = css; document.documentElement.appendChild(s); }
      function racine(){ return document.documentElement; }
      // YouTube croit disposer d'un vrai plein écran (sinon son bouton affiche « plein écran non disponible ») :
      // on lui annonce l'entrée et la sortie comme le ferait le navigateur, mais la vidéo ne fait que remplir la tuile.
      var enPlein = null;
      function annoncer(){ ['fullscreenchange','webkitfullscreenchange'].forEach(function(n){ document.dispatchEvent(new Event(n, { bubbles: true })); });
        window.dispatchEvent(new Event('resize')); }
      // Side est prévenu : il sort la page du tiroir dans une fenêtre qui remplit l'écran, et l'y ramène à la sortie.
      function dire(v){ try { window.webkit.messageHandlers.sidePlein.postMessage(v); } catch (e) {} }
      function entrerDans(el){ poser(); enPlein = el || document.getElementById('movie_player') || racine(); racine().classList.add('side-plein'); annoncer(); dire(true); }
      window.__sideSortir = function(){ if (!enPlein && !racine().classList.contains('side-plein')) return; enPlein = null; racine().classList.remove('side-plein'); annoncer(); dire(false); };
      window.__sideBasculer = function(){ if (racine().classList.contains('side-plein')) window.__sideSortir(); else entrerDans(null); return true; };
      var entrer = function(){ entrerDans(this instanceof Element ? this : null); return Promise.resolve(); };
      var sortir = function(){ window.__sideSortir(); return Promise.resolve(); };
      try {
        ['requestFullscreen','webkitRequestFullscreen','webkitRequestFullScreen'].forEach(function(n){ Element.prototype[n] = entrer; });
        ['webkitEnterFullscreen','webkitEnterFullScreen'].forEach(function(n){ HTMLVideoElement.prototype[n] = entrer; });
        ['webkitExitFullscreen','webkitExitFullScreen'].forEach(function(n){ HTMLVideoElement.prototype[n] = sortir; });
        ['exitFullscreen','webkitExitFullscreen','webkitCancelFullScreen'].forEach(function(n){ Document.prototype[n] = sortir; });
        ['fullscreenEnabled','webkitFullscreenEnabled','webkitFullScreenEnabled'].forEach(function(n){
          Object.defineProperty(Document.prototype, n, { configurable: true, get: function(){ return true; } }); });
        ['fullscreenElement','webkitFullscreenElement','webkitCurrentFullScreenElement'].forEach(function(n){
          Object.defineProperty(Document.prototype, n, { configurable: true, get: function(){ return enPlein; } }); });
        ['fullscreen','webkitIsFullScreen'].forEach(function(n){
          Object.defineProperty(Document.prototype, n, { configurable: true, get: function(){ return !!enPlein; } }); });
        Object.defineProperty(HTMLVideoElement.prototype, 'webkitSupportsFullscreen', { configurable: true, get: function(){ return true; } });
        Object.defineProperty(HTMLVideoElement.prototype, 'webkitDisplayingFullscreen', { configurable: true, get: function(){ return !!enPlein; } });
      } catch (e) {}
      // Le bouton plein écran du lecteur (en bas à droite) et la touche f : on les prend nous-mêmes, sans attendre
      // que YouTube décide (il ne sait pas toujours qu'il est « en plein écran »).
      function basculerIci(e){ e.preventDefault(); e.stopImmediatePropagation(); window.__sideBasculer(); }
      document.addEventListener('click', function(e){
        var b = e.target && e.target.closest && e.target.closest('.ytp-fullscreen-button');
        if (b) basculerIci(e);
      }, true);
      // En plein écran : un clic sur l'image met en pause ou relance, un double-clic ramène la vidéo dans le tiroir.
      // (YouTube ne le fait pas de lui-même ici : il croit son plein écran, et le clic n'arrivait pas à son lecteur.)
      function surLImage(t){
        if (!racine().classList.contains('side-plein') || !t || !t.closest) return false;
        if (t.closest('.ytp-chrome-bottom, .ytp-chrome-top, button, a, .ytp-popup, .ytp-ce-element, .ytp-suggested-action, #secondary')) return false;
        return !!t.closest('#movie_player');
      }
      document.addEventListener('click', function(e){
        if (!surLImage(e.target)) return;
        e.preventDefault(); e.stopImmediatePropagation();
        var p = document.getElementById('movie_player'), v = document.querySelector('video.html5-main-video');
        if (p && p.getPlayerState) { if (p.getPlayerState() === 1) p.pauseVideo(); else p.playVideo(); }
        else if (v) { if (v.paused) v.play(); else v.pause(); }
      }, true);
      document.addEventListener('dblclick', function(e){
        if (!surLImage(e.target)) return;
        e.preventDefault(); e.stopImmediatePropagation();
        window.__sideBasculer();
      }, true);
      document.addEventListener('keydown', function(e){
        var t = e.target, saisie = t && (t.isContentEditable || /INPUT|TEXTAREA/.test(t.tagName));
        if (!saisie && (e.key === 'f' || e.key === 'F') && !e.metaKey && !e.ctrlKey && !e.altKey) basculerIci(e);
      }, true);
      // Hors d'une page de vidéo, la vidéo reprend sa place (sinon elle couvrirait l'accueil).
      setInterval(function(){ if (racine() && racine().classList.contains('side-plein') && location.pathname.indexOf('/watch') !== 0) window.__sideSortir(); }, 500);
    })();
    """

    /// Pour les sites autres que YouTube : la page se croit toujours affichée, pour que la musique continue tiroir fermé.
    static let scriptToujoursAffiche = """
    (function(){
      try {
        ['hidden','webkitHidden'].forEach(function(n){ Object.defineProperty(Document.prototype, n, { configurable: true, get: function(){ return false; } }); });
        ['visibilityState','webkitVisibilityState'].forEach(function(n){ Object.defineProperty(Document.prototype, n, { configurable: true, get: function(){ return 'visible'; } }); });
        var taire = function(e){ if (e.target === window || e.target === document) e.stopImmediatePropagation(); };
        ['visibilitychange','webkitvisibilitychange','freeze'].forEach(function(n){ window.addEventListener(n, taire, true); document.addEventListener(n, taire, true); });
      } catch (e) {}
    })();
    """

    /// Coupe les publicités de YouTube dans la tuile, comme le fait Brave :
    /// 1) la liste des publicités est retirée des réponses de YouTube avant que le lecteur ne les lise ;
    /// 2) si une publicité démarre quand même, elle est avancée à sa fin et le bouton « Ignorer » est pressé ;
    /// 3) les encarts publicitaires de la page sont masqués.
    /// YouTube change régulièrement sa page : si les publicités reviennent, c'est ici qu'il faut ajuster.
    static let scriptSansPub = """
    (function(){
      if (window.__sideSansPub) return; window.__sideSansPub = true;
      // Le site pour téléphone met la vidéo en pause dès que la page n'est plus affichée (panneau refermé).
      // Ici, la page se croit toujours affichée : la lecture continue, comme sur le site d'ordinateur.
      try {
        ['hidden','webkitHidden'].forEach(function(n){ Object.defineProperty(Document.prototype, n, { configurable: true, get: function(){ return false; } }); });
        ['visibilityState','webkitVisibilityState'].forEach(function(n){ Object.defineProperty(Document.prototype, n, { configurable: true, get: function(){ return 'visible'; } }); });
        var taire = function(e){ if (e.target === window || e.target === document) e.stopImmediatePropagation(); };
        ['visibilitychange','webkitvisibilitychange','pagehide','freeze','blur'].forEach(function(n){
          window.addEventListener(n, taire, true); document.addEventListener(n, taire, true); });
      } catch (e) {}
      // Le coupe-publicité est un réglage (Réglages > Tiroir > Multimédia), désactivé au départ.
      var couper = window.__sideCouperPubs === true;
      var cles = couper ? ['adPlacements','playerAds','adSlots','adBreakHeartbeatParams'] : [];
      function nettoyer(o){
        if (!o || typeof o !== 'object') return o;
        try {
          cles.forEach(function(k){ if (k in o) delete o[k]; });
          if (o.playerResponse && typeof o.playerResponse === 'object') cles.forEach(function(k){ if (k in o.playerResponse) delete o.playerResponse[k]; });
        } catch (e) {}
        return o;
      }
      var analyse = JSON.parse;
      JSON.parse = function(){ return nettoyer(analyse.apply(this, arguments)); };
      try {
        var lire = Response.prototype.json;
        Response.prototype.json = function(){ return lire.apply(this, arguments).then(nettoyer); };
      } catch (e) {}
      try {
        var reponse;
        Object.defineProperty(window, 'ytInitialPlayerResponse', { configurable: true,
          get: function(){ return reponse; }, set: function(v){ reponse = nettoyer(v); } });
      } catch (e) {}
      setInterval(function(){
        // YouTube réécrit parfois les classes de la page : celle qui masque les Shorts est remise si besoin.
        if (window.__sideSansShorts === true && document.documentElement && !document.documentElement.classList.contains('side-sans-shorts')) document.documentElement.classList.add('side-sans-shorts');
        var lecteur = document.getElementById('movie_player');
        if (couper && lecteur && lecteur.classList.contains('ad-showing')) {
          var v = lecteur.querySelector('video');
          if (v && isFinite(v.duration) && v.duration > 0 && v.currentTime < v.duration - 0.2) { v.muted = true; v.currentTime = v.duration; }
          var b = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-slot button');
          if (b) b.click();
        }
      }, 300);
      function masquer(){ if (document.getElementById('side-sans-pub') || !document.documentElement) return;
        var s = document.createElement('style'); s.id = 'side-sans-pub';
        s.textContent = (couper ? 'ytm-promoted-video-renderer,ytm-promoted-sparkles-web-renderer,ytm-companion-ad-renderer,ytm-companion-slot,ad-slot-renderer,ytm-statement-banner-renderer,.ytm-promoted-sparkles-text-search-renderer,ytm-item-section-renderer:has(ad-slot-renderer),ytm-rich-item-renderer:has(ad-slot-renderer),ytd-ad-slot-renderer,ytd-rich-item-renderer:has(ytd-ad-slot-renderer),ytd-promoted-sparkles-web-renderer,ytd-companion-slot-renderer,ytd-banner-promo-renderer,#player-ads,#masthead-ad{display:none!important}' : '')
          // Sur le site pour téléphone, YouTube épingle la vidéo en haut : ici, elle défile avec la page.
          + '#player-container-id.sticky-player{position:absolute!important}'
          // La rangée de petits onglets (Tous, Actualités, Podcasts…) est masquée, à l'accueil comme sous une vidéo.
          + 'ytm-feed-filter-chip-bar-renderer,ytm-related-chip-cloud-renderer,ytd-feed-filter-chip-bar-renderer,yt-related-chip-cloud-renderer,#header.ytd-rich-grid-renderer{display:none!important}'
          // … et la place qui leur était réservée au-dessus des vidéos est reprise.
          + '.rich-grid-renderer-contents.rich-grid-top-margin{margin-top:0!important}.rich-grid-renderer-header{display:none!important}'
          // Sur le site d'ordinateur, le voile sombre sous l'en-tête garde la hauteur de ces onglets : il reprend celle de l'en-tête seul.
          + '#frosted-glass.with-chipbar{height:56px!important}'
          // La vidéo a des coins arrondis, comme sur le site de YouTube (sauf en plein écran).
          // (Une découpe, et non un « overflow » : la vidéo est dessinée à part par le Mac, et l'overflow la faisait disparaître.)
          + 'html:not(.side-plein) ytd-watch-flexy #movie_player{clip-path:inset(0 round 12px)!important}'
          // Les Shorts, masqués quand le réglage le demande (la classe se pose et se retire sans recharger la page).
          + 'html.side-sans-shorts ytd-reel-shelf-renderer,html.side-sans-shorts ytd-rich-shelf-renderer[is-shorts],html.side-sans-shorts ytd-rich-section-renderer:has(ytd-rich-shelf-renderer[is-shorts]),'
          + 'html.side-sans-shorts ytd-rich-section-renderer:has(ytm-shorts-lockup-view-model),html.side-sans-shorts grid-shelf-view-model:has(ytm-shorts-lockup-view-model),'
          + 'html.side-sans-shorts ytd-rich-item-renderer:has(a[href^="/shorts/"]),html.side-sans-shorts ytd-video-renderer:has(a[href^="/shorts/"]),'
          + 'html.side-sans-shorts ytd-grid-video-renderer:has(a[href^="/shorts/"]),html.side-sans-shorts ytd-compact-video-renderer:has(a[href^="/shorts/"]),'
          + 'html.side-sans-shorts yt-lockup-view-model:has(a[href^="/shorts/"]),html.side-sans-shorts ytm-shorts-lockup-view-model,'
          + 'html.side-sans-shorts ytd-guide-entry-renderer:has(a[title="Shorts"]),html.side-sans-shorts ytd-mini-guide-entry-renderer[aria-label="Shorts"],'
          + 'html.side-sans-shorts yt-tab-shape[tab-title="Shorts"]{display:none!important}';
        if (window.__sideSansShorts === true) document.documentElement.classList.add('side-sans-shorts');
        document.documentElement.appendChild(s); }
      masquer(); document.addEventListener('DOMContentLoaded', masquer);
    })();
    """

    @objc private func pleinCadre() { js("window.__sideBasculer && window.__sideBasculer()") }

    /// Le réglage « Masquer les Shorts » change : la page suit tout de suite.
    func appliquerShorts(_ masquer: Bool) {
        guard estYouTube else { return }
        js("document.documentElement.classList.toggle('side-sans-shorts', \(masquer ? "true" : "false")); window.__sideSansShorts = \(masquer ? "true" : "false");")
    }
    var estUnYouTube: Bool { estYouTube }
    /// La vidéo en cours passe en plein écran, ou revient dans le tiroir (raccourci, commande d'une autre app).
    func basculerPleinEcran() {
        if fenetreVideo != nil { rentrerDansLeTiroir() } else { pleinCadre() }
    }
    var adresseEnCours: String { page.url?.absoluteString ?? "" }
    /// Pour les essais : note dans le journal si la vidéo est en pause.
    func noterEtat() {
        page.evaluateJavaScript("(function(){var v=document.querySelector('video');return v?(v.paused?'en pause':'en lecture'):'aucune vidéo'})()") { r, _ in
            journalBas("YouTube : vidéo %@", (r as? String) ?? "?")
        }
    }

    // MARK: Plein écran : la page sort du tiroir dans une fenêtre qui remplit l'écran (sans le plein écran d'Apple)

    /// La fenêtre de la vidéo en grand. C'est une fenêtre ordinaire : Square la range dans sa grille comme celle d'une application
    /// (Side lui donne son numéro dans le réglage `videoPleinEcran`, que Square relit).
    private var fenetreVideo: NSWindow?
    private var suggestions = false
    /// Le bouton en haut à droite de la fenêtre : montre ou cache la colonne des vidéos suivantes, comme sur le site de YouTube.
    private func boutonSuggestions() -> NSTitlebarAccessoryViewController {
        let b = NSButton(image: NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: String(localized: "Vidéos suivantes")) ?? NSImage(),
                         target: self, action: #selector(basculerSuggestions))
        b.isBordered = false
        b.contentTintColor = NSColor(white: 1, alpha: 0.85)
        b.symbolConfiguration = .init(pointSize: 15, weight: .medium)
        b.toolTip = String(localized: "Vidéos suivantes")
        b.frame = NSRect(x: 0, y: 0, width: 44, height: 28)
        let conteneur = NSView(frame: NSRect(x: 0, y: 0, width: 52, height: 28))
        b.frame.origin = NSPoint(x: 0, y: 0)
        conteneur.addSubview(b)
        let c = NSTitlebarAccessoryViewController()
        c.view = conteneur
        c.layoutAttribute = .trailing
        return c
    }
    @objc private func basculerSuggestions() {
        suggestions.toggle()
        js("document.documentElement.classList.toggle('side-suggestions', \(suggestions ? "true" : "false")); window.dispatchEvent(new Event('resize'));")
    }

    /// Ce qui reste dans la tuile pendant ce temps : un mot, et un bouton pour ramener la vidéo.
    private var attente: NSView?
    private var suiviTitre: NSKeyValueObservation?
    private var ecouteEchap: Any?
    static let cleFenetreVideo = "videoPleinEcran"

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "sidePlein", let entre = message.body as? Bool else { return }
        if entre { sortirEnGrand() } else { rentrerDansLeTiroir() }
    }

    private func sortirEnGrand() {
        guard fenetreVideo == nil, let ecran = window?.screen ?? NSScreen.main else { return }
        let w = NSWindow(contentRect: ecran.visibleFrame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = page.title?.isEmpty == false ? page.title! : "YouTube"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.backgroundColor = .black
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.appearance = NSAppearance(named: .darkAqua)
        w.addTitlebarAccessoryViewController(boutonSuggestions())
        w.setFrame(ecran.visibleFrame, display: false)
        // Le même lecteur change de fenêtre : la lecture ne s'interrompt pas.
        page.removeFromSuperview()
        page.frame = w.contentView?.bounds ?? .zero
        page.autoresizingMask = [.width, .height]
        w.contentView?.addSubview(page)
        fenetreVideo = w
        suiviTitre = page.observe(\.title) { [weak w] p, _ in if let t = p.title, !t.isEmpty { w?.title = t } }
        // Échap ramène la vidéo dans le tiroir (YouTube attend que le navigateur s'en charge).
        ecouteEchap = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == 53, let self, let w = self.fenetreVideo, e.window === w else { return e }
            self.rentrerDansLeTiroir()
            return nil
        }
        montrerAttente()
        PanneauBas.commun.fermerPourLaVideo()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(page)
        // En plein écran, YouTube laisse défiler ses commentaires par-dessus la vidéo : on repart du haut.
        let enHaut = "window.scrollTo(0,0);document.querySelectorAll('ytd-app,#page-manager,ytd-watch-flexy').forEach(function(e){e.scrollTop=0})"
        js(enHaut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.js(enHaut) }
        UserDefaults.standard.set(w.windowNumber, forKey: Self.cleFenetreVideo)
        journalBas("YouTube : vidéo sortie en plein écran (fenêtre %d)", w.windowNumber)
    }

    /// La vidéo reprend sa place dans la tuile. Appelé par YouTube (Échap, bouton plein écran), par le bouton de la tuile,
    /// ou quand on ferme la fenêtre.
    @objc func rentrerDansLeTiroir() {
        guard let w = fenetreVideo else { return }
        fenetreVideo = nil
        suiviTitre = nil
        if let ecouteEchap { NSEvent.removeMonitor(ecouteEchap) }
        ecouteEchap = nil
        UserDefaults.standard.removeObject(forKey: Self.cleFenetreVideo)
        page.removeFromSuperview()
        page.autoresizingMask = []
        addSubview(page, positioned: .below, relativeTo: barre)
        attente?.removeFromSuperview()
        attente = nil
        needsLayout = true
        w.delegate = nil
        w.orderOut(nil)
        suggestions = false
        js("document.documentElement.classList.remove('side-suggestions'); window.__sideSortir && window.__sideSortir()")      // YouTube reprend sa présentation normale
        journalBas("YouTube : vidéo revenue dans le tiroir")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        rentrerDansLeTiroir()
        return false
    }

    private func montrerAttente() {
        let v = NSView(frame: bounds)
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor
        let image = NSImageView(image: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil) ?? NSImage())
        image.symbolConfiguration = .init(pointSize: 30, weight: .regular)
        image.contentTintColor = NSColor(white: 1, alpha: 0.45)
        let texte = NSTextField(labelWithString: String(localized: "La vidéo est en plein écran"))
        texte.font = .systemFont(ofSize: 15, weight: .semibold)
        texte.textColor = NSColor(white: 1, alpha: 0.85)
        let b = NSButton(title: String(localized: "Ramener dans le tiroir"), target: self, action: #selector(rentrerDansLeTiroir))
        b.bezelStyle = .rounded
        b.controlSize = .large
        let voir = NSButton(title: String(localized: "Afficher la vidéo"), target: self, action: #selector(montrerLaVideo))
        voir.bezelStyle = .rounded
        voir.controlSize = .large
        let boutons = NSStackView(views: [voir, b])
        boutons.spacing = 10
        let pile = NSStackView(views: [image, texte, boutons])
        pile.orientation = .vertical
        pile.spacing = 12
        pile.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(pile)
        pile.centerXAnchor.constraint(equalTo: v.centerXAnchor).isActive = true
        pile.centerYAnchor.constraint(equalTo: v.centerYAnchor).isActive = true
        addSubview(v)
        attente = v
    }

    /// Depuis la tuile : la fenêtre de la vidéo repasse devant, et le tiroir se referme.
    @objc private func montrerLaVideo() {
        guard let w = fenetreVideo else { return }
        PanneauBas.commun.fermerPourLaVideo()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func js(_ code: String) { page.evaluateJavaScript(code, completionHandler: nil) }

    @objc private func lecturePause() {
        js("(function(){var v=document.querySelector('video');if(v){if(v.paused){v.play()}else{v.pause()}}})()")
    }
    @objc private func reculerDansLaVidéo() { js("(function(){var v=document.querySelector('video');if(v){v.currentTime=Math.max(0,v.currentTime-10)}})()") }
    @objc private func avancerDansLaVidéo() { js("(function(){var v=document.querySelector('video');if(v){v.currentTime=v.currentTime+10}})()") }

    /// Appuie à votre place sur le bouton « Ignorer » de YouTube, s'il est affiché. Une publicité que YouTube
    /// n'autorise pas à passer ne peut pas l'être : dans ce cas, un bip.
    @objc private func passerLaPub() {
        let code = """
        (function(){var b=document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-slot button, [id^="skip-button"] button, button[class*="skip"]');
        if(b){b.click();return true}return false})()
        """
        page.evaluateJavaScript(code) { r, _ in if (r as? Bool) != true { NSSound.beep() } }
    }

    /// La double flèche : passe d'un coup de la tuile large à la tuile étroite, et retour.
    @objc private func changerLargeur() {
        let étaitLarge = large
        largeur = étaitLarge ? LecteurYouTubeBas.largeurEtroite : LecteurYouTubeBas.largeurLarge
        auChangementDeLargeur?()
        suivreLaLargeur(étaitLarge: étaitLarge)
    }

    /// La tuile a franchi la limite entre large et étroite : on change de site (ordinateur ou téléphone).
    /// La page en cours est rechargée, et la vidéo reprend où elle en était. Sinon, la page s'adapte toute seule.
    private func suivreLaLargeur(étaitLarge: Bool) {
        guard large != étaitLarge else { return }
        page.customUserAgent = large ? safariMac : safariIPhone
        guard chargée, let enCours = page.url else { return }
        page.evaluateJavaScript("(function(){var v=document.querySelector('video');return v?Math.floor(v.currentTime):0})()") { [weak self] r, _ in
            guard let self, var c = URLComponents(url: enCours, resolvingAgainstBaseURL: false) else { return }
            if enCours.path.hasPrefix("/watch"), let t = r as? Int, t > 5 {
                c.queryItems = (c.queryItems ?? []).filter { $0.name != "t" } + [URLQueryItem(name: "t", value: "\(t)s")]
            }
            self.ouvrir(c.url ?? enCours)
        }
    }

    // MARK: Navigation : YouTube et la connexion Google restent dans la tuile, le reste part dans le navigateur

    private func resteIci(_ url: URL) -> Bool {
        guard estYouTube, let hote = url.host?.lowercased() else { return true }      // un autre site navigue librement (connexion comprise)
        return ["youtube.com", "youtu.be", "google.com", "google.fr", "gstatic.com", "googleusercontent.com", "youtube-nocookie.com"]
            .contains { hote == $0 || hote.hasSuffix("." + $0) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.allow); return }
        let schema = url.scheme?.lowercased() ?? ""
        // « Ouvrir dans l'application » et autres liens qui ne sont pas des pages : ignorés.
        guard ["http", "https", "about", "blob", "data"].contains(schema) else { decisionHandler(.cancel); return }
        if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame != false, !resteIci(url) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// Un lien qui voudrait ouvrir une nouvelle fenêtre : il s'ouvre dans la tuile (YouTube, Google) ou dans le navigateur.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if resteIci(url) { webView.load(action.request) } else { NSWorkspace.shared.open(url) }
        }
        return nil
    }
}

/// Le petit sélecteur au-dessus du coin multimédia : un bouton par élément (Spotify, YouTube, un site ajouté…), un seul affiché.
final class ChoixMediaBas: NSView {
    var auChoix: ((String) -> Void)?
    /// Clic droit : retirer un lecteur, en ajouter un, ouvrir les réglages. Glisser : changer l'ordre.
    var auRetrait: ((String) -> Void)?
    var auAjout: ((MediaBas) -> Void)?
    var auxReglages: (() -> Void)?
    var auNouvelOrdre: (([String]) -> Void)?
    private var boutons: [(String, BoutonBas)] = []
    private var cles: [String] = []
    var choisi = "" { didSet { peindre() } }
    // Le lecteur qu'on est en train de glisser pour le changer de place.
    private var prise: Int?
    private var priseEn: CGFloat = 0
    private var decalage: CGFloat = 0
    private var glisse = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    /// (Re)construit les boutons quand la liste a changé.
    func montrer(_ elements: [(cle: String, nom: String)], choisi: String) {
        if elements.map({ $0.cle + "|" + $0.nom }) != cles {
            cles = elements.map { $0.cle + "|" + $0.nom }
            boutons.forEach { $0.1.removeFromSuperview() }
            boutons = elements.map { e in
                let b = BoutonBas(title: e.nom, target: nil, action: nil)
                b.isBordered = false
                b.wantsLayer = true
                b.layer?.cornerRadius = 7
                b.identifier = NSUserInterfaceItemIdentifier(e.cle)
                addSubview(b)
                return (e.cle, b)
            }
            needsLayout = true
        }
        self.choisi = choisi
    }

    private func peindre() {
        for (cle, b) in boutons {
            let actif = cle == choisi
            b.layer?.backgroundColor = actif ? NSColor(white: 1, alpha: 0.16).cgColor : NSColor.clear.cgColor
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [
                .foregroundColor: actif ? NSColor.white : NSColor(white: 1, alpha: 0.55),
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        }
    }

    private var largeurBouton: CGFloat { (bounds.width - 4 * (CGFloat(boutons.count) + 1)) / CGFloat(max(boutons.count, 1)) }
    private func cadre(_ i: Int) -> NSRect {
        NSRect(x: 4 + CGFloat(i) * (largeurBouton + 4), y: 4, width: largeurBouton, height: bounds.height - 8)
    }

    override func layout() {
        super.layout()
        // Le lecteur qu'on glisse suit la souris ; les autres tiennent leur rang.
        for (i, (_, b)) in boutons.enumerated() where !(glisse && i == prise) { b.frame = cadre(i) }
    }

    // La barre reçoit elle-même les clics (les boutons ne servent qu'à l'affichage) : elle distingue ainsi le clic, le glisser et le clic droit.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let s = superview else { return nil }
        return bounds.contains(convert(point, from: s)) ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func rang(_ x: CGFloat) -> Int? {
        guard !boutons.isEmpty else { return nil }
        return min(max(Int((x - 2) / (largeurBouton + 4)), 0), boutons.count - 1)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        prise = rang(p.x)
        priseEn = p.x
        glisse = false
        if let i = prise { decalage = p.x - cadre(i).minX }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var i = prise, boutons.count > 1 else { return }
        let p = convert(event.locationInWindow, from: nil)
        if !glisse {
            guard abs(p.x - priseEn) > 6 else { return }
            glisse = true
            boutons[i].1.layer?.zPosition = 5
        }
        // Le bouton suit la souris, sans sortir de la barre.
        var r = cadre(i)
        r.origin.x = min(max(p.x - decalage, 4), bounds.width - 4 - r.width)
        boutons[i].1.frame = r
        // Quand son milieu passe sur un autre rang, il prend ce rang et les autres se poussent, en douceur.
        if let cible = rang(r.midX), cible != i {
            let b = boutons.remove(at: i)
            boutons.insert(b, at: cible)
            i = cible
            prise = cible
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                for (k, (_, autre)) in boutons.enumerated() where k != cible { autre.animator().frame = cadre(k) }
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { prise = nil; glisse = false }
        guard let i = prise, boutons.indices.contains(i) else { return }
        if glisse {
            // Lâché : il se pose à son rang, et le nouvel ordre est retenu.
            let b = boutons[i].1
            b.layer?.zPosition = 0
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.15; b.animator().frame = cadre(i) })
            cles = []                                   // la liste sera relue à la prochaine mise à jour
            auNouvelOrdre?(boutons.map { $0.0 })
            return
        }
        let cle = boutons[i].0
        guard cle != choisi else { return }
        choisi = cle
        auChoix?(cle)
    }

    /// Clic droit : retirer ce lecteur, en ajouter un autre (les mêmes propositions que dans les réglages), ou ouvrir les réglages.
    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()
        if let i = rang(p.x) {
            let retirer = menu.addItem(withTitle: String(localized: "Retirer \(boutons[i].1.title)"), action: #selector(retirer(_:)), keyEquivalent: "")
            retirer.target = self
            retirer.representedObject = boutons[i].0
            menu.addItem(.separator())
        }
        let presents = Set(boutons.map { $0.0 })
        let ajout = NSMenu()
        for m in MediaBas.proposes where !presents.contains(m.id) {
            let ligne = ajout.addItem(withTitle: m.nom, action: #selector(ajouter(_:)), keyEquivalent: "")
            ligne.target = self
            ligne.representedObject = m.id
        }
        if ajout.items.isEmpty == false { ajout.addItem(.separator()) }
        let site = ajout.addItem(withTitle: String(localized: "Un autre site web…"), action: #selector(reglages), keyEquivalent: "")
        site.target = self
        let parent = menu.addItem(withTitle: String(localized: "Ajouter un lecteur"), action: nil, keyEquivalent: "")
        parent.submenu = ajout
        menu.addItem(.separator())
        let reglage = menu.addItem(withTitle: String(localized: "Réglages du tiroir…"), action: #selector(reglages), keyEquivalent: "")
        reglage.target = self
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func retirer(_ ligne: NSMenuItem) { if let cle = ligne.representedObject as? String { auRetrait?(cle) } }
    @objc private func ajouter(_ ligne: NSMenuItem) {
        if let cle = ligne.representedObject as? String, let m = MediaBas.proposes.first(where: { $0.id == cle }) { auAjout?(m) }
    }
    @objc private func reglages() { auxReglages?() }
}
