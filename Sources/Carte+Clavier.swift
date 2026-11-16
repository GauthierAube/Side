// Le clavier dans la carte, comme dans le Finder.
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
    // MARK: Clavier, comme dans le Finder
    /// Les raccourcis du Finder : Espace (Coup d'œil), flèches (avec Maj pour étendre), ⌘A, ⌘C, ⌘V, ⌥⌘V, ⌘D, ⌘I,
    /// ⇧⌘N, ⌘⌫, ⌘O et ⌘↓ (ouvrir), ⌘↑ (dossier parent), ⌘[ et ⌘] (précédent, suivant), ⌘1 à ⌘3 (présentation), ⌘F,
    /// et les dossiers du Finder (⇧⌘H, ⇧⌘D, ⇧⌘O, ⌥⌘L, ⇧⌘A, ⇧⌘U). Entrée : renommer. Renvoie vrai si la touche a servi.
    func touche(_ ev: NSEvent) -> Bool {
        let f = ev.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = f.contains(.command), maj = f.contains(.shift), opt = f.contains(.option)
        let sel = Selection.shared
        let col = sel.colonne ?? store.navigateur
        // Maj + flèches : la sélection s'étend, comme dans le Finder.
        if maj, !cmd, [123, 124, 125, 126].contains(ev.keyCode) { fleche(ev.keyCode, etendre: true); return true }
        // La touche est reconnue à sa LETTRE (celle du clavier utilisé : AZERTY, QWERTY…), jamais à son emplacement :
        // sur un clavier français, la touche A est là où un clavier américain a son Q.
        let lettre = (ev.charactersIgnoringModifiers ?? "").lowercased()
        // Les touches sans lettre, et les chiffres (rangée du haut, quel que soit le clavier), par leur emplacement.
        let touche: String = [126: "haut", 125: "bas", 51: "suppr", 18: "1", 19: "2", 20: "3", 21: "4", 33: "[", 30: "]"][Int(ev.keyCode)] ?? lettre
        if cmd && maj {
            switch lettre {
            case "n": nouveauDossier(col)                                            // ⇧⌘N
            case "h": store.naviguer(.folder(Fichiers.home))                          // ⇧⌘H : départ
            case "d": store.naviguer(.folder(Fichiers.home.appendingPathComponent("Desktop")))      // ⇧⌘D : bureau
            case "o": store.naviguer(.folder(Fichiers.documents))                    // ⇧⌘O : documents
            case "a": store.naviguer(.folder(URL(fileURLWithPath: "/Applications")))  // ⇧⌘A : applications
            case "u": store.naviguer(.folder(URL(fileURLWithPath: "/Applications/Utilities")))     // ⇧⌘U : utilitaires
            default: return false
            }
            return true
        }
        if cmd && opt {
            switch lettre {
            case "l": store.naviguer(.folder(Fichiers.downloads))                    // ⌥⌘L : téléchargements
            case "v": coller(col, deplacer: true)                                     // ⌥⌘V : déplacer ici
            default: return false
            }
            return true
        }
        if cmd {
            switch touche {
            case "a":                                                               // ⌘A
                sel.toutChoisir(listeCourante(col), col)
                journal("tout sélectionner : \(sel.nombre) élément(s)")
            case "c":                                                             // ⌘C
                let l = selectionnes
                guard !l.isEmpty else { return false }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects(l.map { $0 as NSURL })
            case "v": coller(col, deplacer: false)                                    // ⌘V
            case "d":                                                             // ⌘D : dupliquer
                let l = selectionnes
                guard !l.isEmpty else { return false }
                for u in l { cible = u; mDupliquer() }
            case "i":                                                              // ⌘I : lire les informations
                guard let u = sel.url else { return false }
                cible = u; mInfos()
            case "f": DispatchQueue.main.async { self.store.demandeRecherche += 1 }   // ⌘F
            case "haut":                                                             // ⌘↑ : dossier parent
                if col.presentation == .colonnes, !col.pile.isEmpty {
                    let parent = col.pile.last!
                    col.tronquer(col.pile.count - 1)
                    sel.choisir(parent, col)
                } else if col.peutRevenir { col.revenir() }
            case "[": if col.peutRevenir { col.revenir() }                          // ⌘[
            case "]": if col.peutAvancer { col.avancer() }                          // ⌘]
            case "1": col.presentation = .icones                                     // ⌘1
            case "2": col.presentation = .liste                                      // ⌘2
            case "3": col.presentation = .colonnes                                   // ⌘3
            case "4": col.presentation = .arbre                                      // ⌘4 : arborescence
            case "bas", "o":                                                           // ⌘↓, ⌘O : ouvrir
                let l = selectionnes
                guard let u = sel.url else { return false }
                if l.count == 1, let it = sel.colonne?.items.first(where: { $0.url == u }), it.isFolder { sel.colonne?.entrer(u) }
                else { hide(); l.forEach { NSWorkspace.shared.open($0, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil) } }
            case "t": store.nouvelOnglet()                                           // ⌘T
            case "w":                                                              // ⌘W
                if store.onglets.count > 1 { store.fermerOnglet(store.ongletActif) } else { hide() }
            case "suppr":                                                             // ⌘⌫ : corbeille
                let l = selectionnes
                guard !l.isEmpty else { return false }
                if l.count == 1 { cible = l[0]; sel.url = nil; mCorbeille() } else { mettreALaCorbeille(l) }
            default: return false
            }
            return true
        }
        switch ev.keyCode {
        case 49:
            guard let u = sel.url ?? survoleAffiche?.url else { return false }
            coupDOeil(u)
        case 123, 124, 125, 126: fleche(ev.keyCode)
        case 36, 76:
            guard let u = sel.url else { return false }
            cible = u
            mRenommer()
        default: return false
        }
        return true
    }

    /// Plusieurs éléments à la corbeille d'un coup ; la sélection passe à l'élément qui suivait le dernier.
    func mettreALaCorbeille(_ l: [URL]) {
        let sel = Selection.shared, col = sel.colonne
        let liste = col.map(listeCourante) ?? []
        let apres = liste.lastIndex { l.contains($0) }.flatMap { i in liste.dropFirst(i + 1).first { !l.contains($0) } }
            ?? liste.last { !l.contains($0) }
        var echecs: [String] = []
        for u in l { do { try FileManager.default.trashItem(at: u, resultingItemURL: nil) } catch { echecs.append(u.lastPathComponent) } }
        store.reloadAll()
        sel.choisir(apres, col)
        if !echecs.isEmpty {
            erreur(String(localized: "Impossible de placer certains éléments dans la corbeille"),
                   NSError(domain: "Side", code: 2, userInfo: [NSLocalizedDescriptionKey: echecs.joined(separator: ", ")]))
        }
    }

    /// ⌘V : les fichiers copiés arrivent dans le dossier courant (copiés, ou déplacés avec ⌥⌘V). Un nom déjà pris devient « nom 2 ».
    func coller(_ col: Column, deplacer: Bool) {
        guard let dossier = dossierCourant(col),
              let fichiers = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !fichiers.isEmpty else { NSSound.beep(); return }
        // Les noms d'arrivée sont choisis ici ; la copie elle-même se fait en arrière-plan, pour ne pas figer Side
        // (ni retenir les clics de tout le Mac) pendant un gros collage.
        var travail: [(de: URL, vers: URL)] = [], echecsAvant: [String] = []
        let la = dossier.resolvingSymlinksInPath().path
        for f in fichiers {
            var dest = dossier.appendingPathComponent(f.lastPathComponent)
            if dest.standardizedFileURL == f.standardizedFileURL && deplacer { continue }
            // Un dossier ne se colle pas dans lui-même (ni dans un de ses sous-dossiers).
            if (la + "/").hasPrefix(f.resolvingSymlinksInPath().path + "/") { echecsAvant.append(f.lastPathComponent); continue }
            if FileManager.default.fileExists(atPath: dest.path) || travail.contains(where: { $0.vers == dest }) {
                dest = nomLibre(dest, suffixe: deplacer ? "" : " " + String(localized: "copie"))
            }
            travail.append((f, dest))
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var arrives: [URL] = [], echecs = echecsAvant
            for (f, dest) in travail {
                do {
                    if deplacer { try FileManager.default.moveItem(at: f, to: dest) } else { try FileManager.default.copyItem(at: f, to: dest) }
                    arrives.append(dest)
                } catch { echecs.append(f.lastPathComponent) }
            }
            DispatchQueue.main.async {
                self.store.reloadAll()
                // Les éléments collés sont sélectionnés, comme dans le Finder.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard let premier = arrives.first else { return }
                    Selection.shared.choisir(premier, col)
                    if arrives.count > 1 { Selection.shared.toutChoisir(arrives, col) }
                }
                if !echecs.isEmpty {
                    self.erreur(String(localized: "Impossible de coller certains éléments"),
                                NSError(domain: "Side", code: 3, userInfo: [NSLocalizedDescriptionKey: echecs.joined(separator: ", ")]))
                }
            }
        }
    }

    /// ⇧⌘N : un nouveau dossier dans le dossier courant, aussitôt prêt à être renommé.
    func nouveauDossier(_ col: Column) {
        guard let dossier = dossierCourant(col) else { NSSound.beep(); return }
        let nouveau = nomLibre(dossier.appendingPathComponent(String(localized: "dossier sans titre")), suffixe: "", ext: "")
        do { try FileManager.default.createDirectory(at: nouveau, withIntermediateDirectories: false) }
        catch { erreur(String(localized: "Impossible de créer le dossier"), error); return }
        store.reloadAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            Selection.shared.choisir(nouveau, col)
            self.cible = nouveau
            self.mRenommer()
        }
    }

    /// Les flèches, comme dans le Finder :
    /// - en icônes, gauche et droite passent à l'élément voisin, haut et bas à la ligne du dessus ou du dessous ;
    /// - en liste, haut et bas passent à l'élément voisin ;
    /// - en colonnes, gauche remonte au dossier parent, droite entre dans le dossier choisi.
    func fleche(_ touche: UInt16, etendre: Bool = false) {
        etendreFleche = etendre
        defer { etendreFleche = false }
        let sel = Selection.shared
        journal("flèche \(touche) — sélection avant : \(sel.url?.lastPathComponent ?? "rien"), survol : \(survole?.url.lastPathComponent ?? "rien")")
        defer { journal("   après : \(Selection.shared.url?.lastPathComponent ?? "rien"), \(Selection.shared.nombre) sélectionné(s) (icônes par ligne : \(Selection.shared.colonne?.colonnesVisibles ?? -1))") }
        // Rien de sélectionné, mais la souris est posée sur un élément (il est grisé) : c'est de lui qu'on part,
        // dans SA colonne. Sans cela, les flèches agissaient sur la grande zone, à l'autre bout de la carte.
        if sel.url == nil, let dessous = survoleAffiche, let c = survoleColonne { sel.choisir(dessous.url, c) }
        let col = sel.colonne ?? store.navigateur
        let gauche = touche == 123, droite = touche == 124, bas = touche == 125, haut = touche == 126
        if col.presentation == .colonnes && col.resultats == nil {
            // La colonne (de la présentation en colonnes) où se trouve la sélection.
            let niveau = sel.url.flatMap { u in col.niveaux.firstIndex { $0.contains { $0.url == u } } } ?? 0
            guard col.niveaux.indices.contains(niveau) else { return }
            let liste = col.niveaux[niveau]
            if gauche {
                guard niveau > 0, niveau - 1 < col.pile.count else { return }
                let parent = col.pile[niveau - 1]
                col.tronquer(niveau)
                choisirEtSuivre(parent, col)
            } else if droite {
                guard let u = sel.url, let it = liste.first(where: { $0.url == u }), it.isFolder else { return }
                col.ouvrirNiveau(u, niveau)
                // Le contenu arrive un instant plus tard : on choisit alors son premier élément.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if col.niveaux.indices.contains(niveau + 1), let premier = col.niveaux[niveau + 1].first {
                        self.choisirEtSuivre(premier.url, col)
                    }
                }
            } else {
                deplacer(dans: liste.map(\.url), pas: bas ? 1 : -1, col)
            }
            return
        }
        let liste = col.visibles.map(\.url)
        if col.presentation == .icones {
            let n = max(1, col.colonnesVisibles)
            // Gauche et droite restent sur la ligne : au bord, on ne passe pas à la ligne suivante.
            if let i = Selection.shared.url.flatMap({ liste.firstIndex(of: $0) }) {
                if gauche && i % n == 0 { return }
                if droite && (i % n == n - 1 || i + 1 >= liste.count) { return }
            }
            deplacer(dans: liste, pas: gauche ? -1 : (droite ? 1 : (bas ? n : -n)), col)
        } else if bas || haut {
            deplacer(dans: liste, pas: bas ? 1 : -1, col)
        }
    }

    /// Avance de `pas` éléments dans la liste ; sans sélection, prend le premier. On ne sort pas de la liste.
    /// Avec Maj, la sélection s'étend de l'ancre jusque-là.
    func deplacer(dans liste: [URL], pas: Int, _ col: Column) {
        guard !liste.isEmpty else { return }
        guard let i = Selection.shared.url.flatMap({ liste.firstIndex(of: $0) }) else { choisirEtSuivre(liste[0], col); return }
        let j = i + pas
        guard liste.indices.contains(j) else { return }
        if etendreFleche {
            Selection.shared.etendre(jusqua: liste[j], dans: liste, col)
            return
        }
        choisirEtSuivre(liste[j], col)
    }

    func choisirEtSuivre(_ url: URL, _ col: Column) {
        Selection.shared.choisir(url, col)
        if QLPreviewPanel.sharedPreviewPanelExists(), let ql = QLPreviewPanel.shared(), ql.isVisible,
           let i = apercus.firstIndex(of: url) {   // l'aperçu suit la sélection
            apercu = url
            ql.currentPreviewItemIndex = i
        }
    }

    /// Ancien nom, encore utilisé par l'aperçu : flèches haut et bas.
    func deplacerSelection(_ pas: Int) { fleche(pas > 0 ? 125 : 126) }
}
