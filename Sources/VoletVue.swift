// Le volet d'une vue d'Horizon (17/11/2026) : un coin actif fait glisser, depuis le bord de l'écran de ce côté, une des
// petites applications « Horizon Vues » (Aujourd'hui, CRM, un projet…). Elle prend toute la hauteur ; on règle sa largeur
// en tirant son bord, comme n'importe quelle fenêtre, et Side s'en souvient. Elle repart quand la souris la quitte, quand
// on clique dans une autre application, ou avec Échap.
//
// Comme pour le tiroir, c'est la vraie fenêtre de l'application : entre deux usages, elle attend hors de l'écran. Le
// glissement se fait avec sa photo (déplacer la vraie fenêtre image par image saccaderait), remplacée par la fenêtre à l'arrivée.
import AppKit
import Carbon.HIToolbox

final class VoletVue: NSObject, ObservableObject {
    static let commun = VoletVue()

    // MARK: Réglages (une clé UserDefaults n'appartient qu'à ce fichier)

    /// L'application que montre chaque coin : nom du coin → chemin de l'application.
    @Published var coins: [String: String] = (UserDefaults.standard.dictionary(forKey: "voletVueCoins") as? [String: String]) ?? [:] {
        didSet { UserDefaults.standard.set(coins, forKey: "voletVueCoins"); préparer() }
    }
    /// La largeur laissée à chaque application.
    private var largeurs: [String: Double] {
        get { (UserDefaults.standard.dictionary(forKey: "voletVueLargeurs") as? [String: Double]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "voletVueLargeurs") }
    }

    func chemin(_ c: Coin) -> String? { coins[c.rawValue] }
    func régler(_ c: Coin, chemin: String?) {
        var d = coins
        d[c.rawValue] = chemin
        coins = d
    }

    // MARK: État

    private struct Ouvert {
        let coin: Coin, chemin: String, bundle: String
        var cadre: NSRect            // la place du volet, en coordonnées de l'écran (origine en bas à gauche)
        var arrivé = false
    }
    private var ouvert: Ouvert?
    private var tour = 0                              // chaque ouverture ou fermeture a son numéro : une animation dépassée ne fait rien
    private var armés: [Coin: Bool] = [:]
    private var débuts: [Coin: Date] = [:]
    private var horsDepuis: Date?
    private var avant: NSRunningApplication?          // l'application de devant à l'ouverture : elle reprend la main à la fermeture
    private var panneau: NSPanel?
    private let image = NSImageView()
    private let idEchap: UInt32 = 77
    /// Les numéros des fenêtres du volet : le plein écran de Side ne les agrandit pas (voir PanneauBas.publierFenêtres).
    private(set) var numéros: [Int] = []

    private func gauche(_ c: Coin) -> Bool { c == .hautGauche || c == .basGauche }

    // MARK: Démarrage et fin

    /// Au lancement de Side, et quand un coin change : les applications des coins sont lancées et rangées hors de l'écran,
    /// pour arriver tout de suite au premier appel.
    func brancher() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivée(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        préparer()
    }

    private func préparer() {
        for chemin in Set(coins.values) where chemin != ouvert?.chemin {
            guard let bundle = Bundle(path: chemin)?.bundleIdentifier else { continue }
            if app(bundle) == nil { lancer(chemin, devant: false) }
            ranger(bundle, essais: 80)
        }
    }

    /// Side quitte : les fenêtres rangées hors de l'écran reviennent, sinon elles resteraient invisibles.
    func rendreLesFenêtres() {
        for chemin in Set(coins.values) {
            guard let bundle = Bundle(path: chemin)?.bundleIdentifier, let f = fenêtre(bundle), let c = AXBas.cadre(f),
                  c.minX >= Ecrans.bordGarage - 2, let e = NSScreen.screens.first else { continue }
            let z = Ecrans.versAX(e.visibleFrame)
            AXBas.placer(f, CGRect(x: z.minX + 40, y: z.minY + 40, width: c.width, height: min(c.height, z.height - 80)))
        }
    }

    // MARK: L'application et sa fenêtre

    private func app(_ bundle: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first { !$0.isTerminated }
    }

    private func lancer(_ chemin: String, devant: Bool) {
        let c = NSWorkspace.OpenConfiguration()
        c.activates = devant
        c.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: chemin), configuration: c, completionHandler: nil)
    }

    /// La fenêtre de travail de l'application (pas une boîte de dialogue).
    private func fenêtre(_ bundle: String) -> AXUIElement? {
        guard let a = app(bundle) else { return nil }
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXWindowsAttribute as CFString, &v)
        let toutes = (v as? [AXUIElement]) ?? []
        return toutes.first { f in
            var s: CFTypeRef?
            AXUIElementCopyAttributeValue(f, kAXSubroleAttribute as CFString, &s)
            return (s as? String) == (kAXStandardWindowSubrole as String)
        } ?? toutes.first
    }

    private func numéro(_ f: AXUIElement) -> CGWindowID {
        var id: CGWindowID = 0
        _ = _AXUIElementGetWindow(f, &id)
        return id
    }

    /// Note le numéro de la fenêtre : le plein écran de Side la laisse à sa taille.
    private func noter(_ f: AXUIElement) {
        let n = Int(numéro(f))
        guard n != 0, !numéros.contains(n) else { return }
        numéros.append(n)
        PanneauBas.commun.publierFenêtres()
    }

    /// Range la fenêtre hors de l'écran dès qu'elle existe (l'application vient peut-être d'être lancée).
    private func ranger(_ bundle: String, essais: Int) {
        guard essais > 0, ouvert?.bundle != bundle else { return }
        if let f = fenêtre(bundle), let c = AXBas.cadre(f) {
            noter(f)
            if c.minX < Ecrans.bordGarage - 2 { AXBas.placer(f, Ecrans.garage(taille: c.size)) }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.ranger(bundle, essais: essais - 1) }
    }

    private func photo(_ f: AXUIElement) -> NSImage? {
        let id = numéro(f)
        guard CGPreflightScreenCaptureAccess(), id != 0,
              let cg = photoFenetreBas(.null, 8, id, 1 | 8)?.takeRetainedValue(), cg.width > 8 else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }

    // MARK: Les coins

    /// Appelé à chaque relevé de la souris, comme les autres coins actifs de Side.
    func surveillerCoin(_ p: NSPoint, _ e: NSScreen, taille: CGFloat) {
        surveillerSortie(p)
        for (nom, chemin) in coins {
            guard let coin = Coin(rawValue: nom), coin != .aucun else { continue }
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
            // Il faut ressortir du coin avant de pouvoir le déclencher de nouveau.
            if !dans(40) { armés[coin] = true; débuts[coin] = nil; continue }
            guard dans(0) else { débuts[coin] = nil; continue }
            guard armés[coin] ?? true, NSEvent.pressedMouseButtons == 0, !CaptureEcran.enCours else { continue }
            if débuts[coin] == nil { débuts[coin] = Date() }
            guard Date().timeIntervalSince(débuts[coin]!) >= 0.05 else { continue }
            armés[coin] = false
            débuts[coin] = nil
            journalBas("coin actif : volet de %@", (chemin as NSString).lastPathComponent)
            if ouvert?.coin == coin { fermer() } else { ouvrir(coin, chemin, sur: e) }
        }
    }

    /// La souris a quitté le volet depuis un moment : il repart. (Pas pendant qu'on tire son bord, ni avant son arrivée.)
    private func surveillerSortie(_ p: NSPoint) {
        guard let o = ouvert, o.arrivé else { horsDepuis = nil; return }
        var zone = o.cadre
        // La largeur a pu changer : on suit la vraie fenêtre.
        if let f = fenêtre(o.bundle), let c = AXBas.cadre(f) { zone = Ecrans.versNS(c); ouvert?.cadre = zone }
        // Toute la hauteur de l'écran compte (la barre des menus est au-dessus du volet), avec une marge sur le côté.
        let dedans = p.x >= zone.minX - 60 && p.x <= zone.maxX + 60
        guard !dedans, NSEvent.pressedMouseButtons == 0, !PanneauBas.menuOuvert else { horsDepuis = nil; return }
        if horsDepuis == nil { horsDepuis = Date() }
        if Date().timeIntervalSince(horsDepuis!) >= 0.6 { fermer() }
    }

    // MARK: Ouvrir

    private func cadreCible(_ chemin: String, _ coin: Coin, sur e: NSScreen) -> NSRect {
        let z = e.visibleFrame
        let w = min(max(CGFloat(largeurs[chemin] ?? 520), 380), (z.width * 0.8).rounded())
        return NSRect(x: gauche(coin) ? z.minX : z.maxX - w, y: z.minY, width: w, height: z.height)
    }

    private func horsÉcran(_ r: NSRect, _ coin: Coin, sur e: NSScreen) -> NSRect {
        var d = r
        d.origin.x = gauche(coin) ? e.frame.minX - r.width - 30 : e.frame.maxX + 30
        return d
    }

    private func montrerPhoto(_ img: NSImage?, icône chemin: String, à cadre: NSRect) {
        let p = panneau ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .floating
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            image.imageScaling = .scaleAxesIndependently
            image.wantsLayer = true
            image.layer?.cornerRadius = Rayon.carte
            image.layer?.cornerCurve = .continuous
            image.layer?.masksToBounds = true
            image.autoresizingMask = [.width, .height]
            p.contentView = image
            panneau = p
            return p
        }()
        // Sans photo (application pas encore ouverte, ou pas d'autorisation) : une carte claire avec son icône.
        image.image = img ?? NSImage(size: cadre.size, flipped: false) { r in
            NSColor.windowBackgroundColor.setFill()
            r.fill()
            let c: CGFloat = 96
            NSWorkspace.shared.icon(forFile: chemin).draw(in: NSRect(x: r.midX - c / 2, y: r.midY - c / 2, width: c, height: c))
            return true
        }
        p.setFrame(cadre, display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()
    }

    private func glisser(vers cadre: NSRect, fin: @escaping () -> Void) {
        guard let p = panneau else { fin(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Mouvement.duree(Mouvement.ample)
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            p.animator().setFrame(cadre, display: true)
        }, completionHandler: fin)
    }

    func ouvrir(_ coin: Coin, _ chemin: String, sur e: NSScreen) {
        guard let bundle = Bundle(path: chemin)?.bundleIdentifier else { return }
        if ouvert != nil { fermer(animé: false) }
        // Un seul volet à la fois sur le bord droit : le presse-papiers lui laisse la place.
        if !gauche(coin), VoletPresse.commun.ouvert { VoletPresse.commun.fermer() }
        tour += 1
        let monTour = tour
        avant = NSWorkspace.shared.frontmostApplication
        // Pas lancée : on la lance. Lancée mais sans fenêtre (elle a été fermée ou rangée) : la rouvrir lui en redonne une.
        if app(bundle) == nil { lancer(chemin, devant: false) } else if fenêtre(bundle) == nil { lancer(chemin, devant: true) }
        let cible = cadreCible(chemin, coin, sur: e)
        ouvert = Ouvert(coin: coin, chemin: chemin, bundle: bundle, cadre: cible)
        horsDepuis = nil
        // La fenêtre, encore hors de l'écran, prend déjà sa taille : sa photo est alors à la bonne proportion.
        let f = fenêtre(bundle)
        if let f {
            noter(f)
            AXBas.placer(f, Ecrans.garage(taille: cible.size))
        }
        montrerPhoto(f.flatMap { photo($0) }, icône: chemin, à: horsÉcran(cible, coin, sur: e))
        TouchesBas.ajouter(idEchap, touche: UInt32(kVK_Escape), modifs: 0) { [weak self] in self?.fermer() }
        glisser(vers: cible) { [weak self] in
            guard let self, self.tour == monTour else { return }
            self.poser(essais: 60, tour: monTour)
        }
    }

    /// Le volet est arrivé : la vraie fenêtre prend la place de sa photo (dès qu'elle existe, si l'application démarre).
    private func poser(essais: Int, tour monTour: Int) {
        guard tour == monTour, let o = ouvert else { return }
        guard let f = fenêtre(o.bundle) else {
            guard essais > 0 else { fermer(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.poser(essais: essais - 1, tour: monTour) }
            return
        }
        noter(f)
        AXBas.placer(f, Ecrans.versAX(o.cadre))
        app(o.bundle)?.activate(options: [])
        AXBas.lever(f)
        ouvert?.arrivé = true
        // Le temps que la fenêtre soit dessinée à sa place, puis la photo s'efface.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.tour == monTour, let p = self.panneau else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = Mouvement.duree(Mouvement.bref); p.animator().alphaValue = 0 }) {
                if self.tour == monTour { p.orderOut(nil) }
            }
        }
    }

    // MARK: Fermer

    func fermer(animé: Bool = true) {
        guard let o = ouvert else { return }
        ouvert = nil
        horsDepuis = nil
        tour += 1
        let monTour = tour
        TouchesBas.retirer(idEchap)
        guard let f = fenêtre(o.bundle), let c = AXBas.cadre(f), c.minX < Ecrans.bordGarage - 2 else {
            panneau?.orderOut(nil)
            return
        }
        // La largeur choisie en tirant le bord est gardée.
        if c.width >= 300 { var l = largeurs; l[o.chemin] = Double(c.width); largeurs = l }
        let place = Ecrans.versNS(c)
        if animé { montrerPhoto(photo(f), icône: o.chemin, à: place) }
        AXBas.placer(f, Ecrans.garage(taille: c.size))
        // L'application d'avant reprend la main, si c'est bien le volet qui l'avait.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == o.bundle, let avant, !avant.isTerminated { avant.activate(options: []) }
        guard animé, let e = NSScreen.screens.first(where: { $0.frame.intersects(place) }) ?? NSScreen.screens.first else {
            panneau?.orderOut(nil)
            return
        }
        glisser(vers: horsÉcran(place, o.coin, sur: e)) { [weak self] in
            guard let self, self.tour == monTour else { return }
            self.panneau?.orderOut(nil)
        }
    }

    /// Le presse-papiers s'ouvre sur le bord droit : un volet de vue ouvert de ce côté lui laisse la place.
    func laisserLeBordDroit() {
        if let o = ouvert, !gauche(o.coin) { fermer() }
    }

    /// Une autre application passe devant (un clic ailleurs, ⌘Tab) : le volet repart.
    @objc private func appActivée(_ note: Notification) {
        guard let o = ouvert, o.arrivé,
              let a = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              a.bundleIdentifier != o.bundle, a.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        avant = nil          // celle qu'on vient de choisir garde la main
        fermer()
    }
}
