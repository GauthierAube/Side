// Le tiroir : le second panneau de Side. Il arrive du bord opposé au Finder (⌃⌥ Espace, son coin actif, ou quatre doigts)
// avec une partie multimédia (YouTube, Spotify, un site au choix) et des fenêtres empruntées à d'autres applications,
// posées côte à côte dans une bande qu'on fait défiler.
// Il se referme au clic ailleurs, avec Échap, le même raccourci ou quatre doigts dans l'autre sens.
import AppKit

extension Bool {
    /// `condition.then { valeur }` : la valeur si c'est vrai, rien sinon.
    func then<T>(_ f: () -> T) -> T? { self ? f() : nil }
}
import Carbon.HIToolbox
import UniformTypeIdentifiers

@_silgen_name("_AXUIElementGetWindow") func _AXUIElementGetWindow(_ el: AXUIElement, _ wid: inout CGWindowID) -> AXError
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindowsBas(_ cid: Int32, _ masque: Int32, _ fenetres: CFArray) -> CFArray?
@_silgen_name("CGSSetConnectionProperty") func CGSSetConnectionPropertyBas(_ cid: Int32, _ cible: Int32, _ cle: CFString, _ valeur: CFTypeRef) -> Int32

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
/// Les raccourcis du tiroir et du presse-papiers, rangés sous le nom « tiroir.<numéro> » dans le registre commun de Side.
enum TouchesBas {
    static func ajouter(_ id: UInt32, touche: UInt32, modifs: UInt32, action: @escaping () -> Void) {
        RaccourcisGlobaux.ajouter("tiroir.\(id)", touche: touche, modifs: modifs, action: action)
    }
    static func retirer(_ id: UInt32) { RaccourcisGlobaux.retirer("tiroir.\(id)") }
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
            // Spotify était fermé : on l'ouvre, puis on rejoue l'ordre une fois qu'il est prêt (avant, l'ordre était perdu).
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Spotify.app"),
                                               configuration: NSWorkspace.OpenConfiguration()) { app, _ in
                guard app != nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if ouvert { commande(ordre, puis: fin) } }
            }
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

/// Une icône de la barre du tiroir : un clic l'affiche, on la glisse pour changer l'ordre (comme dans le Dock),
/// le clic droit ouvre ses actions.
final class IcôneBarreBas: NSImageView {
    var auClic: (() -> Void)?
    var auGlisser: ((CGFloat) -> Void)?       // déplacement vertical depuis le début du glisser
    var auLâcher: (() -> Void)?
    var auMenu: ((NSEvent) -> Void)?
    private var départ: NSPoint?
    private var glisse = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { départ = nil; auMenu?(event); return }    // ⌃-clic : comme un clic droit
        départ = event.locationInWindow; glisse = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let d = départ else { return }
        let dy = event.locationInWindow.y - d.y
        if !glisse, abs(dy) > 4 { glisse = true }
        if glisse { auGlisser?(dy) }
    }
    override func mouseUp(with event: NSEvent) {
        if glisse { auLâcher?() } else { auClic?() }
        départ = nil; glisse = false
    }
    override func rightMouseDown(with event: NSEvent) { auMenu?(event) }
}

/// Une ligne de menu qui exécute une action (les menus du tiroir sont construits à la volée).
final class ActionMenuBas: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func agir() { action() }
}

/// Photo d'une tuile. Un clic dessus la fait venir en entier dans le panneau.
final class ImageTuileBas: NSImageView {
    var auClic: (() -> Void)?
    var auMenu: ((NSEvent) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { auMenu?(event) } else { auClic?() }
    }
    override func rightMouseDown(with event: NSEvent) { auMenu?(event) }
}

/// Le bord haut du panneau : on le tire pour changer la hauteur du panneau, comme le bord de la carte de Side.
/// Une petite barre au milieu le signale, comme en haut des volets d'un téléphone.
final class PoigneeHauteurBas: NSView {
    var auDebut: (() -> Void)?
    var auTirage: ((CGFloat) -> Void)?      // de combien le pointeur est monté depuis le début
    var aLaFin: (() -> Void)?
    private var depart: CGFloat = 0
    private var zone: NSTrackingArea?

    // (Plus de petit trait dessiné : le tiroir se redimensionne par tous ses bords, le pointeur suffit à le signaler.)
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
    /// Le second bouton de la ligne (à gauche du premier), s'il y en a un.
    var auClic2: (() -> Void)?
    private var zone: NSTrackingArea?
    private let aSecond: Bool

    init(icone: NSImage?, nom: String, signe: String?, couleur: NSColor, signe2: String? = nil, aide2: String? = nil) {
        aSecond = signe2 != nil
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Rayon.ligne
        let texte = NSTextField(labelWithString: nom)
        texte.font = .systemFont(ofSize: 13)
        texte.lineBreakMode = .byTruncatingTail
        texte.frame = NSRect(x: icone == nil ? 10 : 36, y: 6, width: signe2 == nil ? 206 : 180, height: 18)
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
        if let signe2 {
            let v = NSImageView(image: NSImage(systemSymbolName: signe2, accessibilityDescription: aide2) ?? NSImage())
            v.contentTintColor = .controlAccentColor
            v.frame = NSRect(x: 226, y: 6, width: 18, height: 18)
            v.toolTip = aide2
            addSubview(v)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.contains(p) else { return }
        // Le second bouton (plein écran) a sa propre zone ; le reste de la ligne garde l'action habituelle.
        if aSecond, p.x >= 220, p.x < 248, let a = auClic2 { a(); return }
        auClic?()
    }
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
    struct Ligne {
        let icone: NSImage?; let nom: String; let signe: String?; let couleur: NSColor; let action: (() -> Void)?
        /// Un second bouton, à gauche du premier (« Passer en plein écran » pour une app du tiroir).
        var signe2: String? = nil; var aide2: String? = nil; var action2: (() -> Void)? = nil
        init(icone: NSImage?, nom: String, signe: String?, couleur: NSColor, action: (() -> Void)?) {
            self.icone = icone; self.nom = nom; self.signe = signe; self.couleur = couleur; self.action = action
        }
    }
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
                let v = LigneSelecteurBas(icone: l.icone, nom: l.nom, signe: l.signe, couleur: l.couleur, signe2: l.signe2, aide2: l.aide2)
                if let a2 = l.action2 { v.auClic2 = { [weak self] in self?.fermer(); a2() } }
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
        let ecran = (PanneauBas.commun.écranDuTiroir)?.visibleFrame ?? .zero
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
        // Coins arrondis par un masque, comme le recommande Apple pour un fond flou : arrondir son calque laissait
        // dépasser un petit coin carré clair (le fond de la fenêtre et son ombre restaient carrés).
        let r: CGFloat = 10
        let masque = NSImage(size: NSSize(width: 2 * r + 1, height: 2 * r + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        masque.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        masque.resizingMode = .stretch
        fond.maskImage = masque
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
    /// Là où le tiroir gare les fenêtres qu'il garde : juste après le bord droit du plus à droite des écrans.
    /// (Avant le 15/11/2026 : le bord de l'écran principal, donc en plein sur un second écran placé à droite.)

    static let commun = PanneauBas()
    /// Lus hors du fil principal (geste à quatre doigts, défilement).
    static var estOuvertBrut = false
    static var cadreBrut = CGRect.zero          // le panneau, en coordonnées globales
    static var curseurBord = false              // le pointeur est sur le bord du tiroir (double flèche affichée)

    /// Ce point de l'écran est-il sur le bord qu'on tire pour régler la hauteur ? Quelques points au-dehors du tiroir,
    /// et toute sa marge au-dedans (jusqu'au bord des fenêtres des tuiles compris).
    /// Avec Peinard comme lecteur YouTube, le tiroir lui-même ne se redimensionne plus (demande de Gauthier, 15/11/2026) :
    /// plus de bord ni de côté à tirer, plus de relais. Il garde la taille qu'il avait. Seule la séparation entre le coin
    /// multimédia et les applications se tire encore (poignée). À 740 points de large, Peinard (page à 77 %) donne 960 points
    /// à YouTube, qui met alors de lui-même la vidéo à gauche et les suivantes à droite ; plus étroit, Peinard garde une
    /// bande de suggestions jusqu'à 462 points environ, puis une seule colonne.
    static var tailleFixe: Bool { TuilePeinard.disponible && ConfigTiroir.commun.medias.contains { $0.genre == "youtube" } }
    static let largeurPeinard: CGFloat = 740

    /// Le dernier clic sur le bord du tiroir (instant, endroit) : deux clics rapprochés font un double-clic (agrandir).
    static var dernierClicBord: (TimeInterval, CGPoint) = (0, .zero)
    /// `mêmeFigé` : aussi quand la taille du tiroir est figée (le double-clic pour agrandir reste possible).
    static func surLeBord(_ p: CGPoint, mêmeFigé: Bool = false) -> Bool {
        guard mêmeFigé || !tailleFixe else { return false }
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
    /// `sansSide` : les petites fenêtres de Side elle-même (caches des boutons verts) ne comptent pas.
    static func tiroirSous(_ p: CGPoint, sansSide: Bool = false) -> Bool {
        let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let moi = Int(ProcessInfo.processInfo.processIdentifier)
        for w in infos {
            if sansSide, (w[kCGWindowOwnerPID as String] as? Int) == moi { continue }
            let couche = (w[kCGWindowLayer as String] as? Int) ?? 0
            // Seules les fenêtres d'applications ordinaires peuvent couvrir le tiroir. Depuis macOS 27.2, le Centre de
            // notifications garde une fenêtre transparente sur tout l'écran (couche 23) : elle ne compte pas.
            guard couche < 20, ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0.05,     // ni barre des menus, ni pointeur, ni fenêtre invisible
                  (w[kCGWindowOwnerName as String] as? String) != "Centre de notifications",
                  (w[kCGWindowOwnerName as String] as? String) != "Notification Center",
                  let d = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: d), r.contains(p),
                  let n = w[kCGWindowNumber as String] as? Int else { continue }
            return numerosDuTiroir.contains(n)
        }
        return false
    }
    /// Le relais (13/11/2026) : attraper un bord du tiroir revient à attraper le bord de la fenêtre de l'application affichée.
    /// Le clic est décalé sur ce bord : c'est l'application qui se redimensionne elle-même, comme d'habitude sur le Mac
    /// (donc sans à-coups), et le tiroir ne fait que la suivre. `relais` est le décalage ajouté au pointeur pendant le geste.
    static var relais: CGPoint?
    static var relaisHauteurSeule = false        // l'application affichée a une largeur fixe : pas de relais par les côtés
    static var relaisCôté = 0                    // 0 : le bord du haut (ou du bas) ; -1 : le bord gauche ; 1 : le droit
    /// La fenêtre de l'application affichée, si elle se laisse redimensionner (coordonnées globales). Tenue par la veille.
    static var fenêtreRelayable: CGRect?
    static var tirageHauteur = false            // on est en train de tirer le bord du tiroir (suivi par le filtre d'événements)
    static var departHauteur: CGFloat = 0
    /// Les côtés du tiroir, à gauche (le bord du coin multimédia) et à droite : on les tire pour réduire ou élargir tout le tiroir,
    /// qui reste centré. -1 : côté gauche, 1 : côté droit, 0 : aucun.
    static var tirageLargeur = 0
    static var departLargeur: CGFloat = 0
    static var curseurCôté = false
    /// Le dernier écart de la souris pendant qu'on tire un bord, et s'il y a déjà un recalcul en route.
    static var écartEnAttente: CGFloat = 0
    static var recalculPrévu = false
    static func surUnCôté(_ p: CGPoint) -> Int {
        guard !tailleFixe else { return 0 }
        let c = cadreBrut
        guard p.y >= c.minY + 4, p.y <= c.maxY - 4 else { return 0 }
        if p.x >= c.minX - 8, p.x <= c.minX + 10, tiroirSous(p) || p.x < c.minX { return -1 }
        if p.x >= c.maxX - 10, p.x <= c.maxX + 8, tiroirSous(p) || p.x > c.maxX { return 1 }
        return 0
    }
    static var filtre: CFMachPort?

    let idRaccourci: UInt32 = 1
    let idEchap: UInt32 = 2
    var enCapture = false               // une capture d'écran est en cours, tiroir ouvert : il se fait oublier
    var notesIntrouvables: Set<String> = []   // notes qu'on n'a pas retrouvées dans Notes : on ne les réclame plus en boucle
    /// Un geste a choisi une application, mais un autre geste a commencé avant que sa fenêtre soit posée : à faire à la fin.
    var installationEnAttente = false
    /// La fenêtre de chaque tuile, telle que son application l'a donnée il y a un instant (voir fenetre).
    var fenêtresGardées: [String: (fenêtre: AXUIElement?, sansRéponse: Bool, à: CFAbsoluteTime)] = [:]
    var titresDeNotes: [String: String] = [:] // le titre actuel de chaque note (il change si on modifie sa première ligne)
    let largeurLecteur: CGFloat = 300
    let largeurPlus: CGFloat = 44
    let marge: CGFloat = 14

    // MARK: Les tuiles (la liste est la vôtre : bouton « + » du panneau)

    var emprunts: [EmpruntBas] = {
        if let d = UserDefaults.standard.array(forKey: "panneauBasTuiles") as? [[String: String]] {
            // Un Finder ajouté avant qu'il soit refusé : il quitte le tiroir.
            return d.compactMap { EmpruntBas($0) }.filter { !PanneauBas.refusées.contains($0.bundle) }
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

    var panneau: NSPanel?
    var fond: FondPanneauBas?
    var teinte: TeinteBas?

    let bandeVue = NSView()             // la bande où défilent les tuiles (elle coupe ce qui dépasse)
    let plus = BoutonBas(frame: .zero)
    var bienvenue: BienvenueTiroirBas?      // le mot d'accueil, à la toute première ouverture du tiroir
    let roue = BoutonBas(frame: .zero)      // la roue dentée, au bout de la bande sous la case « + » : ouvre les réglages
    let selecteur = SelecteurTuilesBas()   // la liste qui s'ouvre au-dessus de la case « + »
    let poignee = PoigneeHauteurBas()
    var hauteurAuDepart: CGFloat = 0
    var refusHauteur: Set<String> = []     // applications qui refusent la hauteur du panneau : on n'insiste pas
    /// Le panneau est ouvert par-dessus un plein écran d'Apple : macOS interdit d'y amener les fenêtres des autres
    /// applications. Les tuiles restent alors en photo, et on ne touche à aucune fenêtre (sinon macOS renvoie sur le bureau).
    var sansFenêtres = false
    let banniere = NSView()
    let messageBanniere = NSTextField(labelWithString: "")
    var boutonBanniere: NSButton?
    var ailleursNoms: Set<String> = []          // tuiles dont la fenêtre vit sur un autre bureau : laissées en photo
    let lecteur = LecteurSpotifyBas(frame: .zero)
    /// Les pages web du coin multimédia (YouTube, et les sites ajoutés dans les réglages), créées à la demande et gardées :
    /// celle qui est masquée continue de jouer.
    /// Les pages du coin multimédia : l'ancien lecteur web (sites, et YouTube sans Peinard) ou la tuile Peinard.
    var pagesWeb: [String: NSView] = [:]
    /// Seulement les lecteurs web (pas la tuile Peinard).
    var lecteursWeb: [LecteurYouTubeBas] { pagesWeb.values.compactMap { $0 as? LecteurYouTubeBas } }
    let hauteurChoix: CGFloat = 34
    let poignéeMédia = PoigneeLargeurBas()
    var largeurMédiaAuDépart: CGFloat = 0
    let choixMédia = ChoixMediaBas()
    var photos: [String: NSImage] = [:]        // dernière photo nette de chaque tuile
    var images: [String: ImageTuileBas] = [:]   // photo de chaque tuile, pendant qu'elle glisse, défile ou attend sur le côté
    var veille: Timer?                          // regarde si vous avez fermé une fenêtre (bouton rouge)
    var absences: [String: Int] = [:]
    var numéros: [String: CGWindowID] = [:] { didSet { publierFenêtres() } }
    /// La tuile sortie en grand par son bouton vert : sa fenêtre est hors du tiroir, Square peut la ranger.
    var enGrand: String? { didSet { publierFenêtres() } }
    var tic = 0
    var enMain: String?                         // la tuile que vous êtes en train d'élargir ou de déplacer
    var enMainRetaillée = false
    var dernierAppui = Date.distantPast         // dernière fois où le bouton de la souris était enfoncé
    var libérée: String?                        // la tuile qui sort du panneau en grand : on ne la range pas
    /// Les boutons jaune et vert de chaque tuile visible (coordonnées globales), pour les intercepter. Lus par le filtre de clics.
    static var boutonsVerts: [(nom: String, cadre: CGRect)] = [] {
        didSet {
            let cadres = boutonsVerts.map(\.cadre)
            if Thread.isMainThread { CachesBoutonsVerts.placer(cadres) } else { DispatchQueue.main.async { CachesBoutonsVerts.placer(cadres) } }
        }
    }
    static var boutonsJaunes: [(nom: String, cadre: CGRect)] = []
    static var clicAvalé = false
    var ouvert = false {
        didSet {
            PanneauBas.estOuvertBrut = ouvert
            // Lu par Mulot à l'appui du bouton de pouce : tiroir ouvert, son sélecteur apparaît tout de suite.
            if ouvert != oldValue { UserDefaults.standard.set(ouvert, forKey: "tiroirOuvert") }
        }
    }
    /// Les fenêtres secondaires (réglages, boîtes de dialogue) déjà posées au-dessus de leur application dans le tiroir :
    /// chacune n'est posée qu'une fois, ensuite on peut la déplacer.
    var secondairesPosées: Set<CGWindowID> = []
    /// Mulot mène le tiroir (bouton de pouce tenu) : voir « tiroir:debut » dans commandeExterieure.
    var sourisMène = false
    var ouvertAvantLaSouris = false      // le tiroir était déjà ouvert au début du geste
    var sélecteurParLaSouris = false     // la souris est allée jusqu'au sélecteur pendant ce geste
    var positionSouris: CGFloat = 0      // la dernière position envoyée par Mulot (0 fermé, 1 ouvert, au-delà : le sélecteur)
    /// L'écran choisi à l'ouverture (celui de la souris) : le tiroir y reste tant qu'il est ouvert (voir écranDuTiroir).
    var écranOuvert: NSScreen?
    var ouvertÀ = Date.distantPast
    var ferméÀ = Date.distantPast
    var tuileÀMontrer: Int?             // la tuile à amener à l'écran une fois le panneau arrivé
    var pidAvant: pid_t = 0
    var ecouteClics: Any?
    var minuteur: Timer?
    var q: CGFloat = 0                  // 0 : caché sous l'écran ; 1 : à sa place
    var suiviDoigts = false             // les doigts font avancer le panneau
    var fermetureSuivie = false         // ... pour le refermer
    var enPlace = false                 // le panneau a fini d'arriver
    var glissé = false                  // on peut installer les vraies fenêtres
    var glisséÀ = Date.distantPast
    var défile = false                  // la bande est en train de défiler : toutes les tuiles sont des photos
    var finDéfilement: DispatchWorkItem?
    var replacements: [String: Int] = [:]
    var stables: [String: Int] = [:]    // nombre de vérifications d'affilée où la fenêtre était à sa place
    var vivantes: Set<String> = []      // tuiles dont on a vu la fenêtre depuis l'ouverture du tiroir (même pas encore bien posée)
    var posées: Set<String> = []        // fenêtres bien installées : on n'y touche plus, vous pouvez les redimensionner
    var origines: [String: CGRect] = [:]
    var vues: Set<String> = []
    var dernierLever = Date.distantPast
    var levées = 0
    var mainRendue = -1                       // la série d'ouverture pour laquelle Side a repris le clavier
    /// Une app à la fois : le trou ouvert dans le fond du tiroir, à la place de l'application affichée (voir Tiroir+Trou).
    var trou: CGRect? { didSet { PanneauBas.trouÉcran = trou; majClicsDansLeTrou(nil) } }
    /// Le trou, lu par le filtre d'événements (hors du fil principal) pour savoir si le pointeur est dedans.
    static var trouÉcran: CGRect?
    static var pointeurDansLeTrou = false
    /// Une app à la fois : le tiroir monte presque en plein écran, le temps d'une grosse tâche (20/11/2026).
    /// Jamais retenu : il se rouvre toujours à sa taille habituelle.
    var agrandi = false
    /// La commande de macOS qui a agrandi la fenêtre (« remplir » ou « zoom »), pour la réduire par la commande inverse.
    var commandeAgrandi: String?
    /// Tiroir agrandi : la place du bouton « réduire » à l'écran (coordonnées globales). Les clics dessus restent au tiroir.
    static var pastilleÉcran: CGRect?
    var enTransition = false                  // l'animation d'agrandissement (ou de réduction) est en cours
    let boutonAgrandir = BoutonBas(frame: .zero)
    var installéeÀ: Date?                    // l'application affichée est arrivée dans le trou (pour l'installation en cours)
    var activations = 0                       // demandes d'activation pour l'installation en cours
    var activéeÀ = Date.distantPast           // la dernière fois que Side a fait passer une application du tiroir devant
    /// Un menu de Side est en train d'être affiché (suivi par les notifications de NSMenu).
    static var menuOuvert = false
    var demandées: Set<String> = []     // fenêtres dont on a déjà demandé l'ouverture, pour cette fois
    var serie = 0                       // pour abandonner les attentes d'une ouverture précédente

    /// Le mot d'accueil du tiroir : seulement à la fin de l'ancienne visite dans la carte (essais).
    static var motDAccueil = false
    /// Le coin actif du tiroir. Appelé plusieurs fois par seconde par Side, avec la place du pointeur.
    /// Entrer dans le coin ouvre le tiroir ; il faut s'en éloigner nettement avant qu'y revenir ne le referme.
    var coinArmé = true
    var débutCoin: Date?
    // MARK: Géométrie

    var largeurAuDépart: CGFloat = 0
    /// En dessous, des applications comme Réglages Système n'acceptent plus de tenir dans une tuile.
    let hauteurMini: CGFloat = 530

    // MARK: Une application à la fois (13/11/2026)
    let largeurColonne: CGFloat = 56
    /// La colonne d'icônes, à droite : une par application du tiroir ; celle qu'on regarde est mise en avant.
    var icônesColonne: [IcôneBarreBas] = []
    /// Pendant qu'on glisse une icône de la barre : son rang de départ, et le rang où elle irait si on la lâchait.
    var glisseIcône: (de: Int, vers: Int)?
    var pasIcônes: CGFloat = 40
    var hautIcônes: CGFloat = 0
    var xIcônes: CGFloat = 0
    var cheminsColonne: [String] = []
    let repèreColonne = NSView()
    /// Le fond de la colonne : une barre flottante, floue et teintée comme le Finder de Side (même réglage d'opacité).
    lazy var barreColonne: NSVisualEffectView = {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = Rayon.panneau
        v.layer?.cornerCurve = .continuous
        v.layer?.masksToBounds = true
        v.layer?.borderWidth = 0.5
        v.layer?.borderColor = NSColor(white: 0.5, alpha: 0.25).cgColor
        let t = TeinteBas()
        t.wantsLayer = true
        t.autoresizingMask = [.width, .height]
        v.addSubview(t)
        bandeVue.addSubview(v, positioned: .below, relativeTo: plus)
        return v
    }()
    /// La petite barre du bouton « agrandir », au-dessus de la colonne : le même fond, mais à part.
    lazy var barreAgrandir: NSVisualEffectView = {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = Rayon.panneau
        v.layer?.cornerCurve = .continuous
        v.layer?.masksToBounds = true
        v.layer?.borderWidth = 0.5
        v.layer?.borderColor = NSColor(white: 0.5, alpha: 0.25).cgColor
        let t = TeinteBas()
        t.wantsLayer = true
        t.autoresizingMask = [.width, .height]
        v.addSubview(t)
        bandeVue.addSubview(v, positioned: .below, relativeTo: boutonAgrandir)
        return v
    }()
    /// Le voile flou posé derrière le tiroir agrandi (le même que celui du Finder de Side) : on ne voit plus que l'application.
    var voileAgrandi: NSPanel?
    /// Pendant le mini carrousel (geste à quatre doigts prolongé) : le rang de l'application au départ.
    var navDepart: Int?
    var navDepuisOuvert = false
    /// Trajet des doigts pour passer d'une application à la suivante, en « trajets d'ouverture » (0,3 hauteur de trackpad) :
    /// 0,07 hauteur de trackpad, comme le carrousel du plein écran (très sensible).
    let parApp: CGFloat = 0.07 / 0.3







    // MARK: Hauteur du panneau (on tire son bord haut, comme pour la carte de Side)

    /// Une app à la fois : pendant qu'on tire un bord du tiroir, la vraie fenêtre de l'application suit en direct (elle se
    /// redimensionne comme si on la tirait elle-même), au lieu d'être remplacée par une photo figée.
    var enDirect = false
    var étaitAppuyé = false
    var pointAppui = NSPoint.zero
    var suiviFenêtre = false
    var rangDirect = 0
    var finDirectÀ = Date.distantPast          // l'application affichée : elle le reste quelle que soit la nouvelle hauteur
    // MARK: Relais : l'application se redimensionne elle-même, le tiroir la suit

    var piluleDuGeste = false


    // MARK: Ajouter et retirer des applications

    /// Applications qui ne peuvent pas aller dans le tiroir : le Finder (ses fenêtres appartiennent au bureau, il n'en a
    /// souvent aucune à prêter ; Side a son propre Finder pour ça).
    static let refusées: Set<String> = ["com.apple.finder"]

    // MARK: Changer d'avis : du plein écran au tiroir, et retour

    /// Le résultat de la dernière question posée par fenetre(_:) : l'application n'a pas répondu à temps.
    var sansRéponse = false

    // MARK: Fenêtres empruntées

    /// Pendant qu'une note s'ouvre dans sa propre fenêtre : toute autre fenêtre de Notes est repoussée hors de l'écran
    /// dès qu'elle apparaît (on regarde cinquante fois par seconde), pour qu'on ne la voie pas passer.
    var écartNotes: Timer?
    var enVérification: Set<String> = []
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
    /// Une app à la fois : prolonger le geste fait défiler les applications. Lu hors du fil principal.
    static var navigation = true
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
            if m > 0 {
                // Panneau déjà ouvert, doigts dans le sens d'ouverture : une app à la fois, les applications défilent.
                guard navigation else { return true }
                fermeture = false
                suit = true
                progression = 1 + m / course
                vitesse = 0
                instant = maintenant
                let p = progression
                DispatchQueue.main.async {
                    PanneauBas.commun.commencerNavigation()
                    PanneauBas.commun.suivreDoigts(CGFloat(p))
                }
                return true
            }
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
