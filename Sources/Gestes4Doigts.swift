// Le geste à quatre doigts sur le trackpad (ouvrir et fermer le Finder).
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Une touche du trackpad, telle que la décrit le module « MultitouchSupport » de macOS.
/// (Ce module n'est pas documenté par Apple ; c'est celui qu'utilisent les outils de gestes comme BetterTouchTool.)
private struct Contact {
    var frame: Int32; var horodatage: Double; var identifiant: Int32; var etat: Int32
    var doigt: Int32; var main: Int32
    var x: Float; var y: Float; var vx: Float; var vy: Float   // position de 0 à 1, et vitesse
    var taille: Float; var zero1: Int32; var angle: Float; var grandAxe: Float; var petitAxe: Float
    var ax: Float; var ay: Float; var avx: Float; var avy: Float
    var zero2: Int32; var zero3: Int32; var densite: Float
}

/// Repère un glissement à quatre doigts vers le haut ou vers le bas, et ouvre ou ferme Side.
enum Doigts {
    static var actif = UserDefaults.standard.object(forKey: "quatreDoigts") as? Bool ?? true   // même valeur de départ que Config.quatreDoigts
    static var sens = UserDefaults.standard.string(forKey: "sensDoigts") ?? "bas"
    private static var demarre = false
    private static var dejaFait = false       // le geste en cours a déjà servi


    /// Nombre de trackpads trouvés (pour le diagnostic) ; -1 si le module de macOS est introuvable.
    @discardableResult
    static func demarrer() -> Int {
        guard !demarre else { return 0 }
        demarre = true
        return Trackpads.ecouter({ _, touches, nombre, _, _ in
            Doigts.recevoir(touches, Int(nombre))
            return 0
        })
    }

    /// Appelé par macOS à chaque instant où des doigts touchent le trackpad (hors du fil principal).
    private static func recevoir(_ touches: UnsafeMutableRawPointer?, _ nombre: Int) {
        var doigts: [(Int32, Float)] = []
        if let touches, nombre > 0 {
            let contacts = touches.bindMemory(to: Contact.self, capacity: nombre)
            for i in 0..<nombre { doigts.append((contacts[i].identifiant, contacts[i].y)) }
        }
        dernierePresence = ProcessInfo.processInfo.systemUptime
        nombreDoigts = doigts.count
        guard actif, !CaptureEcran.enCours else { return }
        // Version personnelle : un glissement qui part à l'horizontale (changement d'application, dans Square) n'est pas pour nous.
        if let touches, nombre > 0 {
            let contacts = touches.bindMemory(to: Contact.self, capacity: nombre)
            if FiltreHorizontalBas.avaler((0..<nombre).map { (contacts[$0].identifiant, contacts[$0].x, contacts[$0].y) }) { return }
        } else if FiltreHorizontalBas.avaler([]) { return }
        // Version personnelle : le panneau du bas passe d'abord (voir PanneauBas.swift).
        if GestePanneauBas.intercepter(doigts, sideOuvert: AppDelegate.shared.estOuvert, sensSide: sens) { return }
        let geste = traiter(doigts)
        if suivre(doigts) { return }
        guard geste != 0 else { return }
        // Le sens choisi ouvre Side, le sens inverse le referme. « Les deux » : chaque geste ouvre ou ferme.
        let ouvrir = sens == "deux" ? nil : (geste > 0) == (sens == "haut")
        DispatchQueue.main.async {
            let side = AppDelegate.shared
            switch ouvrir {
            case nil: side.basculer()
            case true?: if !side.estOuvert { side.basculer() }
            case false?: if side.estOuvert { side.basculer() }
            }
        }
    }

    // MARK: La carte suit les doigts, à l'ouverture comme à la fermeture

    /// Recopié par la carte à chaque ouverture et fermeture (lu ici, hors du fil principal).
    static var carteOuverte = false
    private static var suit = false
    private static var fermeture = false             // le geste en cours referme la carte
    private static var sensSuivi: Float = 0          // 1 : les doigts montent pour ouvrir, -1 : ils descendent
    private static var progression: Float = 0
    private static var vitesse: Float = 0            // en hauteurs de trackpad par seconde, dans le sens d'ouverture
    private static var instant: TimeInterval = 0
    private static let course: Float = 0.3           // trajet des doigts pour amener la carte à sa place

    /// Renvoie vrai quand le geste sert à faire suivre la carte (il ne doit alors rien déclencher d'autre).
    private static func suivre(_ doigts: [(Int32, Float)]) -> Bool {
        let maintenant = ProcessInfo.processInfo.systemUptime
        if suit {
            if doigts.count < 3 {   // doigts levés : on finit le geste selon la distance et l'élan
                suit = false
                let ouvrir = fermeture
                    ? !(progression < 0.6 || vitesse < -0.6 || (progression < 0.85 && vitesse < 0.2))
                    : progression > 0.4 || vitesse > 0.6 || (progression > 0.15 && vitesse > -0.2)
                let elan = CGFloat(vitesse / course)   // en « carte par seconde », dans le sens d'ouverture
                DispatchQueue.main.async { AppDelegate.shared.lacherDoigts(ouvrir: ouvrir, elan: elan) }
                return true
            }
            guard let m = moyenne(doigts) else { return true }
            let p = max(0, (fermeture ? 1 : 0) + m * sensSuivi / course)
            let dt = Float(maintenant - instant)
            if dt > 0.004 { vitesse = vitesse * 0.6 + (p - progression) * course / dt * 0.4; instant = maintenant }
            progression = p
            DispatchQueue.main.async { AppDelegate.shared.suivreDoigts(CGFloat(p)) }
            return true
        }
        // Début du geste : quatre doigts qui partent ensemble. Carte fermée : dans le sens d'ouverture ;
        // carte ouverte : dans le sens inverse (« Les deux » : n'importe quel sens).
        guard doigts.count >= 4, let m = moyenne(doigts), abs(m) > 0.015 else { return false }
        let sensGeste: Float = m > 0 ? 1 : -1
        let sensOuvrir: Float = sens == "deux" ? (carteOuverte ? -sensGeste : sensGeste) : (sens == "haut" ? 1 : -1)
        let ferme = carteOuverte
        if (sensGeste == sensOuvrir) == ferme { return false }
        suit = true
        fermeture = ferme
        dejaFait = true   // le geste est pris en charge : pas de bascule en plus
        sensSuivi = sensOuvrir
        progression = (ferme ? 1 : 0) + m * sensOuvrir / course
        vitesse = 0
        instant = maintenant
        let p = progression
        DispatchQueue.main.async {
            AppDelegate.shared.commencerSuivi(fermeture: ferme)
            AppDelegate.shared.suivreDoigts(CGFloat(p))
        }
        return true
    }

    /// Déplacement moyen des doigts depuis leur départ, s'ils vont tous dans le même sens.
    private static func moyenne(_ doigts: [(Int32, Float)]) -> Float? {
        let ecarts = doigts.compactMap { id, y in departs[id].map { y - $0 } }
        guard ecarts.count >= 4 else { return nil }
        let moyen = ecarts.reduce(0, +) / Float(ecarts.count)
        // Chacun glisse vraiment (20/11/2026) : trois doigts avec le pouce posé ne font pas un geste à quatre doigts.
        guard GestePages.tousGlissent(ecarts, moyenne: moyen) else { return nil }
        return moyen
    }

    /// Nombre de doigts posés à l'instant, et moment de la dernière mesure (pour bloquer le défilement parasite).
    static var nombreDoigts = 0
    static var dernierePresence: TimeInterval = 0
    private static var departs: [Int32: Float] = [:]   // hauteur de départ de chaque doigt
    private static let seuil: Float = 0.12             // un huitième de la hauteur du trackpad suffit

    /// Une image du trackpad : chaque doigt avec son numéro et sa hauteur (0 en bas, 1 en haut).
    /// Renvoie 1 pour un geste vers le haut, -1 vers le bas, 0 sinon.
    /// Le geste ne compte qu'une fois, jusqu'à ce que les doigts se lèvent.
    static func traiter(_ doigts: [(Int32, Float)]) -> Int {
        // Moins de trois doigts : le geste est fini (ou n'a pas commencé).
        if doigts.count < 3 { departs = [:]; dejaFait = false; return 0 }
        // On note la hauteur de départ de chaque doigt la première fois qu'on le voit,
        // y compris ceux qui se posent un peu en retard : les doigts n'arrivent jamais tous en même temps.
        for (id, y) in doigts where departs[id] == nil { departs[id] = y }
        // Il faut quatre doigts (ou cinq) pour le geste ; à trois, on attend le quatrième.
        guard doigts.count >= 4, !dejaFait else { return 0 }
        // Déplacement moyen des doigts présents, chacun mesuré depuis son propre départ :
        // un doigt qui se lève ou se pose ne fausse plus la mesure.
        let ecarts = doigts.compactMap { id, y in departs[id].map { y - $0 } }
        guard ecarts.count >= 4 else { return 0 }
        let moyen = ecarts.reduce(0, +) / Float(ecarts.count)
        // Tous les doigts doivent aller dans le même sens (pas un pincement ni un écartement).
        let memeSens = GestePages.tousGlissent(ecarts, moyenne: moyen)
        if memeSens && abs(moyen) > seuil { dejaFait = true; return moyen > 0 ? 1 : -1 }
        return 0
    }

    /// Pendant un geste à trois doigts ou plus, macOS envoie aussi du défilement à l'app sous le pointeur :
    /// la page bougeait en même temps. Side bloque ce défilement-là, et seulement lui.
    private static var filtre: CFMachPort?
    static func bloquerDefilement() {
        guard filtre == nil else { return }
        let masque = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        filtre = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                   eventsOfInterest: masque, callback: { _, type, evenement, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let f = Doigts.filtre { CGEvent.tapEnable(tap: f, enable: true) }
                return Unmanaged.passUnretained(evenement)
            }
            // Seulement si quatre doigts au moins sont posés, mesurés il y a moins d'un dixième de seconde.
            let recent = ProcessInfo.processInfo.systemUptime - Doigts.dernierePresence < 0.1
            if Doigts.actif && recent && Doigts.nombreDoigts >= 4 { return nil }
            return Unmanaged.passUnretained(evenement)
        }, userInfo: nil)
        guard let filtre else { return }   // sans l'autorisation Accessibilité, on s'en passe
        let source = CFMachPortCreateRunLoopSource(nil, filtre, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: filtre, enable: true)
    }
}
