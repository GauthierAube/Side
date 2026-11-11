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

// MARK: - Réglages

enum Reglages {
    static let largeurAjout: CGFloat = 52
    static let margeCarte: CGFloat = 12             // espace entre la carte et les bords de l'écran
    static let rayonCarte: CGFloat = 24
    static let delaiOuverture: TimeInterval = 0.03  // souris immobile dans le coin
    static let carreDepot: CGFloat = 150            // côté d'une zone de dépôt flottante
    static let barreApps: CGFloat = 66              // hauteur du mini-Dock, espace compris
    static let debord: CGFloat = 40                 // place laissée au rebond de l'animation
    static let delaiFermeture: TimeInterval = 0.35  // souris sortie de la carte
    static let joursRecents: Double = 30
    static let nombreRecents = 60
}

// MARK: - Choix de l'utilisateur

enum Coin: String, CaseIterable {
    case aucun, hautGauche, hautDroite, basGauche, basDroite
    var titre: String {
        switch self {
        case .aucun: return "Aucun"
        case .hautGauche: return "En haut à gauche"
        case .hautDroite: return "En haut à droite"
        case .basGauche: return "En bas à gauche"
        case .basDroite: return "En bas à droite"
        }
    }
}

enum Bord: String, CaseIterable {
    case haut, bas, gauche, droite, plein
    var titre: String {
        switch self {
        case .haut: return "Du haut"
        case .bas: return "Du bas"
        case .gauche: return "De la gauche"
        case .droite: return "De la droite"
        case .plein: return "Position libre, en fondu"
        }
    }
    var lateral: Bool { self == .gauche || self == .droite }
}

final class Config: ObservableObject {
    static let shared = Config()
    private let d = UserDefaults.standard

    @Published var coin: Coin { didSet { d.set(coin.rawValue, forKey: "coin") } }
    @Published var bord: Bord { didSet { d.set(bord.rawValue, forKey: "bord") } }
    /// Taille de la carte, en part de l'écran : hauteur (haut/bas) ou largeur (gauche/droite).
    @Published var tailleHauteur: Double { didSet { d.set(tailleHauteur, forKey: "tailleHauteur") } }
    @Published var tailleLargeur: Double { didSet { d.set(tailleLargeur, forKey: "tailleLargeur") } }
    /// Colonnes : vrai = toutes visibles (elles se partagent la place), faux = taille fixe et on fait défiler.
    @Published var ajuster: Bool { didSet { d.set(ajuster, forKey: "ajuster") } }
    @Published var tailleColonne: Double { didSet { d.set(tailleColonne, forKey: "tailleColonne") } }
    @Published var fermerEnSortant: Bool { didSet { d.set(fermerEnSortant, forKey: "fermerEnSortant") } }
    @Published var fermerAuClic: Bool { didSet { d.set(fermerAuClic, forKey: "fermerAuClic") } }
    /// Dossier affiché à l'ouverture de la carte (chemin) ; vide = le dernier consulté.
    @Published var ouverture: String { didSet { d.set(ouverture, forKey: "ouverture") } }
    /// Largeur de la grande zone, réglable en glissant le trait à sa droite.
    @Published var largeurZone: Double { didSet { d.set(largeurZone, forKey: "largeurZone") } }
    /// Opacité du fond de la carte : 0 = très transparent, 1 = opaque.
    @Published var opacite: Double { didSet { d.set(opacite, forKey: "opacite") } }
    /// Taille de la zone sensible du coin actif, en points.
    @Published var tailleCoin: Double { didSet { d.set(tailleCoin, forKey: "tailleCoin") } }
    /// Sensibilité de la secousse : 0 = il faut secouer fort et longtemps, 1 = un petit geste suffit.
    @Published var sensibilite: Double { didSet { d.set(sensibilite, forKey: "sensibilite") } }
    /// Largeur de la carte quand aucune colonne n'est épinglée (part de l'écran ; 1 = toute la largeur).
    @Published var largeurSeule: Double { didSet { d.set(largeurSeule, forKey: "largeurSeule") } }
    /// Largeur des colonnes de la présentation « colonnes », réglable en glissant leurs traits.
    @Published var largeurMiller: Double { didSet { d.set(largeurMiller, forKey: "largeurMiller") } }
    /// Au changement de bureau : "commande" = la carte suit si Commande est maintenue,
    /// "toujours" = elle suit toujours, "jamais" = elle se ferme toujours.
    @Published var suivi: String { didSet { d.set(suivi, forKey: "suivi") } }
    /// Largeur de la carte quand des colonnes sont épinglées (part de l'écran ; 1 = toute la largeur).
    @Published var largeurAvec: Double { didSet { d.set(largeurAvec, forKey: "largeurAvec") } }
    /// Vrai : une seule largeur, avec ou sans colonne épinglée. Faux : deux largeurs séparées.
    @Published var memeLargeur: Bool { didSet { d.set(memeLargeur, forKey: "memeLargeur") } }
    /// Afficher le mini-Dock des apps ouvertes, à côté de la carte.
    @Published var apps: Bool { didSet { d.set(apps, forKey: "apps") } }
    /// Mini-Dock : montrer les apps ouvertes, les apps favorites, ou les deux.
    /// Où flotte le mini-Dock par rapport à la carte : "haut", "bas", "gauche" ou "droite".
    @Published var dockPosition: String { didSet { d.set(dockPosition, forKey: "dockPosition") } }
    /// Taille des icônes du mini-Dock, en points.
    @Published var tailleDock: Double { didSet { d.set(tailleDock, forKey: "tailleDock") } }
    /// Le bouton « Apps » à gauche du mini-Dock : toutes les applications, avec une recherche.
    @Published var lanceur: Bool { didSet { d.set(lanceur, forKey: "lanceur") } }
    @Published var appsOuvertes: Bool { didSet { d.set(appsOuvertes, forKey: "appsOuvertes") } }
    @Published var appsFavoris: Bool { didSet { d.set(appsFavoris, forKey: "appsFavoris") } }
    /// Emplacements des apps favorites, et des apps ouvertes qu'on a choisi de masquer.
    @Published var appsFavorites: [String] { didSet { d.set(appsFavorites, forKey: "appsFavorites") } }
    @Published var appsMasquees: [String] { didSet { d.set(appsMasquees, forKey: "appsMasquees") } }
    /// Raccourcis de l'app « Raccourcis » de macOS affichés dans la barre latérale (par leur nom).
    @Published var raccourcis: [String] { didSet { d.set(raccourcis, forKey: "raccourcis") } }
    /// Historique du copier-coller, et faut-il y garder aussi les mots de passe (affichés masqués).
    @Published var historique: Bool {
        didSet { d.set(historique, forKey: "historique"); if !historique { PressePapiers.shared.toutEffacer() } }
    }
    @Published var historiqueSecrets: Bool { didSet { d.set(historiqueSecrets, forKey: "historiqueSecrets") } }
    /// Flouter ce qui se trouve derrière la carte quand elle est ouverte, et avec quelle force.
    @Published var flou: Bool { didSet { d.set(flou, forKey: "flou") } }
    @Published var flouForce: Double { didSet { d.set(flouForce, forKey: "flouForce") } }
    /// Refermer Side dès qu'on a déposé quelque chose dans une zone de dépôt (la zone, elle, reste).
    @Published var fermerApresDepot: Bool { didSet { d.set(fermerApresDepot, forKey: "fermerApresDepot") } }
    /// Cadenas des zones de dépôt : fermé = elles restent à l'écran quand Side se ferme.
    @Published var depotReste: Bool { didSet { d.set(depotReste, forKey: "depotReste") } }
    /// Chaque nouvelle capture d'écran arrive toute seule dans une zone de dépôt.
    @Published var capturesAuto: Bool { didSet { d.set(capturesAuto, forKey: "capturesAuto") } }
    @Published var secouer: Bool { didSet { d.set(secouer, forKey: "secouer") } }
    /// Glisser quatre doigts vers le haut ou vers le bas sur le trackpad ouvre et ferme Side.
    @Published var quatreDoigts: Bool {
        didSet { d.set(quatreDoigts, forKey: "quatreDoigts"); Doigts.actif = quatreDoigts; if quatreDoigts { Doigts.demarrer(); Doigts.bloquerDefilement() } }
    }
    /// Sens du geste à quatre doigts : "haut", "bas" ou "deux".
    @Published var sensDoigts: String { didSet { d.set(sensDoigts, forKey: "sensDoigts"); Doigts.sens = sensDoigts } }
    /// Geste de la souris : faux = secouer le pointeur, vrai = lui faire faire un cercle.
    @Published var cercle: Bool { didSet { d.set(cercle, forKey: "gestePerso") } }
    // Réglages repris du Finder.
    /// Entrées affichées dans la barre latérale (par leur clé : "recents", "icloud", "disques"…).
    @Published var barre: [String] { didSet { d.set(barre, forKey: "barre") } }
    @Published var extensions: Bool {
        didSet { d.set(extensions, forKey: "extensions"); Fichiers.extensions = extensions; AppDelegate.shared.store.reloadAll() }
    }
    @Published var dossiersEnHaut: Bool {
        didSet { d.set(dossiersEnHaut, forKey: "dossiersEnHaut"); Fichiers.dossiersEnHaut = dossiersEnHaut; AppDelegate.shared.store.reloadAll() }
    }
    /// Recherche : vrai = sur tout le Mac, faux = dans le dossier affiché.
    @Published var rechercheMac: Bool { didSet { d.set(rechercheMac, forKey: "rechercheMac") } }
    // Présentation par icônes.
    @Published var tailleIcones: Double { didSet { d.set(tailleIcones, forKey: "tailleIcones") } }
    @Published var espacement: Double { didSet { d.set(espacement, forKey: "espacement") } }
    @Published var tailleTexte: Double { didSet { d.set(tailleTexte, forKey: "tailleTexte") } }
    @Published var texteADroite: Bool { didSet { d.set(texteADroite, forKey: "texteADroite") } }
    @Published var infos: Bool { didSet { d.set(infos, forKey: "infos") } }
    @Published var apercus: Bool { didSet { d.set(apercus, forKey: "apercus") } }
    /// Raccourci clavier : -2 = Commande + @ (par défaut), -1 = aucun, sinon le code de la touche.
    @Published var touche: Int { didSet { d.set(touche, forKey: "raccourciTouche") } }
    @Published var mods: Int { didSet { d.set(mods, forKey: "raccourciMods") } }
    @Published var libelle: String { didSet { d.set(libelle, forKey: "raccourciLibelle") } }

    private init() {
        coin = d.string(forKey: "coin").flatMap(Coin.init) ?? .hautGauche
        bord = d.string(forKey: "bord").flatMap(Bord.init) ?? .haut
        tailleHauteur = d.object(forKey: "tailleHauteur") as? Double ?? 0.42
        tailleLargeur = d.object(forKey: "tailleLargeur") as? Double ?? 0.25
        ajuster = d.object(forKey: "ajuster") as? Bool ?? true
        tailleColonne = d.object(forKey: "tailleColonne") as? Double ?? 320
        fermerEnSortant = d.bool(forKey: "fermerEnSortant")
        fermerAuClic = d.object(forKey: "fermerAuClic") as? Bool ?? true
        ouverture = d.string(forKey: "ouverture")
            ?? Fichiers.para().first(where: { $0.url.lastPathComponent.hasPrefix("02") })?.url.path ?? ""
        largeurZone = d.object(forKey: "largeurZone") as? Double ?? 420
        opacite = d.object(forKey: "opacite") as? Double ?? 0.5
        tailleCoin = d.object(forKey: "tailleCoin") as? Double ?? 36
        sensibilite = d.object(forKey: "sensibilite") as? Double ?? 0.5
        largeurSeule = d.object(forKey: "largeurSeule") as? Double ?? 0.6
        largeurMiller = d.object(forKey: "largeurMiller") as? Double ?? 220
        suivi = d.string(forKey: "suivi") ?? "commande"
        largeurAvec = d.object(forKey: "largeurAvec") as? Double ?? 1
        memeLargeur = d.bool(forKey: "memeLargeur")
        apps = d.object(forKey: "apps") as? Bool ?? true
        dockPosition = d.string(forKey: "dockPosition") ?? "haut"
        tailleDock = d.object(forKey: "tailleDock") as? Double ?? 40
        lanceur = d.object(forKey: "lanceur") as? Bool ?? true
        appsOuvertes = d.object(forKey: "appsOuvertes") as? Bool ?? true
        appsFavoris = d.object(forKey: "appsFavoris") as? Bool ?? true
        appsFavorites = d.stringArray(forKey: "appsFavorites") ?? []
        appsMasquees = d.stringArray(forKey: "appsMasquees") ?? []
        raccourcis = d.stringArray(forKey: "raccourcis") ?? []
        historique = d.object(forKey: "historique") as? Bool ?? true
        historiqueSecrets = d.object(forKey: "historiqueSecrets") as? Bool ?? true
        flou = d.bool(forKey: "flou")
        flouForce = d.object(forKey: "flouForce") as? Double ?? 0.85
        fermerApresDepot = d.object(forKey: "fermerApresDepot") as? Bool ?? true
        depotReste = d.object(forKey: "depotReste") as? Bool ?? true
        capturesAuto = d.object(forKey: "capturesAuto") as? Bool ?? true
        secouer = d.object(forKey: "secouer") as? Bool ?? true
        quatreDoigts = d.bool(forKey: "quatreDoigts")
        sensDoigts = d.string(forKey: "sensDoigts") ?? "bas"
        cercle = d.bool(forKey: "gestePerso")
        var entrees = d.stringArray(forKey: "barre") ?? ["recents", "dossiers", "icloud", "maison", "applications", "reseau", "tags"]
        // La rubrique Réseau est arrivée après coup : on l'ajoute une fois aux réglages déjà enregistrés.
        if !d.bool(forKey: "barreReseauAjoutee") {
            d.set(true, forKey: "barreReseauAjoutee")
            if !entrees.contains("reseau") { entrees.append("reseau"); d.set(entrees, forKey: "barre") }
        }
        barre = entrees
        extensions = Fichiers.extensions
        dossiersEnHaut = Fichiers.dossiersEnHaut
        rechercheMac = d.bool(forKey: "rechercheMac")
        tailleIcones = d.object(forKey: "tailleIcones") as? Double ?? 64
        espacement = d.object(forKey: "espacement") as? Double ?? 12
        tailleTexte = d.object(forKey: "tailleTexte") as? Double ?? 12
        texteADroite = d.bool(forKey: "texteADroite")
        infos = d.bool(forKey: "infos")
        apercus = d.object(forKey: "apercus") as? Bool ?? true
        touche = d.object(forKey: "raccourciTouche") as? Int ?? -2
        mods = d.integer(forKey: "raccourciMods")
        libelle = d.string(forKey: "raccourciLibelle") ?? "⌘@"
    }
}

// MARK: - Geste de la souris : le cercle

/// Reconnaît un cercle fait à la souris, sans clic. On ne compare pas la forme : il suffit que le pointeur
/// fasse un tour à peu près complet, dans un sens ou dans l'autre. Un cercle grossier ou tremblé convient.
enum Geste {
    static let nombre = 32

    static func longueur(_ p: [CGPoint]) -> CGFloat {
        zip(p, p.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }
    static func boite(_ p: [CGPoint]) -> CGRect {
        guard let a = p.first else { return .zero }
        return p.reduce(CGRect(origin: a, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
    /// Rééchantillonne en `nombre` points régulièrement espacés le long du tracé.
    static func regulier(_ p: [CGPoint]) -> [CGPoint] {
        guard p.count > 1 else { return p }
        let pas = longueur(p) / CGFloat(nombre - 1)
        guard pas > 0 else { return p }
        var sortie = [p[0]], reste: CGFloat = 0, points = p, i = 1
        while i < points.count {
            let a = points[i - 1], b = points[i], d = hypot(b.x - a.x, b.y - a.y)
            if reste + d >= pas, d > 0 {
                let t = (pas - reste) / d
                let q = CGPoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y))
                sortie.append(q)
                points.insert(q, at: i)
                reste = 0
            } else { reste += d }
            i += 1
        }
        while sortie.count < nombre { sortie.append(p[p.count - 1]) }
        return Array(sortie.prefix(nombre))
    }
    /// De combien le tracé tourne, en degrés (positif dans un sens, négatif dans l'autre),
    /// et à quel point il tourne toujours du même côté (1 = toujours, 0 = autant à gauche qu'à droite).
    static func rotation(_ p: [CGPoint]) -> (degres: CGFloat, constance: CGFloat) {
        // Un point sur deux : les petits tremblements de la main ne comptent pas comme des virages.
        // Chaque point est aussi adouci avec ses deux voisins.
        let brut = regulier(p)
        let doux: [CGPoint] = brut.indices.map { i in
            let a = brut[max(i - 1, 0)], b = brut[i], c = brut[min(i + 1, brut.count - 1)]
            return CGPoint(x: (a.x + b.x + c.x) / 3, y: (a.y + b.y + c.y) / 3)
        }
        let r = doux.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        guard r.count >= 3 else { return (0, 0) }
        var somme: CGFloat = 0, absolue: CGFloat = 0
        for i in 1..<(r.count - 1) {
            let a = atan2(r[i].y - r[i - 1].y, r[i].x - r[i - 1].x)
            let b = atan2(r[i + 1].y - r[i].y, r[i + 1].x - r[i].x)
            var d = b - a
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            somme += d
            absolue += abs(d)
        }
        return (somme * 180 / .pi, absolue > 0 ? abs(somme) / absolue : 0)
    }
    /// Rondeur d'un tracé : 1 pour un cercle, proche de 0 pour un aller-retour, quel que soit son angle.
    /// (Rapport entre l'étalement des points dans leur direction la plus courte et dans la plus longue.)
    static func rondeur(_ p: [CGPoint]) -> CGFloat {
        let r = regulier(p), n = CGFloat(r.count)
        guard n > 2 else { return 0 }
        let mx = r.reduce(0) { $0 + $1.x } / n, my = r.reduce(0) { $0 + $1.y } / n
        var xx: CGFloat = 0, yy: CGFloat = 0, xy: CGFloat = 0
        for q in r { xx += (q.x - mx) * (q.x - mx); yy += (q.y - my) * (q.y - my); xy += (q.x - mx) * (q.y - my) }
        let moitie = (xx + yy) / 2, ecart = (((xx - yy) / 2) * ((xx - yy) / 2) + xy * xy).squareRoot()
        let grand = moitie + ecart, petit = max(0, moitie - ecart)
        return grand > 0 ? (petit / grand).squareRoot() : 0
    }
    /// Un tour à peu près complet, dans un sens ou dans l'autre, pas trop aplati.
    static func boucle(_ p: [CGPoint], degres: CGFloat) -> Bool {
        let b = boite(p)
        guard max(b.width, b.height) >= 24 else { return false }   // 24 points : un petit rond du poignet suffit
        // Une secousse dessine aussi une boucle, mais très aplatie : on exige une forme assez ronde.
        guard rondeur(p) >= 0.45 else { return false }
        let r = rotation(p)
        return abs(r.degres) >= degres && r.constance >= 0.65
    }
}

// MARK: - Réseau

/// Les ordinateurs du réseau local qui partagent des fichiers, comme la rubrique « Réseau » du Finder.
/// Side les repère (annonces Bonjour) ; s'y connecter passe par le Finder, qui demande le mot de passe.
final class Reseau: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = Reseau()
    @Published var ordinateurs: [String] = []
    private var chercheurs: [NetServiceBrowser] = []
    private var services: [NetService] = []
    private var enAttente: NetService?

    /// Lance la recherche (une seule fois) : partages Windows/Mac récents (SMB) et anciens Mac (AFP).
    func chercher() {
        guard chercheurs.isEmpty else { return }
        for type in ["_smb._tcp.", "_afpovertcp._tcp."] {
            let c = NetServiceBrowser()
            c.delegate = self
            c.searchForServices(ofType: type, inDomain: "local.")
            chercheurs.append(c)
        }
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        publier()
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        publier()
    }
    private func publier() {
        let moi = Host.current().localizedName
        let noms = Set(services.map(\.name)).filter { $0 != moi }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if noms != ordinateurs { ordinateurs = noms }
    }
    /// Ouvre l'ordinateur dans le Finder, qui affiche ses dossiers partagés (après identification si besoin).
    func ouvrir(_ nom: String) {
        guard let service = services.first(where: { $0.name == nom && $0.type.hasPrefix("_smb") })
                ?? services.first(where: { $0.name == nom }) else { return }
        enAttente = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard sender == enAttente, let hote = sender.hostName else { return }
        enAttente = nil
        let protocole = sender.type.hasPrefix("_afp") ? "afp" : "smb"
        var adresse = URLComponents()
        adresse.scheme = protocole
        adresse.host = hote.hasSuffix(".") ? String(hote.dropLast()) : hote
        if let url = adresse.url { NSWorkspace.shared.open(url) }
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        if sender == enAttente { enAttente = nil; NSSound.beep() }
    }
}

// MARK: - Geste à quatre doigts sur le trackpad

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
    static var actif = UserDefaults.standard.bool(forKey: "quatreDoigts")
    static var sens = UserDefaults.standard.string(forKey: "sensDoigts") ?? "bas"
    private static var demarre = false
    private static var dejaFait = false       // le geste en cours a déjà servi

    private typealias Liste = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Rappel = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias Inscrire = @convention(c) (UnsafeMutableRawPointer?, Rappel) -> Void
    private typealias Lancer = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void

    /// Nombre de trackpads trouvés (pour le diagnostic) ; -1 si le module de macOS est introuvable.
    @discardableResult
    static func demarrer() -> Int {
        guard !demarre else { return 0 }
        guard let module = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let fListe = dlsym(module, "MTDeviceCreateList"), let fInscrire = dlsym(module, "MTRegisterContactFrameCallback"),
              let fLancer = dlsym(module, "MTDeviceStart") else { return -1 }
        let liste = unsafeBitCast(fListe, to: Liste.self), inscrire = unsafeBitCast(fInscrire, to: Inscrire.self)
        let lancer = unsafeBitCast(fLancer, to: Lancer.self)
        guard let appareils = liste()?.takeRetainedValue() as? [AnyObject] else { return 0 }
        for a in appareils {
            let p = Unmanaged.passUnretained(a).toOpaque()
            inscrire(p, { _, touches, nombre, _, _ in
                Doigts.recevoir(touches, Int(nombre))
                return 0
            })
            lancer(p, 0)
        }
        demarre = true
        return appareils.count
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
        guard actif else { return }
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
        guard ecarts.allSatisfy({ moyen > 0 ? $0 > -0.03 : $0 < 0.03 }) else { return nil }
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
        let memeSens = ecarts.allSatisfy { moyen > 0 ? $0 > -0.02 : $0 < 0.02 }
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

// MARK: - Captures d'écran

/// Repère chaque nouvelle capture d'écran grâce à l'index du Mac (Spotlight marque les captures comme telles,
/// où qu'elles soient enregistrées), et la range dans une zone de dépôt.
final class Captures: NSObject {
    static let shared = Captures()
    private let requete = NSMetadataQuery()
    private var depart = Date()
    private var vues: Set<String> = []   // captures déjà traitées depuis le lancement

    func demarrer() {
        depart = Date()
        requete.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemContentCreationDate >= %@", depart as NSDate)
        requete.searchScopes = [NSMetadataQueryLocalComputerScope]
        NotificationCenter.default.addObserver(self, selector: #selector(nouveautes), name: .NSMetadataQueryDidUpdate, object: requete)
        NotificationCenter.default.addObserver(self, selector: #selector(nouveautes), name: .NSMetadataQueryDidFinishGathering, object: requete)
        requete.start()
    }

    @objc private func nouveautes() {
        requete.disableUpdates()
        defer { requete.enableUpdates() }
        let urls = (requete.results as? [NSMetadataItem] ?? []).compactMap { item -> URL? in
            guard let chemin = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            return URL(fileURLWithPath: chemin)
        }
        for url in urls where !vues.contains(url.path) {
            vues.insert(url.path)
            guard Config.shared.capturesAuto, FileManager.default.fileExists(atPath: url.path) else { continue }
            AppDelegate.shared.recevoirCapture(url)
        }
    }

    /// Les captures rangées par Side, pour les regrouper dans la même zone.
    static var rangees: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "capturesRangees") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "capturesRangees") }
    }
}

// MARK: - Raccourcis de macOS

/// Les raccourcis de l'app « Raccourcis », lus et lancés avec la commande `shortcuts` de macOS.
final class Raccourcis: ObservableObject {
    static let shared = Raccourcis()
    @Published var tous: [String] = []
    @Published var enCours: String?

    private init() { actualiser() }

    func actualiser() {
        DispatchQueue.global(qos: .utility).async {
            let noms = Self.commande(["list"]).split(separator: "\n").map(String.init)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            DispatchQueue.main.async { self.tous = noms }
        }
    }

    /// Lance un raccourci ; `fichiers` lui sont passés en entrée (par exemple une image à redimensionner).
    func lancer(_ nom: String, fichiers: [URL] = []) {
        enCours = nom
        DispatchQueue.global(qos: .userInitiated).async {
            var arguments = ["run", nom]
            for f in fichiers { arguments += ["-i", f.path] }
            _ = Self.commande(arguments)
            DispatchQueue.main.async { if self.enCours == nom { self.enCours = nil } }
        }
    }

    private static func commande(_ arguments: [String]) -> String {
        let p = Process(), sortie = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = arguments
        p.standardOutput = sortie
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "" }
        let data = sortie.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Historique du copier-coller

/// Un élément copié. Gardé en mémoire seulement : rien n'est écrit sur le disque.
struct Copie: Identifiable {
    let id = UUID()
    var date: Date
    var texte: String?
    var fichiers: [URL] = []
    var image: NSImage?
    var secret = false   // marqué « mot de passe » par l'app d'origine : affiché masqué
    var epingle = false  // épinglé : reste en haut de la liste, et survit à « Effacer »
}

final class PressePapiers: ObservableObject {
    static let shared = PressePapiers()
    static let maximum = 300
    static let duree: TimeInterval = 7 * 86400   // l'historique est gardé sept jours
    @Published var elements: [Copie] = PressePapiers.charger()
    private var compte = NSPasteboard.general.changeCount

    /// Les éléments épinglés d'abord, puis les autres du plus récent au plus ancien.
    var tries: [Copie] { elements.filter(\.epingle) + elements.filter { !$0.epingle } }

    /// Ce qui est écrit sur le disque : les textes et les fichiers copiés, jamais les mots de passe ni les images.
    private struct Ligne: Codable { var date: Date; var texte: String?; var fichiers: [String]; var epingle: Bool }
    private static var fichier: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Side/presse-papiers.json")
    }
    private static func charger() -> [Copie] {
        var copies: [Copie] = []
        if let data = try? Data(contentsOf: fichier), let lignes = try? JSONDecoder().decode([Ligne].self, from: data) {
            let limite = Date().addingTimeInterval(-duree)
            copies = lignes.filter { $0.epingle || $0.date > limite }.map {
                Copie(date: $0.date, texte: $0.texte, fichiers: $0.fichiers.map { URL(fileURLWithPath: $0) }, epingle: $0.epingle)
            }
        } else {
            // Ancienne version : seuls les textes épinglés étaient gardés, dans les réglages.
            copies = (UserDefaults.standard.stringArray(forKey: "presseEpingles") ?? []).map { Copie(date: Date(), texte: $0, epingle: true) }
        }
        return copies
    }
    private func sauver() {
        let lignes = elements.filter { !$0.secret && ($0.texte != nil || !$0.fichiers.isEmpty) }
            .map { Ligne(date: $0.date, texte: $0.texte, fichiers: $0.fichiers.map(\.path), epingle: $0.epingle) }
        let url = Self.fichier
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(lignes) else { return }
        try? data.write(to: url, options: .atomic)
        // Lisible par toi seul.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        UserDefaults.standard.removeObject(forKey: "presseEpingles")
    }
    /// Oublie ce qui a plus de sept jours (sauf les épinglés).
    private func purger() {
        let limite = Date().addingTimeInterval(-Self.duree)
        elements.removeAll { !$0.epingle && $0.date < limite }
    }
    func epingler(_ c: Copie) {
        guard let i = elements.firstIndex(where: { $0.id == c.id }) else { return }
        elements[i].epingle.toggle()
        sauver()
    }
    /// Historique désactivé : tout est effacé, y compris sur le disque.
    func toutEffacer() {
        elements = []
        try? FileManager.default.removeItem(at: Self.fichier)
        UserDefaults.standard.removeObject(forKey: "presseEpingles")
    }

    /// Appelé régulièrement : enregistre ce qui vient d'être copié.
    func verifier() {
        let pb = NSPasteboard.general
        guard pb.changeCount != compte else { return }
        compte = pb.changeCount
        guard Config.shared.historique else { return }
        let types = pb.types?.map(\.rawValue) ?? []
        // Convention des gestionnaires de mots de passe : « éphémère » = à ne jamais garder, « caché » = secret.
        if types.contains("org.nspasteboard.TransientType") { return }
        let secret = types.contains("org.nspasteboard.ConcealedType")
        if secret && !Config.shared.historiqueSecrets { return }
        var copie = Copie(date: Date(), secret: secret)
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            copie.fichiers = urls
        } else if let texte = pb.string(forType: .string), !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copie.texte = texte
        } else if let image = NSImage(pasteboard: pb) {
            copie.image = image
        } else { return }
        // Recopier la même chose ne crée pas de doublon : l'élément remonte en tête.
        if let i = elements.firstIndex(where: { $0.texte == copie.texte && $0.fichiers == copie.fichiers && $0.image == nil && copie.image == nil }) {
            copie.epingle = elements[i].epingle   // un élément épinglé le reste
            elements.remove(at: i)
        }
        elements.insert(copie, at: 0)
        // Au-delà de la limite, on oublie les plus anciens — jamais les épinglés.
        while elements.count > Self.maximum, let i = elements.lastIndex(where: { !$0.epingle }) { elements.remove(at: i) }
        purger()
        sauver()
    }

    /// Remet un élément dans le presse-papiers, prêt à être collé.
    func recopier(_ c: Copie) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if !c.fichiers.isEmpty { pb.writeObjects(c.fichiers as [NSURL]) }
        else if let image = c.image { pb.writeObjects([image]) }
        else if let texte = c.texte { pb.setString(texte, forType: .string) }
        compte = pb.changeCount
        if let i = elements.firstIndex(where: { $0.id == c.id }) {
            var repris = elements.remove(at: i)
            repris.date = Date()   // réutilisé : il repart pour sept jours
            elements.insert(repris, at: 0)
            sauver()
        }
    }

    func supprimer(_ c: Copie) { elements.removeAll { $0.id == c.id }; sauver() }
    func vider() { elements.removeAll { !$0.epingle }; sauver() }
}

// MARK: - Largeurs de la carte

/// La partie « Finder » (barre latérale, grande zone, zones de dépôt) garde toujours la même largeur.
/// Chaque colonne épinglée s'ajoute à droite et élargit la carte, jusqu'à la largeur de l'écran.
enum Disposition {
    /// Largeur de la carte sans colonne épinglée.
    static func base(_ maxi: CGFloat) -> CGFloat {
        (maxi * CGFloat(min(max(Config.shared.largeurSeule, 0.35), 1))).rounded()
    }
    /// Largeur d'une colonne épinglée. En mode « rétrécir », elles se serrent quand la place manque.
    static func colonne(_ n: Int, _ maxi: CGFloat) -> CGFloat {
        let voulue = CGFloat(Config.shared.tailleColonne)
        guard n > 0, Config.shared.ajuster else { return voulue }
        return max(80, min(voulue, ((maxi - base(maxi)) / CGFloat(n)).rounded(.down) - 1))
    }
    /// Épaisseur occupée par le mini-Dock (icône, point, marges et espace avec la carte) ; 0 s'il est masqué.
    static var dock: CGFloat { Config.shared.apps ? CGFloat(Config.shared.tailleDock) + 20 : 0 }   // icône + 12 de marges + 8 d'espace
    static func carte(_ n: Int, _ maxi: CGFloat) -> CGFloat {
        min(maxi, base(maxi) + CGFloat(n) * (colonne(n, maxi) + 1))
    }
}

// MARK: - Fichiers

enum Tri: String, CaseIterable {
    case nom, date, taille, type
    var titre: String {
        switch self {
        case .nom: return "Nom"
        case .date: return "Date (les plus récents d'abord)"
        case .taille: return "Taille"
        case .type: return "Type"
        }
    }
}

enum Presentation: String { case liste, icones, colonnes }

/// Où en est un fichier d'iCloud Drive : sur le Mac, resté dans le nuage, en cours de téléchargement ou d'envoi.
enum Nuage { case aucun, aTelecharger, telechargement, envoi }

struct FileItem: Identifiable, Hashable {
    let url: URL
    let isFolder: Bool
    let date: Date
    var taille: Int = 0
    var nuage: Nuage = .aucun
    var id: URL { url }
    /// Nom affiché. Avec « Afficher toutes les extensions », les fichiers gardent leur extension ;
    /// les dossiers gardent leur nom traduit (Documents, Téléchargements…).
    var name: String {
        if !isFolder && Fichiers.extensions { return url.lastPathComponent }
        return FileManager.default.displayName(atPath: url.path)
    }
}

enum Fichiers {
    // Copies de deux réglages, lues pendant les tris (les réglages eux-mêmes ne sont pas encore prêts au lancement).
    static var extensions = UserDefaults.standard.object(forKey: "extensions") as? Bool ?? true
    static var dossiersEnHaut = UserDefaults.standard.object(forKey: "dossiersEnHaut") as? Bool ?? true
    static let home = FileManager.default.homeDirectoryForCurrentUser
    /// Vrai pour un serveur ou un dossier partagé du réseau, faux pour un disque branché au Mac.
    static func estReseau(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal == false
    }
    /// Les disques branchés (externes, images disque…) et les serveurs connectés, sans le disque de démarrage.
    static func disques() -> [URL] {
        (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [])
            .filter { $0.path != "/" }
    }
    static let documents = home.appendingPathComponent("Documents")
    /// Le dossier Téléchargements : celui d'iCloud Drive s'il existe, sinon celui du Mac.
    static let downloads: URL = {
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Downloads")
        return FileManager.default.fileExists(atPath: icloud.path) ? icloud : home.appendingPathComponent("Downloads")
    }()
    static let desktop = home.appendingPathComponent("Desktop")
    static let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")

    /// Nom affiché d'un dossier (le dossier Téléchargements d'iCloud s'appelle « Downloads » sur le disque).
    static func nom(_ url: URL) -> String {
        if url.standardizedFileURL == downloads.standardizedFileURL { return "Téléchargements" }
        if url.standardizedFileURL == icloud.standardizedFileURL { return "iCloud Drive" }
        return FileManager.default.displayName(atPath: url.path)
    }

    static let cles: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .contentModificationDateKey, .addedToDirectoryDateKey, .fileSizeKey,
        .isAliasFileKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemIsUploadingKey,
    ]

    /// Le dossier lui-même, puis ceux qui le contiennent, en remontant jusqu'au dossier personnel
    /// (ou jusqu'au disque pour un dossier situé ailleurs).
    static func ascendants(_ url: URL) -> [URL] {
        var liste: [URL] = [], u = url.standardizedFileURL
        while liste.count < 30 {
            liste.append(u)
            if u.path == "/" || u.path == home.path || u.path == icloud.path { break }
            u = u.deletingLastPathComponent()
        }
        return liste
    }

    /// Si c'est un alias ou un lien vers un dossier, rend ce dossier ; sinon rend l'adresse telle quelle.
    static func resoudre(_ url: URL) -> URL {
        guard (try? url.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true,
              let cible = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]),
              let v = try? cible.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
              v.isDirectory == true, v.isPackage != true else { return url }
        return cible
    }

    static func item(_ url: URL) -> FileItem {
        let v = try? url.resourceValues(forKeys: Set(cles))
        var dossier = (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
        // Un alias (ou un lien) vers un dossier se comporte comme ce dossier : on l'ouvre dans Side, pas dans le Finder.
        if !dossier, v?.isAliasFile == true { dossier = resoudre(url) != url }
        let date = max(v?.contentModificationDate ?? .distantPast, v?.addedToDirectoryDate ?? .distantPast)
        // iCloud Drive : le fichier est-il vraiment sur le Mac ?
        var nuage = Nuage.aucun
        if v?.isUbiquitousItem == true {
            if v?.ubiquitousItemIsDownloading == true { nuage = .telechargement }
            else if v?.ubiquitousItemDownloadingStatus == .notDownloaded { nuage = .aTelecharger }
            else if v?.ubiquitousItemIsUploading == true { nuage = .envoi }
        }
        return FileItem(url: url, isFolder: dossier, date: date, taille: v?.fileSize ?? 0, nuage: nuage)
    }

    static func contenu(_ url: URL, tri: Tri) -> [FileItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: resoudre(url), includingPropertiesForKeys: cles, options: [.skipsHiddenFiles])) ?? []
        let items = urls.map(item)
        func parNom(_ a: FileItem, _ b: FileItem) -> Bool {
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        switch tri {
        case .date: return items.sorted { $0.date > $1.date }
        case .taille: return items.sorted { $0.taille > $1.taille }
        case .type:
            return items.sorted {
                let (x, y) = ($0.url.pathExtension.lowercased(), $1.url.pathExtension.lowercased())
                return x == y ? parNom($0, $1) : x < y
            }
        case .nom:
            return items.sorted { dossiersEnHaut && $0.isFolder != $1.isFolder ? $0.isFolder : parNom($0, $1) }
        }
    }

    /// Les dossiers Inbox + PARA : ceux de Documents qui commencent par deux chiffres.
    static func para() -> [FileItem] {
        contenu(documents, tri: .nom).filter { item in
            let n = item.url.lastPathComponent
            return item.isFolder && n.count > 2 && n.prefix(2).allSatisfy(\.isNumber)
        }
    }

    private static let verrou = NSLock()
    private static var cache: (date: Date, items: [FileItem])?

    /// Tous les fichiers modifiés ou reçus récemment, du plus récent au plus ancien.
    /// Le résultat est gardé quelques secondes : deux colonnes s'en servent.
    private static func fichiersRecents() -> [FileItem] {
        verrou.lock()
        defer { verrou.unlock() }
        if let c = cache, Date().timeIntervalSince(c.date) < 5 { return c.items }
        let limite = Date().addingTimeInterval(-Reglages.joursRecents * 86400)
        var trouves: [FileItem] = []
        for racine in [documents, downloads, desktop] {
            guard let e = FileManager.default.enumerator(
                at: racine, includingPropertiesForKeys: cles,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                let it = item(url)
                if it.isFolder {
                    if url.lastPathComponent == "node_modules" { e.skipDescendants() }
                    continue
                }
                if it.date > limite { trouves.append(it) }
            }
        }
        trouves.sort { $0.date > $1.date }
        cache = (Date(), trouves)
        return trouves
    }

    static func recents() -> [FileItem] { Array(fichiersRecents().prefix(Reglages.nombreRecents)) }

    /// Recherche Spotlight dans un dossier et ses sous-dossiers. Les noms qui contiennent le texte passent en premier.
    static func chercher(_ texte: String, dans dossier: URL?) -> [FileItem] {
        // Un texte qui commence par un tiret serait pris pour une option de la commande de recherche : on l'en débarrasse.
        let texte = String(texte.drop { $0 == "-" })
        guard !texte.isEmpty else { return [] }
        let p = Process(), sortie = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = dossier.map { ["-onlyin", resoudre($0).path, texte] } ?? [texte]   // sans dossier : tout le Mac
        p.standardOutput = sortie
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        let data = sortie.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let items = String(decoding: data, as: UTF8.self).split(separator: "\n").prefix(300)
            .map { item(URL(fileURLWithPath: String($0))) }
        func parNom(_ i: FileItem) -> Bool { i.name.localizedCaseInsensitiveContains(texte) }
        return items.sorted { a, b in parNom(a) != parNom(b) ? parNom(a) : a.date > b.date }
    }

    /// Les fichiers et dossiers qui portent un tag du Finder (recherche Spotlight).
    static func avecTag(_ nom: String) -> [FileItem] {
        let p = Process(), sortie = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["kMDItemUserTags == \"" + nom.replacingOccurrences(of: "\"", with: "\\\"") + "\""]
        p.standardOutput = sortie
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        let data = sortie.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let chemins = String(decoding: data, as: UTF8.self).split(separator: "\n").prefix(300)
        return chemins.map { item(URL(fileURLWithPath: String($0))) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Si ce dossier est un paquet, ou se trouve à l'intérieur d'un paquet, rend le dossier qui contient le paquet.
    static func horsPaquet(_ url: URL) -> URL {
        var resultat = url, u = url
        while u.path != "/" && u.path != home.path {
            if (try? u.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { resultat = u.deletingLastPathComponent() }
            u = u.deletingLastPathComponent()
        }
        return resultat
    }

    /// Les dossiers où il s'est passé quelque chose récemment, du plus récent au plus ancien.
    static func dossiersRecents() -> [FileItem] {
        var vus = Set<URL>(), resultat: [FileItem] = []
        for f in fichiersRecents() {
            // Un projet Logic, une bibliothèque Photos… sont des « paquets » : des dossiers que macOS montre comme
            // un seul fichier. On ne les liste pas comme des dossiers : on remonte au vrai dossier qui les contient.
            let dossier = horsPaquet(f.url.deletingLastPathComponent())
            guard vus.insert(dossier).inserted else { continue }
            resultat.append(FileItem(url: dossier, isFolder: true, date: f.date))
            if resultat.count >= Reglages.nombreRecents { break }
        }
        return resultat
    }
}

// MARK: - Étagère

/// L'étagère garde des fichiers sous la main sans les déplacer : elle ne retient que leur emplacement.
enum Etagere {
    static let maximum = 6
    /// Nombre de zones de dépôt : une seule au départ, on peut en ajouter en dessous.
    static var nombre: Int {
        get {
            if let n = UserDefaults.standard.object(forKey: "etagereNombre") as? Int { return min(max(n, 1), maximum) }
            return max(1, ((0..<3).last { !chemins($0).isEmpty } ?? 0) + 1)   // garde les zones déjà remplies
        }
        set { UserDefaults.standard.set(newValue, forKey: "etagereNombre") }
    }
    /// Supprime une zone : les suivantes remontent d'un cran.
    static func supprimer(_ i: Int) {
        let n = nombre
        guard n > 1 else { return }
        for j in i..<(n - 1) { ecrire(chemins(j + 1), j) }
        ecrire([], n - 1)
        nombre = n - 1
    }
    private static func cle(_ i: Int) -> String { i == 0 ? "etagere" : "etagere\(i)" }
    private static func chemins(_ i: Int) -> [String] { UserDefaults.standard.stringArray(forKey: cle(i)) ?? [] }
    private static func ecrire(_ c: [String], _ i: Int) { UserDefaults.standard.set(c, forKey: cle(i)) }

    static func items(_ i: Int) -> [FileItem] {
        chemins(i).filter { FileManager.default.fileExists(atPath: $0) }
            .map { Fichiers.item(URL(fileURLWithPath: $0)) }
    }
    /// Identité d'un fichier sur le disque : la même quel que soit le chemin par lequel on y arrive.
    private static func identite(_ chemin: String) -> NSObject? {
        (try? URL(fileURLWithPath: chemin).resourceValues(forKeys: [.fileResourceIdentifierKey]))?
            .fileResourceIdentifier as? NSObject
    }

    /// Ajoute un élément à une zone. Le même fichier déposé deux fois n'apparaît qu'une fois.
    @discardableResult
    static func ajouter(_ url: URL, _ i: Int) -> Bool {
        let c = url.resolvingSymlinksInPath().standardizedFileURL.path
        let existants = chemins(i)
        if existants.contains(c) || existants.contains(url.path) { return false }
        if let nouvelle = identite(c), existants.contains(where: { identite($0)?.isEqual(nouvelle) == true }) { return false }
        ecrire(existants + [c], i)
        return true
    }

    /// Retire les doublons déjà présents dans une zone : même fichier, ou même contenu.
    static func dedoublonner(_ i: Int) {
        var gardes: [String] = []
        for chemin in chemins(i) {
            let double = gardes.contains { autre in
                if let a = identite(chemin), let b = identite(autre), a.isEqual(b) { return true }
                return FileManager.default.contentsEqual(atPath: chemin, andPath: autre)
            }
            if !double { gardes.append(chemin) }
        }
        if gardes.count != chemins(i).count { ecrire(gardes, i) }
    }

    /// Les fichiers déjà présents dans une zone (pour reconnaître une image déposée une seconde fois).
    static func fichiers(_ i: Int) -> [URL] { chemins(i).map { URL(fileURLWithPath: $0) } }
    static func retirer(_ url: URL, _ i: Int) {
        ecrire(chemins(i).filter { $0 != url.standardizedFileURL.path && $0 != url.path }, i)
    }
    static func vider(_ i: Int) { ecrire([], i) }
    /// Oublie les fichiers qui ne sont plus à l'endroit retenu (déplacés ou supprimés depuis).
    static func purger(_ i: Int) {
        let restants = chemins(i).filter { FileManager.default.fileExists(atPath: $0) }
        if restants.count != chemins(i).count { ecrire(restants, i) }
    }
}

// MARK: - Colonnes

final class Column: ObservableObject, Identifiable {
    enum Kind: Hashable {
        case hub, recents, dossiers, etagere, presse, folder(URL), tag(String)
        var code: String {
            switch self {
            case .hub: return "hub"
            case .recents: return "recents"
            case .etagere: return "etagere"
            case .dossiers: return "dossiers"
            case .presse: return "presse"
            case .tag(let nom): return "tag:" + nom
            case .folder(let u): return "folder:" + u.path
            }
        }
        init?(code: String) {
            if code == "hub" { self = .hub }
            else if code == "recents" { self = .recents }
            else if code == "etagere" { self = .etagere }
            else if code == "dossiers" { self = .dossiers }
            else if code == "presse" { self = .presse }
            else if code.hasPrefix("tag:") { self = .tag(String(code.dropFirst(4))) }
            else if code.hasPrefix("folder:") { self = .folder(URL(fileURLWithPath: String(code.dropFirst(7)))) }
            else { return nil }
        }
    }

    let id = UUID()
    let kind: Kind
    var indexEtagere = 0                     // laquelle des zones de dépôt (si c'en est une)
    @Published var pile: [URL] = []          // dossiers ouverts dans la colonne
    @Published var items: [FileItem] = []
    @Published var charge = false
    /// Présentation en colonnes : le contenu de chaque niveau, du dossier de départ au dossier ouvert.
    @Published var niveaux: [[FileItem]] = []
    private let cleVue: String
    @Published var tri: Tri {
        didSet { UserDefaults.standard.set(tri.rawValue, forKey: "tri2:" + kind.code); reload() }
    }
    @Published var presentation: Presentation {
        didSet { UserDefaults.standard.set(presentation.rawValue, forKey: cleVue); reload() }
    }
    /// Nombre de colonnes que la grille affiche en ce moment (pour les flèches haut et bas).
    var colonnesVisibles = 1
    /// Présentation en icônes : nombre de colonnes de la grille (0 = autant que la place le permet).
    @Published var colonnesGrille: Int = 0 {
        didSet { UserDefaults.standard.set(colonnesGrille, forKey: "grille:" + cleVue) }
    }
    private var generation = 0

    /// `navigateur` : la grande zone garde la même présentation d'un dossier à l'autre.
    init(kind: Kind, navigateur: Bool = false) {
        self.kind = kind
        cleVue = navigateur ? "vue:navigateur" : "vue:" + kind.code
        let d = UserDefaults.standard
        tri = d.string(forKey: "tri2:" + kind.code).flatMap(Tri.init)
            ?? (kind == .folder(Fichiers.downloads) ? .date : .nom)
        presentation = d.string(forKey: cleVue).flatMap(Presentation.init) ?? .liste
        colonnesGrille = d.integer(forKey: "grille:" + cleVue)
    }

    var racine: URL? { if case .folder(let u) = kind { return u } else { return nil } }
    var courant: URL? { pile.last ?? racine }
    var estEtagere: Bool { kind == .etagere && pile.isEmpty }
    var peutRevenir: Bool { !pile.isEmpty }
    var peutTrier: Bool { kind != .recents && courant != nil }

    var titre: String {
        if let u = pile.last { return FileManager.default.displayName(atPath: u.path) }
        switch kind {
        case .hub: return "Inbox & PARA"
        case .recents: return "Fichiers récents"
        case .etagere: return "Étagère"
        case .dossiers: return "Dossiers récents"
        case .presse: return "Presse-papiers"
        case .tag(let nom): return nom
        case .folder(let u):
            return u == Fichiers.downloads ? "Téléchargements" : FileManager.default.displayName(atPath: u.path)
        }
    }
    var symbole: String {
        if !pile.isEmpty { return "folder" }
        switch kind {
        case .hub: return "tray.full"
        case .recents: return "clock"
        case .etagere: return "tray.and.arrow.down"
        case .dossiers: return "clock.arrow.circlepath"
        case .presse: return "doc.on.clipboard"
        case .tag: return "tag"
        case .folder(let u): return u == Fichiers.downloads ? "arrow.down.circle" : "folder"
        }
    }

    private var avant: [URL] = []            // dossiers quittés avec « Précédent », pour « Suivant »
    var peutAvancer: Bool { !avant.isEmpty }
    /// Texte tapé dans « Rechercher » : ne garde que les éléments dont le nom le contient.
    @Published var filtre = "" { didSet { if filtre != oldValue { lancerRecherche() } } }
    /// Résultats de la recherche Spotlight (nil = pas de recherche en cours d'affichage).
    @Published var resultats: [FileItem]?
    @Published var rechercheEnCours = false
    private var rechercheGen = 0
    private var dernierTexte = ""
    var visibles: [FileItem] { resultats ?? items }
    func filtrer(_ liste: [FileItem]) -> [FileItem] { liste }

    /// Cherche avec Spotlight dans le dossier affiché et tous ses sous-dossiers
    /// (noms et contenu des fichiers), après une courte pause pour laisser taper.
    private func lancerRecherche() {
        rechercheGen += 1
        let g = rechercheGen, texte = filtre.trimmingCharacters(in: .whitespaces)
        guard texte.count >= 2 else { dernierTexte = ""; resultats = nil; rechercheEnCours = false; return }
        // Même texte (à un espace près) : on garde les résultats affichés, sans relancer.
        if texte == dernierTexte, resultats != nil { return }
        dernierTexte = texte
        rechercheEnCours = true
        let dossier: URL? = Config.shared.rechercheMac ? nil : (courant ?? Fichiers.home)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
            let encore = DispatchQueue.main.sync { g == self.rechercheGen }
            guard encore else { return }
            let trouves = Fichiers.chercher(texte, dans: dossier)
            DispatchQueue.main.async {
                guard g == self.rechercheGen else { return }
                self.resultats = trouves
                self.rechercheEnCours = false
            }
        }
    }

    func entrer(_ url: URL) { avant = []; filtre = ""; pile.append(url); reload() }
    func revenir() { if let u = pile.popLast() { avant.append(u) }; filtre = ""; reload() }
    func avancer() { if let u = avant.popLast() { filtre = ""; pile.append(u); reload() } }
    /// Présentation en colonnes : ouvre un dossier à partir du niveau cliqué (les niveaux suivants se referment).
    func ouvrirNiveau(_ url: URL, _ niveau: Int) { avant = []; filtre = ""; pile = Array(pile.prefix(niveau)) + [url]; reload() }
    func tronquer(_ niveau: Int) { if pile.count > niveau { pile = Array(pile.prefix(niveau)); reload() } }

    func reload() {
        generation += 1
        let g = generation
        let kind = self.kind, courant = self.courant, tri = self.tri, zoneDepot = self.indexEtagere
        let racine = self.racine, pile = self.pile, enColonnes = presentation == .colonnes
        charge = items.isEmpty
        DispatchQueue.global(qos: .userInitiated).async {
            func depart() -> [FileItem] {
                if let racine { return Fichiers.contenu(racine, tri: tri) }
                switch kind {
                case .recents: return Fichiers.recents()
                case .etagere: return Etagere.items(zoneDepot)
                case .dossiers: return Fichiers.dossiersRecents()
                case .tag(let nom): return Fichiers.avecTag(nom)
                case .presse: return []
                default: return Fichiers.para()
                }
            }
            let resultat = courant.map { Fichiers.contenu($0, tri: tri) } ?? depart()
            let niveaux = enColonnes ? [pile.isEmpty ? resultat : depart()] + pile.map { Fichiers.contenu($0, tri: tri) } : []
            DispatchQueue.main.async {
                guard g == self.generation else { return }
                self.items = resultat
                self.niveaux = niveaux
                self.charge = false
            }
        }
    }
}

final class Store: ObservableObject {
    @Published var columns: [Column] = []
    @Published var largeurMax: CGFloat = 1400   // largeur disponible sur l'écran de la carte
    @Published var margeHaut: CGFloat = 0   // place laissée à l'encoche de l'écran
    private let cle = "colonnes"

    /// Barre latérale : les favoris, le dossier affiché dans la grande zone, et l'étagère.
    @Published var favoris: [URL] = []
    /// Les onglets de la grande zone, comme dans le Finder. `navigateur` est l'onglet affiché.
    @Published var onglets: [Column] = [Column(kind: .recents, navigateur: true)]
    @Published var ongletActif = 0
    var navigateur: Column {
        get { onglets[min(ongletActif, onglets.count - 1)] }
        set { onglets[min(ongletActif, onglets.count - 1)] = newValue }
    }
    var courante: Column.Kind { navigateur.kind }

    func nouvelOnglet() {
        let ici = navigateur.courant.map { Column.Kind.folder($0) } ?? navigateur.kind
        let c = Column(kind: ici, navigateur: true)
        onglets.append(c)
        ongletActif = onglets.count - 1
        c.reload()
    }
    func fermerOnglet(_ i: Int) {
        guard onglets.count > 1, onglets.indices.contains(i) else { return }
        onglets.remove(at: i)
        if ongletActif >= i { ongletActif = max(0, ongletActif - 1) }
    }
    @Published var etageres: [Column] = Store.zones()
    /// Un glisser-déposer est en cours : c'est le moment de montrer les cibles de dépôt.
    @Published var glisse = false
    /// Le panneau des applications est ouvert, sous le mini-Dock.
    @Published var lanceurOuvert = false
    /// Largeur du mini-Dock, pour que le panneau des applications ait la même.
    @Published var largeurDock: CGFloat = 0
    /// L'icône du mini-Dock qu'on est en train de glisser : elle n'est plus affichée dans le mini-Dock.
    @Published var appEnGlisse: URL?
    /// Présentation de bienvenue : numéro de l'étape affichée par-dessus la carte (nil = pas de présentation).
    @Published var accueil: Int?
    func finAccueil() {
        accueil = nil
        UserDefaults.standard.set(true, forKey: "accueilVu")
    }
    /// Ce qu'on fait glisser contient un dossier (ou une entrée de la barre latérale) : on peut l'épingler en colonne.
    @Published var glisseDossier = false
    /// Au moins une zone de dépôt contient quelque chose : elle reste alors affichée, en petit.
    @Published var depotRempli = false
    /// Il y a de la place à droite de la carte : les zones de dépôt y flottent, en carrés.
    /// Sinon (carte en pleine largeur, ou sur le côté), elles s'affichent dans la grande zone.
    @Published var depotDehors = false
    @Published var depotAGauche = false
    private var suiviZones: [AnyCancellable] = []

    func surveillerZones() {
        suiviZones = etageres.map { zone in
            zone.$items.receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                let rempli = self.etageres.contains { !$0.items.isEmpty }
                if rempli != self.depotRempli { self.depotRempli = rempli }
            }
        }
    }

    private static func zones() -> [Column] {
        (0..<Etagere.nombre).map { i in
            let c = Column(kind: .etagere)
            c.indexEtagere = i
            return c
        }
    }
    func ajouterZone() {
        guard Etagere.nombre < Etagere.maximum else { return }
        Etagere.nombre += 1
        etageres = Store.zones()
        surveillerZones()
        etageres.forEach { $0.reload() }
    }
    /// Retire les zones de dépôt vides, en en gardant toujours au moins une.
    func nettoyerZones() {
        var change = false
        for i in stride(from: etageres.count - 1, through: 0, by: -1)
        where Etagere.nombre > 1 && Etagere.items(i).isEmpty {
            Etagere.supprimer(i)
            change = true
        }
        guard change else { return }
        etageres = Store.zones()
        surveillerZones()
        etageres.forEach { $0.reload() }
    }
    func supprimerZone(_ i: Int) {
        Etagere.supprimer(i)
        etageres = Store.zones()
        surveillerZones()
        etageres.forEach { $0.reload() }
    }

    init() {
        let d = UserDefaults.standard
        favoris = d.stringArray(forKey: "favoris")?.map { URL(fileURLWithPath: $0) }
            ?? Fichiers.para().map(\.url) + [Fichiers.downloads]
        // À droite : des dossiers, ou des entrées de la barre latérale qu'on a choisi d'épingler.
        var kinds = (d.stringArray(forKey: cle) ?? []).compactMap { Column.Kind(code: $0) }
        kinds = kinds.filter { $0 != .etagere && $0 != .hub }
        if !d.bool(forKey: "migrationFinder") {   // une fois : pas de doublon avec les favoris
            d.set(true, forKey: "migrationFinder")
            kinds.removeAll { k in favoris.contains { .folder($0) == k } }
            d.set(kinds.map(\.code), forKey: cle)
        }
        columns = kinds.map { Column(kind: $0) }
        let depart = Config.shared.ouverture.isEmpty
            ? d.string(forKey: "dernier").flatMap { Column.Kind(code: $0) } ?? .recents
            : .folder(URL(fileURLWithPath: Config.shared.ouverture))
        let premier = Column(kind: depart, navigateur: true)
        // « Le dernier dossier consulté » : on retrouve aussi les sous-dossiers où l'on était entré.
        if Config.shared.ouverture.isEmpty {
            premier.pile = (d.stringArray(forKey: "dernierChemin") ?? []).map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        onglets = [premier]
        surveillerZones()
    }

    /// Affiche un dossier (ou les récents) dans la grande zone.
    func naviguer(_ kind: Column.Kind) {
        navigateur = Column(kind: kind, navigateur: true)
        navigateur.reload()
        UserDefaults.standard.set(kind.code, forKey: "dernier")
    }
    /// Retient où l'on se trouve, pour le retrouver au prochain lancement de Side.
    func memoriser() {
        UserDefaults.standard.set(navigateur.kind.code, forKey: "dernier")
        UserDefaults.standard.set(navigateur.pile.map(\.path), forKey: "dernierChemin")
    }
    func ajouterFavori(_ url: URL) {
        let u = url.standardizedFileURL
        guard !favoris.contains(where: { $0.standardizedFileURL == u }) else { return }
        favoris.append(u)
        UserDefaults.standard.set(favoris.map(\.path), forKey: "favoris")
    }
    func retirerFavori(_ url: URL) {
        favoris.removeAll { $0 == url }
        UserDefaults.standard.set(favoris.map(\.path), forKey: "favoris")
    }

    func contient(_ kind: Column.Kind) -> Bool { columns.contains { $0.kind == kind } }

    func ajouter(_ kind: Column.Kind) {
        guard !contient(kind) else { return }
        let c = Column(kind: kind)
        columns.append(c)
        c.reload()
        sauver()
    }
    func retirer(_ column: Column) {
        columns.removeAll { $0.id == column.id }
        sauver()
    }
    var glissee: Column?   // colonne en cours de déplacement

    func deplacer(_ colonne: Column, vers cible: Column) {
        guard let de = columns.firstIndex(where: { $0.id == colonne.id }),
              let vers = columns.firstIndex(where: { $0.id == cible.id }), de != vers else { return }
        columns.move(fromOffsets: IndexSet(integer: de), toOffset: vers > de ? vers + 1 : vers)
        sauver()
    }
    func reloadAll() { (columns + onglets + etageres).forEach { $0.reload() } }
    private func sauver() { UserDefaults.standard.set(columns.map(\.kind.code), forKey: cle) }
}

// MARK: - Interface

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct DrawerView: View {
    @ObservedObject var store: Store
    @ObservedObject var config = Config.shared
    @State private var depotAjout = false

    var body: some View {
        // Autour de la carte : le mini-Dock (du côté choisi dans les réglages) et les zones de dépôt
        // flottantes (à droite, ou à gauche si la carte est collée à droite).
        let p = config.apps ? config.dockPosition : ""
        HStack(alignment: .top, spacing: 8) {
            // Le mini-Dock passe devant la carte : la liste du presse-papiers se déroule par-dessus elle.
            if p == "gauche" { AppsView(vertical: true).zIndex(1) }
            VStack(spacing: 8) {
                if p == "haut" { AppsView(vertical: false).zIndex(1) }
                carte
                if p == "bas" { AppsView(vertical: false).zIndex(1) }
            }
            if p == "droite" { AppsView(vertical: true).zIndex(1) }
        }
    }

    private var carte: some View {
        GeometryReader { geo in
                let barre: CGFloat = 210
                let fixes = barre + 10
                // La grande zone garde la largeur qu'elle a sans colonne épinglée.
                let zone = max(300, min(Disposition.base(store.largeurMax), geo.size.width) - fixes)
                let largeur = Disposition.colonne(store.columns.count, store.largeurMax)
                // Glisser le trait à droite de la grande zone partage la place entre elle et les colonnes épinglées :
                // ce que gagne l'une, les autres le perdent, et la carte garde sa largeur.
                // (Sans colonne épinglée, ce trait est le bord de la carte : il change alors sa largeur.)
                let n = store.columns.count
                let reglage = Binding<Double>(
                    get: { Double(zone) },
                    set: { nouvelle in
                        let ecart = CGFloat(nouvelle) - zone
                        if n > 0 {
                            let col = CGFloat(config.tailleColonne) - ecart / CGFloat(n)
                            guard col >= 160 else { return }   // une colonne épinglée garde une largeur lisible
                            config.tailleColonne = Double(col)
                        }
                        config.largeurSeule = Double((CGFloat(nouvelle) + fixes) / max(store.largeurMax, 1))
                    })
                HStack(spacing: 0) {
                    SidebarView(store: store).frame(width: barre)
                    Divider()
                    // La zone de dépôt n'occupe plus de colonne : elle apparaît par-dessus la grande zone
                    // pendant un glisser-déposer, puis reste en fine bande tant qu'elle contient des fichiers.
                    ZStack(alignment: .trailing) {
                        ColumnView(column: store.navigateur, store: store, large: zone > 430, fixe: true)
                            .id(store.navigateur.id)
                            .padding(.trailing, store.depotRempli && !store.depotDehors ? ZonesView.bande + 12 : 0)
                        if !store.depotDehors && (store.glisse || store.depotRempli) {
                            ZonesView(store: store, etendu: store.glisse)
                                .padding(6)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(width: zone)
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.glisse)
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.depotRempli)
                    Poignee(valeur: reglage, mini: 300, maxi: store.largeurMax - fixes)
                    if !store.columns.isEmpty {
                        ScrollView(.horizontal, showsIndicators: !config.ajuster) {
                            HStack(spacing: 0) {
                                ForEach(store.columns) { column in
                                    ColumnView(column: column, store: store, large: largeur > 430,
                                               dernier: column.id == store.columns.last?.id)
                                        .frame(width: largeur)
                                    Divider()
                                }
                            }
                            .frame(height: geo.size.height)
                        }
                    }
                }
                // Le bord droit de la carte devient une cible pendant un glisser : y déposer un dossier l'épingle.
                .overlay(alignment: .trailing) {
                    if store.glisse && store.glisseDossier {
                        BordEpingle().transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.glisse)
        }
        .padding(.top, store.margeHaut)
        .background(ZStack {
            VisualEffect()
            Color(nsColor: .windowBackgroundColor).opacity(config.opacite)
            // La barre latérale reste translucide ; le contenu, à sa droite, est blanc comme dans le Finder.
            HStack(spacing: 0) {
                Color.clear.frame(width: 211)
                Color(nsColor: .textBackgroundColor)
            }
        })
        .overlay {
            if let etape = store.accueil {
                AccueilView(store: store, etape: etape).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.accueil)
        .clipShape(forme)
        .overlay(forme.strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
    }

    private var boutonAjout: some View {
        Button { AppDelegate.shared.choisirDossier() } label: {
            Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(depotAjout ? Color.accentColor.opacity(0.35) : .clear).padding(4))
        // Déposer un dossier ici crée une colonne avec son contenu.
        .onDrop(of: [UTType.fileURL, UTType.utf8PlainText], isTargeted: $depotAjout) { fournisseurs in
            AppDelegate.shared.epingler(fournisseurs)
            return true
        }
        .help("Épingler un dossier en colonne (clique, ou dépose un dossier ici)")
        .accessibilityLabel("Épingler un dossier en colonne")
    }

    /// Une carte flottante : les quatre coins sont arrondis.
    private var forme: RoundedRectangle { RoundedRectangle(cornerRadius: Reglages.rayonCarte, style: .continuous) }
}

/// La barre d'onglets de la grande zone (affichée dès qu'il y en a deux).
/// La présentation de bienvenue : cinq bulles posées sur la carte, qui montrent chacune une partie de Side.
struct AccueilView: View {
    @ObservedObject var store: Store
    @ObservedObject var config = Config.shared
    let etape: Int
    static let nombre = 5

    var body: some View {
        GeometryReader { geo in
            let l = geo.size.width, h = geo.size.height
            let zone = max(300, min(Disposition.base(store.largeurMax), l) - 220)
            // La partie de la carte mise en lumière, et l'endroit où poser la bulle.
            let cible: CGRect? = [nil,
                                  CGRect(x: 0, y: 0, width: 211, height: h),
                                  CGRect(x: 211, y: 0, width: zone, height: h),
                                  nil,   // la zone de dépôt flotte à côté de la carte : elle s'affiche pour de vrai
                                  nil][min(etape, 4)]
            let x: CGFloat = [l / 2, 211 + 170, 211 + zone / 2, l - 170, l / 2][min(etape, 4)]
            let y: CGFloat = etape == 2 ? h * 0.6 : h / 2
            ZStack(alignment: .topLeading) {
                // Un voile sombre, troué à l'endroit qu'on montre.
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    if let c = cible { p.addRoundedRect(in: c.insetBy(dx: 5, dy: 5), cornerSize: CGSize(width: 12, height: 12)) }
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                if let c = cible {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .frame(width: c.width - 10, height: c.height - 10)
                        .offset(x: c.minX + 5, y: c.minY + 5)
                }
                bulle
                    .frame(width: 290)
                    .position(x: min(max(x, 160), l - 160), y: y)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {}   // les clics ne traversent pas le voile
    }

    private var bulle: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<Self.nombre, id: \.self) { i in
                    Capsule().fill(i == etape ? Color.accentColor : Color.primary.opacity(0.18))
                        .frame(width: i == etape ? 18 : 6, height: 6)
                }
                Spacer()
                Text("\(etape + 1) sur \(Self.nombre)").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(titre).font(.title3.weight(.semibold))
                Spacer()
                // Une flèche montre où regarder : la zone de dépôt à droite, le mini-Dock autour de la carte.
                if let fleche { Image(systemName: fleche).font(.title2.weight(.bold)).foregroundStyle(Color.accentColor) }
            }
            contenu.font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            HStack {
                if etape < Self.nombre - 1 {
                    Button("Passer") { store.finAccueil() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer()
                if etape == 0 || etape == Self.nombre - 1 {
                    Button(etape == 0 ? "Changer…" : "Réglages…") {
                        if etape > 0 { store.finAccueil() }
                        AppDelegate.shared.ouvrirReglages()
                    }
                }
                Button(etape < Self.nombre - 1 ? "Suivant" : "Terminer") {
                    if etape < Self.nombre - 1 { store.accueil = etape + 1 } else { store.finAccueil() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
    }

    private var titre: String {
        ["Bienvenue dans Side", "Tes dossiers", "Tes fichiers", "La zone de dépôt", "Tes apps"][min(etape, 4)]
    }

    private var fleche: String? {
        if etape == 3 { return "arrow.right" }
        guard etape == 4, config.apps else { return nil }
        return ["haut": "arrow.up", "bas": "arrow.down", "gauche": "arrow.left", "droite": "arrow.right"][config.dockPosition]
    }

    private func geste(_ symbole: String, _ texte: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbole).foregroundStyle(Color.accentColor).frame(width: 20)
            Text(texte)
        }
    }

    @ViewBuilder private var contenu: some View {
        switch etape {
        case 0:
            VStack(alignment: .leading, spacing: 7) {
                Text("Pour l'ouvrir et le fermer :").foregroundStyle(.secondary)
                if config.coin != .aucun { geste("arrow.up.left.and.arrow.down.right", "Le coin " + config.coin.titre.lowercased()) }
                if config.secouer {
                    geste("cursorarrow.motionlines", config.cercle ? "Un cercle avec la souris" : "Une secousse de souris")
                }
                if config.touche != -1 { geste("keyboard", config.libelle) }
            }
        case 1:
            Text("Glisse un dossier sur « Favoris » pour l'ajouter.")
        case 2:
            VStack(alignment: .leading, spacing: 7) {
                geste("space", "Espace : aperçu")
                geste("cursorarrow.click.2", "Double-clic : ouvrir")
            }
        case 3:
            Text("Glisse un fichier : elle apparaît ici. Ce que tu y poses reste sous la main, même Side fermé.")
        default:
            VStack(alignment: .leading, spacing: 7) {
                if config.apps { geste("dock.rectangle", "Le mini-Dock lance tes apps") }
                geste("menubar.arrow.up.rectangle", "Réglages : icône Side, barre des menus")
            }
        }
    }
}

struct OngletsView: View {
    @ObservedObject var store: Store

    var body: some View {
        if store.onglets.count > 1 {
            HStack(spacing: 4) {
                ForEach(Array(store.onglets.enumerated()), id: \.element.id) { i, onglet in
                    OngletView(column: onglet, actif: i == store.ongletActif,
                               choisir: { store.ongletActif = i }, fermer: { store.fermerOnglet(i) })
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

struct OngletView: View {
    @ObservedObject var column: Column
    let actif: Bool
    let choisir: () -> Void
    let fermer: () -> Void
    @State private var survol = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: fermer) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.primary.opacity(0.12)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(survol ? 1 : 0)
            .help("Fermer l'onglet")
            .accessibilityLabel("Fermer l'onglet")
            Text(column.titre).font(.callout).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity)
            Color.clear.frame(width: 16, height: 16)
        }
        .foregroundStyle(actif ? Color.primary : Color.secondary)
        .padding(.horizontal, 6)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Color.primary.opacity(actif ? 0.16 : (survol ? 0.09 : 0.05))))
        .contentShape(Capsule())
        .onHover { survol = $0 }
        .onTapGesture(perform: choisir)
        .accessibilityAddTraits(actif ? [.isButton, .isSelected] : .isButton)
    }
}

/// Une icône du mini-Dock.
struct AppItem: Identifiable, Equatable {
    let url: URL
    let nom: String
    let ouverte: Bool
    let active: Bool
    let favori: Bool
    var id: String { url.path }
}

extension AppItem {
    /// Une favorite quitte les favorites ; une app simplement ouverte est masquée.
    func retirer() {
        let c = Config.shared
        if favori { c.appsFavorites.removeAll { $0 == url.path } }
        else if !c.appsMasquees.contains(url.path) { c.appsMasquees.append(url.path) }
    }
}

/// Les apps ouvertes (celles qui ont une icône dans le Dock), tenues à jour.
final class Apps: ObservableObject {
    static let shared = Apps()
    @Published var liste: [NSRunningApplication] = []
    @Published var active: pid_t = 0

    private init() {
        let centre = NSWorkspace.shared.notificationCenter
        for nom in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                    NSWorkspace.didActivateApplicationNotification] {
            centre.addObserver(forName: nom, object: nil, queue: .main) { [weak self] _ in self?.rafraichir() }
        }
        rafraichir()
    }

    func rafraichir() {
        liste = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        active = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    }

    /// Ce que le mini-Dock affiche : d'abord les favorites, puis les apps ouvertes (sauf les masquées).
    func elements(_ c: Config) -> [AppItem] {
        var vus = Set<String>(), resultat: [AppItem] = []
        let enCours = liste.compactMap { app in app.bundleURL.map { ($0.standardizedFileURL.path, app) } }
        if c.appsFavoris {
            for chemin in c.appsFavorites where FileManager.default.fileExists(atPath: chemin) && vus.insert(chemin).inserted {
                let app = enCours.first { $0.0 == chemin }?.1
                let nom = FileManager.default.displayName(atPath: chemin).replacingOccurrences(of: ".app", with: "")
                resultat.append(AppItem(url: URL(fileURLWithPath: chemin), nom: nom, ouverte: app != nil,
                                        active: app?.processIdentifier == active, favori: true))
            }
        }
        if c.appsOuvertes {
            for (chemin, app) in enCours where !c.appsMasquees.contains(chemin) && vus.insert(chemin).inserted {
                resultat.append(AppItem(url: URL(fileURLWithPath: chemin), nom: app.localizedName ?? "App", ouverte: true,
                                        active: app.processIdentifier == active, favori: false))
            }
        }
        return resultat
    }
}

/// Le mini-Dock : une pastille flottante avec les apps ouvertes et/ou favorites, puis les raccourcis.
/// Les icônes grossissent en douceur à l'approche du pointeur, comme dans le Dock de macOS.
/// Un clic passe à l'app ; déposer un fichier sur une icône l'ouvre avec cette app ;
/// déposer une app sur la pastille l'ajoute aux favorites.
struct AppsView: View {
    @ObservedObject var apps = Apps.shared
    @ObservedObject var config = Config.shared
    @ObservedObject var store = AppDelegate.shared.store
    let vertical: Bool

    var body: some View {
        // La liste des apps n'est recalculée que lorsqu'une app s'ouvre, se ferme ou qu'un réglage change.
        // L'icône qu'on glisse quitte le mini-Dock : elle est sous la souris, pas en double.
        RangeeDock(items: apps.elements(config).filter { $0.url != store.appEnGlisse }, vertical: vertical)
    }
}

/// Les icônes d'apps, gardées en mémoire : les relire à chaque mouvement de souris faisait saccader.
enum Icones {
    private static let cache = NSCache<NSString, NSImage>()
    /// Une icône à la taille d'une ligne de menu.
    static func petite(_ chemin: String) -> NSImage {
        let image = de(chemin).copy() as? NSImage ?? de(chemin)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
    static func de(_ chemin: String) -> NSImage {
        if let image = cache.object(forKey: chemin as NSString) { return image }
        let image = NSWorkspace.shared.icon(forFile: chemin)
        cache.setObject(image, forKey: chemin as NSString)
        return image
    }
}

/// La rangée d'icônes du mini-Dock. Volontairement simple : rien ne bouge sauf l'icône survolée,
/// qui grossit un peu avec l'animation standard de macOS.
struct RangeeDock: View {
    let items: [AppItem]
    @ObservedObject var config = Config.shared
    let vertical: Bool
    @State private var cible = false

    var body: some View {
        let t = CGFloat(config.tailleDock)
        let epaisseur = Disposition.dock - 8
        let forme = RoundedRectangle(cornerRadius: min(22, epaisseur / 2.6), style: .continuous)
        let contenu = Group {
            // Tout à gauche : le bouton « Apps », puis un trait.
            if config.lanceur {
                LanceurIcone(taille: t)
                if vertical { Divider().frame(width: t * 0.7) } else { Divider().frame(height: t * 0.7) }
            }
            ForEach(items) { item in
                AppIcone(item: item, taille: t)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))   // apparition / disparition animée
            }
            if items.isEmpty {
                Image(systemName: "plus.app").font(.system(size: t * 0.6)).foregroundStyle(.secondary)
                    .frame(width: t, height: t)
                    .help("Dépose une app ici pour l'ajouter au mini-Dock")
            }
            // Après un séparateur : les raccourcis macOS choisis dans les réglages.
            if !config.raccourcis.isEmpty {
                if vertical { Divider().frame(width: t * 0.7) } else { Divider().frame(height: t * 0.7) }
                ForEach(config.raccourcis, id: \.self) { nom in
                    RaccourciIcone(nom: nom, taille: t)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            // Tout au bout : le presse-papiers, dont la liste se déroule au survol.
            if config.historique {
                if vertical { Divider().frame(width: t * 0.7) } else { Divider().frame(height: t * 0.7) }
                PresseIcone(taille: t)
            }
        }
        Group {
            if vertical { VStack(spacing: 6) { contenu }.padding(6) }
            else { HStack(spacing: 6) { contenu }.padding(6) }
        }
        .background(ZStack {
            VisualEffect()
            Color(nsColor: .windowBackgroundColor).opacity(config.opacite)
        }.clipShape(forme))
        .overlay(forme.strokeBorder(cible ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: cible ? 2 : 1))
        .onDrop(of: [UTType.fileURL], isTargeted: $cible) { fournisseurs in
            AppDelegate.shared.ajouterApps(fournisseurs)
            return true
        }
        .contextMenu { Button("Masquer le mini-Dock") { config.apps = false } }
        // Side retient la place exacte du mini-Dock : un clic juste à côté de lui compte comme un clic en dehors.
        .background(Repere(dock: true))
        .background(GeometryReader { g in
            Color.clear
                .onAppear { AppDelegate.shared.store.largeurDock = vertical ? 0 : g.size.width }
                .onChange(of: g.size.width) { _, l in AppDelegate.shared.store.largeurDock = vertical ? 0 : l }
        })
        .frame(maxWidth: vertical ? nil : .infinity, maxHeight: vertical ? .infinity : nil)
        .animation(.smooth(duration: 0.3), value: items)
        .animation(.smooth(duration: 0.3), value: config.raccourcis)
        .accessibilityLabel("Mini-Dock")
    }
}

/// L'effet de survol commun aux icônes du mini-Dock : un léger grossissement, animé par macOS.
struct SurvolDock: ViewModifier {
    @State private var survol = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(survol ? 1.16 : 1)
            .animation(.snappy(duration: 0.18), value: survol)
            .onHover { survol = $0 }
    }
}

/// La petite croix dans un cercle, en haut à gauche d'une icône, comme sur iOS : elle la retire du mini-Dock.
/// Un raccourci macOS dans le mini-Dock : une tuile colorée avec ses initiales.
/// Un clic le lance ; déposer des fichiers dessus le lance avec ces fichiers en entrée.
/// Un repère invisible : la vue qui le porte (mini-Dock, panneau) compte comme une partie de Side pour les clics.
struct Repere: NSViewRepresentable {
    var lanceur = false   // le panneau des applications : un clic hors de lui le referme
    var dock = false      // le mini-Dock : sert à savoir si une icône glissée en est sortie
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        AppDelegate.shared.reperes.add(v)
        if lanceur { AppDelegate.shared.vueLanceur = v }
        if dock { AppDelegate.shared.vueDock = v }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

/// Toutes les applications installées, lues une fois (puis relues à chaque ouverture du panneau, en arrière-plan).
final class Applis: ObservableObject {
    static let shared = Applis()
    struct Appli: Identifiable, Hashable { let url: URL; let nom: String; var id: URL { url } }
    @Published var toutes: [Appli] = []
    private var enCours = false

    func charger() {
        guard !enCours else { return }
        enCours = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let racines = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                           fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
            var vues = Set<String>(), liste: [Appli] = []
            func ajouter(_ u: URL) {
                let chemin = u.resolvingSymlinksInPath().path
                guard u.pathExtension == "app", vues.insert(chemin).inserted else { return }
                liste.append(Appli(url: u, nom: fm.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")))
            }
            for racine in racines {
                let contenu = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: racine), includingPropertiesForKeys: [.isDirectoryKey],
                                                           options: [.skipsHiddenFiles])) ?? []
                for u in contenu {
                    if u.pathExtension == "app" { ajouter(u); continue }
                    // Un dossier d'éditeur (« Adobe… », « Microsoft… ») : on regarde aussi dedans.
                    if (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true, u.lastPathComponent != "Utilities" {
                        ((try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []).forEach(ajouter)
                    }
                }
            }
            liste.sort { $0.nom.localizedStandardCompare($1.nom) == .orderedAscending }
            DispatchQueue.main.async { self.toutes = liste; self.enCours = false }
        }
    }

    /// Les apps dont le nom contient le texte ; celles dont le nom commence par lui d'abord.
    func filtrer(_ texte: String) -> [Appli] {
        let t = texte.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return toutes }
        let trouvees = toutes.filter { $0.nom.localizedStandardContains(t) }
        let debut = trouvees.filter { $0.nom.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .hasPrefix(t.lowercased().folding(options: .diacriticInsensitive, locale: nil)) }
        return debut + trouvees.filter { !debut.contains($0) }
    }
}

/// Le bouton « Apps », tout à gauche du mini-Dock : un clic ouvre la liste de toutes les applications.
struct LanceurIcone: View {
    let taille: CGFloat
    @ObservedObject var store = AppDelegate.shared.store

    private static let icone: NSImage = {
        let apps = "/System/Applications/Apps.app"
        return NSWorkspace.shared.icon(forFile: FileManager.default.fileExists(atPath: apps) ? apps : "/Applications")
    }()

    var body: some View {
        let cote = Config.shared.dockPosition
        // Le panneau part de l'icône : vers le bas si le mini-Dock est en haut, vers le haut s'il est en bas…
        let ancre: Alignment = ["haut": .topLeading, "bas": .bottomLeading, "gauche": .topLeading, "droite": .topTrailing][cote] ?? .topLeading
        let pointDepart: UnitPoint = ["haut": .topLeading, "bas": .bottomLeading, "gauche": .topLeading, "droite": .topTrailing][cote] ?? .topLeading
        let ecart = taille + 16
        let ouvert = store.lanceurOuvert || ProcessInfo.processInfo.arguments.contains("--lanceur")
        Image(nsImage: Self.icone)
            .resizable().frame(width: taille, height: taille)
            .modifier(SurvolDock())
            .contentShape(Rectangle())
            .onTapGesture { store.lanceurOuvert.toggle() }
            .contextMenu {
                Button("Masquer le bouton Apps") { store.lanceurOuvert = false; Config.shared.lanceur = false }
            }
            .overlay(alignment: ancre) {
                if ouvert {
                    LanceurPanneau { store.lanceurOuvert = false }
                        .offset(x: cote == "gauche" ? ecart : (cote == "droite" ? -ecart : -6),
                                y: cote == "haut" ? ecart : (cote == "bas" ? -ecart : -6))
                        .transition(.scale(scale: 0.15, anchor: pointDepart).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: store.lanceurOuvert)
            .help("Toutes les applications")
            .accessibilityLabel("Toutes les applications")
            .accessibilityAddTraits(.isButton)
    }
}

/// Le panneau des applications : une recherche déjà prête à taper, et la grille des apps.
/// Entrée lance la première trouvée. On peut aussi glisser une app vers le mini-Dock pour l'y garder.
struct LanceurPanneau: View {
    let fermer: () -> Void
    @ObservedObject var applis = Applis.shared
    @ObservedObject var store = AppDelegate.shared.store
    @State private var texte = ""
    @FocusState private var champ: Bool

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let trouvees = applis.filtrer(texte)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher une app", text: $texte)
                    .textFieldStyle(.plain).focused($champ)
                    .onSubmit { if let premiere = trouvees.first { lancer(premiere) } }
                    .onExitCommand { fermer() }
                if !texte.isEmpty {
                    Button { texte = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Effacer la recherche")
                }
            }
            .padding(.horizontal, 9).frame(height: 26)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .padding(8)
            Divider()
            if trouvees.isEmpty {
                Text(applis.toutes.isEmpty ? "Chargement…" : "Aucune app").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 4)], spacing: 6) {
                        ForEach(Array(trouvees.enumerated()), id: \.element.id) { rang, app in
                            CaseAppli(app: app, premiere: rang == 0 && !texte.isEmpty) { lancer(app) }
                        }
                    }
                    .padding(10)
                }
            }
        }
        // Aussi large que le mini-Dock, sans descendre sous 330 points.
        .frame(width: max(330, store.largeurDock), height: 300)
        .background(Repere(lanceur: true))
        .background(ZStack { VisualEffect(); Color(nsColor: .windowBackgroundColor).opacity(0.55) })
        .clipShape(forme)
        .overlay(forme.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
        .onAppear {
            applis.charger()
            DispatchQueue.main.async { champ = true }
        }
        .onTapGesture {}   // un clic dans le panneau ne le referme pas
    }

    private func lancer(_ app: Applis.Appli) {
        fermer()
        AppDelegate.shared.allerA(app.url)
    }
}

/// Une app dans la grille : un clic la lance ; glissée sur le mini-Dock, elle y reste.
struct CaseAppli: View {
    let app: Applis.Appli
    let premiere: Bool   // celle qu'Entrée lancera
    let action: () -> Void
    @State private var survol = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: Icones.de(app.url.path)).resizable().frame(width: 38, height: 38)
            Text(app.nom).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .top)
        }
        .padding(.vertical, 6).padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: 10).fill(
            premiere ? Selection.bleu.opacity(0.22) : (survol ? Color.primary.opacity(0.08) : .clear)))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture(perform: action)
        .onDrag { NSItemProvider(object: app.url as NSURL) }
        .help(app.nom)
        .accessibilityLabel(app.nom)
        .accessibilityAddTraits(.isButton)
    }
}

/// Le presse-papiers dans le mini-Dock : passer la souris dessus déroule l'historique,
/// un clic sur une ligne la recopie. Aucun clic pour regarder, un seul pour reprendre.
struct PresseIcone: View {
    let taille: CGFloat
    @ObservedObject var config = Config.shared
    @ObservedObject var presse = PressePapiers.shared
    @State private var surIcone = false
    @State private var surListe = false
    @State private var ouvert = false
    @State private var filtre = ""

    var body: some View {
        let cote = config.dockPosition
        // La liste se déroule vers la carte : sous le Dock s'il est en haut, au-dessus s'il est en bas…
        let ancre: Alignment = ["haut": .top, "bas": .bottom, "gauche": .bottomLeading, "droite": .bottomTrailing][cote] ?? .top
        let ecart = taille + 14
        ZStack {
            RoundedRectangle(cornerRadius: taille * 0.24, style: .continuous)
                .fill(Color.primary.opacity(ouvert ? 0.22 : 0.12))
                .padding(taille * 0.06)
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: taille * 0.42, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(width: taille, height: taille)
        .modifier(SurvolDock())
        .contentShape(Rectangle())
        .onHover { surIcone = $0; suivre() }
        .onTapGesture { ouvert.toggle() }
        .overlay(alignment: ancre) {
            if ouvert || ProcessInfo.processInfo.arguments.contains("--presse") {
                PresseListe(filtre: $filtre) { fermer() }
                    .onHover { surListe = $0; suivre() }
                    .offset(x: cote == "gauche" ? ecart : (cote == "droite" ? -ecart : 0),
                            y: cote == "haut" ? ecart : (cote == "bas" ? -ecart : 0))
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: cote == "bas" ? .bottom : .top)))
            }
        }
        .animation(.snappy(duration: 0.12), value: ouvert)
        .help("Presse-papiers")
        .accessibilityLabel("Historique du presse-papiers")
        .accessibilityAddTraits(.isButton)
    }

    private func fermer() { ouvert = false; filtre = "" }

    /// La liste s'ouvre dès que la souris arrive sur l'icône. À la sortie, un court délai laisse
    /// le temps d'aller de l'icône à la liste sans qu'elle se referme.
    private func suivre() {
        if surIcone || surListe { ouvert = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if !surIcone && !surListe && filtre.isEmpty { ouvert = false }
        }
    }
}

/// La liste déroulée : une recherche (seulement quand l'historique est long) et les éléments copiés.
struct PresseListe: View {
    @Binding var filtre: String
    let fermer: () -> Void
    @ObservedObject var presse = PressePapiers.shared
    @State private var recherche = false
    @FocusState private var champ: Bool

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if recherche {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Rechercher", text: $filtre).textFieldStyle(.plain).focused($champ)
                    Button { filtre = ""; recherche = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Fermer la recherche")
                } else {
                    Text("Presse-papiers · 7 jours").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    // La petite loupe : un clic ouvre le champ de recherche.
                    Button { recherche = true; champ = true } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(0.09)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain).help("Rechercher dans le presse-papiers").accessibilityLabel("Rechercher dans le presse-papiers")
                }
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(recherche ? Color.primary.opacity(0.06) : Color.clear)
            PressePapiersView(filtre: filtre, apresCopie: fermer)
        }
        .frame(width: 320, height: min(400, max(120, CGFloat(presse.elements.count) * 52 + 44)))
        .background(Repere())
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(forme)
        .overlay(forme.strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        .onDisappear { recherche = false }
    }
}

struct RaccourciIcone: View {
    let nom: String
    let taille: CGFloat
    @ObservedObject var raccourcis = Raccourcis.shared
    @State private var cible = false

    /// Les initiales des deux premiers mots, et une couleur toujours la même pour un nom donné.
    private var initiales: String {
        let mots = nom.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let lettres = mots.prefix(2).compactMap(\.first).map(String.init).joined()
        return (lettres.isEmpty ? String(nom.prefix(1)) : lettres).uppercased()
    }
    private var couleur: Color {
        let teinte = nom.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }
        return Color(hue: Double(teinte) / 360, saturation: 0.62, brightness: 0.82)
    }

    var body: some View {
        let actif = raccourcis.enCours == nom
        ZStack {
            RoundedRectangle(cornerRadius: taille * 0.24, style: .continuous).fill(couleur.gradient)
                .padding(taille * 0.06)
            if actif {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Text(initiales)
                    .font(.system(size: taille * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: taille, height: taille)
        .modifier(SurvolDock())
        .background(Circle().fill(Color.accentColor.opacity(cible ? 0.45 : 0)).padding(-3))
        .contentShape(Rectangle())
        .onTapGesture { AppDelegate.shared.lancerRaccourci(nom, []) }
        .onDrop(of: [UTType.fileURL], isTargeted: $cible) { fournisseurs in
            AppDelegate.shared.lancerRaccourci(nom, fournisseurs)
            return true
        }
        .contextMenu { Button("Retirer du mini-Dock") { Config.shared.raccourcis.removeAll { $0 == nom } } }
        .help("Raccourci « \(nom) ». Dépose un fichier pour le lui passer.")
        .accessibilityLabel("Raccourci \(nom)")
        .accessibilityAddTraits(.isButton)
    }
}

struct AppIcone: View {
    let item: AppItem
    let taille: CGFloat
    @State private var cible = false

    var body: some View {
        Image(nsImage: Icones.de(item.url.path))
            .resizable().interpolation(.high)
            .frame(width: taille, height: taille)
            .modifier(SurvolDock())
            .background(Circle().fill(Color.accentColor.opacity(cible ? 0.45 : 0)).padding(-3))
            .contentShape(Rectangle())
            .onTapGesture { AppDelegate.shared.allerA(item.url) }
            // Comme dans le Dock : glisser l'icône hors du mini-Dock et la lâcher la retire.
            // Le glisser porte un type que seul Side connaît, pour qu'aucune autre app ne l'accepte.
            .onDrag {
                AppDelegate.shared.appGlissee = item
                DispatchQueue.main.async { AppDelegate.shared.store.appEnGlisse = item.url }
                let colis = NSItemProvider()
                colis.registerDataRepresentation(forTypeIdentifier: "com.gauthieraube.side.app", visibility: .ownProcess) { fini in
                    fini(Data(), nil)
                    return nil
                }
                return colis
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $cible) { fournisseurs in
                AppDelegate.shared.ouvrirAvec(fournisseurs, item.url)
                return true
            }
            .contextMenu {
                if item.favori {
                    Button("Retirer des favorites") { item.retirer() }
                } else {
                    Button("Garder dans le mini-Dock") { Config.shared.appsFavorites.append(item.url.path) }
                    Button("Masquer cette app") { item.retirer() }
                }
                Divider()
                Button("Masquer le mini-Dock") { Config.shared.apps = false }
            }
            .help(item.nom)
            .accessibilityLabel(item.nom)
            .accessibilityAddTraits(.isButton)
    }
}

/// Un trait de séparation qu'on glisse pour changer une largeur (grande zone, colonnes du Finder).
struct Poignee: View {
    @Binding var valeur: Double
    let mini: CGFloat
    let maxi: CGFloat
    @State private var depart: Double?
    @State private var survol = false

    var body: some View {
        let actif = survol || depart != nil
        Color.clear
            .frame(width: 9)
            .frame(maxHeight: .infinity)
            .overlay(Rectangle()
                .fill(actif ? Color.accentColor : Color(nsColor: .separatorColor))
                .frame(width: actif ? 3 : 1))
            .contentShape(Rectangle())
            .onHover { dedans in
                survol = dedans
                if dedans { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    if depart == nil { depart = valeur }
                    valeur = Double(min(max(CGFloat(depart ?? valeur) + v.translation.width, mini), maxi))
                }
                .onEnded { _ in depart = nil })
            .help("Glisse pour changer la largeur")
            .accessibilityLabel("Changer la largeur")
    }
}

/// Les zones de dépôt flottantes : des carrés arrondis à droite de la carte, façon Dropover.
/// Un carré apparaît pendant un glisser-déposer, et reste tant qu'il contient des fichiers.
struct ZonesFlottantes: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 8) {
            ForEach(store.etageres) { zone in
                ZoneCarree(column: zone, store: store, glisse: store.glisse)
            }
        }
        .frame(width: Reglages.carreDepot)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: store.glisse)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: store.depotRempli)
    }
}

struct ZoneCarree: View {
    @ObservedObject var column: Column
    let store: Store
    let glisse: Bool
    @ObservedObject var config = Config.shared

    var body: some View {
        if glisse || !column.items.isEmpty {
            let forme = RoundedRectangle(cornerRadius: 22, style: .continuous)
            EtagereView(column: column, store: store)
                .frame(width: Reglages.carreDepot, height: Reglages.carreDepot)
                .background(ZStack {
                    VisualEffect()
                    Color(nsColor: .windowBackgroundColor).opacity(config.opacite)
                }.clipShape(forme))
                .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
        }
    }
}

/// Les zones de dépôt. `etendu` : grandes cartes « Dépose ici » (pendant un glisser-déposer).
/// Sinon : une fine bande de vignettes, seulement pour les zones qui contiennent quelque chose.
struct ZonesView: View {
    static let taille = CGSize(width: 150, height: 150)   // largeur des cartes / hauteur de la rangée
    static let bande: CGFloat = 56
    @ObservedObject var store: Store
    let etendu: Bool
    var lateral = false

    var body: some View {
        if lateral {
            GeometryReader { geo in
                let n = CGFloat(store.etageres.count)
                let place = geo.size.width - 16 - 8 * (n - 1)
                HStack(spacing: 8) {
                    ForEach(store.etageres) { zone in
                        EtagereView(column: zone, store: store).frame(width: max(60, place / n))
                    }
                }
                .padding(8)
            }
        } else if etendu {
            VStack(spacing: 8) {
                ForEach(store.etageres) { zone in EtagereView(column: zone, store: store) }
            }
            .padding(8)
            .frame(width: Self.taille.width + 16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 14, y: 4)
        } else {
            VStack(spacing: 6) {
                ForEach(store.etageres) { zone in EtagereCompacte(column: zone, store: store) }
            }
            .frame(width: Self.bande)
        }
    }
}

/// Une zone de dépôt réduite : une bande arrondie de vignettes, qu'on peut emmener ailleurs.
struct EtagereCompacte: View {
    @ObservedObject var column: Column
    let store: Store
    @State private var depot = false

    var body: some View {
        if !column.items.isEmpty {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(column.items) { item in
                        IconView(item: item, column: column, taille: 38, legende: false)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(depot ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(depot ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: depot ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .modifier(Depot(action: { AppDelegate.shared.poser($0, column.indexEtagere) }, cible: $depot, deplace: false))
            .contextMenu {
                Button("Afficher dans le Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(column.items.map(\.url))
                }
                Button("Vider la zone") { Etagere.vider(column.indexEtagere); column.reload() }
                if store.etageres.count > 1 {
                    Button("Supprimer cette zone") { store.supprimerZone(column.indexEtagere) }
                }
            }
            .help("Zone de dépôt : glisse ces fichiers où tu veux")
        }
    }
}

/// Le bord droit de la carte pendant un glisser-déposer : y lâcher un dossier l'épingle en colonne.
struct BordEpingle: View {
    @State private var cible = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
            Text("Épingler").font(.caption)
        }
        .foregroundStyle(cible ? Color.white : Color.accentColor)
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.accentColor.opacity(cible ? 0.75 : 0.2)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1.5))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(8)
        .onDrop(of: [UTType.fileURL, UTType.utf8PlainText], isTargeted: $cible) { fournisseurs in
            AppDelegate.shared.epingler(fournisseurs)
            return true
        }
        .accessibilityLabel("Épingler un dossier en colonne")
    }
}

/// L'étagère : une carte arrondie où poser des fichiers le temps de les emmener ailleurs.
struct EtagereView: View {
    @ObservedObject var column: Column
    let store: Store
    @ObservedObject var config = Config.shared
    @State private var depot = false

    var body: some View {
        let vide = column.items.isEmpty
        ZStack {
            // Le fond de la zone : l'attraper et tirer déplace la zone, comme une petite fenêtre.
            // (Attraper un fichier, lui, le fait glisser hors de la zone.)
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .onChanged { _ in AppDelegate.shared.deplacerDepot() }
                    .onEnded { _ in AppDelegate.shared.finDeplacementDepot() })
            if vide {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.title2).foregroundStyle(.secondary)
                    Text("Dépose ici")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 10)
            } else if column.items.count == 1, let seul = column.items.first {
                IconView(item: seul, column: column, taille: 56, legende: false)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 4)], spacing: 4) {
                        ForEach(column.items) { item in
                            IconView(item: item, column: column, taille: 38, legende: false)
                        }
                    }
                }
                .padding(.top, 36).padding(.bottom, 32).padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if !vide {
                Button { Etagere.vider(column.indexEtagere); column.reload() } label: { rond("xmark") }
                    .buttonStyle(.plain).padding(8)
                    .help("Vider l'étagère").accessibilityLabel("Vider l'étagère")
            }
        }
        .overlay(alignment: .topTrailing) {
            if !vide {
                Menu {
                    Button("Afficher dans le Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(column.items.map(\.url))
                    }
                    Button("Vider l'étagère") { Etagere.vider(column.indexEtagere); column.reload() }
                    if store.etageres.count > 1 {
                        Button("Supprimer cette zone") { store.supprimerZone(column.indexEtagere) }
                    }
                    Divider()
                    Button("Replacer à côté de Side") { AppDelegate.shared.replacerDepot() }
                } label: { rond("chevron.down") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(8)
                .accessibilityLabel("Actions de l'étagère")
            }
        }
        // Le cadenas : fermé, la zone reste à l'écran quand Side se ferme ; ouvert, elle se cache avec lui.
        .overlay(alignment: .top) {
            if !vide {
                Button { config.depotReste.toggle() } label: {
                    rond(config.depotReste ? "lock.fill" : "lock.open.fill")
                        .foregroundStyle(config.depotReste ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain).padding(8)
                .help(config.depotReste ? "Verrouillée : reste à l'écran quand Side se ferme. Clique pour qu'elle se cache avec Side."
                                         : "Déverrouillée : se cache quand Side se ferme. Clique pour la garder à l'écran.")
                .accessibilityLabel(config.depotReste ? "Zone verrouillée à l'écran" : "Zone qui se cache avec Side")
            }
        }
        .overlay(alignment: .bottom) {
            if !vide {
                Text(column.items.count == 1 ? column.items[0].name : "\(column.items.count) éléments")
                    .font(.caption).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.14)))
                    .padding(.horizontal, 10).padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 22)
            .fill(depot ? Color.accentColor.opacity(0.28) : Color.clear))   // même matière que la barre latérale
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(
            depot ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: depot ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .modifier(Depot(action: { AppDelegate.shared.poser($0, column.indexEtagere) }, cible: $depot, deplace: false))
        .contextMenu {
            if store.etageres.count > 1 {
                Button("Supprimer cette zone") { store.supprimerZone(column.indexEtagere) }
            }
        }
    }

    private func rond(_ symbole: String) -> some View {
        Image(systemName: symbole)
            .font(.system(size: 10, weight: .bold))
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.primary.opacity(0.16)))
            .contentShape(Circle())
    }
}

/// La barre latérale, façon Finder : étagère, récents, favoris, emplacements.
/// Un ordinateur du réseau dans la barre latérale : un clic l'ouvre dans le Finder pour s'y connecter.
struct LigneReseau: View {
    let nom: String
    @State private var survol = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "desktopcomputer").foregroundStyle(Color.accentColor).frame(width: 18)
            Text(nom).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(survol ? Color.primary.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture { Reseau.shared.ouvrir(nom) }
        .help("Se connecter à « \(nom) » dans le Finder. Une fois connecté, il apparaît ici et se parcourt dans Side.")
        .accessibilityLabel("Se connecter à \(nom)")
        .accessibilityAddTraits(.isButton)
    }
}

struct SidebarView: View {
    @ObservedObject var store: Store
    @ObservedObject var reseau = Reseau.shared
    @ObservedObject var config = Config.shared
    @State private var depotFavori = false
    /// Sections repliées (mémorisées). Les tags sont repliés au départ.
    @State private var repliees: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "sectionsRepliees") ?? ["Tags"])

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                let b = Set(config.barre)
                if b.contains("recents") || b.contains("dossiers") { titre("Récents") }
                if ouverte("Récents") {
                    if b.contains("recents") {
                        LigneBarre(store: store, kind: .recents, nom: "Fichiers récents", symbole: "clock")
                    }
                    if b.contains("dossiers") {
                        LigneBarre(store: store, kind: .dossiers, nom: "Dossiers récents", symbole: "clock.arrow.circlepath")
                    }
                }
                titre("Favoris")
                    .background(RoundedRectangle(cornerRadius: 5).fill(depotFavori ? Color.accentColor.opacity(0.35) : .clear))
                    .modifier(Depot(action: { AppDelegate.shared.ajouterFavoris($0) }, cible: $depotFavori))
                    .help("Clique pour replier. Glisse un dossier ici pour l'ajouter aux favoris.")
                if ouverte("Favoris") {
                    ForEach(store.favoris, id: \.self) { url in
                        LigneBarre(store: store, kind: .folder(url), nom: Fichiers.nom(url), symbole: "folder")
                            .contextMenu { Button("Retirer des favoris") { store.retirerFavori(url) } }
                    }
                }
                titre("Emplacements")
                if ouverte("Emplacements") {
                    if b.contains("icloud") {
                        LigneBarre(store: store, kind: .folder(Fichiers.icloud), nom: "iCloud Drive", symbole: "icloud")
                    }
                    if b.contains("maison") {
                        LigneBarre(store: store, kind: .folder(Fichiers.home), nom: NSUserName(), symbole: "house")
                    }
                    if b.contains("applications") {
                        LigneBarre(store: store, kind: .folder(URL(fileURLWithPath: "/Applications")), nom: "Applications", symbole: "square.grid.3x3")
                    }
                    if b.contains("bureau") {
                        LigneBarre(store: store, kind: .folder(Fichiers.desktop), nom: "Bureau", symbole: "menubar.dock.rectangle")
                    }
                    if b.contains("documents") {
                        LigneBarre(store: store, kind: .folder(Fichiers.documents), nom: "Documents", symbole: "doc")
                    }
                    if b.contains("telechargements") {
                        LigneBarre(store: store, kind: .folder(Fichiers.downloads), nom: "Téléchargements", symbole: "arrow.down.circle")
                    }
                    if b.contains("disques") {
                        ForEach(Fichiers.disques(), id: \.self) { disque in
                            LigneBarre(store: store, kind: .folder(disque), nom: Fichiers.nom(disque),
                                       symbole: Fichiers.estReseau(disque) ? "server.rack" : "externaldrive")
                        }
                    }
                }
                if b.contains("reseau") {
                    titre("Réseau")
                    if ouverte("Réseau") {
                        // D'abord les serveurs déjà connectés (on peut les parcourir), puis les ordinateurs repérés.
                        ForEach(Fichiers.disques().filter(Fichiers.estReseau), id: \.self) { serveur in
                            LigneBarre(store: store, kind: .folder(serveur), nom: Fichiers.nom(serveur), symbole: "server.rack")
                        }
                        ForEach(reseau.ordinateurs, id: \.self) { nom in LigneReseau(nom: nom) }
                        if reseau.ordinateurs.isEmpty {
                            Text("Aucun ordinateur repéré").font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                        }
                    }
                }
                if b.contains("tags") { titre("Tags") }
                if b.contains("tags") && ouverte("Tags") {
                    let noms = NSWorkspace.shared.fileLabels, couleurs = NSWorkspace.shared.fileLabelColors
                    ForEach(Array(noms.indices.dropFirst()), id: \.self) { i in
                        LigneBarre(store: store, kind: .tag(noms[i]), nom: noms[i], symbole: "circle.fill",
                                   couleur: i < couleurs.count ? Color(nsColor: couleurs[i]) : nil)
                    }
                }
            }
        }
        .padding(8)
        // La recherche d'ordinateurs ne démarre que si la rubrique Réseau est affichée.
        .onAppear { if config.barre.contains("reseau") { reseau.chercher() } }
        .onChange(of: config.barre) { _, b in if b.contains("reseau") { reseau.chercher() } }
    }

    private func ouverte(_ section: String) -> Bool { !repliees.contains(section) }

    /// Titre de section : un clic la replie ou la déplie, comme dans le Finder.
    private func titre(_ texte: String) -> some View {
        HStack(spacing: 4) {
            Text(texte).font(.subheadline).fontWeight(.semibold)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(ouverte(texte) ? 90 : 0))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6).padding(.top, 14).padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                if repliees.contains(texte) { repliees.remove(texte) } else { repliees.insert(texte) }
            }
            UserDefaults.standard.set(Array(repliees), forKey: "sectionsRepliees")
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(texte + (ouverte(texte) ? ", section ouverte" : ", section repliée"))
    }
}

/// Un raccourci macOS dans la barre latérale : un clic le lance ;
/// déposer des fichiers dessus le lance avec ces fichiers en entrée.
struct LigneRaccourci: View {
    let nom: String
    @ObservedObject var raccourcis = Raccourcis.shared
    @State private var survol = false
    @State private var depot = false

    var body: some View {
        let actif = raccourcis.enCours == nom
        HStack(spacing: 7) {
            Image(systemName: actif ? "hourglass" : "bolt.fill").foregroundStyle(Color.accentColor).frame(width: 18)
            Text(nom).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(
            depot ? Color.accentColor.opacity(0.35) : (actif ? Color.primary.opacity(0.16) : (survol ? Color.primary.opacity(0.08) : .clear))))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture { raccourcis.lancer(nom) }
        .onDrop(of: [UTType.fileURL], isTargeted: $depot) { fournisseurs in
            AppDelegate.shared.lancerRaccourci(nom, fournisseurs)
            return true
        }
        .help("Lancer « \(nom) ». Dépose un fichier pour le lui passer.")
        .accessibilityAddTraits(.isButton)
    }
}

/// L'historique du copier-coller : un clic recopie l'élément, on peut aussi le glisser ailleurs.
struct PressePapiersView: View {
    @ObservedObject var presse = PressePapiers.shared
    var filtre = ""
    var apresCopie: (() -> Void)?
    @State private var copie: UUID?

    private var visibles: [Copie] {
        let f = filtre.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return presse.tries }
        return presse.tries.filter { !$0.secret && apercu($0).localizedCaseInsensitiveContains(f) }
    }

    private static let dates: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        if presse.elements.isEmpty {
            Text("Ce que tu copies apparaîtra ici.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibles.isEmpty {
            Text("Aucun résultat").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(visibles) { ligne($0) }
                }
                .padding(6)
            }
        }
    }

    private func ligne(_ c: Copie) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Group {
                if let image = c.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 5))
                } else if let fichier = c.fichiers.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: fichier.path)).resizable().frame(width: 28, height: 28)
                } else {
                    Image(systemName: c.secret ? "key.fill" : "text.alignleft").foregroundStyle(.secondary).frame(width: 28, height: 28)
                }
            }
            .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(apercu(c)).lineLimit(2).truncationMode(.tail)
                Text(copie == c.id ? "Copié — prêt à coller" : Self.dates.localizedString(for: c.date, relativeTo: Date()))
                    .font(.caption).foregroundStyle(copie == c.id ? Color.accentColor : .secondary)
            }
            Spacer(minLength: 0)
            if c.epingle { Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.accentColor).padding(.top, 3) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(copie == c.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture {
            presse.recopier(c)
            copie = c.id
            // Le temps de lire « Copié », puis la liste se referme.
            DispatchQueue.main.asyncAfter(deadline: .now() + (apresCopie == nil ? 1.5 : 0.6)) {
                if copie == c.id { copie = nil; apresCopie?() }
            }
        }
        .onDrag {
            if let fichier = c.fichiers.first { return NSItemProvider(object: fichier as NSURL) }
            if let image = c.image { return NSItemProvider(object: image) }
            return NSItemProvider(object: (c.texte ?? "") as NSString)
        }
        .contextMenu {
            Button("Copier") { presse.recopier(c) }
            if c.secret {
                // Un mot de passe ne s'épingle pas : il serait écrit sur le disque.
            } else {
                Button(c.epingle ? "Désépingler" : "Épingler en haut de la liste") { presse.epingler(c) }
            }
            Button("Supprimer de l'historique") { presse.supprimer(c) }
            Divider()
            Button("Effacer l'historique (sauf les épinglés)") { presse.vider() }
        }
        .help("Clic : recopier. Clic droit : épingler. On peut aussi le glisser ailleurs.")
    }

    private func apercu(_ c: Copie) -> String {
        if c.secret { return "••••••••••  (mot de passe)" }
        if !c.fichiers.isEmpty {
            let noms = c.fichiers.map { FileManager.default.displayName(atPath: $0.path) }
            return noms.count == 1 ? noms[0] : "\(noms.count) fichiers : " + noms.prefix(3).joined(separator: ", ")
        }
        if c.image != nil { return "Image" }
        return (c.texte ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LigneBarre: View {
    @ObservedObject var store: Store
    let kind: Column.Kind
    let nom: String
    let symbole: String
    var couleur: Color?
    @State private var survol = false
    @State private var depot = false

    private var dossier: URL? { if case .folder(let u) = kind { return u } else { return nil } }

    var body: some View {
        let actif = store.courante == kind
        HStack(spacing: 7) {
            Image(systemName: symbole).foregroundStyle(couleur ?? Color.accentColor)
                .font(couleur == nil ? .body : .system(size: 11)).frame(width: 18)
            Text(nom).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(
            depot ? Color.accentColor.opacity(0.35)
                : (actif ? Color.primary.opacity(0.16) : (survol ? Color.primary.opacity(0.08) : .clear))))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture { store.naviguer(kind) }
        .modifier(Glissable(kind: kind))   // on peut emmener le dossier ailleurs (bouton +, autre app…)
        // Déposer un fichier sur un dossier de la barre le range dedans, comme dans le Finder.
        .modifier(Depot(action: dossier.map { d in { AppDelegate.shared.deposer($0, dans: d) } }, cible: $depot))
        .help(nom)
    }
}

/// Rend une ligne de la barre latérale glissable : un dossier part comme un vrai dossier,
/// les autres entrées (Récents, Tags) comme un repère que seul le bouton « + » comprend.
struct Glissable: ViewModifier {
    static let prefixe = "side-entree:"
    let kind: Column.Kind
    func body(content: Content) -> some View {
        content.onDrag {
            if case .folder(let url) = kind { return NSItemProvider(object: url as NSURL) }
            return NSItemProvider(object: (Glissable.prefixe + kind.code) as NSString)
        }
    }
}

/// En position libre, tirer l'en-tête de la grande zone déplace la carte, comme une fenêtre du Finder.
struct Deplacable: ViewModifier {
    let actif: Bool
    func body(content: Content) -> some View {
        if actif {
            content.gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in AppDelegate.shared.deplacerCarte() }
                .onEnded { _ in AppDelegate.shared.finDeplacement() })
        } else {
            content
        }
    }
}

/// Permet de réorganiser les colonnes épinglées en glissant leur titre.
struct Reorganisable: ViewModifier {
    let column: Column
    let store: Store
    let actif: Bool

    func body(content: Content) -> some View {
        if actif {
            content
                .onDrag {
                    store.glissee = column
                    return NSItemProvider(object: "side-colonne" as NSString)
                }
                .onDrop(of: [UTType.utf8PlainText], delegate: DeplacementColonne(cible: column, store: store))
                .help("Glisse le titre pour déplacer la colonne")
        } else {
            content
        }
    }
}

struct ColumnView: View {
    @ObservedObject var column: Column
    let store: Store
    let large: Bool
    var fixe = false   // la grande zone : ni retirable, ni déplaçable
    var dernier = false   // dernière colonne épinglée : porte le petit bouton « + »
    @State private var depot = false
    @State private var recherche = false          // le champ de recherche est déplié
    @FocusState private var champRecherche: Bool
    @ObservedObject private var config = Config.shared

    var body: some View {
        contenu
            .contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: depot ? 2 : 0).padding(2))
            .modifier(Depot(action: actionDepot, cible: $depot))
    }

    /// Sur l'étagère, on pose une référence ; dans un dossier, on range le fichier.
    private var actionDepot: (([NSItemProvider]) -> Void)? {
        if column.estEtagere { return { AppDelegate.shared.poser($0, column.indexEtagere) } }
        if let dossier = column.courant { return { AppDelegate.shared.deposer($0, dans: dossier) } }
        return nil
    }

    private var contenu: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // Précédent / Suivant, toujours présents comme dans le Finder (grisés quand ils ne servent pas).
                // Les colonnes épinglées, plus étroites, ont les mêmes en un peu plus petit.
                HStack(spacing: 0) {
                    navBouton("chevron.left", column.peutRevenir, "Dossier précédent", etroit: !fixe) { column.revenir() }
                    Divider().frame(height: 14)
                    navBouton("chevron.right", column.peutAvancer, "Dossier suivant", etroit: !fixe) { column.avancer() }
                }
                .background(Capsule().fill(Color.primary.opacity(0.09)))
                if fixe, let ici = column.courant {
                    // Cliquer le nom du dossier déroule le chemin qui y mène, comme Commande-clic sur le titre dans le Finder.
                    Menu {
                        ForEach(Array(Fichiers.ascendants(ici).enumerated()), id: \.offset) { rang, dossier in
                            Button {
                                if rang > 0 { store.naviguer(.folder(dossier)) }
                            } label: {
                                Label { Text(Fichiers.nom(dossier)) } icon: {
                                    Image(nsImage: Icones.petite(dossier.path))
                                }
                            }
                            .disabled(rang == 0)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(column.titre).font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                    .frame(minWidth: 90, alignment: .leading)   // le nom reste lisible, même sur une carte étroite
                    .layoutPriority(2)
                    .help("Afficher le chemin de ce dossier")
                    .accessibilityLabel("Chemin du dossier \(column.titre)")
                } else {
                    Text(column.titre).font(fixe ? .title3.weight(.semibold) : .headline).layoutPriority(1).lineLimit(1).truncationMode(.middle)
                        .contentShape(Rectangle())
                        .onTapGesture { if column.peutRevenir { column.revenir() } }   // cliquer le nom = revenir en arrière
                        .help(column.peutRevenir ? "Revenir au dossier précédent" : column.titre)
                }
                Spacer(minLength: 4)
                // Colonnes épinglées, plus étroites : les boutons de présentation passent dans le menu « … »,
                // pour laisser toute la place au nom du dossier.
                if fixe {
                    HStack(spacing: 2) {
                        boutonVue(.icones, "square.grid.2x2", "Afficher en icônes")
                        boutonVue(.liste, "list.bullet", "Afficher en liste")
                        boutonVue(.colonnes, "rectangle.split.3x1", "Afficher en colonnes")
                    }
                    .padding(3)
                    .background(Capsule().fill(Color.primary.opacity(0.09)))
                }
                Menu {
                    if !fixe {
                        Picker("Présentation", selection: $column.presentation) {
                            Label("Icônes", systemImage: "square.grid.2x2").tag(Presentation.icones)
                            Label("Liste", systemImage: "list.bullet").tag(Presentation.liste)
                        }
                        .pickerStyle(.inline)
                        if column.presentation == .icones {
                            Picker("Colonnes de la grille", selection: $column.colonnesGrille) {
                                Text("Automatique").tag(0)
                                ForEach(1...4, id: \.self) { n in Text(n == 1 ? "1 colonne" : "\(n) colonnes").tag(n) }
                            }
                        }
                        Divider()
                    } else if column.presentation == .icones {
                        Picker("Colonnes de la grille", selection: $column.colonnesGrille) {
                            Text("Automatique").tag(0)
                            ForEach(1...6, id: \.self) { n in Text(n == 1 ? "1 colonne" : "\(n) colonnes").tag(n) }
                        }
                        Divider()
                    }
                    if column.peutTrier {
                        Picker("Trier par", selection: $column.tri) {
                            ForEach(Tri.allCases, id: \.self) { Text($0.titre).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                    if let u = column.courant {
                        Button("Ouvrir dans le Finder") { AppDelegate.shared.ouvrir(u) }
                    }
                    Divider()
                    if fixe {
                        Button("Nouvel onglet (⌘T)") { store.nouvelOnglet() }
                        if let u = column.courant {
                            Button("Épingler ce dossier en colonne") { store.ajouter(.folder(u)) }
                            Button("Épingler un autre dossier…") { AppDelegate.shared.choisirDossier() }
                            Button("Ajouter aux favoris") { store.ajouterFavori(u) }
                        }
                    } else {
                        Button("Épingler un autre dossier…") { AppDelegate.shared.choisirDossier() }
                        Button("Retirer cette colonne") { store.retirer(column) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 28)
                        .background(Capsule().fill(Color.primary.opacity(0.09)))
                        .contentShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Autres actions")
                if fixe {
                    if recherche || !column.filtre.isEmpty {
                        // Le champ ne s'ouvre que sur demande ; fermé, il laisse la place au nom du dossier.
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Rechercher", text: $column.filtre).textFieldStyle(.plain).focused($champRecherche)
                                .onExitCommand { column.filtre = ""; recherche = false }
                            Button { column.filtre = ""; recherche = false } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Fermer la recherche")
                        }
                        .padding(.horizontal, 10)
                        .frame(width: large ? 180 : 140, height: 28)
                        .background(Capsule().fill(Color.primary.opacity(0.09)))
                        .transition(.opacity)
                    } else {
                        Button {
                            recherche = true
                            DispatchQueue.main.async { champRecherche = true }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 30, height: 28)
                                .background(Capsule().fill(Color.primary.opacity(0.09)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Rechercher")
                        .accessibilityLabel("Rechercher")
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .contentShape(Rectangle())
            .modifier(Reorganisable(column: column, store: store, actif: !fixe))
            .modifier(Deplacable(actif: fixe))

            if fixe { OngletsView(store: store) }   // sous l'en-tête, comme dans le Finder

            Divider()

            if column.kind == .presse && column.pile.isEmpty {
                PressePapiersView()
            } else if fixe && column.presentation == .colonnes && column.resultats == nil && !column.rechercheEnCours {
                MillerView(column: column)
            } else if column.visibles.isEmpty {
                Text(column.rechercheEnCours ? "Recherche…" : column.resultats != nil ? "Aucun résultat" : column.charge ? "Chargement…"
                     : (column.estEtagere ? "Dépose ici des fichiers pour les garder sous la main, puis glisse-les où tu veux." : "Aucun élément"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { defilement in
                ScrollView {
                    if column.presentation == .icones {
                        let grille = column.colonnesGrille > 0
                            ? Array(repeating: GridItem(.flexible(), spacing: CGFloat(config.espacement)), count: column.colonnesGrille)
                            : [GridItem(.adaptive(minimum: CGFloat(config.tailleIcones) + (config.texteADroite ? 150 : 56)),
                                        spacing: CGFloat(config.espacement))]
                        LazyVGrid(columns: grille, spacing: CGFloat(config.espacement) + 2) {
                            ForEach(column.visibles) { item in
                                IconView(item: item, column: column)
                            }
                        }
                        .padding(8)
                        // On retient combien d'icônes tiennent par ligne : la flèche du bas descend d'une ligne entière.
                        .background(GeometryReader { g in
                            let place = g.size.width - 16, pas = CGFloat(config.espacement)
                            let mini = CGFloat(config.tailleIcones) + (config.texteADroite ? 150 : 56)
                            let n = column.colonnesGrille > 0 ? column.colonnesGrille : max(1, Int((place + pas) / (mini + pas)))
                            Color.clear.onAppear { column.colonnesVisibles = n }.onChange(of: n) { _, v in column.colonnesVisibles = v }
                        })
                    } else {
                        LazyVStack(spacing: 1) {
                            ForEach(column.visibles) { item in
                                RowView(item: item, column: column, large: large)
                            }
                        }
                        .padding(6)
                    }
                }
                .onReceive(Selection.shared.changements) { url in
                    if let url, Selection.shared.colonne === column { defilement.scrollTo(url) }
                }
                }
            }
        }
    }

    private func navBouton(_ symbole: String, _ actif: Bool, _ aide: String, etroit: Bool = false,
                           _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: etroit ? 11 : 12, weight: .semibold))
                .foregroundStyle(actif ? Color.primary : Color.secondary.opacity(0.5))
                .frame(width: etroit ? 24 : 30, height: etroit ? 24 : 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!actif)
        .help(aide)
        .accessibilityLabel(aide)
    }

    private func boutonVue(_ p: Presentation, _ symbole: String, _ aide: String) -> some View {
        let actif = column.presentation == p
        return Button { column.presentation = p } label: {
            Image(systemName: symbole)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(actif ? Color.primary : Color.secondary)
                .frame(width: 30, height: 22)
                .background(Capsule().fill(actif ? Color.primary.opacity(0.18) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(aide)
        .accessibilityLabel(aide)
    }
}

/// Réorganise les colonnes pendant qu'on en glisse une sur une autre.
struct DeplacementColonne: DropDelegate {
    let cible: Column
    let store: Store

    func validateDrop(info: DropInfo) -> Bool { store.glissee != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func dropEntered(info: DropInfo) {
        guard let g = store.glissee, g !== cible else { return }
        withAnimation(.easeInOut(duration: 0.2)) { store.deplacer(g, vers: cible) }
    }
    func performDrop(info: DropInfo) -> Bool {
        store.glissee = nil
        return true
    }
}

/// L'élément sélectionné (un seul à la fois, comme un clic simple dans le Finder).
/// Un fichier montré dans l'aperçu sous un autre nom que le sien (l'image tirée d'un SVG garde le nom du SVG).
final class ElementApercu: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?
    init(url: URL, titre: String) { previewItemURL = url; previewItemTitle = titre }
}

final class Selection: ObservableObject {
    static let shared = Selection()
    /// Le bleu de sélection du Finder (il suit la couleur d'accentuation choisie dans les Réglages Système).
    static let bleu = Color(nsColor: .selectedContentBackgroundColor)
    /// L'élément sélectionné. L'interface est prévenue APRÈS le changement : prévenue avant (le fonctionnement
    /// par défaut), elle se redessinait parfois avec l'ancienne valeur, et l'affichage avait une flèche de retard.
    var url: URL? {
        didSet {
            guard url != oldValue else { return }
            objectWillChange.send()
            changements.send(url)
        }
    }
    /// Annonce chaque nouvelle sélection (pour faire défiler la liste jusqu'à elle).
    let changements = PassthroughSubject<URL?, Never>()
    weak var colonne: Column?
    func choisir(_ url: URL?, _ colonne: Column?) {
        self.colonne = colonne
        self.url = url
        // Sélectionner un élément sort du champ « Rechercher » : Espace sert alors au Coup d'œil,
        // au lieu d'ajouter un espace au texte recherché.
        if url != nil { AppDelegate.shared.lacherChamp() }
    }
}

/// Présentation en colonnes, comme dans le Finder : chaque dossier ouvert ajoute une colonne à droite.
struct MillerView: View {
    @ObservedObject var column: Column
    @ObservedObject var config = Config.shared

    var body: some View {
        ScrollViewReader { defilement in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 0) {
                    ForEach(Array(column.niveaux.enumerated()), id: \.offset) { niveau, items in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(niveau == column.niveaux.count - 1 ? column.filtrer(items) : items) { item in
                                    MillerRow(item: item, column: column, niveau: niveau)
                                }
                            }
                            .padding(6)
                        }
                        .frame(width: CGFloat(config.largeurMiller))
                        .modifier(DepotNiveau(dossier: dossier(niveau)))
                        .id(niveau)
                        // Glisser ce trait change la largeur des colonnes.
                        Poignee(valeur: $config.largeurMiller, mini: 140, maxi: 520)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .onChange(of: column.niveaux.count) { _, n in
                withAnimation(.easeOut(duration: 0.2)) { defilement.scrollTo(n - 1, anchor: .trailing) }
            }
            // Sélectionner un élément dans une colonne à moitié masquée la fait glisser entièrement dans la vue.
            .onReceive(Selection.shared.changements) { url in
                guard let url, Selection.shared.colonne === column,
                      let niveau = column.niveaux.firstIndex(where: { $0.contains { $0.url == url } }) else { return }
                withAnimation(.easeOut(duration: 0.2)) { defilement.scrollTo(niveau) }
            }
        }
    }
}

extension MillerView {
    /// Le dossier que montre la colonne numéro `niveau` (nil si ce n'est pas un vrai dossier : récents, tags…).
    func dossier(_ niveau: Int) -> URL? {
        if niveau > 0 { return niveau - 1 < column.pile.count ? column.pile[niveau - 1] : nil }
        if let premier = column.pile.first {
            if case .folder = column.kind { return premier.deletingLastPathComponent() }
            return nil
        }
        return column.courant
    }
}

/// Une colonne de la présentation en colonnes accepte les fichiers pour son propre dossier.
struct DepotNiveau: ViewModifier {
    let dossier: URL?
    @State private var cible = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(cible ? 0.12 : 0)))
            .modifier(Depot(action: dossier.map { d in { AppDelegate.shared.deposer($0, dans: d) } }, cible: $cible))
    }
}

struct MillerRow: View {
    let item: FileItem
    let column: Column
    let niveau: Int
    @State private var survol = false
    @State private var depot = false
    @ObservedObject private var selection = Selection.shared
    @ObservedObject private var config = Config.shared   // pour se redessiner quand un réglage change

    var body: some View {
        let ouvert = niveau < column.pile.count && column.pile[niveau] == item.url
        let choisi = selection.url == item.url
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 18, height: 18)
            Text(item.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            NuageIcone(item: item, blanc: choisi)
            // Flèche réservée aux dossiers : sur un fichier, le nuage se cale ainsi au bord droit, comme dans le Finder.
            if item.isFolder {
                Image(systemName: "chevron.right").font(.caption)
                    .foregroundStyle(choisi ? Color.white.opacity(0.85) : Color.secondary.opacity(0.6))
            }
        }
        .foregroundStyle(choisi ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)   // lignes resserrées, presque comme dans le Finder
        .background(RoundedRectangle(cornerRadius: 6).fill(
            depot ? Color.accentColor.opacity(0.35)
                : (choisi ? Selection.bleu
                    : (ouvert ? Color.primary.opacity(0.16) : (survol ? Color.primary.opacity(0.1) : .clear)))))
        .contentShape(Rectangle())
        .onHover { survol = $0; AppDelegate.shared.survoler(item, column, $0) }
        // Un clic sur un dossier l'ouvre dans la colonne suivante ; sur un fichier, il le sélectionne.
        .onTapGesture {
            selection.choisir(item.url, column)
            if item.isFolder { column.ouvrirNiveau(item.url, niveau) } else { column.tronquer(niveau) }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if !item.isFolder { AppDelegate.shared.ouvrir(item.url) }
        })
        .modifier(Depot(
            action: item.isFolder ? { AppDelegate.shared.deposer($0, dans: item.url) } : nil,
            cible: $depot))
        .help(item.name)
    }
}

/// Le petit nuage du Finder, à côté d'un fichier d'iCloud Drive qui n'est pas (encore) sur le Mac.
/// Un clic dessus lance le téléchargement.
struct NuageIcone: View {
    let item: FileItem
    var blanc = false   // sur une ligne sélectionnée (fond bleu)

    var body: some View {
        if item.nuage != .aucun {
            let couleur = blanc ? Color.white.opacity(0.9) : Color.secondary
            Group {
                switch item.nuage {
                case .aTelecharger:
                    Image(systemName: "icloud.and.arrow.down")
                        .contentShape(Rectangle())
                        .onTapGesture { AppDelegate.shared.telecharger(item.url) }
                        .help("Dans iCloud, pas encore sur ce Mac. Clique pour le télécharger.")
                        .accessibilityLabel("Télécharger depuis iCloud")
                        .accessibilityAddTraits(.isButton)
                case .telechargement:
                    Image(systemName: "icloud.and.arrow.down.fill").symbolEffect(.pulse)
                        .help("Téléchargement en cours…")
                        .accessibilityLabel("Téléchargement en cours")
                default:
                    Image(systemName: "icloud.and.arrow.up").symbolEffect(.pulse)
                        .help("Envoi vers iCloud en cours…")
                        .accessibilityLabel("Envoi vers iCloud en cours")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(couleur)
        }
    }
}

/// Clic, glisser-déposer et survol : communs à la liste et aux icônes.
struct Interactions: ViewModifier {
    let item: FileItem
    let column: Column
    @Binding var survol: Bool
    var fond = true   // faux pour les icônes : elles dessinent leur sélection elles-mêmes, comme dans le Finder
    @State private var depot = false
    @ObservedObject private var selection = Selection.shared

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 6).fill(
                depot ? Color.accentColor.opacity(0.35)
                    : (fond && selection.url == item.url ? Selection.bleu
                        : (survol && selection.url != item.url ? Color.primary.opacity(0.1) : .clear))))
            .contentShape(Rectangle())
            .onHover { survol = $0; AppDelegate.shared.survoler(item, column, $0) }
            // Comme dans le Finder : un clic sélectionne, un double-clic ouvre.
            .onTapGesture { selection.choisir(item.url, column) }
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                if !item.isFolder { AppDelegate.shared.ouvrir(item.url) }
                else if column.kind == .etagere { AppDelegate.shared.store.naviguer(.folder(item.url)) }
                else { column.entrer(item.url) }
            })
            .modifier(Depot(
                action: item.isFolder && !column.estEtagere ? { AppDelegate.shared.deposer($0, dans: item.url) } : nil,
                cible: $depot))
            .help(item.name)
    }
}

/// Accepte les fichiers qu'on dépose et les confie à `action` (rien si `action` est absent).
struct Depot: ViewModifier {
    /// Fichiers, mais aussi images, PDF, vidéos et sons qui n'existent pas encore sur le disque.
    static let types: [UTType] = [.fileURL, .image, .pdf, .movie, .audio]
    let action: (([NSItemProvider]) -> Void)?
    @Binding var cible: Bool
    var deplace = true   // faux pour les zones de dépôt : elles ne déplacent jamais le fichier

    func body(content: Content) -> some View {
        if let action {
            content.onDrop(of: Depot.types, delegate: Arrivee(action: action, cible: $cible, deplace: deplace))
        } else {
            content
        }
    }

    /// Dit à macOS ce que fera le dépôt, pour qu'il montre le bon pointeur :
    /// un déplacement par défaut, une copie (avec le « + » vert) quand Option est maintenue.
    struct Arrivee: DropDelegate {
        let action: ([NSItemProvider]) -> Void
        @Binding var cible: Bool
        let deplace: Bool

        func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: Depot.types) }
        func dropEntered(info: DropInfo) { cible = true }
        func dropExited(info: DropInfo) { cible = false }
        func dropUpdated(info: DropInfo) -> DropProposal? {
            // Un vrai fichier peut être déplacé ; une image tirée d'une page web ne peut qu'être copiée.
            let fichier = NSPasteboard(name: .drag).types?.contains(.fileURL) == true
            let copie = !deplace || !fichier || NSEvent.modifierFlags.contains(.option)
            return DropProposal(operation: copie ? .copy : .move)
        }
        func performDrop(info: DropInfo) -> Bool {
            cible = false
            action(info.itemProviders(for: Depot.types))
            return true
        }
    }
}

/// Le départ d'un glisser de fichier, confié à macOS : la destination choisit entre déplacer et copier,
/// comme pour un fichier tiré depuis le Finder (déplacer par défaut, copier avec Option).
final class DepartGlisser: NSObject, NSDraggingSource {
    static let shared = DepartGlisser()
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.move, .copy, .link, .generic]
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // Le fichier est peut-être parti ailleurs : on rafraîchit, et la zone de dépôt oublie ce qui n'est plus là.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { AppDelegate.shared.apresGlisser() }
    }
}

enum Vignettes {
    static let cache = NSCache<NSURL, NSImage>()
}

struct IconView: View {
    let item: FileItem
    let column: Column
    var taille: CGFloat?   // nil = la taille choisie dans les réglages
    var legende = true
    @State private var survol = false
    @State private var vignette: NSImage?
    @State private var info = ""
    @ObservedObject private var selection = Selection.shared
    @ObservedObject private var config = Config.shared

    var body: some View {
        let choisi = selection.url == item.url
        let cote = taille ?? CGFloat(config.tailleIcones)
        let droite = legende && config.texteADroite
        let image = Image(nsImage: (config.apercus ? vignette : nil) ?? NSWorkspace.shared.icon(forFile: item.url.path))
            .resizable().aspectRatio(contentMode: .fit)
            .frame(width: cote, height: cote)
            .padding(3)
            // Comme dans le Finder : l'icône choisie se pose sur un carré gris, son nom sur du bleu.
            .background(RoundedRectangle(cornerRadius: 6).fill(
                choisi ? (legende ? Color.primary.opacity(0.12) : Selection.bleu.opacity(0.3)) : .clear))
            // Sans nom sous l'icône (zone de dépôt) : un cadre bleu montre clairement ce qui est sélectionné.
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Selection.bleu, lineWidth: choisi && !legende ? 2.5 : 0))
        let texte = VStack(alignment: droite ? .leading : .center, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                NuageIcone(item: item, blanc: choisi)
                Text(item.name)
                    .font(.system(size: CGFloat(config.tailleTexte)))
                    .multilineTextAlignment(droite ? .leading : .center)
                    .lineLimit(2).truncationMode(.middle)
                    .foregroundStyle(choisi ? Color.white : Color.primary)
            }
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(choisi ? Selection.bleu : .clear))
            if config.infos && !info.isEmpty {
                Text(info).font(.system(size: max(9, CGFloat(config.tailleTexte) - 2)))
                    .foregroundStyle(Color.accentColor).lineLimit(1)
            }
        }
        Group {
            if !legende {
                image
            } else if droite {
                HStack(spacing: 6) { image; texte; Spacer(minLength: 0) }
            } else {
                VStack(spacing: 4) {
                    image
                    texte.frame(maxWidth: .infinity, minHeight: CGFloat(config.tailleTexte) * 2.7, alignment: .top)
                }
            }
        }
        .padding(legende ? 4 : 0)
        .modifier(Interactions(item: item, column: column, survol: $survol, fond: false))
        .onAppear(perform: charger)
    }

    private func charger() {
        if legende && info.isEmpty { renseigner() }
        guard !item.isFolder, vignette == nil else { return }
        if let img = Vignettes.cache.object(forKey: item.url as NSURL) { vignette = img; return }
        let demande = QLThumbnailGenerator.Request(
            fileAt: item.url, size: CGSize(width: 128, height: 128),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: demande) { rep, _ in
            guard let img = rep?.nsImage else { return }
            Vignettes.cache.setObject(img, forKey: item.url as NSURL)
            DispatchQueue.main.async { vignette = img }
        }
    }

    /// « Afficher les informations » : le poids d'un fichier, le nombre d'éléments d'un dossier.
    private func renseigner() {
        if !item.isFolder {
            info = ByteCountFormatter.string(fromByteCount: Int64(item.taille), countStyle: .file)
            return
        }
        let url = item.url
        DispatchQueue.global(qos: .utility).async {
            let n = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") }.count
            DispatchQueue.main.async { info = n == 0 ? "Vide" : (n == 1 ? "1 élément" : "\(n) éléments") }
        }
    }
}

struct RowView: View {
    let item: FileItem
    let column: Column
    let large: Bool
    @State private var survol = false
    @ObservedObject private var selection = Selection.shared
    @ObservedObject private var config = Config.shared   // pour se redessiner quand un réglage change

    private static let jour: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()
    private static let dates: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        // Ligne choisie : fond bleu du Finder, textes en blanc.
        let choisi = selection.url == item.url
        let discret = choisi ? Color.white.opacity(0.85) : Color.secondary
        return HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                if ((column.kind == .recents || column.kind == .dossiers) && column.pile.isEmpty) || column.resultats != nil {
                    Text(detail).font(.caption).foregroundStyle(discret).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            NuageIcone(item: item, blanc: choisi)
            if large {
                Group {
                    Text(Self.jour.string(from: item.date))
                        .frame(width: 86, alignment: .trailing)
                    Text(item.isFolder ? "--" : ByteCountFormatter.string(fromByteCount: Int64(item.taille), countStyle: .file))
                        .frame(width: 64, alignment: .trailing)
                }
                .font(.caption).foregroundStyle(discret)
            }
            // Flèche réservée aux dossiers : sur un fichier, le nuage se cale ainsi au bord droit, comme dans le Finder.
            if item.isFolder {
                Image(systemName: "chevron.right").font(.caption)
                    .foregroundStyle(choisi ? Color.white.opacity(0.85) : Color.secondary.opacity(0.6))
            }
        }
        .foregroundStyle(choisi ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)   // lignes resserrées, presque comme dans le Finder
        .modifier(Interactions(item: item, column: column, survol: $survol))
    }

    private var detail: String {
        let parent = item.url.deletingLastPathComponent()
        let dossier = parent.standardizedFileURL == Fichiers.downloads.standardizedFileURL
            ? "Téléchargements" : FileManager.default.displayName(atPath: parent.path)
        return dossier + " · " + Self.dates.localizedString(for: item.date, relativeTo: Date())
    }
}

// MARK: - Réglages de l'utilisateur

/// Les volets de la fenêtre de réglages, comme les rubriques des Réglages Système.
enum Volet: String, CaseIterable, Identifiable {
    /// Volet affiché à l'ouverture des réglages (« --volet nom » le choisit, pour les tests).
    static var depart: Volet {
        let a = CommandLine.arguments
        return a.firstIndex(of: "--volet").flatMap { $0 + 1 < a.count ? Volet(rawValue: a[$0 + 1]) : nil } ?? .ouverture
    }
    case ouverture, fermeture, apparence, finder, colonnes, depot, raccourcis, general
    var id: String { rawValue }
    var titre: String {
        switch self {
        case .ouverture: return "Ouverture"
        case .fermeture: return "Fermeture"
        case .apparence: return "Apparence"
        case .finder: return "Comme le Finder"
        case .colonnes: return "Dossiers et colonnes"
        case .depot: return "Dépôt et apps"
        case .raccourcis: return "Raccourcis"
        case .general: return "Général"
        }
    }
    var symbole: String {
        switch self {
        case .ouverture: return "cursorarrow.rays"
        case .fermeture: return "xmark"
        case .apparence: return "paintbrush.fill"
        case .finder: return "folder.fill"
        case .colonnes: return "rectangle.split.3x1.fill"
        case .depot: return "tray.and.arrow.down.fill"
        case .raccourcis: return "bolt.fill"
        case .general: return "gearshape.fill"
        }
    }
    var couleur: Color {
        switch self {
        case .ouverture: return .blue
        case .fermeture: return .red
        case .apparence: return .purple
        case .finder: return .cyan
        case .colonnes: return .orange
        case .depot: return .green
        case .raccourcis: return .pink
        case .general: return .gray
        }
    }
}

struct ReglagesView: View {
    @ObservedObject var config = Config.shared
    @ObservedObject var store = AppDelegate.shared.store
    @State private var volet: Volet = Volet.depart
    @State private var demarrage = SMAppService.mainApp.status == .enabled
    @State private var ecoute = false
    @ObservedObject var raccourcis = Raccourcis.shared

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Volet.allCases) { ligne($0) }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 48)
            .padding(.bottom, 10)
            .frame(width: 210)
            .background(ZStack {
                Color(nsColor: .windowBackgroundColor)
                Color.primary.opacity(0.05)
            })
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(volet.titre).font(.title2.weight(.semibold))
                    .padding(.horizontal, 26).padding(.top, 16).padding(.bottom, 2)
                Form { contenu }
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)   // remplit toute la fenêtre
        .ignoresSafeArea()
    }

    private func ligne(_ v: Volet) -> some View {
        let choisi = v == volet
        return HStack(spacing: 9) {
            Image(systemName: v.symbole)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(v.couleur.gradient))
            Text(v.titre)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(choisi ? Color.primary.opacity(0.14) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { volet = v }
        .accessibilityAddTraits(choisi ? [.isButton, .isSelected] : .isButton)
    }

    private func pourcent(_ x: Double) -> String { "\(Int((x * 100).rounded())) %" }

    private func curseur(_ titre: String, _ valeur: Binding<Double>, _ plage: ClosedRange<Double>, _ texte: String) -> some View {
        LabeledContent(titre) {
            HStack {
                Slider(value: valeur, in: plage).frame(width: 190)
                Text(texte).monospacedDigit().foregroundStyle(.secondary).frame(width: 84, alignment: .trailing)
            }
        }
    }

    private func note(_ texte: String) -> some View {
        Text(texte).font(.caption).foregroundStyle(.secondary)
    }

    /// Case à cocher d'une entrée de la barre latérale.
    private func entree(_ titre: String, _ symbole: String, _ cle: String) -> some View {
        Toggle(isOn: Binding(
            get: { config.barre.contains(cle) },
            set: { oui in
                if oui { if !config.barre.contains(cle) { config.barre.append(cle) } }
                else { config.barre.removeAll { $0 == cle } }
            })) {
            Label(titre, systemImage: symbole)
        }
    }

    @ViewBuilder private var contenu: some View {
        switch volet {
        case .ouverture:
            Section {
                Picker("Coin actif", selection: $config.coin) {
                    ForEach(Coin.allCases, id: \.self) { Text($0.titre).tag($0) }
                }
                curseur("Taille du coin", $config.tailleCoin, 6...120, "\(Int(config.tailleCoin.rounded())) pt")
                    .disabled(config.coin == .aucun)
            } header: { Text("Coin de l'écran") } footer: {
                note("Si macOS utilise déjà ce coin, désactive-le dans Réglages Système > Bureau et Dock > Coins actifs.")
            }
            Section {
                Toggle("Geste de la souris", isOn: $config.secouer)
                Picker("Geste", selection: $config.cercle) {
                    Text("Secouer le pointeur").tag(false)
                    Text("Faire un cercle").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(!config.secouer)
                curseur("Sensibilité", $config.sensibilite, 0...1,
                        config.sensibilite > 0.66 ? "Élevée" : (config.sensibilite > 0.33 ? "Moyenne" : "Faible"))
                    .disabled(!config.secouer)
            } header: { Text("Geste de la souris") } footer: {
                if config.cercle {
                    note("Fais un cercle avec le pointeur, d'un seul mouvement rapide, sans cliquer, pour ouvrir Side. Il peut être grossier, petit ou grand, dans un sens ou dans l'autre. Le cercle ne referme pas Side : utilise un clic à côté, Échap, le coin ou le raccourci.")
                }
            }
            Section {
                Toggle("Glisser quatre doigts sur le trackpad", isOn: $config.quatreDoigts)
                Picker("Pour ouvrir", selection: $config.sensDoigts) {
                    Text("Vers le bas").tag("bas")
                    Text("Vers le haut").tag("haut")
                    Text("Les deux").tag("deux")
                }
                .pickerStyle(.segmented)
                .disabled(!config.quatreDoigts)
                if config.quatreDoigts {
                    LabeledContent("Gestes de macOS") {
                        Button("Ouvrir les réglages du trackpad") {
                            if let u = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") {
                                NSWorkspace.shared.open(u)
                            }
                        }
                    }
                }
            } header: { Text("Trackpad") } footer: {
                note((config.sensDoigts == "deux"
                      ? "Chaque geste, vers le haut ou vers le bas, ouvre ou ferme Side. "
                      : "Le geste dans l'autre sens referme Side. ")
                     + "Attention : macOS utilise déjà ces gestes, vers le haut pour Mission Control et vers le bas pour « Exposé des apps ». Pour que les deux ne se déclenchent pas ensemble, mets-les sur « Désactivé » dans Réglages Système > Trackpad > Autres gestes. Side ne change pas ces réglages lui-même.")
            }
            Section("Clavier") {
                LabeledContent("Raccourci") {
                    HStack {
                        Button(ecoute ? "Tape le raccourci…" : config.libelle) {
                            ecoute = true
                            AppDelegate.shared.ecouterRaccourci { ecoute = false }
                        }
                        Button("Effacer") { AppDelegate.shared.definirRaccourci(touche: -1, mods: 0, libelle: "Aucun") }
                            .disabled(config.touche == -1)
                    }
                }
            }
        case .fermeture:
            Section {
                Picker("Au changement de bureau ou d'app plein écran", selection: $config.suivi) {
                    Text("Fermer, sauf si Commande est maintenue").tag("commande")
                    Text("Toujours rester affichée").tag("toujours")
                    Text("Toujours fermer").tag("jamais")
                }
                Toggle("Fermer d'un clic en dehors", isOn: $config.fermerAuClic)
                Toggle("Fermer quand la souris en sort", isOn: $config.fermerEnSortant)
            } footer: {
                note("La carte se ferme toujours avec le raccourci clavier, la touche Échap, une secousse ou en revenant dans le coin actif.")
            }
        case .apparence:
            Section("Position et taille") {
                Picker("La carte arrive", selection: $config.bord) {
                    ForEach(Bord.allCases, id: \.self) { Text($0.titre).tag($0) }
                }
                if config.bord == .plein {
                    HStack {
                        note("La carte apparaît au centre. Tire-la par sa barre du haut pour la déplacer : Side retient l'endroit.")
                        Spacer()
                        Button("Recentrer") { AppDelegate.shared.recentrerCarte() }
                    }
                }
                curseur("Hauteur de la carte", $config.tailleHauteur, 0.15...0.9, pourcent(config.tailleHauteur))
                curseur("Largeur du Finder (sans les colonnes)", $config.largeurSeule, 0.35...1, pourcent(config.largeurSeule))
            }
            Section("Fond de la carte") {
                curseur("Opacité", $config.opacite, 0...1, pourcent(config.opacite))
            }
            Section {
                Toggle("Flouter l'arrière-plan quand Side est ouvert", isOn: $config.flou)
                curseur("Intensité", $config.flouForce, 0.3...1, pourcent(config.flouForce))
                    .disabled(!config.flou)
            } header: { Text("Arrière-plan") } footer: {
                note("L'écran derrière la carte s'estompe en fondu. On peut toujours cliquer et glisser des fichiers au travers.")
            }
        case .finder:
            Section {
                entree("Fichiers récents", "clock", "recents")
                entree("Dossiers récents", "clock.arrow.circlepath", "dossiers")
                entree("iCloud Drive", "icloud", "icloud")
                entree(NSUserName(), "house", "maison")
                entree("Applications", "square.grid.3x3", "applications")
                entree("Bureau", "menubar.dock.rectangle", "bureau")
                entree("Documents", "doc", "documents")
                entree("Téléchargements", "arrow.down.circle", "telechargements")
                entree("Disques externes et serveurs connectés", "externaldrive", "disques")
                entree("Réseau (ordinateurs qui partagent des fichiers)", "network", "reseau")
                entree("Tags", "circle.fill", "tags")
            } header: { Text("Afficher dans la barre latérale") } footer: {
                note("Tes favoris se gèrent directement dans la barre : glisse un dossier sur « Favoris » pour l'ajouter, clic droit pour le retirer.")
            }
            Section("Présentation par icônes") {
                curseur("Taille des icônes", $config.tailleIcones, 32...128,
                        "\(Int(config.tailleIcones.rounded())) × \(Int(config.tailleIcones.rounded()))")
                curseur("Espacement de la grille", $config.espacement, 2...40, "\(Int(config.espacement.rounded())) pt")
                Picker("Taille du texte", selection: $config.tailleTexte) {
                    ForEach([10, 11, 12, 13, 14, 15, 16], id: \.self) { Text("\($0)").tag(Double($0)) }
                }
                Picker("Position du texte", selection: $config.texteADroite) {
                    Text("En bas").tag(false)
                    Text("À droite").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("Afficher les informations", isOn: $config.infos)
                Toggle("Utiliser un aperçu comme icône", isOn: $config.apercus)
            }
            Section("Options avancées") {
                Toggle("Afficher toutes les extensions de fichiers", isOn: $config.extensions)
                Toggle("Laisser les dossiers en haut lors du tri par nom", isOn: $config.dossiersEnHaut)
                Picker("En effectuant une recherche", selection: $config.rechercheMac) {
                    Text("Rechercher sur ce Mac").tag(true)
                    Text("Rechercher dans le dossier affiché").tag(false)
                }
            }
        case .colonnes:
            Section("Grande zone") {
                Picker("Au lancement de Side, afficher", selection: $config.ouverture) {
                    Text("Le dernier dossier consulté").tag("")
                    ForEach(store.favoris, id: \.self) { Text(Fichiers.nom($0)).tag($0.path) }
                }
            }
            Section {
                curseur("Largeur d'une colonne",
                        $config.tailleColonne, 180...700, "\(Int(config.tailleColonne.rounded())) pt")
                Picker("Quand la place manque", selection: $config.ajuster) {
                    Text("Rétrécir pour tout afficher").tag(true)
                    Text("Taille fixe, à faire défiler").tag(false)
                }
            } header: { Text("Colonnes épinglées") } footer: {
                note("Pour épingler un dossier : glisse-le vers le bord droit de la carte, ou utilise le bouton + de la dernière colonne.")
            }
        case .depot:
            Section {
                LabeledContent("Zones affichées", value: "\(store.etageres.count)")
                Toggle("Refermer Side après un dépôt", isOn: $config.fermerApresDepot)
                if config.fermerApresDepot {
                    note("Pour le garder ouvert cette fois-là : maintiens Option (⌥) en lâchant le fichier, ou ramène tout de suite la souris sur la carte.")
                }
                Toggle("Garder les zones remplies à l'écran quand Side est fermé", isOn: $config.depotReste)
                Toggle("Ajouter mes captures d'écran à une zone de dépôt", isOn: $config.capturesAuto)
                if config.capturesAuto {
                    note("Dès qu'une capture d'écran est enregistrée, elle t'attend dans une zone, prête à être glissée ailleurs. Les captures se rangent ensemble dans la même zone.")
                }
            } header: { Text("Zones de dépôt") } footer: {
                note("Une zone apparaît en haut à droite de la carte quand tu fais glisser un fichier. Tant qu'elle contient quelque chose, elle reste à l'écran même quand Side est fermé, pour que tu puisses glisser son contenu ailleurs. Secoue le pointeur pendant le glisser pour en ajouter une autre en dessous. Les zones vides disparaissent toutes seules.")
            }
            Section {
                Toggle("Afficher le mini-Dock", isOn: $config.apps)
                Picker("Emplacement", selection: $config.dockPosition) {
                    Text("Au-dessus de la carte").tag("haut")
                    Text("En dessous").tag("bas")
                    Text("À gauche").tag("gauche")
                    Text("À droite").tag("droite")
                }
                .disabled(!config.apps)
                curseur("Taille des icônes", $config.tailleDock, 28...64, "\(Int(config.tailleDock.rounded())) pt")
                    .disabled(!config.apps)
                Toggle("Afficher le bouton « Apps » (toutes les applications, avec une recherche)", isOn: $config.lanceur).disabled(!config.apps)
                Toggle("Apps ouvertes", isOn: $config.appsOuvertes).disabled(!config.apps)
                Toggle("Apps favorites", isOn: $config.appsFavoris).disabled(!config.apps)
                if !config.appsMasquees.isEmpty {
                    Button("Réafficher les \(config.appsMasquees.count) apps masquées") { config.appsMasquees = [] }
                }
            } header: { Text("Mini-Dock") } footer: {
                note("Un clic passe à l'app. Déposer un fichier sur une icône l'ouvre avec cette app. Pour ajouter une favorite : dépose une app sur le mini-Dock, ou clic droit > « Garder dans le mini-Dock ». Pour retirer une icône : glisse-la hors du mini-Dock et lâche-la quand la croix apparaît, ou clic droit.")
            }
        case .raccourcis:
            Section {
                if raccourcis.tous.isEmpty {
                    Text("Aucun raccourci trouvé dans l'app Raccourcis.").foregroundStyle(.secondary)
                }
                ForEach(raccourcis.tous, id: \.self) { nom in
                    Toggle(nom, isOn: Binding(
                        get: { config.raccourcis.contains(nom) },
                        set: { oui in
                            if oui { config.raccourcis.append(nom) } else { config.raccourcis.removeAll { $0 == nom } }
                        }))
                }
                Button("Actualiser la liste") { raccourcis.actualiser() }
            } header: { Text("Afficher dans le mini-Dock") } footer: {
                note("Ce sont les raccourcis de l'app « Raccourcis » de macOS. Ils s'affichent à droite des apps, après un séparateur, sous forme de tuiles à leurs initiales. Un clic les lance ; déposer un fichier dessus le leur passe en entrée.")
            }
        case .general:
            Section {
                Toggle("Garder un historique du copier-coller (7 jours)", isOn: $config.historique)
                Toggle("Y garder aussi les mots de passe (affichés masqués)", isOn: $config.historiqueSecrets)
                    .disabled(!config.historique)
            } header: { Text("Presse-papiers") } footer: {
                note("L'historique se déroule en passant la souris sur l'icône au bout du mini-Dock. Les textes et les fichiers copiés sont gardés 7 jours sur ce Mac ; ce que tu épingles (clic droit) est gardé sans limite. Les images et les mots de passe ne sont jamais écrits sur le disque : ils s'effacent quand Side se ferme. Décocher l'historique efface tout.")
            }
            Section("Présentation") {
                LabeledContent("Les cinq étapes de bienvenue") {
                    Button("Revoir la présentation") { AppDelegate.shared.revoirAccueil() }
                }
            }
            Section {
                Toggle("Ouvrir Side à l'ouverture de session", isOn: Binding(
                    get: { demarrage },
                    set: { _ in
                        AppDelegate.shared.basculerDemarrage()
                        demarrage = SMAppService.mainApp.status == .enabled
                    }))
            }
        }
    }
}

// MARK: - Fenêtre

/// La poignée de la fenêtre des zones de dépôt : une petite barre, comme en haut des cartes d'iOS.
/// On l'attrape pour déplacer la fenêtre. C'est une vue AppKit à part, pour recevoir le clic à coup sûr.
final class PoigneeDepot: NSView {
    static let hauteur: CGFloat = 0   // la poignée n'existe plus : on attrape la zone elle-même
    private let barre = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        barre.cornerRadius = 2.5
        barre.backgroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
        barre.shadowOpacity = 0.4
        barre.shadowRadius = 2
        barre.shadowOffset = .zero
        layer?.addSublayer(barre)
        toolTip = "Glisse pour déplacer la zone de dépôt"
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
        if clicDroit, let it = AppDelegate.shared.survole {
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
    private let config = Config.shared
    private var fenetreReglages: NSWindow?
    private var raccourciRef: EventHotKeyRef?
    private var gestionnaireInstalle = false
    private var ecouteur: Any?
    private var dernierX: CGFloat = 0, parcours: CGFloat = 0, versDroite = true
    private var demiTours: [TimeInterval] = []
    private var pointClic: NSPoint?
    private var pointClicDedans: NSPoint?
    /// Vrai pendant que la zone de dépôt accompagne l'animation de la carte (ce n'est pas toi qui la déplaces).
    private var animationDepot = false
    private var depotEnCours: TimeInterval = -10   // moment du dernier lâcher dans une zone de dépôt
    /// La carte seule (sans la bande du mini-Dock), à l'écran, et le mini-Dock tel que la vue le dessine.
    private var cadreSeule: NSRect = .zero
    /// Les vues qui font partie de Side en plus de la carte : le mini-Dock, et le panneau du presse-papiers.
    let reperes = NSHashTable<NSView>.weakObjects()
    weak var vueLanceur: NSView?
    weak var vueDock: NSView?
    /// La petite croix qui suit la souris quand une icône glissée est assez loin du mini-Dock pour être retirée.
    private var croix: NSPanel?
    private var sortieDuDock: TimeInterval?   // depuis quand l'icône glissée est hors du mini-Dock
    /// Vrai si ce point de l'écran est dans cette vue.
    private func dans(_ v: NSView?, _ p: NSPoint, marge: CGFloat = 0) -> Bool {
        guard let v, let w = v.window else { return false }
        return w.convertToScreen(v.convert(v.bounds, to: nil)).insetBy(dx: -marge, dy: -marge).contains(p)
    }
    /// Demande à iCloud de rapatrier un fichier resté dans le nuage.
    func telecharger(_ url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.store.reloadAll() }
    }
    private var battement = 0

    /// Pendant qu'on glisse une icône du mini-Dock : hors du mini-Dock depuis un instant, une croix suit la souris
    /// pour dire « lâche ici pour retirer ». De retour sur le mini-Dock, elle disparaît.
    private func suivreIconeGlissee() {
        let ici = NSEvent.mouseLocation
        let dehors = !dans(vueDock, ici, marge: 20)
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
    private func surIconeLanceur(_ p: NSPoint) -> Bool {
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
    private func surSide(_ p: NSPoint) -> Bool {
        if cadreSeule.contains(p) { return true }
        for v in reperes.allObjects {
            guard let w = v.window, w.isVisible, !v.isHiddenOrHasHiddenAncestor else { continue }
            if w.convertToScreen(v.convert(v.bounds, to: nil)).insetBy(dx: -6, dy: -6).contains(p) { return true }
        }
        return false
    }
    private var derniereSecousse: TimeInterval = 0
    private var suitBureaux = false
    private var dernierGlisser = NSPasteboard(name: .drag).changeCount
    private var glisserActif = false
    var appGlissee: AppItem?   // icône du mini-Dock en cours de glisser
    private let forcerGlisse = CommandLine.arguments.contains("--glisse")   // pour les tests
    private var panel: DrawerPanel!
    private var host: NSHostingView<DrawerView>!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var abonnement: AnyCancellable?
    private var abonnementBord: AnyCancellable?

    private(set) var survole: FileItem?    // élément sous la souris
    private weak var survoleColonne: Column?
    private var cible: URL?                // élément visé par le menu contextuel
    private var apercu: URL?
    private var apercus: [URL] = []                   // les fichiers proposés dans l'aperçu
    private var apercuOuvert = false
    private var appAvantApercu: NSRunningApplication?   // l'app qui avait la main avant l'aperçu
    private var visible = false
    private var epingle = false            // reste ouvert (test ou clic dans la barre des menus)
    /// Mode test (argument --show) : garde la carte ouverte pour une capture d'écran.
    /// Il ne dure que 8 secondes, pour ne jamais bloquer les fermetures pendant qu'on utilise l'app.
    private let lancement = ProcessInfo.processInfo.systemUptime
    private var modeTest: Bool {
        CommandLine.arguments.contains("--show") && ProcessInfo.processInfo.systemUptime - lancement < 8
    }
    /// Moment de la dernière ouverture ou fermeture : sert de garde-fou entre le coin et la secousse.
    private var dernierBasculement: TimeInterval = 0
    private var voile: NSPanel?
    private var depotPanel: NSPanel?
    private var suiviDepot: [AnyCancellable] = []
    private var ancreDepot: NSPoint = .zero   // coin haut-gauche de la fenêtre des zones de dépôt
    private var ancrePerso: NSPoint?          // l'endroit où tu l'as déplacée à la main, s'il y en a un
    private var placementAuto = false
    private var accesDemande = false
    private var horsBureau = 0   // nombre de vérifications où la carte n'était pas sur le bureau affiché
    private var teinteVoile: NSView?
    private var arme = true                // la souris doit quitter le coin avant de rouvrir
    private var aQuitteCoin = false        // la souris est sortie du coin depuis l'ouverture
    private var debutCoin: Date?
    private var debutDehors: Date?
    private var cadreCarte: NSRect = .zero // la carte visible, à l'écran (la fenêtre est un peu plus grande)
    private var repos: NSPoint = .zero     // position de la carte dans sa fenêtre, une fois ouverte
    /// Position libre : coin haut-gauche de la carte, là où tu l'as posée (nil = au centre).
    private var positionLibre: NSPoint? = (UserDefaults.standard.array(forKey: "cartePosition") as? [Double])
        .flatMap { $0.count == 2 ? NSPoint(x: $0[0], y: $0[1]) : nil }
    private var prise: (souris: NSPoint, fenetre: NSPoint, carte: NSRect)?   // déplacement en cours
    private var ecran: NSScreen?

    func applicationDidFinishLaunching(_ note: Notification) {
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
        nettoyerDepot()
        creerDepot()
        if let e = NSScreen.main { placer(sur: e, anime: false) }   // fixe l'emplacement des zones de dépôt
        store.reloadAll()
        // Surveille le presse-papiers deux fois par seconde pour tenir l'historique du copier-coller.
        let surveillance = Timer(timeInterval: 0.5, repeats: true) { _ in PressePapiers.shared.verifier() }
        RunLoop.main.add(surveillance, forMode: .common)
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
            self?.toucheApercu(ev) == true ? nil : ev
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
        // Pour les tests : « --image fichier.png » dessine la carte (ou les réglages, avec --volet) dans une image,
        // sans rien afficher à l'écran ni prendre le clavier, puis quitte. « --choisir n » sélectionne d'abord
        // le premier élément de la grande zone (0) ou de la n-ième colonne épinglée.
        if let i = CommandLine.arguments.firstIndex(of: "--image"), i + 1 < CommandLine.arguments.count {
            let sortie = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            let reglages = CommandLine.arguments.contains("--volet")
            let taille = reglages ? NSSize(width: 820, height: 900) : NSSize(width: 1150, height: 560)
            let vue: NSView = reglages ? NSHostingView(rootView: ReglagesView()) : NSHostingView(rootView: DrawerView(store: store))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: taille), styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = vue
            store.largeurMax = 1400
            store.reloadAll()
            if CommandLine.arguments.contains("--presse") {   // pour les tests : un historique d'exemple
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
        if let i = CommandLine.arguments.firstIndex(of: "--apercu"), i + 1 < CommandLine.arguments.count {
            let url = URL(fileURLWithPath: CommandLine.arguments[i + 1])   // pour les tests
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.coupDOeil(url) }
        }
    }

    /// Side n'a pas de barre des menus visible, mais macOS a besoin d'un menu Édition
    /// pour que Commande + A, C, V, X et Z fonctionnent dans le champ « Rechercher ».
    private func installerMenuEdition() {
        let edition = NSMenu(title: "Édition")
        edition.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
        let retablir = edition.addItem(withTitle: "Rétablir", action: Selector(("redo:")), keyEquivalent: "z")
        retablir.keyEquivalentModifierMask = [.command, .shift]
        edition.addItem(.separator())
        edition.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edition.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edition.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edition.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let principal = NSMenu()
        let entree = NSMenuItem(title: "Édition", action: nil, keyEquivalent: "")
        entree.submenu = edition
        principal.addItem(NSMenuItem(title: "Side", action: nil, keyEquivalent: ""))
        principal.addItem(entree)
        NSApp.mainMenu = principal
    }

    // MARK: Menu de la barre des menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Afficher Side", action: #selector(afficherEpingle), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Ajouter un dossier…", action: #selector(choisirDossier), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Réglages…", action: #selector(ouvrirReglages), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Revoir la présentation", action: #selector(revoirAccueil), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let demarrage = menu.addItem(
            withTitle: "Ouvrir à l'ouverture de session", action: #selector(basculerDemarrage), keyEquivalent: "")
        demarrage.target = self
        demarrage.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter Side", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func basculerDemarrage() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Impossible de modifier l'ouverture automatique"
            a.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }

    // MARK: Raccourci clavier Commande + @

    /// Cherche la touche qui tape « @ » sur le clavier actuel (elle change selon le clavier).
    private func toucheArobase() -> UInt32 {
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

    private func installerRaccourci() {
        if !gestionnaireInstalle {
            gestionnaireInstalle = true
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { AppDelegate.shared.basculer() }
                return noErr
            }, 1, &type, nil, nil)
        }
        if let ref = raccourciRef { UnregisterEventHotKey(ref); raccourciRef = nil }
        guard config.touche != -1 else { return }
        let touche = config.touche == -2 ? toucheArobase() : UInt32(config.touche)
        let mods = config.touche == -2 ? UInt32(cmdKey) : UInt32(config.mods)
        let id = EventHotKeyID(signature: OSType(0x5449_524F), id: 1)
        RegisterEventHotKey(touche, mods, id, GetApplicationEventTarget(), 0, &raccourciRef)
    }

    func definirRaccourci(touche: Int, mods: Int, libelle: String) {
        config.touche = touche
        config.mods = mods
        config.libelle = libelle
        installerRaccourci()
    }

    /// Attend la prochaine combinaison de touches tapée dans la fenêtre Réglages.
    func ecouterRaccourci(fin: @escaping () -> Void) {
        if let ref = raccourciRef { UnregisterEventHotKey(ref); raccourciRef = nil }
        if let e = ecouteur { NSEvent.removeMonitor(e) }
        ecouteur = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self else { return ev }
            let f = ev.modifierFlags
            let annule = ev.keyCode == 53
            // Il faut au moins Commande, Contrôle ou Option, sinon on bloquerait une touche normale.
            guard annule || !f.intersection([.command, .control, .option]).isEmpty else { NSSound.beep(); return nil }
            if let e = self.ecouteur { NSEvent.removeMonitor(e); self.ecouteur = nil }
            if annule { self.installerRaccourci(); fin(); return nil }
            var mods = 0, texte = ""
            if f.contains(.control) { mods |= controlKey; texte += "⌃" }
            if f.contains(.option) { mods |= optionKey; texte += "⌥" }
            if f.contains(.shift) { mods |= shiftKey; texte += "⇧" }
            if f.contains(.command) { mods |= cmdKey; texte += "⌘" }
            texte += (ev.charactersIgnoringModifiers ?? "?").uppercased()
            self.definirRaccourci(touche: Int(ev.keyCode), mods: mods, libelle: texte)
            fin()
            return nil
        }
    }

    /// La carte est-elle ouverte ? (pour le geste à quatre doigts : ouvrir dans un sens, fermer dans l'autre)
    var estOuvert: Bool { visible }

    /// Relance la présentation de bienvenue, carte ouverte.
    @objc func revoirAccueil() {
        store.accueil = 0
        if !visible { basculer() }
    }

    @objc func ouvrirReglages() {
        hide()
        if fenetreReglages == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: ReglagesView()))
            w.title = "Réglages de Side"
            // Comme les Réglages Système : barre de titre fondue dans le contenu, barre latérale à gauche.
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.setContentSize(NSSize(width: 760, height: 500))   // sinon une bande vide reste en bas
            w.isReleasedWhenClosed = false
            w.center()
            fenetreReglages = w
        }
        NSApp.activate(ignoringOtherApps: true)
        fenetreReglages?.makeKeyAndOrderFront(nil)
    }

    private func ecranSous(_ p: NSPoint) -> NSScreen? {
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

    // MARK: Secouer le pointeur

    /// Quatre allers-retours rapides de la souris (même pendant qu'on glisse un fichier) ouvrent la carte.
    /// Le cercle, cherché en continu dans les derniers mouvements de la souris.
    private var trace: [(p: CGPoint, t: TimeInterval)] = []

    private func chercherCercle(_ ici: CGPoint) {
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
    private var attendrePause = false
    private var dernierMouvement: TimeInterval = 0

    private func secousse() {
        guard config.secouer, prise == nil else { return }   // secouer ouvre la carte, et la referme si elle est ouverte
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
            if glisserActif && visible { store.ajouterZone() } else { basculer() }
        }
    }

    // MARK: Dépôt de fichiers dans la carte

    /// Crée une colonne pour ce qui est déposé sur le bouton « + » :
    /// un dossier, ou une entrée de la barre latérale (Fichiers récents, Dossiers récents, un tag).
    func epingler(_ fournisseurs: [NSItemProvider]) {
        for f in fournisseurs {
            if f.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = f.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL, Fichiers.item(url).isFolder else { return }
                    DispatchQueue.main.async { self.store.ajouter(.folder(url.standardizedFileURL)) }
                }
            } else {
                _ = f.loadObject(ofClass: NSString.self) { texte, _ in
                    guard let texte = texte as? String, texte.hasPrefix(Glissable.prefixe),
                          let kind = Column.Kind(code: String(texte.dropFirst(Glissable.prefixe.count))) else { return }
                    DispatchQueue.main.async { self.store.ajouter(kind) }
                }
            }
        }
    }

    /// Ajoute aux favoris les dossiers déposés sur le titre « Favoris ».
    func ajouterFavoris(_ fournisseurs: [NSItemProvider]) {
        for f in fournisseurs {
            _ = f.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL, Fichiers.item(url).isFolder else { return }
                DispatchQueue.main.async { self.store.ajouterFavori(url) }
            }
        }
    }

    /// Au lancement : supprime du dossier de dépôt ce qui n'est plus dans aucune zone.
    private func nettoyerDepot() {
        (0..<Etagere.maximum).forEach { Etagere.dedoublonner($0) }
        let gardes = Set((0..<Etagere.maximum).flatMap { Etagere.items($0).map { $0.url.standardizedFileURL.path } })
        let contenu = (try? FileManager.default.contentsOfDirectory(at: Self.dossierDepot, includingPropertiesForKeys: nil)) ?? []
        for fichier in contenu where !gardes.contains(fichier.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: fichier)
        }
    }

    /// Dossier où Side enregistre ce qu'on dépose et qui n'est pas encore un fichier
    /// (vignette de capture d'écran, image glissée depuis une page web…).
    private static let dossierDepot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Side/Dépôt", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// Transforme ce qu'on dépose en fichier. `temporaire` est vrai quand Side a dû l'enregistrer lui-même.
    /// Les vrais fichiers du glisser en cours, lus directement là où macOS les note.
    /// (Ce que l'interface transmet au moment du dépôt est parfois une copie du fichier, pas le fichier :
    /// le ranger créait alors un doublon « nom 2 », même en le lâchant dans son propre dossier.)
    private func fichiersGlisses() -> [URL] {
        let lus = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return lus.map { ($0 as NSURL).filePathURL ?? $0 }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Reçoit tout ce qui vient d'être lâché : les vrais fichiers s'il y en a, sinon ce que l'interface fournit
    /// (une image tirée d'une page web, une capture d'écran…), dont Side enregistre alors une copie.
    private func recevoirTout(_ fournisseurs: [NSItemProvider], _ suite: @escaping (_ url: URL, _ temporaire: Bool) -> Void) {
        let directs = fichiersGlisses()
        if !directs.isEmpty { directs.forEach { suite($0, false) }; return }
        fournisseurs.forEach { recevoir($0, suite) }
    }

    private func recevoir(_ f: NSItemProvider, _ suite: @escaping (_ url: URL, _ temporaire: Bool) -> Void) {
        if f.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = f.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                // macOS transmet parfois une « référence » au fichier plutôt que son chemin : on revient au chemin,
                // sinon Side ne reconnaît pas le dossier d'origine et crée un doublon.
                let chemin = (url as NSURL).filePathURL ?? url
                DispatchQueue.main.async { suite(chemin, false) }
            }
            return
        }
        let acceptes: [UTType] = [.image, .pdf, .movie, .audio]
        guard let type = f.registeredTypeIdentifiers.first(where: { id in
            guard let t = UTType(id) else { return false }
            return acceptes.contains { t.conforms(to: $0) }
        }) else { return }
        let nomPropose = f.suggestedName
        f.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
            // Le fichier fourni disparaît à la fin de ce bloc : on le copie tout de suite.
            guard let url else { return }
            let ext = url.pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? "") : url.pathExtension
            var nom = nomPropose ?? url.deletingPathExtension().lastPathComponent
            if nom.isEmpty { nom = "Élément déposé" }
            var cible = Self.dossierDepot.appendingPathComponent(nom).appendingPathExtension(ext)
            var n = 2
            while FileManager.default.fileExists(atPath: cible.path) {
                cible = Self.dossierDepot.appendingPathComponent("\(nom) \(n)").appendingPathExtension(ext)
                n += 1
            }
            guard (try? FileManager.default.copyItem(at: url, to: cible)) != nil else { return }
            DispatchQueue.main.async { suite(cible, true) }
        }
    }

    /// Une capture d'écran vient d'être enregistrée : elle va dans la zone des captures
    /// (celle qui en contient déjà), sinon dans une zone vide, sinon dans une nouvelle zone en dessous.
    func recevoirCapture(_ url: URL) {
        // Déjà déposée à la main depuis la vignette de macOS (même nom) : on ne la met pas deux fois.
        let nom = url.lastPathComponent
        if (0..<store.etageres.count).contains(where: { Etagere.fichiers($0).contains { $0.lastPathComponent == nom } }) { return }
        let rangees = Captures.rangees
        let n = store.etageres.count
        var zone = (0..<n).first { i in
            let f = Etagere.fichiers(i)
            return !f.isEmpty && f.allSatisfy { rangees.contains($0.path) }
        } ?? (0..<n).first { Etagere.items($0).isEmpty }
        if zone == nil, Etagere.nombre < Etagere.maximum { store.ajouterZone(); zone = store.etageres.count - 1 }
        let i = zone ?? 0
        let chemin = url.resolvingSymlinksInPath().standardizedFileURL.path
        Captures.rangees = rangees.filter { FileManager.default.fileExists(atPath: $0) }.union([chemin])
        Etagere.ajouter(url, i)
        journal("capture rangée dans la zone \(i) : \(nom)")
        store.reloadAll()
        // Side fermé : la zone se montre tout de suite, comme la vignette de macOS, mais reste plus longtemps.
        if !visible { captureJusqua = ProcessInfo.processInfo.systemUptime + 60 }
        majDepot()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.majDepot() }
    }

    /// Pose des éléments sur l'étagère. Les vrais fichiers ne sont pas déplacés : seul leur emplacement est retenu.
    func poser(_ fournisseurs: [NSItemProvider], _ zone: Int) {
        // Option maintenue au moment de lâcher : Side reste ouvert, pour enchaîner.
        let garder = NSEvent.modifierFlags.contains(.option)
        // Entre le lâcher et l'arrivée du fichier dans la zone, celle-ci reste affichée (sinon elle clignote).
        depotEnCours = ProcessInfo.processInfo.systemUptime
        if !store.glisse { store.glisse = true }
        do {
            recevoirTout(fournisseurs) { url, temporaire in
                // Une image ou capture déposée une seconde fois : Side vient d'en enregistrer une copie.
                // Si la zone contient déjà exactement le même contenu, on jette la copie.
                if temporaire, Etagere.fichiers(zone).contains(where: { $0.path != url.path
                    && FileManager.default.contentsEqual(atPath: $0.path, andPath: url.path) }) {
                    try? FileManager.default.removeItem(at: url)
                } else if !Etagere.ajouter(url, zone), temporaire {
                    try? FileManager.default.removeItem(at: url)
                }
                self.store.reloadAll()
                self.depotEnCours = ProcessInfo.processInfo.systemUptime - 1.2   // le fichier est là : encore un court instant
                guard self.config.fermerApresDepot, !garder else { return }
                // Un court instant avant de fermer : si la souris est revenue sur la carte, c'est qu'on n'a pas fini.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !self.cadreCarte.contains(NSEvent.mouseLocation) { self.hide() }
                }
            }
        }
    }

    func deposer(_ fournisseurs: [NSItemProvider], dans dossier: URL) {
        recevoirTout(fournisseurs) { url, _ in self.ranger(url, dans: dossier) }
    }

    /// Comme le Finder : déplace sur le même disque, copie sinon (ou si Option est enfoncée).
    private func ranger(_ source: URL, dans dossier: URL) {
        let source = (source as NSURL).filePathURL ?? source
        let src = source.standardizedFileURL, dst = Fichiers.resoudre(dossier).standardizedFileURL   // un alias de dossier : on range dans le vrai dossier
        // Lâché dans le dossier où il se trouve déjà (ou sur lui-même, ou dans un de ses sous-dossiers) : on ne fait rien.
        // On compare les vrais chemins : deux écritures du même dossier ne doivent pas créer un doublon.
        let ici = src.resolvingSymlinksInPath().path, parent = src.deletingLastPathComponent().resolvingSymlinksInPath().path
        let la = dst.resolvingSymlinksInPath().path
        guard ici != la, parent != la, !(la + "/").hasPrefix(ici + "/") else { return }
        // Dernière vérification, par l'identité du dossier sur le disque plutôt que par son nom.
        let idParent = try? URL(fileURLWithPath: parent).resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        let idCible = try? URL(fileURLWithPath: la).resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        if let idParent, let idCible, idParent.isEqual(idCible) { return }
        var cible = dst.appendingPathComponent(src.lastPathComponent)
        if FileManager.default.fileExists(atPath: cible.path) { cible = nomLibre(cible, suffixe: " 2") }
        let v1 = try? src.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let v2 = try? dst.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let memeDisque = v1 != nil && v2 != nil && v1!.isEqual(v2!)
        do {
            if !memeDisque || NSEvent.modifierFlags.contains(.option) {
                try FileManager.default.copyItem(at: src, to: cible)
            } else {
                try FileManager.default.moveItem(at: src, to: cible)
            }
        } catch { erreur("Impossible de ranger « \(src.lastPathComponent) »", error) }
        store.reloadAll()
    }

    @objc func afficherEpingle() {
        guard let e = NSScreen.main ?? NSScreen.screens.first else { return }
        epingle = true
        show(sur: e)
    }

    @objc func choisirDossier() {
        hide()
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = "Ajouter"
        p.message = "Choisis le dossier à épingler dans Side"
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK, let url = p.url {
            store.ajouter(.folder(url.standardizedFileURL))
            afficherEpingle()
        }
    }

    // MARK: Mini-Dock

    /// Passe à une app (ou la lance), y compris quand elle est en plein écran sur un autre bureau.
    /// Activer une app ne suffit pas à rejoindre son bureau quand le réglage Mission Control
    /// correspondant est désactivé. Le moyen sûr est celui que tu utilises à la main : cliquer sur son
    /// icône dans le Dock de macOS. Side le fait à ta place (il lui faut l'accès « Accessibilité »).
    func allerA(_ url: URL) {
        hide()
        let chemin = url.standardizedFileURL.path
        let ouverte = NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL.path == chemin }
        if ouverte, AXIsProcessTrusted() {
            DispatchQueue.global(qos: .userInitiated).async {
                if !Self.cliquerDansLeDock(chemin) { DispatchQueue.main.async { Self.activer(url) } }
            }
        } else {
            // Sans l'accès « Accessibilité », Side ne peut qu'activer l'app (sans changer de bureau).
            // On le demande une fois par lancement : macOS affiche alors sa fenêtre d'autorisation.
            if ouverte, !accesDemande {
                accesDemande = true
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            }
            Self.activer(url)
        }
    }

    private static func activer(_ url: URL) {
        let reglage = NSWorkspace.OpenConfiguration()
        reglage.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: reglage) { _, _ in }
    }

    /// Appuie sur l'icône de l'app dans le Dock de macOS. Renvoie faux si elle n'y est pas trouvée.
    private static func cliquerDansLeDock(_ chemin: String) -> Bool {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else { return false }
        let racine = AXUIElementCreateApplication(dock.processIdentifier)
        func enfants(_ e: AXUIElement) -> [AXUIElement] {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v) == .success else { return [] }
            return v as? [AXUIElement] ?? []
        }
        for liste in enfants(racine) {
            for icone in enfants(liste) {
                var v: CFTypeRef?
                guard AXUIElementCopyAttributeValue(icone, kAXURLAttribute as CFString, &v) == .success,
                      let url = v as? URL, url.standardizedFileURL.path == chemin else { continue }
                return AXUIElementPerformAction(icone, kAXPressAction as CFString) == .success
            }
        }
        return false
    }

    private static func ouvrirApp(_ url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", url.path]
        try? p.run()
    }

    /// Lance un raccourci macOS avec les fichiers déposés dessus.
    func lancerRaccourci(_ nom: String, _ fournisseurs: [NSItemProvider]) {
        hide()   // la carte passe au-dessus de tout : on la ferme pour laisser voir ce que le raccourci ouvre
        let groupe = DispatchGroup()
        var fichiers: [URL] = []
        for f in fournisseurs {
            groupe.enter()
            _ = f.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { DispatchQueue.main.async { fichiers.append(url) } }
                DispatchQueue.main.async { groupe.leave() }
            }
        }
        groupe.notify(queue: .main) { Raccourcis.shared.lancer(nom, fichiers: fichiers) }
    }

    /// Ouvre les fichiers déposés sur une icône avec cette app. Une app déposée devient une favorite.
    func ouvrirAvec(_ fournisseurs: [NSItemProvider], _ app: URL) {
        for f in fournisseurs {
            _ = f.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async {
                    if url.pathExtension == "app" { self.favoriser(url); return }
                    self.hide()
                    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
    }
    /// Ajoute aux favorites les apps déposées sur le mini-Dock.
    func ajouterApps(_ fournisseurs: [NSItemProvider]) {
        for f in fournisseurs {
            _ = f.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL, url.pathExtension == "app" else { return }
                DispatchQueue.main.async { self.favoriser(url) }
            }
        }
    }
    private func favoriser(_ url: URL) {
        let chemin = url.standardizedFileURL.path
        if !config.appsFavorites.contains(chemin) { config.appsFavorites.append(chemin) }
        config.appsMasquees.removeAll { $0 == chemin }
    }

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
        (0..<Etagere.nombre).forEach(Etagere.purger)
        store.reloadAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.store.nettoyerZones(); self.majDepot() }
    }

    // MARK: Redimensionner la carte par ses bords

    /// Le bord (ou le coin) de la carte sous ce point de l'écran : x = -1 gauche, 1 droite ; y = 1 haut, -1 bas.
    /// La bande sensible fait 7 points à partir du bord, vers l'intérieur ; près d'un coin, on tire les deux bords.
    private func bordSous(_ p: NSPoint) -> (x: Int, y: Int)? {
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
    private func curseurBord(_ x: Int, _ y: Int) -> NSCursor {
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
    private var priseBord: (souris: NSPoint, largeur: Double, hauteur: Double, x: Int, y: Int)?
    private var pointeurBord = false

    /// Souris sur un bord : le pointeur change. Bouton enfoncé puis tiré : la carte change de taille.
    private func suivreBords(_ ev: NSEvent) -> NSEvent? {
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

    /// Bouton enfoncé sur un fichier, puis souris qui s'éloigne : le fichier part en glisser-déposer.
    private var departGlisser: (point: NSPoint, item: FileItem, fenetre: NSWindow)?
    private func suivreGlisser(_ ev: NSEvent) -> NSEvent? {
        switch ev.type {
        case .leftMouseDown:
            departGlisser = nil
            if let item = survole, let f = ev.window, f === panel || f === depotPanel, !ev.modifierFlags.contains(.control),
               bordSous(NSEvent.mouseLocation) == nil {   // pas sur un bord de la carte : là, on redimensionne
                departGlisser = (ev.locationInWindow, item, f)
            }
        case .leftMouseUp:
            departGlisser = nil
        case .leftMouseDragged:
            guard let d = departGlisser, ev.window === d.fenetre, let vue = d.fenetre.contentView,
                  hypot(ev.locationInWindow.x - d.point.x, ev.locationInWindow.y - d.point.y) >= 5 else { return ev }
            departGlisser = nil
            let element = NSDraggingItem(pasteboardWriter: d.item.url as NSURL)
            let icone = NSWorkspace.shared.icon(forFile: d.item.url.path)
            icone.size = NSSize(width: 48, height: 48)
            let ici = vue.convert(ev.locationInWindow, from: nil)
            element.setDraggingFrame(NSRect(x: ici.x - 24, y: ici.y - 24, width: 48, height: 48), contents: icone)
            vue.beginDraggingSession(with: [element], event: ev, source: DepartGlisser.shared)
            return nil
        default: break
        }
        return ev
    }

    func survoler(_ item: FileItem, _ colonne: Column, _ dedans: Bool) {
        if dedans { survole = item; survoleColonne = colonne } else if survole == item { survole = nil }
    }

    // MARK: Clavier, comme dans le Finder

    /// Espace : Coup d'œil. Flèches haut/bas : élément suivant. Commande + bas ou Commande + O : ouvrir.
    /// Entrée : renommer. Commande + Effacer : corbeille. Renvoie vrai si la touche a servi.
    func touche(_ ev: NSEvent) -> Bool {
        let cmd = ev.modifierFlags.contains(.command)
        let sel = Selection.shared
        switch (ev.keyCode, cmd) {
        case (49, false):
            guard let u = sel.url ?? survole?.url else { return false }
            coupDOeil(u)
        case (125, true), (31, true):
            guard let u = sel.url else { return false }
            if let it = sel.colonne?.items.first(where: { $0.url == u }), it.isFolder { sel.colonne?.entrer(u) }
            else { ouvrir(u) }
        case (17, true): store.nouvelOnglet()                       // Commande + T
        case (13, true):                                            // Commande + W
            if store.onglets.count > 1 { store.fermerOnglet(store.ongletActif) } else { hide() }
        case (123, false), (124, false), (125, false), (126, false): fleche(ev.keyCode)
        case (36, false), (76, false):
            guard let u = sel.url else { return false }
            cible = u
            mRenommer()
        case (51, true):
            guard let u = sel.url else { return false }
            cible = u
            sel.url = nil
            mCorbeille()
        default: return false
        }
        return true
    }

    /// Les flèches, comme dans le Finder :
    /// - en icônes, gauche et droite passent à l'élément voisin, haut et bas à la ligne du dessus ou du dessous ;
    /// - en liste, haut et bas passent à l'élément voisin ;
    /// - en colonnes, gauche remonte au dossier parent, droite entre dans le dossier choisi.
    private func fleche(_ touche: UInt16) {
        let sel = Selection.shared
        journal("flèche \(touche) — sélection avant : \(sel.url?.lastPathComponent ?? "rien"), survol : \(survole?.url.lastPathComponent ?? "rien")")
        defer { journal("   après : \(Selection.shared.url?.lastPathComponent ?? "rien") (icônes par ligne : \(Selection.shared.colonne?.colonnesVisibles ?? -1))") }
        // Rien de sélectionné, mais la souris est posée sur un élément (il est grisé) : c'est de lui qu'on part,
        // dans SA colonne. Sans cela, les flèches agissaient sur la grande zone, à l'autre bout de la carte.
        if sel.url == nil, let dessous = survole, let c = survoleColonne { sel.choisir(dessous.url, c) }
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
    private func deplacer(dans liste: [URL], pas: Int, _ col: Column) {
        guard !liste.isEmpty else { return }
        guard let i = Selection.shared.url.flatMap({ liste.firstIndex(of: $0) }) else { choisirEtSuivre(liste[0], col); return }
        let j = i + pas
        guard liste.indices.contains(j) else { return }
        choisirEtSuivre(liste[j], col)
    }

    private func choisirEtSuivre(_ url: URL, _ col: Column) {
        Selection.shared.choisir(url, col)
        if QLPreviewPanel.sharedPreviewPanelExists(), let ql = QLPreviewPanel.shared(), ql.isVisible,
           let i = apercus.firstIndex(of: url) {   // l'aperçu suit la sélection
            apercu = url
            ql.currentPreviewItemIndex = i
        }
    }

    /// Ancien nom, encore utilisé par l'aperçu : flèches haut et bas.
    private func deplacerSelection(_ pas: Int) { fleche(pas > 0 ? 125 : 126) }

    // MARK: Menu contextuel (clic droit), calqué sur celui du Finder

    private var auDessus: NSWindow.Level { NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) }

    func menuContextuel(_ item: FileItem, event: NSEvent) {
        let url = item.url
        cible = url
        Selection.shared.choisir(url, survoleColonne)
        let m = NSMenu()
        @discardableResult
        func ajouter(_ titre: String, _ action: Selector, symbole: String? = nil, dans menu: NSMenu? = nil) -> NSMenuItem {
            let it = (menu ?? m).addItem(withTitle: titre, action: action, keyEquivalent: "")
            it.target = self
            if let symbole { it.image = NSImage(systemSymbolName: symbole, accessibilityDescription: nil) }
            return it
        }

        if survoleColonne?.estEtagere == true {
            ajouter("Retirer de l'étagère", #selector(mRetirerEtagere))
            m.addItem(.separator())
        }
        ajouter("Ouvrir", #selector(mOuvrir))
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
            m.addItem(withTitle: "Ouvrir avec", action: nil, keyEquivalent: "").submenu = sous
        }
        let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if v?.isUbiquitousItem == true {
            if v?.ubiquitousItemDownloadingStatus == .current {
                ajouter("Supprimer le téléchargement", #selector(mLiberer))
            } else {
                ajouter("Télécharger", #selector(mTelecharger))
            }
        }
        m.addItem(.separator())
        ajouter("Placer dans la corbeille", #selector(mCorbeille), symbole: "trash")
        m.addItem(.separator())
        ajouter("Lire les informations", #selector(mInfos))
        ajouter("Renommer", #selector(mRenommer))
        ajouter("Compresser « \(url.lastPathComponent) »", #selector(mCompresser))
        ajouter("Dupliquer", #selector(mDupliquer))
        ajouter("Créer un alias", #selector(mAlias))
        ajouter("Coup d'œil", #selector(mCoupDOeil))
        ajouter("Copier", #selector(mCopier))
        // Comme dans le Finder : avec la touche Option, « Copier » devient « Copier le chemin ».
        let chemin = ajouter("Copier « \(url.lastPathComponent) » en tant que chemin d'accès", #selector(mCopierChemin))
        chemin.isAlternate = true
        chemin.keyEquivalentModifierMask = [.option]
        m.addItem(.separator())
        ajouter("Partager…", #selector(mPartager), symbole: "square.and.arrow.up")
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
        let itTags = m.addItem(withTitle: "Tags", action: nil, keyEquivalent: "")
        itTags.image = NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
        itTags.submenu = tags
        m.addItem(.separator())
        ajouter("Afficher dans le Finder", #selector(mReveler))
        if item.isFolder {
            ajouter("Épingler en colonne", #selector(mEpingler))
            ajouter("Ajouter aux favoris", #selector(mFavori))
        }

        NSMenu.popUpContextMenu(m, with: event, for: host)
    }

    private func tagsDe(_ url: URL) -> [String] {
        var valeur: AnyObject?
        try? (url as NSURL).getResourceValue(&valeur, forKey: .tagNamesKey)
        return valeur as? [String] ?? []
    }

    private func erreur(_ texte: String, _ e: Error) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = texte
        a.informativeText = e.localizedDescription
        a.window.level = auDessus
        epingle = true
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// Fait une action sur le fichier visé, affiche l'erreur éventuelle, puis rafraîchit les colonnes.
    private func agir(_ quoi: String, _ action: (URL) throws -> Void) {
        guard let url = cible else { return }
        do { try action(url) } catch { erreur("Impossible de \(quoi) « \(url.lastPathComponent) »", error) }
        store.reloadAll()
    }

    /// Un nom libre dans le même dossier : « nom suffixe.ext », puis « nom suffixe 2.ext »…
    private func nomLibre(_ url: URL, suffixe: String, ext: String? = nil) -> URL {
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

    @objc private func mEpingler() { if let u = cible { store.ajouter(.folder(u.standardizedFileURL)) } }
    @objc private func mFavori() { if let u = cible { store.ajouterFavori(u) } }
    @objc private func mRetirerEtagere() {
        if let u = cible { Etagere.retirer(u, survoleColonne?.indexEtagere ?? 0); store.reloadAll() }
    }
    @objc private func mOuvrir() { if let u = cible { ouvrir(u) } }
    @objc private func mReveler() { if let u = cible { reveler(u) } }
    @objc private func mCoupDOeil() { if let u = cible { coupDOeil(u) } }

    @objc private func mOuvrirAvec(_ sender: NSMenuItem) {
        guard let u = cible, let app = sender.representedObject as? URL else { return }
        hide()
        NSWorkspace.shared.open([u], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    @objc private func mTelecharger() {
        agir("télécharger") { try FileManager.default.startDownloadingUbiquitousItem(at: $0) }
    }
    @objc private func mLiberer() {
        agir("libérer") { try FileManager.default.evictUbiquitousItem(at: $0) }
    }
    @objc private func mCorbeille() {
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
        agir("placer dans la corbeille") { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
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
    @objc private func mDupliquer() {
        agir("dupliquer") { try FileManager.default.copyItem(at: $0, to: self.nomLibre($0, suffixe: " copie")) }
    }
    @objc private func mAlias() {
        agir("créer un alias de") {
            let data = try $0.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
            try URL.writeBookmarkData(data, to: self.nomLibre($0, suffixe: " alias", ext: ""))
        }
    }
    @objc private func mCopierChemin() {
        guard let u = cible else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(u.path, forType: .string)
    }
    @objc private func mCopier() {
        guard let u = cible else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([u as NSURL])
    }
    @objc private func mTag(_ sender: NSMenuItem) {
        guard let nom = sender.representedObject as? String else { return }
        agir("modifier les tags de") {
            var tags = self.tagsDe($0)
            if let i = tags.firstIndex(of: nom) { tags.remove(at: i) } else { tags.append(nom) }
            try ($0 as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
        }
    }
    @objc private func mCompresser() {
        guard let u = cible else { return }
        let zip = nomLibre(u, suffixe: "", ext: "zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", u.path, zip.path]
        p.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.store.reloadAll() } }
        do { try p.run() } catch { erreur("Impossible de compresser « \(u.lastPathComponent) »", error) }
    }
    @objc private func mRenommer() {
        guard let u = cible else { return }
        let a = NSAlert()
        a.messageText = "Renommer « \(u.lastPathComponent) »"
        a.addButton(withTitle: "Renommer")
        a.addButton(withTitle: "Annuler")
        let champ = NSTextField(string: u.lastPathComponent)
        champ.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        a.accessoryView = champ
        a.window.initialFirstResponder = champ
        a.window.level = auDessus
        epingle = true
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let nom = champ.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nom.isEmpty, nom != u.lastPathComponent, !nom.contains("/") else { return }
        agir("renommer") { try FileManager.default.moveItem(at: $0, to: $0.deletingLastPathComponent().appendingPathComponent(nom)) }
    }
    @objc private func mInfos() {
        guard let u = cible else { return }
        let chemin = u.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Finder\"\nactivate\nopen information window of (POSIX file \"\(chemin)\" as alias)\nend tell"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err {
            erreur("Impossible d'afficher les informations", NSError(domain: "Side", code: 1, userInfo: [
                NSLocalizedDescriptionKey: (err[NSAppleScript.errorMessage] as? String) ?? "Le Finder n'a pas répondu."]))
        } else { hide() }
    }
    @objc private func mPartager() {
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
    private func apresApercu() {
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
    private func imagePourApercu(_ url: URL) -> URL? {
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
    private func toucheApercu(_ ev: NSEvent) -> Bool {
        guard ecouteur == nil, QLPreviewPanel.sharedPreviewPanelExists(),
              let ql = QLPreviewPanel.shared(), ql.isVisible else { return false }
        switch ev.keyCode {
        case 49, 53: fermerApercu()
        case 123, 124, 125, 126: fleche(ev.keyCode)   // mêmes déplacements qu'aperçu fermé
        default: return false
        }
        return true
    }

    // MARK: Affichage

    /// macOS réserve la place du Dock même sur un bureau en plein écran, où il est pourtant masqué.
    /// On reconnaît le plein écran (ou le Split View) à une fenêtre qui occupe toute la hauteur de
    /// l'écran, jusqu'à son bord bas : sur un bureau normal, aucune fenêtre ne passe sous le Dock ainsi.
    private func dockMasque(sur e: NSScreen) -> Bool {
        guard let numero = e.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let liste = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let ecran = CGDisplayBounds(numero)
        let moi = ProcessInfo.processInfo.processIdentifier
        for fenetre in liste {
            guard (fenetre[kCGWindowLayer as String] as? Int) == 0,
                  (fenetre[kCGWindowOwnerPID as String] as? pid_t) != moi,
                  let dico = fenetre[kCGWindowBounds as String] as? NSDictionary,
                  let cadre = CGRect(dictionaryRepresentation: dico), ecran.intersects(cadre) else { continue }
            if cadre.maxY >= ecran.maxY - 1 && cadre.height >= ecran.height - 60 && cadre.width >= ecran.width * 0.2 {
                return true
            }
        }
        return false
    }

    /// La carte flotte à quelques points des bords de l'écran, sous la barre des menus et l'encoche.
    /// La fenêtre, elle, va jusqu'au bord d'où vient la carte, pour que celle-ci glisse depuis ce bord.
    private func placer(sur e: NSScreen, anime: Bool) {
        let f = e.frame, m = Reglages.margeCarte, s = Reglages.debord
        let plafond = min(f.maxY - e.safeAreaInsets.top, e.visibleFrame.maxY)
        // La partie « Finder » garde sa largeur ; chaque colonne épinglée élargit la carte.
        // La carte a la même forme quel que soit le côté d'où elle arrive : seule sa position change.
        let dispo = f.width - 2 * m
        if store.largeurMax != dispo { store.largeurMax = dispo }
        let lw = Disposition.carte(store.columns.count, dispo)
        let h = (f.height * config.tailleHauteur).rounded()
        // Place du mini-Dock, de chaque côté de la carte (un seul côté à la fois).
        let d = Disposition.dock, p = config.apps ? config.dockPosition : ""
        let dG = p == "gauche" ? d : 0, dD = p == "droite" ? d : 0
        let dH = p == "haut" ? d : 0, dB = p == "bas" ? d : 0
        // Quand le Dock de macOS est visible, la carte se pose juste au-dessus (ou à côté) de lui.
        // En plein écran le Dock est masqué : la carte va alors jusqu'au bord de l'écran, comme avant.
        let v = dockMasque(sur: e) ? f : e.visibleFrame
        let x: CGFloat, y: CGFloat   // coin bas-gauche de la carte elle-même
        switch config.bord {
        case .plein:   // même taille que d'habitude, au milieu de l'écran (mini-Dock compris)
            if let libre = positionLibre, f.insetBy(dx: -1, dy: -1).contains(libre) {
                // Là où tu l'as posée, sans jamais sortir de l'écran.
                x = max(v.minX + m + dG, min(libre.x, v.maxX - m - lw - dD))
                y = max(v.minY + m + dB, min(libre.y - h, plafond - m - h - dH))
            } else {
                x = f.minX + ((f.width - lw - dG - dD) / 2).rounded() + dG
                y = v.minY + ((plafond - v.minY - h - dH - dB) / 2).rounded() + dB
            }
        case .haut: x = f.minX + ((f.width - lw) / 2).rounded(); y = plafond - m - h - dH
        case .bas: x = f.minX + ((f.width - lw) / 2).rounded(); y = v.minY + m + dB
        case .gauche: x = v.minX + m + dG; y = v.minY + ((plafond - v.minY - h) / 2).rounded()
        case .droite: x = v.maxX - m - lw - dD; y = v.minY + ((plafond - v.minY - h) / 2).rounded()
        }
        // Les zones de dépôt ont leur propre fenêtre. On retient où la placer : à droite de la carte,
        // sinon à gauche, sinon par-dessus son coin haut-droit.
        let g = Reglages.carreDepot + 8
        if f.maxX - m - (x + lw + dD) >= g {
            ancreDepot = NSPoint(x: x + lw + dD + 8, y: y + h)
        } else if (x - dG) - (f.minX + m) >= g {
            ancreDepot = NSPoint(x: x - dG - g, y: y + h)
        } else {
            ancreDepot = NSPoint(x: f.maxX - m - g, y: y + h - 56)
        }
        if !store.depotDehors { store.depotDehors = true }
        cadreSeule = NSRect(x: x, y: y, width: lw, height: h)
        // ens = la carte et son mini-Dock
        let ens = NSRect(x: x - dG, y: y - dB, width: lw + dG + dD, height: h + dH + dB)
        let fenetre: NSRect
        switch config.bord {
        case .haut: fenetre = NSRect(x: ens.minX, y: ens.minY - s, width: ens.width, height: f.maxY - ens.minY + s)
        case .bas: fenetre = NSRect(x: ens.minX, y: f.minY, width: ens.width, height: ens.maxY - f.minY + s)
        case .gauche: fenetre = NSRect(x: f.minX, y: ens.minY, width: ens.maxX - f.minX + s, height: ens.height)
        case .droite: fenetre = NSRect(x: ens.minX - s, y: ens.minY, width: f.maxX - ens.minX + s, height: ens.height)
        case .plein: fenetre = ens   // pas de glissement : la fenêtre a la taille de la carte
        }
        if store.margeHaut != 0 { store.margeHaut = 0 }
        repos = NSPoint(x: ens.minX - fenetre.minX, y: ens.minY - fenetre.minY)
        cadreCarte = ens
        panel.setFrame(fenetre, display: true)
        host.setFrameSize(ens.size)
        if !anime { host.setFrameOrigin(repos) }
        panel.invalidateShadow()
        majDepot()
    }

    /// Vrai si le glisser en cours transporte un fichier ou une image (et pas du simple texte).
    private func glisseContientFichier() -> Bool {
        let types = NSPasteboard(name: .drag).types ?? []
        return types.contains(.fileURL) || types.contains(.tiff) || types.contains(.png) || types.contains(.pdf)
            || types.contains(NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"))
    }

    /// Vrai si le glisser en cours transporte au moins un dossier, ou une entrée de la barre latérale.
    private func glisseContientDossier() -> Bool {
        let pb = NSPasteboard(name: .drag)
        if pb.string(forType: .string)?.hasPrefix(Glissable.prefixe) == true { return true }
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.contains { Fichiers.item($0).isFolder }
    }

    /// Position libre : la carte suit la souris pendant qu'on tire son en-tête.
    func deplacerCarte() {
        guard config.bord == .plein, visible, let e = ecran else { return }
        let ici = NSEvent.mouseLocation
        if prise == nil { prise = (ici, panel.frame.origin, cadreCarte) }
        guard let prise else { return }
        // On retient la carte dans l'écran, sous la barre des menus.
        let m = Reglages.margeCarte, f = e.frame
        let plafond = min(f.maxY - e.safeAreaInsets.top, e.visibleFrame.maxY)
        let dx = max(f.minX + m - prise.carte.minX, min(ici.x - prise.souris.x, f.maxX - m - prise.carte.maxX))
        let dy = max(f.minY + m - prise.carte.minY, min(ici.y - prise.souris.y, plafond - m - prise.carte.maxY))
        panel.setFrameOrigin(NSPoint(x: prise.fenetre.x + dx, y: prise.fenetre.y + dy))
        cadreSeule = cadreSeule.offsetBy(dx: prise.carte.minX + dx - cadreCarte.minX, dy: prise.carte.minY + dy - cadreCarte.minY)
        cadreCarte = prise.carte.offsetBy(dx: dx, dy: dy)
    }

    /// Fin du déplacement : Side retient l'endroit (coin haut-gauche de la carte, hors mini-Dock).
    func finDeplacement() {
        guard prise != nil, let e = ecran else { return }
        prise = nil
        let d = Disposition.dock, p = config.apps ? config.dockPosition : ""
        let coin = NSPoint(x: cadreCarte.minX + (p == "gauche" ? d : 0), y: cadreCarte.maxY - (p == "haut" ? d : 0))
        positionLibre = coin
        UserDefaults.standard.set([Double(coin.x), Double(coin.y)], forKey: "cartePosition")
        placer(sur: e, anime: false)   // replace aussi les zones de dépôt à côté
    }

    /// Oublie l'endroit choisi : la carte revient au centre de l'écran.
    func recentrerCarte() {
        positionLibre = nil
        UserDefaults.standard.removeObject(forKey: "cartePosition")
        if visible, let e = ecran { placer(sur: e, anime: false) }
    }

    /// Carte entièrement cachée derrière son bord d'écran : point de départ du vrai glissement
    /// (raccourci, souris, et surtout quatre doigts, où elle suit le geste).
    private var loin: NSPoint {
        let t = panel.frame.size, c = host.frame.size
        switch config.bord {
        case .haut: return NSPoint(x: repos.x, y: t.height)
        case .bas: return NSPoint(x: repos.x, y: -c.height)
        case .gauche: return NSPoint(x: -c.width, y: repos.y)
        case .droite: return NSPoint(x: t.width, y: repos.y)
        case .plein: return repos
        }
    }

    // MARK: Suivre les quatre doigts

    private var suiviDoigts = false
    private var ombreSuivi: TimeInterval = 0
    private var qSuivi: CGFloat = 0   // où en est la carte (0 = cachée, 1 = à sa place)
    /// Une capture vient d'arriver alors que Side est fermé : la zone s'affiche jusqu'à ce moment-là.
    private var captureJusqua: TimeInterval = 0
    private var captureVisible: Bool { ProcessInfo.processInfo.systemUptime < captureJusqua }
    private var zoneSuivie: NSRect?   // place finale de la zone de dépôt quand elle suit les doigts avec la carte

    /// Durée et courbe pour finir un trajet en partant à la vitesse donnée (fraction du trajet par seconde),
    /// puis en ralentissant jusqu'à l'arrêt. La pente de départ de la courbe = la vitesse des doigts.
    static func elan(reste: CGFloat, vitesse: CGFloat) -> (duree: TimeInterval, courbe: CAMediaTimingFunction) {
        let v = max(0, vitesse)
        guard reste > 0.001 else { return (0.15, CAMediaTimingFunction(name: .easeOut)) }
        // Assez de temps pour ralentir en douceur, sans traîner : la durée suit la vitesse.
        let duree = v > 0.01 ? min(0.4, max(0.18, Double(2.2 * reste / v))) : 0.3
        let pente = v * CGFloat(duree) / reste        // vitesse de départ, rapportée à la courbe
        let x1: CGFloat = 0.3
        let y1 = min(1, pente * x1)
        return (duree, CAMediaTimingFunction(controlPoints: Float(x1), Float(y1), 0.35, 1))
    }

    /// Quatre doigts commencent à glisser : pour ouvrir, la carte arrive cachée, prête à suivre ;
    /// pour fermer, elle quitte sa place avec eux.
    func commencerSuivi(fermeture: Bool = false) {
        if fermeture {
            guard visible else { return }
            journal("déclencheur : quatre doigts (suivi de fermeture)")
            suiviDoigts = true
            // Cadenas ouvert : la zone de dépôt part avec la carte, au même rythme que les doigts.
            if let zone = depotPanel, zone.isVisible, !config.depotReste, !store.glisse {
                zoneSuivie = zone.frame
                animationDepot = true
            }
            return
        }
        guard !visible, let e = ecranSous(NSEvent.mouseLocation) else { return }
        journal("déclencheur : quatre doigts (suivi)")
        epingle = true
        show(sur: e, suivi: true)
        suiviDoigts = true
    }

    /// p : 0 = cachée, 1 = à sa place. Au-delà, elle résiste, comme un élastique.
    func suivreDoigts(_ p: CGFloat) {
        guard suiviDoigts, visible else { return }
        let q = p <= 1 ? max(0, p) : 1 + min(0.5, p - 1) * 0.12
        qSuivi = q
        let a = loin, b = repos
        if config.bord == .plein {
            panel.alphaValue = min(1, q)
        } else {
            host.setFrameOrigin(NSPoint(x: a.x + (b.x - a.x) * q, y: a.y + (b.y - a.y) * q))
            panel.alphaValue = min(1, q * 3)
        }
        // La zone de dépôt suit, décalée exactement comme la carte, avec la même transparence.
        if let r = zoneSuivie, let zone = depotPanel {
            zone.setFrameOrigin(NSPoint(x: r.minX + (a.x - b.x) * (1 - q), y: r.minY + (a.y - b.y) * (1 - q)))
            zone.alphaValue = panel.alphaValue
        }
        let maintenant = ProcessInfo.processInfo.systemUptime
        if maintenant - ombreSuivi > 0.05 { ombreSuivi = maintenant; panel.invalidateShadow() }
    }

    /// Doigts levés : la carte finit de s'ouvrir (ou revient à sa place), sinon elle repart derrière le bord.
    /// elan : vitesse de la carte au moment du lâcher (en « carte entière par seconde », sens d'ouverture).
    /// La suite du mouvement part exactement à cette vitesse, puis ralentit : pas d'à-coup.
    func lacherDoigts(ouvrir: Bool, elan: CGFloat = 0) {
        guard suiviDoigts else { return }
        suiviDoigts = false
        guard visible else { return }
        let reste = ouvrir ? abs(1 - qSuivi) : qSuivi          // chemin restant, en fraction du trajet
        let vers = ouvrir ? elan * (qSuivi <= 1 ? 1 : -1) : -elan   // vitesse dans le sens où elle va finir
        let suite = AppDelegate.elan(reste: reste, vitesse: vers)
        let zoneArrivee = zoneSuivie
        zoneSuivie = nil
        guard ouvrir else { hide(suite: suite); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = suite.duree
            ctx.timingFunction = suite.courbe
            host.animator().setFrameOrigin(repos)
            panel.animator().alphaValue = 1
            if let r = zoneArrivee, let zone = depotPanel {
                zone.animator().setFrame(r, display: true)
                zone.animator().alphaValue = 1
            }
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.invalidateShadow()
            if zoneArrivee != nil {
                self.animationDepot = false
                self.depotPanel?.invalidateShadow()
                self.majDepot()
            }
        })
    }

    private var duree: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
    }

    /// La fenêtre des zones de dépôt. Indépendante de la carte : elle reste à l'écran, sur tous les
    /// bureaux, tant qu'une zone contient quelque chose — même quand Side est fermé.
    private func creerDepot() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Reglages.carreDepot, height: Reglages.carreDepot),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.animationBehavior = .none
        // Contenu : la poignée en haut, les zones en dessous.
        let conteneur = NSView(frame: p.contentView!.bounds)
        let zones = NSHostingView(rootView: ZonesFlottantes(store: store))
        zones.frame = NSRect(x: 0, y: 0, width: conteneur.bounds.width, height: conteneur.bounds.height - PoigneeDepot.hauteur)
        zones.autoresizingMask = [.width, .height]
        let poignee = PoigneeDepot(frame: NSRect(x: 0, y: conteneur.bounds.height - PoigneeDepot.hauteur,
                                                 width: conteneur.bounds.width, height: PoigneeDepot.hauteur))
        poignee.autoresizingMask = [.width, .minYMargin]
        conteneur.addSubview(zones)
        _ = poignee   // plus affichée : la zone se déplace en l'attrapant par son fond
        p.contentView = conteneur
        depotPanel = p
        if let xy = UserDefaults.standard.array(forKey: "depotPosition") as? [Double], xy.count == 2 {
            ancrePerso = NSPoint(x: xy[0], y: xy[1])
        }
        // Quand tu la déplaces, Side retient l'endroit (coin haut-gauche) et ne la replace plus tout seul.
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            guard let self, !self.placementAuto, !self.animationDepot else { return }
            let coin = NSPoint(x: p.frame.minX, y: p.frame.maxY)
            self.ancrePerso = coin; self.journal("zone déplacée, position retenue : \(coin)")
            UserDefaults.standard.set([Double(coin.x), Double(coin.y)], forKey: "depotPosition")
        }
        // Mise à jour dès que quelque chose change : glisser en cours, zone remplie ou vidée, zone ajoutée.
        suiviDepot = [
            config.$depotReste.sink { [weak self] _ in DispatchQueue.main.async { self?.majDepot() } },
            store.$glisse.sink { [weak self] _ in DispatchQueue.main.async { self?.majDepot() } },
            store.$depotRempli.sink { [weak self] _ in DispatchQueue.main.async { self?.majDepot() } },
            store.$etageres.sink { [weak self] _ in DispatchQueue.main.async { self?.majDepot() } },
        ]
    }

    /// Affiche, place ou cache la fenêtre des zones de dépôt.
    private func majDepot() {
        guard let depotPanel else { return }
        // Visibles : pendant un glisser, ou si une zone est remplie — et, cadenas ouvert, seulement tant que Side est ouvert.
        let remplies = store.etageres.filter { !$0.items.isEmpty }.count
        let visibles = store.glisse ? store.etageres.count : ((visible || config.depotReste || captureVisible) ? remplies : 0)
        guard visibles > 0 else {
            // On laisse l'animation de disparition se terminer avant de retirer la fenêtre.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                let encore = self.store.glisse
                    || ((self.visible || self.config.depotReste || self.captureVisible) && self.store.etageres.contains { !$0.items.isEmpty })
                if !encore {
                    depotPanel.orderOut(nil)
                    // Vide et disparue : la prochaine fois, elle revient à sa place, à droite de la carte.
                    if !self.store.etageres.contains(where: { !$0.items.isEmpty }) {
                        self.ancrePerso = nil
                        UserDefaults.standard.removeObject(forKey: "depotPosition")
                    }
                }
            }
            return
        }
        let hauteur = CGFloat(store.etageres.count) * (Reglages.carreDepot + 8) + PoigneeDepot.hauteur
        // À l'endroit où tu l'as posée, sinon à côté de la carte ; toujours dans l'écran.
        var coin = ancrePerso ?? ancreDepot
        if let ecran = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(coin) }) ?? NSScreen.main {
            coin.x = min(max(coin.x, ecran.frame.minX + 4), ecran.frame.maxX - Reglages.carreDepot - 4)
            coin.y = min(max(coin.y, ecran.frame.minY + Reglages.carreDepot + 4), ecran.frame.maxY - 4)
        }
        let cadre = NSRect(x: coin.x, y: coin.y - hauteur, width: Reglages.carreDepot, height: hauteur)
        if depotPanel.frame != cadre {
            placementAuto = true
            depotPanel.setFrame(cadre, display: true)
            DispatchQueue.main.async { self.placementAuto = false }
        }
        // Filet de sécurité : une zone affichée n'est jamais laissée transparente (hors animation d'arrivée).
        if !animationDepot && depotPanel.alphaValue < 1 { depotPanel.alphaValue = 1 }
        depotPanel.orderFrontRegardless()
        journal("zones affichées à \(cadre) | transparence=\(depotPanel.alphaValue) animation=\(animationDepot) ancrePerso=\(String(describing: ancrePerso)) visible=\(depotPanel.isVisible)")
        depotPanel.invalidateShadow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { depotPanel.invalidateShadow() }
    }

    /// La zone de dépôt suit la souris pendant qu'on la tire par son fond ; l'endroit est retenu au passage.
    private var priseDepot: (souris: NSPoint, origine: NSPoint)?
    func deplacerDepot() {
        guard let zone = depotPanel else { return }
        let ici = NSEvent.mouseLocation
        if priseDepot == nil { priseDepot = (ici, zone.frame.origin) }
        guard let prise = priseDepot else { return }
        zone.setFrameOrigin(NSPoint(x: prise.origine.x + ici.x - prise.souris.x, y: prise.origine.y + ici.y - prise.souris.y))
    }
    func finDeplacementDepot() {
        priseDepot = nil
        majDepot()   // la garde dans l'écran
    }

    /// Oublie l'endroit choisi à la main : la fenêtre des zones revient à côté de la carte.
    func replacerDepot() {
        ancrePerso = nil
        UserDefaults.standard.removeObject(forKey: "depotPosition")
        majDepot()
    }

    /// Le voile de flou : une fenêtre de la taille de l'écran, juste sous la carte.
    /// Elle laisse passer les clics et les glisser-déposer : on peut toujours attraper un fichier dans l'app derrière.
    private func montrerFlou(sur e: NSScreen) {
        guard config.flou else { cacherFlou(); return }
        if voile == nil {
            let v = NSPanel(contentRect: e.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            v.isOpaque = false
            v.backgroundColor = .clear
            v.hasShadow = false
            v.ignoresMouseEvents = true
            v.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
            v.animationBehavior = .none
            let effet = NSVisualEffectView(frame: NSRect(origin: .zero, size: e.frame.size))
            effet.material = .hudWindow   // un flou qui laisse deviner ce qu'il y a derrière
            effet.blendingMode = .behindWindow
            effet.state = .active
            effet.autoresizingMask = [.width, .height]
            // Par-dessus le flou, une teinte : sombre en mode sombre, claire en mode clair.
            let teinte = NSView(frame: effet.bounds)
            teinte.wantsLayer = true
            teinte.autoresizingMask = [.width, .height]
            effet.addSubview(teinte)
            teinteVoile = teinte
            v.contentView = effet
            voile = v
        }
        guard let voile else { return }
        let sombre = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        voile.appearance = NSAppearance(named: sombre ? .darkAqua : .aqua)
        teinteVoile?.layer?.backgroundColor = (sombre ? NSColor.black : NSColor.white).withAlphaComponent(0.16).cgColor
        voile.collectionBehavior = panel.collectionBehavior
        voile.setFrame(e.frame, display: true)
        if !voile.isVisible { voile.alphaValue = 0 }
        voile.orderFrontRegardless()
        panel.orderFrontRegardless()   // la carte reste au-dessus du voile
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            voile.animator().alphaValue = CGFloat(config.flouForce)
        }
    }

    private func cacherFlou(immediat: Bool = false) {
        guard let voile, voile.isVisible else { return }
        if immediat { voile.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            voile.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.visible else { return }
            voile.orderOut(nil)
        })
    }

    /// Avec l'argument --journal, note dans la sortie d'erreur chaque ouverture et fermeture (pour diagnostiquer).
    private func journal(_ texte: String) {
        guard CommandLine.arguments.contains("--journal") else { return }
        fputs(String(format: "%.1f ", ProcessInfo.processInfo.systemUptime - lancement) + texte + "\n", stderr)
    }

    private func show(sur e: NSScreen, suivi: Bool = false) {
        journal("ouverture (déjà visible : \(visible))")
        ecran = e
        debutDehors = nil
        store.reloadAll()
        if visible { placer(sur: e, anime: false); return }
        visible = true
        captureJusqua = 0   // Side ouvert : la zone suit de nouveau la carte
        dernierBasculement = ProcessInfo.processInfo.systemUptime
        aQuitteCoin = false
        suivreBureaux(doitSuivre())
        Selection.shared.choisir(nil, nil)
        // Le cercle ne peut refermer qu'après un arrêt de la souris : la fin du geste d'ouverture ne compte pas.
        attendrePause = true
        derniereSecousse = ProcessInfo.processInfo.systemUptime
        trace = []
        // Toute première ouverture : la présentation de bienvenue.
        if store.accueil == nil && !UserDefaults.standard.bool(forKey: "accueilVu") { store.accueil = 0 }
        placer(sur: e, anime: true)
        let reduit = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // La carte part de derrière le bord de l'écran et glisse jusqu'à sa place.
        // « Réduire les animations » : fondu seul.
        host.setFrameOrigin(reduit && !suivi ? repos : loin)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        montrerFlou(sur: e)
        // Cadenas ouvert : la zone de dépôt arrive avec la carte, dans le même mouvement.
        var arrivee: NSRect?
        if let zone = depotPanel, zone.isVisible, !config.depotReste, !store.glisse {
            animationDepot = true
            arrivee = zone.frame
            zone.alphaValue = 0
            // Elle part du même endroit que la carte, décalée d'autant : les deux arrivent ensemble.
            if !reduit || suivi { zone.setFrame(zone.frame.offsetBy(dx: host.frame.origin.x - repos.x, dy: host.frame.origin.y - repos.y), display: false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.zoneSuivie == nil else { return }   // les doigts la tiennent encore
                self.animationDepot = false
                zone.invalidateShadow()
            }
        }
        Doigts.carteOuverte = true
        if suivi {   // ce sont les doigts qui font avancer la carte, et la zone de dépôt avec elle
            zoneSuivie = arrivee
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            // Un vrai glissement depuis le bord : part avec élan, puis ralentit longuement pour se poser en douceur.
            ctx.duration = reduit ? 0.15 : 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            if let arrivee, let zone = depotPanel {
                zone.animator().setFrame(arrivee, display: true)
                zone.animator().alphaValue = 1
            }
            host.animator().setFrameOrigin(repos)
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.panel.invalidateShadow() }
    }

    private func hide(immediat: Bool = false, suite: (duree: TimeInterval, courbe: CAMediaTimingFunction)? = nil) {
        guard visible else { return }
        journal("fermeture <- " + Thread.callStackSymbols.dropFirst().prefix(3).map { $0.split(separator: " ").dropFirst(3).first.map(String.init) ?? "?" }.joined(separator: " <- "))
        visible = false
        suiviDoigts = false
        Doigts.carteOuverte = false
        dernierBasculement = ProcessInfo.processInfo.systemUptime
        store.lanceurOuvert = false   // le panneau des applications part avec la carte
        epingle = false
        arme = false
        store.memoriser()
        cacherFlou(immediat: immediat)
        // Cadenas ouvert : la zone de dépôt part avec la carte, dans le même mouvement, comme une seule fenêtre.
        let zone = depotPanel
        let ensemble = !immediat && !config.depotReste && !store.glisse && zone?.isVisible == true
        if !ensemble { majDepot() }
        if immediat { panel.orderOut(nil); return }
        let reduit = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fondu = config.bord == .plein
        let glisse = !reduit && !fondu
        if ensemble { animationDepot = true }
        zoneSuivie = nil
        // La zone fait le même trajet que la carte, jusque derrière le bord : elles partent ensemble.
        let trajet = NSPoint(x: loin.x - host.frame.origin.x, y: loin.y - host.frame.origin.y)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduit ? 0.12 : 0.26   // la fermeture est plus brève que l'ouverture
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0.4)
            // Lâchée par les doigts en pleine course : elle continue sur sa lancée, sans s'arrêter.
            if let suite, glisse { ctx.duration = suite.duree; ctx.timingFunction = suite.courbe }
            if glisse { host.animator().setFrameOrigin(loin) }
            panel.animator().alphaValue = 0
            if ensemble, let zone {
                if glisse {
                    zone.animator().setFrame(zone.frame.offsetBy(dx: trajet.x, dy: trajet.y), display: true)
                }
                zone.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            guard let self else { return }
            if ensemble, let zone {
                if !self.visible { zone.orderOut(nil) }
                zone.alphaValue = 1
                self.animationDepot = false
                self.majDepot()   // la remet à sa place (et l'affiche si la carte a été rouverte entre-temps)
            }
            guard !self.visible else { return }
            self.panel.orderOut(nil)
        })
    }

    /// Normalement la carte appartient à son bureau et part avec lui. Tant que Commande est enfoncée,
    /// elle est au contraire présente sur tous les bureaux : elle reste donc en place pendant le
    /// changement, sans disparaître puis réapparaître.
    /// La carte doit-elle suivre au changement de bureau ? Dépend du réglage et de la touche Commande.
    private func doitSuivre(_ commande: Bool = NSEvent.modifierFlags.contains(.command)) -> Bool {
        switch config.suivi {
        case "toujours": return true
        case "jamais": return false
        default: return commande
        }
    }

    private func suivreBureaux(_ oui: Bool) {
        suitBureaux = oui
        panel.collectionBehavior = oui
            ? [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            : [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        voile?.collectionBehavior = panel.collectionBehavior
    }

    // MARK: Surveillance de la souris

    private func dansCoin(_ p: NSPoint, _ e: NSScreen, marge: CGFloat = 0) -> Bool {
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

    private func tick() {
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
                journal("glisser détecté | visible=\(visible) appGlissee=\(appGlissee != nil) types=\(NSPasteboard(name: .drag).types?.map(\.rawValue).prefix(4) ?? [])")
            }
        } else if glisserActif {
            glisserActif = false
            // Une icône du mini-Dock lâchée pendant que la croix est affichée : on la retire, comme dans le Dock.
            // Lâchée ailleurs (ou ramenée dans le mini-Dock) : elle reprend sa place.
            if let icone = appGlissee {
                appGlissee = nil
                let retirer = croix?.isVisible == true
                croix?.orderOut(nil)
                sortieDuDock = nil
                if retirer { icone.retirer() }
                store.appEnGlisse = nil
            }
            // Le glisser est fini : on retire les zones restées vides (il en reste toujours une).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.store.nettoyerZones() }
        }
        if appGlissee != nil, glisserActif { suivreIconeGlissee() }
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
        let montrer = (glisserActif && visible && appGlissee == nil) || zoneSeule || forcerGlisse || (visible && store.accueil == 3)
            || ProcessInfo.processInfo.systemUptime - depotEnCours < 1.5
        // Un glisser commence alors que toutes les zones sont déjà remplies : une zone vide apparaît en dessous,
        // pour pouvoir poser ailleurs. Elle disparaîtra d'elle-même si on ne s'en sert pas.
        if montrer, !store.glisse, glisserActif, !store.etageres.contains(where: { $0.items.isEmpty }) {
            store.ajouterZone()
        }
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
        if cadreCarte.insetBy(dx: -24, dy: -24).contains(p) {
            debutDehors = nil
            if epingle && !modeTest { epingle = false }
            return
        }
        if epingle || NSEvent.pressedMouseButtons != 0 { debutDehors = nil; return }
        if debutDehors == nil { debutDehors = Date() }
        if Date().timeIntervalSince(debutDehors!) >= Reglages.delaiFermeture { hide() }
    }
}

@main
enum Main {
    static func main() {
        reprendreAnciensReglages()
        deplacerAncienDossier()
        let app = NSApplication.shared
        app.delegate = AppDelegate.shared
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// L'app s'appelait « Tiroir » (identifiant com.gauthieraube.tiroir). Au premier lancement sous le nom Side,
    /// on recopie une fois les anciens réglages (favoris, raccourci, position…) pour ne rien perdre.
    /// Les données (historique du copier-coller, fichiers déposés) étaient rangées dans « Application Support/Nook ».
    /// On renomme ce dossier une fois en « Side », avant que l'app ne s'en serve.
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
