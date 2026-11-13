// Les transitions entre le tiroir et le plein écran. Déplacer la vraie fenêtre d'une autre application à petits pas est saccadé
// (chaque pas passe par l'application). On anime donc une photo de la fenêtre, d'un seul mouvement fluide, comme le font les
// animations de macOS : elle grandit du tiroir jusqu'à tout l'écran, ou rétrécit jusqu'à sa place dans le tiroir. La vraie
// fenêtre est posée à l'arrivée, sous la photo, qui s'efface alors.
import AppKit

enum TransitionFenetre {
    private static var panneau: NSPanel?
    private static let calque = CALayer()

    /// Coordonnées de l'écran à l'origine en haut à gauche (celles des fenêtres des autres applications) → origine en bas à gauche.
    static func versÉcran(_ r: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    /// Anime l'image de `de` vers `vers` (coordonnées de l'écran, origine en bas à gauche), puis appelle `arrivée`.
    /// La photo reste affichée jusqu'à `effacer()`, pour couvrir le moment où la vraie fenêtre se pose.
    static func animer(_ image: NSImage?, de: CGRect, vers: CGRect, durée: TimeInterval = 0.38,
                       arrondiDépart: CGFloat = 20, arrondiArrivée: CGFloat = 10, arrivée: @escaping () -> Void) {
        guard let ecran = NSScreen.screens.first(where: { $0.frame.intersects(vers) }) ?? NSScreen.main else { arrivée(); return }
        let p = panneau ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .screenSaver
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.animationBehavior = .none
            let v = NSView()
            v.wantsLayer = true
            v.layer?.addSublayer(calque)
            p.contentView = v
            return p
        }()
        panneau = p
        p.setFrame(ecran.frame, display: false)
        let o = ecran.frame.origin
        let départ = de.offsetBy(dx: -o.x, dy: -o.y), fin = vers.offsetBy(dx: -o.x, dy: -o.y)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        calque.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        calque.contentsGravity = .resizeAspect      // jamais déformée ni rognée
        calque.masksToBounds = true
        calque.cornerCurve = .continuous
        calque.cornerRadius = arrondiDépart
        calque.backgroundColor = NSColor.clear.cgColor
        calque.opacity = 1
        calque.frame = départ
        CATransaction.commit()
        p.alphaValue = 1
        p.orderFrontRegardless()
        CATransaction.flush()
        // Le mouvement : départ vif, arrivée longue et douce, comme les fenêtres de macOS.
        CATransaction.begin()
        CATransaction.setAnimationDuration(durée)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1))
        CATransaction.setCompletionBlock(arrivée)
        calque.frame = fin
        calque.cornerRadius = arrondiArrivée
        CATransaction.commit()
    }

    /// La vraie fenêtre est en place : la photo s'efface en fondu bref.
    static func effacer(après délai: TimeInterval = 0.12) {
        DispatchQueue.main.asyncAfter(deadline: .now() + délai) {
            guard let p = panneau else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.12)
            CATransaction.setCompletionBlock { p.orderOut(nil) }
            calque.opacity = 0
            CATransaction.commit()
        }
    }
}
