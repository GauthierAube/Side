// Glissement à quatre doigts vers la gauche ou la droite : application suivante ou précédente, sur le même bureau.
// Il remplace le glissement de macOS entre bureaux quand il n'y a qu'un seul bureau. S'il y en a plusieurs, on laisse macOS faire.
// (Trois doigts ne conviennent pas ici : ils servent déjà à déplacer les fenêtres.)
import AppKit

/// Une touche du trackpad, telle que la décrit le module « MultitouchSupport » de macOS (non documenté par Apple).
private struct ContactGlisse {
    var frame: Int32; var horodatage: Double; var identifiant: Int32; var etat: Int32
    var doigt: Int32; var main: Int32
    var x: Float; var y: Float; var vx: Float; var vy: Float   // position de 0 à 1, et vitesse
    var taille: Float; var zero1: Int32; var angle: Float; var grandAxe: Float; var petitAxe: Float
    var ax: Float; var ay: Float; var avx: Float; var avy: Float
    var zero2: Int32; var zero3: Int32; var densite: Float
}

enum Glisse {
    static var actif: Bool {
        get { UserDefaults.standard.object(forKey: "glisseQuatreDoigts") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "glisseQuatreDoigts") }
    }
    /// Sens du glissement. Par défaut, comme entre les bureaux de macOS : les cartes suivent les doigts (doigts vers la gauche,
    /// on avance vers la droite). Inversé : doigts vers la droite pour avancer vers la droite.
    static var inverse: Bool {
        get { UserDefaults.standard.bool(forKey: "glisseInverse") }
        set { UserDefaults.standard.set(newValue, forKey: "glisseInverse") }
    }
    private static var demarre = false
    /// Le balayage à quatre doigts de macOS entre les plein écran d'Apple est-il coupé (Réglages Système > Trackpad > Plus de
    /// gestes) ? Alors Side prend toujours le geste, même quand une vidéo ou une app est dans un plein écran d'Apple :
    /// elle apparaît comme une carte du carrousel, et le geste ne change plus de mode selon les fenêtres ouvertes.
    static var systemeLibre: Bool {
        func valeur(_ domaine: String) -> Int? { UserDefaults(suiteName: domaine)?.object(forKey: "TrackpadFourFingerHorizSwipeGesture") as? Int }
        let v = [valeur("com.apple.AppleMultitouchTrackpad"), valeur("com.apple.driver.AppleBluetoothMultitouch.trackpad")].compactMap { $0 }
        return !v.isEmpty && v.allSatisfy { $0 == 0 }
    }
    private static var depart: [Int32: (Float, Float)] = [:]   // où chaque doigt s'est posé


    static func demarrer() {
        guard !demarre else { return }
        demarre = true
        let n = Trackpads.ecouter({ _, touches, nombre, _, _ in
            Glisse.recevoir(touches, Int(nombre))
            return 0
        })
        if n < 0 { journal("Square: trackpad illisible, pas de glissement") }
        // Au réveil du Mac, l'état du geste en cours est remis à zéro (les trackpads, eux, sont relancés par Trackpads).
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            depart = [:]; phase = 0; dernier = 0; dxSuivi = 0; montre = false; bornes = nil
        }
    }

    private static var phase = 0             // 0 : pas encore décidé, 1 : le carrousel suit les doigts, -1 : ce geste n'est pas pour nous
    private static var montre = false         // le carrousel est affiché pour ce geste
    private static var debutGeste: TimeInterval = 0
    /// Un geste parti vite mais qui dure plus que cela affiche quand même le carrousel. Réglable (« Taille du carrousel… »).
    static var attente: TimeInterval {
        get { UserDefaults.standard.object(forKey: "glisseAttente") as? Double ?? 0.12 }
        set { UserDefaults.standard.set(newValue, forKey: "glisseAttente") }
    }
    private static let vif: Float = 0.42              // au-delà de cette vitesse (largeurs de trackpad par seconde), c'est un effleurement
    private static let jugement: TimeInterval = 0.045 // moment où le geste est jugé, après son départ
    private static var juge = false
    private static var dxDepart: Float = 0
    private static var departVif = false
    private static var vitesseDepart: Float = 0
    private static var rapidite: Float = 0
    private static var dxPrec: Float = 0
    private static var instantPrec: TimeInterval = 0
    private static var instantPose: TimeInterval = 0
    private static var dernier: Float = 0     // dernier trajet envoyé, en nombre de fenêtres
    private static var dxSuivi: Float = 0     // position des doigts au dernier pas compté
    /// Jusqu'où la bande peut aller, en fenêtres, depuis celle de départ (nil : roue sans fin). Posé par le carrousel.
    static var bornes: ClosedRange<Float>?
    /// L'accélération, comme celle du pointeur : lents, les doigts avancent d'une fenêtre à la fois, avec précision ;
    /// rapides, chaque centimètre compte jusqu'à quatre fois plus, pour atteindre d'un geste une application tout au bout.
    private static func gain(_ vitesse: Float) -> Float {
        1 + 3 * min(max((vitesse - 0.2) / 0.8, 0), 1)
    }
    /// Sensibilité du geste (1 = normale) : plus elle est haute, moins les doigts ont à glisser pour passer d'une application
    /// à la suivante. Réglable dans Réglages > Plein écran > Carrousel.
    static var sensibilite: Double = UserDefaults.standard.object(forKey: "glisseSensibilite") as? Double ?? 1 {
        didSet { UserDefaults.standard.set(sensibilite, forKey: "glisseSensibilite") }
    }
    // Trajet des doigts, en largeur de trackpad, pour avancer d'une fenêtre (0,11 à la sensibilité normale).
    private static var parFenetre: Float { 0.11 / Float(max(sensibilite, 0.3)) }

    /// Appelé par macOS à chaque instant où des doigts touchent le trackpad (hors du fil principal).
    private static func recevoir(_ touches: UnsafeMutableRawPointer?, _ nombre: Int) {
        // Le pointeur est sur le volet de gauche à plusieurs vues : le geste horizontal change de vue, et Square n'en fait rien.
        if VoletVue.pointeurSurPile {
            var doigts: [(Int32, Float, Float)] = []
            if let touches, nombre > 0 {
                let c = touches.bindMemory(to: ContactGlisse.self, capacity: nombre)
                doigts = (0..<nombre).map { (c[$0].identifiant, c[$0].x, c[$0].y) }
            }
            if var e = GestePages.suivre(doigts, instant: ProcessInfo.processInfo.systemUptime) {
                if case .début(let s) = e, inverse { e = .début(-s) }
                DispatchQueue.main.async { VoletVue.commun.geste(e) }
            }
            if phase == 0, nombre >= 3 { phase = -1 }
        } else if nombre < 3 {
            _ = GestePages.suivre([], instant: 0)
        }
        let actif = Glisse.actif && Partie.pleinEcran.active     // aussi coupé avec la partie « plein écran »
        guard actif, let touches, nombre == 4 else {
            // Doigts levés : le carrousel choisit la fenêtre sous le cadre. (Un doigt levé un instant ne suffit pas.)
            if nombre < 3 || !actif {
                if phase == 1 {
                    let q = dernier
                    // Une ligne par geste dans le journal, pour régler la sensibilité sur de vrais gestes.
                    let duree = (ProcessInfo.processInfo.systemUptime - debutGeste) * 1000
                    journal("Square: geste à quatre doigts — %.2f largeur/s à 45 ms (%@), %.0f ms, trajet %.2f fenêtre, carrousel %@",
                            vitesseDepart, !juge ? "trop bref pour être jugé" : (departVif ? "vif" : "posé"), duree, abs(q),
                            montre ? "affiché" : "non affiché")
                    if montre {
                        DispatchQueue.main.async { Programme.appli.carrouselFin(CGFloat(q)) }
                    } else if abs(q) > 0.12 {
                        // Geste bref, doigts déjà relevés : pas de carrousel, on passe simplement à la fenêtre voisine.
                        DispatchQueue.main.async { Programme.appli.voisine(q > 0 ? 1 : -1) }
                    }
                }
                depart = [:]; phase = 0; dernier = 0; dxSuivi = 0; montre = false; bornes = nil
            }
            return
        }
        guard phase >= 0 else { return }
        let contacts = touches.bindMemory(to: ContactGlisse.self, capacity: nombre)
        var dx: Float = 0, dy: Float = 0, suivis: Float = 0
        var vus: [Int32: (Float, Float)] = [:]
        var parDoigt: [Float] = []
        for i in 0..<nombre {
            let c = contacts[i]
            vus[c.identifiant] = (c.x, c.y)
            if let d = depart[c.identifiant] { dx += c.x - d.0; dy += c.y - d.1; suivis += 1; parDoigt.append(c.x - d.0) }
        }
        let maintenant = ProcessInfo.processInfo.systemUptime
        if suivis < 4 { if phase == 0 { depart = vus; instantPose = maintenant }; return }   // les quatre doigts viennent de se poser
        // Tant que les doigts sont immobiles, le départ du mouvement reste « maintenant ».
        if phase == 0, max(abs(dx / suivis), abs(dy / suivis)) < 0.006 { instantPose = maintenant }
        dx /= suivis; dy /= suivis
        if phase == 0 {
            // Horizontal (nous) ou vertical (Side, sa carte, son tiroir) : la même règle que Side, au même instant.
            guard let aPlat = GestePages.horizontal(dx, dy) else { return }
            guard aPlat else { phase = -1; return }
            // Les quatre doigts glissent, chacun dans le même sens (20/11/2026). Un glisser à trois doigts (sélectionner du
            // texte, déplacer un fichier) avec le pouce posé sur le trackpad faisait aussi quatre contacts : la moyenne avançait
            // et le carrousel partait. Un doigt immobile (le pouce) ou à contresens : ce geste n'est pas pour nous.
            // Jugé trop tôt (à 2 mm de trajet), un doigt qui traîne faisait refuser tout le geste : on lui laisse le temps
            // de suivre (21/11/2026). Le pouce posé, lui, ne suit jamais : refusé un peu plus loin, sans rien afficher.
            guard GestePages.tousGlissent(parDoigt, moyenne: dx) else {
                if abs(dx) > GestePages.patience {
                    phase = -1
                    journal("Square: geste à quatre doigts refusé — un doigt ne glisse pas (trajets %@)",
                            parDoigt.map { String(format: "%.3f", $0) }.joined(separator: " "))
                }
                return
            }
            phase = 1
            debutGeste = maintenant
            // Vitesse de départ : le trajet déjà fait, sur le temps écoulé depuis que les doigts ont commencé à bouger.
            rapidite = abs(dx) / Float(max(maintenant - instantPose, 0.008))
            dxPrec = dx; instantPrec = maintenant
            dxDepart = dx
            dernier = (inverse ? dx : -dx) / parFenetre; dxSuivi = dx
            juge = false; departVif = false; vitesseDepart = 0
        }
        // Comme entre les bureaux : la bande suit les doigts. Doigts vers la gauche, on avance vers les fenêtres de droite.
        // Vitesse des doigts, en largeurs de trackpad par seconde (lissée).
        let dt = Float(maintenant - instantPrec)
        if dt > 0.003 { rapidite = rapidite * 0.5 + abs(dx - dxPrec) / dt * 0.5; dxPrec = dx; instantPrec = maintenant }
        // Chaque pas des doigts compte d'autant plus qu'ils vont vite.
        let pas = dx - dxSuivi
        dxSuivi = dx
        dernier += (inverse ? pas : -pas) / parFenetre * gain(rapidite)
        if let b = bornes { dernier = min(max(dernier, b.lowerBound - 0.3), b.upperBound + 0.3) }   // la bande ne file pas au-delà de ses bouts
        let q = dernier
        if !montre {
            // Un geste posé affiche le carrousel tout de suite. Seul un effleurement rapide le retient : si les doigts se
            // relèvent aussitôt, on change de fenêtre sans rien afficher ; s'ils ralentissent ou restent, il apparaît.
            if !juge {
                // Le geste est jugé 45 millisecondes après son départ, sur le chemin parcouru entre-temps. C'est ce qui
                // sépare le mieux les deux gestes (mesuré sur de vrais gestes le 12/11) : un effleurement file à près d'une
                // largeur de trackpad par seconde, un geste posé avance sept fois moins vite.
                guard maintenant - debutGeste >= jugement else { return }
                juge = true
                vitesseDepart = abs(dx - dxDepart) / Float(maintenant - debutGeste)
                departVif = vitesseDepart > vif
            }
            guard !departVif || maintenant - debutGeste > attente else { return }
            montre = true
            DispatchQueue.main.async { Programme.appli.carrouselDebut() }
        }
        DispatchQueue.main.async { Programme.appli.carrouselSuivre(CGFloat(q)) }
    }
}
