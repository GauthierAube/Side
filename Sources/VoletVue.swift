// Le volet d'une vue d'Horizon (17/11/2026) : un coin actif fait glisser, depuis le bord de l'écran de ce côté, une des
// vues d'Horizon (Aujourd'hui, CRM, un projet…). Depuis le 20/11/2026, chaque vue est une fenêtre du seul Horizon, reconnue
// à son titre (voir VuesHorizon.swift), et non plus une petite application à part. Elle prend toute la hauteur ; on règle sa largeur
// en tirant son bord, comme n'importe quelle fenêtre, et Side s'en souvient. Elle repart quand la souris la quitte, quand
// on clique dans une autre application, ou avec Échap.
//
// Comme pour le tiroir, c'est la vraie fenêtre de l'application : entre deux usages, elle attend hors de l'écran. Le
// glissement se fait avec sa photo (déplacer la vraie fenêtre image par image saccaderait), remplacée par la fenêtre à l'arrivée.
import AppKit
import Carbon.HIToolbox
import Combine

final class VoletVue: NSObject, ObservableObject {
    static let commun = VoletVue()

    // MARK: Réglages (une clé UserDefaults n'appartient qu'à ce fichier)

    /// La vue que montre chaque coin : nom du coin → « horizon-vue://crm » (une vue d'Horizon), chemin d'une application,
    /// ou valeur d'un volet à plusieurs vues (« pile:gauche »). Les anciennes petites applications « Horizon Vues »
    /// sont converties au chargement (20/11/2026).
    @Published var coins: [String: String] = {
        let d = UserDefaults.standard
        let lus = (d.dictionary(forKey: "voletVueCoins") as? [String: String]) ?? [:]
        let migrés = lus.mapValues(VuesHorizon.migrer)
        if migrés != lus { d.set(migrés, forKey: "voletVueCoins") }
        if let l = d.dictionary(forKey: "voletVueLargeurs") as? [String: Double] {
            let m = Dictionary(l.map { (VuesHorizon.migrer($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
            if m.keys.sorted() != l.keys.sorted() { d.set(m, forKey: "voletVueLargeurs") }
        }
        return migrés
    }() {
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
        var pile: PileVues?          // le volet à plusieurs vues (gauche ou droit), nil pour une seule vue
        var gesteLibre = true        // le geste horizontal est au volet (pas à macOS pour changer de bureau)
        var cadre: NSRect            // la place du volet, en coordonnées de l'écran (origine en bas à gauche)
        var arrivé = false
    }
    private var ouvert: Ouvert?
    /// Le volet est-il ouvert (ou en train de s'ouvrir) ? Le tiroir laisse alors passer Horizon appelé par le volet.
    var estOuvert: Bool { ouvert != nil }
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

    /// Le volet ouvert est un volet à plusieurs vues, et le pointeur est dessus : le geste horizontal à quatre doigts
    /// est pour lui (voir Glisse.recevoir). Écrit sur le fil principal à chaque relevé de la souris, lu hors du fil principal.
    static var pointeurSurPile = false

    // MARK: Démarrage et fin

    /// Au lancement de Side, et quand un coin change : les applications des coins sont lancées et rangées hors de l'écran,
    /// pour arriver tout de suite au premier appel.
    func brancher() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivée(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        préparer()
        // Pour les essais : un geste fabriqué, sans trackpad (objet « 1 » : vue suivante, « -1 » : précédente).
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(essaiGeste(_:)),
                                                            name: .init("com.gauthieraube.side.essai-cartes"), object: nil)
        // La liste d'un volet change (réglages) : ses applications sont lancées et rangées à leur tour.
        suivis = [PileVues.gauche, PileVues.droite].map {
            $0.$vues.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.préparer() }
        }
    }
    private var suivis: [AnyCancellable] = []

    /// Les applications à garder prêtes : celles des coins, plus toutes celles des volets à plusieurs vues qui ont un coin.
    private var tousLesChemins: Set<String> {
        var s = Set(coins.values)
        for pile in [PileVues.gauche, PileVues.droite] where s.remove(pile.sentinelle) != nil { s.formUnion(pile.vues) }
        return s
    }

    /// Les applications rangées par Side jusqu'ici : celles qui sortent des réglages retrouvent leur fenêtre.
    private var connus: Set<String> = []

    /// Les applications sorties des réglages, sauf celle affichée dans le volet (elle reviendra quand il se fermera).
    static func retirées(avant: Set<String>, après: Set<String>, affiché: String?) -> Set<String> {
        avant.subtracting(après).subtracting([affiché].compactMap { $0 })
    }

    /// Le geste horizontal est-il au volet ? Avec plusieurs bureaux sur l'écran, c'est macOS qui glisse d'un bureau
    /// à l'autre (même règle que le carrousel de Square), sauf si Square prend toujours le geste.
    static func gesteLibre(bureaux: Int, toujours: Bool, systèmeLibre: Bool) -> Bool {
        bureaux <= 1 || toujours || systèmeLibre
    }

    private func préparer() {
        let tous = tousLesChemins
        rendre(VoletVue.retirées(avant: connus, après: tous, affiché: ouvert?.chemin))
        connus = tous.union(Set([ouvert?.chemin].compactMap { $0 }).intersection(connus))
        for chemin in tous where chemin != ouvert?.chemin {
            guard let bundle = bundleDe(chemin) else { continue }
            // Une vue d'Horizon n'existe qu'une fois sa fenêtre ouverte, même quand Horizon tourne déjà.
            if app(bundle) == nil || (VuesHorizon.estUneVue(chemin) && fenêtre(chemin) == nil) { lancer(chemin, devant: false) }
            ranger(chemin, essais: 80)
        }
    }

    /// Side quitte : les fenêtres rangées hors de l'écran reviennent, sinon elles resteraient invisibles.
    func rendreLesFenêtres() { rendre(tousLesChemins) }

    /// Les fenêtres de ces applications reviennent de hors de l'écran (Side quitte, ou elles ne sont plus dans les réglages).
    private func rendre(_ chemins: Set<String>) {
        for chemin in chemins {
            guard let f = fenêtre(chemin), let c = AXBas.cadre(f),
                  c.minX >= Ecrans.bordGarage - 2, let e = NSScreen.screens.first else { continue }
            let z = Ecrans.versAX(e.visibleFrame)
            AXBas.placer(f, CGRect(x: z.minX + 40, y: z.minY + 40, width: c.width, height: min(c.height, z.height - 80)))
        }
    }

    // MARK: L'application et sa fenêtre

    private func app(_ bundle: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first { !$0.isTerminated }
    }

    /// L'identifiant de l'application : Horizon pour une vue d'Horizon.
    private func bundleDe(_ chemin: String) -> String? {
        VuesHorizon.estUneVue(chemin) ? VuesHorizon.bundle : Bundle(path: chemin)?.bundleIdentifier
    }

    /// Lance l'application ; pour une vue d'Horizon, ouvre (ou ramène) sa fenêtre dans Horizon.
    private func lancer(_ chemin: String, devant: Bool) {
        if VuesHorizon.estUneVue(chemin) { VuesHorizon.ouvrir(chemin, devant: devant); return }
        let c = NSWorkspace.OpenConfiguration()
        c.activates = devant
        c.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: chemin), configuration: c, completionHandler: nil)
    }

    /// La fenêtre de travail de l'application (pas une boîte de dialogue). Pour une vue d'Horizon, la fenêtre d'Horizon
    /// qui porte son titre ; pour Horizon lui-même, sa fenêtre principale, jamais celle d'une vue.
    private func fenêtre(_ chemin: String) -> AXUIElement? {
        if VuesHorizon.estUneVue(chemin) { return VuesHorizon.fenêtre(chemin) }
        guard let bundle = bundleDe(chemin), let a = app(bundle) else { return nil }
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXWindowsAttribute as CFString, &v)
        let toutes = (v as? [AXUIElement]) ?? []
        if bundle == VuesHorizon.bundle { return VuesHorizon.fenêtrePrincipale(parmi: toutes) }
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
    private func ranger(_ chemin: String, essais: Int) {
        // Par chemin, pas par application : plusieurs vues d'Horizon ont la même (20/11/2026).
        guard essais > 0, ouvert?.chemin != chemin else { return }
        if let f = fenêtre(chemin), let c = AXBas.cadre(f) {
            noter(f)
            if c.minX < Ecrans.bordGarage - 2 { AXBas.placer(f, Ecrans.garage(taille: c.size)) }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.ranger(chemin, essais: essais - 1) }
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
        guard let o = ouvert else { horsDepuis = nil; VoletVue.pointeurSurPile = false; return }
        guard o.arrivé else {
            horsDepuis = nil
            VoletVue.pointeurSurPile = o.pile != nil && o.gesteLibre && p.x >= o.cadre.minX && p.x <= o.cadre.maxX
            return
        }
        var zone = o.cadre
        // La largeur a pu changer : on suit la vraie fenêtre.
        if let f = fenêtre(o.chemin), let c = AXBas.cadre(f) {
            zone = Ecrans.versNS(c)
            // Plein écran (le bouton, ou un double-clic sur la barre du haut, que macOS gère lui-même) : la fenêtre a
            // grandi d'un coup. Le volet garde sa place d'avant, pour y revenir.
            let plein = VoletVue.estAgrandie(zone, volet: o.cadre)
            if plein != agrandi { agrandi = plein; journalBas(plein ? "volet en plein écran" : "volet revenu à sa place") }
            if !agrandi { ouvert?.cadre = zone }
            majBouton(zone)
        }
        if agrandi {
            // En plein écran, la vue reste jusqu'à ce qu'on la réduise (bouton, double-clic, Échap) ou qu'on change d'app.
            horsDepuis = nil
            VoletVue.pointeurSurPile = false
            PointsPile.commun.cacher()
            return
        }
        VoletVue.pointeurSurPile = o.pile != nil && o.gesteLibre && p.x >= zone.minX && p.x <= zone.maxX
        // Toute la hauteur de l'écran compte (la barre des menus est au-dessus du volet), avec une marge sur le côté.
        let dedans = p.x >= zone.minX - 60 && p.x <= zone.maxX + 60
        guard !dedans, NSEvent.pressedMouseButtons == 0, !PanneauBas.menuOuvert else { horsDepuis = nil; return }
        if horsDepuis == nil { horsDepuis = Date() }
        if Date().timeIntervalSince(horsDepuis!) >= 0.6 { fermer() }
    }

    // MARK: Ouvrir

    private func cadreCible(_ chemin: String, _ coin: Coin, pile: PileVues?, sur e: NSScreen) -> NSRect {
        let z = e.visibleFrame
        let voulue = pile?.largeur ?? (largeurs[chemin] ?? 520)
        let w = min(max(CGFloat(voulue), 380), (z.width * 0.8).rounded())
        let r = NSRect(x: gauche(coin) ? z.minX : z.maxX - w, y: z.minY, width: w, height: z.height)
        return pile == nil ? r : VoletVue.flottant(r, droite: !gauche(coin))
    }

    private func horsÉcran(_ r: NSRect, _ coin: Coin, sur e: NSScreen) -> NSRect {
        var d = r
        d.origin.x = gauche(coin) ? e.frame.minX - r.width - 30 : e.frame.maxX + 30
        return d
    }

    /// Le calque qui porte la photo d'une fenêtre pendant un glissement. Le second ne sert qu'au changement de page
    /// du volet de gauche : la vue qui arrive glisse à côté de celle qui part.
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
        image.image = img ?? carteIcône(chemin, cadre.size)
        p.setFrame(cadre, display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()
    }

    /// Sans photo (application pas encore ouverte, ou pas d'autorisation) : une carte claire avec son icône.
    private func carteIcône(_ chemin: String, _ taille: NSSize) -> NSImage {
        NSImage(size: taille, flipped: false) { r in
            NSColor.windowBackgroundColor.setFill()
            r.fill()
            let c: CGFloat = 96
            VuesHorizon.icône(chemin).draw(in: NSRect(x: r.midX - c / 2, y: r.midY - c / 2, width: c, height: c))
            return true
        }
    }

    private func glisser(vers cadre: NSRect, fin: @escaping () -> Void) {
        guard let p = panneau else { fin(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Mouvement.duree(Mouvement.ample)
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            p.animator().setFrame(cadre, display: true)
        }, completionHandler: fin)
    }

    func ouvrir(_ coin: Coin, _ demandé: String, sur e: NSScreen) {
        let pile = PileVues.pour(demandé)
        guard let chemin = pile.map({ $0.cheminCourant }) ?? demandé, let bundle = bundleDe(chemin) else { return }
        if ouvert != nil { fermer(animé: false) }
        // Un seul volet à la fois sur le bord droit : le presse-papiers lui laisse la place.
        if !gauche(coin), VoletPresse.commun.ouvert { VoletPresse.commun.fermer() }
        tour += 1
        let monTour = tour
        avant = NSWorkspace.shared.frontmostApplication
        // Pas lancée : on la lance. Lancée mais sans fenêtre (elle a été fermée ou rangée) : la rouvrir lui en redonne une.
        if app(bundle) == nil { lancer(chemin, devant: false) } else if fenêtre(chemin) == nil { lancer(chemin, devant: true) }
        let cible = cadreCible(chemin, coin, pile: pile, sur: e)
        ouvert = Ouvert(coin: coin, chemin: chemin, bundle: bundle, pile: pile, cadre: cible)
        horsDepuis = nil
        // La fenêtre, encore hors de l'écran, prend déjà sa taille : sa photo est alors à la bonne proportion.
        let f = fenêtre(chemin)
        if let f {
            noter(f)
            AXBas.placer(f, Ecrans.garage(taille: cible.size))
        }
        montrerPhoto(f.flatMap { photo($0) }, icône: chemin, à: horsÉcran(cible, coin, sur: e))
        TouchesBas.ajouter(idEchap, touche: UInt32(kVK_Escape), modifs: 0) { [weak self] in self?.échap() }
        glisser(vers: cible) { [weak self] in
            guard let self, self.tour == monTour else { return }
            self.poser(essais: 60, tour: monTour)
        }
    }

    /// Le volet est arrivé : la vraie fenêtre prend la place de sa photo (dès qu'elle existe, si l'application démarre).
    private func poser(essais: Int, tour monTour: Int, cartes: Bool? = nil) {
        guard tour == monTour, let o = ouvert else { return }
        guard let f = fenêtre(o.chemin) else {
            guard essais > 0 else { fermer(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.poser(essais: essais - 1, tour: monTour, cartes: cartes) }
            return
        }
        noter(f)
        AXBas.placer(f, Ecrans.versAX(o.cadre))
        // La vue d'abord devant les autres fenêtres d'Horizon, puis Horizon activé : seule elle remonte (20/11/2026).
        AXBas.lever(f)
        app(o.bundle)?.activate(options: [])
        AXBas.lever(f)
        ouvert?.arrivé = true
        if o.pile != nil, let e = NSScreen.screens.first(where: { $0.frame.intersects(o.cadre) }) {
            let id = Ecrans.identifiant(e)
            ouvert?.gesteLibre = VoletVue.gesteLibre(bureaux: Relevé.tout().0.filter { $0.ecran == id }.count,
                                                     toujours: UserDefaults.standard.bool(forKey: "glisseToujours"),
                                                     systèmeLibre: Glisse.systemeLibre)
        }
        if let pile = o.pile {
            PointsPile.commun.montrer(pile, au: o.cadre) { [weak self] i in self?.allerÀ(i) }
            photographierVoisines(tour: monTour)
        }
        // Le temps que la fenêtre soit dessinée à sa place, puis la photo s'efface.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.tour == monTour else { return }
            if cartes != nil { CartesPile.commun.effacer(); return }
            guard let p = self.panneau else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = Mouvement.duree(Mouvement.bref); p.animator().alphaValue = 0 }) {
                if self.tour == monTour { p.orderOut(nil) }
            }
        }
    }

    // MARK: Le volet à plusieurs vues (gauche ou droit)

    /// Le volet à plusieurs vues flotte : un peu de bord côté écran, en haut et en bas, pour que son ombre se voie.
    static func flottant(_ r: NSRect, droite: Bool = false) -> NSRect {
        NSRect(x: r.minX + (droite ? -10 : 10), y: r.minY + 10, width: r.width, height: r.height - 20)
    }

    /// Les dernières photos des vues du volet. Celles des voisines sont prises d'avance, à chaque arrivée : au départ
    /// d'un geste, il n'y a plus qu'à photographier la vue en cours, et les cartes partent sans attendre.
    private var photos: [String: NSImage] = [:]

    private func photographierVoisines(tour monTour: Int) {
        guard let o = ouvert, let pile = o.pile else { return }
        for chemin in Set([1, -1].compactMap { pile.page($0) }.map { pile.vues[$0] }) where chemin != o.chemin {
            guard let f = fenêtre(chemin), let c = AXBas.cadre(f), c.minX >= Ecrans.bordGarage - 2 else { continue }
            // Hors de l'écran, à la taille du volet : la photo est alors à la bonne proportion.
            if abs(c.width - o.cadre.width) > 1 || abs(c.height - o.cadre.height) > 1 { AXBas.placer(f, Ecrans.garage(taille: o.cadre.size)) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, self.tour == monTour, let img = self.photo(f) else { return }
                self.photos[chemin] = img
            }
        }
    }

    /// Un changement de vue en cours : les cartes sont à l'écran, les vraies fenêtres hors de l'écran.
    private struct Transition {
        let cible: Int?              // la vue qui arrive (nil au bout de la liste : la carte fait l'élastique)
        let ancien: Ouvert
        let neuf: Ouvert?
    }
    private var transition: Transition?
    private var enGeste = false      // les doigts tiennent les cartes (pas encore lâchées)

    /// Quatre doigts à l'horizontale sur le volet : les cartes suivent les doigts (voir GestePages et CartesPile).
    func geste(_ e: GestePages.Événement) {
        switch e {
        case .début(let doigts):
            // Les doigts vers le bord de l'écran poussent la carte dehors : vue suivante. À droite, c'est donc l'inverse.
            guard let pile = ouvert?.pile else { return }
            let sens = pile.àDroite ? -doigts : doigts
            enGeste = commencer(sens: sens, cible: pile.page(sens))
        case .suivi(let p):
            if enGeste { CartesPile.commun.dessiner(CGFloat(p)) }
        case .fin(let p, let élan):
            guard enGeste else { return }
            enGeste = false
            // Comme sur l'iPad : à mi-chemin, ou d'un geste vif, la carte change ; un retour vif la ramène.
            terminer(arrivée: (p > 0.4 || élan > 0.6) && élan > -0.4, depuis: CGFloat(p))
        }
    }

    @objc private func essaiGeste(_ note: Notification) {
        let sens = Int(note.object as? String ?? "1") ?? 1
        geste(.début(sens))
        let départ = CACurrentMediaTime()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] t in
            let p = Float(min((CACurrentMediaTime() - départ) / 0.35, 1)) * 0.7
            if p >= 0.7 { t.invalidate(); self?.geste(.fin(0.7, 1.5)); return }
            self?.geste(.suivi(p))
        }
    }

    /// Un clic sur un point : la vue numéro i, avec le même mouvement de cartes.
    func allerÀ(_ i: Int) {
        guard let pile = ouvert?.pile, pile.vues.indices.contains(i), i != pile.index else { return }
        guard !enGeste, commencer(sens: i > pile.index ? 1 : -1, cible: i) else { return }
        terminer(arrivée: true, depuis: 0)
    }

    /// Pose les cartes au départ du mouvement. Faux si le volet n'est pas prêt (pas ouvert, ou un mouvement pas fini).
    private func commencer(sens: Int, cible: Int?) -> Bool {
        guard transition == nil, !agrandi, let o = ouvert, let pile = o.pile, o.arrivé else { return false }
        let t0 = CACurrentMediaTime()
        defer { journalBas("volet à plusieurs vues : cartes posées en %.0f ms", (CACurrentMediaTime() - t0) * 1000) }
        tour += 1
        // Le volet garde sa place et sa largeur (tirer le bord change la largeur de toutes les vues).
        var cadre = o.cadre
        let enCours = fenêtre(o.chemin)
        if let enCours, let c = AXBas.cadre(enCours), c.minX < Ecrans.bordGarage - 2 {
            cadre = Ecrans.versNS(c)
            if c.width >= 300 {
                if abs(Double(c.width) - pile.largeur) > 1 { photos.removeAll() }     // la largeur a changé : photos à refaire
                pile.largeur = Double(c.width)
            }
        }
        let photoEnCours = enCours.flatMap { photo($0) } ?? photos[o.chemin] ?? carteIcône(o.chemin, cadre.size)
        photos[o.chemin] = photoEnCours
        // La vue voisine : lancée si besoin, mise à la taille du volet hors de l'écran, puis photographiée.
        var neuf: Ouvert?
        var photoVoisine: NSImage?
        if let cible, pile.vues.indices.contains(cible), let bundle = bundleDe(pile.vues[cible]) {
            let chemin = pile.vues[cible]
            if app(bundle) == nil { lancer(chemin, devant: false) } else if fenêtre(chemin) == nil { lancer(chemin, devant: true) }
            let f = fenêtre(chemin)
            // Déjà à la bonne taille hors de l'écran (c'est fait à chaque arrivée) : rien à déplacer, les cartes partent plus vite.
            if let f {
                noter(f)
                let c = AXBas.cadre(f)
                if c == nil || abs(c!.width - cadre.width) > 1 || abs(c!.height - cadre.height) > 1 || c!.minX < Ecrans.bordGarage - 2 {
                    AXBas.placer(f, Ecrans.garage(taille: cadre.size))
                }
            }
            photoVoisine = photos[chemin] ?? f.flatMap { photo($0) } ?? carteIcône(chemin, cadre.size)
            neuf = Ouvert(coin: o.coin, chemin: chemin, bundle: bundle, pile: pile, gesteLibre: o.gesteLibre, cadre: cadre)
        }
        // Vers la suivante, la vue en cours est devant et s'en va ; vers la précédente, celle-ci revient par-dessus.
        if sens > 0 || photoVoisine == nil {
            CartesPile.commun.préparer(devant: photoEnCours, derrière: photoVoisine, cadre: cadre, sens: sens, droite: pile.àDroite)
        } else {
            CartesPile.commun.préparer(devant: photoVoisine!, derrière: photoEnCours, cadre: cadre, sens: sens, droite: pile.àDroite)
        }
        panneau?.orderOut(nil)
        PointsPile.commun.cacher()
        // Les cartes sont à l'écran : la vraie fenêtre peut partir.
        if let enCours { AXBas.placer(enCours, Ecrans.garage(taille: cadre.size)) }
        var ancien = o
        ancien.cadre = cadre
        ancien.arrivé = false
        ouvert = ancien
        horsDepuis = nil
        transition = Transition(cible: neuf == nil ? nil : cible, ancien: ancien, neuf: neuf)
        return true
    }

    private func terminer(arrivée: Bool, depuis p: CGFloat) {
        guard let t = transition else { return }
        let monTour = tour
        let va = arrivée && t.neuf != nil
        CartesPile.commun.finir(vers: va ? 1 : 0, depuis: p) { [weak self] in
            guard let self, self.tour == monTour else { return }
            self.transition = nil
            if va, let n = t.neuf, let i = t.cible { n.pile?.index = i; self.ouvert = n } else { self.ouvert = t.ancien }
            self.poser(essais: 60, tour: monTour, cartes: va)
            self.préparer()          // la vue quittée a peut-être été retirée des réglages : sa fenêtre revient
        }
    }

    // MARK: Plein écran (20/11/2026)
    // Comme le tiroir : un bouton, ou un double-clic sur la barre du haut de la vue, la passe en plein écran par le zoom
    // natif du Mac (macOS anime la fenêtre) ; la même chose, ou Échap, la renvoie dans son volet.

    private var agrandi = false
    private var bouton: NSPanel?
    private let boutonVue = BoutonPleinEcran(frame: NSRect(x: 0, y: 0, width: BoutonPleinEcran.côté, height: BoutonPleinEcran.côté))
    private var zoneBouton: NSRect = .zero

    /// La fenêtre a pris (presque) tout l'écran alors que le volet est étroit.
    static func estAgrandie(_ fenêtre: NSRect, volet: NSRect) -> Bool {
        fenêtre.width > volet.width + 60 && fenêtre.height >= volet.height - 40
    }

    @objc func basculerAgrandi() {
        guard let o = ouvert, o.arrivé, transition == nil, !enGeste, let f = fenêtre(o.chemin) else { return }
        AXBas.lever(f)
        app(o.bundle)?.activate(options: [])
        let voulu = !agrandi
        let écran = NSScreen.screens.first(where: { $0.frame.intersects(o.cadre) }) ?? NSScreen.main
        journalBas(voulu ? "volet : plein écran demandé" : "volet : retour demandé")
        // Le zoom natif (le bouton vert avec ⌥) ; sans lui, la fenêtre est posée directement.
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(f, kAXZoomButtonAttribute as CFString, &v)
        if let v, CFGetTypeID(v) == AXUIElementGetTypeID() {
            let b = v as! AXUIElement
            DispatchQueue.global(qos: .userInteractive).async { _ = AXUIElementPerformAction(b, "AXZoomWindow" as CFString) }
        }
        // Filet : si macOS n'a rien fait, Side pose la fenêtre lui-même.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, let o = self.ouvert, let c = AXBas.cadre(f) else { return }
            let plein = VoletVue.estAgrandie(Ecrans.versNS(c), volet: o.cadre)
            guard plein != voulu else { return }
            if voulu, let e = écran { AXBas.placer(f, Ecrans.versAX(e.visibleFrame)) } else { AXBas.placer(f, Ecrans.versAX(o.cadre)) }
        }
    }

    private func échap() {
        if agrandi { basculerAgrandi() } else { fermer() }
    }

    /// Le petit bouton en haut à droite de la vue : « plein écran », ou « revenir au volet » (voir BoutonPleinEcran).
    private func majBouton(_ zone: NSRect) {
        let p = bouton ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.hidesOnDeactivate = false
            p.acceptsMouseMovedEvents = true
            boutonVue.action = { [weak self] in self?.basculerAgrandi() }
            boutonVue.largeurChangée = { [weak self] _ in self?.placerBouton(animé: true) }
            p.contentView = boutonVue
            bouton = p
            return p
        }()
        boutonVue.régler(agrandi: agrandi)
        if zone != zoneBouton || !p.isVisible {
            zoneBouton = zone
            placerBouton(animé: false)
        }
        if !p.isVisible { p.orderFrontRegardless() }
        // Le survol, d'après la position de la souris. Pour se replier, la souris doit quitter le rond d'origine ET la
        // pastille élargie : pas de va-et-vient pendant qu'elle s'élargit.
        let m = NSEvent.mouseLocation
        let rond = NSRect(x: zone.maxX - 12 - BoutonPleinEcran.côté, y: zone.maxY - 8 - BoutonPleinEcran.côté,
                          width: BoutonPleinEcran.côté, height: BoutonPleinEcran.côté)
        boutonVue.survol(rond.contains(m) || p.frame.contains(m))
    }

    /// Le panneau du bouton, ancré en haut à droite de la vue (il s'élargit vers la gauche au survol).
    private func placerBouton(animé: Bool) {
        guard let p = bouton else { return }
        let w = boutonVue.largeurVoulue, h = BoutonPleinEcran.côté
        let c = NSRect(x: zoneBouton.maxX - 12 - w, y: zoneBouton.maxY - 8 - h, width: w, height: h)
        guard !p.frame.equalTo(c) else { return }
        if animé {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Mouvement.duree(Mouvement.bref)
                p.animator().setFrame(c, display: true)
            }
        } else {
            p.setFrame(c, display: true)
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
        PointsPile.commun.cacher()
        CartesPile.commun.cacher()
        transition = nil
        enGeste = false
        VoletVue.pointeurSurPile = false
        let étaitAgrandi = agrandi
        agrandi = false
        bouton?.orderOut(nil)
        boutonVue.survol(false)
        guard let f = fenêtre(o.chemin), let vraie = AXBas.cadre(f), vraie.minX < Ecrans.bordGarage - 2 else {
            panneau?.orderOut(nil)
            return
        }
        // En plein écran, la vue repart à la taille du volet (pas à celle de l'écran).
        let c = étaitAgrandi ? Ecrans.versAX(o.cadre) : vraie
        // La largeur choisie en tirant le bord est gardée.
        if c.width >= 300 {
            if let pile = o.pile { pile.largeur = Double(c.width) } else { var l = largeurs; l[o.chemin] = Double(c.width); largeurs = l }
        }
        let place = Ecrans.versNS(c)
        if animé { montrerPhoto(photo(f), icône: o.chemin, à: place) }
        AXBas.placer(f, Ecrans.garage(taille: c.size))
        préparer()                   // la vue fermée a peut-être été retirée des réglages : sa fenêtre revient
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
    /// (Une autre fenêtre d'Horizon, quand le volet montre une de ses vues, ne change pas d'application : macOS ne le signale
    /// pas. Le volet repart alors quand la souris le quitte, comme d'habitude.)
    @objc private func appActivée(_ note: Notification) {
        guard let o = ouvert, o.arrivé,
              let a = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              a.bundleIdentifier != o.bundle, a.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        avant = nil          // celle qu'on vient de choisir garde la main
        fermer()
    }
}
