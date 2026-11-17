// La surveillance de la souris : coins actifs, fermeture quand elle sort.
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
    // MARK: Surveillance de la souris
    func dansCoin(_ p: NSPoint, _ e: NSScreen, marge: CGFloat = 0) -> Bool {
        let t = CGFloat(config.tailleCoin) + marge, f = e.frame
        let gauche = p.x <= f.minX + t, droite = p.x >= f.maxX - t
        let haut = p.y >= f.maxY - t, bas = p.y <= f.minY + t
        switch config.coin {
        case .aucun: return false
        case .hautGauche: return haut && gauche
        case .hautDroite: return haut && droite
        case .basGauche: return bas && gauche
        case .basDroite: return bas && droite
        }
    }

    func tick() {
        // Tant qu'un fichier affiché se télécharge ou s'envoie, on rafraîchit de temps en temps pour suivre son état.
        battement += 1
        if visible, battement % 50 == 0,
           (store.columns + store.onglets).contains(where: { c in
               (c.visibles + c.niveaux.flatMap { $0 }).contains { $0.nuage == .telechargement || $0.nuage == .envoi } }) {
            store.reloadAll()
        }
        // L'aperçu a été refermé de lui-même (Espace, Échap, sa croix) : on rend la main à l'app d'avant.
        if apercuOuvert, !(QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible) { apresApercu() }
        // Un glisser-déposer est-il en cours ? Le presse-papiers du glisser change au début de chaque glisser.
        if NSEvent.pressedMouseButtons & 1 != 0 {
            let compte = NSPasteboard(name: .drag).changeCount
            if compte != dernierGlisser {
                dernierGlisser = compte; glisserActif = true
                // Des zones vides restées d'avant (vidées entre-temps) : on les retire, une seule zone vide apparaît.
                // Les autres naîtront de la secousse.
                store.nettoyerZones()
                // Pendant un glisser, macOS ne nous transmet pas toujours les mouvements de la souris (selon l'application
                // d'où part le fichier, ou si c'est un dossier) : la secousse se lisait une fois sur deux. On suit donc
                // le pointeur nous-mêmes, soixante fois par seconde, tant que le glisser dure.
                if suiviSecousse == nil {
                    let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.secousse() }
                    RunLoop.main.add(t, forMode: .common)
                    suiviSecousse = t
                }
                journal("glisser détecté | visible=\(visible) appGlissee=\(appGlissee != nil) types=\(NSPasteboard(name: .drag).types?.map(\.rawValue).prefix(4) ?? [])")
            }
        } else if glisserActif {
            glisserActif = false
            zoneSecouee = false
            suiviSecousse?.invalidate(); suiviSecousse = nil
            // Une icône du mini-Dock lâchée pendant que la croix est affichée : on la retire, comme dans le Dock.
            // Lâchée ailleurs (ou ramenée dans le mini-Dock) : elle reprend sa place.
            // Une app venue d'ailleurs, lâchée : on laisse au mini-Dock un instant pour la recevoir.
            // S'il ne l'a pas reçue (lâchée à côté), sa place provisoire disparaît.
            if apercuApp != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self else { return }
                    withAnimation(Mouvement.glissement) { self.annulerApercuApp() }
                }
            }
            if let icone = appGlissee {
                appGlissee = nil
                let retirer = croix?.isVisible == true
                croix?.orderOut(nil)
                sortieDuDock = nil
                if retirer { icone.retirer() }
                store.appEnGlisse = nil
                store.appHorsDock = false
            }
            // Le glisser est fini : on retire les zones restées vides (il en reste toujours une).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.store.nettoyerZones() }
        }
        if appGlissee != nil, glisserActif { suivreIconeGlissee() }
        // Une app en cours de dépôt qui ressort du mini-Dock : sa place provisoire se referme.
        if apercuApp != nil, glisserActif, !dans(vueDock, NSEvent.mouseLocation, marge: 14) {
            withAnimation(Mouvement.glissement) { annulerApercuApp() }
        }
        // Zone montrée pour une capture : la souris dessus (ou un glisser en cours) la garde, sinon elle part après une minute.
        if captureJusqua > 0 {
            let maintenant = ProcessInfo.processInfo.systemUptime
            if glisserActif || depotPanel?.frame.contains(NSEvent.mouseLocation) == true {
                captureJusqua = max(captureJusqua, maintenant + 5)
            } else if maintenant >= captureJusqua {
                captureJusqua = 0
                majDepot()
            }
        }
        if pointeurBord, priseBord == nil, let b = bordSous(NSEvent.mouseLocation) { curseurBord(b.x, b.y).set() }
        // Side fermé mais une zone de dépôt restée à l'écran : glisser un fichier la réveille aussi.
        let zoneSeule = !visible && depotPanel?.isVisible == true && glisserActif && glisseContientFichier()
        let montrer = (glisserActif && visible && appGlissee == nil) || zoneSeule || (zoneSecouee && glisserActif) || forcerGlisse || (visible && store.accueil == 3)
            || ProcessInfo.processInfo.systemUptime - depotEnCours < 1.5
        // (Une nouvelle zone vide n'apparaît plus toute seule au début d'un glisser : seulement en secouant ce qu'on tient.
        // Sans secousse, on peut toujours poser dans une zone déjà là.)
        if montrer != store.glisse {
            journal("zones : \(montrer ? "montrer" : "cacher") | glisser=\(glisserActif) visible=\(visible) appGlissee=\(appGlissee != nil) zones=\(store.etageres.count) panneau=\(depotPanel?.frame ?? .zero)")
            store.glisse = montrer
        }
        // La cible « épingler en colonne » ne sert que pour un dossier : on regarde ce qui est glissé.
        let dossier = montrer && (forcerGlisse || glisseContientDossier())
        if dossier != store.glisseDossier { store.glisseDossier = dossier }

        // Filet de sécurité : si la carte est restée sur un autre bureau (changement d'app en plein écran
        // que macOS n'a pas signalé), Side la considère comme fermée. Sinon il faudrait aller deux fois
        // dans le coin : une fois pour « fermer » la carte invisible, une fois pour l'ouvrir.
        if visible && !panel.isOnActiveSpace && !doitSuivre() {
            horsBureau += 1
            if horsBureau > 8 {
                horsBureau = 0
                journal("carte restée sur un autre bureau : considérée comme fermée")
                fermerApercu()
                hide(immediat: true)
                arme = true
                dernierBasculement = 0
            }
        } else {
            horsBureau = 0
        }

        let p = NSEvent.mouseLocation
        guard let e = ecranSous(p) else { return }
        // Version personnelle : le tiroir du bas a son propre coin actif (voir PanneauBas.swift).
        PanneauBas.commun.surveillerCoin(p, e, taille: CGFloat(config.tailleCoin))
        VoletPresse.commun.surveillerCoin(p, e, taille: CGFloat(config.tailleCoin))      // le volet du presse-papiers, à droite
        ConfigSquare.commun.surveillerCoin(p, e, taille: CGFloat(config.tailleCoin))     // la grille de Square, s'il est installé
        VoletVue.commun.surveillerCoin(p, e, taille: CGFloat(config.tailleCoin))         // le volet d'une vue d'Horizon
        let coin = dansCoin(p, e)

        if !visible {
            if !coin { arme = true; debutCoin = nil; return }
            // (marche aussi pendant qu'on glisse un fichier) — et pas juste après une fermeture
            guard arme, ProcessInfo.processInfo.systemUptime - dernierBasculement > 0.6 else { return }
            if debutCoin == nil { debutCoin = Date() }
            if Date().timeIntervalSince(debutCoin!) >= Reglages.delaiOuverture {
                debutCoin = nil
                epingle = true
                journal("déclencheur : coin actif, souris en \(Int(p.x)),\(Int(p.y))")
                show(sur: e)
            }
            return
        }

        let suivre = doitSuivre()
        if suivre != suitBureaux { suivreBureaux(suivre) }

        // Revenir dans le coin referme la carte.
        // La souris doit s'être vraiment éloignée du coin (140 points) avant qu'y revenir ne referme :
        // un petit mouvement autour du coin, juste après l'ouverture, ne compte pas.
        if !dansCoin(p, e, marge: 140) { aQuitteCoin = true }
        else if coin && aQuitteCoin && NSEvent.pressedMouseButtons == 0 && !modeTest
                    && ProcessInfo.processInfo.systemUptime - dernierBasculement > 0.5 { hide(); return }

        // Par défaut la carte reste ouverte. Avec le réglage « Fermer quand la souris en sort »,
        // il se referme une fois que la souris y est entrée puis ressortie.
        guard config.fermerEnSortant else { debutDehors = nil; return }
        // Pendant un aperçu (Espace) ou une fenêtre de question (renommer, erreur), la carte reste.
        if apercuOuvert || NSApp.modalWindow != nil { debutDehors = nil; return }
        // La zone de dépôt, à côté du Finder, en fait partie : y aller ne compte pas comme une sortie.
        let surLaZone = (cadreDepot?.insetBy(dx: -24, dy: -24).contains(p) ?? false)
        if cadreCarte.insetBy(dx: -24, dy: -24).contains(p) || surLaZone || (config.presseDehors > 0 && surSide(p)) {
            debutDehors = nil
            if epingle && !modeTest { epingle = false }
            return
        }
        if epingle || NSEvent.pressedMouseButtons != 0 { debutDehors = nil; return }
        if debutDehors == nil { debutDehors = Date() }
        if Date().timeIntervalSince(debutDehors!) >= Reglages.delaiFermeture { hide() }
    }
}
