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
        // Horizon a plusieurs fenêtres (sa grande fenêtre, et chaque vue du tiroir) : la vue passe d'abord devant les
        // autres fenêtres d'Horizon, puis Horizon est activé sans « premier plan » forcé. macOS n'amène alors que cette
        // fenêtre, comme un clic dessus. Avec le premier plan forcé, toutes ses fenêtres remontaient, la grande devant
        // le tiroir, qui disparaissait (20/11/2026).
        if a.bundleIdentifier == VuesHorizon.bundle {
            AXBas.lever(f)
            a.activate(options: [])
            AXBas.lever(f)
            AXUIElementSetAttributeValue(f, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            return
        }
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
            placerVoileAgrandi()
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
        // (Agrandi : la fenêtre a la taille que macOS lui a donnée, on suit son cadre tel quel.)
        let c = agrandi ? cadre : cadre.intersection(zone.insetBy(dx: -1, dy: -1))
        guard !c.isEmpty else { return }
        if agrandi, tic % 4 == 0 { placerVoileAgrandi() }
        if abs(c.minX - t.minX) > 1 || abs(c.minY - t.minY) > 1 || abs(c.width - t.width) > 1 || abs(c.height - t.height) > 1 { trouer(c) }
    }
}

// MARK: Agrandir le tiroir, le temps d'une grosse tâche (20/11/2026)
extension PanneauBas {
    /// Le bouton de la colonne, ⌃⌥ Entrée (le raccourci « Agrandir » de Square) ou un double-clic sur le bord :
    /// le tiroir monte presque en plein écran, l'application avec lui ; la même chose le fait redescendre aussitôt.
    @objc func basculerAgrandi() {
        guard ouvert, enPlace, uneApp, !suiviDoigts, !enDirect, !enTransition, let p = panneau, let ecran = écranDuTiroir else { return }
        finDéfilement?.cancel()
        défile = false
        let rang = rangCourant
        let courante = entières(p.frame).first?.0
        let a = courante.flatMap { app($0) }, f = courante.flatMap { fenetre($0) }
        agrandi.toggle()
        journalBas(agrandi ? "tiroir agrandi" : "tiroir réduit")
        majBoutonAgrandir()
        if agrandi { montrerVoileAgrandi() } else { cacherVoileAgrandi() }
        enTransition = true
        serie += 1                                  // arrête l'installation en cours
        trouer(nil)
        PanneauBas.pastilleÉcran = nil
        images.values.forEach { $0.isHidden = true }
        // Le tiroir (colonne, coin multimédia) s'efface pendant que la fenêtre change de taille, puis revient en fondu.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduit ? 0.05 : 0.1
            p.animator().alphaValue = 0
        }
        // À la fin du mouvement : le tiroir prend sa nouvelle taille et reparaît.
        let suite = { [weak self] in
            guard let self, self.ouvert else { self?.enTransition = false; return }
            let fin = self.cadre(ecran)
            p.level = self.agrandi ? .floating : .normal     // agrandi : le bouton « réduire » flotte au-dessus de l'application
            p.setFrame(fin, display: true)
            self.garderLeRang(rang, fin)
            self.disposerLeFond(fin)
            self.poser(1)
            p.alphaValue = 0
            self.déplacerImages(animé: false)
            self.images.values.forEach { $0.isHidden = true }
            p.invalidateShadow()
            self.enTransition = false
            if self.agrandi {
                // L'application garde la taille que macOS lui a donnée : le tiroir ne la repose pas, il ouvre son trou sur elle.
                if let f, let c = AXBas.cadre(f) { self.trouer(c) }
                if let n = courante?.nom { self.posées.insert(n) }
                self.placerVoileAgrandi()
            } else {
                self.installer(déjàArrivé: true)
                if let n = courante?.nom { self.images[n]?.isHidden = true }
            }
            self.révélerLeTiroir()
        }
        guard let a, let f, let avant = AXBas.cadre(f) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { suite() }
            return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != a.processIdentifier { activer(a, f) }
        // C'est macOS (l'application elle-même) qui anime sa fenêtre, comme quand on l'agrandit à la main : d'abord le zoom
        // du Mac (celui du bouton vert avec ⌥), sinon les commandes du menu Fenêtre (« Remplir », « Réduire/agrandir »).
        // Pour revenir : la même commande dans l'autre sens.
        let essais: [(nom: String, menu: [String]?)]
        if agrandi {
            essais = [("zoom", nil), ("remplir", ["Remplir", "Fill"]), ("zoom du menu", ["Réduire/agrandir", "Zoom"])]
        } else {
            switch commandeAgrandi {
            case "zoom": essais = [("zoom", nil)]
            case "remplir": essais = [("retour", ["Rétablir la taille précédente", "Return to Previous Size"])]
            case "zoom du menu": essais = [("zoom du menu", ["Réduire/agrandir", "Zoom"])]
            default: essais = []
            }
        }
        let visible = Ecrans.versAX(ecran.visibleFrame)
        func tenter(_ i: Int) {
            guard i < essais.count else {
                // Aucune commande du Mac n'a répondu : la fenêtre est posée directement (agrandie), ou par l'installation (réduite).
                if self.agrandi { self.commandeAgrandi = nil; AXBas.placer(f, visible) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { suite() }
                return
            }
            let essai = essais[i]
            let aprèsLaCommande: (Bool) -> Void = { lancée in
                guard lancée else { tenter(i + 1); return }
                self.attendreLaFenêtre(f, depuis: avant) { bougé in
                    guard bougé else { tenter(i + 1); return }
                    if self.agrandi { self.commandeAgrandi = essai.nom }
                    journalBas("fenêtre %@ par macOS (%@)", self.agrandi ? "agrandie" : "réduite", essai.nom)
                    suite()
                }
            }
            if let menu = essai.menu { aprèsLaCommande(self.presserMenuFenêtre(a, menu)) } else { self.zoomer(f, puis: aprèsLaCommande) }
        }
        // Un court instant, que l'application soit bien devant.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { tenter(0) }
    }

    /// Le zoom du Mac sur cette fenêtre (l'action « zoom » de son bouton vert, pas le plein écran d'Apple). L'application
    /// anime elle-même sa fenêtre ; la demande part hors du fil principal, pour ne pas figer Side pendant le mouvement.
    func zoomer(_ f: AXUIElement, puis fin: @escaping (Bool) -> Void) {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(f, kAXZoomButtonAttribute as CFString, &v)
        guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { fin(false); return }
        let bouton = v as! AXUIElement
        var noms: CFArray?
        AXUIElementCopyActionNames(bouton, &noms)
        guard ((noms as? [String]) ?? []).contains("AXZoomWindow") else { fin(false); return }
        DispatchQueue.global(qos: .userInteractive).async {
            _ = AXUIElementPerformAction(bouton, "AXZoomWindow" as CFString)
            DispatchQueue.main.async { fin(true) }
        }
    }

    /// Presse une ligne du menu Fenêtre de l'application (dans la langue du Mac ou en anglais), sous-menus compris.
    func presserMenuFenêtre(_ a: NSRunningApplication, _ intitulés: [String]) -> Bool {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXMenuBarAttribute as CFString, &v)
        guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return false }
        func chercher(_ el: AXUIElement, _ profondeur: Int) -> AXUIElement? {
            for c in enfants(el) {
                if intitulés.contains(titre(c)) {
                    var actif: CFTypeRef?
                    AXUIElementCopyAttributeValue(c, kAXEnabledAttribute as CFString, &actif)
                    if (actif as? Bool) ?? true { return c }
                }
                if profondeur < 4, let trouvé = chercher(c, profondeur + 1) { return trouvé }
            }
            return nil
        }
        for rubrique in enfants(v as! AXUIElement) where ["Fenêtre", "Window"].contains(titre(rubrique)) {
            if let ligne = chercher(rubrique, 0) { return AXUIElementPerformAction(ligne, kAXPressAction as CFString) == .success }
        }
        return false
    }

    /// Attend que la fenêtre ait bougé puis se soit arrêtée (l'animation de macOS est finie). `bougé` : faux si rien
    /// ne s'est passé en 0,8 s (la commande n'a pas eu d'effet).
    func attendreLaFenêtre(_ f: AXUIElement, depuis départ: CGRect, fin: @escaping (Bool) -> Void) {
        let début = CACurrentMediaTime()
        var dernier = départ, calme = 0, bougé = false
        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { t in
            let c = AXBas.cadre(f) ?? dernier
            let écoulé = CACurrentMediaTime() - début
            if !c.equalTo(départ) { bougé = true }
            calme = c.equalTo(dernier) ? calme + 1 : 0
            dernier = c
            if !bougé, écoulé > 0.8 { t.invalidate(); fin(false); return }
            if bougé, calme >= 3 || écoulé > 1.5 { t.invalidate(); fin(true) }
        }
    }

    /// Le tiroir réapparaît en fondu, après un agrandissement ou une réduction.
    func révélerLeTiroir() {
        guard let p = panneau else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduit ? 0.08 : 0.2
            p.animator().alphaValue = 1
        }
    }

    /// Une app à la fois : la position de défilement se compte en hauteurs de tiroir. Quand la hauteur change,
    /// on la recalcule pour rester sur la même application (sinon aucune n'était plus « à l'écran » et rien ne s'installait).
    func garderLeRang(_ rang: Int, _ fin: CGRect) {
        guard uneApp else { return }
        let a = arrêts(fin)
        if a.débuts.indices.contains(rang) { défilement = a.débuts[rang] }
    }

    /// On tire un bord du tiroir agrandi : il redevient un tiroir ordinaire, à la taille qu'on lui donne.
    func quitterAgrandi() {
        guard agrandi else { return }
        agrandi = false
        panneau?.level = .normal
        PanneauBas.pastilleÉcran = nil
        majBoutonAgrandir()
        cacherVoileAgrandi()
        if let p = panneau { placerLecteurs(hauteur: bande(p.frame).height, animé: false) }
    }

    func majBoutonAgrandir() {
        let symbole = agrandi ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        let aide = agrandi ? String(localized: "Réduire le tiroir (⌃⌥ Entrée)") : String(localized: "Agrandir le tiroir (⌃⌥ Entrée)")
        boutonAgrandir.image = NSImage(systemSymbolName: symbole, accessibilityDescription: aide)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .semibold))
        boutonAgrandir.toolTip = aide
    }

    // MARK: Le voile flou derrière le tiroir agrandi
    /// Le même voile que celui du Finder de Side (flou « hudWindow », teinte claire ou sombre, force réglée dans les
    /// réglages) : tout ce qui est derrière le tiroir agrandi est flouté, on ne voit plus que l'application.
    /// Il laisse passer les clics et se tient juste derrière le tiroir et son application.
    func montrerVoileAgrandi() {
        guard let ecran = écranDuTiroir else { return }
        let v: NSPanel
        if let déjà = voileAgrandi { v = déjà } else {
            v = NSPanel(contentRect: ecran.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            v.isOpaque = false
            v.backgroundColor = .clear
            v.hasShadow = false
            v.ignoresMouseEvents = true
            v.level = .normal
            v.animationBehavior = .none
            v.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
            let effet = NSVisualEffectView(frame: NSRect(origin: .zero, size: ecran.frame.size))
            effet.material = .hudWindow
            effet.blendingMode = .behindWindow
            effet.state = .active
            effet.autoresizingMask = [.width, .height]
            let teinte = NSView(frame: effet.bounds)
            teinte.wantsLayer = true
            teinte.autoresizingMask = [.width, .height]
            effet.addSubview(teinte)
            v.contentView = effet
            voileAgrandi = v
        }
        let sombre = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        v.appearance = NSAppearance(named: sombre ? .darkAqua : .aqua)
        v.contentView?.subviews.first?.layer?.backgroundColor = (sombre ? NSColor.black : NSColor.white).withAlphaComponent(0.16).cgColor
        v.setFrame(ecran.frame, display: true)
        if !v.isVisible { v.alphaValue = 0 }
        v.orderFrontRegardless()
        placerVoileAgrandi()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduit ? 0.1 : 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            v.animator().alphaValue = CGFloat(Config.shared.flouForce)
        }
    }

    /// Le voile passe juste derrière le tiroir et la fenêtre de l'application, celle des deux qui est le plus en arrière.
    func placerVoileAgrandi() {
        guard agrandi, let v = voileAgrandi, v.isVisible, let p = panneau else { return }
        let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let ordre = infos.compactMap { $0[kCGWindowNumber as String] as? Int }
        var repères = [p.windowNumber]
        if let (e, _) = entières(p.frame).first, let f = fenetre(e) {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(f, &wid) == .success { repères.append(Int(wid)) }
        }
        guard let plusLoin = repères.max(by: { (ordre.firstIndex(of: $0) ?? -1) < (ordre.firstIndex(of: $1) ?? -1) }),
              let rangLoin = ordre.firstIndex(of: plusLoin) else { return }
        // Déjà juste derrière : rien à faire (on ne réordonne pas les fenêtres pour rien).
        if let rangVoile = ordre.firstIndex(of: v.windowNumber), rangVoile == rangLoin + 1 { return }
        v.order(.below, relativeTo: plusLoin)
    }

    func cacherVoileAgrandi(immédiat: Bool = false) {
        guard let v = voileAgrandi, v.isVisible else { return }
        if immédiat { v.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduit ? 0.08 : 0.2
            v.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.agrandi || !self.ouvert else { return }
            v.orderOut(nil)
        })
    }
}

// MARK: Clics dans le trou, Échap
extension PanneauBas {
    /// Le tiroir ignore la souris tant que le pointeur est dans le trou : le clic va à l'application, même quand le tiroir
    /// est passé devant elle (un clic sur sa colonne d'icônes, par exemple). `point` : coordonnées globales du pointeur.
    func majClicsDansLeTrou(_ point: CGPoint?) {
        let p = point ?? Ecrans.versAX(NSRect(origin: NSEvent.mouseLocation, size: .zero)).origin
        let dans = ouvert && (trou?.contains(p) ?? false) && !(PanneauBas.pastilleÉcran?.contains(p) ?? false)
        PanneauBas.pointeurDansLeTrou = dans
        if panneau?.ignoresMouseEvents != dans { panneau?.ignoresMouseEvents = dans }
    }

    /// Échap : le tiroir agrandi redescend ; sinon, le tiroir se referme.
    func échap() {
        if agrandi { basculerAgrandi() } else { fermer(rendreLaMain: true) }
    }
}
