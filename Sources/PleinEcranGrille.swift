// La grille du plein écran : les cases, leur ordre, le glisser.
// Sorti de PleinEcran.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

let orange = NSColor(srgbRed: 0.847, green: 0.435, blue: 0.290, alpha: 1)

final class Case: NSView {
    var tuile: Tuile
    let numero: Int
    private let image = CALayer()
    private let ombre = CALayer()
    private let grandeIcone = NSImageView()
    private let petiteIcone = NSImageView()
    private var iconesMembres: [(vue: NSImageView, fenetre: Fenetre)] = []
    /// Le cadre de la vignette, dans les coordonnées de la case.
    private(set) var cadreVignette = CGRect.zero
    private let fermer = NSButton()
    private let fermable: Bool
    var auFermer: (() -> Void)?
    private(set) var imageActuelle: CGImage?

    var survol = false { didSet {
        majBordure(); fermer.isHidden = !(survol && fermable); versTiroir.isHidden = !(survol && fermable)
    } }
    var courant = false { didSet { majBordure() } }

    init(tuile: Tuile, numero: Int) {
        self.tuile = tuile
        self.numero = numero
        fermable = true
        super.init(frame: .zero)
        wantsLayer = true
        // La fenêtre flotte sur le fond flou : une vignette à ses proportions, avec une ombre, et son nom en dessous.
        ombre.shadowColor = NSColor.black.cgColor
        ombre.shadowOpacity = 0.45
        ombre.shadowRadius = 22
        ombre.shadowOffset = CGSize(width: 0, height: -10)
        layer?.addSublayer(ombre)
        image.contentsGravity = .resizeAspectFill
        image.masksToBounds = true
        image.cornerRadius = Rayon.encadre
        image.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        ombre.addSublayer(image)

        grandeIcone.image = tuile.icone
        grandeIcone.imageScaling = .scaleProportionallyUpOrDown
        addSubview(grandeIcone)

        petiteIcone.image = tuile.icone
        petiteIcone.imageScaling = .scaleProportionallyUpOrDown
        addSubview(petiteIcone)

        // Pas de nom : l'icône de l'application, à cheval sur le bas de la vignette.
        petiteIcone.wantsLayer = true
        // Une case de groupe : une icône par fenêtre, chacune sous la sienne.
        if case .groupe(let fs, _) = tuile.cible {
            petiteIcone.isHidden = true
            for f in fs {
                let v = NSImageView()
                v.image = NSRunningApplication(processIdentifier: f.pid)?.icon
                v.imageScaling = .scaleProportionallyUpOrDown
                v.wantsLayer = true
                v.shadow = petiteIcone.shadow
                iconesMembres.append((v, f))
            }
        }
        petiteIcone.shadow = { let o = NSShadow(); o.shadowColor = NSColor(white: 0, alpha: 0.45); o.shadowBlurRadius = 8
                               o.shadowOffset = NSSize(width: 0, height: -3); return o }()

        // (Plus de numéro au survol depuis le 13/11/2026 : ⌘1 à ⌘9 suivent toujours l'ordre des cases.)

        fermer.bezelStyle = .circular
        fermer.isBordered = false
        fermer.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white, NSColor(white: 0.1, alpha: 0.85)])))
        // Croix blanche sur rond sombre : visible aussi sur une fenêtre claire (celle du Finder, par exemple).
        fermer.shadow = { let o = NSShadow(); o.shadowColor = NSColor(white: 0, alpha: 0.4); o.shadowBlurRadius = 4; return o }()
        fermer.toolTip = String(localized: "Quitter \(tuile.titre)")
        fermer.target = self
        fermer.action = #selector(clicFermer)
        fermer.isHidden = true
        addSubview(fermer)
        // À côté de la croix : envoyer l'application dans le tiroir.
        versTiroir.bezelStyle = .circular
        versTiroir.isBordered = false
        versTiroir.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: String(localized: "Envoyer au tiroir"))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white, NSColor(white: 0.1, alpha: 0.85)])))
        versTiroir.shadow = fermer.shadow
        versTiroir.toolTip = String(localized: "Envoyer au tiroir")
        versTiroir.target = self
        versTiroir.action = #selector(clicTiroir)
        versTiroir.isHidden = true
        addSubview(versTiroir)
        majBordure()
    }
    private let versTiroir = NSButton()
    var auTiroir: (() -> Void)?
    @objc private func clicTiroir() { auTiroir?() }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicFermer() { auFermer?() }

    private func majBordure() {
        image.borderWidth = survol ? 4 : (courant ? 2 : 0)
        image.borderColor = (survol ? orange : NSColor(white: 1, alpha: 0.7)).cgColor
    }

    func montrer(_ img: CGImage?) {
        imageActuelle = img
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        image.contents = img
        CATransaction.commit()
        grandeIcone.isHidden = img != nil
        needsLayout = true
    }

    /// Proportions de la fenêtre : celles de sa photo, sinon celles de son cadre à l'écran.
    private var proportions: CGFloat {
        // La forme de la vignette suit la place de la fenêtre à l'écran, pas sa photo : une photo pas encore refaite
        // (fenêtre qui vient de changer de taille) est simplement rognée, sans déformer la case.
        if let r = tuile.cadre, r.height > 0 { return r.width / r.height }
        if let i = imageActuelle, i.height > 0 { return CGFloat(i.width) / CGFloat(i.height) }
        return 1.6
    }

    override func layout() {
        super.layout()
        // La vignette prend toute la place au-dessus du pied (où dépasse l'icône), à ses proportions, centrée.
        let pied: CGFloat = 26
        let zone = CGRect(x: 0, y: pied, width: bounds.width, height: max(10, bounds.height - pied))
        var l = zone.width, h = l / proportions
        if h > zone.height { h = zone.height; l = h * proportions }
        cadreVignette = CGRect(x: zone.midX - l / 2, y: zone.midY - h / 2, width: l, height: h).integral
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ombre.frame = cadreVignette
        image.frame = ombre.bounds
        ombre.shadowPath = CGPath(roundedRect: ombre.bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
        CATransaction.commit()
        let v = cadreVignette
        let c = min(v.width, v.height) * 0.34
        grandeIcone.frame = NSRect(x: v.midX - c / 2, y: v.midY - c / 2, width: c, height: c)
        fermer.frame = NSRect(x: v.maxX - 40, y: v.maxY - 40, width: 34, height: 34)
        versTiroir.frame = NSRect(x: v.maxX - 78, y: v.maxY - 40, width: 34, height: 34)
        // L'icône, centrée et droite, à cheval sur le bord bas de la vignette.
        let cote: CGFloat = 58
        petiteIcone.frame = NSRect(x: v.midX - cote / 2, y: v.minY - 24, width: cote, height: cote)
        if case .groupe(let fs, _) = tuile.cible {
            let tout = Tuile.englobant(fs)
            for (vue, f) in iconesMembres {
                if vue.superview == nil { addSubview(vue, positioned: .below, relativeTo: fermer) }
                // Le cadre de cette fenêtre dans la vignette : l'icône est à cheval sur son bord bas.
                let x = v.minX + (f.cadre.midX - tout.minX) / max(tout.width, 1) * v.width
                let bas = v.maxY - (f.cadre.maxY - tout.minY) / max(tout.height, 1) * v.height
                let c2: CGFloat = 46
                vue.frame = NSRect(x: x - c2 / 2, y: bas - 19, width: c2, height: c2)
            }
        }
    }
}

/// Le chiffre d'une case, bien centré dans un rond.
final class Pastille: NSView {
    private let texte: String
    init(texte: String) { self.texte = texte; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.62).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        let attributs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold),
                                                        .foregroundColor: NSColor.white]
        let t = texte.size(withAttributes: attributs)
        texte.draw(at: NSPoint(x: bounds.midX - t.width / 2, y: bounds.midY - t.height / 2), withAttributes: attributs)
    }
}

final class BandeBas: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: NSColor(white: 0, alpha: 0.82), ending: .clear)?.draw(in: bounds, angle: 90)
    }
}

final class Grille: NSView {
    var cases: [Case] = []
    private var zoom: CALayer?
    var auChoix: ((Case) -> Void)?
    var auFond: (() -> Void)?
    var auFermer: ((Tuile) -> Void)?
    /// Clic droit › « Envoyer au tiroir » : l'application de cette case quitte le plein écran pour le tiroir.
    var auTiroir: ((Tuile) -> Void)?
    var auDepot: ((Tuile, DepotGrille) -> Void)?
    private var animeDisposition = false
    let dock = DockGrille(frame: .zero)
    /// La place à laisser en bas pour le Dock de macOS sorti le temps de la grille (nil : celle que donne macOS).
    var basReserve: CGFloat?

    /// Des fenêtres ont quitté la grille : leurs cases disparaissent et les autres glissent en douceur vers leur nouvelle place
    /// (et leur nouvelle taille, si la grille a perdu une colonne ou une ligne).
    func reorganiser(_ tuiles: [Tuile], fin: @escaping () -> Void) {
        let gardees = Dictionary(tuiles.map { ($0.cle, $0) }, uniquingKeysWith: { a, _ in a })   // une fenêtre « sur tous les bureaux » peut être listée deux fois
        for c in cases where gardees[c.tuile.cle] == nil { c.removeFromSuperview() }
        cases = cases.filter { gardees[$0.tuile.cle] != nil }
        for c in cases { if let t = gardees[c.tuile.cle] { c.tuile = t } }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.3, 1)
            animeDisposition = true
            needsLayout = true
            layoutSubtreeIfNeeded()
            animeDisposition = false
        }, completionHandler: fin)
    }
    // Glisser-déposer d'une case
    private var prise: Case?
    private var priseEn = CGPoint.zero
    private var volante: CALayer?
    private let repere = CALayer()
    private var depot: DepotGrille?
    private var videsActuelles: [(place: Int, cadre: CGRect)] = []
    // Redimensionnement : la séparation entre deux fenêtres d'une case de groupe, que l'on tire
    private var reglage: (c: Case, a: Fenetre, b: Fenetre, horizontal: Bool)?
    private var restante: CALayer?             // la fenêtre qui reste seule dans son groupe s'étend pendant qu'on emporte l'autre
    private var restanteWid: CGWindowID = 0
    private var source: Tuile?                 // ce que l'on transporte : la case, ou une seule fenêtre d'une case de groupe
    private var sortDUnGroupe = false
    private var origineVolante = CGRect.zero
    private var imageVolante: CGImage?
    private var zone: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        addSubview(dock)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Le fond de la grille : le fond d'écran du bureau, flouté.
    func poserFond(_ img: CGImage?) { layer?.contents = img }

    /// Où chaque fenêtre est dessinée dans la grille (seule dans sa case, ou à sa place dans une case de groupe).
    private func cadresDesFenetres() -> [CGWindowID: CGRect] {
        var r: [CGWindowID: CGRect] = [:]
        let ecran = Ecrans.cadreGlobal(window?.screen)
        for c in cases {
            let v = c.cadreVignette.offsetBy(dx: c.frame.minX, dy: c.frame.minY)
            switch c.tuile.cible {
            case .fenetre(let f, _): r[f.wid] = v
            case .groupe(let fs, _):
                let ecran = Tuile.englobant(fs)
                for f in fs {
                    r[f.wid] = CGRect(x: v.minX + (f.cadre.minX - ecran.minX) / ecran.width * v.width,
                                      y: v.maxY - (f.cadre.maxY - ecran.minY) / ecran.height * v.height,
                                      width: f.cadre.width / ecran.width * v.width, height: f.cadre.height / ecran.height * v.height)
                }
            case .espace: break
            }
        }
        return r
    }

    /// D'où part une fenêtre qu'on vient de lâcher : de l'endroit où était la souris, pas de son ancienne case.
    private var lachers: [CGWindowID: CGRect] = [:]
    private var volants: [CALayer] = []

    /// Recharge la grille. Avec « transition », chaque fenêtre glisse de son ancienne place à la nouvelle, en changeant
    /// de forme s'il le faut (partage de l'écran, retour au plein écran, échange de cases) : rien ne saute.
    func charger(_ tuiles: [Tuile], courante: String?, espaces: [Espace], transition: Bool) {
        guard transition, let fond = layer else { lachers = [:]; charger(tuiles, courante: courante, espaces: espaces); return }
        var avant = cadresDesFenetres()
        for (w, r) in lachers { avant[w] = r }
        lachers = [:]
        charger(tuiles, courante: courante, espaces: espaces)
        let apres = cadresDesFenetres()
        volants.forEach { $0.removeFromSuperlayer() }
        volants = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (w, arrivee) in apres {
            guard let depart = avant[w] else { continue }
            let l = CALayer()
            l.contents = Images.commun.enCache(w)
            l.contentsGravity = .resizeAspectFill
            l.masksToBounds = true
            l.cornerRadius = Rayon.encadre
            l.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
            l.frame = depart
            l.zPosition = 70
            l.setValue(NSValue(rect: arrivee), forKey: "arrivee")
            fond.addSublayer(l)
            volants.append(l)
        }
        CATransaction.commit()
        let nouvelles = cases
        nouvelles.forEach { $0.alphaValue = 0 }
        let lot = volants
        CATransaction.flush()
        CATransaction.begin()
        CATransaction.setAnimationDuration(Mouvement.duree(0.3))
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.3, 1))
        CATransaction.setCompletionBlock { [weak self] in
            // Les vraies cases prennent le relais, en fondu, puis les calques de transition disparaissent.
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.1
                nouvelles.forEach { $0.animator().alphaValue = 1 }
            }) {
                lot.forEach { $0.removeFromSuperlayer() }
                self?.volants.removeAll { l in lot.contains { $0 === l } }
            }
        }
        for l in lot { if let r = (l.value(forKey: "arrivee") as? NSValue)?.rectValue { l.frame = r } }
        CATransaction.commit()
    }

    func charger(_ tuiles: [Tuile], courante: String?, espaces: [Espace]) {
        zoom?.removeFromSuperlayer()
        zoom = nil
        // Un glisser interrompu (Échap, grille refermée) ne laisse pas de vignette fantôme.
        volante?.removeFromSuperlayer(); volante = nil
        restante?.removeFromSuperlayer(); restante = nil
        prise = nil; source = nil; sortDUnGroupe = false
        vedette = nil
        cases.forEach { $0.removeFromSuperview() }
        cases = tuiles.enumerated().map { i, t in
            let c = Case(tuile: t, numero: i + 1)
            c.courant = t.cle == courante
            c.auFermer = { [weak self] in self?.auFermer?(t) }
            c.auTiroir = { [weak self] in self?.auTiroir?(t) }
            c.montrer(Images.commun.image(pour: t, espaces: espaces))
            addSubview(c)
            return c
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        majSurvol()
    }

    func rafraichir(espaces: [Espace]) {
        for c in cases { c.montrer(Images.commun.image(pour: c.tuile, espaces: espaces)) }
    }

    override func layout() {
        super.layout()
        // Le Dock couvre toute la grille (il laisse passer les clics hors de sa pastille) ; les cases occupent la place
        // qui reste, du côté opposé au sien.
        // La barre des menus et le Dock de macOS restent visibles au-dessus de la grille (24/11/2026) : on leur laisse leur
        // place (rien en bas quand le Dock se masque tout seul, il passe alors devant la grille au survol).
        var utile = bounds
        if let e = window?.screen {
            let f = e.frame
            var v = DockNatif.zoneSansDock(e) ?? e.visibleFrame
            // Le Dock sorti pour la grille : sa place est réservée d'avance, les cases ne bougent pas quand il arrive.
            if let bas = basReserve, f.minY + bas > v.minY { v.size.height -= f.minY + bas - v.minY; v.origin.y = f.minY + bas }
            utile.origin.x += v.minX - f.minX; utile.origin.y += v.minY - f.minY
            utile.size.width -= (v.minX - f.minX) + (f.maxX - v.maxX)
            utile.size.height -= (v.minY - f.minY) + (f.maxY - v.maxY)
        }
        dock.frame = utile
        let reserve = dock.reserve
        var zone = utile
        switch DockGrille.cote {
        case "haut": zone.size.height -= reserve
        case "gauche": zone.origin.x += reserve; zone.size.width -= reserve
        case "droite": zone.size.width -= reserve
        default: zone.origin.y += reserve; zone.size.height -= reserve
        }
        // Une vraie grille, aérée : chaque fenêtre a sa case fixe, une case sans fenêtre reste vide.
        guard !cases.isEmpty else { return }
        let positions = cases.map { Grille.position($0.tuile.place) }
        let colonnes = (positions.map { $0.colonne }.max() ?? 0) + 1
        let lignes = (positions.map { $0.ligne }.max() ?? 0) + 1
        let margeX = bounds.width * 0.045, margeY = bounds.height * 0.04
        let ecartX = bounds.width * 0.035, ecartY = bounds.height * 0.04
        let pied: CGFloat = 26                               // la place de l'icône qui dépasse sous la vignette
        let largeurMax = (zone.width - 2 * margeX - CGFloat(colonnes - 1) * ecartX) / CGFloat(colonnes)
        let hauteurMax = (zone.height - 2 * margeY - CGFloat(lignes - 1) * ecartY) / CGFloat(lignes) - pied
        // Des cases aux proportions de l'écran, aussi grandes que possible, et la grille entière centrée.
        let format = bounds.width / max(bounds.height, 1)
        let largeur = min(largeurMax, hauteurMax * format), hauteur = largeur / format + pied
        let totalL = CGFloat(colonnes) * largeur + CGFloat(colonnes - 1) * ecartX
        let totalH = CGFloat(lignes) * hauteur + CGFloat(lignes - 1) * ecartY
        let x0 = zone.midX - totalL / 2, sommet = zone.midY + totalH / 2
        func cadre(_ p: (colonne: Int, ligne: Int)) -> NSRect {
            NSRect(x: x0 + CGFloat(p.colonne) * (largeur + ecartX),
                   y: sommet - CGFloat(p.ligne + 1) * hauteur - CGFloat(p.ligne) * ecartY, width: largeur, height: hauteur)
        }
        for (c, p) in zip(cases, positions) { if animeDisposition { c.animator().frame = cadre(p) } else { c.frame = cadre(p) } }
        // Les cases vides de la grille : on peut y déposer une fenêtre.
        let prises = Set(cases.map { $0.tuile.place })
        videsActuelles = (0..<24).filter { !prises.contains($0) }.compactMap { k in
            let p = Grille.position(k)
            guard p.colonne < colonnes, p.ligne < lignes else { return nil }
            return (k, cadre(p).insetBy(dx: 0, dy: pied / 2).offsetBy(dx: 0, dy: pied / 2))
        }
    }

    /// Où se trouve la case numéro k. Les quatre premières forment un carré (deux en haut, deux en bas) ; les suivantes
    /// ajoutent des colonnes à droite (haut puis bas), sans jamais déplacer les précédentes ; au-delà de huit, une troisième ligne.
    static func position(_ k: Int) -> (colonne: Int, ligne: Int) {
        if k < 4 { return (k % 2, k / 2) }
        if k < 8 { return (k / 2, k % 2) }
        if k < 12 { return (k - 8, 2) }
        return (4 + (k - 12) / 3, (k - 12) % 3)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let zone { removeTrackingArea(zone) }
        let z = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(z)
        zone = z
    }

    func majSurvol() {
        guard let w = window else { return }
        let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        // La souris reprend la main sur la molette, mais seulement si elle a vraiment bougé : tourner la molette la fait
        // toujours trembler d'un ou deux points, ce qui ramenait la mise en avant sous le pointeur.
        if vedette != nil {
            let ici = NSEvent.mouseLocation
            if hypot(ici.x - sourisVedette.x, ici.y - sourisVedette.y) < 18 { return }
            vedette = nil
        }
        for c in cases { let s = c.frame.contains(p); if c.survol != s { c.survol = s } }
        // Au-dessus d'une séparation entre deux fenêtres d'un groupe, le pointeur montre qu'on peut la tirer.
        var curseur = NSCursor.arrow
        if let c = cases.first(where: { $0.frame.contains(p) }), case .groupe(let fs, _) = c.tuile.cible {
            let v = c.cadreVignette.offsetBy(dx: c.frame.minX, dy: c.frame.minY), tout = Tuile.englobant(fs)
            if v.contains(p), let (_, _, horizontal) = Grille.separation(fs, x: tout.minX + (p.x - v.minX) / max(v.width, 1) * tout.width,
                                                  y: tout.minY + (1 - (p.y - v.minY) / max(v.height, 1)) * tout.height,
                                                  marge: 9 / max(v.width, 1) * tout.width) {
                curseur = horizontal ? .resizeLeftRight : .resizeUpDown
            }
        }
        curseur.set()
    }

    override func mouseMoved(with event: NSEvent) { majSurvol() }
    override func mouseEntered(with event: NSEvent) { majSurvol() }
    override func mouseExited(with event: NSEvent) { majSurvol() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Deux doigts vers le haut sur une case : on ferme l'application, comme sur iPhone

    private var balayee: Case?
    private var montee: CGFloat = 0
    private var baseBalayee = CGRect.zero

    // MARK: La molette de la souris parcourt les cases, en boucle

    /// La case mise en avant par la molette (nil : aucune). Un clic, Entrée ou le clic de la molette la choisit.
    private(set) var vedette: Case?
    private var cumulMolette: CGFloat = 0
    private var dernierCran: TimeInterval = 0
    private var sourisVedette = CGPoint.zero

    /// Avance la mise en avant d'une case, dans un sens ou dans l'autre. Après la dernière, on revient à la première.
    private func avancerVedette(_ d: Int) {
        guard !cases.isEmpty else { return }
        let depart = vedette ?? cases.first(where: { $0.survol }) ?? cases.first(where: { $0.courant })
        var i = depart.flatMap { c in cases.firstIndex { $0 === c } } ?? (d > 0 ? -1 : 0)
        i = ((i + d) % cases.count + cases.count) % cases.count
        vedette = cases[i]
        sourisVedette = NSEvent.mouseLocation
        for c in cases { let s = c === vedette; if c.survol != s { c.survol = s } }
    }

    /// Choisit la case mise en avant par la molette, s'il y en a une.
    @discardableResult
    func choisirVedette() -> Bool {
        guard let c = vedette, zoom == nil else { return false }
        vedette = nil
        auChoix?(c)
        return true
    }

    override func otherMouseUp(with event: NSEvent) { choisirVedette() }      // clic de la molette

    override func scrollWheel(with event: NSEvent) {
        guard zoom == nil, volante == nil else { return }
        // Une molette de souris n'a pas de « phase », contrairement au trackpad : elle fait défiler la mise en avant.
        if event.phase.isEmpty, event.momentumPhase.isEmpty {
            let dy = event.scrollingDeltaY
            guard dy != 0 else { return }
            // La molette envoie beaucoup de petits mouvements, surtout lancée : on les cumule, et on n'avance que d'une case
            // à la fois, pas plus de sept fois par seconde.
            cumulMolette += event.hasPreciseScrollingDeltas ? dy : dy * 10
            let seuil: CGFloat = 70
            guard abs(cumulMolette) >= seuil else { return }
            let maintenant = ProcessInfo.processInfo.systemUptime
            if maintenant - dernierCran >= 0.14 {
                avancerVedette(cumulMolette < 0 ? 1 : -1)
                dernierCran = maintenant
                // Une ligne par cran dans le journal, pour régler la molette sur de vrais mouvements.
                journal("Square: molette dans la grille — cran %@ (cumul %.0f, %@)", cumulMolette < 0 ? "suivant" : "précédent",
                        Double(cumulMolette), event.hasPreciseScrollingDeltas ? "fin" : "par lignes")
            }
            cumulMolette = 0
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        if event.phase == .began {
            balayee = cases.first { $0.frame.contains(p) }
            baseBalayee = balayee?.frame ?? .zero
            montee = 0
        }
        guard let c = balayee else { return }
        if event.phase == .changed {
            // Avec le défilement « naturel », des doigts qui montent donnent un déplacement négatif.
            montee += event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            let h = max(0, montee)
            c.frame = baseBalayee.offsetBy(dx: 0, dy: h)
            c.alphaValue = max(0.25, 1 - h / 320)
        } else if event.phase == .ended || event.phase == .cancelled {
            balayee = nil
            let partie = montee > 110 && event.phase == .ended
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                c.animator().frame = partie ? baseBalayee.offsetBy(dx: 0, dy: bounds.height) : baseBalayee
                c.animator().alphaValue = partie ? 0 : 1
            }) { [weak self] in if partie { self?.auFermer?(c.tuile) } }
        }
    }

    /// Clic droit sur une case : quitter l'application.
    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let c = cases.first(where: { $0.frame.contains(p) }) else { return }
        clicDroitSur = c.tuile
        let menu = NSMenu()
        let tiroir = menu.addItem(withTitle: String(localized: "Envoyer au tiroir"), action: #selector(envoyerAuTiroir), keyEquivalent: "")
        tiroir.target = self
        tiroir.image = NSImage(systemSymbolName: "rectangle.bottomthird.inset.filled", accessibilityDescription: nil)
        menu.addItem(.separator())
        let item = menu.addItem(withTitle: String(localized: "Quitter \(c.tuile.titre.components(separatedBy: " — ").first ?? String(localized: "l'application"))"),
                                action: #selector(quitterLaCase), keyEquivalent: "")
        item.target = self
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    private var clicDroitSur: Tuile?
    @objc private func quitterLaCase() { if let t = clicDroitSur { clicDroitSur = nil; auFermer?(t) } }
    @objc private func envoyerAuTiroir() { if let t = clicDroitSur { clicDroitSur = nil; auTiroir?(t) } }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        prise = cases.first { $0.frame.contains(p) }
        priseEn = p
        source = prise?.tuile
        origineVolante = prise.map { $0.cadreVignette.offsetBy(dx: $0.frame.minX, dy: $0.frame.minY) } ?? .zero
        imageVolante = prise?.imageActuelle
        reglage = nil
        // Dans une case de groupe : sur la séparation entre deux fenêtres, on les redimensionne ; sur une fenêtre, on l'attrape
        // pour la sortir du groupe. (Pour déplacer la case entière, on l'attrape par une icône, en bas.)
        if let c = prise, case .groupe(let fs, let e) = c.tuile.cible, origineVolante.contains(p) {
            let v = origineVolante, ecran = Tuile.englobant(fs)
            let sx = ecran.minX + (p.x - v.minX) / max(v.width, 1) * ecran.width
            let sy = ecran.minY + (1 - (p.y - v.minY) / max(v.height, 1)) * ecran.height
            if let (a, b, horizontal) = Grille.separation(fs, x: sx, y: sy, marge: 9 / max(v.width, 1) * ecran.width) {
                reglage = (c, a, b, horizontal)
                return
            }
            guard p.y > origineVolante.minY + 34 else { return }
            if let f = fs.first(where: { $0.cadre.contains(CGPoint(x: sx, y: sy)) }) {
                var t = Tuile(cle: "f\(f.wid)", titre: f.app, icone: c.tuile.icone, cible: .fenetre(f, e), pid: f.pid)
                t.place = c.tuile.place
                source = t
                sortDUnGroupe = true
                imageVolante = Images.commun.image(pour: t, espaces: [])
                origineVolante = CGRect(x: v.minX + (f.cadre.minX - ecran.minX) / ecran.width * v.width,
                                        y: v.maxY - (f.cadre.maxY - ecran.minY) / ecran.height * v.height,
                                        width: f.cadre.width / ecran.width * v.width, height: f.cadre.height / ecran.height * v.height)
            }
        }
    }

    /// La séparation entre deux fenêtres d'un groupe qui se trouve sous ce point de l'écran, s'il y en a une.
    /// horizontal : les fenêtres sont côte à côte (on tire la séparation vers la gauche ou la droite).
    static func separation(_ fs: [Fenetre], x: CGFloat, y: CGFloat, marge: CGFloat) -> (Fenetre, Fenetre, Bool)? {
        for a in fs {
            for b in fs where b.wid != a.wid {
                let ca = a.cadre, cb = b.cadre
                if abs(ca.maxX - cb.minX) < 14, abs(x - ca.maxX) <= marge, y > max(ca.minY, cb.minY), y < min(ca.maxY, cb.maxY) { return (a, b, true) }
                if abs(ca.maxY - cb.minY) < 14, abs(y - ca.maxY) <= marge, x > max(ca.minX, cb.minX), x < min(ca.maxX, cb.maxX) { return (a, b, false) }
            }
        }
        return nil
    }

    /// On tire la séparation : les deux fenêtres voisines changent de taille dans la case, en direct.
    private func regler(_ r: (c: Case, a: Fenetre, b: Fenetre, horizontal: Bool), _ p: CGPoint) {
        guard case .groupe(let fs, let e) = r.c.tuile.cible else { return }
        let v = r.c.cadreVignette.offsetBy(dx: r.c.frame.minX, dy: r.c.frame.minY), tout = Tuile.englobant(fs)
        let mini: CGFloat = 260
        var ca = r.a.cadre, cb = r.b.cadre
        if r.horizontal {
            let limite = min(max(ca.maxX + (p.x - priseEn.x) / max(v.width, 1) * tout.width, ca.minX + mini), cb.maxX - mini)
            ca.size.width = limite - ca.minX
            cb.size.width = cb.maxX - limite; cb.origin.x = limite
        } else {
            let limite = min(max(ca.maxY - (p.y - priseEn.y) / max(v.height, 1) * tout.height, ca.minY + mini), cb.maxY - mini)
            ca.size.height = limite - ca.minY
            cb.size.height = cb.maxY - limite; cb.origin.y = limite
        }
        let nouvelles = fs.map { f -> Fenetre in
            let c = f.wid == r.a.wid ? ca : (f.wid == r.b.wid ? cb : f.cadre)
            return Fenetre(wid: f.wid, pid: f.pid, app: f.app, titre: f.titre, cadre: c, agrandie: false, masquee: f.masquee)
        }
        var t = Tuile(cle: r.c.tuile.cle, titre: r.c.tuile.titre, icone: r.c.tuile.icone, cible: .groupe(nouvelles, e), pid: r.c.tuile.pid)
        t.place = r.c.tuile.place
        r.c.tuile = t
        r.c.montrer(Images.commun.image(pour: t, espaces: []))
    }

    /// La case transportée prend la place d'une autre ; celles qui se trouvent entre les deux glissent d'un cran.
    private func inserer(_ c: Case, aLaPlaceDe cible: Case) {
        var ordre = cases.sorted { $0.tuile.place < $1.tuile.place }
        let places = ordre.map { $0.tuile.place }                  // les mêmes cases de la grille, redistribuées
        guard let de = ordre.firstIndex(where: { $0 === c }), let vers = ordre.firstIndex(where: { $0 === cible }) else { return }
        ordre.remove(at: de)
        ordre.insert(c, at: vers)
        journal("Square: case glissée du rang %d au rang %d", de + 1, vers + 1)
        for (x, place) in zip(ordre, places) { x.tuile.place = place }
        ordreChange = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.3, 1)
            animeDisposition = true
            needsLayout = true
            layoutSubtreeIfNeeded()
            animeDisposition = false
        }
    }
    private var ordreChange = false

    /// On tire une case : sa vignette suit la souris. Au-dessus d'une autre case, un repère orange montre ce qui se passera
    /// si on lâche : toute la vignette (échange des places) ou une moitié (partage de l'écran de ce côté).
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let r = reglage { regler(r, p); return }
        guard zoom == nil, let c = prise, let source, let fond = layer else { return }
        let origine = origineVolante
        if volante == nil {
            guard hypot(p.x - priseEn.x, p.y - priseEn.y) > 8 else { return }
            let l = CALayer()
            l.contents = imageVolante
            l.contentsGravity = .resizeAspectFill
            l.masksToBounds = true
            l.cornerRadius = Rayon.encadre
            l.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
            l.opacity = 0.92
            l.zPosition = 90
            l.frame = origine
            fond.addSublayer(l)
            volante = l
            repere.backgroundColor = orange.withAlphaComponent(0.4).cgColor
            repere.borderColor = orange.cgColor
            repere.borderWidth = 3
            repere.cornerRadius = Rayon.encadre
            repere.zPosition = 80
            repere.isHidden = true
            fond.addSublayer(repere)
            c.alphaValue = sortDUnGroupe ? 0.6 : 0.25
            // On emporte une des deux fenêtres d'un groupe : celle qui reste s'étend tout de suite dans sa case.
            if sortDUnGroupe, case .groupe(let fs, _) = c.tuile.cible, fs.count == 2, case .fenetre(let pris, _) = source.cible,
               let autre = fs.first(where: { $0.wid != pris.wid }) {
                let v = c.cadreVignette.offsetBy(dx: c.frame.minX, dy: c.frame.minY), tout = Tuile.englobant(fs)
                let r = CALayer()
                r.contents = Images.commun.enCache(autre.wid)
                r.contentsGravity = .resizeAspectFill
                r.masksToBounds = true
                r.cornerRadius = Rayon.encadre
                r.zPosition = 60
                r.frame = CGRect(x: v.minX + (autre.cadre.minX - tout.minX) / tout.width * v.width,
                                 y: v.maxY - (autre.cadre.maxY - tout.minY) / tout.height * v.height,
                                 width: autre.cadre.width / tout.width * v.width, height: autre.cadre.height / tout.height * v.height)
                fond.addSublayer(r)
                restante = r
                restanteWid = autre.wid
                c.alphaValue = 0
                CATransaction.flush()
                CATransaction.begin()
                CATransaction.setAnimationDuration(Mouvement.duree(0.28))
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.3, 1))
                r.frame = v
                CATransaction.commit()
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Un peu plus petite pendant le transport, pour bien voir ce qu'il y a dessous.
        let l = origine.width * 0.7, h = origine.height * 0.7
        volante?.frame = CGRect(x: p.x - l / 2, y: p.y - h / 2, width: l, height: h)
        depot = nil
        repere.isHidden = true
        // Seule la vignette compte comme « sur la case » : l'espace entre deux vignettes sert à glisser la case entre elles.
        if let cible = cases.first(where: { $0 !== c && $0.cadreVignette.offsetBy(dx: $0.frame.minX, dy: $0.frame.minY).contains(p) }) {
            let v = cible.cadreVignette.offsetBy(dx: cible.frame.minX, dy: cible.frame.minY)
            let rx = (p.x - v.minX) / max(v.width, 1), ry = (p.y - v.minY) / max(v.height, 1)
            var zone = v
            // La fenêtre visée : celle de la case, ou, dans une case de groupe, celle qui se trouve sous la souris.
            var visee: Fenetre?, cadreVisee = v
            var rxv = rx, ryv = ry
            if case .fenetre = source.cible {
                switch cible.tuile.cible {
                case .fenetre(let f, _): visee = f
                case .groupe(let fs, _):
                    let ecran = Tuile.englobant(fs)
                    let sx = ecran.minX + rx * ecran.width, sy = ecran.minY + (1 - ry) * ecran.height
                    if let f = fs.first(where: { $0.cadre.contains(CGPoint(x: sx, y: sy)) }) {
                        visee = f
                        rxv = (sx - f.cadre.minX) / max(f.cadre.width, 1)
                        ryv = 1 - (sy - f.cadre.minY) / max(f.cadre.height, 1)
                        cadreVisee = CGRect(x: v.minX + (f.cadre.minX - ecran.minX) / ecran.width * v.width,
                                            y: v.maxY - (f.cadre.maxY - ecran.minY) / ecran.height * v.height,
                                            width: f.cadre.width / ecran.width * v.width, height: f.cadre.height / ecran.height * v.height)
                    }
                case .espace: break
                }
            }
            if let f = visee, rxv < 0.27 || rxv > 0.73 || ryv < 0.27 || ryv > 0.73 {
                zone = cadreVisee
                if rxv < 0.27 { zone.size.width /= 2; depot = .partager(f, .gauche) }
                else if rxv > 0.73 { zone.origin.x = cadreVisee.midX; zone.size.width /= 2; depot = .partager(f, .droite) }
                else if ryv > 0.73 { zone.origin.y = cadreVisee.midY; zone.size.height /= 2; depot = .partager(f, .haut) }
                else { zone.size.height /= 2; depot = .partager(f, .bas) }
            } else if sortDUnGroupe { depot = .separer(nil); zone = .zero }
            else {
                // Au milieu d'une autre case : comme sur iPhone, la case transportée prend cette place tout de suite
                // et les autres se poussent pour lui faire de la place.
                CATransaction.commit()
                inserer(c, aLaPlaceDe: cible)
                return
            }
            repere.frame = zone
            repere.isHidden = false
        } else if let vide = videsActuelles.first(where: { $0.cadre.contains(p) }) {
            depot = sortDUnGroupe ? .separer(vide.place) : .place(vide.place)
            repere.frame = vide.cadre
            repere.isHidden = false
        } else if sortDUnGroupe, !c.frame.contains(p) {
            depot = .separer(nil)          // lâchée n'importe où hors de sa case : elle quitte le groupe
        } else if !sortDUnGroupe, !c.frame.contains(p) {
            // Entre deux cases d'une même rangée (ou au bout d'une rangée) : la case transportée s'y glisse, les autres se poussent.
            let rangee = cases.filter { $0 !== c && p.y >= $0.frame.minY && p.y <= $0.frame.maxY }
            let gauche = rangee.filter { $0.frame.midX <= p.x }.max { $0.frame.midX < $1.frame.midX }
            let droite = rangee.filter { $0.frame.midX > p.x }.min { $0.frame.midX < $1.frame.midX }
            let ordre = cases.sorted { $0.tuile.place < $1.tuile.place }
            func rang(_ x: Case) -> Int { ordre.firstIndex { $0 === x } ?? 0 }
            let moi = rang(c)
            var cible: Case?
            if let droite, moi > rang(droite) { cible = droite }            // elle vient d'après : elle prend la place de celle de droite
            else if let gauche, moi < rang(gauche) { cible = gauche }       // elle vient d'avant : elle prend la place de celle de gauche
            if let cible {
                CATransaction.commit()
                inserer(c, aLaPlaceDe: cible)
                return
            }
        }
        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        guard zoom == nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        if let r = reglage {
            // Fin d'un redimensionnement : les vraies fenêtres prennent les tailles choisies.
            reglage = nil; prise = nil; source = nil
            if case .groupe(let fs, _) = r.c.tuile.cible {
                auDepot?(r.c.tuile, .redimensionner(Dictionary(uniqueKeysWithValues: fs.map { ($0.wid, $0.cadre) })))
            }
            return
        }
        if let c = prise, volante != nil {
            // Fin d'un glisser-déposer. On retient d'où part la fenêtre lâchée, pour que la transition parte de la souris.
            if let v = volante, let source, depot != nil {
                switch source.cible {
                case .fenetre(let f, _): lachers = [f.wid: v.frame]
                default: lachers = [:]
                }
                // La fenêtre restée dans la case s'est déjà étendue : la transition repart de là.
                if let r = restante { lachers[restanteWid] = r.frame }
            }
            restante?.removeFromSuperlayer(); restante = nil
            repere.removeFromSuperlayer()
            prise = nil
            let transportee = source ?? c.tuile
            source = nil; sortDUnGroupe = false
            let reordonne = ordreChange
            ordreChange = false
            if let d = depot {
                volante?.removeFromSuperlayer(); volante = nil
                c.alphaValue = 1
                depot = nil
                auDepot?(transportee, d)
            } else if let v = volante {
                // Lâchée sans autre effet : la vignette rejoint sa case en douceur (sa nouvelle case, si l'ordre a changé).
                volante = nil
                CATransaction.begin()
                CATransaction.setAnimationDuration(Mouvement.duree(0.2))
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.3, 1))
                CATransaction.setCompletionBlock { [weak self] in
                    v.removeFromSuperlayer()
                    c.alphaValue = 1
                    guard let self, reordonne else { return }
                    self.auDepot?(transportee, .ordre(Dictionary(self.cases.map { ($0.tuile.cle, $0.tuile.place) }, uniquingKeysWith: { a, _ in a })))
                }
                v.frame = c.cadreVignette.offsetBy(dx: c.frame.minX, dy: c.frame.minY)
                v.opacity = 1
                CATransaction.commit()
            }
            return
        }
        prise = nil
        source = nil; sortDUnGroupe = false
        // Une case mise en avant par la molette : un clic, où qu'il soit, la choisit.
        if choisirVedette() { return }
        if let c = cases.first(where: { $0.frame.contains(p) }) { auChoix?(c) }
        else { auFond?() }
    }

    /// L'image de la case grandit jusqu'à remplir l'écran.
    /// Une application lancée depuis le Dock : son icône grandit jusqu'à couvrir l'écran, comme une case choisie,
    /// et reste là le temps que l'application ouvre sa fenêtre (la grille s'efface ensuite).
    func zoomerIcone(_ chemin: String) {
        guard let fond = layer, let (depart, image) = dock.icone(de: chemin) else { return }
        zoom?.removeFromSuperlayer()
        let l = CALayer()
        l.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        l.cornerRadius = Rayon.carte
        l.cornerCurve = .continuous
        l.masksToBounds = true
        l.frame = convert(depart, from: dock)
        l.zPosition = 100
        let icone = CALayer()
        icone.contents = image
        icone.contentsGravity = .resizeAspect
        icone.frame = l.bounds
        icone.autoresizingMask = []
        l.addSublayer(icone)
        fond.addSublayer(l)
        zoom = l
        CATransaction.flush()
        CATransaction.begin()
        CATransaction.setAnimationDuration(Mouvement.duree(0.3))
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1))
        l.frame = bounds
        l.cornerRadius = 0
        // L'icône grandit un peu et reste au centre, comme à l'ouverture d'une app sur l'iPhone.
        icone.frame = CGRect(x: bounds.midX - 64, y: bounds.midY - 64, width: 128, height: 128)
        CATransaction.commit()
    }

    func zoomer(_ c: Case, fin: @escaping () -> Void) {
        guard let img = c.imageActuelle, let fond = layer else { fin(); return }
        zoom?.removeFromSuperlayer()     // un zoom encore en cours : sa capture ne doit pas rester collée sur la grille
        let l = CALayer()
        l.contents = img
        l.contentsGravity = .resizeAspectFill
        l.masksToBounds = true
        l.cornerRadius = Rayon.carte
        l.frame = c.cadreVignette.offsetBy(dx: c.frame.minX, dy: c.frame.minY)
        l.zPosition = 100
        fond.addSublayer(l)
        zoom = l
        CATransaction.flush()
        CATransaction.begin()
        CATransaction.setAnimationDuration(Mouvement.duree(0.16))
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock(fin)
        // Elle rejoint la place exacte de la fenêtre (sous la barre des menus), pour qu'il n'y ait aucun saut à l'arrivée.
        let arrivee = cadreReel(c)
        l.frame = arrivee
        l.cornerRadius = 0
        CATransaction.commit()
    }
}

extension Grille {
    /// La place de la fenêtre à l'écran, dans les coordonnées de la grille. Sans fenêtre connue : tout l'écran.
    func cadreReel(_ c: Case) -> CGRect {
        guard let r = c.tuile.cadre else { return bounds }
        let ecran = Ecrans.cadreGlobal(window?.screen)
        return CGRect(x: r.minX - ecran.minX, y: bounds.height - (r.minY - ecran.minY) - r.height, width: r.width, height: r.height)
    }

    /// Apparition de la grille : la fenêtre où vous êtes rétrécit jusqu'à sa case, les autres arrivent en fondu en grossissant un peu.
    func preparerApparition() { for c in cases { c.alphaValue = 0 } }

    func apparaitre() {
        guard let fond = layer else { cases.forEach { $0.alphaValue = 1 }; return }
        let duree = 0.3, courbe = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        var volants: [(CALayer, Case)] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for c in cases {
            let vignette = c.cadreVignette.offsetBy(dx: c.frame.minX, dy: c.frame.minY)
            guard let img = c.imageActuelle else { continue }
            let l = CALayer()
            l.contents = img
            l.contentsGravity = .resizeAspectFill
            l.masksToBounds = true
            l.zPosition = c.courant ? 60 : 50
            if c.courant {
                l.frame = cadreReel(c)
                l.cornerRadius = 0
            } else {
                l.frame = vignette.insetBy(dx: vignette.width * 0.06, dy: vignette.height * 0.06)
                l.cornerRadius = Rayon.encadre
                l.opacity = 0
            }
            fond.addSublayer(l)
            volants.append((l, c))
        }
        CATransaction.commit()
        CATransaction.flush()
        CATransaction.begin()
        CATransaction.setAnimationDuration(duree)
        CATransaction.setAnimationTimingFunction(courbe)
        CATransaction.setCompletionBlock { [weak self] in
            // Les vraies cases prennent le relais (avec leur icône, leur chiffre et leur ombre).
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                self?.cases.forEach { $0.animator().alphaValue = 1 }
            } completionHandler: { volants.forEach { $0.0.removeFromSuperlayer() } }
        }
        for (l, c) in volants {
            l.frame = c.cadreVignette.offsetBy(dx: c.frame.minX, dy: c.frame.minY)
            l.cornerRadius = Rayon.encadre
            l.opacity = 1
        }
        CATransaction.commit()
        // Une case sans photo n'a pas de calque volant : elle apparaît simplement en fondu.
        let avecCalque = Set(volants.map { ObjectIdentifier($0.1) })
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duree
            for c in cases where !avecCalque.contains(ObjectIdentifier(c)) { c.animator().alphaValue = 1 }
        }
    }
}

final class Panneau: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
