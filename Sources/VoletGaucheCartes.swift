// Les cartes du volet à plusieurs vues (18/11/2026), à la manière de Slide Over sur l'iPad : pendant le geste, la vue en cours
// est une carte qui glisse vers le bord de l'écran (gauche ou droit, en miroir) en suivant les doigts ; la vue suivante attend derrière, un peu plus petite
// et assombrie, et grandit pour prendre sa place. Vers la précédente, c'est l'inverse : elle revient du bord par-dessus,
// et la vue en cours recule derrière. Ce sont des photos des fenêtres ; les vraies prennent la place à l'arrivée.
import AppKit

final class CartesPile {
    static let commun = CartesPile()

    struct Disposition: Equatable {
        var devant: NSRect, derrière: NSRect
        var voile: CGFloat            // assombrissement de la carte de derrière (0 : aucun)
    }

    private static let échelleDerrière: CGFloat = 0.92
    private static let voileDerrière: CGFloat = 0.3

    private static func réduit(_ r: NSRect, _ é: CGFloat) -> NSRect {
        r.insetBy(dx: r.width * (1 - é) / 2, dy: r.height * (1 - é) / 2)
    }

    /// La place des deux cartes pour une avancée de 0 (départ) à 1 (arrivée). Sens +1 : la carte de devant part vers la gauche
    /// et découvre celle de derrière. Sens -1 : le même mouvement, joué à l'envers (la carte revient du bord).
    static func disposition(_ cadre: NSRect, avancée: CGFloat, sens: Int, droite: Bool = false) -> Disposition {
        let p = min(max(sens > 0 ? avancée : 1 - avancée, 0), 1)
        var devant = réduit(cadre, 1 - 0.04 * p)
        devant.origin.x += (droite ? 1 : -1) * p * (cadre.width + 60)      // vers le bord de l'écran
        let derrière = réduit(cadre, échelleDerrière + (1 - échelleDerrière) * p)
        return Disposition(devant: devant, derrière: derrière, voile: voileDerrière * (1 - p))
    }

    /// Au bout de la liste : la carte suit un peu les doigts, de moins en moins, puis revient.
    static func élastique(_ cadre: NSRect, avancée: CGFloat, sens: Int, droite: Bool = false) -> NSRect {
        let d = 60 * (1 - 1 / (1 + max(avancée, 0) * 2))
        return cadre.offsetBy(dx: (droite ? 1 : -1) * CGFloat(sens) * d, dy: 0)
    }

    // MARK: Les deux calques

    // Comme le carrousel du tiroir : un seul panneau de la taille de l'écran, et des calques que la carte graphique
    // déplace et agrandit elle-même. (Changer la taille d'une fenêtre à chaque image saccadait.)
    private final class Carte {
        let calque = CALayer()        // porte l'ombre
        let image = CALayer()         // la photo, aux coins arrondis
        let voile = CALayer()

        init() {
            calque.shadowColor = NSColor.black.cgColor
            calque.shadowOpacity = 0.35
            calque.shadowRadius = 22
            calque.shadowOffset = CGSize(width: 0, height: -8)
            image.masksToBounds = true
            image.cornerCurve = .continuous
            image.cornerRadius = Rayon.fenetre
            image.contentsGravity = .resize
            voile.backgroundColor = NSColor.black.cgColor
            voile.opacity = 0
            image.addSublayer(voile)
            calque.addSublayer(image)
        }

        func préparer(_ img: NSImage, taille: CGSize) {
            calque.bounds = CGRect(origin: .zero, size: taille)
            image.frame = calque.bounds
            voile.frame = calque.bounds
            image.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
            calque.shadowPath = CGPath(roundedRect: calque.bounds, cornerWidth: Rayon.fenetre, cornerHeight: Rayon.fenetre, transform: nil)
            calque.isHidden = false
        }

        /// Place la carte sur ce rectangle (coordonnées du panneau) : un déplacement et un agrandissement, sans redessin.
        func poser(_ r: CGRect) {
            calque.position = CGPoint(x: r.midX, y: r.midY)
            let é = r.width / max(calque.bounds.width, 1)
            calque.transform = CATransform3DMakeScale(é, é, 1)
        }
    }

    private var panneau: NSPanel?
    private let devant = Carte(), derrière = Carte()
    private var cadre = NSRect.zero        // la place du volet, en coordonnées du panneau
    private var sens = 1
    private var seule = false              // pas de carte voisine : la carte de devant fait l'élastique
    private var droite = false             // volet de droite : tout est en miroir
    private var tour = 0

    private func sansAnimation(_ f: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        f()
        CATransaction.commit()
    }

    private func placer(_ avancée: CGFloat) {
        if seule {
            devant.poser(CartesPile.élastique(cadre, avancée: avancée, sens: sens, droite: droite))
            return
        }
        let d = CartesPile.disposition(cadre, avancée: avancée, sens: sens, droite: droite)
        devant.poser(d.devant)
        derrière.poser(d.derrière)
        derrière.voile.opacity = Float(d.voile)
    }

    /// Pose les cartes au départ du mouvement. `devant` est la carte du dessus (la vue en cours vers la suivante,
    /// la vue précédente sinon) ; `derrière` manque quand il n'y a qu'une vue. `cadre` : la place du volet à l'écran.
    func préparer(devant imgDevant: NSImage, derrière imgDerrière: NSImage?, cadre cadreÉcran: NSRect, sens: Int, droite: Bool) {
        guard let écran = NSScreen.screens.first(where: { $0.frame.intersects(cadreÉcran) }) ?? NSScreen.main else { return }
        let p = panneau ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.animationBehavior = .none
            let v = NSView()
            v.wantsLayer = true
            v.layer?.addSublayer(derrière.calque)
            v.layer?.addSublayer(devant.calque)
            p.contentView = v
            panneau = p
            return p
        }()
        tour += 1
        p.setFrame(écran.frame, display: false)
        cadre = cadreÉcran.offsetBy(dx: -écran.frame.minX, dy: -écran.frame.minY)
        self.sens = sens
        self.droite = droite
        seule = imgDerrière == nil
        sansAnimation {
            devant.calque.removeAllAnimations()
            derrière.calque.removeAllAnimations()
            derrière.voile.removeAllAnimations()
            devant.préparer(imgDevant, taille: cadre.size)
            if let imgDerrière { derrière.préparer(imgDerrière, taille: cadre.size) } else { derrière.calque.isHidden = true }
            placer(0)
        }
        p.alphaValue = 1
        p.orderFrontRegardless()
        CATransaction.flush()
    }

    /// Les cartes à cette avancée (pendant le geste : elles suivent les doigts, sans animation).
    func dessiner(_ avancée: CGFloat) {
        sansAnimation { placer(avancée) }
    }

    /// Finit le mouvement jusqu'à cette avancée (1 : la carte change, 0 : elle revient) : départ vif, arrivée douce.
    func finir(vers cible: CGFloat, depuis avancée: CGFloat, fin: @escaping () -> Void) {
        let reste = Double(min(max(abs(cible - avancée), 0.35), 1))
        CATransaction.begin()
        CATransaction.setAnimationDuration(Mouvement.duree(0.42) * reste)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1))
        CATransaction.setCompletionBlock(fin)
        placer(seule ? 0 : cible)
        CATransaction.commit()
    }

    /// La vraie fenêtre est en place : les cartes s'effacent en fondu bref.
    func effacer() {
        guard let p = panneau else { return }
        let monTour = tour
        NSAnimationContext.runAnimationGroup({ $0.duration = Mouvement.duree(Mouvement.bref); p.animator().alphaValue = 0 }) { [weak self] in
            if self?.tour == monTour { p.orderOut(nil) }
        }
    }

    func cacher() { tour += 1; panneau?.orderOut(nil) }
}
