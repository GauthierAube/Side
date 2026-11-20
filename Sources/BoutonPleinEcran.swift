// Le bouton « plein écran » posé en haut à droite d'une vue du volet (20/11/2026).
// Une pastille de verre dépoli, comme les commandes posées sur une vidéo dans QuickTime ou Photos : on la voit sur
// n'importe quel fond. Au survol, elle s'allume, dit ce qu'elle fait (« Plein écran », « Revenir ») et la souris devient
// une main. Elle vit dans son propre petit panneau flottant (voir VoletVue.majBouton), qui s'élargit vers la gauche au survol.
import AppKit

final class BoutonPleinEcran: NSView {
    /// La hauteur de la pastille ; repliée, elle est ronde.
    static let côté: CGFloat = 30

    var action: (() -> Void)?
    /// Appelé quand la largeur voulue change (survol) : le panneau suit, ancré à droite.
    var largeurChangée: ((CGFloat) -> Void)?

    private let fond = NSVisualEffectView()
    /// La teinte posée sur le verre : sombre au repos, couleur d'accent au survol.
    private let teinte = NSView()
    private let icône = NSImageView()
    private let texte = NSTextField(labelWithString: "")
    private var survolée = false
    private(set) var agrandi = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        fond.material = .hudWindow
        fond.blendingMode = .behindWindow
        fond.state = .active
        fond.wantsLayer = true
        fond.layer?.cornerCurve = .continuous
        fond.layer?.masksToBounds = true
        fond.layer?.borderWidth = 0.5
        fond.autoresizingMask = [.width, .height]
        addSubview(fond)
        teinte.wantsLayer = true
        teinte.autoresizingMask = [.width, .height]
        fond.addSubview(teinte)
        icône.imageScaling = .scaleProportionallyDown
        icône.contentTintColor = .white
        fond.addSubview(icône)
        texte.font = .systemFont(ofSize: 12, weight: .semibold)
        texte.textColor = .white
        texte.alphaValue = 0
        texte.isHidden = true
        texte.lineBreakMode = .byClipping
        fond.addSubview(texte)
        appliquer()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Plein écran (la pastille propose de revenir) ou volet (elle propose le plein écran).
    func régler(agrandi: Bool) {
        guard agrandi != self.agrandi || icône.image == nil else { return }
        self.agrandi = agrandi
        appliquer()
    }

    /// La largeur que veut la pastille : un rond, ou au survol un rond plus le texte.
    var largeurVoulue: CGFloat {
        survolée ? (Self.côté + texte.intrinsicContentSize.width + 16).rounded(.up) : Self.côté
    }

    private func appliquer() {
        // Quatre flèches qui partent vers les coins : « tout l'écran » ; vers le centre : « revenir ».
        let noms = agrandi
            ? ["arrow.down.forward.and.arrow.up.backward", "arrow.down.right.and.arrow.up.left"]
            : ["arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", "arrow.up.left.and.arrow.down.right"]
        let aide = agrandi ? String(localized: "Revenir au volet (Échap)") : String(localized: "Plein écran")
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        icône.image = noms.lazy.compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: aide)?.withSymbolConfiguration(config) }.first
        texte.stringValue = agrandi ? String(localized: "Revenir") : String(localized: "Plein écran")
        toolTip = aide
        setAccessibilityLabel(aide)
        setAccessibilityRole(.button)
        dessinerSurvol()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        fond.frame = bounds
        teinte.frame = fond.bounds
        fond.layer?.cornerRadius = bounds.height / 2          // une pastille : arrondi = moitié de la hauteur
        let c = Self.côté
        icône.frame = NSRect(x: bounds.width - c + 7, y: 7, width: c - 14, height: c - 14)
        let t = texte.intrinsicContentSize
        texte.frame = NSRect(x: 12, y: ((bounds.height - t.height) / 2).rounded(), width: t.width + 2, height: t.height)
    }

    private func dessinerSurvol() {
        teinte.layer?.backgroundColor = (survolée ? NSColor.controlAccentColor.withAlphaComponent(0.85) : NSColor.black.withAlphaComponent(0.35)).cgColor
        fond.layer?.borderColor = NSColor.white.withAlphaComponent(survolée ? 0.5 : 0.25).cgColor
    }

    // MARK: Survol, main, clic

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways : Side n'est jamais l'application de devant quand on survole la vue d'Horizon.
        // Pas d'entrée / sortie ici : quand la pastille s'élargit, macOS recalcule la zone et signalait une sortie,
        // la pastille se repliait, puis rentrait… elle clignotait. C'est le volet qui dit si la souris est dessus
        // (VoletVue.majBouton, à chaque relevé de la souris) : voir `survol(_:)`.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    /// La souris est-elle sur la pastille (dans son panneau) ? Décidé par le volet, d'après la position de la souris.
    func survol(_ oui: Bool) { changerSurvol(oui) }
    override func mouseMoved(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func changerSurvol(_ oui: Bool) {
        guard oui != survolée else { return }
        survolée = oui
        if oui { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        texte.isHidden = !oui
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Mouvement.duree(Mouvement.bref)
            texte.animator().alphaValue = oui ? 1 : 0
        }
        dessinerSurvol()
        largeurChangée?(largeurVoulue)
    }

    override func mouseDown(with event: NSEvent) {
        fond.layer?.opacity = 0.7
    }

    override func mouseUp(with event: NSEvent) {
        fond.layer?.opacity = 1
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action?()
    }
}
