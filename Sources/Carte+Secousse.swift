// La secousse du pointeur qui ouvre le Finder pendant un glisser.
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
    // MARK: Secouer le pointeur
    func chercherCercle(_ ici: CGPoint) {
        // Le cercle ouvre Side, mais ne le referme pas : carte ouverte, la souris fait trop de mouvements arrondis
        // (aller vers un fichier, tourner autour d'un bouton) pour qu'on puisse les distinguer d'un vrai cercle.
        guard !visible else { trace = []; return }
        let maintenant = ProcessInfo.processInfo.systemUptime
        if let dernier = trace.last {
            guard hypot(ici.x - dernier.p.x, ici.y - dernier.p.y) >= 2 else { return }
            if maintenant - dernier.t > 0.35 { trace = []; attendrePause = false }   // une pause : un nouveau geste commence
        } else if maintenant - dernierMouvement > 0.35 {
            attendrePause = false
        }
        dernierMouvement = maintenant
        trace.append((ici, maintenant))
        trace.removeAll { maintenant - $0.t > 1.8 }
        // Après un cercle reconnu, on attend que la main s'arrête (ou 1,5 s au plus) : la fin du même geste
        // ne doit pas être prise pour un nouveau cercle qui refermerait aussitôt Side.
        if attendrePause && maintenant - derniereSecousse < 1.5 { return }
        attendrePause = false
        // Le cercle n'a pas besoin d'être fermé. Plus c'est sensible, moins il en faut :
        // de 270° mesurés (environ 8 dixièmes de tour) à 210° (environ les deux tiers).
        let degres = 270 - 60 * CGFloat(config.sensibilite)
        for duree in [0.45, 0.7, 1.0, 1.4, 1.8] {
            let morceau = trace.filter { maintenant - $0.t <= duree }.map(\.p)
            guard morceau.count >= 10, Geste.boucle(morceau, degres: degres) else { continue }
            derniereSecousse = maintenant
            trace = []
            attendrePause = true
            basculer()
            return
        }
    }
    func secousse() {
        // Secouer ouvre la carte, et la referme si elle est ouverte. Pendant un glisser-déposer, le geste sert
        // aux zones de dépôt : il marche alors même si le geste de souris est désactivé dans les réglages.
        guard config.secouer || glisserActif, prise == nil else { return }
        // Le cercle remplace la secousse — sauf pendant un glisser-déposer, où secouer ajoute une zone.
        if config.cercle, !glisserActif {
            // Pas de délai de sécurité pour le cercle : un geste aussi net ne se fait pas par erreur.
            chercherCercle(NSEvent.mouseLocation)
            return
        }
        // Garde-fous : aller vite vers le coin actif ressemble à une secousse. On l'ignore donc près du coin,
        // et pendant un instant après chaque ouverture ou fermeture.
        let ici = NSEvent.mouseLocation
        // Délai raccourci (0,6 s au lieu de 1,2 s) : assez pour ne pas confondre l'élan vers le coin avec une secousse.
        if ProcessInfo.processInfo.systemUptime - dernierBasculement < 0.6
            || (ecranSous(ici).map { dansCoin(ici, $0, marge: 160) } ?? false) {
            demiTours = []
            dernierX = ici.x
            return
        }
        let x = NSEvent.mouseLocation.x
        let dx = x - dernierX
        dernierX = x
        guard abs(dx) > 0.5 else { return }
        let maintenant = ProcessInfo.processInfo.systemUptime
        if (dx > 0) == versDroite {
            parcours += abs(dx)
        } else {
            // Plus c'est sensible, plus les allers-retours peuvent être courts et peu nombreux.
            if parcours >= 110 - 80 * CGFloat(config.sensibilite) { demiTours.append(maintenant) }
            versDroite = dx > 0
            parcours = abs(dx)
        }
        demiTours.removeAll { maintenant - $0 > 0.6 }
        let voulus = config.sensibilite > 0.66 ? 3 : (config.sensibilite > 0.33 ? 4 : 5)
        if demiTours.count >= voulus, maintenant - derniereSecousse > 0.8 {
            derniereSecousse = maintenant
            demiTours = []
            // Pendant un glisser-déposer, carte ouverte : secouer ajoute une zone de dépôt en dessous.
            // (Une seule zone vide à la fois : secouer encore n'en ajoute pas d'autres.)
            if glisserActif && (visible || zoneSecouee) {
                if !store.etageres.contains(where: { $0.items.isEmpty }) { store.ajouterZone() }
            }
            // Side fermé, un fichier sous la souris : la zone de dépôt apparaît seule, près du pointeur (façon Dropover).
            else if glisserActif && appGlissee == nil && glisseContientFichier() { ouvrirZoneSecouee() }
            else if config.secouer { basculer() }
        }
    }

    func ouvrirZoneSecouee() {
        journal("déclencheur : secousse pendant un glisser, zone de dépôt seule")
        // Pas encore à l'écran : elle arrive à côté du pointeur. Déjà là (elle contient des fichiers) : elle ne bouge pas.
        if depotPanel?.isVisible != true {
            let ici = NSEvent.mouseLocation
            ancrePerso = NSPoint(x: ici.x + 24, y: ici.y + (zonesVersHaut ? -1 : 1) * Reglages.hauteurDepot / 2)
        }
        zoneSecouee = true
        // Les zones déjà là sont toutes remplies : la secousse en crée une nouvelle, vide.
        if !store.etageres.contains(where: { $0.items.isEmpty }) { store.ajouterZone() }
        // Ce qu'on y pose reste à l'écran un moment, même cadenas ouvert (comme pour une capture).
        captureJusqua = ProcessInfo.processInfo.systemUptime + 60
    }
}
