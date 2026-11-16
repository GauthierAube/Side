// Les réglages de Side : valeurs fixes (Reglages) et choix de l'utilisateur (Config).
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum Reglages {
    static let largeurAjout: CGFloat = 52
    static let margeCarte: CGFloat = 12             // espace entre la carte et les bords de l'écran
    static let rayonCarte: CGFloat = 24
    static let delaiOuverture: TimeInterval = 0.03  // souris immobile dans le coin
    static let carreDepot: CGFloat = 198            // largeur d'une zone de dépôt flottante (celle de l'étagère de Dropover)
    static let hauteurDepot: CGFloat = 207          // sa hauteur
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
        case .aucun: return String(localized: "Aucun")
        case .hautGauche: return String(localized: "En haut à gauche")
        case .hautDroite: return String(localized: "En haut à droite")
        case .basGauche: return String(localized: "En bas à gauche")
        case .basDroite: return String(localized: "En bas à droite")
        }
    }
}

enum Bord: String, CaseIterable {
    case haut, bas, gauche, droite, plein
    var titre: String {
        switch self {
        case .haut: return String(localized: "Du haut")
        case .bas: return String(localized: "Du bas")
        case .gauche: return String(localized: "De la gauche")
        case .droite: return String(localized: "De la droite")
        case .plein: return String(localized: "Position libre, en fondu")
        }
    }
    var lateral: Bool { self == .gauche || self == .droite }
}

final class Config: ObservableObject {
    static let shared = Config()
    private let d = UserDefaults.standard

    @Published var coin: Coin { didSet { d.set(coin.rawValue, forKey: "coin") } }
    @Published var bord: Bord { didSet { d.set(bord.rawValue, forKey: "bord"); GestePanneauBas.enHaut = bord == .bas } }   // version personnelle : le tiroir passe au bord opposé
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
    /// Place réservée dans la fenêtre pour que la liste du presse-papiers se déroule à l'opposé de la carte
    /// (sous le mini-Dock quand la carte vient du haut, au-dessus quand elle vient du bas). 0 = par-dessus la carte.
    @Published var presseDehors: CGFloat = 0
    /// Taille des icônes du mini-Dock, en points.
    @Published var tailleDock: Double { didSet { d.set(tailleDock, forKey: "tailleDock") } }
    /// De combien l'icône sous le pointeur grossit dans le mini-Dock (1 = pas du tout, 2 = deux fois plus grande).
    @Published var grossissement: Double { didSet { d.set(grossissement, forKey: "grossissement") } }
    /// Le bouton « Apps » à gauche du mini-Dock : toutes les applications, avec une recherche.
    @Published var lanceur: Bool { didSet { d.set(lanceur, forKey: "lanceur") } }
    @Published var appsOuvertes: Bool { didSet { d.set(appsOuvertes, forKey: "appsOuvertes") } }
    @Published var appsFavoris: Bool { didSet { d.set(appsFavoris, forKey: "appsFavoris") } }
    /// Emplacements des apps favorites, et des apps ouvertes qu'on a choisi de masquer.
    @Published var appsFavorites: [String] { didSet { d.set(appsFavorites, forKey: "appsFavorites") } }
    @Published var appsMasquees: [String] { didSet { d.set(appsMasquees, forKey: "appsMasquees") } }
    /// L'ordre des icônes du mini-Dock, choisi en les glissant. Une app absente de la liste se range à la fin.
    @Published var appsOrdre: [String] { didSet { d.set(appsOrdre, forKey: "appsOrdre") } }
    /// Raccourcis de l'app « Raccourcis » de macOS affichés dans la barre latérale (par leur nom).
    @Published var raccourcis: [String] { didSet { d.set(raccourcis, forKey: "raccourcis") } }
    /// Historique du copier-coller, et faut-il y garder aussi les mots de passe (affichés masqués).
    @Published var historique: Bool {
        didSet { d.set(historique, forKey: "historique"); if !historique { PressePapiers.shared.toutEffacer() } }
    }
    @Published var historiqueSecrets: Bool { didSet { d.set(historiqueSecrets, forKey: "historiqueSecrets") } }
    /// Collage en cascade : ⌘ gardé enfoncé, V de nouveau pour choisir parmi les 5 derniers copiés (CollageCascade.swift).
    @Published var collageCascade: Bool { didSet { d.set(collageCascade, forKey: "collageCascade") } }
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
    /// Combien de dossiers la rubrique « Dossiers récents » affiche.
    @Published var nombreDossiers: Int {
        didSet { d.set(nombreDossiers, forKey: "nombreDossiers"); Fichiers.nombreDossiers = nombreDossiers; AppDelegate.shared.store.reloadAll() }
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
    // Clé propre au Finder : « raccourciTouche » est aussi la clé du raccourci de la grille (reprise de Square).
    @Published var touche: Int { didSet { d.set(touche, forKey: "finderRaccourciTouche") } }
    @Published var mods: Int { didSet { d.set(mods, forKey: "raccourciMods") } }
    @Published var libelle: String { didSet { d.set(libelle, forKey: "raccourciLibelle") } }

    /// Les apps gardées dans le Dock de macOS, dans l'ordre (lues dans ses réglages, sans autorisation à demander).
    static func appsDuDock() -> [String] {
        let tuiles = UserDefaults(suiteName: "com.apple.dock")?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        var vues = Set<String>()
        return tuiles.compactMap { tuile -> String? in
            guard let donnees = tuile["tile-data"] as? [String: Any],
                  let fichier = donnees["file-data"] as? [String: Any],
                  let adresse = fichier["_CFURLString"] as? String,
                  let url = URL(string: adresse) ?? URL(string: adresse.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""),
                  url.isFileURL else { return nil }
            let chemin = url.standardizedFileURL.path
            guard chemin.hasSuffix(".app"), FileManager.default.fileExists(atPath: chemin), vues.insert(chemin).inserted else { return nil }
            return chemin
        }
    }

    private init() {
        coin = d.string(forKey: "coin").flatMap(Coin.init) ?? .basGauche
        bord = d.string(forKey: "bord").flatMap(Bord.init) ?? .haut
        tailleHauteur = d.object(forKey: "tailleHauteur") as? Double ?? 0.53
        tailleLargeur = d.object(forKey: "tailleLargeur") as? Double ?? 0.25
        ajuster = d.object(forKey: "ajuster") as? Bool ?? true
        tailleColonne = d.object(forKey: "tailleColonne") as? Double ?? 248
        fermerEnSortant = d.bool(forKey: "fermerEnSortant")
        fermerAuClic = d.object(forKey: "fermerAuClic") as? Bool ?? true
        ouverture = d.string(forKey: "ouverture")
            ?? Fichiers.para().first(where: { $0.url.lastPathComponent.hasPrefix("02") })?.url.path ?? ""
        largeurZone = d.object(forKey: "largeurZone") as? Double ?? 438
        opacite = d.object(forKey: "opacite") as? Double ?? 0.14
        tailleCoin = d.object(forKey: "tailleCoin") as? Double ?? 50
        sensibilite = d.object(forKey: "sensibilite") as? Double ?? 0.67
        largeurSeule = d.object(forKey: "largeurSeule") as? Double ?? 0.53
        largeurMiller = d.object(forKey: "largeurMiller") as? Double ?? 220
        suivi = d.string(forKey: "suivi") ?? "commande"
        largeurAvec = d.object(forKey: "largeurAvec") as? Double ?? 0.7
        memeLargeur = d.bool(forKey: "memeLargeur")
        apps = d.object(forKey: "apps") as? Bool ?? false   // le mini-Dock n'est plus proposé (12/11/2026) : masqué au départ
        dockPosition = d.string(forKey: "dockPosition") ?? "bas"
        tailleDock = d.object(forKey: "tailleDock") as? Double ?? 45
        grossissement = d.object(forKey: "grossissement") as? Double ?? 1.25
        lanceur = d.object(forKey: "lanceur") as? Bool ?? false
        appsOuvertes = d.object(forKey: "appsOuvertes") as? Bool ?? true
        appsFavoris = d.object(forKey: "appsFavoris") as? Bool ?? true
        if let enregistrees = d.stringArray(forKey: "appsFavorites") {
            appsFavorites = enregistrees
        } else {
            // Premier lancement : le mini-Dock reprend les apps du Dock de macOS, dans le même ordre.
            // Enregistré tout de suite : ensuite, le mini-Dock vit sa vie.
            let duDock = Config.appsDuDock()
            appsFavorites = duDock
            if !duDock.isEmpty { d.set(duDock, forKey: "appsFavorites") }
        }
        appsMasquees = d.stringArray(forKey: "appsMasquees") ?? []
        appsOrdre = d.stringArray(forKey: "appsOrdre") ?? []
        raccourcis = d.stringArray(forKey: "raccourcis") ?? []
        historique = d.object(forKey: "historique") as? Bool ?? true
        historiqueSecrets = d.object(forKey: "historiqueSecrets") as? Bool ?? true
        collageCascade = d.object(forKey: "collageCascade") as? Bool ?? true
        flou = d.bool(forKey: "flou")
        flouForce = d.object(forKey: "flouForce") as? Double ?? 1
        fermerApresDepot = d.object(forKey: "fermerApresDepot") as? Bool ?? true
        depotReste = d.object(forKey: "depotReste") as? Bool ?? true
        capturesAuto = d.object(forKey: "capturesAuto") as? Bool ?? true
        secouer = d.object(forKey: "secouer") as? Bool ?? false
        quatreDoigts = d.object(forKey: "quatreDoigts") as? Bool ?? true
        sensDoigts = d.string(forKey: "sensDoigts") ?? "bas"
        cercle = d.object(forKey: "gestePerso") as? Bool ?? true
        var entrees = d.stringArray(forKey: "barre") ?? ["recents", "dossiers", "icloud", "maison", "applications", "tags", "disques", "reseau"]
        // La rubrique Réseau est arrivée après coup : on l'ajoute une fois aux réglages déjà enregistrés.
        if !d.bool(forKey: "barreReseauAjoutee") {
            d.set(true, forKey: "barreReseauAjoutee")
            if !entrees.contains("reseau") { entrees.append("reseau"); d.set(entrees, forKey: "barre") }
        }
        barre = entrees
        extensions = Fichiers.extensions
        dossiersEnHaut = Fichiers.dossiersEnHaut
        nombreDossiers = d.object(forKey: "nombreDossiers") as? Int ?? 6
        rechercheMac = d.bool(forKey: "rechercheMac")
        tailleIcones = d.object(forKey: "tailleIcones") as? Double ?? 64
        espacement = d.object(forKey: "espacement") as? Double ?? 12
        tailleTexte = d.object(forKey: "tailleTexte") as? Double ?? 12
        texteADroite = d.bool(forKey: "texteADroite")
        infos = d.bool(forKey: "infos")
        apercus = d.object(forKey: "apercus") as? Bool ?? true
        // Avant le 15/11/2026, le Finder et la grille écrivaient la même clé « raccourciTouche ». On ne reprend
        // l'ancienne valeur que si elle est sûrement celle du Finder (raccourci du Finder choisi, grille jamais touchée).
        if let t = d.object(forKey: "finderRaccourciTouche") as? Int { touche = t }
        else if d.string(forKey: "raccourciLibelle") != nil, d.string(forKey: "raccourciNom") == nil,
                let t = d.object(forKey: "raccourciTouche") as? Int { touche = t }
        else { touche = -2 }
        mods = d.integer(forKey: "raccourciMods")
        libelle = d.string(forKey: "raccourciLibelle") ?? "⌘@"
    }
}
