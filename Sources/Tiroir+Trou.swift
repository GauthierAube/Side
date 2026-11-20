// Une application à la fois, version fiable (20/11/2026).
// Avant, le tiroir passait derrière l'application affichée et se battait avec macOS pour qu'elle reste devant lui :
// il réactivait les applications, reprenait la main, se repassait dessous, plusieurs fois par seconde. Chaque essai
// pouvait rater (application lente, macOS qui rend la main à l'application d'avant) : l'application clignotait,
// apparaissait ou non, et le tiroir se refermait parfois tout seul.
// Maintenant, le tiroir laisse un TROU à la place de l'application. Quel que soit l'ordre des fenêtres, on la voit
// au travers, et un clic dans le trou va directement à elle. Il ne reste qu'une chose à réussir : poser la fenêtre et
// activer son application, une fois. Le tiroir vérifie que c'est bien elle qu'on voit avant d'enlever la photo.

import AppKit

extension PanneauBas {
    /// Ouvre un trou dans le fond du tiroir, à la place de cette fenêtre (coordonnées globales, origine en haut à gauche),
    /// ou le referme (nil). Le trou est tout à fait transparent : macOS y laisse passer les clics vers la fenêtre de dessous.
    func trouer(_ zoneAX: CGRect?) {
        guard let fond, let teinte else { return }
        guard let z = zoneAX, let p = panneau else {
            guard trou != nil else { return }
            trou = nil
            majFond()                         // le fond retrouve son masque habituel (plein, ou « sans fond »)
            teinte.layer?.mask = nil
            return
        }
        trou = z
        let r = fond.convert(p.convertFromScreen(Ecrans.versNS(z)), from: nil)
        let rayon = Rayon.fenetre
        let taille = fond.bounds.size
        // Le flou : un masque de la taille du fond, plein partout sauf dans le trou.
        if ConfigTiroir.commun.fond {
            let masque = NSImage(size: taille, flipped: false) { tout in
                NSColor.black.setFill()
                tout.fill()
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(roundedRect: r, xRadius: rayon, yRadius: rayon).fill()
                return true
            }
            masque.resizingMode = .stretch
            fond.maskImage = masque
        }
        // La teinte (et le voile presque invisible du mode « sans fond ») : percée au même endroit.
        let forme = CAShapeLayer()
        let chemin = CGMutablePath()
        chemin.addRect(teinte.bounds)
        chemin.addRoundedRect(in: teinte.convert(r, from: fond), cornerWidth: rayon, cornerHeight: rayon)
        forme.path = chemin
        forme.fillRule = .evenOdd
        teinte.layer?.mask = forme
        p.invalidateShadow()
    }

    /// La fenêtre (d'une autre application) qu'on voit à cet endroit de l'écran, Side mis à part.
    func fenêtreVueÀ(_ point: CGPoint) -> Int? {
        let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let moi = Int(ProcessInfo.processInfo.processIdentifier)
        for w in infos {
            guard (w[kCGWindowOwnerPID as String] as? Int) != moi, ((w[kCGWindowLayer as String] as? Int) ?? 0) < 20,
                  ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0.05,
                  let d = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: d), r.contains(point)
            else { continue }
            return w[kCGWindowNumber as String] as? Int
        }
        return nil
    }

    /// Fait passer l'application devant, avec le clavier, sur sa fenêtre du tiroir.
    /// Deux façons à la fois : par l'Accessibilité (la plus sûre depuis une application de fond comme Side) et par AppKit.
    func activer(_ a: NSRunningApplication, _ f: AXUIElement) {
        activations += 1
        activéeÀ = Date()
        if a.isHidden { a.unhide() }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        a.activate(options: [])
        AXBas.lever(f)
        AXUIElementSetAttributeValue(f, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    /// Une app à la fois : pose la fenêtre de l'application affichée à sa place, active son application, et n'enlève la
    /// photo que lorsque c'est bien cette fenêtre qu'on voit dans le tiroir. Pendant quatre secondes au plus.
    func installerUneApp(_ visibles: [(EmpruntBas, CGRect)], serie maSerie: Int, essais: Int = 80, installéeÀ: Date? = nil) {
        guard ouvert, serie == maSerie, !défile, let (e, zone) = visibles.first else { return }
        guard essais > 0 else {
            if trou == nil { journalBas("%@ : fenêtre pas venue en 4 s, la tuile reste en photo", e.nom) }
            return
        }
        let suite = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.installerUneApp(visibles, serie: maSerie, essais: essais - 1, installéeÀ: self?.installéeÀ)
            }
        }
        guard let a = app(e), let f = fenetre(e) else {
            if !posées.contains(e.nom) { demander(e) }      // l'application n'a pas encore de fenêtre : on la lui demande (une fois)
            suite()
            return
        }
        placer(e, f, zone)
        // La fenêtre doit d'abord être à sa place (son coin, au moins : une application de taille fixe garde la sienne).
        guard let c = AXBas.cadre(f), posées.contains(e.nom) || (abs(c.minX - zone.minX) < 3 && abs(c.minY - zone.minY) < 3) else {
            suite()
            return
        }
        var wid: CGWindowID = 0
        _ = _AXUIElementGetWindow(f, &wid)
        let devant = NSWorkspace.shared.frontmostApplication?.processIdentifier == a.processIdentifier
        let vue = fenêtreVueÀ(CGPoint(x: c.midX, y: c.midY)) == Int(wid)
        if !devant || !vue {
            // Pas encore elle qu'on voit, ou plus elle : macOS rend souvent la main à l'application d'avant une fraction de
            // seconde après l'avoir donnée. On (re)demande, au plus huit fois, en laissant à macOS le temps de suivre.
            if installéeÀ != nil { journalBas("%@ repassée derrière (%@ devant) : on la ramène", e.nom, NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") }
            if Date().timeIntervalSince(activéeÀ) > 0.25, activations < 8 { activer(a, f) }
            suite()
            return
        }
        let visible = c.intersection(zone.insetBy(dx: -1, dy: -1))
        if trou.map({ !$0.equalTo(visible) }) ?? true {
            images[e.nom]?.isHidden = true
            trouer(visible)
            mainRendue = serie
            journalBas("%@ dans le tiroir (%d activation(s))", e.nom, activations)
        }
        // On continue de veiller jusqu'à ce qu'elle soit stable (posée, et toujours devant 1,5 s après son arrivée).
        self.installéeÀ = installéeÀ ?? Date()
        if !posées.contains(e.nom) || Date().timeIntervalSince(self.installéeÀ ?? Date()) < 1.5 { suite() }
    }

    /// Pendant que le tiroir est ouvert : le trou suit la fenêtre si on la déplace ou la redimensionne.
    func suivreLeTrou() {
        guard uneApp, let t = trou, let p = panneau, let (e, zone) = entières(p.frame).first, let f = fenetre(e),
              let cadre = AXBas.cadre(f) else { return }
        let c = cadre.intersection(zone.insetBy(dx: -1, dy: -1))
        guard !c.isEmpty else { return }
        if abs(c.minX - t.minX) > 1 || abs(c.minY - t.minY) > 1 || abs(c.width - t.width) > 1 || abs(c.height - t.height) > 1 { trouer(c) }
    }
}
