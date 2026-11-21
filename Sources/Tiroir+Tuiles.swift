// La liste des tuiles du tiroir et leur géométrie.
// Partie de PanneauBas (PanneauBas.swift), rangée à part le 15/11/2026 sans changement.

import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

extension PanneauBas {
    // MARK: Les tuiles (la liste est la vôtre : bouton « + » du panneau)
    /// Décalage de la bande de tuiles, retenu d'une fois sur l'autre.
    var défilement: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "panneauBasDéfilement")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "panneauBasDéfilement") }
    }

    /// Avec ou sans fond derrière les tuiles. Sans fond, le flou est masqué (les tuiles et le dépôt d'applications restent).
    func majFond() {
        guard let fond else { return }
        let avec = ConfigTiroir.commun.fond
        fond.maskImage = avec ? nil : NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }
        // Sans fond, le tiroir garde un voile presque invisible : une zone tout à fait transparente laisserait passer
        // les clics et les glisser à l'application de derrière.
        teinte?.presqueInvisible = !avec
        teinte?.needsDisplay = true
        fond.window?.invalidateShadow()
    }
    var médias: [MediaBas] { ConfigTiroir.commun.medias }
    /// La largeur du coin multimédia, la même pour tous ses éléments ; rien du tout s'il est vide.
    var largeurTête: CGFloat {
        guard !médias.isEmpty else { return 0 }
        let place = (écranDuTiroir?.visibleFrame.width ?? 1440) - 2 * marge      // jamais plus large que la bande
        guard uneApp else { return min(LecteurYouTubeBas.largeurCommune, place) }
        // Une app à la fois : quand la place manque, c'est le coin multimédia qui cède d'abord (jusqu'à sa largeur minimum),
        // pour que l'application garde au moins la largeur qu'elle exige, comme dans les vues partagées de macOS.
        let tiroir = (panneau?.frame.width ?? place + 2 * marge) - 2 * marge
        let libre = tiroir - largeurAppMini - largeurColonne - 2 * marge
        return max(LecteurYouTubeBas.largeurMini, min(LecteurYouTubeBas.largeurCommune, place, libre))
    }
    /// La plus grande des largeurs minimum des applications du tiroir (360 points si aucune n'en impose).
    var largeurAppMini: CGFloat {
        max(360, emprunts.compactMap { largeursMini[$0.cléTaille] }.max() ?? 0)
    }
    /// Où commencent les tuiles des applications, après le coin multimédia.
    var débutTuiles: CGFloat { médias.isEmpty || (agrandi && uneApp) ? 0 : largeurTête + marge }
    /// Le coin multimédia montre un seul de ses éléments, au choix (retenu). Les autres continuent de jouer, masqués.
    var média: String {
        get {
            let m = UserDefaults.standard.string(forKey: "panneauBasMédia") ?? "youtube"
            return médias.contains { $0.id == m } ? m : (médias.first?.id ?? "")
        }
        set { UserDefaults.standard.set(newValue, forKey: "panneauBasMédia") }
    }
    /// Les numéros des fenêtres rangées dans le tiroir, pour Square : il ne les met ni dans sa grille ni dans son carrousel.
    func publierFenêtres() {
        // Avec la fenêtre du volet d'une vue (VoletVue) : elle non plus ne doit pas être agrandie par le plein écran.
        let ids = (emprunts.filter { $0.nom != enGrand }.compactMap { numéros[$0.nom] }.map { Int($0) } + VoletVue.commun.numéros).sorted()
        PanneauBas.numerosDuTiroir = Set(ids + [panneau?.windowNumber ?? -1])
        let d = UserDefaults.standard
        if (d.array(forKey: "fenetresDuTiroir") as? [Int]) != ids { d.set(ids, forKey: "fenetresDuTiroir") }
    }     // le numéro de la fenêtre de chaque tuile, pour savoir tout de suite si elle a été fermée
    func brancher() {
        // Une application figée ne doit pas figer Side : les questions posées aux autres applications (Accessibilité)
        // abandonnent au bout de 0,3 s au lieu des six secondes du système.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.3)
        NotificationCenter.default.addObserver(forName: Partie.changement, object: nil, queue: .main) { [weak self] _ in
            if !Partie.tiroir.active { self?.rendreToutesLesFenêtres() }     // tiroir coupé : ses fenêtres reviennent à l'écran
        }
        UserDefaults.standard.set(emprunts.map { $0.enTexte }, forKey: "panneauBasTuiles")   // la liste nettoyée (sans Finder)
        brancherChangerDAvis()
        // Pendant qu'un menu de Side est affiché, le tiroir n'active aucune application (le menu se refermerait).
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in PanneauBas.menuOuvert = true }
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in PanneauBas.menuOuvert = false }
        installerRaccourci()
        VoletPresse.commun.installerRaccourci()     // le volet du presse-papiers a aussi le sien
        GestePanneauBas.enHaut = enHaut
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivée(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        // Commandes venues d'une autre application (Mulot, pour les boutons de la souris) : « carte » ou « panneau ».
        // Side signale dans ses réglages qu'il les accepte : Mulot ne propose ces actions que dans ce cas.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(commandeExterieure(_:)),
                                                            name: .init("com.gauthieraube.side.commande"), object: nil)
        UserDefaults.standard.set(true, forKey: "commandesExterieures")
        UserDefaults.standard.set(false, forKey: "tiroirOuvert")      // au lancement, le tiroir est fermé (lu par Mulot)
        // Les photos des fenêtres pendant le glissement demandent l'autorisation « Enregistrement de l'écran ».
        // Sans elle, le panneau glisse avec de simples cartes grises à la place.
        let photos = CGPreflightScreenCaptureAccess()
        if !photos, !UserDefaults.standard.bool(forKey: "panneauBasPhotosDemandées") {
            UserDefaults.standard.set(true, forKey: "panneauBasPhotosDemandées")
            CGRequestScreenCaptureAccess()
        }
        écouterDéfilement()
        journalBas("panneau branché, accessibilité=%d, photos=%d, défilement=%d", AXIsProcessTrusted() ? 1 : 0, photos ? 1 : 0,
                   PanneauBas.filtre == nil ? 0 : 1)
    }

    var estOuvert: Bool { ouvert }
    func basculer() { ouvert ? fermer(rendreLaMain: true) : ouvrir() }

    /// Suite de la visite guidée : le tiroir s'ouvre avec son mot d'accueil (même s'il a déjà été vu).
    func présenter() {
        PanneauBas.motDAccueil = true
        UserDefaults.standard.set(false, forKey: "tiroirBienvenueVue")
        if ouvert { if let p = panneau { disposerLeFond(p.frame) }; return }
        // Un instant, le temps que le Finder finisse de se refermer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.ouvrir() }
    }

    @objc func commandeExterieure(_ note: Notification) {
        guard let commande = note.object as? String else { return }
        if !commande.hasPrefix("tiroir:suivre:") { journalBas("commande reçue : %@", commande) }   // pas 60 lignes par seconde
        switch commande {
        case "carte": AppDelegate.shared.basculer()      // la carte Finder
        case "panneau": basculer()                        // le panneau du bas
        case "presse": VoletPresse.commun.basculer()      // le volet du presse-papiers
        case "grille": Programme.appli.basculerGrille()   // la grille du plein écran
        case "encoche": Ile.commun.basculer()             // l'île de l'encoche
        case "encoche:finder": Descente.finder()          // le Finder qui descend de l'encoche
        case "encoche:suivante": Ile.commun.feuilleter(1) // pour les essais : la vue suivante de l'île ouverte
        case "encoche:hud": Ile.commun.montrerHud(.volume, niveau: 0.6)   // pour les essais : la jauge du volume
        case "recherche": Recherche.commun.basculer()     // la recherche sur le web
        // Pour les essais : « recherche:didgeridoo » ouvre la pilule sans prendre le clavier et lance la recherche.
        case _ where commande.hasPrefix("recherche:"): Recherche.commun.essai(String(commande.dropFirst(10)))
        // Pour les essais : « dock:/Applications/X.app » fait comme un clic sur cette icône du Dock de la grille.
        case _ where commande.hasPrefix("dock:") && UserDefaults.standard.bool(forKey: "essais"):
            Programme.appli.essaiDock(String(commande.dropFirst(5)))
        case "reglages-coins":                            // Square renvoie ici pour régler son coin actif
            AppDelegate.shared.fermerReglages()
            Volet.demande = .coins
            AppDelegate.shared.ouvrirReglages()
        case _ where commande.hasPrefix("volet:"):           // pour les essais : ouvrir les réglages sur ce volet
            if let v = Volet(rawValue: String(commande.dropFirst(6))) { Volet.demandeDirecte(v) }
        case "video-etat": lecteursWeb.first(where: { $0.estUnYouTube })?.noterEtat()
        // Pour les essais : joue le geste du mini carrousel (« mini:debut », « mini:0.5 » pour un trajet, « mini:fin »).
        case _ where commande.hasPrefix("tuile:"):          // pour les essais : afficher l'application de ce rang
            if let i = Int(commande.dropFirst(6)), emprunts.indices.contains(i) { montrerTuile(i) }
        // Les commandes d'essai qui agissent sur des fichiers ou sur la page YouTube ne sont écoutées que si on l'a demandé
        case "volet-plein": VoletVue.commun.basculerAgrandi()   // pour les essais : le bouton plein écran du volet ouvert
        case _ where commande.hasPrefix("coin:"):           // pour les essais : « coin:hautGauche » ouvre (ou ferme) le volet de ce coin
            if VoletVue.commun.estOuvert {
                VoletVue.commun.fermer()
            } else if let c = Coin(rawValue: String(commande.dropFirst(5))), let chemin = VoletVue.commun.chemin(c), let e = NSScreen.main {
                VoletVue.commun.ouvrir(c, chemin, sur: e)
            }
        case _ where commande.hasPrefix("bord:"):           // pour les essais : « bord:x:y » (coordonnées globales, en haut à gauche)
            let v = commande.split(separator: ":").dropFirst().compactMap { Double($0) }
            if v.count == 2 {
                let p = CGPoint(x: v[0], y: v[1])
                journalBas("bord %.0f,%.0f : surLeBord=%d côté=%d tiroirSous=%d cadre=%@ numéros=%@ relayable=%@", p.x, p.y,
                           PanneauBas.surLeBord(p) ? 1 : 0, PanneauBas.surUnCôté(p), PanneauBas.tiroirSous(p) ? 1 : 0,
                           NSStringFromRect(PanneauBas.cadreBrut), "\(PanneauBas.numerosDuTiroir.sorted())",
                           PanneauBas.fenêtreRelayable.map { NSStringFromRect($0) } ?? "aucune")
            }
        case _ where commande.hasPrefix("pilule:"):          // pour les essais : afficher une pastille
            Pilule.montrer(String(commande.dropFirst(7)), symbole: "arrow.up.and.down")
        // Mulot, bouton de pouce tenu : le tiroir s'ouvre s'il ne l'est pas, puis son sélecteur vertical suit la souris
        // (« tiroir:suivre:1.5 » = une application et demie plus loin) ; « tiroir:fin » pose l'application du centre.
        // Mulot, bouton de pouce tenu.
        //  - Tiroir fermé : il monte en suivant la souris, comme les doigts au trackpad, puis le sélecteur prend le relais
        //    dans le même mouvement. « tiroir:suivre:<v>:<a> » : v = 0 fermé, 1 ouvert, au-delà le sélecteur.
        //  - Tiroir ouvert : le sélecteur apparaît dès l'appui (« tiroir:debut »), sans attendre. a = le nombre
        //    d'applications parcourues depuis l'appui (négatif vers l'arrière).
        // « tiroir:fin » : l'application du centre prend la place.
        case "tiroir:debut":
            sourisMène = true
            ouvertAvantLaSouris = ouvert
            sélecteurParLaSouris = false
            positionSouris = 0
            if ouvert {
                if enPlace, !suiviDoigts { commencerNavigation(); sélecteurParLaSouris = navDepart != nil }
            } else {
                commencerSuivi(fermeture: false)
            }
        case "tiroir:fin":
            guard sourisMène else { return }
            sourisMène = false
            if ouvertAvantLaSouris {
                if navDepart != nil { lacherDoigts(ouvrir: true, elan: 0) }
            } else {
                // Lâché très près du départ (la souris est revenue en arrière) : le tiroir redescend.
                lacherDoigts(ouvrir: positionSouris > 0.12 || navDepart != nil, elan: 0)
            }
        case _ where commande.hasPrefix("tiroir:suivre:"):
            let n = commande.dropFirst(14).split(separator: ":").compactMap { Double($0) }.map { CGFloat($0) }
            guard sourisMène, ouvert, let v = n.first else { return }
            let a = n.count > 1 ? n[1] : 0
            positionSouris = v
            if ouvertAvantLaSouris {
                guard navDepart != nil else { return }
                suivreDoigts(1 + a * parApp)
            } else {
                // Les mêmes unités que le trackpad : au-delà de 1, « parApp » de progression par application.
                if v > 1 { sélecteurParLaSouris = true }
                suivreDoigts(v <= 1 ? max(0, v) : 1 + (v - 1) * parApp)
            }
        // Pour les essais : « vue:hautGauche » fait comme le coin actif de ce nom (le volet d'une vue d'Horizon).
        case _ where commande.hasPrefix("vue:"):
            // « vue:basDroite:/chemin/de/l'application.app » (ou « vue:basDroite:horizon-vue://crm ») essaie une application
            // ou une vue d'Horizon sans toucher aux réglages.
            let m = commande.dropFirst(4).split(separator: ":", maxSplits: 1).map(String.init)
            if let c = m.first.flatMap(Coin.init(rawValue:)), let ch = m.count > 1 ? m[1] : VoletVue.commun.chemin(c), let e = Ecrans.deTravail {
                VoletVue.commun.ouvrir(c, ch, sur: e)
            }
        case "mini:debut": commencerNavigation()
        case "mini:fin": lacherDoigts(ouvrir: true, elan: 0)
        case "video":                                     // la vidéo YouTube du tiroir : en plein écran, ou de retour
            lecteursWeb.first(where: { $0.estUnYouTube })?.basculerPleinEcran()
        case "corbeille":                                 // la carte Finder, ouverte sur la corbeille
            if !AppDelegate.shared.estOuvert { AppDelegate.shared.basculer() }
            Corbeille.montrer()
        default:
            if commande.hasPrefix("mini:"), let t = Double(commande.dropFirst(5)) { suivreDoigts(1 + CGFloat(t)); return }
            if commande.hasPrefix("js "), UserDefaults.standard.bool(forKey: "essais"), let y = lecteursWeb.first(where: { $0.estUnYouTube }) { y.essaiScript(String(commande.dropFirst(3))); return }
            // « youtube https://… » : ouvre ce lien dans la tuile YouTube (pour les essais, et pour d'autres apps).
            if commande.hasPrefix("youtube "), let u = URL(string: String(commande.dropFirst(8))) {
                montrerYouTube(u)      // le tiroir s'ouvre sur sa tuile YouTube (21/11/2026 ; avant, il fallait l'avoir ouvert)
            }
        }
    }

    /// (Ré)installe le raccourci clavier choisi dans les réglages (aucun si on l'a effacé).
    func installerRaccourci() {
        TouchesBas.retirer(idRaccourci)
        let c = ConfigTiroir.commun
        guard c.touche != -1 else { return }
        TouchesBas.ajouter(idRaccourci, touche: UInt32(c.touche), modifs: UInt32(c.mods)) { [weak self] in self?.basculer() }
    }
    /// Pendant qu'on tape un nouveau raccourci dans les réglages : l'ancien ne doit pas ouvrir le tiroir.
    func suspendreRaccourci() { TouchesBas.retirer(idRaccourci) }

    func surveillerCoin(_ p: NSPoint, _ e: NSScreen, taille: CGFloat) {
        let coin = ConfigTiroir.commun.coin
        guard coin != .aucun else { return }
        func dans(_ marge: CGFloat) -> Bool {
            let t = taille + marge, f = e.frame
            let gauche = p.x <= f.minX + t, droite = p.x >= f.maxX - t, haut = p.y >= f.maxY - t, bas = p.y <= f.minY + t
            switch coin {
            case .aucun: return false
            case .hautGauche: return haut && gauche
            case .hautDroite: return haut && droite
            case .basGauche: return bas && gauche
            case .basDroite: return bas && droite
            }
        }
        if !dans(40) { coinArmé = true; débutCoin = nil; return }
        guard dans(0) else { débutCoin = nil; return }
        guard coinArmé, NSEvent.pressedMouseButtons == 0, !suiviDoigts else { return }
        if débutCoin == nil { débutCoin = Date() }
        guard Date().timeIntervalSince(débutCoin!) >= 0.05 else { return }
        coinArmé = false
        débutCoin = nil
        journalBas("coin actif du tiroir")
        basculer()
    }

    /// Pour la fenêtre Réglages : les applications du tiroir, dans l'ordre.
    var tuiles: [(nom: String, chemin: String)] { emprunts.map { ($0.nom, $0.chemin) } }
    func retirerTuile(nom: String) {
        if let i = emprunts.firstIndex(where: { $0.nom == nom }) { retirer(i) }
    }

    func app(_ e: EmpruntBas) -> NSRunningApplication? {
        // Demandée par son identifiant : passer en revue toutes les applications ouvertes, à chaque appel, coûtait cher pendant un geste.
        NSRunningApplication.runningApplications(withBundleIdentifier: e.bundle).first
    }
    func estEmpruntée(_ a: NSRunningApplication?) -> Bool {
        guard let b = a?.bundleIdentifier else { return false }
        return emprunts.contains { $0.bundle == b }
    }

    // MARK: Géométrie
    /// La largeur du tiroir, en part de l'écran (1 = toute la largeur), réglée en tirant un de ses côtés.
    /// Sur un grand écran, la part se compte sur 1800 points au plus (16/11/2026) : 87 % d'un Studio Display (2880 points)
    /// donnait un tiroir de 2500 points, avec un grand vide entre le coin multimédia et l'application.
    var largeurChoisie: CGFloat {
        get { let v = UserDefaults.standard.double(forKey: "tiroirLargeur"); return v > 0 ? CGFloat(v) : 1 }
        set { UserDefaults.standard.set(Double(newValue), forKey: "tiroirLargeur") }
    }
    static let largeurRéférenceMaxi: CGFloat = 1800
    /// La largeur sur laquelle se compte la part choisie : celle de l'écran, sans dépasser 1800 points.
    static func largeurRéférence(_ largeurÉcran: CGFloat) -> CGFloat { min(largeurÉcran, largeurRéférenceMaxi) }
    /// La largeur minimum de chaque application du tiroir (celles qui refusent d'être plus étroites), apprise en les posant.
    var largeursMini: [String: CGFloat] {
        get { (UserDefaults.standard.dictionary(forKey: "tiroirLargeursMini") as? [String: Double])?.mapValues { CGFloat($0) } ?? [:] }
        set { UserDefaults.standard.set(newValue.mapValues { Double($0) }, forKey: "tiroirLargeursMini") }
    }
    /// La largeur du tiroir en dessous de laquelle une de ses applications ne tiendrait plus.
    var largeurTiroirMini: CGFloat {
        guard uneApp else { return 720 }
        let tête: CGFloat = médias.isEmpty ? 0 : LecteurYouTubeBas.largeurMini + marge     // le coin multimédia à sa largeur minimum
        return max(720, largeurAppMini + tête + largeurColonne + 3 * marge)
    }
    /// La taille maximum des applications qui refusent de grandir (la Calculette…), apprise en les posant : [largeur, hauteur].
    /// Une telle application est centrée dans sa place du tiroir, au lieu d'être collée dans un coin avec du vide à côté.
    var taillesMaxi: [String: [Double]] {
        get {
            // Les tailles retenues avant le 13/11/2026 bloquaient les deux dimensions à la fois : on repart de zéro, une fois.
            if !UserDefaults.standard.bool(forKey: "tiroirTaillesMaxiParDimension") {
                UserDefaults.standard.set(true, forKey: "tiroirTaillesMaxiParDimension")
                UserDefaults.standard.removeObject(forKey: "tiroirTaillesMaxi")
            }
            return (UserDefaults.standard.dictionary(forKey: "tiroirTaillesMaxi") as? [String: [Double]]) ?? [:]
        }
        set { UserDefaults.standard.set(newValue, forKey: "tiroirTaillesMaxi") }
    }
    /// La hauteur minimum de chaque application du tiroir (celles qui refusent d'être plus basses), apprise en les posant.
    var hauteursMini: [String: CGFloat] {
        get { (UserDefaults.standard.dictionary(forKey: "tiroirHauteursMini") as? [String: Double])?.mapValues { CGFloat($0) } ?? [:] }
        set { UserDefaults.standard.set(newValue.mapValues { Double($0) }, forKey: "tiroirHauteursMini") }
    }
    /// Le tiroir est plus étroit qu'une de ses applications ne l'accepte : il s'élargit et tout se replace.
    func respecterLesLargeursMini() {
        guard ouvert, let p = panneau, let ecran = écranDuTiroir else { return }
        let fin = cadre(ecran)
        guard abs(fin.width - p.frame.width) > 1 || abs(fin.height - p.frame.height) > 1 else { return }
        p.setFrame(fin, display: true)
        disposerLeFond(fin)
        poser(1)
        déplacerImages(animé: false)
        installer(déjàArrivé: true)
    }

    /// Hauteur du panneau, choisie en tirant son bord haut. 0 : jamais réglée (la moitié basse de l'écran).
    var hauteurChoisie: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "panneauBasHauteur")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "panneauBasHauteur") }
    }
    /// Le tiroir arrive toujours du bord opposé au Finder de Side : du bas en général, du haut quand le Finder vient du bas.
    var enHaut: Bool { ConfigTiroir.enHaut }
}
