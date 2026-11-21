// Side — une carte de fichiers qui glisse depuis le bord de l'écran
// quand la souris touche le coin haut-gauche, même en plein écran.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Fenêtre de la carte et pilotage de l'application

/// La poignée de la fenêtre des zones de dépôt : une petite barre, comme en haut des cartes d'iOS.
/// On l'attrape pour déplacer la fenêtre. C'est une vue AppKit à part, pour recevoir le clic à coup sûr.
final class PoigneeDepot: NSView {
    static let hauteur: CGFloat = 0   // la poignée n'existe plus : on attrape la zone elle-même
    private let barre = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        barre.cornerRadius = Rayon.dessin(2.5)
        barre.backgroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
        barre.shadowOpacity = 0.4
        barre.shadowRadius = 2
        barre.shadowOffset = .zero
        layer?.addSublayer(barre)
        toolTip = String(localized: "Glisse pour déplacer la zone de dépôt")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        barre.frame = CGRect(x: (bounds.width - 40) / 2, y: (bounds.height - 5) / 2, width: 40, height: 5)
    }
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}


final class DrawerPanel: NSPanel {
    var surEchap: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { surEchap?() } else { super.keyDown(with: event) }
    }
    override func sendEvent(_ event: NSEvent) {
        let clicDroit = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        if clicDroit, let it = AppDelegate.shared.survoleAffiche {
            AppDelegate.shared.menuContextuel(it, event: event)
            return
        }
        if event.type == .keyDown, !(firstResponder is NSTextView), AppDelegate.shared.touche(event) { return }
        super.sendEvent(event)
    }
    override func cancelOperation(_ sender: Any?) { surEchap?() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = AppDelegate()

    let store = Store()
    let config = Config.shared
    var fenetreReglages: NSWindow?
    var dernierX: CGFloat = 0, parcours: CGFloat = 0, versDroite = true
    var demiTours: [TimeInterval] = []
    var pointClic: NSPoint?
    var pointClicDedans: NSPoint?
    /// Vrai pendant que la zone de dépôt accompagne l'animation de la carte (ce n'est pas toi qui la déplaces).
    var animationDepot = false
    var depotEnCours: TimeInterval = -10   // moment du dernier lâcher dans une zone de dépôt
    /// La carte seule (sans la bande du mini-Dock), à l'écran, et le mini-Dock tel que la vue le dessine.
    var cadreSeule: NSRect = .zero
    /// Les vues qui font partie de Side en plus de la carte : le mini-Dock, et le panneau du presse-papiers.
    let reperes = NSHashTable<NSView>.weakObjects()
    weak var vueLanceur: NSView?
    weak var vueDock: NSView?
    /// La petite croix qui suit la souris quand une icône glissée est assez loin du mini-Dock pour être retirée.
    var croix: NSPanel?
    var sortieDuDock: TimeInterval?   // depuis quand l'icône glissée est hors du mini-Dock
    /// Vrai si ce point de l'écran est dans cette vue.
    func dans(_ v: NSView?, _ p: NSPoint, marge: CGFloat = 0) -> Bool {
        guard let v, let w = v.window else { return false }
        return w.convertToScreen(v.convert(v.bounds, to: nil)).insetBy(dx: -marge, dy: -marge).contains(p)
    }
    /// Demande à iCloud de rapatrier un fichier resté dans le nuage.
    func telecharger(_ url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.store.reloadAll() }
    }
    var battement = 0

    /// Pendant qu'on glisse une icône du mini-Dock : hors du mini-Dock depuis un instant, une croix suit la souris
    /// pour dire « lâche ici pour retirer ». De retour sur le mini-Dock, elle disparaît.
    func suivreIconeGlissee() {
        let ici = NSEvent.mouseLocation
        let dehors = !dans(vueDock, ici, marge: 20)
        if store.appHorsDock != dehors { store.appHorsDock = dehors }
        let maintenant = ProcessInfo.processInfo.systemUptime
        if !dehors { sortieDuDock = nil; croix?.orderOut(nil); return }
        if sortieDuDock == nil { sortieDuDock = maintenant }
        guard let depuis = sortieDuDock, maintenant - depuis > 0.5 else { return }
        if croix == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 26, height: 26),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.contentView = NSHostingView(rootView:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color(white: 0.32))
                    .background(Circle().fill(Color.black.opacity(0.25)).padding(1))
                    .frame(width: 26, height: 26))
            croix = p
        }
        guard let croix else { return }
        // En haut à gauche de l'icône glissée, comme la croix des apps d'iOS.
        croix.setFrameOrigin(NSPoint(x: ici.x - 34, y: ici.y + 10))
        if !croix.isVisible {
            croix.alphaValue = 0
            croix.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.15; croix.animator().alphaValue = 1 }
        }
    }

    /// L'icône Apps est la première du mini-Dock : on la reconnaît à sa place au bout de celui-ci.
    func surIconeLanceur(_ p: NSPoint) -> Bool {
        guard let dock = vueDock, let w = dock.window else { return false }
        let r = w.convertToScreen(dock.convert(dock.bounds, to: nil))
        let t = CGFloat(config.tailleDock) + 12
        let vertical = config.dockPosition == "gauche" || config.dockPosition == "droite"
        let icone = vertical ? NSRect(x: r.minX, y: r.maxY - t, width: r.width, height: t)
                             : NSRect(x: r.minX, y: r.minY, width: t, height: r.height)
        return icone.contains(p)
    }

    /// Vrai si ce point de l'écran est sur la carte, le mini-Dock ou un panneau ouvert — pas dans le vide autour.
    /// La place de chaque vue est lue au moment du clic : toujours juste, même pendant une animation.
    func surSide(_ p: NSPoint) -> Bool {
        if cadreSeule.contains(p) { return true }
        if let zone = cadreDepot, zone.contains(p) { return true }     // la zone de dépôt fait partie de Side
        for v in reperes.allObjects {
            guard let w = v.window, w.isVisible, !v.isHiddenOrHasHiddenAncestor else { continue }
            if w.convertToScreen(v.convert(v.bounds, to: nil)).insetBy(dx: -6, dy: -6).contains(p) { return true }
        }
        return false
    }
    var derniereSecousse: TimeInterval = 0
    var suitBureaux = false
    var dernierGlisser = NSPasteboard(name: .drag).changeCount
    var glisserActif = false
    var appGlissee: AppItem?   // icône du mini-Dock en cours de glisser
    let forcerGlisse = CommandLine.arguments.contains("--glisse")   // pour les tests
    var panel: DrawerPanel!
    var host: NSHostingView<DrawerView>!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var abonnement: AnyCancellable?
    var abonnementBord: AnyCancellable?

    var survole: FileItem?    // élément sous la souris
    weak var survoleColonne: Column?
    var cible: URL?                // élément visé par le menu contextuel
    var apercu: URL?
    var apercus: [URL] = []                   // les fichiers proposés dans l'aperçu
    var apercuOuvert = false
    var appAvantApercu: NSRunningApplication?   // l'app qui avait la main avant l'aperçu
    var visible = false
    /// Le cadre du Finder de Side à l'écran (pour la barre de commande).
    var cadreFinder: NSRect { cadreSeule }
    /// Où en est la carte de son glissement, à l'instant même (ce qu'on voit à l'écran) : son écart à sa place, et
    /// l'écart total du trajet. La barre de commande s'y cale image par image, pour arriver et repartir collée à elle.
    var epingle = false            // reste ouvert (test ou clic dans la barre des menus)
    /// Dernière ouverture de la carte : un fichier enregistré après elle (moins de 10 minutes) l'ouvre sur lui (voir Enregistrements).
    var derniereOuvertureCarte = Date()
    /// Mode test (argument --show) : garde la carte ouverte pour une capture d'écran.
    /// Il ne dure que 8 secondes, pour ne jamais bloquer les fermetures pendant qu'on utilise l'app.
    let lancement = ProcessInfo.processInfo.systemUptime
    var modeTest: Bool {
        CommandLine.arguments.contains("--show") && ProcessInfo.processInfo.systemUptime - lancement < 8
    }
    /// Moment de la dernière ouverture ou fermeture : sert de garde-fou entre le coin et la secousse.
    var dernierBasculement: TimeInterval = 0
    var voile: NSPanel?
    var depotPanel: NSPanel?
    var suiviDepot: [AnyCancellable] = []
    var ancreDepot: NSPoint = .zero   // coin haut-gauche de la fenêtre des zones de dépôt (bas-gauche si `zonesVersHaut`)
    /// Carte venue du haut : les zones de dépôt se rangent en bas de la carte et s'empilent vers le haut.
    var zonesVersHaut: Bool { config.bord == .haut }
    var suiviSecousse: Timer?         // lit la secousse pendant un glisser
    var ancrePerso: NSPoint?          // l'endroit où tu l'as déplacée à la main, s'il y en a un
    var placementAuto = false
    var accesDemande = false
    var horsBureau = 0   // nombre de vérifications où la carte n'était pas sur le bureau affiché
    var teinteVoile: NSView?
    var arme = true                // la souris doit quitter le coin avant de rouvrir
    var aQuitteCoin = false        // la souris est sortie du coin depuis l'ouverture
    var debutCoin: Date?
    var debutDehors: Date?
    var cadreCarte: NSRect = .zero // la carte visible, à l'écran (la fenêtre est un peu plus grande)
    var repos: NSPoint = .zero     // position de la carte dans sa fenêtre, une fois ouverte
    /// Position libre : coin haut-gauche de la carte, là où tu l'as posée (nil = au centre).
    var positionLibre: NSPoint? = (UserDefaults.standard.array(forKey: "cartePosition") as? [Double])
        .flatMap { $0.count == 2 ? NSPoint(x: $0[0], y: $0[1]) : nil }
    var prise: (souris: NSPoint, fenetre: NSPoint, carte: NSRect)?   // déplacement en cours
    var ecran: NSScreen?

    var activiteEveil: NSObjectProtocol?

    /// Side quitte : les fenêtres que le tiroir gardait hors de l'écran reviennent, sinon elles resteraient invisibles.
    func applicationWillTerminate(_ note: Notification) {
        PanneauBas.commun.rendreToutesLesFenêtres()
        VoletVue.commun.rendreLesFenêtres()
    }

    /// Mode photo : dessine la carte (ou un volet des réglages) dans une image, puis quitte. Voir tools/snap.sh.
    func lancerModePhoto() {
        // Pour les tests : « --image fichier.png » dessine la carte (ou les réglages, avec --volet) dans une image,
        // sans rien afficher à l'écran ni prendre le clavier, puis quitte. « --choisir n » sélectionne d'abord
        // le premier élément de la grande zone (0) ou de la n-ième colonne épinglée.
        if let i = CommandLine.arguments.firstIndex(of: "--image"), i + 1 < CommandLine.arguments.count {
            let sortie = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            // « --sombre » / « --clair » : l'image est dessinée dans ce mode, quel que soit celui du Mac (tools/snap.sh).
            if CommandLine.arguments.contains("--sombre") { NSApp.appearance = NSAppearance(named: .darkAqua) }
            if CommandLine.arguments.contains("--clair") { NSApp.appearance = NSAppearance(named: .aqua) }
            let reglages = CommandLine.arguments.contains("--volet")
            let volet = CommandLine.arguments.contains("--volet-presse")   // pour les tests : le volet du presse-papiers seul
            let taille = volet ? NSSize(width: 360, height: 640) : reglages ? NSSize(width: 820, height: 900) : NSSize(width: 1150, height: 560)
            let vue: NSView = volet ? NSHostingView(rootView: VoletPresseVue(fermer: {}))
                : reglages ? NSHostingView(rootView: ReglagesView()) : NSHostingView(rootView: DrawerView(store: store))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: taille), styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = vue
            store.largeurMax = 1400
            store.reloadAll()
            if CommandLine.arguments.contains("--presse") || volet {   // pour les tests : un historique d'exemple
                PressePapiers.shared.elements = [
                    Copie(date: Date(), texte: "FR76 0000 0000 0000 0000 0000 000", epingle: true),
                    Copie(date: Date().addingTimeInterval(-40), texte: "Bonjour, merci pour votre message, je reviens vers vous demain."),
                    Copie(date: Date().addingTimeInterval(-300), texte: "motdepasse", secret: true),
                    Copie(date: Date().addingTimeInterval(-900), texte: "https://github.com/GauthierAube/Side"),
                    Copie(date: Date().addingTimeInterval(-4000), fichiers: [URL(fileURLWithPath: "/Applications/Safari.app")]),
                ]
            }
            if let j = CommandLine.arguments.firstIndex(of: "--accueil"), j + 1 < CommandLine.arguments.count {
                store.accueil = Int(CommandLine.arguments[j + 1])   // pour les tests : une étape de la présentation
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                // Pour les tests : « --entrer » ouvre le premier dossier de la dernière colonne épinglée.
                if CommandLine.arguments.contains("--entrer"), let col = self.store.columns.first,
                   let dossier = col.visibles.first(where: \.isFolder) {
                    col.entrer(dossier.url)
                }
                if let j = CommandLine.arguments.firstIndex(of: "--choisir"), j + 1 < CommandLine.arguments.count,
                   let n = Int(CommandLine.arguments[j + 1]) {
                    let colonne = n == 0 ? self.store.navigateur : self.store.columns[min(n, self.store.columns.count) - 1]
                    let premier = (n == 0 && colonne.presentation == .colonnes ? colonne.niveaux.first?.first : colonne.visibles.first)
                    Selection.shared.choisir(premier?.url, colonne)
                }
            }
            if CommandLine.arguments.contains("--test-fleches") {
                // Pour les tests : les flèches dans la grille d'une colonne épinglée, sans clavier ni écran.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let col = self.store.columns.first ?? self.store.navigateur
                    col.presentation = .icones
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        vue.layoutSubtreeIfNeeded()
                        let noms = col.visibles.map(\.name)
                        print("colonne :", col.titre, "— icônes par ligne mesurées :", col.colonnesVisibles)
                        func ou() -> String {
                            guard let u = Selection.shared.url, let i = col.visibles.firstIndex(where: { $0.url == u }) else { return "rien" }
                            return "n°\(i) \(noms[i])"
                        }
                        Selection.shared.choisir(col.visibles.first?.url, col)
                        print("départ        :", ou())
                        // Vraies touches, passées par le même chemin que le clavier.
                        func touche(_ code: UInt16) {
                            let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad],
                                                      timestamp: 0, windowNumber: 0, context: nil,
                                                      characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
                            print("   touche \(code) prise :", self.touche(ev), "| colonne choisie = celle affichée :", Selection.shared.colonne === col)
                        }
                        // Comme chez toi : rien de sélectionné, la souris posée sur le 5e élément (Koala-bravo).
                        Selection.shared.choisir(nil, nil)
                        self.survoler(col.visibles[4], col, true)
                        print("--- souris posée sur :", noms[4], "(rien de sélectionné) ---")
                        for (t, nom) in [(124, "droite"), (126, "haut"), (123, "gauche"), (125, "bas")] { touche(UInt16(t)); print(nom, ":", ou()) }
                        self.survoler(col.visibles[4], col, false)
                        Selection.shared.choisir(col.visibles.first?.url, col)
                        print("--- par le clavier ---")
                        for (t, nom) in [(124, "droite"), (125, "bas"), (123, "gauche")] { touche(UInt16(t)); print(nom, ":", ou()) }
                        Selection.shared.choisir(col.visibles.first?.url, col)
                        print("--- par la fonction ---")
                        for (t, nom) in [(124, "droite"), (125, "bas"), (123, "gauche"), (125, "bas"), (126, "haut"), (124, "droite"), (124, "droite (bord)"), (123, "gauche"), (123, "gauche (bord)")] {
                            self.fleche(UInt16(t))
                            print(nom.padding(toLength: 14, withPad: " ", startingAt: 0), ":", ou())
                        }
                        exit(0)
                    }
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                vue.layoutSubtreeIfNeeded()
                if let rep = vue.bitmapImageRepForCachingDisplay(in: vue.bounds) {
                    vue.cacheDisplay(in: vue.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: sortie)
                }
                exit(0)
            }
            return
        }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        UserDefaults.standard.removeObject(forKey: LecteurYouTubeBas.cleFenetreVideo)   // plus de vidéo en plein écran d'une fois sur l'autre
        // Pour les essais : « --image-presentation dossier » dessine chaque étape de la présentation dans des images, puis quitte.
        // Pour les essais : « --test-cascade » rejoue des suites de touches du collage en cascade ;
        // « --image-cascade fichier.png [--sombre] » dessine sa fenêtre avec un historique d'exemple.
        if CommandLine.arguments.contains("--test-cascade") { CollageCascade.essais() }
        // « --test-recherche » : ce que le champ de recherche ferait de quelques saisies.
        if CommandLine.arguments.contains("--test-recherche") { Recherche.essais() }
        if let i = CommandLine.arguments.firstIndex(of: "--image-cascade"), i + 1 < CommandLine.arguments.count {
            if CommandLine.arguments.contains("--sombre") { NSApp.appearance = NSAppearance(named: .darkAqua) }
            if CommandLine.arguments.contains("--clair") { NSApp.appearance = NSAppearance(named: .aqua) }
            CollageCascade.imageEssai(vers: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--image-presentation"), i + 1 < CommandLine.arguments.count {
            PresentationSide.images(vers: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            exit(0)
        }
        // Side attend en arrière-plan, sans fenêtre : macOS le mettait en sommeil (« App Nap ») au bout de quelques minutes,
        // et le premier geste à quatre doigts tardait à répondre. On lui dit que Side doit toujours réagir tout de suite.
        // (Cela n'empêche pas le Mac de se mettre en veille.)
        activiteEveil = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                              reason: "Side répond aux gestes du trackpad")
        // Première ouverture : la présentation de Side.
        if !UserDefaults.standard.bool(forKey: "accueilVu"), CommandLine.arguments.count == 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { PresentationSide.montrer() }
        }
        // Version personnelle : le panneau du bas, branché après le raccourci de Side (voir PanneauBas.swift).
        if !CommandLine.arguments.contains("--image") {      // pas en mode photo (voir lancerModePhoto)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { PanneauBas.commun.brancher(); VoletVue.commun.brancher() }
            // L'île de l'encoche (Encoche.swift).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Ile.commun.brancher() }
            // La recherche sur le web (Recherche.swift).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Recherche.commun.brancher() }
        }
        panel = DrawerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // La carte appartient au bureau où elle a été ouverte : quand on change de bureau ou d'app
        // plein écran, elle part avec lui au lieu de rester affichée pendant la transition.
        suivreBureaux(false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar   // après isFloatingPanel, qui remet le niveau à zéro
        panel.animationBehavior = .none
        panel.surEchap = { [weak self] in self?.hide() }

        let conteneur = NSView()
        conteneur.wantsLayer = true
        conteneur.layer?.masksToBounds = true
        host = NSHostingView(rootView: DrawerView(store: store))
        host.autoresizingMask = []
        conteneur.addSubview(host)
        panel.contentView = conteneur

        // Mode photo (« --image », tools/snap.sh) : la carte est dessinée dans une image, puis Side quitte. Rien d'autre ne démarre
        // (raccourcis, tiroir, plein écran, coins, presse-papiers) : cette copie partage les réglages du vrai Side et ne doit
        // ni réagir à tes gestes ni écrire dans tes données.
        if CommandLine.arguments.contains("--image") { lancerModePhoto(); return }
        Journaux.raccourcir()
        // Un écran branché, débranché, ou une résolution changée : la carte ouverte gardait l'ancienne géométrie.
        // Elle se referme et se replacera à la prochaine ouverture. (La notification arrive aussi quand le Dock ou la barre
        // des menus bougent : on ne réagit que si les écrans eux-mêmes ont changé.)
        var ecransConnus = NSScreen.screens.map(\.frame)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            let maintenant = NSScreen.screens.map(\.frame)
            guard maintenant != ecransConnus else { return }
            ecransConnus = maintenant
            if self?.visible == true { self?.hide(immediat: true) }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Side")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        abonnement = store.$columns.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self, self.visible, let e = self.ecran else { return }
            self.placer(sur: e, anime: false)
        }

        let t = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)   // tourne aussi pendant un glisser-déposer
        timer = t

        installerRaccourci()
        installerMenuEdition()
        Programme.appli.demarrer()        // le plein écran (grille, carrousel, agrandissement) : l'ancien Square
        Enregistrements.demarrer()        // les fichiers enregistrés ailleurs : la carte s'ouvre sur eux
        VisualiseurFichiers.ecouter()     // « Afficher dans le Finder », quand Side est le visualiseur de fichiers
        FinderJamais.demarrer()           // « Toujours Side, jamais le Finder » : les fenêtres du Finder reviennent à Side
        if CommandLine.arguments.count == 1 { MesApps.commun.demarrer() }   // « Mes applications » : tout se met en place
        nettoyerDepot()
        creerDepot()
        if let e = Ecrans.deTravail { placer(sur: e, anime: false) }   // fixe l'emplacement des zones de dépôt
        store.reloadAll()
        // Surveille le presse-papiers deux fois par seconde pour tenir l'historique du copier-coller.
        let surveillance = Timer(timeInterval: 0.5, repeats: true) { _ in PressePapiers.shared.verifier() }
        RunLoop.main.add(surveillance, forMode: .common)
        // L'historique et les liens enregistrés, partagés avec mes autres Mac par iCloud Drive.
        if CommandLine.arguments.count == 1 { SynchroPresse.commun.demarrer() }
        // Réagir à la touche Commande dès qu'elle bouge, sans attendre la prochaine vérification.
        let surCommande: (NSEvent) -> Void = { [weak self] ev in
            guard let self, self.visible else { return }
            let suivre = self.doitSuivre(ev.modifierFlags.contains(.command))
            if suivre != self.suitBureaux { self.suivreBureaux(suivre) }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: surCommande)
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { ev in surCommande(ev); return ev }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Sauf si la touche Commande est maintenue : la carte suit alors sur le nouveau bureau.
            guard let self, !self.modeTest, self.visible else { return }
            if self.doitSuivre() {
                if !self.panel.isOnActiveSpace {
                    // Commande a été enfoncée trop tard : la carte rejoint le bureau en fondu, sans à-coup.
                    self.suivreBureaux(true)
                    self.panel.alphaValue = 0
                    self.panel.orderFrontRegardless()
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.2
                        self.panel.animator().alphaValue = 1
                    }
                }
                self.panel.makeKey()
                return
            }
            self.fermerApercu()
            self.hide(immediat: true)   // déjà hors de vue : on la range sans animation
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self else { return ev }
            if self.toucheApercu(ev) { return nil }
            if ev.modifierFlags.contains(.command) {
                self.journal("touche ⌘ code \(ev.keyCode) lettre \(ev.charactersIgnoringModifiers ?? "?") — visible \(self.visible), fenêtre de la carte \(ev.window === self.panel), champ de texte \(self.panel.firstResponder is NSTextView), sélection \(Selection.shared.nombre), colonne \(Selection.shared.colonne != nil)")
            }
            // Les raccourcis avec ⌘ du Finder de Side passent avant les menus de l'application : après un clic sur un fichier,
            // « Édition › Tout sélectionner » attrapait ⌘A (pour une liste interne) et la sélection ne changeait pas.
            if ev.modifierFlags.contains(.command), self.visible, ev.window === self.panel,
               !(self.panel.firstResponder is NSTextView), self.touche(ev) { return nil }
            return ev
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in self?.secousse() }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] ev in
            self?.secousse()
            return ev
        }
        // Un clic dans une autre app referme la carte. On attend le relâchement du bouton :
        // si la souris a bougé entre-temps, c'est un glisser-déposer et la carte reste ouverte.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] ev in
            guard let self else { return }
            let p = NSEvent.mouseLocation
            if ev.type == .leftMouseDown { self.pointClic = p; return }
            guard let debut = self.pointClic else { return }
            self.pointClic = nil
            // Un clic un peu « glissé » reste un clic : on tolère 12 points de mouvement.
            guard self.visible, self.config.fermerAuClic, !self.modeTest,
                  hypot(p.x - debut.x, p.y - debut.y) < 12, !self.surSide(p) else { return }
            self.journal("clic ailleurs en \(p) : fermeture (zone de dépôt : \(String(describing: self.cadreDepot)))")
            self.hide()
        }
        // Les bords de la carte passent avant tout le reste : pointeur de redimensionnement, puis tirer pour agrandir.
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] ev in
            guard let self else { return ev }
            return self.suivreBords(ev)
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] ev in
            guard let self else { return ev }
            return self.suivreGlisser(ev)   // nil : le mouvement devient un glisser-déposer
        }
        // Même chose quand le clic tombe dans le vide de notre propre fenêtre (à côté du mini-Dock, par exemple).
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] ev in
            guard let self, ev.window === self.panel else { return ev }
            let p = NSEvent.mouseLocation
            if ev.type == .leftMouseDown {
                // Panneau des applications ouvert : un clic hors de lui (et hors de son icône) le referme.
                if self.store.lanceurOuvert, !self.dans(self.vueLanceur, p), !self.surIconeLanceur(p) {
                    self.store.lanceurOuvert = false
                }
                self.pointClicDedans = self.surSide(p) ? nil : p
                return ev
            }
            guard let debut = self.pointClicDedans else { return ev }
            self.pointClicDedans = nil
            if self.visible, self.config.fermerAuClic, !self.modeTest, self.prise == nil, self.store.accueil == nil,
               hypot(p.x - debut.x, p.y - debut.y) < 12, !self.surSide(p) { self.hide() }
            return ev
        }
        abonnementBord = config.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self, self.visible, let e = self.ecran else { return }
            self.placer(sur: e, anime: false)
            self.montrerFlou(sur: e)   // le réglage du flou s'applique tout de suite
        }
        if config.lanceur { Applis.shared.charger() }   // la liste des apps est prête avant le premier clic
        if config.quatreDoigts { Doigts.demarrer(); Doigts.bloquerDefilement() }
        Captures.shared.demarrer()
        CollageCascade.demarrer()
        if CommandLine.arguments.contains("--test-pages") { exit(EssaisPages.lancer()) }   // le volet de gauche à plusieurs vues
        if CommandLine.arguments.contains("--test-doigts") {   // pour les tests : le module des gestes répond-il ?
            print("trackpads trouvés :", Doigts.demarrer())
            // Gestes fabriqués : (numéro du doigt, hauteur) image par image.
            func essai(_ nom: String, _ sens: String, _ images: [[(Int32, Float)]]) {
                Doigts.sens = sens
                _ = Doigts.traiter([])
                let geste = images.lazy.map { Doigts.traiter($0) }.first { $0 != 0 } ?? 0
                let effet = geste == 0 ? "rien" : (sens == "deux" ? "ouvre ou ferme" : ((geste > 0) == (sens == "haut") ? "ouvre" : "ferme"))
                print(nom, effet)
            }
            func quatre(_ y: Float, decalages: [Float] = [0, 0, 0, 0]) -> [(Int32, Float)] {
                (0..<4).map { (Int32($0), y + decalages[$0]) }
            }
            let descente = stride(from: Float(0.7), through: 0.5, by: -0.02).map { quatre($0) }
            essai("4 doigts vers le bas, court (0,2)        ", "bas", descente)
            essai("même geste, réglé sur vers le haut       ", "haut", descente)
            essai("4 doigts vers le haut, réglé vers le bas ", "bas", descente.reversed())
            // Doigts qui se posent un par un pendant la descente.
            var arrivee: [[(Int32, Float)]] = [[(0, 0.7), (1, 0.7)], [(0, 0.69), (1, 0.69), (2, 0.7)]]
            arrivee += stride(from: Float(0.68), through: 0.5, by: -0.02).map { quatre($0) }
            essai("doigts posés un par un                   ", "bas", arrivee)
            // Un doigt se lève au milieu : la mesure ne doit pas sauter.
            var leve = stride(from: Float(0.7), through: 0.64, by: -0.02).map { quatre($0) }
            leve.append([(0, 0.62), (1, 0.62), (2, 0.62)])
            leve += stride(from: Float(0.6), through: 0.54, by: -0.02).map { quatre($0) }
            essai("un doigt se lève un instant              ", "bas", leve)
            essai("pincement (doigts qui se rapprochent)    ", "deux",
                  (0..<10).map { i in quatre(0.5, decalages: [0.1 - Float(i) * 0.01, 0.1 - Float(i) * 0.01, -0.1 + Float(i) * 0.01, -0.1 + Float(i) * 0.01]) })
            essai("petit tremblement sur place              ", "deux", (0..<20).map { i in quatre(0.5 + (i % 2 == 0 ? 0.01 : -0.01)) })
            essai("trois doigts seulement                   ", "bas", stride(from: Float(0.7), through: 0.4, by: -0.03).map { y in (0..<3).map { (Int32($0), y) } })
            exit(0)
        }
        journal("accès Accessibilité : \(AXIsProcessTrusted() ? "accordé" : "refusé")")
        if CommandLine.arguments.contains("--show") { afficherEpingle() }
        if CommandLine.arguments.contains("--ouvrir") {   // pour les tests : ouverture normale, comme avec le raccourci
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.basculer() }
        }
        if CommandLine.arguments.contains("--reglages") {   // pour les tests
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.ouvrirReglages() }
        }
        // Pour les tests : « --test-geste » mesure la reconnaissance du cercle sur des tracés fabriqués, sans toucher à la souris.
        if CommandLine.arguments.contains("--test-geste") {
            func cercle(_ depart: Double, tours: Double = 1, rayon: Double = 80, bruit: Double = 0, sens: Double = 1) -> [CGPoint] {
                (0...60).map { (i: Int) -> CGPoint in
                    let a = depart + sens * tours * 2 * .pi * Double(i) / 60
                    let r = rayon + Double.random(in: -bruit...bruit)
                    return CGPoint(x: 500 + r * cos(a), y: 400 + r * sin(a))
                }
            }
            func tour(_ nom: String, _ p: [CGPoint]) {
                let r = Geste.rotation(p)
                print(nom, Geste.boucle(p, degres: 240) ? "reconnu" : "refusé ", String(format: "%.0f° constance %.2f", r.degres, r.constance))
            }
            let ligne: [CGPoint] = (0...40).map { (i: Int) -> CGPoint in CGPoint(x: Double(i) * 10, y: 300 + Double(i)) }
            let zigzag: [CGPoint] = (0...60).map { (i: Int) -> CGPoint in CGPoint(x: 400 + 150 * sin(Double(i) / 5), y: 300 + Double(i)) }
            tour("cercle propre           ", cercle(0))
            tour("tout petit cercle (30)  ", cercle(2, rayon: 15, bruit: 1))
            tour("patate tremblée         ", cercle(1, rayon: 60, bruit: 12))
            tour("ovale                   ", cercle(1).map { CGPoint(x: $0.x * 1.8, y: $0.y) })
            tour("sens inverse            ", cercle(0, sens: -1))
            tour("trois quarts de tour    ", cercle(0.5, tours: 0.75))
            tour("deux tiers de tour      ", cercle(0.5, tours: 0.67))
            tour("demi-tour               ", cercle(0.5, tours: 0.5))
            tour("3/4 de tour tremblé     ", cercle(2, tours: 0.78, rayon: 40, bruit: 5))
            // Une vraie secousse : des allers-retours le long d'une boucle très fine, ici en diagonale.
            let secousse: [CGPoint] = (0...60).map { (i: Int) -> CGPoint in
                let a = 4 * Double.pi * Double(i) / 60
                let u = 120 * cos(a), v = 14 * sin(a)
                return CGPoint(x: 500 + (u - v) * 0.707, y: 400 + (u + v) * 0.707)
            }
            tour("secousse en diagonale   ", secousse)
            tour("secousse, un seul tour  ", Array(secousse.prefix(31)))
            tour("ovale très allongé (3:1)", cercle(1).map { CGPoint(x: $0.x * 3, y: $0.y) })
            tour("ligne droite            ", ligne)
            tour("zigzag (secousse)       ", zigzag)
            var boucles = 0
            for _ in 0..<2000 {   // des mouvements au hasard : presque aucun ne doit passer pour un cercle
                var p = CGPoint(x: 500, y: 400), cap = Double.random(in: 0...6.28), trajet: [CGPoint] = []
                for _ in 0..<Int.random(in: 15...60) {
                    cap += Double.random(in: -0.5...0.5)
                    p.x += 9 * cos(cap); p.y += 9 * sin(cap)
                    trajet.append(p)
                }
                if Geste.boucle(trajet, degres: 240) { boucles += 1 }
            }
            print("2000 mouvements au hasard pris pour un cercle :", boucles)
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--apercu"), i + 1 < CommandLine.arguments.count {
            let url = URL(fileURLWithPath: CommandLine.arguments[i + 1])   // pour les tests
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.coupDOeil(url) }
        }
    }

    /// Side n'a pas de barre des menus visible, mais macOS a besoin d'un menu Édition
    /// pour que Commande + A, C, V, X et Z fonctionnent dans le champ « Rechercher ».
    func installerMenuEdition() {
        let edition = NSMenu(title: String(localized: "Édition"))
        edition.addItem(withTitle: String(localized: "Annuler"), action: Selector(("undo:")), keyEquivalent: "z")
        let retablir = edition.addItem(withTitle: String(localized: "Rétablir"), action: Selector(("redo:")), keyEquivalent: "z")
        retablir.keyEquivalentModifierMask = [.command, .shift]
        edition.addItem(.separator())
        edition.addItem(withTitle: String(localized: "Couper"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edition.addItem(withTitle: String(localized: "Copier"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edition.addItem(withTitle: String(localized: "Coller"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edition.addItem(withTitle: String(localized: "Tout sélectionner"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let principal = NSMenu()
        let entree = NSMenuItem(title: String(localized: "Édition"), action: nil, keyEquivalent: "")
        entree.submenu = edition
        principal.addItem(NSMenuItem(title: "Side", action: nil, keyEquivalent: ""))
        principal.addItem(entree)
        NSApp.mainMenu = principal
    }



    // MARK: Secouer le pointeur

    /// Quatre allers-retours rapides de la souris (même pendant qu'on glisse un fichier) ouvrent la carte.
    /// Le cercle, cherché en continu dans les derniers mouvements de la souris.
    var trace: [(p: CGPoint, t: TimeInterval)] = []

    var attendrePause = false
    var dernierMouvement: TimeInterval = 0

    /// Vrai entre la secousse qui a fait apparaître la zone de dépôt seule et la fin du glisser.
    var zoneSecouee = false

    // MARK: Dépôt de fichiers dans la carte

    /// Dossier où Side enregistre ce qu'on dépose et qui n'est pas encore un fichier
    /// (vignette de capture d'écran, image glissée depuis une page web…).
    static let dossierDepot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Side/Dépôt", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()


    // MARK: Déposer une app à un endroit précis du mini-Dock

    /// L'app en cours de dépôt, déjà rangée à sa future place (invisible : la place est vide sous la souris).
    var apercuApp: String?
    var apercuAjoutee = false   // vrai si c'est ce glisser qui l'a mise dans le mini-Dock


    // MARK: Redimensionner la carte par ses bords

    var priseBord: (souris: NSPoint, largeur: Double, hauteur: Double, x: Int, y: Int)?
    var pointeurBord = false

    /// Bouton enfoncé sur un fichier, puis souris qui s'éloigne : le fichier part en glisser-déposer.
    var departGlisser: (point: NSPoint, item: FileItem, fenetre: NSWindow)?
    /// La pile d'une zone de dépôt flottante, sous la souris : l'attraper emmène tous ses fichiers.
    weak var pileSurvolee: Column?
    var departPile: (point: NSPoint, pile: Column)?

    // MARK: Clavier, comme dans le Finder

    var etendreFleche = false



    // MARK: Suivre les quatre doigts

    var suiviDoigts = false
    var ombreSuivi: TimeInterval = 0
    var qSuivi: CGFloat = 0   // où en est la carte (0 = cachée, 1 = à sa place)
    /// Une capture vient d'arriver alors que Side est fermé : la zone s'affiche jusqu'à ce moment-là.
    var captureJusqua: TimeInterval = 0
    var zoneSuivie: NSRect?   // place finale de la zone de dépôt quand elle suit les doigts avec la carte

    /// La zone de dépôt suit la souris pendant qu'on la tire par son fond ; l'endroit est retenu au passage.
    var priseDepot: (souris: NSPoint, origine: NSPoint)?

}

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--test-ecrans") { exit(Int32(Ecrans.essai())) }   // essai sans écran réel
        // IA locale : « --test-capture fichier » affiche le nom proposé pour cette image, sans rien renommer ;
        // « --test-nom-capture » vérifie le nettoyage des réponses du modèle, sans serveur.
        if CommandLine.arguments.contains("--test-nom-capture") { exit(NomDeCapture.essaiNettoyage()) }
        if let i = CommandLine.arguments.firstIndex(of: "--test-capture") {
            guard i + 1 < CommandLine.arguments.count else { print("usage : Side --test-capture fichier"); exit(64) }
            NomDeCapture.essai(CommandLine.arguments[i + 1])
        }
        reprendreAnciensReglages()
        deplacerAncienDossier()
        reprendreReglagesDeSquare()
        let app = NSApplication.shared
        app.delegate = AppDelegate.shared
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// L'app s'appelait « Tiroir » (identifiant com.gauthieraube.tiroir). Au premier lancement sous le nom Side,
    /// on recopie une fois les anciens réglages (favoris, raccourci, position…) pour ne rien perdre.
    /// Les données (historique du copier-coller, fichiers déposés) étaient rangées dans « Application Support/Nook ».
    /// On renomme ce dossier une fois en « Side », avant que l'app ne s'en serve.
    /// Side et Square ne font plus qu'une app (13/11/2026). Au premier lancement, les réglages de Square (coin, ordre des cases,
    /// groupes, Dock, gestes, raccourcis…) sont recopiés une fois ici. Ceux qui existent déjà ici (langue…) sont gardés.
    private static func reprendreReglagesDeSquare() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "reglagesSquareRepris") else { return }
        d.set(true, forKey: "reglagesSquareRepris")
        guard let anciens = UserDefaults(suiteName: "com.gauthieraube.square")?.persistentDomain(forName: "com.gauthieraube.square") else { return }
        for (cle, valeur) in anciens where d.object(forKey: cle) == nil && !cle.hasPrefix("NS") && !cle.hasPrefix("Apple") {
            d.set(valeur, forKey: cle)
        }
    }

    private static func deplacerAncienDossier() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let ancien = base.appendingPathComponent("Nook", isDirectory: true)
        let nouveau = base.appendingPathComponent("Side", isDirectory: true)
        guard fm.fileExists(atPath: ancien.path), !fm.fileExists(atPath: nouveau.path) else { return }
        try? fm.moveItem(at: ancien, to: nouveau)
    }

    private static func reprendreAnciensReglages() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "reglagesRepris") else { return }
        if let anciens = UserDefaults(suiteName: "com.gauthieraube.tiroir")?.persistentDomain(forName: "com.gauthieraube.tiroir") {
            for (cle, valeur) in anciens where d.object(forKey: cle) == nil { d.set(valeur, forKey: cle) }
        }
        d.set(true, forKey: "reglagesRepris")
    }
}
