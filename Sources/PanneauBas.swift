// Le tiroir : le second panneau de Side. Il arrive du bord opposé au Finder (⌃⌥ Espace, son coin actif, ou quatre doigts)
// avec une partie multimédia (YouTube, Spotify, un site au choix) et des fenêtres empruntées à d'autres applications,
// posées côte à côte dans une bande qu'on fait défiler.
// Il se referme au clic ailleurs, avec Échap, le même raccourci ou quatre doigts dans l'autre sens.
import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

@_silgen_name("_AXUIElementGetWindow") func _AXUIElementGetWindow(_ el: AXUIElement, _ wid: inout CGWindowID) -> AXError
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionIDBas() -> Int32
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindowsBas(_ cid: Int32, _ masque: Int32, _ fenetres: CFArray) -> CFArray?
@_silgen_name("CGSSetConnectionProperty") func CGSSetConnectionPropertyBas(_ cid: Int32, _ cible: Int32, _ cle: CFString, _ valeur: CFTypeRef) -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpacesBas(_ cid: Int32) -> CFArray

/// Petit journal dans ~/Library/Logs/Side-panneau.log, pour comprendre un souci après coup.
func journalBas(_ format: String, _ args: CVarArg...) {
    let ligne = ISO8601DateFormatter().string(from: Date()) + " " + String(format: format, arguments: args) + "\n"
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Side-panneau.log")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(ligne.data(using: .utf8)!); try? h.close() }
    else { try? ligne.data(using: .utf8)!.write(to: url) }
}

// MARK: - Accessibilité : lire et changer la place d'une fenêtre d'une autre application

enum AXBas {
    static func cadre(_ el: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p)
        AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s)
        guard let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, taille = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &taille)
        return CGRect(origin: point, size: taille)
    }

    static func placer(_ el: AXUIElement, _ r: CGRect) {
        var p = r.origin, s = r.size
        guard let vp = AXValueCreate(.cgPoint, &p), let vs = AXValueCreate(.cgSize, &s) else { return }
        AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, vp)
        AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, vs)
        AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, vp)
    }

    static func lever(_ el: AXUIElement) {
        AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
    }
}

// MARK: - Raccourcis clavier du panneau

/// Side a déjà son propre raccourci, qui réagit à toute touche globale. Celui-ci est installé après lui :
/// il ne retient que les touches du panneau (reconnues à leur signature) et laisse passer les autres.
enum TouchesBas {
    private static let signature = OSType(0x50424153)   // "PBAS"
    private static var actions: [UInt32: () -> Void] = [:]
    private static var refs: [UInt32: EventHotKeyRef] = [:]
    private static var installé = false

    private static func installer() {
        guard !installé else { return }
        installé = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, ev, _ in
            var hk = EventHotKeyID()
            GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard hk.signature == TouchesBas.signature else { return OSStatus(eventNotHandledErr) }
            TouchesBas.actions[hk.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }

    static func ajouter(_ id: UInt32, touche: UInt32, modifs: UInt32, action: @escaping () -> Void) {
        installer()
        retirer(id)
        var ref: EventHotKeyRef?
        let hk = EventHotKeyID(signature: signature, id: id)
        let etat = RegisterEventHotKey(touche, modifs, hk, GetApplicationEventTarget(), 0, &ref)
        if etat == noErr, let ref {
            refs[id] = ref
            actions[id] = action
        } else {
            journalBas("touche %d refusée (%d)", Int(touche), Int(etat))
        }
    }

    static func retirer(_ id: UInt32) {
        if let r = refs[id] { UnregisterEventHotKey(r) }
        refs[id] = nil
        actions[id] = nil
    }
}

// MARK: - Spotify (piloté par AppleScript)

/// Bouton qui réagit au premier clic, même quand Side n'est pas l'application active.
final class BoutonBas: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Curseur qui réagit au premier clic, lui aussi.
final class CurseurBas: NSSlider {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum SpotifyBas {
    struct Etat {
        var enCours = false, joue = false
        var titre = "", artiste = "", pochette = ""
        var position = 0.0, duree = 0.0          // en secondes
        var aleatoire = false, repete = false
        var volume = 50.0
    }
    private static let file = DispatchQueue(label: "side.spotify")

    static var ouvert: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
    }

    private static func script(_ source: String) -> String? {
        var erreur: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&erreur)
        if let erreur { journalBas("Spotify a répondu %@", "\(erreur[NSAppleScript.errorMessage] ?? erreur)") }
        return r?.stringValue
    }

    private static func nombre(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    static func lire(_ fin: @escaping (Etat) -> Void) {
        guard ouvert else { fin(Etat()); return }
        file.async {
            let texte = script("""
            tell application "Spotify"
                set e to player state as string
                set r to e & linefeed & (shuffling as string) & linefeed & (repeating as string) & linefeed & (sound volume as string)
                if e is "stopped" then return r
                return r & linefeed & (player position as string) & linefeed & ((duration of current track) as string) & linefeed & (name of current track) & linefeed & (artist of current track) & linefeed & (artwork url of current track)
            end tell
            """) ?? ""
            let l = texte.components(separatedBy: "\n")
            var etat = Etat()
            etat.enCours = true
            etat.joue = l.first == "playing"
            if l.count >= 4 { etat.aleatoire = l[1] == "true"; etat.repete = l[2] == "true"; etat.volume = nombre(l[3]) }
            if l.count >= 9 {
                etat.position = nombre(l[4]); etat.duree = nombre(l[5]) / 1000
                etat.titre = l[6]; etat.artiste = l[7]; etat.pochette = l[8]
            }
            DispatchQueue.main.async { fin(etat) }
        }
    }

    static func commande(_ ordre: String, puis fin: @escaping () -> Void = {}) {
        if !ouvert {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Spotify.app"),
                                               configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return
        }
        file.async {
            _ = script("tell application \"Spotify\" to \(ordre)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: fin)
        }
    }
}

// MARK: - Le panneau

/// Une tuile du panneau : la fenêtre d'une autre application, empruntée le temps que le panneau est ouvert.
struct EmpruntBas {
    let nom: String
    let bundle: String
    let chemin: String
    let note: String?          // pour Notes : le nom de la note à ouvrir dans sa propre fenêtre
    /// L'identifiant de la note dans Notes : il ne change jamais, même quand on réécrit sa première ligne (son titre).
    var noteId: String?

    var enTexte: [String: String] {
        var d = ["nom": nom, "bundle": bundle, "chemin": chemin]
        if let note { d["note"] = note }
        if let noteId { d["noteId"] = noteId }
        return d
    }
    init(nom: String, bundle: String, chemin: String, note: String? = nil, noteId: String? = nil) {
        self.nom = nom; self.bundle = bundle; self.chemin = chemin; self.note = note; self.noteId = noteId
    }
    init?(_ d: [String: String]) {
        guard let nom = d["nom"], let bundle = d["bundle"], let chemin = d["chemin"] else { return nil }
        self.init(nom: nom, bundle: bundle, chemin: chemin, note: d["note"], noteId: d["noteId"])
    }
}

final class FenetrePanneauBas: NSPanel {
    override var canBecomeKey: Bool { true }      // pour taper dans la recherche Spotify, sans activer Side
    override var canBecomeMain: Bool { false }
}

/// Photo d'une tuile. Un clic dessus la fait venir en entier dans le panneau.
final class ImageTuileBas: NSImageView {
    var auClic: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { auClic?() }
}

/// Le bord haut du panneau : on le tire pour changer la hauteur du panneau, comme le bord de la carte de Side.
/// Une petite barre au milieu le signale, comme en haut des volets d'un téléphone.
final class PoigneeHauteurBas: NSView {
    var auDebut: (() -> Void)?
    var auTirage: ((CGFloat) -> Void)?      // de combien le pointeur est monté depuis le début
    var aLaFin: (() -> Void)?
    private var depart: CGFloat = 0
    private var zone: NSTrackingArea?

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 20, y: bounds.midY - 2, width: 40, height: 4), xRadius: 2, yRadius: 2).fill()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
    override func mouseDown(with event: NSEvent) { depart = NSEvent.mouseLocation.y; auDebut?() }
    override func mouseDragged(with event: NSEvent) { auTirage?(NSEvent.mouseLocation.y - depart) }
    override func mouseUp(with event: NSEvent) { aLaFin?() }
}

/// La même teinte que le mini-Dock de Side, posée sur le flou : couleur de fenêtre, à l'opacité choisie dans les réglages.
final class TeinteBas: NSView {
    /// Sans fond : un voile à peine visible, qui suffit à garder les clics pour le tiroir.
    var presqueInvisible = false
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = presqueInvisible ? NSColor(white: 0.5, alpha: 0.012).cgColor
            : NSColor.windowBackgroundColor.withAlphaComponent(CGFloat(Config.shared.opacite)).cgColor
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Fond du panneau : on peut y déposer une application pour l'ajouter aux tuiles.
final class FondPanneauBas: NSVisualEffectView {
    var auDépôt: (([URL]) -> Void)?
    private func apps(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { $0.pathExtension == "app" }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { apps(sender).isEmpty ? [] : .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let a = apps(sender)
        guard !a.isEmpty else { return false }
        auDépôt?(a)
        return true
    }
}

/// Une ligne de la liste « + » : icône, nom, et à droite un signe moins (retirer) ou plus (ajouter).
final class LigneSelecteurBas: NSView {
    var auClic: (() -> Void)?
    private var zone: NSTrackingArea?

    init(icone: NSImage?, nom: String, signe: String?, couleur: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        let texte = NSTextField(labelWithString: nom)
        texte.font = .systemFont(ofSize: 13)
        texte.lineBreakMode = .byTruncatingTail
        texte.frame = NSRect(x: icone == nil ? 10 : 36, y: 6, width: 206, height: 18)
        addSubview(texte)
        if let icone {
            let v = NSImageView(image: icone)
            v.imageScaling = .scaleProportionallyUpOrDown
            v.frame = NSRect(x: 8, y: 5, width: 20, height: 20)
            addSubview(v)
        }
        if let signe {
            let v = NSImageView(image: NSImage(systemSymbolName: signe, accessibilityDescription: nil) ?? NSImage())
            v.contentTintColor = couleur
            v.frame = NSRect(x: 252, y: 6, width: 18, height: 18)
            addSubview(v)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { auClic?() } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let zone { removeTrackingArea(zone) }
        let z = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(z)
        zone = z
    }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = nil }
}

/// La petite liste qui s'ouvre au-dessus de la case « + » : les tuiles du panneau (à retirer) et les applications
/// ouvertes (à ajouter). C'est une fenêtre de Side, posée au-dessus de tout, et non un menu du système.
final class SelecteurTuilesBas {
    struct Ligne { let icone: NSImage?; let nom: String; let signe: String?; let couleur: NSColor; let action: (() -> Void)? }
    private var fenetre: NSPanel?
    private var ecoutes: [Any] = []
    var ouvert: Bool { fenetre != nil }

    func montrer(pres ancre: NSRect, _ rubriques: [(String, [Ligne])]) {
        fermer()
        let largeur: CGFloat = 280
        let pile = NSView()
        var y: CGFloat = 8
        var vues: [(NSView, CGFloat, CGFloat)] = []      // vue, position depuis le haut, hauteur
        for (titre, lignes) in rubriques where !lignes.isEmpty {
            if !titre.isEmpty {
                let t = NSTextField(labelWithString: titre)
                t.font = .systemFont(ofSize: 11, weight: .semibold)
                t.textColor = .secondaryLabelColor
                vues.append((t, y + 2, 16))
                y += 22
            }
            for l in lignes {
                let v = LigneSelecteurBas(icone: l.icone, nom: l.nom, signe: l.signe, couleur: l.couleur)
                v.auClic = { [weak self] in self?.fermer(); l.action?() }
                vues.append((v, y, 30))
                y += 31
            }
            y += 6
        }
        let hauteur = y + 2
        pile.frame = NSRect(x: 0, y: 0, width: largeur, height: hauteur)
        for (v, haut, h) in vues {
            v.frame = NSRect(x: v is NSTextField ? 12 : 4, y: hauteur - haut - h, width: largeur - (v is NSTextField ? 24 : 8), height: h)
            pile.addSubview(v)
        }
        let ecran = NSScreen.main?.visibleFrame ?? .zero
        let visible = min(hauteur, max(160, ecran.height - 60))
        let p = FenetrePanneauBas(contentRect: NSRect(x: 0, y: 0, width: largeur, height: visible),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.animationBehavior = .none
        let fond = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: largeur, height: visible))
        fond.material = .menu
        fond.blendingMode = .behindWindow
        fond.state = .active
        fond.wantsLayer = true
        fond.layer?.cornerRadius = 10
        fond.layer?.masksToBounds = true
        let defilant = NSScrollView(frame: fond.bounds)
        defilant.drawsBackground = false
        defilant.hasVerticalScroller = hauteur > visible
        defilant.documentView = pile
        fond.addSubview(defilant)
        p.contentView = fond
        // Juste au-dessus de la case « + », sans sortir de l'écran.
        let x = min(max(ancre.midX - largeur / 2, ecran.minX + 8), ecran.maxX - largeur - 8)
        let bas = min(max(ancre.maxY + 8, ecran.minY + 8), ecran.maxY - visible - 8)
        p.setFrameOrigin(NSPoint(x: x, y: bas))
        pile.scroll(NSPoint(x: 0, y: hauteur))
        p.orderFrontRegardless()
        fenetre = p
        // Un clic en dehors de la liste la referme.
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.fermer() }) { ecoutes.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] e in
            if e.window !== self?.fenetre { self?.fermer() }
            return e
        }) { ecoutes.append(l) }
    }

    func fermer() {
        ecoutes.forEach { NSEvent.removeMonitor($0) }
        ecoutes = []
        fenetre?.orderOut(nil)
        fenetre = nil
    }
}

@_silgen_name("CGWindowListCreateImage")
func photoFenetreBas(_ zone: CGRect, _ options: UInt32, _ wid: CGWindowID, _ image: UInt32) -> Unmanaged<CGImage>?

final class PanneauBas: NSObject {
    static let commun = PanneauBas()
    /// Lus hors du fil principal (geste à quatre doigts, défilement).
    static var estOuvertBrut = false
    static var cadreBrut = CGRect.zero          // le panneau, en coordonnées globales
    static var curseurBord = false              // le pointeur est sur le bord du tiroir (double flèche affichée)

    /// Ce point de l'écran est-il sur le bord qu'on tire pour régler la hauteur ? Quelques points au-dehors du tiroir,
    /// et toute sa marge au-dedans (jusqu'au bord des fenêtres des tuiles compris).
    static func surLeBord(_ p: CGPoint) -> Bool {
        let c = cadreBrut
        let bord = ConfigTiroir.enHaut ? c.maxY : c.minY                   // le bord tourné vers le milieu de l'écran
        let dedans = ConfigTiroir.enHaut ? bord - p.y : p.y - bord
        guard p.x >= c.minX && p.x <= c.maxX && dedans >= -8 && dedans <= 18 else { return false }
        // Une autre fenêtre est posée là, par-dessus le tiroir (les réglages de Side, la liste du « + », une autre application) :
        // le pointeur est sur elle, pas sur le bord du tiroir.
        return tiroirSous(p)
    }
    /// Les numéros de la fenêtre du tiroir et de celles de ses tuiles (tenus à jour par le tiroir).
    static var numerosDuTiroir: Set<Int> = []
    /// La fenêtre la plus en avant sous ce point (coordonnées de l'écran, origine en haut à gauche) est-elle le tiroir ou une de ses tuiles ?
    static func tiroirSous(_ p: CGPoint) -> Bool {
        let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        for w in infos {
            let couche = (w[kCGWindowLayer as String] as? Int) ?? 0
            guard couche < 24, ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0.05,     // ni barre des menus, ni pointeur, ni fenêtre invisible
                  let d = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: d), r.contains(p),
                  let n = w[kCGWindowNumber as String] as? Int else { continue }
            return numerosDuTiroir.contains(n)
        }
        return false
    }
    static var tirageHauteur = false            // on est en train de tirer le bord du tiroir (suivi par le filtre d'événements)
    static var departHauteur: CGFloat = 0
    private static var filtre: CFMachPort?

    private let idRaccourci: UInt32 = 1
    private let idEchap: UInt32 = 2
    private var enCapture = false               // une capture d'écran est en cours, tiroir ouvert : il se fait oublier
    private var notesIntrouvables: Set<String> = []   // notes qu'on n'a pas retrouvées dans Notes : on ne les réclame plus en boucle
    private var titresDeNotes: [String: String] = [:] // le titre actuel de chaque note (il change si on modifie sa première ligne)
    private let largeurLecteur: CGFloat = 300
    private let largeurPlus: CGFloat = 44
    private let marge: CGFloat = 14

    // MARK: Les tuiles (la liste est la vôtre : bouton « + » du panneau)

    private var emprunts: [EmpruntBas] = {
        if let d = UserDefaults.standard.array(forKey: "panneauBasTuiles") as? [[String: String]] {
            return d.compactMap { EmpruntBas($0) }
        }
        // Au départ : Notes et Réglages Système, deux petites applications qu'on consulte d'un coup d'œil. Chacun ajuste
        // ensuite la liste avec la case « + ». Elle est enregistrée tout de suite (Square la lit pour ne pas agrandir ces fenêtres).
        let depart = [("com.apple.Notes", "/System/Applications/Notes.app"),
                      ("com.apple.systempreferences", "/System/Applications/System Settings.app")]
            .filter { FileManager.default.fileExists(atPath: $0.1) }
            .map { EmpruntBas(nom: FileManager.default.displayName(atPath: $0.1).replacingOccurrences(of: ".app", with: ""),
                              bundle: $0.0, chemin: $0.1) }
        UserDefaults.standard.set(depart.map { $0.enTexte }, forKey: "panneauBasTuiles")
        return depart
    }() {
        didSet { UserDefaults.standard.set(emprunts.map { $0.enTexte }, forKey: "panneauBasTuiles"); publierFenêtres() }
    }

    /// Décalage de la bande de tuiles, retenu d'une fois sur l'autre.
    private var défilement: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "panneauBasDéfilement")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "panneauBasDéfilement") }
    }

    private var panneau: NSPanel?
    private var fond: FondPanneauBas?
    private var teinte: TeinteBas?

    /// Avec ou sans fond derrière les tuiles. Sans fond, le flou est masqué (les tuiles et le dépôt d'applications restent).
    func majFond() {
        guard let fond else { return }
        let avec = ConfigTiroir.commun.fond
        fond.maskImage = avec ? nil : NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }
        // Sans fond, le tiroir garde un voile presque invisible : une zone tout à fait transparente laisserait passer
        // les clics et les glisser à l'application de derrière.
        teinte?.presqueInvisible = !avec
        teinte?.needsDisplay = true
        fond.window?.invalidateShadow()
    }
    private let bandeVue = NSView()             // la bande où défilent les tuiles (elle coupe ce qui dépasse)
    private let plus = BoutonBas(frame: .zero)
    private var bienvenue: BienvenueTiroirBas?      // le mot d'accueil, à la toute première ouverture du tiroir
    private let roue = BoutonBas(frame: .zero)      // la roue dentée, au bout de la bande sous la case « + » : ouvre les réglages
    private let selecteur = SelecteurTuilesBas()   // la liste qui s'ouvre au-dessus de la case « + »
    private let poignee = PoigneeHauteurBas()
    private var hauteurAuDepart: CGFloat = 0
    private var refusHauteur: Set<String> = []     // applications qui refusent la hauteur du panneau : on n'insiste pas
    /// Le panneau est ouvert par-dessus un plein écran d'Apple : macOS interdit d'y amener les fenêtres des autres
    /// applications. Les tuiles restent alors en photo, et on ne touche à aucune fenêtre (sinon macOS renvoie sur le bureau).
    private var sansFenêtres = false
    private let banniere = NSView()
    private let messageBanniere = NSTextField(labelWithString: "")
    private var boutonBanniere: NSButton?
    private var ailleursNoms: Set<String> = []          // tuiles dont la fenêtre vit sur un autre bureau : laissées en photo
    private let lecteur = LecteurSpotifyBas(frame: .zero)
    /// Les pages web du coin multimédia (YouTube, et les sites ajoutés dans les réglages), créées à la demande et gardées :
    /// celle qui est masquée continue de jouer.
    private var pagesWeb: [String: LecteurYouTubeBas] = [:]
    private var médias: [MediaBas] { ConfigTiroir.commun.medias }
    /// La largeur du coin multimédia, la même pour tous ses éléments ; rien du tout s'il est vide.
    private var largeurTête: CGFloat {
        guard !médias.isEmpty else { return 0 }
        let place = (NSScreen.main?.visibleFrame.width ?? 1440) - 2 * marge      // jamais plus large que la bande
        return min(LecteurYouTubeBas.largeurCommune, place)
    }
    /// Où commencent les tuiles des applications, après le coin multimédia.
    private var débutTuiles: CGFloat { médias.isEmpty ? 0 : largeurTête + marge }
    private let hauteurChoix: CGFloat = 34
    private let poignéeMédia = PoigneeLargeurBas()
    private var largeurMédiaAuDépart: CGFloat = 0
    /// Le coin multimédia montre un seul de ses éléments, au choix (retenu). Les autres continuent de jouer, masqués.
    private var média: String {
        get {
            let m = UserDefaults.standard.string(forKey: "panneauBasMédia") ?? "youtube"
            return médias.contains { $0.id == m } ? m : (médias.first?.id ?? "")
        }
        set { UserDefaults.standard.set(newValue, forKey: "panneauBasMédia") }
    }
    private let choixMédia = ChoixMediaBas()
    private var photos: [String: NSImage] = [:]        // dernière photo nette de chaque tuile
    private var images: [String: ImageTuileBas] = [:]   // photo de chaque tuile, pendant qu'elle glisse, défile ou attend sur le côté
    private var veille: Timer?                          // regarde si vous avez fermé une fenêtre (bouton rouge)
    private var absences: [String: Int] = [:]
    private var numéros: [String: CGWindowID] = [:] { didSet { publierFenêtres() } }
    /// La tuile sortie en grand par son bouton vert : sa fenêtre est hors du tiroir, Square peut la ranger.
    private var enGrand: String? { didSet { publierFenêtres() } }
    /// Les numéros des fenêtres rangées dans le tiroir, pour Square : il ne les met ni dans sa grille ni dans son carrousel.
    private func publierFenêtres() {
        let ids = emprunts.filter { $0.nom != enGrand }.compactMap { numéros[$0.nom] }.map { Int($0) }.sorted()
        PanneauBas.numerosDuTiroir = Set(ids + [panneau?.windowNumber ?? -1])
        let d = UserDefaults.standard
        if (d.array(forKey: "fenetresDuTiroir") as? [Int]) != ids { d.set(ids, forKey: "fenetresDuTiroir") }
    }     // le numéro de la fenêtre de chaque tuile, pour savoir tout de suite si elle a été fermée
    private var tic = 0
    private var enMain: String?                         // la tuile que vous êtes en train d'élargir ou de déplacer
    private var enMainRetaillée = false
    private var dernierAppui = Date.distantPast         // dernière fois où le bouton de la souris était enfoncé
    private var libérée: String?                        // la tuile qui sort du panneau en grand : on ne la range pas
    /// Les boutons jaune et vert de chaque tuile visible (coordonnées globales), pour les intercepter. Lus par le filtre de clics.
    static var boutonsVerts: [(nom: String, cadre: CGRect)] = []
    static var boutonsJaunes: [(nom: String, cadre: CGRect)] = []
    private static var clicAvalé = false
    private var ouvert = false { didSet { PanneauBas.estOuvertBrut = ouvert } }
    private var ouvertÀ = Date.distantPast
    private var ferméÀ = Date.distantPast
    private var tuileÀMontrer: Int?             // la tuile à amener à l'écran une fois le panneau arrivé
    private var pidAvant: pid_t = 0
    private var ecouteClics: Any?
    private var minuteur: Timer?
    private var q: CGFloat = 0                  // 0 : caché sous l'écran ; 1 : à sa place
    private var suiviDoigts = false             // les doigts font avancer le panneau
    private var fermetureSuivie = false         // ... pour le refermer
    private var enPlace = false                 // le panneau a fini d'arriver
    private var glissé = false                  // on peut installer les vraies fenêtres
    private var glisséÀ = Date.distantPast
    private var défile = false                  // la bande est en train de défiler : toutes les tuiles sont des photos
    private var finDéfilement: DispatchWorkItem?
    private var replacements: [String: Int] = [:]
    private var stables: [String: Int] = [:]    // nombre de vérifications d'affilée où la fenêtre était à sa place
    private var vivantes: Set<String> = []      // tuiles dont on a vu la fenêtre depuis l'ouverture du tiroir (même pas encore bien posée)
    private var posées: Set<String> = []        // fenêtres bien installées : on n'y touche plus, vous pouvez les redimensionner
    private var origines: [String: CGRect] = [:]
    private var vues: Set<String> = []
    private var dernierLever = Date.distantPast
    private var levées = 0
    private var mainRendue = -1                       // la série d'ouverture pour laquelle Side a repris le clavier
    /// Un menu de Side est en train d'être affiché (suivi par les notifications de NSMenu).
    static var menuOuvert = false
    private var demandées: Set<String> = []     // fenêtres dont on a déjà demandé l'ouverture, pour cette fois
    private var serie = 0                       // pour abandonner les attentes d'une ouverture précédente

    func brancher() {
        // Pendant qu'un menu de Side est affiché, le tiroir n'active aucune application (le menu se refermerait).
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in PanneauBas.menuOuvert = true }
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in PanneauBas.menuOuvert = false }
        installerRaccourci()
        VoletPresse.commun.installerRaccourci()     // le volet du presse-papiers a aussi le sien
        GestePanneauBas.enHaut = enHaut
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivée(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        // Commandes venues d'une autre application (Mulot, pour les boutons de la souris) : « carte » ou « panneau ».
        // Side signale dans ses réglages qu'il les accepte : Mulot ne propose ces actions que dans ce cas.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(commandeExterieure(_:)),
                                                            name: .init("com.gauthieraube.side.commande"), object: nil)
        UserDefaults.standard.set(true, forKey: "commandesExterieures")
        // Les photos des fenêtres pendant le glissement demandent l'autorisation « Enregistrement de l'écran ».
        // Sans elle, le panneau glisse avec de simples cartes grises à la place.
        let photos = CGPreflightScreenCaptureAccess()
        if !photos, !UserDefaults.standard.bool(forKey: "panneauBasPhotosDemandées") {
            UserDefaults.standard.set(true, forKey: "panneauBasPhotosDemandées")
            CGRequestScreenCaptureAccess()
        }
        écouterDéfilement()
        journalBas("panneau branché, accessibilité=%d, photos=%d, défilement=%d", AXIsProcessTrusted() ? 1 : 0, photos ? 1 : 0,
                   PanneauBas.filtre == nil ? 0 : 1)
    }

    var estOuvert: Bool { ouvert }
    func basculer() { ouvert ? fermer(rendreLaMain: true) : ouvrir() }

    /// Suite de la visite guidée : le tiroir s'ouvre avec son mot d'accueil (même s'il a déjà été vu).
    func présenter() {
        UserDefaults.standard.set(false, forKey: "tiroirBienvenueVue")
        if ouvert { if let p = panneau { disposerLeFond(p.frame) }; return }
        // Un instant, le temps que le Finder finisse de se refermer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.ouvrir() }
    }

    @objc private func commandeExterieure(_ note: Notification) {
        guard let commande = note.object as? String else { return }
        journalBas("commande reçue : %@", commande)
        switch commande {
        case "carte": AppDelegate.shared.basculer()      // la carte Finder
        case "panneau": basculer()                        // le panneau du bas
        case "presse": VoletPresse.commun.basculer()      // le volet du presse-papiers
        case "reglages-coins":                            // Square renvoie ici pour régler son coin actif
            AppDelegate.shared.fermerReglages()
            Volet.demande = .coins
            AppDelegate.shared.ouvrirReglages()
        case "video-etat": pagesWeb.values.first(where: { $0.estUnYouTube })?.noterEtat()
        case "video":                                     // la vidéo YouTube du tiroir : en plein écran, ou de retour
            pagesWeb.values.first(where: { $0.estUnYouTube })?.basculerPleinEcran()
        case "corbeille":                                 // la carte Finder, ouverte sur la corbeille
            if !AppDelegate.shared.estOuvert { AppDelegate.shared.basculer() }
            Corbeille.montrer()
        default:
            // « youtube https://… » : ouvre ce lien dans la tuile YouTube (pour les essais, et pour d'autres apps).
            if commande.hasPrefix("youtube "), let u = URL(string: String(commande.dropFirst(8))) {
                pagesWeb.values.first(where: { $0.estUnYouTube })?.ouvrir(u)
            }
        }
    }

    /// (Ré)installe le raccourci clavier choisi dans les réglages (aucun si on l'a effacé).
    func installerRaccourci() {
        TouchesBas.retirer(idRaccourci)
        let c = ConfigTiroir.commun
        guard c.touche != -1 else { return }
        TouchesBas.ajouter(idRaccourci, touche: UInt32(c.touche), modifs: UInt32(c.mods)) { [weak self] in self?.basculer() }
    }
    /// Pendant qu'on tape un nouveau raccourci dans les réglages : l'ancien ne doit pas ouvrir le tiroir.
    func suspendreRaccourci() { TouchesBas.retirer(idRaccourci) }

    /// Le coin actif du tiroir. Appelé plusieurs fois par seconde par Side, avec la place du pointeur.
    /// Entrer dans le coin ouvre le tiroir ; il faut s'en éloigner nettement avant qu'y revenir ne le referme.
    private var coinArmé = true
    private var débutCoin: Date?
    func surveillerCoin(_ p: NSPoint, _ e: NSScreen, taille: CGFloat) {
        let coin = ConfigTiroir.commun.coin
        guard coin != .aucun else { return }
        func dans(_ marge: CGFloat) -> Bool {
            let t = taille + marge, f = e.frame
            let gauche = p.x <= f.minX + t, droite = p.x >= f.maxX - t, haut = p.y >= f.maxY - t, bas = p.y <= f.minY + t
            switch coin {
            case .aucun: return false
            case .hautGauche: return haut && gauche
            case .hautDroite: return haut && droite
            case .basGauche: return bas && gauche
            case .basDroite: return bas && droite
            }
        }
        if !dans(40) { coinArmé = true; débutCoin = nil; return }
        guard dans(0) else { débutCoin = nil; return }
        guard coinArmé, NSEvent.pressedMouseButtons == 0, !suiviDoigts else { return }
        if débutCoin == nil { débutCoin = Date() }
        guard Date().timeIntervalSince(débutCoin!) >= 0.05 else { return }
        coinArmé = false
        débutCoin = nil
        journalBas("coin actif du tiroir")
        basculer()
    }

    /// Pour la fenêtre Réglages : les applications du tiroir, dans l'ordre.
    var tuiles: [(nom: String, chemin: String)] { emprunts.map { ($0.nom, $0.chemin) } }
    func retirerTuile(nom: String) {
        if let i = emprunts.firstIndex(where: { $0.nom == nom }) { retirer(i) }
    }

    private func app(_ e: EmpruntBas) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == e.bundle }
    }
    private func estEmpruntée(_ a: NSRunningApplication?) -> Bool {
        guard let b = a?.bundleIdentifier else { return false }
        return emprunts.contains { $0.bundle == b }
    }

    // MARK: Géométrie

    /// Hauteur du panneau, choisie en tirant son bord haut. 0 : jamais réglée (la moitié basse de l'écran).
    private var hauteurChoisie: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "panneauBasHauteur")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "panneauBasHauteur") }
    }
    /// En dessous, des applications comme Réglages Système n'acceptent plus de tenir dans une tuile.
    private let hauteurMini: CGFloat = 530

    /// Le tiroir arrive toujours du bord opposé au Finder de Side : du bas en général, du haut quand le Finder vient du bas.
    private var enHaut: Bool { ConfigTiroir.enHaut }

    /// Emplacement du panneau (coordonnées AppKit) : collé au bas (ou au haut) de l'écran, à la hauteur choisie.
    private func cadre(_ ecran: NSScreen) -> CGRect {
        let z = ecran.visibleFrame
        let voulue = hauteurChoisie > 0 ? hauteurChoisie : (z.height * 0.52).rounded()
        let h = min(max(voulue, hauteurMini), (z.height * 0.94).rounded())
        return CGRect(x: z.minX, y: enHaut ? z.maxY - h : z.minY, width: z.width, height: h)
    }

    /// Le panneau en coordonnées globales (origine en haut à gauche), comme les fenêtres des autres applications.
    private func panneauGlobal(_ c: CGRect) -> CGRect {
        let hautEcran = NSScreen.screens.first?.frame.height ?? c.maxY
        return CGRect(x: c.minX, y: hautEcran - c.maxY, width: c.width, height: c.height)
    }

    /// La bande où tout défile, sur toute la largeur du panneau (coordonnées globales) : le lecteur Spotify d'abord, puis les tuiles.
    private func bande(_ c: CGRect) -> CGRect {
        let g = panneauGlobal(c)
        let x0 = g.minX + marge
        let x1 = g.maxX - marge
        return CGRect(x: x0, y: g.minY + marge, width: max(100, x1 - x0), height: g.height - 2 * marge)
    }

    /// Taille de chaque fenêtre et hauteur où elle se pose, telles que vous les avez laissées : [—, décalage vertical, largeur, hauteur].
    private var disposition: [String: [Double]] {
        get { (UserDefaults.standard.dictionary(forKey: "panneauBasDisposition") as? [String: [Double]]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "panneauBasDisposition") }
    }

    /// Place de chaque tuile, l'une après l'autre le long de la bande (coordonnées globales).
    private func zones(_ c: CGRect) -> [CGRect] {
        let b = bande(c), retenue = disposition
        var x = b.minX - défilement + débutTuiles      // le coin multimédia ouvre la bande
        let haut = b.minY
        return emprunts.map { e in
            // Un carrousel : toutes les tuiles ont la même hauteur et sont alignées ; seule la largeur change de l'une à l'autre.
            var l: CGFloat = e.note != nil ? 430 : 720
            if let r = retenue[e.nom], r.count == 4 { l = r[2] }
            l = min(max(l, 200), b.width)
            let h = b.maxY - haut, y = haut
            defer { x += l + marge }
            return CGRect(x: x, y: y, width: l, height: h)
        }
    }

    /// Les décalages où une tuile commence pile au début de la bande, et le plus grand décalage possible.
    private func arrêts(_ c: CGRect) -> (débuts: [CGFloat], maxi: CGFloat) {
        let b = bande(c), ancien = défilement
        défilement = 0
        let zs = zones(c)
        défilement = ancien
        let bout = (zs.last?.maxX ?? (b.minX + largeurTête)) + marge + largeurPlus     // jusqu'à la case « + »
        let maxi = max(0, bout - b.minX - b.width)
        return (zs.map { min($0.minX - b.minX, maxi) }, maxi)
    }

    /// Les tuiles entièrement visibles : ce sont les seules dont la vraie fenêtre est à l'écran.
    private func entières(_ c: CGRect) -> [(EmpruntBas, CGRect)] {
        let b = bande(c)
        return zip(emprunts, zones(c)).filter { $0.1.minX >= b.minX - 1 && $0.1.maxX <= b.maxX + 1 }.map { ($0.0, $0.1) }
    }

    /// À la fermeture ou avant de défiler : retient la taille que vous avez donnée à chaque fenêtre.
    private func retenir() {
        guard let p = panneau else { return }
        let g = panneauGlobal(p.frame)
        var d = disposition
        for (e, _) in entières(p.frame) where posées.contains(e.nom) {
            guard let f = fenetre(e), let c = AXBas.cadre(f), c.intersects(g), c.width >= 150, c.height >= 100 else { continue }
            d[e.nom] = [0, Double(c.minY - g.minY), Double(c.width), Double(c.height)]
        }
        disposition = d
    }

    private func construire() -> NSPanel {
        let p = FenetrePanneauBas(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .normal                         // les fenêtres empruntées doivent pouvoir passer devant
        p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        p.animationBehavior = .none
        // Comme la carte de Side : la fenêtre ne bouge pas, c'est son contenu qui glisse depuis le bord de l'écran.
        let support = NSView()
        support.wantsLayer = true
        support.layer?.masksToBounds = true
        p.contentView = support
        let fond = FondPanneauBas()
        // Le même fond que le mini-Dock de Side : flou « popover », puis la teinte de fenêtre par-dessus.
        fond.material = .popover
        fond.blendingMode = .behindWindow
        fond.state = .active
        fond.wantsLayer = true
        fond.layer?.cornerRadius = 18
        fond.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        fond.layer?.masksToBounds = true
        fond.autoresizingMask = []
        let teinte = TeinteBas()
        teinte.wantsLayer = true
        teinte.autoresizingMask = [.width, .height]
        teinte.frame = fond.bounds
        fond.addSubview(teinte)
        self.teinte = teinte
        fond.registerForDraggedTypes([.fileURL])
        fond.auDépôt = { [weak self] urls in urls.forEach { self?.ajouter($0) } }
        support.addSubview(fond)
        self.fond = fond
        majFond()
        bandeVue.wantsLayer = true
        bandeVue.layer?.masksToBounds = true
        fond.addSubview(bandeVue)
        bandeVue.addSubview(lecteur)             // le lecteur défile avec les tuiles
        bandeVue.addSubview(choixMédia)
        // Le bord droit du coin multimédia se tire pour l'élargir ou le rétrécir (même largeur pour Spotify et YouTube).
        bandeVue.addSubview(poignéeMédia)
        poignéeMédia.auDebut = { [weak self] in
            guard let self else { return }
            self.largeurMédiaAuDépart = self.largeurTête
            _ = self.commencerDéfilement()
        }
        poignéeMédia.auTirage = { [weak self] d in
            guard let self else { return }
            LecteurYouTubeBas.largeurCommune = min(max(self.largeurMédiaAuDépart + d, LecteurYouTubeBas.largeurMini), 2400)
            self.déplacerImages(animé: false)
        }
        poignéeMédia.aLaFin = { [weak self] in
            guard let self, let p = self.panneau else { return }
            LecteurYouTubeBas.largeurCommune = self.largeurTête        // la largeur vraiment obtenue (bornée à la bande)
            self.finDéfilement?.cancel()
            if self.défile { self.finirDéfilement(vers: min(self.défilement, self.arrêts(p.frame).maxi)) } else { self.recharger(versLaFin: false) }
        }
        // Clic droit et glisser sur la barre des lecteurs : la liste des réglages est modifiée, le tiroir se met à jour tout seul.
        choixMédia.auRetrait = { cle in ConfigTiroir.commun.medias.removeAll { $0.id == cle } }
        choixMédia.auAjout = { m in if !ConfigTiroir.commun.medias.contains(where: { $0.id == m.id }) { ConfigTiroir.commun.medias.append(m) } }
        choixMédia.auxReglages = { [weak self] in self?.ouvrirLesRéglages() }
        choixMédia.auNouvelOrdre = { ordre in
            let actuels = ConfigTiroir.commun.medias
            let ranges = ordre.compactMap { cle in actuels.first { $0.id == cle } }
            if ranges.count == actuels.count { ConfigTiroir.commun.medias = ranges }
        }
        choixMédia.auChoix = { [weak self] m in
            guard let self else { return }
            self.média = m
            journalBas("coin multimédia : %@", m)
            if self.ouvert, self.panneau != nil { self.recharger(versLaFin: false) } else { self.placerLecteurs(hauteur: self.bandeVue.bounds.height, animé: false) }
        }
        plus.isBordered = false
        plus.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: String(localized: "Ajouter une application"))?
            .withSymbolConfiguration(.init(pointSize: 30, weight: .regular))
        plus.contentTintColor = .secondaryLabelColor
        plus.toolTip = String(localized: "Ajouter ou retirer une application du panneau")
        plus.target = self
        plus.action = #selector(ouvrirMenu(_:))
        bandeVue.addSubview(plus)                // la case « + » ferme la bande, après la dernière tuile
        // Le bandeau d'explication, affiché seulement par-dessus un plein écran d'Apple.
        banniere.wantsLayer = true
        banniere.layer?.cornerRadius = 12
        banniere.layer?.backgroundColor = NSColor(white: 0, alpha: 0.78).cgColor
        let message = messageBanniere
        message.font = .systemFont(ofSize: 13, weight: .medium)
        message.textColor = .white
        let sortie = BoutonBas(title: String(localized: "Passer en faux plein écran"), target: self, action: #selector(sortirDuPleinÉcran))
        sortie.bezelStyle = .rounded
        sortie.controlSize = .regular
        boutonBanniere = sortie
        let rangee = NSStackView(views: [message, sortie])
        rangee.spacing = 14
        rangee.translatesAutoresizingMaskIntoConstraints = false
        banniere.addSubview(rangee)
        NSLayoutConstraint.activate([
            rangee.centerXAnchor.constraint(equalTo: banniere.centerXAnchor), rangee.centerYAnchor.constraint(equalTo: banniere.centerYAnchor),
        ])
        banniere.isHidden = true
        fond.addSubview(banniere)
        poignee.auDebut = { [weak self] in self?.commencerHauteur() }
        poignee.auTirage = { [weak self] d in self?.tirerHauteur(d) }
        poignee.aLaFin = { [weak self] in self?.finirHauteur() }
        fond.addSubview(poignee)
        // Après chaque clic dans le tiroir, ses tuiles repassent devant lui (voir repasserSousLesTuiles).
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] ev in
            if let self, ev.window === self.panneau {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.repasserSousLesTuiles() }
            }
            return ev
        }
        roue.isBordered = false
        roue.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: String(localized: "Réglages"))?
            .withSymbolConfiguration(.init(pointSize: 26, weight: .regular))      // la même taille que la case « + »
        roue.contentTintColor = .secondaryLabelColor
        roue.toolTip = String(localized: "Réglages de Side")
        roue.target = self
        roue.action = #selector(ouvrirLesRéglages)
        bandeVue.addSubview(roue)                // au bout de la bande, sous la case « + », alignée sur le bas des tuiles
        return p
    }

    // MARK: Glissement, comme la carte de Side

    /// Place du contenu pour un avancement donné (0 : caché sous le bord ; 1 : à sa place).
    private func origine(_ q: CGFloat) -> NSPoint {
        NSPoint(x: 0, y: (enHaut ? 1 : -1) * (panneau?.frame.height ?? 0) * (1 - min(1, max(0, q))))      // caché au-delà de son bord
    }

    private func poser(_ q: CGFloat) {
        self.q = q
        fond?.setFrameOrigin(origine(q))
        panneau?.alphaValue = min(1, q * 3)
    }

    private func glisser(vers cible: CGFloat, duree: TimeInterval, courbe: CAMediaTimingFunction, fin: @escaping () -> Void) {
        q = cible
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duree
            ctx.timingFunction = courbe
            fond?.animator().setFrameOrigin(origine(cible))
            panneau?.animator().alphaValue = cible > 0 ? 1 : 0
        }, completionHandler: fin)
    }

    private var reduit: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Photos des tuiles

    /// La photo d'une tuile, à la pleine résolution de l'écran : on ne doit pas la distinguer de la vraie fenêtre.
    /// `fraîche` : on la refait maintenant. Sinon on reprend la dernière, prise quand la fenêtre a quitté l'écran :
    /// l'ouverture du panneau n'attend ainsi aucune photo.
    private func photo(_ e: EmpruntBas, taille: CGSize, fraîche: Bool) -> NSImage {
        if !fraîche, let gardée = photos[e.nom] {
            gardée.size = taille
            return gardée
        }
        var wid: CGWindowID = 0
        if CGPreflightScreenCaptureAccess(), let f = fenetre(e), _AXUIElementGetWindow(f, &wid) == .success,
           let cg = photoFenetreBas(.null, 8, wid, 1 | 8)?.takeRetainedValue(), cg.width > 8 {
            let img = NSImage(cgImage: cg, size: taille)
            photos[e.nom] = img
            return img
        }
        if let gardée = photos[e.nom] { gardée.size = taille; return gardée }
        // Pas d'autorisation, ou application pas encore ouverte : une carte claire avec son icône.
        return NSImage(size: taille, flipped: false) { r in
            NSColor(white: 0.93, alpha: 1).setFill()
            NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
            let c: CGFloat = 72
            NSWorkspace.shared.icon(forFile: e.chemin).draw(in: NSRect(x: r.midX - c / 2, y: r.midY - c / 2, width: c, height: c))
            return true
        }
    }

    /// Place d'une tuile dans la bande (coordonnées de la vue), à partir de sa place à l'écran.
    private func dansLaBande(_ r: CGRect, _ b: CGRect) -> NSRect {
        NSRect(x: r.minX - b.minX, y: b.height - (r.minY - b.minY) - r.height, width: r.width, height: r.height)
    }

    /// Refait la photo de chaque tuile et la pose à sa place dans la bande.
    /// `fraîches` : les tuiles à l'écran sont rephotographiées (elles ont pu changer) ; les autres gardent leur dernière photo.
    private func poserImages(fraîches: Bool = true) {
        let àLÉcran = Set((panneau.map { entières($0.frame) } ?? []).map { $0.0.nom })
        images.values.forEach { $0.removeFromSuperview() }
        images = [:]
        guard let p = panneau else { return }
        let b = bande(p.frame)
        placerLecteurs(hauteur: b.height, animé: false)
        placerPlus(animé: false)
        for (i, (e, r)) in zip(emprunts, zones(p.frame)).enumerated() {
            let v = ImageTuileBas(frame: dansLaBande(r, b))
            v.image = photo(e, taille: r.size, fraîche: fraîches && àLÉcran.contains(e.nom))
            v.imageScaling = .scaleAxesIndependently
            v.wantsLayer = true
            v.layer?.cornerRadius = 20
            v.layer?.cornerCurve = .continuous
            v.layer?.masksToBounds = true
            v.auClic = { [weak self] in self?.montrerTuile(i) }
            bandeVue.addSubview(v)
            images[e.nom] = v
        }
    }

    /// Les deux lecteurs maison, au début de la bande : Spotify, puis YouTube.
    private func placerLecteurs(hauteur: CGFloat, animé: Bool) {
        // Le coin multimédia, au début de la bande : un petit sélecteur en haut (s'il y a le choix), et dessous l'élément choisi.
        let liste = médias, choisi = média
        // Les pages des éléments retirés dans les réglages s'en vont (et se taisent).
        for (id, vue) in pagesWeb where !liste.contains(where: { $0.id == id && $0.genre != "spotify" }) {
            vue.removeFromSuperview()
            pagesWeb[id] = nil
        }
        let seul = liste.count <= 1
        choixMédia.isHidden = seul
        choixMédia.montrer(liste.map { ($0.id, $0.nom) }, choisi: choisi)
        poignéeMédia.isHidden = liste.isEmpty
        let h = max(0, seul ? hauteur : hauteur - hauteurChoix - 6)
        let s = NSRect(x: -défilement, y: 0, width: largeurTête, height: h)
        let c = NSRect(x: -défilement, y: hauteur - hauteurChoix, width: largeurTête, height: hauteurChoix)
        poignéeMédia.frame = NSRect(x: s.maxX - 9, y: 0, width: 9, height: h)
        let courant = liste.first { $0.id == choisi }
        lecteur.isHidden = courant?.genre != "spotify"
        // La page de l'élément choisi est créée à sa première apparition, tiroir ouvert.
        if let m = courant, m.genre != "spotify", pagesWeb[m.id] == nil, ouvert, let adresse = URL(string: m.adresse) {
            let vue = LecteurYouTubeBas(accueil: adresse, youtube: m.genre == "youtube")
            bandeVue.addSubview(vue, positioned: .below, relativeTo: choixMédia)
            pagesWeb[m.id] = vue
            vue.réveiller()
        }
        for (id, vue) in pagesWeb { vue.isHidden = id != choisi }
        if animé {
            lecteur.animator().frame = s; choixMédia.animator().frame = c
            pagesWeb.values.forEach { $0.animator().frame = s }
        } else {
            lecteur.frame = s; choixMédia.frame = c
            pagesWeb.values.forEach { $0.frame = s }
        }
    }

    /// La liste du coin multimédia a changé dans les réglages.
    func médiasChangés() {
        if ouvert, panneau != nil { recharger(versLaFin: false) } else { placerLecteurs(hauteur: bandeVue.bounds.height, animé: false) }
    }

    /// La case « + », juste après la dernière tuile.
    private func placerPlus(animé: Bool) {
        guard let p = panneau else { return }
        let b = bande(p.frame)
        let fin = (zones(p.frame).last?.maxX ?? (b.minX - défilement + largeurTête)) + marge
        let r = NSRect(x: fin - b.minX, y: (b.height - largeurPlus) / 2, width: largeurPlus, height: largeurPlus)
        // La roue dentée : même colonne et même taille que la case « + », posée en bas, au niveau du bas des tuiles.
        let bas = NSRect(x: r.minX, y: 0, width: largeurPlus, height: largeurPlus)
        if animé { plus.animator().frame = r; roue.animator().frame = bas } else { plus.frame = r; roue.frame = bas }
    }

    private func déplacerImages(animé: Bool) {
        guard let p = panneau else { return }
        let b = bande(p.frame)
        placerPlus(animé: animé)
        placerLecteurs(hauteur: b.height, animé: animé)
        for (e, r) in zip(emprunts, zones(p.frame)) {
            guard let v = images[e.nom] else { continue }
            v.isHidden = false
            if animé { v.animator().frame = dansLaBande(r, b) } else { v.frame = dansLaBande(r, b) }
        }
    }

    private func disposerLeFond(_ fin: CGRect) {
        fond?.setFrameSize(fin.size)
        let b = bande(fin), g = panneauGlobal(fin)
        bandeVue.frame = NSRect(x: b.minX - g.minX, y: marge, width: b.width, height: b.height)
        placerLecteurs(hauteur: b.height, animé: false)
        placerPlus(animé: false)
        // La poignée de hauteur et les coins arrondis sont du côté qui regarde l'écran : en haut pour un tiroir du bas, et l'inverse.
        poignee.frame = NSRect(x: 0, y: enHaut ? 0 : fin.height - marge, width: fin.width, height: marge)
        fond?.layer?.maskedCorners = enHaut ? [.layerMinXMinYCorner, .layerMaxXMinYCorner] : [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        GestePanneauBas.enHaut = enHaut
        banniere.frame = NSRect(x: (fin.width - 640) / 2, y: marge + 14, width: 640, height: 46)
        // Première ouverture : un mot d'accueil, au milieu du tiroir, jusqu'à ce qu'on clique « Compris ».
        if bienvenue == nil, !UserDefaults.standard.bool(forKey: "tiroirBienvenueVue"), let fond {
            let b = BienvenueTiroirBas()
            b.auCompris = { [weak self] in
                UserDefaults.standard.set(true, forKey: "tiroirBienvenueVue")
                self?.bienvenue?.removeFromSuperview()
                self?.bienvenue = nil
                if let self, self.ouvert, self.enPlace { self.installer(déjàArrivé: true) }      // les vraies fenêtres arrivent
            }
            fond.addSubview(b)
            bienvenue = b
        }
        if let b = bienvenue {
            let t = b.fittingSize
            let l = max(t.width, 440)
            // À droite du lecteur multimédia quand il y a la place, sinon au milieu.
            let libre = fin.width - (marge + débutTuiles)
            let x = libre >= l + 40 ? marge + débutTuiles + (libre - l) / 2 : (fin.width - l) / 2
            b.frame = NSRect(x: x, y: (fin.height - t.height) / 2, width: l, height: t.height)
        }
        PanneauBas.cadreBrut = g
    }

    // MARK: Ouverture

    /// Met le panneau en place, caché sous le bord, avec les photos des tuiles : prêt à glisser.
    private func préparerOuverture() -> Bool {
        // Pendant une capture d'écran, le tiroir ne s'ouvre par aucun geste.
        guard !ouvert, !CaptureEcran.enCours, let ecran = NSScreen.main else { return false }
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
    private func installer(déjàArrivé: Bool) {
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

    private func arrivé() {
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

    private func ouvrir() {
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

    /// p : 0 = caché, 1 = à sa place.
    func suivreDoigts(_ p: CGFloat) {
        guard suiviDoigts, ouvert else { return }
        poser(min(1, max(0, p)))
    }

    /// Doigts levés : le panneau finit sa course sur sa lancée, dans un sens ou dans l'autre.
    func lacherDoigts(ouvrir: Bool, elan: CGFloat) {
        guard suiviDoigts else { return }
        suiviDoigts = false
        guard ouvert else { return }
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
    private func quitterLesFenêtres() {
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

    private func terminerFermeture(rendreLaMain: Bool, duree: TimeInterval, courbe: CAMediaTimingFunction) {
        guard ouvert else { return }
        ouvert = false
        suiviDoigts = false
        serie += 1
        minuteur?.invalidate()
        minuteur = nil
        veille?.invalidate()
        veille = nil
        PanneauBas.boutonsVerts = []
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

    /// « Masquer les Shorts » : appliqué aux pages YouTube déjà ouvertes.
    func appliquerShorts() { pagesWeb.values.forEach { $0.appliquerShorts(ConfigTiroir.commun.masquerShorts) } }

    private func fermer(rendreLaMain: Bool) {
        guard ouvert else { return }
        if !suiviDoigts || !fermetureSuivie { quitterLesFenêtres() }
        // Comme la carte de Side : la fermeture est plus brève que l'ouverture.
        terminerFermeture(rendreLaMain: rendreLaMain, duree: reduit ? 0.12 : 0.26,
                          courbe: CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0.4))
    }

    // MARK: Plein écran d'Apple

    /// L'espace affiché est-il un plein écran d'Apple ? (Les fenêtres des autres applications ne peuvent pas y venir.)
    private func dansUnPleinÉcranApple() -> Bool {
        let ecrans = (CGSCopyManagedDisplaySpacesBas(CGSMainConnectionIDBas()) as? [[String: Any]]) ?? []
        guard let e = ecrans.first, let courant = (e["Current Space"] as? [String: Any]) else { return false }
        return (courant["type"] as? Int) == 4
    }

    /// Bouton du bandeau : l'application de derrière quitte le plein écran d'Apple et remplit l'écran à la place
    /// (un faux plein écran). Le panneau se rouvre ensuite, avec ses vraies tuiles.
    @objc private func sortirDuPleinÉcran() {
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
                if let ecran = NSScreen.main, let principal = NSScreen.screens.first {
                    let z = ecran.visibleFrame
                    AXBas.placer(f, CGRect(x: z.minX, y: principal.frame.height - z.maxY, width: z.width, height: z.height))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.ouvrir() }
            }
        }
        attendre(16)
    }

    // MARK: Hauteur du panneau (on tire son bord haut, comme pour la carte de Side)

    fileprivate func commencerHauteur() {
        guard let p = panneau, commencerDéfilement() else { return }     // les tuiles deviennent des photos le temps du geste
        finDéfilement?.cancel()
        hauteurAuDepart = p.frame.height
    }

    fileprivate func tirerHauteur(_ montée: CGFloat) {
        guard ouvert, défile, let p = panneau, let ecran = p.screen ?? NSScreen.main else { return }
        hauteurChoisie = hauteurAuDepart + (enHaut ? -montée : montée)          // bornée par cadre() : un minimum, et presque tout l'écran au plus
        let fin = cadre(ecran)
        hauteurChoisie = fin.height
        p.setFrame(fin, display: true)
        disposerLeFond(fin)
        poser(1)
        déplacerImages(animé: false)                      // toutes les tuiles prennent la nouvelle hauteur, ensemble
    }

    fileprivate func finirHauteur() {
        guard ouvert, défile else { return }
        journalBas("hauteur du panneau : %.0f", panneau?.frame.height ?? 0)
        refusHauteur = []
        défile = false
        panneau?.invalidateShadow()
        installer(déjàArrivé: true)
    }

    // MARK: Défilement horizontal de la bande

    /// Un défilement horizontal au-dessus du panneau fait glisser les tuiles au lieu d'aller à l'application sous le pointeur.
    private func écouterDéfilement() {
        guard PanneauBas.filtre == nil else { return }
        let masque = CGEventMask(1 << CGEventType.scrollWheel.rawValue) | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue) | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        // Side n'est pas l'application de devant quand le tiroir est ouvert : macOS ne le laisse changer le pointeur
        // (la double flèche, sur le bord du tiroir) que si on le demande expressément.
        _ = CGSSetConnectionPropertyBas(CGSMainConnectionIDBas(), CGSMainConnectionIDBas(), "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        PanneauBas.filtre = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: masque, callback: { _, type, ev, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let f = PanneauBas.filtre { CGEvent.tapEnable(tap: f, enable: true) }
                return Unmanaged.passUnretained(ev)
            }
            // Pendant une capture d'écran, le tiroir ne touche à aucun clic ni au pointeur.
            if CaptureEcran.enCours, !PanneauBas.tirageHauteur { return Unmanaged.passUnretained(ev) }
            // Le bord du tiroir qu'on tire pour régler sa hauteur. Les fenêtres des tuiles sont posées juste dessous, devant
            // le tiroir, et leur propre zone de redimensionnement déborde sur ce bord : sans ce filtre, c'est une fenêtre
            // qui attrapait le clic et se redimensionnait à la place du tiroir. Ici, le clic sur le bord est pour le tiroir.
            if PanneauBas.tirageHauteur {
                if type == .leftMouseDragged {
                    NSCursor.resizeUpDown.set()          // la double flèche reste pendant tout le geste
                    let montee = PanneauBas.departHauteur - ev.location.y        // l'écran global compte vers le bas
                    DispatchQueue.main.async { PanneauBas.commun.tirerHauteur(montee) }
                    return nil
                }
                if type == .leftMouseUp {
                    PanneauBas.tirageHauteur = false
                    DispatchQueue.main.async { PanneauBas.commun.finirHauteur() }
                    return nil
                }
            }
            if type == .leftMouseDragged { return Unmanaged.passUnretained(ev) }
            if type == .mouseMoved {
                // Au-dessus du bord : le pointeur devient une double flèche, pour montrer qu'on peut le tirer.
                let dessus = PanneauBas.estOuvertBrut && PanneauBas.surLeBord(ev.location)
                if dessus { NSCursor.resizeUpDown.set() } else if PanneauBas.curseurBord { NSCursor.arrow.set() }
                PanneauBas.curseurBord = dessus
                return Unmanaged.passUnretained(ev)
            }
            if type == .leftMouseDown, PanneauBas.estOuvertBrut {
                let p = ev.location
                if PanneauBas.surLeBord(p) {
                    PanneauBas.tirageHauteur = true
                    PanneauBas.departHauteur = p.y
                    DispatchQueue.main.async { PanneauBas.commun.commencerHauteur() }
                    return nil
                }
            }
            // Bouton vert d'une tuile : au lieu du plein écran d'Apple, la fenêtre sort du panneau en grand.
            if type == .leftMouseUp {
                guard PanneauBas.clicAvalé else { return Unmanaged.passUnretained(ev) }
                PanneauBas.clicAvalé = false
                return nil
            }
            if type == .leftMouseDown {
                guard PanneauBas.estOuvertBrut else { return Unmanaged.passUnretained(ev) }
                if let vert = PanneauBas.boutonsVerts.first(where: { $0.cadre.contains(ev.location) }) {
                    PanneauBas.clicAvalé = true
                    PanneauBas.commun.sortirEnGrand(nom: vert.nom)
                    return nil
                }
                if let jaune = PanneauBas.boutonsJaunes.first(where: { $0.cadre.contains(ev.location) }) {
                    PanneauBas.clicAvalé = true
                    PanneauBas.commun.retirerSansFermer(nom: jaune.nom)
                    return nil
                }
                return Unmanaged.passUnretained(ev)
            }
            guard PanneauBas.estOuvertBrut, PanneauBas.cadreBrut.contains(ev.location) else { return Unmanaged.passUnretained(ev) }
            let dx = ev.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            let dy = ev.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            guard dx != 0, abs(dx) > abs(dy) * 1.2 else { return Unmanaged.passUnretained(ev) }
            DispatchQueue.main.async { PanneauBas.commun.défiler(CGFloat(dx)) }
            return nil
        }, userInfo: nil)
        guard let filtre = PanneauBas.filtre else { return }   // sans l'autorisation Accessibilité, pas de défilement
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, filtre, 0), .commonModes)
        CGEvent.tapEnable(tap: filtre, enable: true)
    }

    /// Passe en mode défilement : toutes les tuiles deviennent des photos, les vraies fenêtres sont rangées.
    private func commencerDéfilement() -> Bool {
        selecteur.fermer()
        guard ouvert, enPlace, !suiviDoigts, panneau != nil else { return false }
        if !défile {
            défile = true
            serie += 1
            if !sansFenêtres { retenir(); poserImages(); ranger(sauf: []) }
        }
        return true
    }

    func défiler(_ dx: CGFloat) {
        guard let p = panneau, commencerDéfilement() else { return }
        défilement = min(max(0, défilement - dx), arrêts(p.frame).maxi)
        déplacerImages(animé: false)
        finDéfilement?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.finirDéfilement() }
        finDéfilement = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: w)
    }

    /// Le défilement s'arrête : la bande se cale sur la tuile la plus proche, puis les vraies fenêtres reviennent.
    private func finirDéfilement(vers cible: CGFloat? = nil) {
        guard let p = panneau, ouvert, défile else { return }
        let a = arrêts(p.frame)
        défilement = cible ?? ([0, a.maxi] + a.débuts).min(by: { abs($0 - défilement) < abs($1 - défilement) }) ?? 0
        défilement = min(max(0, défilement), a.maxi)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            déplacerImages(animé: true)
        }, completionHandler: { [weak self] in
            guard let self, self.ouvert, self.défile else { return }
            self.défile = false
            self.installer(déjàArrivé: true)
        })
    }

    /// Clic sur la photo d'une tuile à moitié cachée : elle vient en entier dans le panneau.
    private func montrerTuile(_ i: Int) {
        guard let p = panneau, emprunts.indices.contains(i), commencerDéfilement() else { return }
        finDéfilement?.cancel()
        let a = arrêts(p.frame), b = bande(p.frame), r = zones(p.frame)[i]
        // Déjà à gauche de la bande : on l'amène au début. À droite : juste assez pour qu'elle tienne en entier.
        let cible = r.minX < b.minX ? a.débuts[i] : min(a.maxi, défilement + (r.maxX - b.maxX))
        finirDéfilement(vers: cible)
    }

    // MARK: Boutons rouge et vert des tuiles

    /// Plusieurs fois par seconde, tant que le panneau est ouvert :
    /// - une fenêtre fermée par son bouton rouge retire sa tuile ;
    /// - une fenêtre que vous élargissez pousse ses voisines (c'est un carrousel : rien ne se chevauche) ;
    /// - une fenêtre que vous déplacez change de rang dans la bande quand vous la lâchez ;
    /// - on repère les boutons jaune et vert, pour les intercepter.
    private func veiller() {
        // Pendant une capture d'écran : Échap doit annuler la capture (pas refermer le tiroir), et aucune fenêtre ne doit
        // être ramenée devant. Le tiroir rend donc sa touche Échap et ne fait plus rien, jusqu'à la fin de la capture.
        let capture = ouvert && CaptureEcran.enCours
        if capture != enCapture {
            enCapture = capture
            if capture { TouchesBas.retirer(idEchap) }
            else if ouvert { TouchesBas.ajouter(idEchap, touche: UInt32(kVK_Escape), modifs: 0) { [weak self] in self?.fermer(rendreLaMain: true) } }
        }
        if capture { return }
        guard ouvert, enPlace, !défile, !suiviDoigts, !sansFenêtres, let p = panneau else {
            PanneauBas.boutonsVerts = []; PanneauBas.boutonsJaunes = []; enMain = nil; return
        }
        tic += 1
        let appuyé = NSEvent.pressedMouseButtons & 1 != 0
        if appuyé { dernierAppui = Date() }
        let geste = appuyé || Date().timeIntervalSince(dernierAppui) < 1     // c'est bien vous qui bougez la fenêtre
        let b = bande(p.frame)
        var verts: [(nom: String, cadre: CGRect)] = [], jaunes: [(nom: String, cadre: CGRect)] = []
        for (e, zone) in entières(p.frame) where posées.contains(e.nom) {
            if let a = app(e), a.isHidden { continue }
            // Certaines applications quittent quand on ferme leur fenêtre (Réglages Système) : c'est aussi un bouton rouge.
            guard app(e) != nil, let f = fenetre(e) else {
                // Absente depuis plus d'une demi-seconde : la fenêtre a bien été fermée (et pas seulement en train de se recréer).
                absences[e.nom, default: 0] += 1
                // Sa fenêtre n'existe plus du tout pour macOS : c'est sûr, elle a été fermée. On n'attend pas davantage.
                let disparue = numéros[e.nom].map { n in
                    ((CGWindowListCopyWindowInfo([.optionIncludingWindow], n) as? [[String: Any]]) ?? []).isEmpty
                } ?? false
                if absences[e.nom, default: 0] >= (disparue ? 2 : 5), let i = emprunts.firstIndex(where: { $0.nom == e.nom }) {
                    journalBas("%@ fermée par son bouton rouge", e.nom)
                    if enMain == e.nom { enMain = nil }
                    retirer(i)
                    return
                }
                continue
            }
            absences[e.nom] = 0
            var numéro: CGWindowID = 0
            if _AXUIElementGetWindow(f, &numéro) == .success, numéro != 0 { numéros[e.nom] = numéro }
            guard let c = AXBas.cadre(f) else { continue }
            let retaillée = abs(c.width - zone.width) > 3
            // La hauteur d'une tuile est celle du panneau : étirée à la main, elle y revient au lâcher.
            // (Sauf pour une application qui refuse cette hauteur : on n'insiste pas.)
            let hauteurChangée = abs(c.height - zone.height) > 3 && !refusHauteur.contains(e.nom)
            let bougée = abs(c.minX - zone.minX) > 3 || abs(c.minY - zone.minY) > 3 || hauteurChangée
            if (retaillée || bougée), enMain == nil, geste { enMain = e.nom; enMainRetaillée = false }
            if enMain == e.nom {
                if retaillée {
                    // Sa nouvelle largeur est retenue tout de suite, et les voisines se poussent pendant que vous tirez.
                    enMainRetaillée = true
                    var d = disposition
                    d[e.nom] = [0, 0, Double(min(max(c.width, 200), b.width)), 0]
                    disposition = d
                }
                if appuyé {
                    if enMainRetaillée { pousser(sauf: e.nom) }
                    else if abs(c.midX - zone.midX) > 30 {
                        // Comme dans la grille de Square : pendant qu'on la déplace, la tuile prend sa nouvelle place
                        // et les autres se poussent tout de suite pour la lui laisser.
                        let avant = emprunts.map(\.nom)
                        changerDeRang(e, milieu: c.midX)
                        if emprunts.map(\.nom) != avant { pousser(sauf: e.nom) }
                    }
                } else {
                    // Lâchée : déplacée sans être élargie, elle prend le rang où vous l'avez posée. Puis tout se réaligne.
                    if !enMainRetaillée, abs(c.midX - zone.midX) > 30 { changerDeRang(e, milieu: c.midX) }
                    enMain = nil
                    recaler()
                    return
                }
                continue
            }
            guard tic % 3 == 0 else { continue }
            var v: CFTypeRef?
            AXUIElementCopyAttributeValue(f, kAXFullScreenButtonAttribute as CFString, &v)
            if let v, CFGetTypeID(v) == AXUIElementGetTypeID(), let r = AXBas.cadre(v as! AXUIElement) {
                verts.append((e.nom, r.insetBy(dx: -2, dy: -2)))
            }
            var j: CFTypeRef?
            AXUIElementCopyAttributeValue(f, kAXMinimizeButtonAttribute as CFString, &j)
            if let j, CFGetTypeID(j) == AXUIElementGetTypeID(), let r = AXBas.cadre(j as! AXUIElement) {
                jaunes.append((e.nom, r.insetBy(dx: -2, dy: -2)))
            }
        }
        if enMain != nil, !emprunts.contains(where: { $0.nom == enMain }) { enMain = nil }
        if tic % 3 == 0, enMain == nil {
            PanneauBas.boutonsVerts = verts
            PanneauBas.boutonsJaunes = jaunes
        }
    }

    /// Pendant que vous élargissez une fenêtre : les autres tuiles visibles suivent, sans attendre que vous lâchiez.
    private func pousser(sauf nom: String) {
        guard let p = panneau else { return }
        for (e, zone) in zip(emprunts, zones(p.frame)) where e.nom != nom && posées.contains(e.nom) {
            guard let f = fenetre(e), let c = AXBas.cadre(f), c.minX < (NSScreen.screens.first?.frame.maxX ?? 0) - 2,
                  abs(c.minX - zone.minX) > 1 else { continue }
            AXBas.placer(f, zone)
        }
    }

    /// La tuile lâchée ailleurs prend le rang qui correspond à l'endroit où elle a été posée.
    private func changerDeRang(_ e: EmpruntBas, milieu: CGFloat) {
        guard let p = panneau, let depuis = emprunts.firstIndex(where: { $0.nom == e.nom }) else { return }
        let autres = zip(emprunts, zones(p.frame)).filter { $0.0.nom != e.nom }
        let vers = autres.filter { $0.1.midX < milieu }.count
        guard vers != depuis else { return }
        var liste = emprunts
        liste.remove(at: depuis)
        liste.insert(e, at: min(vers, liste.count))
        emprunts = liste
        journalBas("%@ passe au rang %d", e.nom, vers + 1)
    }

    /// Réaligne toute la bande : photos refaites, puis vraies fenêtres réinstallées à leur place.
    private func recaler() {
        poserImages()
        installer(déjàArrivé: true)
    }

    /// Bouton « Voir la vidéo » du lecteur : la fenêtre de Spotify s'affiche en grand (c'est là que la vidéo se regarde).
    func montrerSpotifyEnGrand() {
        if let i = emprunts.firstIndex(where: { $0.bundle == "com.spotify.client" }) { sortirEnGrand(i); return }
        journalBas("Spotify ouvert en grand pour la vidéo")
        fermer(rendreLaMain: false)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Spotify.app"), configuration: config) { app, _ in
            guard let pid = app?.processIdentifier else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard let ecran = NSScreen.main, let principal = NSScreen.screens.first else { return }
                var v: CFTypeRef?
                AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &v)
                guard let f = (v as? [AXUIElement])?.first else { return }
                let z = ecran.visibleFrame
                AXBas.placer(f, CGRect(x: z.minX, y: principal.frame.height - z.maxY, width: z.width, height: z.height))
                AXBas.lever(f)
            }
        }
    }

    /// Bouton jaune : la tuile quitte le panneau pour de bon, mais sa fenêtre reste ouverte, rendue à son application.
    func retirerSansFermer(nom: String) {
        guard let i = emprunts.firstIndex(where: { $0.nom == nom }) else { return }
        journalBas("%@ retirée par son bouton jaune", nom)
        retirer(i)
    }

    /// Bouton vert : la fenêtre quitte le panneau et remplit l'écran
    /// (un faux plein écran, sans changement d'espace). Elle reviendra dans le panneau à sa prochaine ouverture.
    func sortirEnGrand(nom: String) {
        if let i = emprunts.firstIndex(where: { $0.nom == nom }) { sortirEnGrand(i) }
    }

    private func sortirEnGrand(_ i: Int) {
        guard ouvert, emprunts.indices.contains(i), let ecran = NSScreen.main, let principal = NSScreen.screens.first else { return }
        let e = emprunts[i]
        journalBas("%@ sort du panneau en grand", e.nom)
        enGrand = e.nom
        libérée = e.nom
        fermer(rendreLaMain: false)
        libérée = nil
        let v = ecran.visibleFrame
        let plein = CGRect(x: v.minX, y: principal.frame.height - v.maxY, width: v.width, height: v.height)
        // L'application peut ne pas être ouverte encore : on l'ouvre, puis on agrandit sa fenêtre dès qu'elle existe.
        if fenetre(e) == nil {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: e.chemin), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
        func essayer(_ reste: Int) {
            if let f = fenetre(e) {
                AXBas.placer(f, plein)
                AXBas.lever(f)
                app(e)?.activate(options: [])
            } else if reste > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { essayer(reste - 1) }
            }
        }
        essayer(16)
    }

    // MARK: Ajouter et retirer des applications

    /// « Une seule note… » : la liste des notes de l'application Notes s'affiche, on clique sur celle qu'on veut.
    /// Sa tuile remplace alors celle de toute l'application Notes.
    private func demanderUneNote() {
        guard let fenetre = plus.window else { return }
        let ancre = fenetre.convertToScreen(plus.convert(plus.bounds, to: nil))
        DispatchQueue.global().async { [weak self] in
            // Les titres des notes, dans l'ordre de Notes (les plus récentes d'abord). Rien d'autre n'est lu.
            var erreur: NSDictionary?
            // Avec leur identifiant, qui ne change pas quand on réécrit la première ligne d'une note.
            let reponse = NSAppleScript(source: "tell application \"Notes\" to get {name, id} of every note")?.executeAndReturnError(&erreur)
            var titres: [String] = [], ids: [String: String] = [:]
            if let reponse, reponse.numberOfItems == 2, let noms = reponse.atIndex(1), let idents = reponse.atIndex(2), noms.numberOfItems > 0 {
                for i in 1...noms.numberOfItems {
                    if let t = noms.atIndex(i)?.stringValue, !t.isEmpty, !titres.contains(t) {
                        titres.append(t)
                        ids[t] = idents.atIndex(i)?.stringValue
                    }
                    if titres.count >= 40 { break }
                }
            }
            if let erreur { journalBas("Notes a répondu %@", "\(erreur[NSAppleScript.errorMessage] ?? erreur)") }
            DispatchQueue.main.async {
                guard let self, self.ouvert else { return }
                let icone = NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app")
                let lignes = titres.map { t in
                    SelecteurTuilesBas.Ligne(icone: icone, nom: t, signe: "plus.circle.fill", couleur: .systemGreen) { [weak self] in self?.ajouterNote(t, id: ids[t]) }
                }
                let vide = [SelecteurTuilesBas.Ligne(icone: nil, nom: String(localized: "Aucune note trouvée dans Notes"), signe: nil, couleur: .clear, action: nil)]
                self.selecteur.montrer(pres: ancre, [(String(localized: "Choisir une note"), lignes.isEmpty ? vide : lignes)])
            }
        }
    }

    /// Range une note précise dans le tiroir (par son titre). Aussi appelé depuis les réglages.
    func ajouterNote(_ titre: String, id: String? = nil) {
        guard !titre.isEmpty, !emprunts.contains(where: { $0.note == titre }) else { return }
        // La tuile de toute l'application Notes ferait double emploi (et prendrait la fenêtre de la note pour la sienne).
        for e in emprunts where e.bundle == "com.apple.Notes" && e.note == nil { rendreLaFenêtre(e) }
        emprunts.removeAll { $0.bundle == "com.apple.Notes" && $0.note == nil }
        emprunts.append(EmpruntBas(nom: String(localized: "Note \(titre)"), bundle: "com.apple.Notes", chemin: "/System/Applications/Notes.app", note: titre, noteId: id))
        journalBas("tuile ajoutée : une note")
        recharger(versLaFin: true)
    }

    /// Un clic dans le tiroir (case « + », sélecteur, page YouTube…) fait passer sa fenêtre devant celles des tuiles,
    /// qui disparaissent alors derrière lui. On le remet aussitôt juste sous la tuile la plus en arrière.
    private func repasserSousLesTuiles() {
        guard ouvert, enPlace, !défile, !sansFenêtres, let p = panneau else { return }
        let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let ordre = infos.compactMap { $0[kCGWindowNumber as String] as? Int }
        guard let rangPanneau = ordre.firstIndex(of: p.windowNumber) else { return }
        var plusLoin: (rang: Int, numero: Int)?
        for (e, _) in entières(p.frame) where posées.contains(e.nom) {
            var wid: CGWindowID = 0
            guard let f = fenetre(e), _AXUIElementGetWindow(f, &wid) == .success, let rang = ordre.firstIndex(of: Int(wid)) else { continue }
            if rang > (plusLoin?.rang ?? -1) { plusLoin = (rang, Int(wid)) }
        }
        guard let cible = plusLoin, cible.rang > rangPanneau else { return }      // une tuile est passée derrière le tiroir
        p.order(.below, relativeTo: cible.numero)
    }

    /// La roue dentée : le tiroir se referme et la fenêtre Réglages s'ouvre.
    @objc private func ouvrirLesRéglages() {
        fermer(rendreLaMain: false)
        AppDelegate.shared.ouvrirReglages()
    }

    @objc private func ouvrirMenu(_ bouton: NSView) {
        if selecteur.ouvert { selecteur.fermer(); return }
        func icone(_ chemin: String) -> NSImage { NSWorkspace.shared.icon(forFile: chemin) }
        let presentes = emprunts.enumerated().map { i, e in
            SelecteurTuilesBas.Ligne(icone: icone(e.chemin), nom: e.nom, signe: "minus.circle.fill", couleur: .systemRed) { [weak self] in self?.retirer(i) }
        }
        let moi = Bundle.main.bundleIdentifier
        let ouvertes = NSWorkspace.shared.runningApplications.filter { a in
            a.activationPolicy == .regular && a.bundleIdentifier != moi && a.bundleURL != nil && !estEmpruntée(a)
        }.sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
        let aAjouter = ouvertes.map { a in
            SelecteurTuilesBas.Ligne(icone: icone(a.bundleURL!.path), nom: a.localizedName ?? "?", signe: "plus.circle.fill", couleur: .systemGreen) { [weak self] in
                self?.ajouter(a.bundleURL!)
            }
        }
        let symbole: (String) -> NSImage? = { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) }
        let autre = [
            SelecteurTuilesBas.Ligne(icone: symbole("square.grid.2x2"), nom: String(localized: "Choisir une application…"), signe: "chevron.right", couleur: .tertiaryLabelColor) { [weak self] in
                self?.choisirApplication()
            },
            // Une seule note, dans sa propre petite fenêtre, plutôt que toute l'application Notes.
            SelecteurTuilesBas.Ligne(icone: icone("/System/Applications/Notes.app"), nom: String(localized: "Une seule note…"), signe: "chevron.right", couleur: .tertiaryLabelColor) { [weak self] in
                self?.demanderUneNote()
            },
        ]
        guard let fenetre = bouton.window else { return }
        let ancre = fenetre.convertToScreen(bouton.convert(bouton.bounds, to: nil))
        journalBas("liste + ouverte")
        // Les deux façons d'ajouter d'abord, bien en vue ; puis les tuiles du tiroir, puis les applications ouvertes.
        selecteur.montrer(pres: ancre, [(String(localized: "Ajouter au tiroir"), autre), (String(localized: "Dans le tiroir"), presentes),
                                        (String(localized: "Applications ouvertes"), aAjouter)])
    }

    @objc private func choisirApplication() {
        let p = NSOpenPanel()
        p.title = String(localized: "Ajouter au panneau")
        p.prompt = String(localized: "Ajouter")
        p.allowedContentTypes = [.applicationBundle]
        p.allowsMultipleSelection = true
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        guard Devant.panneau(p) == .OK else { return }
        p.urls.forEach { ajouter($0) }
    }

    func ajouter(_ url: URL) {
        guard let bundle = Bundle(url: url)?.bundleIdentifier, bundle != Bundle.main.bundleIdentifier,
              !emprunts.contains(where: { $0.bundle == bundle && $0.note == nil }) else {
            journalBas("ajout refusé pour %@ (déjà dans le panneau, ou application illisible)", url.lastPathComponent)
            return
        }
        let nom = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        emprunts.append(EmpruntBas(nom: nom, bundle: bundle, chemin: url.path))
        journalBas("tuile ajoutée : %@", nom)
        // La nouvelle tuile arrive au bout de la bande : on y défile pour la montrer.
        recharger(versLaFin: true)
    }

    private func retirer(_ i: Int) {
        guard emprunts.indices.contains(i) else { return }
        let e = emprunts[i]
        rendreLaFenêtre(e)
        emprunts.remove(at: i)
        journalBas("tuile retirée : %@", e.nom)
        recharger(versLaFin: false)
    }

    /// La liste des tuiles a changé : on refait la bande.
    private func recharger(versLaFin: Bool) {
        guard let p = panneau, ouvert else { return }
        if enPlace, !suiviDoigts {
            if !défile { défile = true; serie += 1; retenir(); ranger(sauf: []) }
            // La case « + » et la roue dentée ne sautent pas : elles glissent vers leur nouvelle place, au bord de la dernière tuile.
            let plusAvant = plus.frame, roueAvant = roue.frame
            poserImages()
            plus.frame = plusAvant
            roue.frame = roueAvant
            finDéfilement?.cancel()
            finirDéfilement(vers: versLaFin ? arrêts(p.frame).maxi : min(défilement, arrêts(p.frame).maxi))
        } else {
            poserImages()
        }
    }

    // MARK: Fenêtres empruntées

    private func titre(_ el: AXUIElement) -> String {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &v)
        return (v as? String) ?? ""
    }

    private func enfants(_ el: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v)
        return (v as? [AXUIElement]) ?? []
    }

    /// La fenêtre à emprunter, si elle existe déjà : pour une note, celle qui porte son nom.
    private func fenetre(_ e: EmpruntBas) -> AXUIElement? {
        guard let a = app(e), !a.isHidden else { return nil }
        let el = AXUIElementCreateApplication(a.processIdentifier)
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &v)
        let toutes = (v as? [AXUIElement]) ?? []
        guard let note = e.note else {
            if let f = toutes.first { noterNuméro(e, f) }
            return toutes.first
        }
        // Une note déjà trouvée est reconnue à son numéro de fenêtre : son titre (sa première ligne) change dès qu'on l'écrit,
        // et la chercher par son titre la faisait passer pour fermée (elle quittait le tiroir et restait sur le bureau).
        if let n = numéros[e.nom], let f = toutes.first(where: { w in var id: CGWindowID = 0; return _AXUIElementGetWindow(w, &id) == .success && id == n }) {
            return f
        }
        let actuel = titresDeNotes[note] ?? note
        let f = toutes.first { titre($0) == actuel } ?? toutes.first { titre($0) == note }
        if let f { noterNuméro(e, f) }
        return f
    }

    private func noterNuméro(_ e: EmpruntBas, _ f: AXUIElement) {
        var id: CGWindowID = 0
        if _AXUIElementGetWindow(f, &id) == .success, id != 0, numéros[e.nom] != id { numéros[e.nom] = id }
    }

    /// L'application a bien une fenêtre, mais pas sur le bureau affiché (l'Accessibilité ne voit que le bureau courant).
    private func surUnAutreBureau(_ e: EmpruntBas) -> Bool {
        guard let a = app(e), !a.isHidden, fenetre(e) == nil else { return false }
        // Une note a sa propre fenêtre, qu'on ouvre à la demande : la grande fenêtre de Notes, où qu'elle soit, ne compte pas.
        if e.note != nil { return false }
        // Le bureau affiché, et celui de chaque fenêtre de l'application : elle est « ailleurs » si elle a une vraie fenêtre
        // et qu'aucune n'est sur le bureau affiché. (Une fenêtre simplement garée hors de l'écran est bien sur ce bureau.)
        let ecrans = (CGSCopyManagedDisplaySpacesBas(CGSMainConnectionIDBas()) as? [[String: Any]]) ?? []
        let courants = Set(ecrans.compactMap { (($0["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.intValue })
        guard !courants.isEmpty else { return false }
        let infos = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
        var ailleurs = false
        for w in infos {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == a.processIdentifier, (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat], (b["Width"] ?? 0) > 200, (b["Height"] ?? 0) > 200,
                  let numero = w[kCGWindowNumber as String] as? Int else { continue }
            let bureaux = (CGSCopySpacesForWindowsBas(CGSMainConnectionIDBas(), 7, [numero] as CFArray) as? [Int]) ?? []
            if bureaux.isEmpty { continue }                              // fenêtre fantôme : ni ici ni ailleurs
            if !courants.isDisjoint(with: bureaux) { return false }      // elle en a une ici : on saura la trouver ou la rouvrir
            ailleurs = true
        }
        return ailleurs
    }

    /// Fait apparaître la fenêtre quand elle n'existe pas encore (une seule demande par installation).
    private func demander(_ e: EmpruntBas) {
        guard !demandées.contains(e.nom), !notesIntrouvables.contains(e.nom), !CaptureEcran.enCours else { return }
        demandées.insert(e.nom)
        journalBas("ouverture demandée pour %@", e.nom)
        guard let note = e.note else {
            // « Ouvrir » plutôt qu'« activer » : si l'application tourne sans fenêtre, macOS lui en redonne une.
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: e.chemin), configuration: config, completionHandler: nil)
            return
        }
        // Notes : on affiche la note, puis on demande « Ouvrir la note dans une nouvelle fenêtre » dans le menu Fenêtre.
        // La grande fenêtre de Notes ne sert que d'intermédiaire : elle est tenue hors de l'écran pendant toute l'opération.
        écarterLaGrandeFenêtreDeNotes(pendant: 4.5)
        let maSerie = serie
        // Notes pas encore lancée : on la lance masquée, le temps de garer sa grande fenêtre, pour qu'elle ne passe pas à l'écran.
        let lancée = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Notes" }
        if !lancée {
            let config = NSWorkspace.OpenConfiguration()
            config.hides = true
            config.activates = false
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: e.chemin), configuration: config, completionHandler: nil)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + (lancée ? 0 : 1.2)) { [weak self] in
            var erreur: NSDictionary?
            // La note qui porte ce nom ; à défaut, celle dont le nom le contient (sa première ligne a pu être retouchée).
            let cherche = note.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            // D'abord par son identifiant (il ne change jamais), puis par son nom.
            let parId = e.noteId.map { "try\n set n to note id \"\($0.replacingOccurrences(of: "\"", with: ""))\"\n end try" } ?? ""
            let script = """
            tell application "Notes"
                set n to missing value
                \(parId)
                if n is missing value then
                    try
                        set n to first note whose name is "\(cherche)"
                    end try
                end if
                if n is missing value then set n to first note whose name contains "\(cherche)"
                show n
                return {name of n, id of n}
            end tell
            """
            let reponse = NSAppleScript(source: script)?.executeAndReturnError(&erreur)
            let titre = reponse?.atIndex(1)?.stringValue, ident = reponse?.atIndex(2)?.stringValue
            if let erreur { journalBas("Notes a répondu %@", "\(erreur[NSAppleScript.errorMessage] ?? erreur)") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                guard let titre else {
                    // Note introuvable (supprimée, ou renommée du tout au tout) : on ne clique surtout pas dans le menu de Notes
                    // (il ouvrirait une autre note), on ne la réclame plus, et on le dit.
                    self.notesIntrouvables.insert(e.nom)
                    self.messageBanniere.stringValue = String(localized: "La note « \(note) » est introuvable dans Notes : renommée ou supprimée. Retire sa tuile et choisis-la de nouveau avec le +.")
                    self.boutonBanniere?.isHidden = true
                    self.banniere.isHidden = !self.ouvert
                    self.fermerLeResteDeNotes()
                    return
                }
                self.titresDeNotes[note] = titre
                // Une tuile rangée avant que Side ne retienne les identifiants : on le retient maintenant.
                if let ident, let i = self.emprunts.firstIndex(where: { $0.nom == e.nom }), self.emprunts[i].noteId == nil {
                    self.emprunts[i].noteId = ident
                }
                guard self.ouvert, self.serie == maSerie, let a = self.app(e) else { return }
                // Le menu de Notes est dans la langue de Notes (celle du Mac), pas dans celle de Side : on cherche les deux.
                let ok = self.presserMenu(a, ["Ouvrir la note dans une nouvelle fenêtre", "Open Note in New Window"])
                journalBas("menu de Notes %@", ok ? "pressé" : "introuvable")
                // La note a maintenant sa fenêtre à elle : la grande fenêtre de Notes, qui a servi à l'ouvrir, se referme.
                for attente in [0.7, 1.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + attente) { [weak self] in self?.fermerLeResteDeNotes() }
                }
            }
        }
    }

    /// Cette fenêtre de Notes est-elle celle d'une note du tiroir ? D'abord par son numéro (le titre d'une note change dès
    /// qu'on écrit sa première ligne), puis par son titre. Sinon, c'est la grande fenêtre de Notes, que le tiroir écarte ou rend.
    private func estUneNoteDuTiroir(_ f: AXUIElement, _ notes: Set<String>) -> Bool {
        var id: CGWindowID = 0
        if _AXUIElementGetWindow(f, &id) == .success, id != 0,
           emprunts.contains(where: { $0.note != nil && numéros[$0.nom] == id }) { return true }
        let t = titre(f)
        return notes.contains(t) || titresDeNotes.values.contains(t)
    }

    /// Pendant qu'une note s'ouvre dans sa propre fenêtre : toute autre fenêtre de Notes est repoussée hors de l'écran
    /// dès qu'elle apparaît (on regarde cinquante fois par seconde), pour qu'on ne la voie pas passer.
    private var écartNotes: Timer?
    private func écarterLaGrandeFenêtreDeNotes(pendant durée: TimeInterval) {
        écartNotes?.invalidate()
        let fin = Date().addingTimeInterval(durée)
        let pousser: () -> Void = { [weak self] in
            guard let self, let ecran = NSScreen.screens.first,
                  let a = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Notes" }) else { return }
            let notes = Set(self.emprunts.compactMap { $0.note })
            var v: CFTypeRef?
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXWindowsAttribute as CFString, &v)
            for f in (v as? [AXUIElement]) ?? [] where !self.estUneNoteDuTiroir(f, notes) {
                guard let c = AXBas.cadre(f), c.minX < ecran.frame.maxX - 2 else { continue }
                AXBas.placer(f, CGRect(x: ecran.frame.maxX - 1, y: ecran.frame.height - 1, width: c.width, height: c.height))
            }
        }
        pousser()      // tout de suite : si Notes est déjà ouverte, sa fenêtre part avant même d'être appelée
        écartNotes = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] t in
            if Date() > fin { t.invalidate(); self?.écartNotes = nil; return }
            pousser()
        }
    }

    /// Quand le tiroir montre une note seule : la grande fenêtre de Notes reste garée hors de l'écran, au lieu d'être refermée.
    /// Ainsi, la prochaine fois qu'on a besoin d'elle pour ouvrir une note, elle n'a pas à réapparaître : rien ne clignote.
    /// Elle revient à l'écran dès qu'on appelle Notes normalement (voir appActivée).
    private func fermerLeResteDeNotes() {
        guard ouvert, emprunts.contains(where: { $0.note != nil }),
              !emprunts.contains(where: { $0.bundle == "com.apple.Notes" && $0.note == nil }) else { return }
        écarterLaGrandeFenêtreDeNotes(pendant: 0.2)
    }

    /// Notes appelée normalement (Dock, raccourci) alors que sa grande fenêtre est garée hors de l'écran : on la lui rend.
    private func rendreLaGrandeFenêtreDeNotes(_ a: NSRunningApplication) {
        guard let ecran = NSScreen.screens.first, let visible = NSScreen.main?.visibleFrame else { return }
        let notes = Set(emprunts.compactMap { $0.note })
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXWindowsAttribute as CFString, &v)
        for f in (v as? [AXUIElement]) ?? [] where !estUneNoteDuTiroir(f, notes) {
            guard let c = AXBas.cadre(f), c.minX >= ecran.frame.maxX - 2 else { continue }
            let milieu = CGPoint(x: visible.midX, y: ecran.frame.height - visible.midY)
            AXBas.placer(f, CGRect(x: milieu.x - c.width / 2, y: milieu.y - c.height / 2, width: c.width, height: c.height))
            journalBas("grande fenêtre de Notes rendue")
        }
    }

    private func presserMenu(_ a: NSRunningApplication, _ intitulés: [String]) -> Bool {
        let el = AXUIElementCreateApplication(a.processIdentifier)
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXMenuBarAttribute as CFString, &v)
        guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return false }
        for rubrique in enfants(v as! AXUIElement) {
            for menu in enfants(rubrique) {
                for ligne in enfants(menu) where intitulés.contains(titre(ligne)) {
                    return AXUIElementPerformAction(ligne, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }

    /// Pendant le glissement : chaque fenêtre visible déjà ouverte est amenée devant le panneau, l'une après l'autre,
    /// alors qu'elle est encore hors de l'écran. Une fois le panneau arrivé, on les installe d'un coup à la place de leurs photos.
    private func préparer(_ visibles: [(EmpruntBas, CGRect)], serie maSerie: Int) {
        guard ouvert, serie == maSerie else { return }
        let prêtes = visibles.allSatisfy { fenetre($0.0).map { estDevant($0) } ?? true }
        if glissé && (prêtes || Date().timeIntervalSince(glisséÀ) > 0.4) {
            for (e, zone) in visibles { if let f = fenetre(e) { placer(e, f, zone) } }
            // Les photos restent un instant sous les vraies fenêtres, le temps qu'elles se posent.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.serie == maSerie else { return }
                for (e, _) in visibles where self.fenetre(e) != nil { self.images[e.nom]?.isHidden = true }
            }
            surveiller(visibles, essais: 80, serie: maSerie)
            return
        }
        if !prêtes { remonter(visibles.map { $0.0 }, attente: 0.05) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.préparer(visibles, serie: maSerie)
        }
    }

    /// La fenêtre est-elle devant le panneau ?
    private func estDevant(_ f: AXUIElement) -> Bool {
        guard let p = panneau else { return false }
        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(f, &wid) == .success else { return false }
        let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let ordre = infos.compactMap { $0[kCGWindowNumber as String] as? Int }
        guard let rangPanneau = ordre.firstIndex(of: p.windowNumber), let rang = ordre.firstIndex(of: Int(wid)) else { return false }
        return rang < rangPanneau
    }

    /// Pendant quatre secondes : ouvre les fenêtres manquantes, les installe à leur place et les ramène devant.
    /// Une fenêtre installée n'est plus touchée ensuite : vous pouvez la redimensionner.
    private func surveiller(_ visibles: [(EmpruntBas, CGRect)], essais: Int, serie maSerie: Int) {
        guard ouvert, serie == maSerie, essais > 0 else { return }
        for (e, zone) in visibles {
            if let f = fenetre(e) {
                placer(e, f, zone)
                if posées.contains(e.nom) { images[e.nom]?.isHidden = true }
            } else if !posées.contains(e.nom) {
                demander(e)
            }
        }
        remonter(visibles.map { $0.0 })
        rendreLeClavier(visibles.map { $0.0 })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.surveiller(visibles, essais: essais - 1, serie: maSerie)
        }
    }

    /// Toutes les tuiles sont devant. Pour y arriver, il a fallu activer leurs applications : la dernière garde le clavier
    /// (le champ de recherche de Mots de passe, par exemple). Side le reprend, et repasse aussitôt sous les tuiles.
    private func rendreLeClavier(_ liste: [EmpruntBas]) {
        guard !PanneauBas.menuOuvert, mainRendue != serie, Date().timeIntervalSince(dernierLever) > 0.3 else { return }
        let devant = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let devant, liste.contains(where: { $0.bundle == devant }) else { return }
        // Toutes les tuiles visibles ont leur fenêtre, devant le tiroir (une note encore en train de s'ouvrir : on attend).
        guard liste.allSatisfy({ e in fenetre(e).map { estDevant($0) } ?? false }) else { return }
        mainRendue = serie
        NSApp.activate(ignoringOtherApps: true)
        panneau?.makeKey()
        // L'activation de Side fait passer le tiroir devant les tuiles, un peu plus tard : on le repasse dessous, à plusieurs reprises.
        for attente in [0.0, 0.1, 0.25, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + attente) { [weak self] in self?.repasserSousLesTuiles() }
        }
        journalBas("clavier repris par Side (%@ était devant)", devant)
    }

    /// Une fenêtre empruntée restée derrière le panneau est ramenée devant, une seule à la fois :
    /// macOS ne fait passer devant qu'une application par demande.
    private func remonter(_ liste: [EmpruntBas], attente: TimeInterval = 0.2) {
        // Un menu de Side est ouvert (clic droit sur la barre des lecteurs…) : activer une application le refermerait.
        guard !PanneauBas.menuOuvert else { return }
        // Side a repris le clavier : les tuiles sont déjà devant, on ne réactive plus leurs applications.
        guard mainRendue != serie else { return }
        guard Date().timeIntervalSince(dernierLever) > attente, levées < 12 else { return }
        for e in liste {
            guard let f = fenetre(e), !estDevant(f) else { continue }
            AXBas.lever(f)
            app(e)?.activate(options: [])
            dernierLever = Date()
            levées += 1
            return
        }

    }

    private func placer(_ e: EmpruntBas, _ f: AXUIElement, _ zone: CGRect) {
        vivantes.insert(e.nom)
        guard !posées.contains(e.nom), let avant = AXBas.cadre(f) else { return }
        let ecran = NSScreen.screens.first?.frame ?? .zero
        // Sa place d'avant l'emprunt, pour la lui rendre si on rouvre l'application normalement.
        if !vues.contains(e.nom) {
            vues.insert(e.nom)          // seulement la toute première fois, avant qu'on y touche
            if avant.minX < ecran.maxX - 2 { origines[e.nom] = avant }
        }
        let aSaPlace = abs(avant.minX - zone.minX) < 2 && abs(avant.minY - zone.minY) < 2
        let aSaTaille = abs(avant.width - zone.width) < 2 && abs(avant.height - zone.height) < 2
        // Bien placée six vérifications de suite (ou l'application refuse la taille demandée) : on la laisse tranquille.
        if aSaPlace && (aSaTaille || replacements[e.nom, default: 0] >= 2) {
            if !aSaTaille, abs(avant.height - zone.height) > 3 { refusHauteur.insert(e.nom) }
            stables[e.nom, default: 0] += 1
            if stables[e.nom, default: 0] >= 6 { posées.insert(e.nom) }
            return
        }
        stables[e.nom] = 0
        guard replacements[e.nom, default: 0] < 6 else { posées.insert(e.nom); return }
        replacements[e.nom, default: 0] += 1
        AXBas.placer(f, zone)
    }

    /// Remet à l'écran la fenêtre d'une tuile rangée (application rouverte normalement, ou tuile retirée du panneau).
    private func rendreLaFenêtre(_ e: EmpruntBas) {
        guard let ecran = NSScreen.screens.first, let visible = NSScreen.main?.visibleFrame,
              let f = fenetre(e), let c = AXBas.cadre(f) else { return }
        let milieu = CGPoint(x: visible.midX, y: ecran.frame.height - visible.midY)
        let r = origines[e.nom] ?? CGRect(x: milieu.x - c.width / 2, y: milieu.y - c.height / 2, width: c.width, height: c.height)
        AXBas.placer(f, r)
        numéros[e.nom] = nil                       // elle n'est plus dans le tiroir : Square peut la ranger
        journalBas("fenêtre rendue à %@", e.nom)
    }

    /// Range hors de l'écran les fenêtres empruntées (sauf celles citées), sans masquer leur application
    /// (sinon elle se verrouille et se recrée).
    private func ranger(sauf gardées: Set<String>) {
        guard let ecran = NSScreen.screens.first else { return }
        for e in emprunts where !gardées.contains(e.nom) && e.nom != libérée {
            guard let f = fenetre(e), let c = AXBas.cadre(f), c.minX < ecran.frame.maxX - 2 else { continue }
            AXBas.placer(f, CGRect(x: ecran.frame.maxX - 1, y: ecran.frame.height - 1, width: c.width, height: c.height))
        }
    }

    /// Une capture d'écran est-elle en train d'être choisie (⌘⇧4, ⌘⇧5) ? Son voile couvre tout l'écran.
    /// Tant qu'il est là, les clics servent à tracer la zone : le panneau ne se referme pas.
    private func captureEnCours() -> Bool { CaptureEcran.enCours }

    @objc private func appActivée(_ note: Notification) {
        guard let a = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if !ouvert {
            if a.bundleIdentifier == "com.apple.Notes", emprunts.contains(where: { $0.note != nil }) { rendreLaGrandeFenêtreDeNotes(a) }
            // Une application empruntée rouverte normalement (Dock, raccourci) pendant que le panneau est fermé :
            // on lui rend sa fenêtre. Pas pour la note, qui ne sert que dans le panneau.
            // Une application du panneau appelée normalement (Dock, raccourci, Square) pendant que le panneau est fermé :
            // sa fenêtre ne sort pas du panneau. C'est le panneau qui s'ouvre, sur sa tuile.
            guard let ecran = NSScreen.screens.first, Date().timeIntervalSince(ferméÀ) > 1.0 else { return }
            for (i, e) in emprunts.enumerated() where e.bundle == a.bundleIdentifier && e.note == nil {
                guard let f = fenetre(e), let c = AXBas.cadre(f), c.minX >= ecran.frame.maxX - 2 else { continue }
                journalBas("%@ appelée : le panneau s'ouvre sur sa tuile", e.nom)
                tuileÀMontrer = i
                ouvrir()
                break
            }
            return
        }
        guard Date().timeIntervalSince(ouvertÀ) > 0.4, !estEmpruntée(a),
              a.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        guard a.bundleIdentifier != "com.apple.screencaptureui", !captureEnCours() else { return }
        // Une application du tiroir qui quitte quand on ferme sa fenêtre (Réglages Système) : macOS passe aussitôt la main
        // à l'application d'avant. Ce n'est pas vous qui changez d'application : le tiroir reste ouvert, et la tuile s'en va.
        // On laisse un court instant à l'application pour finir de quitter avant de trancher.
        let nom = a.localizedName ?? "?"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.ouvert else { return }
            if let i = self.emprunts.firstIndex(where: { e in
                self.vivantes.contains(e.nom) && (self.app(e).map { $0.isTerminated } ?? true)
            }) {
                journalBas("%@ a quitté (fenêtre fermée) : sa tuile est retirée, le tiroir reste ouvert", self.emprunts[i].nom)
                self.retirer(i)
                return
            }
            journalBas("%@ passe devant", nom)
            self.fermer(rendreLaMain: false)
        }
    }
}

// MARK: - Partage du geste à quatre doigts avec Side

/// Side écoute déjà le trackpad. À chaque image, il passe ici d'abord. Le panneau suit les doigts exactement
/// comme la carte de Side (même course, mêmes seuils, même élan au lâcher) :
/// - panneau ouvert : quatre doigts vers le bas le referment, et Side ne bouge pas ;
/// - panneau et Side fermés : quatre doigts vers le haut l'ouvrent (seulement si Side s'ouvre vers le bas).
/// Trie les gestes à quatre doigts dès leur départ : vertical, il est pour Side et le panneau ; horizontal, il est pour Square
/// (changement d'application) et Side n'en voit rien jusqu'au lever des doigts.
enum FiltreHorizontalBas {
    private static var departs: [Int32: (Float, Float)] = [:]
    private static var sens = 0              // 0 : pas encore décidé, 1 : vertical, 2 : horizontal
    private static let seuil: Float = 0.025  // trajet moyen des doigts avant de trancher

    /// Renvoie vrai quand Side doit ignorer cet instant du geste.
    static func avaler(_ doigts: [(Int32, Float, Float)]) -> Bool {
        guard doigts.count >= 4 else {
            // Moins de quatre doigts : rien à trier. Tous levés (ou presque) : le prochain geste repart de zéro.
            if doigts.count < 3 { departs = [:]; sens = 0 }
            return false
        }
        if sens == 1 { return false }
        if sens == 2 { return true }
        var dx: Float = 0, dy: Float = 0, suivis: Float = 0
        for (id, x, y) in doigts { if let d = departs[id] { dx += x - d.0; dy += y - d.1; suivis += 1 } }
        if suivis < 4 {
            departs = Dictionary(uniqueKeysWithValues: doigts.map { ($0.0, ($0.1, $0.2)) })
            return false
        }
        dx /= suivis; dy /= suivis
        guard max(abs(dx), abs(dy)) > seuil else { return true }      // pas encore assez de trajet : on attend de savoir
        sens = abs(dx) > abs(dy) ? 2 : 1
        return sens == 2
    }
}

enum GestePanneauBas {
    /// Réglage « quatre doigts vers le haut ouvrent le tiroir ». Lu hors du fil principal.
    static var actif = true
    /// Le tiroir arrive du haut de l'écran : tous les gestes sont alors inversés (vers le bas pour ouvrir). Lu hors du fil principal.
    static var enHaut = false
    private static var departs: [Int32: Float] = [:]
    private static var réservé = false       // le geste en cours est pour le panneau : Side l'ignore jusqu'au lever des doigts
    private static var suit = false
    private static var fermeture = false
    private static var progression: Float = 0
    private static var vitesse: Float = 0    // en hauteurs de trackpad par seconde, dans le sens d'ouverture
    private static var instant: TimeInterval = 0
    private static let course: Float = 0.3   // trajet des doigts pour amener le panneau à sa place

    private static func moyenne(_ doigts: [(Int32, Float)]) -> Float? {
        let sens: Float = enHaut ? -1 : 1      // compté dans le sens qui ouvre le tiroir
        let ecarts = doigts.compactMap { id, y in departs[id].map { (y - $0) * sens } }
        guard ecarts.count >= 4 else { return nil }
        let moyen = ecarts.reduce(0, +) / Float(ecarts.count)
        guard ecarts.allSatisfy({ moyen > 0 ? $0 > -0.03 : $0 < 0.03 }) else { return nil }
        return moyen
    }

    /// Renvoie vrai si Side doit ignorer cette image du trackpad. Appelé hors du fil principal.
    static func intercepter(_ doigts: [(Int32, Float)], sideOuvert: Bool, sensSide: String) -> Bool {
        let maintenant = ProcessInfo.processInfo.systemUptime
        if doigts.count < 3 {
            if suit {   // doigts levés : on finit le geste selon la distance et l'élan
                suit = false
                let ouvrir = fermeture
                    ? !(progression < 0.6 || vitesse < -0.6 || (progression < 0.85 && vitesse < 0.2))
                    : progression > 0.4 || vitesse > 0.6 || (progression > 0.15 && vitesse > -0.2)
                let elan = CGFloat(vitesse / course)
                DispatchQueue.main.async { PanneauBas.commun.lacherDoigts(ouvrir: ouvrir, elan: elan) }
            }
            departs = [:]
            réservé = false
            return false
        }
        for (id, y) in doigts where departs[id] == nil { departs[id] = y }
        if suit {
            guard let m = moyenne(doigts) else { return true }
            let p = max(0, (fermeture ? 1 : 0) + m / course)
            let dt = Float(maintenant - instant)
            if dt > 0.004 { vitesse = vitesse * 0.6 + (p - progression) * course / dt * 0.4; instant = maintenant }
            progression = p
            DispatchQueue.main.async { PanneauBas.commun.suivreDoigts(CGFloat(p)) }
            return true
        }
        if réservé { return true }
        let panneauOuvert = PanneauBas.estOuvertBrut
        guard doigts.count >= 4, let m = moyenne(doigts), abs(m) > 0.015 else { return panneauOuvert }
        if panneauOuvert {
            réservé = true
            guard m < 0 else { return true }     // vers le haut, panneau déjà ouvert : rien à faire
            fermeture = true
        } else if m > 0, !sideOuvert, sensSide == (enHaut ? "haut" : "bas"), actif {
            réservé = true
            fermeture = false
        } else {
            return false
        }
        suit = true
        progression = (fermeture ? 1 : 0) + m / course
        vitesse = 0
        instant = maintenant
        let p = progression, ferme = fermeture
        DispatchQueue.main.async {
            PanneauBas.commun.commencerSuivi(fermeture: ferme)
            PanneauBas.commun.suivreDoigts(CGFloat(p))
        }
        return true
    }
}
