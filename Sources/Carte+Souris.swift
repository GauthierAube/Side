// Actions sur les fichiers, redimensionnement par les bords, sélection à la souris.
// Partie de AppDelegate (Side.swift), rangée à part le 15/11/2026 sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

extension AppDelegate {
    // MARK: Actions sur les fichiers
    /// On ferme d'abord la carte, puis on ouvre sans attendre la réponse de macOS :
    /// certaines ouvertures (app téléchargée d'Internet…) affichent une question et bloqueraient l'app.
    func ouvrir(_ url: URL) {
        hide()
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
    func reveler(_ url: URL) {
        hide()
        DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func lacherChamp() {
        if panel.firstResponder is NSTextView { panel.makeFirstResponder(nil) }
    }

    /// Après un glisser parti de Side : les listes sont relues, et les zones de dépôt oublient les fichiers partis.
    func apresGlisser() {
        store.glissee = nil      // un glisser de colonne lâché ailleurs que sur un titre n'est plus « en cours »
        (0..<Etagere.nombre).forEach(Etagere.purger)
        store.reloadAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.store.nettoyerZones(); self.majDepot() }
    }

    // MARK: Redimensionner la carte par ses bords
    /// Le bord (ou le coin) de la carte sous ce point de l'écran : x = -1 gauche, 1 droite ; y = 1 haut, -1 bas.
    /// La bande sensible fait 7 points à partir du bord, vers l'intérieur ; près d'un coin, on tire les deux bords.
    func bordSous(_ p: NSPoint) -> (x: Int, y: Int)? {
        let c = cadreSeule
        guard visible, store.accueil == nil, c.insetBy(dx: -1, dy: -1).contains(p) else { return nil }
        let bande: CGFloat = 7, coin: CGFloat = 20
        let g = p.x - c.minX, d = c.maxX - p.x, b = p.y - c.minY, h = c.maxY - p.y
        guard min(g, d, b, h) <= bande else { return nil }
        var x = 0, y = 0
        if g <= bande { x = -1 } else if d <= bande { x = 1 }
        if h <= bande { y = 1 } else if b <= bande { y = -1 }
        // Près d'un coin : on prend aussi l'autre bord.
        if x != 0, y == 0 { if h <= coin { y = 1 } else if b <= coin { y = -1 } }
        if y != 0, x == 0 { if g <= coin { x = -1 } else if d <= coin { x = 1 } }
        return (x, y)
    }
    func curseurBord(_ x: Int, _ y: Int) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch (x, y) {
            case (-1, 1): position = .topLeft
            case (1, 1): position = .topRight
            case (-1, -1): position = .bottomLeft
            case (1, -1): position = .bottomRight
            case (0, 1): position = .top
            case (0, -1): position = .bottom
            case (-1, 0): position = .left
            default: position = .right
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        return y == 0 ? .resizeLeftRight : (x == 0 ? .resizeUpDown : .crosshair)
    }
    /// Souris sur un bord : le pointeur change. Bouton enfoncé puis tiré : la carte change de taille.
    func suivreBords(_ ev: NSEvent) -> NSEvent? {
        let ici = NSEvent.mouseLocation
        switch ev.type {
        case .mouseMoved:
            if let b = bordSous(ici), ev.window === panel || ev.window == nil {
                curseurBord(b.x, b.y).set()
                pointeurBord = true
            } else if pointeurBord {
                pointeurBord = false
                NSCursor.arrow.set()
            }
        case .leftMouseDown:
            guard ev.window === panel, let b = bordSous(ici) else { return ev }
            priseBord = (ici, config.largeurSeule, config.tailleHauteur, b.x, b.y)
            return nil   // le clic ne descend pas vers un bouton situé juste dessous
        case .leftMouseDragged:
            guard let d = priseBord, let e = ecran else { return ev }
            curseurBord(d.x, d.y).set()
            // Une carte centrée grandit des deux côtés à la fois : on double l'écart pour que le bord suive la souris.
            let centreeX = config.bord == .haut || config.bord == .bas, centreeY = config.bord == .gauche || config.bord == .droite
            if d.x != 0 {
                let dx = (ici.x - d.souris.x) * CGFloat(d.x) * (centreeX ? 2 : 1)
                config.largeurSeule = min(1, max(0.35, d.largeur + Double(dx / max(e.frame.width, 1))))
            }
            if d.y != 0 {
                let dy = (ici.y - d.souris.y) * CGFloat(d.y) * (centreeY ? 2 : 1)
                config.tailleHauteur = min(0.9, max(0.15, d.hauteur + Double(dy / max(e.frame.height, 1))))
            }
            return nil
        case .leftMouseUp:
            guard priseBord != nil else { return ev }
            priseBord = nil
            return nil
        default: break
        }
        return ev
    }

    func suivreGlisser(_ ev: NSEvent) -> NSEvent? {
        switch ev.type {
        case .leftMouseDown:
            departGlisser = nil
            departPile = nil
            if let item = survoleAffiche, let f = ev.window, f === panel || f === depotPanel, !ev.modifierFlags.contains(.control),
               bordSous(NSEvent.mouseLocation) == nil {   // pas sur un bord de la carte : là, on redimensionne
                departGlisser = (ev.locationInWindow, item, f)
            } else if let pile = pileSurvolee, let f = ev.window, f === depotPanel, pile.items.count > 1 {
                departPile = (ev.locationInWindow, pile)
            }
        case .leftMouseUp:
            departGlisser = nil
            departPile = nil
        case .leftMouseDragged:
            // La pile d'une zone de dépôt : tous ses fichiers partent ensemble.
            if let d = departPile, let f = depotPanel, ev.window === f, let vue = f.contentView,
               hypot(ev.locationInWindow.x - d.point.x, ev.locationInWindow.y - d.point.y) >= 5 {
                departPile = nil
                let ici = vue.convert(ev.locationInWindow, from: nil)
                let urls = d.pile.items.map(\.url)
                let elements: [NSDraggingItem] = urls.enumerated().map { i, u in
                    let e = NSDraggingItem(pasteboardWriter: u as NSURL)
                    let icone = NSWorkspace.shared.icon(forFile: u.path)
                    icone.size = NSSize(width: 48, height: 48)
                    let d = CGFloat(min(i, 4)) * 5
                    e.setDraggingFrame(NSRect(x: ici.x - 24 + d, y: ici.y - 24 - d, width: 48, height: 48), contents: icone)
                    return e
                }
                DepartGlisser.shared.sortis = (urls, d.pile.indexEtagere)
                journal("zone de dépôt : la pile part (\(urls.count) fichiers)")
                vue.beginDraggingSession(with: elements, event: ev, source: DepartGlisser.shared)
                return nil
            }
            guard let d = departGlisser, ev.window === d.fenetre, let vue = d.fenetre.contentView,
                  hypot(ev.locationInWindow.x - d.point.x, ev.locationInWindow.y - d.point.y) >= 5 else { return ev }
            departGlisser = nil
            let element = NSDraggingItem(pasteboardWriter: d.item.url as NSURL)
            let icone = NSWorkspace.shared.icon(forFile: d.item.url.path)
            icone.size = NSSize(width: 48, height: 48)
            let ici = vue.convert(ev.locationInWindow, from: nil)
            element.setDraggingFrame(NSRect(x: ici.x - 24, y: ici.y - 24, width: 48, height: 48), contents: icone)
            // Parti d'une zone de dépôt flottante : elle l'oubliera une fois déposé ailleurs.
            if d.fenetre === depotPanel, let zone = survoleColonne, zone.estEtagere { DepartGlisser.shared.sortis = ([d.item.url], zone.indexEtagere) }
            vue.beginDraggingSession(with: [element], event: ev, source: DepartGlisser.shared)
            return nil
        default: break
        }
        return ev
    }

    func survolerPile(_ colonne: Column, _ dedans: Bool) {
        if dedans { pileSurvolee = colonne } else if pileSurvolee === colonne { pileSurvolee = nil }
    }
    /// Le cadre de la fenêtre des zones de dépôt, si elle est à l'écran.
    var cadreDepot: NSRect? { depotPanel?.isVisible == true ? depotPanel?.frame : nil }

    func survoler(_ item: FileItem, _ colonne: Column, _ dedans: Bool) {
        if dedans { survole = item; survoleColonne = colonne } else if survole == item { survole = nil }
    }

    /// L'élément sous la souris, s'il est toujours affiché. SwiftUI ne prévient pas quand la ligne survolée disparaît
    /// (on entre dans un dossier) : sans cette vérification, un clic droit ou un glisser dans le vide visait l'ancien élément.
    var survoleAffiche: FileItem? {
        guard let it = survole, let c = survoleColonne else { return nil }
        let present = c.visibles.contains { $0.url == it.url } || c.niveaux.contains { $0.contains { $0.url == it.url } }
        return present ? it : nil
    }

    // MARK: Sélection à la souris, comme dans le Finder
    /// Un clic sur un élément : seul (clic), ajouté ou retiré (⌘-clic), ou toute la plage depuis l'ancre (Maj-clic).
    /// Renvoie vrai si le clic a seulement modifié la sélection (avec ⌘ ou Maj) : rien d'autre ne doit alors se passer.
    @discardableResult
    func cliquer(_ url: URL, _ colonne: Column, liste: [URL]) -> Bool {
        let f = NSEvent.modifierFlags, sel = Selection.shared
        if f.contains(.command) { sel.basculer(url, colonne); return true }
        if f.contains(.shift), sel.colonne === colonne, sel.ancre != nil { sel.etendre(jusqua: url, dans: liste, colonne); return true }
        sel.choisir(url, colonne)
        return false
    }

    /// La liste affichée où se trouve la sélection : la colonne (en présentation en colonnes) ou toute la vue.
    func listeCourante(_ col: Column) -> [URL] {
        if col.presentation == .colonnes && col.resultats == nil {
            let u = Selection.shared.url
            let niveau = u.flatMap { u in col.niveaux.firstIndex { $0.contains { $0.url == u } } } ?? max(0, col.niveaux.count - 1)
            return col.niveaux.indices.contains(niveau) ? col.niveaux[niveau].map(\.url) : []
        }
        return col.visibles.map(\.url)
    }
    /// Le dossier où coller ou créer : celui qui contient la sélection, sinon celui qui est affiché.
    func dossierCourant(_ col: Column) -> URL? {
        if let u = Selection.shared.url, Selection.shared.colonne === col { return u.deletingLastPathComponent() }
        return col.courant
    }
    /// Les éléments sélectionnés, dans l'ordre affiché.
    var selectionnes: [URL] {
        let sel = Selection.shared
        return sel.dansLOrdre(sel.colonne.map(listeCourante) ?? [])
    }
}
