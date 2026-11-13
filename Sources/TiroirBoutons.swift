// Le bouton vert des applications du tiroir. Survolé, macOS ouvre de lui-même son menu « Déplacer et redimensionner » :
// dans le tiroir, il n'a pas de sens. Une petite fenêtre invisible de Side est donc posée juste au-dessus de chaque bouton
// vert : la souris la survole elle, et non l'application, qui ne voit jamais le survol. Le clic, lui, est déjà pris en
// charge par le filtre de clics du tiroir (il sort l'application au centre de l'écran).
import AppKit

enum CachesBoutonsVerts {
    private static var caches: [NSPanel] = []

    /// `cadres` : les boutons verts visibles, en coordonnées de l'écran à l'origine en haut à gauche. Vide : tout disparaît.
    static func placer(_ cadres: [CGRect]) {
        while caches.count < cadres.count { caches.append(nouveau()) }
        for (i, c) in caches.enumerated() {
            if i < cadres.count {
                c.setFrame(TransitionFenetre.versÉcran(cadres[i].insetBy(dx: -2, dy: -2)), display: false)
                if !c.isVisible { c.orderFrontRegardless() }
            } else if c.isVisible {
                c.orderOut(nil)
            }
        }
    }

    private static func nouveau() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = NSColor(white: 1, alpha: 0.002)     // presque rien : assez pour recevoir la souris
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.animationBehavior = .none
        p.hidesOnDeactivate = false
        p.contentView?.toolTip = String(localized: "Sortir du tiroir")
        return p
    }
}
