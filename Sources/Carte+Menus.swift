// Menu de la barre des menus et raccourci du Finder.
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
    // MARK: Menu de la barre des menus
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: String(localized: "Afficher Side"), action: #selector(afficherEpingle), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Ajouter un dossier…"), action: #selector(choisirDossier), keyEquivalent: "").target = self
        menu.addItem(.separator())
        // Le plein écran (ex-Square).
        menu.addItem(withTitle: String(localized: "Afficher la grille  (\(Raccourci.actuel.nom))"), action: #selector(Appli.basculerGrille),
                     keyEquivalent: "").target = Programme.appli
        menu.addItem(withTitle: String(localized: "Agrandir la fenêtre en cours  (⌃⌥ Entrée)"), action: #selector(Appli.agrandirActive),
                     keyEquivalent: "").target = Programme.appli
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Réglages…"), action: #selector(ouvrirReglages), keyEquivalent: ",").target = self
        // « Revoir la présentation » n'est plus dans ce menu : elle se relance depuis Réglages > Général.
        menu.addItem(.separator())
        let demarrage = menu.addItem(
            withTitle: String(localized: "Ouvrir à l'ouverture de session"), action: #selector(basculerDemarrage), keyEquivalent: "")
        demarrage.target = self
        demarrage.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quitter Side"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func basculerDemarrage() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = String(localized: "Impossible de modifier l'ouverture automatique")
            a.informativeText = error.localizedDescription
            Devant.alerte(a)
        }
    }

    // MARK: Raccourci clavier Commande + @
    /// Cherche la touche qui tape « @ » sur le clavier actuel (elle change selon le clavier).
    func toucheArobase() -> UInt32 {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return 10 }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> UInt32 in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            for code in 0..<UInt16(127) {
                var morte: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var n = 0
                let err = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                         OptionBits(kUCKeyTranslateNoDeadKeysBit), &morte, 4, &n, &chars)
                if err == noErr, n == 1, chars[0] == 64 { return UInt32(code) }
            }
            return 10
        }
    }

    func installerRaccourci() {
        RaccourcisGlobaux.retirer("finder")
        guard config.touche != -1 else { return }
        let touche = config.touche == -2 ? toucheArobase() : UInt32(config.touche)
        let mods = config.touche == -2 ? UInt32(cmdKey) : UInt32(config.mods)
        guard mods != 0 else { return }      // jamais une touche nue : elle serait prise dans tout le Mac
        let accepte = RaccourcisGlobaux.ajouter("finder", touche: touche, modifs: mods) {
            DispatchQueue.main.async { AppDelegate.shared.basculer() }
        }
        if !accepte {
            // Combinaison déjà prise (par le tiroir, la grille, le presse-papiers…) : on le dit au lieu de l'afficher comme active.
            NSSound.beep()
            config.touche = -1; config.mods = 0; config.libelle = String(localized: "Aucun")
        }
    }

    func definirRaccourci(touche: Int, mods: Int, libelle: String) {
        config.touche = touche
        config.mods = mods
        config.libelle = libelle
        installerRaccourci()
    }

    /// Attend la prochaine combinaison de touches tapée dans la fenêtre Réglages.
    func ecouterRaccourci(fin: @escaping () -> Void) {
        SaisieRaccourci.attendre(suspendre: { RaccourcisGlobaux.retirer("finder") },
                                 reprendre: { [weak self] in self?.installerRaccourci() },
                                 choisi: { [weak self] in self?.definirRaccourci(touche: $0, mods: $1, libelle: $2) },
                                 fin: fin)
    }

    /// La carte est-elle ouverte ? (pour le geste à quatre doigts : ouvrir dans un sens, fermer dans l'autre)
    var estOuvert: Bool { visible }

    /// Relance la présentation de bienvenue (une fenêtre à part, qui montre les gestes en images).
    @objc func revoirAccueil() {
        if visible { hide() }
        PresentationSide.montrer()
    }

    /// Referme et oublie la fenêtre des réglages (pour la rouvrir sur un autre volet).
    func annulerToutesLesEcoutes() { SaisieRaccourci.annuler() }

    func fermerReglages() {
        annulerToutesLesEcoutes()
        fenetreReglages?.close()
        fenetreReglages = nil
    }

    @objc func ouvrirReglages() {
        hide()
        if fenetreReglages == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: ReglagesView()))
            w.title = String(localized: "Réglages de Side")
            // Comme les Réglages Système : barre de titre fondue dans le contenu, barre latérale à gauche.
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.setContentSize(NSSize(width: 800, height: 680))   // assez haut pour toute la barre latérale ; elle défile sinon
            w.styleMask.insert(.resizable)
            w.isReleasedWhenClosed = false
            w.center()
            // Réglages fermés pendant la saisie d'un raccourci : la saisie est abandonnée (sinon le raccourci restait
            // coupé, et la prochaine combinaison tapée dans Side devenait un raccourci global).
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                self?.annulerToutesLesEcoutes()
            }
            fenetreReglages = w
        }
        NSApp.activate(ignoringOtherApps: true)
        fenetreReglages?.makeKeyAndOrderFront(nil)
    }

    func ecranSous(_ p: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) })
            ?? NSScreen.screens.first(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(p) })
            ?? NSScreen.main
    }

    func basculer() {
        journal("déclencheur : raccourci, secousse ou test")
        if visible { hide(); return }
        guard let e = ecranSous(NSEvent.mouseLocation) else { return }
        epingle = true
        show(sur: e)
    }
}
