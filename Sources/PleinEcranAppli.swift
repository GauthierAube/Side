// Le plein écran : son pilotage (raccourcis, carrousel, grille, coins).
// Sorti de PleinEcran.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

final class Appli: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panneau: Panneau?
    private let grille = Grille()
    private var espaces: [Espace] = []
    private var tuiles: [Tuile] = []
    private var ouverteÀ = Date.distantPast
    /// La grille est en train de mener elle-même une application devant (case choisie, lancement depuis son Dock,
    /// retour) : l'activation qui en découle ne doit pas la refermer d'un coup.
    private var enMouvement = false
    private var activationsIgnoréesJusquÀ = Date.distantPast
    private var pidDevant: pid_t = 0         // application devant en ce moment
    private var pidAvant: pid_t = 0          // celle d'avant
    private var fenetreRaccourci: NSWindow?
    private var ecoute: Any?

    private let idGrille: UInt32 = 1
    private let idAgrandir: UInt32 = 2
    private let chiffres: [Int] = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
    private let pavé: [Int] = [kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5,
                               kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9]

    /// Démarre le module plein écran (appelé une fois par l'AppDelegate de l'app). Plus d'icône à lui dans la barre des menus :
    /// ses actions sont dans le menu de l'app.
    func demarrer() {
        Groupes.nettoyer()

        grille.auChoix = { [weak self] c in self?.choisir(c.tuile, depuis: c) }
        grille.auFond = { [weak self] in self?.fermerGrilleEnRevenant() }
        grille.auFermer = { [weak self] t in self?.fermer(t) }
        grille.auTiroir = { [weak self] t in
            self?.fermerGrille()
            PanneauBas.commun.envoyerAuTiroir(pid: t.pid)
        }
        grille.auDepot = { [weak self] t, d in self?.deposer(t, d) }
        grille.dock.auLancement = { [weak self] chemin in self?.lancerDepuisLeDock(chemin) }
        grille.dock.auBoutonApps = { [weak self] in self?.basculerLanceur() }
        grille.dock.auCorbeille = { [weak self] in
            self?.fermerGrille()
            // La corbeille s'ouvre dans le Finder de l'app.
            if !AppDelegate.shared.estOuvert { AppDelegate.shared.basculer() }
            Corbeille.montrer()
        }
        grille.dock.auQuitter = { [weak self] chemin in self?.quitterDepuisLeDock(chemin) }
        Lanceur.commun.auChoix = { [weak self] chemin in self?.lancerDepuisLeDock(chemin) }
        Lanceur.commun.auDock = { [weak self] in self?.grille.dock.charger(); self?.grille.needsLayout = true }
        Lanceur.commun.aLaFermeture = { [weak self] in
            self?.lanceurFermeA = Date()
            // Les chiffres et Échap de la grille reprennent du service.
            if let e = self?.ecouteLanceur { NSEvent.removeMonitor(e) }
            self?.ecouteLanceur = nil
            if self?.panneau?.isVisible == true { self?.brancherTouchesGrille() }
        }

        brancherRaccourci()
        AgrandirAuto.demarrer()
        BoutonVert.demarrer()
        Glisse.demarrer()
        CoinGrille.demarrer()
        brancherRaccourcisDirects()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(ouvrirReglages),
                                                            name: .init("com.gauthieraube.square.reglages"), object: nil)
        // Commandes venues d'une autre application (Mulot, pour les boutons de la souris).
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(commandeExterieure(_:)),
                                                            name: .init("com.gauthieraube.square.commande"), object: nil)
        Touches.ajouter(idAgrandir, touche: UInt32(kVK_Return), modifs: UInt32(controlKey | optionKey)) {
            // Tiroir ouvert (une app à la fois) : le même raccourci agrandit ou réduit le tiroir (20/11/2026).
            if PanneauBas.commun.ouvert, ConfigTiroir.commun.uneApp { PanneauBas.commun.basculerAgrandi(); return }
            if Partie.pleinEcran.active { Agrandir.fenetreActive() }
        }
        // Partie « Plein écran » coupée ou rallumée dans les réglages : ses raccourcis ⌘1 à ⌘9 suivent.
        NotificationCenter.default.addObserver(forName: Partie.changement, object: nil, queue: .main) { [weak self] _ in
            self?.brancherRaccourcisDirects()
        }

        pidDevant = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let centre = NSWorkspace.shared.notificationCenter
        centre.addObserver(self, selector: #selector(espaceChangé), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        centre.addObserver(self, selector: #selector(appActivée(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        // La présentation du plein écran fait partie de celle de l'app (elle s'enchaîne après la sienne).
        // Autorisations demandées une fois : Accessibilité (pour déplacer les fenêtres) et Enregistrement de l'écran (pour les images).
        let cle = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([cle: true] as CFDictionary)
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        // Première série de photos dès le lancement : la grille aura ses images à la première ouverture.
        Images.commun.capturer(Relevé.tout().espaces) {}
    }

    // (L'ancien menu de Square, dans la barre des menus, n'existe plus : Side a le sien.)

    @objc func agrandirActive() {
        // Le menu vient de se fermer : on laisse l'application d'avant reprendre la main.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Agrandir.fenetreActive() }
    }




    @objc func ouvrirReglages() {
        fermerGrille()          // la grille flotte au-dessus de tout : la fenêtre de réglages resterait cachée derrière
        // Une seule fenêtre de réglages pour toute l'app : elle s'ouvre sur la rubrique de la grille.
        AppDelegate.shared.fermerReglages()
        Volet.demande = .grille
        AppDelegate.shared.ouvrirReglages()
    }

    // MARK: Raccourcis directs : une touche et un chiffre pour aller droit à la fenêtre de ce numéro

    /// La touche à tenir avec le chiffre : "cmd", "opt", "ctrl", ou "aucun" pour ne pas avoir ces raccourcis.
    static var toucheDirecte: String {
        get { UserDefaults.standard.string(forKey: "raccourcisDirects") ?? "cmd" }
        set { UserDefaults.standard.set(newValue, forKey: "raccourcisDirects") }
    }

    /// (Ré)enregistre les neuf raccourcis, d'après le réglage.
    func brancherRaccourcisDirects() {
        for i in 0..<9 { Touches.retirer(UInt32(200 + i)) }
        guard Partie.pleinEcran.active else { return }     // partie coupée : ⌘1 à ⌘9 sont rendus aux autres applications
        let modifs: Int
        switch Appli.toucheDirecte {
        case "cmd": modifs = cmdKey
        case "opt": modifs = optionKey
        case "ctrl": modifs = controlKey
        default: return
        }
        for i in 0..<9 {
            Touches.ajouter(UInt32(200 + i), touche: UInt32(chiffres[i]), modifs: UInt32(modifs)) { [weak self] in self?.allerALaFenetre(i) }
        }
    }

    /// Va droit à la fenêtre numéro n + 1, dans l'ordre des cases de la grille.
    private func allerALaFenetre(_ n: Int) {
        guard Partie.pleinEcran.active else { return }
        // Un numéro de « Mes applications » : va droit à cette application, et l'ouvre si elle ne l'est pas.
        let mes = MesApps.commun.liste
        if mes.indices.contains(n) {
            let b = mes[n].bundle
            if panneau?.isVisible == true { fermerGrille() }
            let (tous, courants) = Relevé.tout()
            let apps = construire(tous)
            if let t = apps.first(where: { NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier == b }) {
                let ecran = Ecrans.identifiant(ecranSousLaSouris())
                guard t.cle != cléCourante(tous, courants, ecran: ecran) else { return }
                journal("Square: raccourci %d → %@ (mes applications)", n + 1, mes[n].nom)
                espaces = tous
                Bascule.aller(t, espaces: tous)
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) {
                journal("Square: raccourci %d → ouvre %@", n + 1, mes[n].nom)
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
            return
        }
        if panneau?.isVisible == true {
            if grille.cases.indices.contains(n) { choisir(grille.cases[n].tuile, depuis: grille.cases[n]) }
            return
        }
        let (tous, courants) = Relevé.tout()
        let apps = construire(tous).filter { if case .espace(let e) = $0.cible { return e.pleinEcran }; return true }
        guard apps.indices.contains(n) else { NSSound.beep(); return }
        let ecran = Ecrans.identifiant(ecranSousLaSouris())
        guard apps[n].cle != cléCourante(tous, courants, ecran: ecran) else { return }     // on y est déjà
        journal("Square: raccourci %d → %@", n + 1, apps[n].titre.components(separatedBy: " — ").first ?? "")
        espaces = tous
        Bascule.aller(apps[n], espaces: tous)
    }

    /// Une autre application demande une action de Square : « grille », « suivante », « precedente » ou « agrandir ».
    @objc private func commandeExterieure(_ note: Notification) {
        guard let commande = note.object as? String else { return }
        if !commande.hasPrefix("carrousel:suivre") { journal("Square: commande reçue — %@", commande) }   // pas 60 lignes par seconde
        switch commande {
        case "grille": basculerGrille()
        case "suivante": voisine(1)
        case "precedente": voisine(-1)
        case "agrandir": Agrandir.fenetreActive()
        case "aller-side":                                // pour les essais : aller à la fenêtre de Side (la vidéo), comme le carrousel
            let (tous, _) = Relevé.tout()
            if let t = construire(tous).first(where: { $0.pid == ProcessInfo.processInfo.processIdentifier }) { Bascule.aller(t, espaces: tous) }
            else { journal("Square: aller-side — pas de fenêtre de Side dans les cases") }
        default:
            // Le carrousel mené de l'extérieur (bouton de pouce de la souris tenu pendant qu'on la déplace, ou molette du pouce) :
            // « carrousel:debut », « carrousel:suivre:<position> », « carrousel:fin:<position> », « carrousel:cran:<±1> ».
            let morceaux = commande.split(separator: ":").map(String.init)
            guard morceaux.first == "carrousel", morceaux.count >= 2 else { return }
            let valeur = morceaux.count > 2 ? CGFloat(Double(morceaux[2]) ?? 0) : 0
            switch morceaux[1] {
            case "debut": carrouselDebut()
            case "suivre": carrouselSuivre(valeur)
            case "fin": carrouselFin(valeur)
            case "cran": carrouselParCrans(valeur > 0 ? 1 : -1)
            default: break
            }
        }
    }

    private var carrouselCrans = 0
    private var carrouselAttente: Timer?

    /// La molette du pouce : chaque cran avance le carrousel d'une fenêtre ; quand la molette s'arrête un instant,
    /// la fenêtre du centre passe devant. On voit ainsi où l'on va, au lieu de changer de fenêtre à chaque cran.
    private func carrouselParCrans(_ d: Int) {
        if carrouselApps.isEmpty {
            carrouselDebut()
            carrouselCrans = 0
            guard !carrouselApps.isEmpty else { return }
        }
        carrouselCrans += d                    // une roue sans fin : on fait le tour
        if !Carrousel.roue { carrouselCrans = min(max(carrouselCrans, -carrouselDepart), carrouselApps.count - 1 - carrouselDepart) }
        Carrousel.commun.placer(CGFloat(carrouselDepart + carrouselCrans), anime: true)
        carrouselAttente?.invalidate()
        carrouselAttente = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.carrouselFin(CGFloat(self.carrouselCrans))
            self.carrouselCrans = 0
        }
    }

    /// Pour la fenêtre de réglages : changer le raccourci, et montrer ou cacher l'aperçu du carrousel.
    func reglerLeRaccourci() { changerRaccourci() }
    /// L'aperçu des réglages s'efface tout seul peu après le dernier changement, ou au premier clic, où qu'il soit.
    func apercuDuCarrousel(_ visible: Bool) {
        finApercu?.invalidate(); finApercu = nil
        guard visible else { fermerApercu(); return }
        apercuCarrousel(anime: !Carrousel.commun.visible)
        finApercu = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in self?.fermerApercu() }
        if clicsApercu.isEmpty {
            if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.fermerApercu() }) { clicsApercu.append(g) }
            if let l = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] e in
                // Un clic sur le curseur de taille garde l'aperçu (on est en train de régler) ; ailleurs, il le ferme.
                if !(e.window?.contentView?.hitTest(e.locationInWindow) is NSSlider) { self?.fermerApercu() }
                return e
            }) { clicsApercu.append(l) }
        }
    }
    private var finApercu: Timer?
    private var clicsApercu: [Any] = []
    private func fermerApercu() {
        finApercu?.invalidate(); finApercu = nil
        clicsApercu.forEach { NSEvent.removeMonitor($0) }; clicsApercu = []
        Carrousel.commun.masquer()
    }



    /// La souris est arrivée dans le coin choisi : la grille s'affiche (si elle l'est déjà, rien ne change).
    func grilleParLeCoin() {
        guard Partie.pleinEcran.active else { return }
        // Grille déjà affichée : un second passage dans le coin la referme, et vous retrouvez l'application où vous étiez.
        if panneau?.isVisible == true { journal("Square: grille refermée par le coin"); fermerGrilleEnRevenant(); return }
        journal("Square: grille ouverte par le coin")
        ouvrirGrille()
    }

    @objc private func resserrerGrille() {
        UserDefaults.standard.removeObject(forKey: "placesCases")
        UserDefaults.standard.removeObject(forKey: "placesApps")
    }

    // MARK: Carrousel (glissement à quatre doigts)

    private var fenetreCarrousel: NSWindow?

    /// Réglage de la taille des cartes : une petite fenêtre en bas de l'écran, et le carrousel lui-même en aperçu au centre.
    @objc private func reglerCarrousel() {
        if let w = fenetreCarrousel { w.makeKeyAndOrderFront(nil); return }
        guard let ecran = ecranSousLaSouris() else { return }
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 176), styleMask: [.titled, .closable],
                        backing: .buffered, defer: false)
        w.title = String(localized: "Carrousel à quatre doigts")
        w.isReleasedWhenClosed = false
        w.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)     // au-dessus de l'aperçu
        w.hidesOnDeactivate = false
        let petit = NSTextField(labelWithString: String(localized: "Petit")), grand = NSTextField(labelWithString: String(localized: "Grand"))
        petit.frame = NSRect(x: 20, y: 122, width: 44, height: 18)
        grand.frame = NSRect(x: 362, y: 122, width: 44, height: 18)
        let curseur = NSSlider(value: Double(Carrousel.taille), minValue: Double(Carrousel.tailles.lowerBound),
                               maxValue: Double(Carrousel.tailles.upperBound), target: self, action: #selector(tailleCarrouselChangée(_:)))
        curseur.isContinuous = true
        curseur.frame = NSRect(x: 66, y: 118, width: 290, height: 26)
        let titreTaille = NSTextField(labelWithString: String(localized: "Taille des cartes"))
        titreTaille.font = .systemFont(ofSize: 12, weight: .semibold)
        titreTaille.frame = NSRect(x: 20, y: 146, width: 380, height: 18)
        // Le délai avant d'afficher le carrousel quand le geste part vite.
        let titreDelai = NSTextField(labelWithString: String(localized: "Après un geste vif, le carrousel apparaît…"))
        titreDelai.font = .systemFont(ofSize: 12, weight: .semibold)
        titreDelai.frame = NSRect(x: 20, y: 80, width: 380, height: 18)
        let tot = NSTextField(labelWithString: String(localized: "Vite")), tard = NSTextField(labelWithString: String(localized: "Tard"))
        tot.frame = NSRect(x: 20, y: 56, width: 44, height: 18)
        tard.frame = NSRect(x: 362, y: 56, width: 44, height: 18)
        let delai = NSSlider(value: Glisse.attente, minValue: 0.04, maxValue: 0.35, target: self, action: #selector(delaiCarrouselChangé(_:)))
        delai.isContinuous = true
        delai.frame = NSRect(x: 66, y: 52, width: 290, height: 26)
        let aide = NSTextField(wrappingLabelWithString: String(localized: "Vers « Vite » : il apparaît plus tôt, mais un simple effleurement risque de l'afficher. Vers « Tard » : l'inverse."))
        aide.font = .systemFont(ofSize: 11)
        aide.textColor = .secondaryLabelColor
        aide.frame = NSRect(x: 20, y: 12, width: 384, height: 32)
        for v in [titreTaille, petit, curseur, grand, titreDelai, tot, delai, tard, aide] as [NSView] { w.contentView?.addSubview(v) }
        let v = ecran.visibleFrame
        w.setFrameOrigin(NSPoint(x: v.midX - 210, y: v.minY + 40))
        fenetreCarrousel = w
        NotificationCenter.default.addObserver(self, selector: #selector(fenetreCarrouselFermée), name: NSWindow.willCloseNotification, object: w)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        apercuCarrousel(anime: true)
    }

    @objc private func delaiCarrouselChangé(_ curseur: NSSlider) { Glisse.attente = (curseur.doubleValue * 100).rounded() / 100 }

    @objc private func tailleCarrouselChangée(_ curseur: NSSlider) {
        Carrousel.taille = CGFloat(curseur.doubleValue.rounded())
        apercuCarrousel(anime: false)
    }

    /// Le carrousel tel qu'il apparaîtra, avec vos fenêtres du moment.
    private func apercuCarrousel(anime: Bool) {
        guard let ecran = fenetreCarrousel?.screen ?? ecranSousLaSouris() else { return }
        let (tous, courants) = Relevé.tout()
        let apps = construire(tous).filter { if case .espace(let e) = $0.cible { return e.pleinEcran }; return true }
        guard !apps.isEmpty else { return }
        let ici = cléCourante(tous, courants, ecran: Ecrans.identifiant(ecran))
        let depart = apps.firstIndex { $0.cle == ici } ?? min(1, apps.count - 1)
        Carrousel.commun.ouvrir(apps, depart: depart, espaces: tous, ecran: ecran, anime: anime)
    }

    @objc private func fenetreCarrouselFermée() {
        guard let w = fenetreCarrousel else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: w)
        fenetreCarrousel = nil
        Carrousel.commun.masquer()
    }

    private var carrouselApps: [Tuile] = []
    private var carrouselDepart = 0

    /// Les quatre doigts partent à l'horizontale : le carrousel apparaît, calé sur la fenêtre où vous êtes.
    func carrouselDebut() {
        carrouselApps = []
        guard !CaptureEcran.enCours, fenetreCarrousel == nil, panneau?.isVisible != true, let ecran = ecranSousLaSouris() else { return }
        let (tous, courants) = Relevé.tout()
        let id = Ecrans.identifiant(ecran)
        // Avec plusieurs bureaux sur l'écran, c'est macOS qui glisse d'un bureau à l'autre : on ne s'en mêle pas.
        guard tous.filter({ $0.ecran == id }).count == 1 || UserDefaults.standard.bool(forKey: "glisseToujours") || Glisse.systemeLibre else { return }
        let apps = construire(tous).filter { if case .espace(let e) = $0.cible { return e.pleinEcran }; return true }
        guard apps.count > 1 else { return }
        espaces = tous
        carrouselApps = apps
        let ici = cléCourante(tous, courants, ecran: id)
        carrouselDepart = apps.firstIndex { $0.cle == ici } ?? 0
        Glisse.bornes = Carrousel.roue ? nil : Float(-carrouselDepart)...Float(apps.count - 1 - carrouselDepart)
        Carrousel.commun.ouvrir(apps, depart: carrouselDepart, espaces: tous, ecran: ecran)
        Images.commun.capturer(tous) { [weak self] in if let self { Carrousel.commun.rafraichir(espaces: self.espaces) } }
    }

    /// Pas de boucle (essayée puis retirée le 12/11 : on s'y perd) : on s'arrête aux deux bouts.
    /// Comme le mini carrousel du tiroir (13/11/2026) : une roue sans fin. Après la dernière fenêtre revient la première.
    private func carrouselPosition(_ q: CGFloat) -> CGFloat {
        let p = CGFloat(carrouselDepart) + q
        return Carrousel.roue ? p : min(max(p, 0), CGFloat(carrouselApps.count - 1))     // la bande s'arrête aux deux bouts
    }
    /// Le rang de la fenêtre sous la position p, en faisant le tour.
    private func carrouselRang(_ p: CGFloat) -> Int {
        let n = max(carrouselApps.count, 1)
        return ((Int(p.rounded()) % n) + n) % n
    }

    func carrouselSuivre(_ q: CGFloat) {
        guard !carrouselApps.isEmpty else { return }
        Carrousel.commun.placer(carrouselPosition(q), anime: false)
    }

    /// Doigts levés : la fenêtre sous le cadre passe devant. Un petit geste bref suffit pour passer à la voisine.
    func carrouselFin(_ q: CGFloat) {
        guard !carrouselApps.isEmpty else { return }
        var cible = carrouselRang(carrouselPosition(q))
        if cible == carrouselDepart, abs(q) > 0.22, abs(q) < 0.5 { cible = carrouselRang(CGFloat(carrouselDepart + (q > 0 ? 1 : -1))) }
        // La case choisie est dans un autre espace que l'écran actuel (une vidéo de Safari dans un plein écran d'Apple, ou
        // l'inverse) : macOS va faire glisser tout l'écran d'un espace à l'autre. La carte ne grandit pas en plus jusqu'à
        // une place qui va de toute façon partir de côté (deux mouvements à la fois, ça saute) : le carrousel s'efface seul.
        let autreEspace: Bool = {
            guard carrouselApps.indices.contains(cible), let e = Bascule.espaceVise(carrouselApps[cible], espaces: espaces) else { return false }
            return Relevé.espaceCourant(ecran: e.ecran) != e.id
        }()
        if autreEspace, cible != carrouselDepart { Carrousel.commun.masquer() } else { Carrousel.commun.fermer(sur: cible) }
        let apps = carrouselApps
        carrouselApps = []
        guard cible != carrouselDepart else { return }
        journal("Square: quatre doigts → %@", apps[cible].titre.components(separatedBy: " — ").first ?? "")
        Bascule.aller(apps[cible], espaces: espaces)
    }

    /// Glissement à quatre doigts : passe à l'application agrandie voisine, dans l'ordre des cases de la grille.
    /// Avec plusieurs bureaux sur l'écran, c'est macOS qui glisse d'un bureau à l'autre : on ne s'en mêle pas.
    func voisine(_ sens: Int) {
        guard panneau?.isVisible != true, !CaptureEcran.enCours else { return }
        let (espaces, courants) = Relevé.tout()
        let ecran = Ecrans.identifiant(ecranSousLaSouris())
        guard espaces.filter({ $0.ecran == ecran }).count == 1 || UserDefaults.standard.bool(forKey: "glisseToujours") || Glisse.systemeLibre else { return }
        let apps = construire(espaces).filter { if case .espace(let e) = $0.cible { return e.pleinEcran }; return true }
        guard apps.count > 1 else { return }
        let ici = cléCourante(espaces, courants, ecran: ecran)
        let rang = apps.firstIndex { $0.cle == ici }
        // Aux deux bouts, on s'arrête, comme entre les bureaux. Depuis le bureau nu, on entre par le bout le plus proche.
        let cible = rang.map { $0 + sens } ?? (sens > 0 ? 0 : apps.count - 1)
        guard apps.indices.contains(cible) else { NSSound.beep(); return }
        journal("Square: quatre doigts → %@", apps[cible].titre.components(separatedBy: " — ").first ?? "")
        Bascule.aller(apps[cible], espaces: espaces)
    }

    @objc private func basculerAuto() {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() } else { try? SMAppService.mainApp.register() }
    }

    @objc private func ouvrirAccessibilité() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func ouvrirCapture() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    // MARK: Raccourci

    private func brancherRaccourci() {
        let r = Raccourci.actuel
        Touches.ajouter(idGrille, touche: r.touche, modifs: r.modifs) { [weak self] in self?.appuiRaccourci() }
    }

    private func appuiRaccourci() {
        guard Partie.pleinEcran.active || panneau?.isVisible == true else { return }
        if panneau?.isVisible == true {
            let rapide = Date().timeIntervalSince(ouverteÀ) < 0.4
            fermerGrille()
            if rapide { retourPrécédent() }         // double appui : application d'avant
        } else {
            ouvrirGrille()
        }
    }

    @objc private func changerRaccourci() {
        Touches.retirer(idGrille)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = String(localized: "Raccourci de la grille")
        w.isReleasedWhenClosed = false
        let t = NSTextField(wrappingLabelWithString: String(localized: "Appuyez sur le nouveau raccourci.\nIl faut au moins une touche ⌃ ⌥ ⇧ ou ⌘ (ou une touche F1 à F20).\nÉchap pour annuler."))
        t.alignment = .center
        t.frame = NSRect(x: 20, y: 20, width: 340, height: 80)
        w.contentView?.addSubview(t)
        w.center()
        fenetreRaccourci = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        ecoute = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.fenetreRaccourci else { return e }
            if Int(e.keyCode) == kVK_Escape { self.finRaccourci(); return nil }
            guard let r = Raccourci.depuis(e) else { NSSound.beep(); return nil }
            Raccourci.actuel = r
            self.finRaccourci()
            return nil
        }
        NotificationCenter.default.addObserver(self, selector: #selector(fenetreRaccourciFermée), name: NSWindow.willCloseNotification, object: w)
    }

    @objc private func fenetreRaccourciFermée() { finRaccourci() }

    private func finRaccourci() {
        guard let w = fenetreRaccourci else { return }
        fenetreRaccourci = nil
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: w)
        if let ecoute { NSEvent.removeMonitor(ecoute) }
        ecoute = nil
        w.close()
        brancherRaccourci()
    }

    // MARK: Grille

    private func ecranSousLaSouris() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(p) } ?? Ecrans.deTravail
    }

    /// Les vraies places (celles de tous les écrans, voir `construire`) des cases affichées, dans l'ordre : la case 0 de la
    /// grille est à la place `rangsGlobaux[0]`, etc. Pour ranger la grille d'un écran sans déranger celle de l'autre.
    private var rangsGlobaux: [Int] = []

    /// Les cases de la grille : celles de son écran seulement (23/11/2026), numérotées 0, 1, 2… dans l'ordre de toutes.
    private func casesDeLaGrille(_ espaces: [Espace], ecran: NSScreen) -> [Tuile] {
        var t = construire(espaces).filter { Self.estSur(ecran, $0) }
        rangsGlobaux = t.map { $0.place }
        for i in t.indices { t[i].place = i }
        return t
    }

    /// La vraie place d'une case de la grille affichée (une place au-delà de la dernière case reste au-delà).
    private func placeGlobale(_ p: Int) -> Int {
        if rangsGlobaux.indices.contains(p) { return rangsGlobaux[p] }
        return (rangsGlobaux.max() ?? -1) + 1 + max(0, p - rangsGlobaux.count)
    }

    /// La case est-elle sur cet écran ? Une fenêtre y est si son milieu y est ; un plein écran d'Apple ou un bureau, s'il est
    /// sur cet écran. Une fenêtre garée hors de tout écran (celles du tiroir) n'est sur aucun.
    static func estSur(_ ecran: NSScreen, _ t: Tuile) -> Bool {
        guard NSScreen.screens.count > 1 else { return true }
        let zone = Ecrans.cadreGlobal(ecran)                     // origine en haut à gauche, comme le cadre des fenêtres
        let dedans = { (f: Fenetre) in zone.contains(CGPoint(x: f.cadre.midX, y: f.cadre.midY)) }
        switch t.cible {
        case .fenetre(let f, _): return dedans(f)
        case .groupe(let fs, _): return fs.contains(where: dedans)
        case .espace(let e): return e.ecran == Ecrans.identifiant(ecran)
        }
    }

    /// Construit les cases : les fenêtres agrandies, les plein écran d'Apple, puis les bureaux.
    private func construire(_ espaces: [Espace]) -> [Tuile] {
        var haut: [Tuile] = [], bureaux: [Tuile] = []
        var membresDe: [String: [String]] = [:]       // pour chaque case de groupe, les cases de ses fenêtres
        var parApp: [pid_t: Int] = [:]
        // Une case par fenêtre, agrandie ou non. Le bureau lui-même n'a pas de case.
        func retenue(_ f: Fenetre) -> Bool { f.agrandie || !f.masquee }
        for e in espaces where !e.pleinEcran { for f in e.fenetres where retenue(f) { parApp[f.pid, default: 0] += 1 } }
        for e in espaces {
            if e.pleinEcran {
                guard let f = e.fenetres.first else { continue }
                var noms: [String] = []
                for x in e.fenetres where !noms.contains(x.app) { noms.append(x.app) }
                haut.append(Tuile(cle: "e\(e.id)", titre: noms.joined(separator: " + "),
                                  icone: NSRunningApplication(processIdentifier: f.pid)?.icon, cible: .espace(e), pid: f.pid))
            } else {
                var dejaGroupees: Set<CGWindowID> = []
                for f in e.fenetres where retenue(f) {
                    if dejaGroupees.contains(f.wid) { continue }
                    // Les fenêtres qui se partagent l'écran n'ont qu'une case à elles toutes.
                    let membres = e.fenetres.filter { retenue($0) && Groupes.ensemble($0.wid, f.wid) }
                    if membres.count > 1 {
                        dejaGroupees.formUnion(membres.map { $0.wid })
                        let cle = "g\(membres.map { $0.wid }.min() ?? f.wid)"
                        membresDe[cle] = membres.map { "f\($0.wid)" }
                        var noms: [String] = []
                        for x in membres where !noms.contains(x.app) { noms.append(x.app) }
                        haut.append(Tuile(cle: cle, titre: noms.joined(separator: " + "),
                                          icone: NSRunningApplication(processIdentifier: f.pid)?.icon, cible: .groupe(membres, e), pid: f.pid))
                        continue
                    }
                    let titre = (parApp[f.pid] ?? 0) > 1 && !f.titre.isEmpty ? "\(f.app) — \(f.titre)" : f.app
                    haut.append(Tuile(cle: "f\(f.wid)", titre: titre, icone: NSRunningApplication(processIdentifier: f.pid)?.icon,
                                      cible: .fenetre(f, e), pid: f.pid))
                }
            }
        }
        // Chaque fenêtre garde son rang. Une nouvelle prend la première case libre (ou celle que son application occupait
        // la dernière fois) ; une fenêtre fermée libère sa case, et les suivantes se resserrent.
        let reglages = UserDefaults.standard
        let vivantes = Set(haut.map { $0.cle })
        var places = (reglages.dictionary(forKey: "placesCases") as? [String: Int]) ?? [:]
        if places.isEmpty {     // première fois : on reprend l'ordre déjà affiché
            let ordre = (reglages.stringArray(forKey: "ordreCases") ?? []).filter { vivantes.contains($0) }
            for (i, cle) in ordre.enumerated() { places[cle] = i }
        }
        // Un groupe tout neuf s'installe à la place d'une de ses fenêtres (la plus proche du début).
        for (cle, membres) in membresDe where places[cle] == nil {
            if let p = membres.compactMap({ places[$0] }).min() { places[cle] = p }
        }
        // Une fenêtre qui vient de quitter son groupe ne reprend pas la case du groupe : elle ira sur la première case libre.
        places = places.filter { vivantes.contains($0.key) }
        func app(_ t: Tuile) -> String { NSRunningApplication(processIdentifier: t.pid)?.bundleIdentifier ?? "?" }
        // « Mes applications » (réglages) : celles qui sont ouvertes prennent les premières cases, dans l'ordre de leurs
        // numéros ; les autres fenêtres se rangent après. Une application de la liste qui est fermée ne garde pas de case
        // vide (15/11/2026 : « on ne va pas imposer »). ⌘1 à ⌘9 suivent toujours les numéros de la liste.
        let ouvertes = Set(haut.map(app))
        let numerotees = MesApps.commun.bundles.filter { ouvertes.contains($0) }
        var reservees: [String: Int] = [:]
        for t in haut {
            if let i = numerotees.firstIndex(of: app(t)), !reservees.values.contains(i) { reservees[t.cle] = i }
        }
        for (cle, p) in places where reservees[cle] == nil && p < numerotees.count { places[cle] = nil }
        for (cle, i) in reservees { places[cle] = i }
        var vues: Set<Int> = []
        for cle in places.keys.sorted() { if let p = places[cle], !vues.insert(p).inserted { places[cle] = nil } }
        for (cle, i) in reservees { places[cle] = i }
        var souvenirs = (reglages.dictionary(forKey: "placesApps") as? [String: Int]) ?? [:]
        var prises = Set(places.values).union(0..<numerotees.count)
        for t in haut where places[t.cle] == nil {
            var p = 0
            if let ancienne = souvenirs[app(t)], !prises.contains(ancienne) { p = ancienne } else { while prises.contains(p) { p += 1 } }
            places[t.cle] = p
            prises.insert(p)
        }
        for i in haut.indices { haut[i].place = places[haut[i].cle] ?? 0 }
        haut.sort { $0.place < $1.place }
        // Pas de trou : les cases se resserrent, dans le même ordre (une application fermée libère sa place).
        for i in haut.indices { haut[i].place = i; places[haut[i].cle] = i }
        for t in haut.reversed() { souvenirs[app(t)] = t.place }
        reglages.set(places, forKey: "placesCases")
        reglages.set(souvenirs, forKey: "placesApps")
        reglages.set(haut.map { $0.cle }, forKey: "ordreCases")

        return haut + bureaux
    }

    /// La case de ce qui est à l'écran en ce moment.
    private func cléCourante(_ espaces: [Espace], _ courants: [String: UInt64], ecran: String) -> String? {
        guard let id = courants[ecran], let e = espaces.first(where: { $0.id == id }) else { return nil }
        if e.pleinEcran { return "e\(e.id)" }
        if let devant = e.fenetres.first(where: { !$0.masquee }) {
            let membres = e.fenetres.filter { Groupes.ensemble($0.wid, devant.wid) }
            return membres.count > 1 ? "g\(membres.map { $0.wid }.min() ?? devant.wid)" : "f\(devant.wid)"
        }
        return "e\(e.id)"
    }

    @objc func basculerGrille() {
        guard Partie.pleinEcran.active || panneau?.isVisible == true else { return }     // plein écran coupé dans les réglages
        if panneau?.isVisible == true { fermerGrilleEnRevenant() } else { ouvrirGrille() }
    }

    private func ouvrirGrille() {
        guard let ecran = ecranSousLaSouris() else { return }
        Groupes.nettoyer()
        let (tous, courants) = Relevé.tout()
        espaces = tous
        // Plusieurs écrans : la grille ne montre que les applications de l'écran où elle s'ouvre (23/11/2026).
        tuiles = casesDeLaGrille(tous, ecran: ecran)
        if panneau == nil {
            let p = Panneau(contentRect: ecran.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            // Juste sous le Dock de macOS, pour qu'il reste visible en bas (24/11/2026) ; la barre des menus aussi.
            p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.isOpaque = false
            p.backgroundColor = .black
            p.hasShadow = false
            p.hidesOnDeactivate = false
            p.acceptsMouseMovedEvents = true
            p.animationBehavior = .none
            p.contentView = grille
            panneau = p
        }
        panneau?.setFrame(ecran.frame, display: false)
        let cle = cléCourante(tous, courants, ecran: Ecrans.identifiant(ecran))
        grille.poserFond(Images.commun.fondFlou(ecran: ecran))
        grille.dock.charger()
        grille.charger(tuiles, courante: cle, espaces: tous)
        grille.preparerApparition()
        panneau?.orderFrontRegardless()
        grille.apparaitre()
        grille.majSurvol()
        ouverteÀ = Date()
        enMouvement = false

        brancherTouchesGrille()
        Images.commun.oublier(sauf: Set(tous.flatMap { $0.fenetres.map { $0.wid } }))
        Images.commun.capturer(tous) { [weak self] in
            guard let self, self.panneau?.isVisible == true else { return }
            self.grille.rafraichir(espaces: self.espaces)
        }
    }

    private func brancherTouchesGrille() {
        Touches.ajouter(100, touche: UInt32(kVK_Escape), modifs: 0) { [weak self] in self?.fermerGrilleEnRevenant() }
        // Entrée choisit la case mise en avant par la molette.
        Touches.ajouter(120, touche: UInt32(kVK_Return), modifs: 0) { [weak self] in self?.grille.choisirVedette() }
        for (i, c) in grille.cases.prefix(9).enumerated() {
            Touches.ajouter(UInt32(101 + i), touche: UInt32(chiffres[i]), modifs: 0) { [weak self] in self?.choisir(c.tuile, depuis: c) }
            Touches.ajouter(UInt32(111 + i), touche: UInt32(pavé[i]), modifs: 0) { [weak self] in self?.choisir(c.tuile, depuis: c) }
        }
    }

    private func retirerTouches() { for id in 100...121 { Touches.retirer(UInt32(id)) } }

    private var ecouteLanceur: Any?
    private var lanceurFermeA = Date.distantPast

    /// Clic droit sur une icône du Dock, « Quitter » : comme la croix d'une case, la grille se resserre en douceur.
    private func quitterDepuisLeDock(_ chemin: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == chemin }) else { return }
        activationsIgnoréesJusquÀ = Date().addingTimeInterval(2)    // l'app qui quitte passe la main à une autre
        if let t = tuiles.first(where: { t in
            if t.pid == app.processIdentifier { return true }
            if case .groupe(let fs, _) = t.cible { return fs.contains { $0.pid == app.processIdentifier } }
            return false
        }), case .fenetre = t.cible {
            fermer(t)
        } else {
            app.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.grille.dock.charger() }
    }

    /// Le bouton « Apps » du Dock : la liste de toutes les applications s'ouvre au-dessus de lui (ou se referme).
    private func basculerLanceur() {
        if Lanceur.commun.ouvert { Lanceur.commun.fermer(); return }
        // Un second clic sur le bouton referme la liste : l'appui l'a déjà fermée (clic hors d'elle), le relâchement
        // ne doit pas la rouvrir aussitôt.
        guard Date().timeIntervalSince(lanceurFermeA) > 0.4, let ecran = panneau?.screen else { return }
        retirerTouches()            // le clavier sert maintenant à chercher : les chiffres ne choisissent plus une case
        let ancre = grille.dock.ancreBoutonApps
        Lanceur.commun.ouvrir(surEcran: ecran, contre: ancre.point, cote: ancre.cote)
        // Un clic ailleurs que dans la liste la referme.
        ecouteLanceur = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { e in
            if Lanceur.commun.ouvert, e.window is PanneauLanceur == false { Lanceur.commun.fermer() }
            return e
        }
    }

    /// Clic sur une icône du Dock de la grille : l'application déjà ouverte passe devant (sa case grandit), sinon elle se lance
    /// (et sa fenêtre s'agrandit toute seule, comme toute nouvelle fenêtre).
    /// Pour les essais (commande « dock: ») : comme un clic sur cette icône du Dock de la grille.
    func essaiDock(_ chemin: String) { lancerDepuisLeDock(chemin) }

    private func lancerDepuisLeDock(_ chemin: String) {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == chemin }),
           let c = grille.cases.first(where: { c in
               if c.tuile.pid == app.processIdentifier { return true }
               if case .groupe(let fs, _) = c.tuile.cible { return fs.contains { $0.pid == app.processIdentifier } }
               return false
           }) {
            choisir(c.tuile, depuis: c)
            // Lancée depuis le Dock, une application s'ouvre en grand (sauf une case d'écran partagé).
            if case .fenetre = c.tuile.cible { agrandirQuandDevant(app, essais: 30) }
            return
        }
        journal("Square: ouverture depuis le Dock de la grille")
        enMouvement = true
        // Comme une case choisie : l'icône grandit jusqu'à couvrir l'écran, et la grille s'efface quand la fenêtre arrive.
        retirerTouches()
        grille.zoomerIcone(chemin)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: chemin), configuration: config) { [weak self] app, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let app else { self.fermerGrille(); return }
                self.ouvrirEnGrand(app, essais: 40)
            }
        }
    }

    /// Attend la fenêtre de l'application lancée (douze secondes au plus), l'amène devant, l'agrandit, puis efface la grille.
    private func ouvrirEnGrand(_ app: NSRunningApplication, essais: Int) {
        guard essais > 0, !app.isTerminated else { fermerGrille(); return }
        let (tous, _) = Relevé.tout()
        guard let (f, e) = Bascule.fenetre(deLApp: app.processIdentifier, espaces: tous) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.ouvrirEnGrand(app, essais: essais - 1) }
            return
        }
        journal("Square: %@ ouverte depuis le Dock", f.app)
        Bascule.montrer(f, dans: e)
        agrandirDesQuePossible(f, essais: 15)
    }

    /// Une fenêtre toute neuve n'est pas toujours tout de suite visible par l'Accessibilité : on réessaie un peu
    /// (trois secondes au plus), avec en secours la fenêtre principale de l'application. Puis la grille s'efface.
    private func agrandirDesQuePossible(_ f: Fenetre, essais: Int) {
        var el = AX.fenetre(pid: f.pid, wid: f.wid)
        if el == nil {
            var v: CFTypeRef?
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(f.pid), kAXMainWindowAttribute as CFString, &v)
            if let v, CFGetTypeID(v) == AXUIElementGetTypeID() { el = (v as! AXUIElement) }
        }
        if let el {
            Agrandir.basculer(el, seulementAgrandir: true)
            // Beaucoup d'applications remettent d'elles-mêmes, juste après leur lancement, la taille qu'elles avaient
            // retenue : on vérifie un peu plus tard, et on réagrandit si elle a été défaite.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                if let c = AX.cadre(el) {
                    let zone = Ecrans.zoneVisible(contenant: c)
                    if c.width * c.height < 0.9 * zone.width * zone.height, essais > 0 {
                        self.agrandirDesQuePossible(f, essais: essais - 1)
                        return
                    }
                }
                journal("Square: %@ agrandie", f.app)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.fermerGrille() }
            }
            return
        } else if essais > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.agrandirDesQuePossible(f, essais: essais - 1) }
            return
        }
        // Le temps que la fenêtre prenne sa taille sous l'icône agrandie, puis la grille s'efface.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.fermerGrille() }
    }

    /// Une application déjà ouverte, choisie depuis le Dock : une fois devant, sa fenêtre est agrandie.
    private func agrandirQuandDevant(_ app: NSRunningApplication, essais: Int) {
        guard essais > 0, !app.isTerminated else { return }
        guard app.isActive, let (f, _) = Bascule.fenetre(deLApp: app.processIdentifier, espaces: Relevé.tout().0),
              let el = AX.fenetre(pid: f.pid, wid: f.wid) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.agrandirQuandDevant(app, essais: essais - 1) }
            return
        }
        Agrandir.basculer(el, seulementAgrandir: true)
    }

    /// Une case a été lâchée dans la grille : échange de places, nouvelle place, ou partage de l'écran.
    private func deposer(_ t: Tuile, _ d: DepotGrille) {
        var places = (UserDefaults.standard.dictionary(forKey: "placesCases") as? [String: Int]) ?? [:]
        switch d {
        // (Les places de la grille sont celles de son écran : on les traduit en vraies places, voir `rangsGlobaux`.)
        case .echanger(let autre):
            places[t.cle] = placeGlobale(autre.place)
            places[autre.cle] = placeGlobale(t.place)
        case .place(let k):
            places[t.cle] = placeGlobale(k)
        case .separer(let k):
            // La fenêtre quitte son groupe et reprend tout l'écran ; si elle n'y laisse qu'une fenêtre, celle-ci aussi.
            guard case .fenetre(let a, _) = t.cible else { return }
            if let k { places[t.cle] = placeGlobale(k); UserDefaults.standard.set(places, forKey: "placesCases") }
            appliquerCadres(Groupes.separer(a, membres: membresDuGroupe(a.wid)))
            return
        case .redimensionner(let cadres):
            appliquerCadres(cadres, transition: false)
            return
        case .ordre(let nouvelles):
            // Les cases sont déjà à leur place à l'écran : on retient le nouvel ordre, et on les refait à l'identique.
            for (cle, p) in nouvelles { places[cle] = placeGlobale(p) }
            UserDefaults.standard.set(places, forKey: "placesCases")
            UserDefaults.standard.removeObject(forKey: "placesApps")
            retenirDansMesApps(places)
            redessinerGrille()
            return
        case .partager(let autre, let cote):
            guard case .fenetre(let a, _) = t.cible else { return }
            // Les fenêtres se rangent derrière la grille, qui reste affichée : leurs deux cases n'en font plus qu'une.
            // Si elle vient d'un autre groupe, celles qu'elle y laisse reprennent la place libérée.
            let anciennes = membresDuGroupe(a.wid), nouvelles = membresDuGroupe(autre.wid)
            var cadres: [CGWindowID: CGRect] = [:]
            if !anciennes.contains(where: { $0.wid == autre.wid }) { cadres = Groupes.quitter(a, membres: anciennes) }
            for (w, r) in Groupes.partager(a, sur: autre, cote: cote, membres: nouvelles) { cadres[w] = r }
            appliquerCadres(cadres)
            return
        }
        UserDefaults.standard.set(places, forKey: "placesCases")
        UserDefaults.standard.removeObject(forKey: "placesApps")     // les anciennes places par application ne valent plus
        retenirDansMesApps(places)
        redessinerGrille(transition: true)
    }

    /// Réorganiser la grille change aussi les numéros de « Mes applications » (réglages) : les deux façons de ranger
    /// disent la même chose. Les applications numérotées prennent l'ordre de leurs nouvelles cases ; une application
    /// numérotée mais fermée garde son rang.
    private func retenirDansMesApps(_ places: [String: Int]) {
        let mes = MesApps.commun.liste
        guard mes.count > 1 else { return }
        var rang: [String: Double] = [:]
        for (i, a) in mes.enumerated() { rang[a.bundle] = Double(i) + 0.5 }
        var vus: Set<String> = []
        for t in tuiles.sorted(by: { (places[$0.cle] ?? .max) < (places[$1.cle] ?? .max) }) {
            guard let b = NSRunningApplication(processIdentifier: t.pid)?.bundleIdentifier, rang[b] != nil,
                  let p = places[t.cle], vus.insert(b).inserted else { continue }
            rang[b] = Double(p)
        }
        let nouvel = mes.sorted { (rang[$0.bundle] ?? 0) < (rang[$1.bundle] ?? 0) }
        if nouvel != mes {
            journal("Square: mes applications réordonnées depuis la grille : %@", nouvel.map(\.nom).joined(separator: ", "))
            MesApps.commun.liste = nouvel
        }
    }

    /// Les fenêtres qui partagent l'écran avec celle-ci, elle comprise (elle seule si elle n'est dans aucun groupe).
    private func membresDuGroupe(_ wid: CGWindowID) -> [Fenetre] {
        for t in tuiles {
            if case .groupe(let fs, _) = t.cible, fs.contains(where: { $0.wid == wid }) { return fs }
            if case .fenetre(let f, _) = t.cible, f.wid == wid { return [f] }
        }
        return []
    }

    /// La grille se redessine tout de suite avec les nouveaux cadres, sans attendre les fenêtres ; celles-ci sont déplacées
    /// juste après, derrière la grille, puis les photos sont refaites.
    private func appliquerCadres(_ cadres: [CGWindowID: CGRect], transition: Bool = true) {
        var touchees: [Fenetre] = []
        espaces = espaces.map { e in
            var copie = Espace(id: e.id, pleinEcran: e.pleinEcran, ecran: e.ecran, rang: e.rang, fenetres: e.fenetres.map { f in
                guard let r = cadres[f.wid] else { return f }
                touchees.append(f)
                let zone = Ecrans.zoneVisible(contenant: r)
                let pleine = r.width * r.height >= 0.9 * zone.width * zone.height
                return Fenetre(wid: f.wid, pid: f.pid, app: f.app, titre: f.titre, cadre: r, agrandie: pleine, masquee: f.masquee)
            })
            copie.nomBureau = e.nomBureau
            return copie
        }
        if let ecran = panneau?.screen, panneau?.isVisible == true {
            tuiles = casesDeLaGrille(espaces, ecran: ecran)
            let courants = Relevé.tout().courants
            grille.charger(tuiles, courante: cléCourante(espaces, courants, ecran: Ecrans.identifiant(ecran)), espaces: espaces, transition: transition)
            retirerTouches()
            brancherTouchesGrille()
        }
        DispatchQueue.main.async { [weak self] in
            Groupes.appliquer(cadres, fenetres: touchees)
            self?.redessinerBientot()
        }
    }

    /// Les fenêtres viennent d'être déplacées derrière la grille : on leur laisse un instant, puis la grille se redessine
    /// et reprend des photos fraîches.
    private func redessinerBientot() {
        // Les cases sont déjà à jour : on ne refait que leurs photos, une fois les fenêtres redessinées à leur nouvelle taille.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.panneau?.isVisible == true else { return }
            Images.commun.capturer(self.espaces) { [weak self] in
                guard let self, self.panneau?.isVisible == true else { return }
                self.grille.rafraichir(espaces: self.espaces)
            }
        }
    }

    /// La grille se redessine sur place, sans rejouer l'animation d'ouverture.
    private func redessinerGrille(transition: Bool = false) {
        guard let ecran = panneau?.screen else { return }
        let (tous, courants) = Relevé.tout()
        espaces = tous
        tuiles = casesDeLaGrille(tous, ecran: ecran)
        grille.charger(tuiles, courante: cléCourante(tous, courants, ecran: Ecrans.identifiant(ecran)), espaces: tous, transition: transition)
        retirerTouches()
        brancherTouchesGrille()
    }

    /// Refermer sans rien choisir : la fenêtre où vous étiez regrandit jusqu'à sa place, puis la grille disparaît.
    private func fermerGrilleEnRevenant() {
        guard panneau?.isVisible == true, let c = grille.cases.first(where: { $0.courant }) else { fermerGrille(); return }
        enMouvement = true
        retirerTouches()
        grille.zoomer(c) { [weak self] in self?.fermerGrille() }
    }

    private func fermerGrille() {
        Lanceur.commun.fermer()
        panneau?.orderOut(nil)
        retirerTouches()
    }

    private func choisir(_ t: Tuile, depuis c: Case) {
        journal("Square: choix %@", t.titre)
        enMouvement = true
        retirerTouches()
        Bascule.aller(t, espaces: espaces)
        // L'image de la case grandit et cache ce qui se passe derrière ; la grille disparaît une fois arrivé.
        let vise = Bascule.espaceVise(t, espaces: espaces)
        grille.zoomer(c) { [weak self] in self?.attendreArrivée(vise, essais: 25) }
    }

    private func attendreArrivée(_ e: Espace?, essais: Int) {
        if let e, essais > 0, Relevé.espaceCourant(ecran: e.ecran) != e.id {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in self?.attendreArrivée(e, essais: essais - 1) }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.fermerGrille() }
    }

    private func retourPrécédent() {
        guard pidAvant != 0, let app = NSRunningApplication(processIdentifier: pidAvant) else { return }
        journal("Square: retour à %@", app.localizedName ?? "?")
        if app.isHidden { app.unhide() }
        app.activate(options: [])
    }

    private func fermer(_ t: Tuile) {
        guard let app = NSRunningApplication(processIdentifier: t.pid) else { return }
        activationsIgnoréesJusquÀ = Date().addingTimeInterval(2)    // fermer ou quitter fait passer la main à une autre app
        // Le Finder ne se quitte pas : on ferme simplement sa fenêtre. Side non plus : sa vidéo en grand retourne dans son tiroir.
        func seFerme(_ a: NSRunningApplication?) -> Bool { a?.bundleIdentifier == "com.apple.finder" || a?.bundleIdentifier == Relevé.side }
        let finder = seFerme(app)
        if finder {
            switch t.cible {
            case .fenetre(let f, _): Relevé.fermerFenetre(pid: f.pid, wid: f.wid)
            case .groupe(let fs, _): for f in fs where f.pid == t.pid { Relevé.fermerFenetre(pid: f.pid, wid: f.wid) }
            case .espace: break
            }
        } else {
            app.terminate()
        }
        // Les cases de l'application quittent la grille tout de suite, et les autres se resserrent en douceur.
        var pidsPartis: Set<pid_t> = finder ? [] : [t.pid]
        if case .groupe(let fs, _) = t.cible {
            // Une case de groupe : toutes ses applications se ferment.
            for f in fs where f.pid != t.pid {
                let a = NSRunningApplication(processIdentifier: f.pid)
                if seFerme(a) { Relevé.fermerFenetre(pid: f.pid, wid: f.wid) } else { a?.terminate(); pidsPartis.insert(f.pid) }
            }
        }
        let parties = Set(tuiles.filter { $0.cle == t.cle || pidsPartis.contains($0.pid) }.map { $0.cle })
        tuiles.removeAll { parties.contains($0.cle) }
        // Pas de trou : la fenêtre de la dernière case vient occuper la case libérée (une seule fenêtre change de place).
        while let derniere = tuiles.indices.max(by: { tuiles[$0].place < tuiles[$1].place }) {
            let prises = Set(tuiles.map { $0.place })
            guard let libre = (0..<tuiles[derniere].place).first(where: { !prises.contains($0) }) else { break }
            tuiles[derniere].place = libre
        }
        tuiles.sort { $0.place < $1.place }
        // Les cases des autres écrans gardent leur place : on ne réécrit que celles de cette grille.
        var places = (UserDefaults.standard.dictionary(forKey: "placesCases") as? [String: Int]) ?? [:]
        for cle in parties { places[cle] = nil }
        for t in tuiles { places[t.cle] = placeGlobale(t.place) }
        UserDefaults.standard.set(places, forKey: "placesCases")
        UserDefaults.standard.removeObject(forKey: "placesApps")
        guard panneau?.isVisible == true else { return }
        if tuiles.isEmpty { fermerGrille(); return }
        let courante = grille.cases.first { $0.courant && !parties.contains($0.tuile.cle) }?.tuile.cle
        retirerTouches()
        grille.reorganiser(tuiles) { [weak self] in
            guard let self, self.panneau?.isVisible == true else { return }
            // Les cases sont refaites à l'identique, au même endroit, pour remettre à jour leurs chiffres.
            self.grille.charger(self.tuiles, courante: courante, espaces: self.espaces)
            self.brancherTouchesGrille()
        }
    }

    @objc private func espaceChangé() {
        // Changement d'espace fait ailleurs (trackpad, Mission Control) : la grille n'a plus de raison de rester.
        if panneau?.isVisible == true, Date().timeIntervalSince(ouverteÀ) > 0.5, grille.cases.allSatisfy({ !$0.survol }) { fermerGrille() }
    }

    @objc private func appActivée(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular || (app.bundleIdentifier == Relevé.side && Relevé.videoDeSideAnnoncee),
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if app.processIdentifier != pidDevant { pidAvant = pidDevant; pidDevant = app.processIdentifier }
        // Une application ouverte par le Dock de macOS (ou ⌘ Tab) pendant que la grille est affichée : la grille
        // s'efface pour la laisser voir, sinon elle resterait cachée derrière.
        if panneau?.isVisible == true, !enMouvement, Date() > activationsIgnoréesJusquÀ,
           Date().timeIntervalSince(ouverteÀ) > 0.4 {
            journal("Square: %@ activée hors de la grille, la grille s'efface", app.localizedName ?? "?")
            fermerGrille()
        }
    }
}
