// Ouvrir et fermer le tiroir, à la main ou aux quatre doigts.
// Partie de PanneauBas (PanneauBas.swift), rangée à part le 15/11/2026 sans changement.

import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

extension PanneauBas {
    // MARK: Ouverture
    /// Met le panneau en place, caché sous le bord, avec les photos des tuiles : prêt à glisser.
    func préparerOuverture() -> Bool {
        guard Partie.tiroir.active else { journalBas("tiroir coupé dans les réglages : pas d'ouverture"); return false }
        // Pendant une capture d'écran, le tiroir ne s'ouvre par aucun geste.
        // Le tiroir s'ouvre sur l'écran de la souris (16/11/2026 ; avant : celui de la fenêtre active), et y reste.
        guard !ouvert, !CaptureEcran.enCours, let ecran = Ecrans.deTravail else { return false }
        écranOuvert = ecran
        ouvert = true
        ouvertÀ = Date()
        vivantes = []
        serie += 1
        pidAvant = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let p = panneau ?? construire()
        panneau = p
        publierFenêtres()                          // le tiroir lui-même compte parmi « ses » fenêtres (double flèche du bord)
        let fin = cadre(ecran)
        p.setFrame(fin, display: false)
        disposerLeFond(fin)
        sansFenêtres = dansUnPleinÉcranApple()
        notesIntrouvables = []                       // à chaque ouverture, on redonne sa chance à une note introuvable
        // Une fenêtre restée sur un autre bureau n'est jamais réclamée : macOS vous y renverrait. Sa tuile reste en photo.
        ailleursNoms = sansFenêtres ? [] : Set(emprunts.filter { surUnAutreBureau($0) }.map { $0.nom })
        banniere.isHidden = !sansFenêtres && ailleursNoms.isEmpty
        boutonBanniere?.isHidden = !sansFenêtres
        messageBanniere.stringValue = sansFenêtres
            ? String(localized: "Plein écran d'Apple : macOS empêche d'y afficher les tuiles.")
            : String(localized: "En photo : \(ailleursNoms.sorted().joined(separator: ", ")) — fenêtre ouverte sur un autre bureau.")
        if sansFenêtres { journalBas("ouvert par-dessus un plein écran d'Apple : tuiles en photo") }
        if !ailleursNoms.isEmpty { journalBas("sur un autre bureau, laissées en photo : %@", ailleursNoms.sorted().joined(separator: ", ")) }
        défilement = min(défilement, arrêts(fin).maxi)
        poser(0)
        poserImages(fraîches: false)
        p.orderFrontRegardless()
        enPlace = false
        défile = false
        // Pendant le glissement, les vraies fenêtres, encore hors de l'écran, passent devant le panneau.
        installer(déjàArrivé: false)

        lecteur.rafraichir()
        minuteur = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.lecteur.rafraichir() }
        absences = [:]
        enMain = nil
        veille = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in self?.veiller() }
        TouchesBas.ajouter(idEchap, touche: UInt32(kVK_Escape), modifs: 0) { [weak self] in self?.fermer(rendreLaMain: true) }
        ecouteClics = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let p = self.panneau, !p.frame.contains(NSEvent.mouseLocation) else { return }
            guard ConfigTiroir.commun.fermerAuClic else { return }
            guard !self.captureEnCours() else { journalBas("clic ailleurs ignoré : capture d'écran en cours"); return }
            journalBas("clic ailleurs")
            self.fermer(rendreLaMain: false)
        }
        return true
    }

    /// (Ré)installe les vraies fenêtres des tuiles entièrement visibles ; les autres restent en photo, rangées hors de l'écran.
    func installer(déjàArrivé: Bool) {
        guard let p = panneau else { return }
        serie += 1
        guard !sansFenêtres else { return }       // par-dessus un plein écran d'Apple : on ne touche à aucune fenêtre
        // Tant que le mot d'accueil est affiché, les tuiles restent en photo : une vraie fenêtre passerait devant lui.
        guard bienvenue == nil else { return }
        glissé = déjàArrivé
        glisséÀ = Date()
        enGrand = nil                              // la fenêtre sortie en grand revient dans le tiroir
        replacements = [:]
        stables = [:]
        posées = []
        demandées = []
        levées = 0
        dernierLever = .distantPast
        let visibles = entières(p.frame).filter { !ailleursNoms.contains($0.0.nom) }
        ranger(sauf: Set(visibles.map { $0.0.nom }))
        préparer(visibles, serie: serie)
    }

    func arrivé() {
        guard ouvert else { return }
        enPlace = true
        glissé = true
        glisséÀ = Date()
        panneau?.invalidateShadow()
        // Une note seule dans le tiroir : la grande fenêtre de Notes ne doit pas rester derrière elle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.fermerLeResteDeNotes() }
        if let i = tuileÀMontrer, let p = panneau, emprunts.indices.contains(i),
           !entières(p.frame).contains(where: { $0.0.nom == emprunts[i].nom }) { montrerTuile(i) }
        tuileÀMontrer = nil
    }

    func ouvrir() {
        guard préparerOuverture() else { return }
        journalBas("ouvert")
        // Le même glissement que la carte de Side : part avec élan, puis ralentit longuement pour se poser.
        glisser(vers: 1, duree: reduit ? 0.15 : 0.45, courbe: CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)) { [weak self] in
            self?.arrivé()
        }
    }

    // MARK: Quatre doigts : le panneau suit les doigts, à l'ouverture comme à la fermeture
    func commencerSuivi(fermeture: Bool) {
        if fermeture {
            guard ouvert, !suiviDoigts else { return }
            journalBas("quatre doigts (suivi de fermeture)")
            quitterLesFenêtres()
        } else {
            guard préparerOuverture() else { return }
            journalBas("quatre doigts (suivi d'ouverture)")
        }
        suiviDoigts = true
        fermetureSuivie = fermeture
    }

    /// Le tiroir est déjà ouvert et les doigts repartent dans le sens d'ouverture : le mini carrousel apparaît.
    func commencerNavigation() {
        guard uneApp, ouvert, enPlace, !suiviDoigts, emprunts.count > 1 else { return }
        suiviDoigts = true
        fermetureSuivie = false
        navDepuisOuvert = true
        ouvrirMiniCarrousel()
        journalBas("quatre doigts (mini carrousel)")
    }

    /// La place de l'application affichée dans le tiroir, en coordonnées de l'écran (origine en bas à gauche).
    func zoneÉcran() -> CGRect? {
        guard let p = panneau, emprunts.indices.contains(rangCourant) else { return nil }
        return zoneÉcran(pour: p.frame)
    }
    /// La place de l'application dans un tiroir posé à ce cadre (coordonnées de l'écran, origine en bas à gauche).
    func zoneÉcran(pour cadreTiroir: CGRect) -> CGRect {
        let z = bande(cadreTiroir)
        let x = z.minX + débutTuiles, w = max(200, z.width - débutTuiles - largeurColonne - marge)
        return Ecrans.versNS(CGRect(x: x, y: z.minY, width: w, height: z.height))   // z est en AX : retour au repère AppKit
    }

    func ouvrirMiniCarrousel() {
        guard let p = panneau, let ecran = écranDuTiroir, let z = zoneÉcran() else { return }
        let départ = rangCourant
        navDepart = départ
        let visibles = Set(entières(p.frame).map { $0.0.nom })
        let imgs: [NSImage?] = emprunts.map { e in
            // L'application affichée est rephotographiée (elle a pu changer) ; les autres gardent leur dernière photo.
            photo(e, taille: z.size, fraîche: visibles.contains(e.nom)) ?? photos[e.nom]
        }
        let icos: [NSImage?] = emprunts.map { NSWorkspace.shared.icon(forFile: $0.chemin) }
        CarrouselTiroir.commun.ouvrir(images: imgs, icones: icos, depart: départ, zone: z, ecran: ecran, enHaut: enHaut)
    }

    /// p : 0 = caché, 1 = à sa place ; au-delà (une app à la fois), le mini carrousel suit les doigts.
    func suivreDoigts(_ p: CGFloat) {
        guard suiviDoigts, ouvert else { return }
        // Une fois le sélecteur apparu, les doigts peuvent monter et descendre librement : le tiroir ne se referme jamais
        // pendant le geste ; au lâcher, l'application choisie prend la place et le tiroir reste ouvert.
        if uneApp, !fermetureSuivie, navDepuisOuvert || navDepart != nil || p > 1, emprunts.count > 1 {
            if !navDepuisOuvert { poser(1) }
            if navDepart == nil { ouvrirMiniCarrousel() }
            guard let d = navDepart else { return }
            // Sans fin : on peut monter ou descendre aussi loin qu'on veut, les applications reviennent en boucle.
            let q = (p - 1) / parApp
            CarrouselTiroir.commun.placer(CGFloat(d) + q, anime: false)
            // La mise en avant de la colonne de droite suit l'application du centre, pendant le geste (17/11/2026).
            marquerIcône(CarrouselTiroir.commun.rangCentral)
            return
        }
        poser(min(1, max(0, p)))
    }

    /// Doigts levés pendant le mini carrousel : la carte du centre grandit jusqu'à sa place, et l'application la remplace.
    func finirMiniCarrousel() {
        guard let d = navDepart, let p = panneau else { return }
        navDepart = nil
        let depuisOuvert = navDepuisOuvert
        navDepuisOuvert = false
        let pos = CarrouselTiroir.commun.position, n = emprunts.count
        var cible = CarrouselTiroir.commun.rangCentral
        // La liste a pu changer pendant le geste (une application du tiroir a quitté) : on ne vise pas une tuile disparue.
        guard n > 0, emprunts.indices.contains(cible) else { CarrouselTiroir.commun.masquer(); return }
        // Comme le carrousel du plein écran : un petit geste bref suffit pour passer à la voisine (en faisant le tour).
        if cible == d, abs(pos - CGFloat(d)) > 0.22, abs(pos - CGFloat(d)) < 0.5 { cible = ((d + (pos > CGFloat(d) ? 1 : -1)) % n + n) % n }
        if let z = zoneÉcran() { CarrouselTiroir.commun.fermer(sur: cible, zone: z) }
        if cible != d {
            journalBas("application du tiroir : %@", emprunts[cible].nom)
            if depuisOuvert { _ = commencerDéfilement() }
            défilement = arrêts(p.frame).débuts[cible]
            déplacerImages(animé: false)
        }
        // Le temps que la carte arrive à sa place, puis la vraie fenêtre prend le relais.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.ouvert else { return }
            // Un nouveau geste a déjà commencé (on enchaîne les gestes pour aller à une application éloignée) : les vraies
            // fenêtres attendent sa fin. Les poser maintenant, sous le carrousel, le faisait saccader (17/11/2026).
            if depuisOuvert, self.navDepart != nil {
                if cible != d { self.installationEnAttente = true }
                return
            }
            let àPoser = cible != d || self.installationEnAttente
            self.installationEnAttente = false
            if depuisOuvert {
                if àPoser { self.défile = false; self.installer(déjàArrivé: true) }
            } else {
                self.arrivé()
                if àPoser { self.défile = false; self.installer(déjàArrivé: true) }
            }
        }
    }

    /// Doigts levés : le panneau finit sa course sur sa lancée, dans un sens ou dans l'autre.
    func lacherDoigts(ouvrir: Bool, elan: CGFloat) {
        guard suiviDoigts else { return }
        suiviDoigts = false
        guard ouvert else { return }
        // Le mini carrousel était affiché : l'application choisie prend la place.
        if navDepart != nil { finirMiniCarrousel(); return }
        let reste = ouvrir ? 1 - q : q
        let suite = AppDelegate.elan(reste: reste, vitesse: ouvrir ? elan : -elan)
        if ouvrir {
            // Fermeture annulée en route : les fenêtres, déjà rangées, reviennent à leur place.
            if fermetureSuivie { installer(déjàArrivé: false) }
            glisser(vers: 1, duree: suite.duree, courbe: suite.courbe) { [weak self] in self?.arrivé() }
        } else {
            terminerFermeture(rendreLaMain: true, duree: suite.duree, courbe: suite.courbe)
        }
    }

    // MARK: Fermeture
    /// Les vraies fenêtres laissent la place à leurs photos, puis sont rangées hors de l'écran.
    func quitterLesFenêtres() {
        selecteur.fermer()
        serie += 1          // arrête la surveillance en cours
        glissé = false
        enPlace = false
        finDéfilement?.cancel()
        if !sansFenêtres {
            if !défile { retenir(); poserImages() }
            ranger(sauf: [])
        }
        défile = false
    }

    func terminerFermeture(rendreLaMain: Bool, duree: TimeInterval, courbe: CAMediaTimingFunction) {
        guard ouvert else { return }
        ouvert = false
        // Un mini carrousel encore affiché disparaît avec le tiroir.
        if navDepart != nil { navDepart = nil; navDepuisOuvert = false; CarrouselTiroir.commun.masquer() }
        suiviDoigts = false
        serie += 1
        minuteur?.invalidate()
        minuteur = nil
        veille?.invalidate()
        veille = nil
        PanneauBas.boutonsVerts = []
        PanneauBas.fenêtreRelayable = nil
        PanneauBas.boutonsJaunes = []
        TouchesBas.retirer(idEchap)
        if let e = ecouteClics { NSEvent.removeMonitor(e) }
        ecouteClics = nil
        if rendreLaMain, pidAvant != 0, let avant = NSRunningApplication(processIdentifier: pidAvant), !estEmpruntée(avant) {
            avant.activate(options: [])
        }
        let maSerie = serie
        glisser(vers: 0, duree: duree, courbe: courbe) { [weak self] in
            guard let self, !self.ouvert, self.serie == maSerie else { return }
            self.panneau?.orderOut(nil)
        }
        ferméÀ = Date()
        journalBas("fermé")
    }

    /// La vidéo sort en plein écran : le tiroir se referme, sans rendre la main à l'application d'avant.
    func fermerPourLaVideo() { fermer(rendreLaMain: false) }

    /// Le réglage « une application à la fois » a changé : le tiroir se referme, il se recomposera à la prochaine ouverture.
    func majDisposition() {
        défilement = 0
        if ouvert { fermer(rendreLaMain: false) }
    }

    /// « Masquer les Shorts » : appliqué aux pages YouTube déjà ouvertes.
    /// Les réglages de la page YouTube (Shorts, posts, pastilles, sponsors) : appliqués tout de suite, sans recharger.
    func appliquerShorts() { lecteursWeb.forEach { $0.appliquerReglages() } }
    /// Minuteur de sommeil écoulé : toutes les vidéos du tiroir se mettent en pause.
    func mettreEnPause() { lecteursWeb.forEach { $0.mettreEnPause() }; TuilePeinard.mettreEnPause() }

    func fermer(rendreLaMain: Bool) {
        guard ouvert else { return }
        if !suiviDoigts || !fermetureSuivie { quitterLesFenêtres() }
        // Comme la carte de Side : la fermeture est plus brève que l'ouverture.
        terminerFermeture(rendreLaMain: rendreLaMain, duree: reduit ? 0.12 : 0.26,
                          courbe: CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0.4))
    }

    // MARK: Plein écran d'Apple
    /// L'espace affiché est-il un plein écran d'Apple ? (Les fenêtres des autres applications ne peuvent pas y venir.)
    /// L'écran du tiroir : celui choisi à l'ouverture tant qu'il est ouvert (et toujours branché), sinon celui de la souris.
    var écranDuTiroir: NSScreen? {
        if ouvert, let e = écranOuvert, NSScreen.screens.contains(e) { return e }
        return Ecrans.deTravail
    }

    /// Le tiroir s'ouvre-t-il par-dessus un plein écran d'Apple ? On regarde l'écran du tiroir (avant le 16/11/2026 :
    /// toujours le premier écran, faux avec deux écrans).
    func dansUnPleinÉcranApple() -> Bool { Ecrans.pleinEcranApple(sur: écranDuTiroir) }

    /// Bouton du bandeau : l'application de derrière quitte le plein écran d'Apple et remplit l'écran à la place
    /// (un faux plein écran). Le panneau se rouvre ensuite, avec ses vraies tuiles.
    @objc func sortirDuPleinÉcran() {
        let pid = pidAvant
        fermer(rendreLaMain: true)
        guard pid != 0 else { return }
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &v)
        guard let f = ((v as? [AXUIElement]) ?? []).first(where: { el in
            var plein: CFTypeRef?
            AXUIElementCopyAttributeValue(el, "AXFullScreen" as CFString, &plein)
            return (plein as? Bool) == true
        }) else { journalBas("pas de fenêtre en plein écran à convertir"); return }
        journalBas("sortie du plein écran d'Apple")
        AXUIElementSetAttributeValue(f, "AXFullScreen" as CFString, kCFBooleanFalse)
        func attendre(_ reste: Int) {
            var plein: CFTypeRef?
            AXUIElementCopyAttributeValue(f, "AXFullScreen" as CFString, &plein)
            if (plein as? Bool) == true, reste > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { attendre(reste - 1) }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                if let ecran = Ecrans.deTravail, let principal = NSScreen.screens.first {
                    let z = ecran.visibleFrame
                    AXBas.placer(f, CGRect(x: z.minX, y: principal.frame.height - z.maxY, width: z.width, height: z.height))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.ouvrir() }
            }
        }
        attendre(16)
    }
}
