// Le mini carrousel du tiroir : le même que celui du plein écran (quatre doigts vers la gauche ou la droite), mais vertical,
// en miniature, centré sur l'application affichée dans le tiroir. Pendant le geste, les applications du tiroir apparaissent en
// petites cartes qui suivent les doigts ; celle du centre est plus grande. Doigts levés, elle grandit jusqu'à la place de
// l'application dans le tiroir, qui la remplace.
import AppKit

final class CarrouselTiroir {
    static let commun = CarrouselTiroir()
    private var panneau: NSPanel?
    private let scene = NSView()
    private let groupe = CALayer()
    private var cartes: [(carte: CALayer, image: CALayer)] = []
    private var largeur: CGFloat = 240, hauteur: CGFloat = 150     // la carte du centre
    private let petit: CGFloat = 0.62                               // taille des autres, par rapport à celle du centre
    private var centre = CGPoint.zero                               // dans la scène
    /// Sens de l'empilement : les cartes suivent les doigts (vers le haut pour un tiroir du bas).
    private var sensY: CGFloat = -1
    private(set) var visible = false
    private(set) var position: CGFloat = 0
    /// L'application sous le centre, en faisant le tour.
    var rangCentral: Int {
        let n = max(cartes.count, 1)
        return ((Int(position.rounded()) % n) + n) % n
    }

    private func construire() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.animationBehavior = .none
        scene.wantsLayer = true
        scene.layer?.addSublayer(groupe)
        p.contentView = scene
        return p
    }

    /// `zone` : la place de l'application dans le tiroir, en coordonnées de l'écran (origine en bas à gauche).
    func ouvrir(images: [NSImage?], icones: [NSImage?], depart: Int, zone: CGRect, ecran: NSScreen, enHaut: Bool) {
        let p = panneau ?? construire()
        panneau = p
        sensY = enHaut ? 1 : -1
        p.setFrame(ecran.frame, display: false)
        // Des cartes à la proportion de l'application, en miniature (un peu plus d'un cinquième de sa hauteur).
        hauteur = max(80, min(140, (zone.height * 0.22).rounded()))
        largeur = (hauteur * max(1.2, min(2.4, zone.width / max(zone.height, 1)))).rounded()
        centre = CGPoint(x: zone.midX - ecran.frame.minX, y: zone.midY - ecran.frame.minY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        groupe.frame = CGRect(origin: .zero, size: ecran.frame.size)
        cartes.forEach { $0.carte.removeFromSuperlayer() }
        cartes = zip(images, icones).map { img, ico in
            let carte = CALayer()
            carte.bounds = CGRect(x: 0, y: 0, width: largeur, height: hauteur)
            carte.shadowColor = NSColor.black.cgColor
            carte.shadowOpacity = 0.5
            carte.shadowRadius = 18
            carte.shadowOffset = CGSize(width: 0, height: -8)
            carte.shadowPath = CGPath(roundedRect: carte.bounds, cornerWidth: 14, cornerHeight: 14, transform: nil)
            let image = CALayer()
            image.frame = carte.bounds
            image.cornerRadius = 14
            image.cornerCurve = .continuous
            image.masksToBounds = true
            image.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
            image.contentsGravity = .resizeAspectFill
            image.contents = img?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            image.borderColor = NSColor.controlAccentColor.cgColor
            carte.addSublayer(image)
            // L'icône de l'application, à cheval sur le bord gauche de la carte.
            let icone = CALayer()
            let cote = (hauteur * 0.38).rounded()
            icone.frame = CGRect(x: -cote * 0.4, y: hauteur / 2 - cote / 2, width: cote, height: cote)
            icone.contents = ico?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            icone.shadowOpacity = 0.4
            icone.shadowRadius = 5
            icone.shadowOffset = CGSize(width: 0, height: -2)
            carte.addSublayer(icone)
            groupe.addSublayer(carte)
            return (carte, image)
        }
        groupe.opacity = 0
        groupe.transform = CATransform3DMakeScale(0.9, 0.9, 1)
        CATransaction.commit()
        placer(CGFloat(depart), anime: false)
        p.alphaValue = 1
        p.orderFrontRegardless()
        visible = true
        // Apparition : comme le carrousel du plein écran, un fondu bref en grossissant un peu.
        CATransaction.flush()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.13)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1))
        groupe.opacity = 1
        groupe.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    /// Amène la position p (en nombre d'applications, éventuellement entre deux) au centre. Les cartes sont posées sur une roue,
    /// comme les sélecteurs à molette d'Apple : en tournant, elles rapetissent et s'effacent vers l'arrière, puis reviennent de
    /// l'autre côté en grossissant. Rien ne saute : le carrousel tourne sans fin.
    func placer(_ p: CGFloat, anime: Bool) {
        position = p
        let n = CGFloat(max(cartes.count, 1))
        let pas = hauteur * petit + 10
        // Le rayon de la roue : deux cartes voisines restent à « pas » l'une de l'autre près du centre.
        let angleParCarte = 2 * CGFloat.pi / max(n, 3)
        let rayon = pas / max(sin(angleParCarte), 0.5)
        CATransaction.begin()
        if anime {
            CATransaction.setAnimationDuration(0.16)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else { CATransaction.setDisableActions(true) }
        for (i, c) in cartes.enumerated() {
            var d = CGFloat(i) - p
            d -= n * (d / n).rounded()                       // l'écart le plus court en faisant le tour
            let angle = d * angleParCarte
            let profondeur = (cos(angle) + 1) / 2                  // 1 devant, 0 tout au fond de la roue
            let proche = 1 - min(abs(d), 1)
            let taille = (petit + (1 - petit) * proche) * (0.45 + 0.55 * profondeur)
            c.carte.position = CGPoint(x: centre.x, y: centre.y + sensY * rayon * sin(angle))
            c.carte.transform = CATransform3DMakeScale(taille, taille, 1)
            c.carte.opacity = Float(min(1, max(0, (profondeur - 0.08) * 1.7)))
            c.carte.zPosition = profondeur * 10
            c.image.borderWidth = proche > 0.5 ? 3 : 0
        }
        CATransaction.commit()
    }

    /// Le tiroir se referme pendant le geste : tout s'efface, sans rien choisir.
    func masquer() {
        guard visible, let p = panneau else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; p.animator().alphaValue = 0 }) {
            if !self.visible { p.orderOut(nil) }
        }
    }

    /// Doigts levés : la carte choisie grandit jusqu'à la place de l'application dans le tiroir, les autres s'effacent.
    func fermer(sur index: Int, zone: CGRect) {
        guard visible, let p = panneau else { return }
        visible = false
        let f = p.frame
        let arrivee = CGRect(x: zone.minX - f.minX, y: zone.minY - f.minY, width: zone.width, height: zone.height)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 0.8, 0.3, 1))
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, !self.visible else { return }
            p.orderOut(nil)
        }
        for (i, c) in cartes.enumerated() {
            if i == index {
                c.carte.zPosition = 20
                c.carte.position = CGPoint(x: arrivee.midX, y: arrivee.midY)
                c.carte.transform = CATransform3DMakeScale(arrivee.width / largeur, arrivee.height / hauteur, 1)
                c.image.borderWidth = 0
                c.carte.shadowOpacity = 0
                c.carte.sublayers?.last?.opacity = 0
            } else {
                c.carte.opacity = 0
            }
        }
        CATransaction.commit()
    }
}
