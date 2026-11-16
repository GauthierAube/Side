// Le menu du clic droit et le coup d'œil (barre d'espace).
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
    // MARK: Menu contextuel (clic droit), calqué sur celui du Finder
    var auDessus: NSWindow.Level { Devant.niveau }

    func menuContextuel(_ item: FileItem, event: NSEvent) {
        let url = item.url
        cible = url
        if !Selection.shared.contient(url) { Selection.shared.choisir(url, survoleColonne) }
        let m = NSMenu()
        @discardableResult
        func ajouter(_ titre: String, _ action: Selector, symbole: String? = nil, dans menu: NSMenu? = nil) -> NSMenuItem {
            let it = (menu ?? m).addItem(withTitle: titre, action: action, keyEquivalent: "")
            it.target = self
            if let symbole { it.image = NSImage(systemSymbolName: symbole, accessibilityDescription: nil) }
            return it
        }

        if survoleColonne?.estEtagere == true {
            ajouter(String(localized: "Retirer de l'étagère"), #selector(mRetirerEtagere))
            m.addItem(.separator())
        }
        ajouter(String(localized: "Ouvrir"), #selector(mOuvrir))
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
        if !item.isFolder, !apps.isEmpty {
            let sous = NSMenu()
            for app in apps.prefix(15) {
                let it = ajouter(FileManager.default.displayName(atPath: app.path), #selector(mOuvrirAvec(_:)), dans: sous)
                let icone = NSWorkspace.shared.icon(forFile: app.path)
                icone.size = NSSize(width: 16, height: 16)
                it.image = icone
                it.representedObject = app
            }
            m.addItem(withTitle: String(localized: "Ouvrir avec"), action: nil, keyEquivalent: "").submenu = sous
        }
        // Imprimer, comme Fichier > Imprimer dans le Finder : le fichier est confié à son application, qui l'imprime.
        if !item.isFolder, !apps.isEmpty {
            let plusieurs = Selection.shared.nombre > 1 && Selection.shared.contient(url)
            ajouter(plusieurs ? String(localized: "Imprimer les \(Selection.shared.nombre) éléments") : String(localized: "Imprimer"),
                    #selector(mImprimer), symbole: "printer")
        }
        let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if v?.isUbiquitousItem == true {
            if v?.ubiquitousItemDownloadingStatus == .current {
                ajouter(String(localized: "Supprimer le téléchargement"), #selector(mLiberer))
            } else {
                ajouter(String(localized: "Télécharger"), #selector(mTelecharger))
            }
        }
        m.addItem(.separator())
        if Selection.shared.nombre > 1, Selection.shared.contient(url) {
            ajouter(String(localized: "Placer les \(Selection.shared.nombre) éléments dans la corbeille"), #selector(mCorbeilleTous), symbole: "trash")
        } else {
            ajouter(String(localized: "Placer dans la corbeille"), #selector(mCorbeille), symbole: "trash")
        }
        m.addItem(.separator())
        ajouter(String(localized: "Lire les informations"), #selector(mInfos))
        ajouter(String(localized: "Renommer"), #selector(mRenommer))
        ajouter(String(localized: "Compresser « \(url.lastPathComponent) »"), #selector(mCompresser))
        ajouter(String(localized: "Dupliquer"), #selector(mDupliquer))
        ajouter(String(localized: "Créer un alias"), #selector(mAlias))
        ajouter(String(localized: "Coup d'œil"), #selector(mCoupDOeil))
        ajouter(String(localized: "Copier"), #selector(mCopier))
        // Comme dans le Finder : avec la touche Option, « Copier » devient « Copier le chemin ».
        let chemin = ajouter(String(localized: "Copier « \(url.lastPathComponent) » en tant que chemin d'accès"), #selector(mCopierChemin))
        chemin.isAlternate = true
        chemin.keyEquivalentModifierMask = [.option]
        m.addItem(.separator())
        ajouter(String(localized: "Partager…"), #selector(mPartager), symbole: "square.and.arrow.up")
        m.addItem(.separator())

        let tags = NSMenu()
        let actuels = tagsDe(url)
        let noms = NSWorkspace.shared.fileLabels, couleurs = NSWorkspace.shared.fileLabelColors
        for i in noms.indices.dropFirst() where i < couleurs.count {
            let it = ajouter(noms[i], #selector(mTag(_:)), dans: tags)
            it.representedObject = noms[i]
            it.state = actuels.contains(noms[i]) ? .on : .off
            let c = couleurs[i]
            it.image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
                c.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                return true
            }
        }
        let itTags = m.addItem(withTitle: String(localized: "Tags"), action: nil, keyEquivalent: "")
        itTags.image = NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
        itTags.submenu = tags
        m.addItem(.separator())
        ajouter(String(localized: "Afficher dans le Finder"), #selector(mReveler))
        if item.isFolder {
            ajouter(String(localized: "Épingler en colonne"), #selector(mEpingler))
            ajouter(String(localized: "Ajouter aux favoris"), #selector(mFavori))
        }

        NSMenu.popUpContextMenu(m, with: event, for: host)
    }

    func tagsDe(_ url: URL) -> [String] {
        var valeur: AnyObject?
        try? (url as NSURL).getResourceValue(&valeur, forKey: .tagNamesKey)
        return valeur as? [String] ?? []
    }

    func erreur(_ texte: String, _ e: Error) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = texte
        a.informativeText = e.localizedDescription
        epingle = true
        Devant.alerte(a)
    }

    /// Fait une action sur le fichier visé, affiche l'erreur éventuelle, puis rafraîchit les colonnes.
    /// `quoi` donne le titre de l'erreur à partir du nom du fichier.
    func agir(_ quoi: (String) -> String, _ action: (URL) throws -> Void) {
        guard let url = cible else { return }
        do { try action(url) } catch { erreur(quoi(url.lastPathComponent), error) }
        store.reloadAll()
    }

    /// Un nom libre dans le même dossier : « nom suffixe.ext », puis « nom suffixe 2.ext »…
    func nomLibre(_ url: URL, suffixe: String, ext: String? = nil) -> URL {
        let dossier = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent + suffixe
        let e = ext ?? url.pathExtension
        var n = 1
        while true {
            let nom = (n == 1 ? base : "\(base) \(n)") + (e.isEmpty ? "" : "." + e)
            let candidat = dossier.appendingPathComponent(nom)
            if !FileManager.default.fileExists(atPath: candidat.path) { return candidat }
            n += 1
        }
    }

    @objc func mEpingler() { if let u = cible { store.ajouter(.folder(u.standardizedFileURL)) } }
    @objc func mFavori() { if let u = cible { store.ajouterFavori(u) } }
    @objc func mRetirerEtagere() {
        if let u = cible { Etagere.retirer(u, survoleColonne?.indexEtagere ?? 0); store.reloadAll() }
    }
    @objc func mOuvrir() { if let u = cible { ouvrir(u) } }
    @objc func mReveler() { if let u = cible { reveler(u) } }
    @objc func mCoupDOeil() { if let u = cible { coupDOeil(u) } }
    /// Imprimer : chaque fichier (la sélection, si l'élément visé en fait partie) est ouvert par son application « pour
    /// impression ». C'est le mécanisme de macOS, celui de Fichier > Imprimer dans le Finder.
    @objc func mImprimer() {
        guard let u = cible else { return }
        let sel = Selection.shared
        let urls = (sel.nombre > 1 && sel.contient(u) ? Array(sel.urls) : [u]).filter { !Fichiers.item($0).isFolder }
        guard !urls.isEmpty else { return }
        let c = NSWorkspace.OpenConfiguration()
        c.isForPrinting = true
        hide()
        for url in urls {
            NSWorkspace.shared.open(url, configuration: c) { _, erreur in
                if erreur != nil { DispatchQueue.main.async { NSSound.beep() } }
            }
        }
    }

    @objc func mOuvrirAvec(_ sender: NSMenuItem) {
        guard let u = cible, let app = sender.representedObject as? URL else { return }
        hide()
        NSWorkspace.shared.open([u], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    @objc func mTelecharger() {
        agir({ String(localized: "Impossible de télécharger « \($0) »") }) { try FileManager.default.startDownloadingUbiquitousItem(at: $0) }
    }
    @objc func mLiberer() {
        agir({ String(localized: "Impossible de libérer « \($0) »") }) { try FileManager.default.evictUbiquitousItem(at: $0) }
    }
    @objc func mCorbeille() {
        guard let url = cible else { return }
        // Comme dans le Finder : après la suppression, la sélection passe à l'élément suivant,
        // ou au précédent si c'était le dernier, ou au dossier qui le contenait s'il ne reste rien.
        func contient(_ c: Column) -> Bool {
            c.visibles.contains { $0.url == url } || c.niveaux.contains { $0.contains { $0.url == url } }
        }
        let partout: [Column?] = [Selection.shared.colonne, survoleColonne, store.navigateur]
            + store.columns.map { $0 } + store.etageres.map { $0 }
        let colonne = partout.compactMap { $0 }.first(where: contient)
        var liste: [URL] = [], niveau: Int?
        if let colonne {
            if colonne.presentation == .colonnes, let n = colonne.niveaux.firstIndex(where: { $0.contains { $0.url == url } }) {
                niveau = n
                liste = colonne.niveaux[n].map(\.url)
            } else {
                liste = colonne.visibles.map(\.url)
            }
        }
        let rang = liste.firstIndex(of: url)
        agir({ String(localized: "Impossible de placer « \($0) » dans la corbeille") }) { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
        guard let colonne, let rang, !FileManager.default.fileExists(atPath: url.path) else { return }
        // Un dossier supprimé qui était ouvert en colonnes : ses colonnes à droite se referment.
        if let n = niveau, n < colonne.pile.count, colonne.pile[n] == url { colonne.tronquer(n) }
        let restants = liste.filter { $0 != url }
        if !restants.isEmpty {
            Selection.shared.choisir(restants[min(rang, restants.count - 1)], colonne)
        } else if let n = niveau, n > 0, n - 1 < colonne.pile.count {
            Selection.shared.choisir(colonne.pile[n - 1], colonne)
        } else {
            Selection.shared.choisir(nil, nil)
        }
    }
    @objc func mDupliquer() {
        // En arrière-plan : dupliquer un gros dossier figeait Side (et les clics de tout le Mac) le temps de la copie.
        guard let url = cible else { return }
        let dest = nomLibre(url, suffixe: " " + String(localized: "copie"))
        DispatchQueue.global(qos: .userInitiated).async {
            var echec: Error?
            do { try FileManager.default.copyItem(at: url, to: dest) } catch { echec = error }
            DispatchQueue.main.async {
                if let echec { self.erreur(String(localized: "Impossible de dupliquer « \(url.lastPathComponent) »"), echec) }
                self.store.reloadAll()
            }
        }
    }
    @objc func mAlias() {
        agir({ String(localized: "Impossible de créer un alias de « \($0) »") }) {
            let data = try $0.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
            try URL.writeBookmarkData(data, to: self.nomLibre($0, suffixe: " alias", ext: ""))
        }
    }
    @objc func mCopierChemin() {
        guard let u = cible else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(u.path, forType: .string)
    }
    @objc func mCopier() {
        guard let u = cible else { return }
        // Plusieurs éléments sélectionnés, dont celui-ci : ils sont tous copiés.
        let l = Selection.shared.contient(u) && Selection.shared.nombre > 1 ? selectionnes : [u]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(l.map { $0 as NSURL })
    }
    @objc func mCorbeilleTous() { mettreALaCorbeille(selectionnes) }
    @objc func mTag(_ sender: NSMenuItem) {
        guard let nom = sender.representedObject as? String else { return }
        agir({ String(localized: "Impossible de modifier les tags de « \($0) »") }) {
            var tags = self.tagsDe($0)
            if let i = tags.firstIndex(of: nom) { tags.remove(at: i) } else { tags.append(nom) }
            try ($0 as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
        }
    }
    @objc func mCompresser() {
        guard let u = cible else { return }
        let zip = nomLibre(u, suffixe: "", ext: "zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", u.path, zip.path]
        p.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.store.reloadAll() } }
        do { try p.run() } catch { erreur(String(localized: "Impossible de compresser « \(u.lastPathComponent) »"), error) }
    }
    /// Renommer, comme dans le Finder : le nom devient modifiable sur place, surligné en bleu (sans son extension).
    /// Entrée valide, Échap annule, un clic ailleurs valide. (Avant le 16/11/2026 : une fenêtre de question, qui passait
    /// derrière la carte.)
    @objc func mRenommer() {
        guard let u = cible else { return }
        epingle = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        Renommage.shared.url = u
    }
    /// Le nom tapé sur place est validé : le fichier change de nom, et reste choisi sous son nouveau nom.
    func renommer(_ u: URL, en nom: String) {
        let nom = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nom.isEmpty, nom != u.lastPathComponent, !nom.contains("/") else { return }
        let nouveau = u.deletingLastPathComponent().appendingPathComponent(nom)
        do { try FileManager.default.moveItem(at: u, to: nouveau) }
        catch { erreur(String(localized: "Impossible de renommer « \(u.lastPathComponent) »"), error); return }
        let col = Selection.shared.colonne
        store.reloadAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Selection.shared.choisir(nouveau, col) }
    }
    @objc func mInfos() {
        guard let u = cible else { return }
        let chemin = u.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Finder\"\nactivate\nopen information window of (POSIX file \"\(chemin)\" as alias)\nend tell"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err {
            erreur(String(localized: "Impossible d'afficher les informations"), NSError(domain: "Side", code: 1, userInfo: [
                NSLocalizedDescriptionKey: (err[NSAppleScript.errorMessage] as? String) ?? String(localized: "Le Finder n'a pas répondu.")]))
        } else { hide() }
    }
    @objc func mPartager() {
        guard let u = cible else { return }
        epingle = true
        let p = host.convert(panel.mouseLocationOutsideOfEventStream, from: nil)
        NSSharingServicePicker(items: [u]).show(
            relativeTo: NSRect(x: p.x, y: p.y, width: 1, height: 1), of: host, preferredEdge: .minY)
    }

    // MARK: Coup d'œil (aussi avec la barre d'espace)
    /// Coup d'œil : le vrai panneau d'aperçu de macOS, celui du Finder (taille adaptée au document,
    /// pages d'un PDF sur le côté, lecteur audio et vidéo, partage).
    /// Il ne charge le contenu que pour l'app active : Side passe donc au premier plan le temps de l'aperçu,
    /// puis rend la main à l'app d'avant.
    func coupDOeil(_ url: URL) {
        guard let ql = QLPreviewPanel.shared() else { return }
        if ql.isVisible { fermerApercu(); return }
        // Les voisins du fichier (même dossier affiché) sont proposés aussi : les flèches passent de l'un à l'autre.
        let col = Selection.shared.colonne ?? store.navigateur
        let voisins = col.visibles.map(\.url)
        apercus = voisins.contains(url) ? voisins : [url]
        apercu = url
        epingle = true
        if let devant = NSWorkspace.shared.frontmostApplication, devant.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            appAvantApercu = devant
        }
        NSApp.activate(ignoringOtherApps: true)
        ql.dataSource = self
        ql.delegate = self
        // L'aperçu doit passer devant la carte et devant une app en plein écran.
        // macOS remet parfois son niveau à zéro en l'affichant : on le règle avant et après.
        let niveau = NSWindow.Level(rawValue: auDessus.rawValue + 1)
        ql.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ql.level = niveau
        ql.reloadData()
        ql.currentPreviewItemIndex = apercus.firstIndex(of: url) ?? 0
        ql.makeKeyAndOrderFront(nil)
        ql.level = niveau
        apercuOuvert = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard ql.isVisible else { return }
            ql.level = niveau
        }
    }
    func fermerApercu() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let ql = QLPreviewPanel.shared(), ql.isVisible else { return }
        ql.orderOut(nil)
        apresApercu()
    }
    /// L'aperçu vient de se fermer : l'app d'avant reprend la main, et la carte le clavier si elle est ouverte.
    func apresApercu() {
        apercuOuvert = false
        if visible, QLPreviewPanel.sharedPreviewPanelExists(), let i = QLPreviewPanel.shared()?.currentPreviewItemIndex,
           apercus.indices.contains(i) {
            Selection.shared.choisir(apercus[i], Selection.shared.colonne)   // la sélection suit le dernier fichier regardé
        }
        appAvantApercu?.activate()
        appAvantApercu = nil
        // L'app d'avant met un instant à reprendre la main, et prend alors le clavier à la carte :
        // on le lui redonne une fois ce passage terminé, sinon les flèches ne répondent plus.
        if visible { panel.makeKey() }
        for delai in [0.05, 0.2, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delai) { [weak self] in
                guard let self, self.visible, !self.apercuOuvert, !self.panel.isKeyWindow else { return }
                self.panel.makeKey()
            }
        }
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { apercus.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard apercus.indices.contains(index) else { return nil }
        let url = apercus[index]
        if url.pathExtension.lowercased() == "svg", let image = imagePourApercu(url) {
            return ElementApercu(url: image, titre: url.lastPathComponent)
        }
        return url as NSURL
    }

    /// macOS affiche un SVG comme une page web, en taille réelle : un grand dessin dépasse et se retrouve coupé.
    /// On en fait donc une image (dans un dossier temporaire), que l'aperçu ajuste à la fenêtre comme une photo.
    func imagePourApercu(_ url: URL) -> URL? {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("Side-apercus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        let cle = "\(abs(url.path.hashValue))-\(Int(date.timeIntervalSince1970))"
        let cible = dossier.appendingPathComponent(cle).appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".png")
        if FileManager.default.fileExists(atPath: cible.path) { return cible }
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else { return nil }
        // Assez de points pour rester net en grand, sans dépasser 3000 de côté.
        let k = min(3000 / max(image.size.width, image.size.height), max(2, 1600 / max(image.size.width, image.size.height)))
        let l = Int(image.size.width * k), h = Int(image.size.height * k)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: l, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let contexte = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = contexte
        image.draw(in: NSRect(x: 0, y: 0, width: l, height: h))
        NSGraphicsContext.restoreGraphicsState()
        try? FileManager.default.createDirectory(at: cible.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: cible)) != nil else { return nil }
        return cible
    }
    /// Aperçu ouvert : les quatre flèches se déplacent dans la grille (ou la liste) exactement comme sans aperçu,
    /// et l'aperçu suit. (Avant, l'aperçu les prenait pour « fichier précédent / suivant » dans l'ordre de la liste.)
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, [123, 124, 125, 126].contains(event.keyCode) else { return false }
        fleche(event.keyCode)
        return true
    }
    /// Tant que l'aperçu est affiché : Espace ou Échap le referme, les flèches changent de fichier.
    func toucheApercu(_ ev: NSEvent) -> Bool {
        guard !SaisieRaccourci.enCours, QLPreviewPanel.sharedPreviewPanelExists(),
              let ql = QLPreviewPanel.shared(), ql.isVisible else { return false }
        switch ev.keyCode {
        case 49, 53: fermerApercu()
        case 123, 124, 125, 126: fleche(ev.keyCode)   // mêmes déplacements qu'aperçu fermé
        default: return false
        }
        return true
    }
}
