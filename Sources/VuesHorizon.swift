// Les vues d'Horizon (20/11/2026).
// Horizon (l'app de Gauthier) montrait chacune de ses vues (CRM, Aujourd'hui, À planifier…) dans une petite application
// à part, rangée dans « /Applications/Horizon Vues » : une copie entière d'Horizon par vue. Ce dossier disparaît.
// Désormais, chaque vue est une fenêtre du seul Horizon, qui porte le titre de la vue (« Horizon CRM »…). La fenêtre
// principale d'Horizon s'appelle simplement « Horizon ».
//
// Side range une vue là où il rangeait le chemin d'une application : « horizon-vue://crm ». Ce fichier est le seul à savoir
// ce que cela veut dire : la liste des vues, leur nom, leur icône, ouvrir la fenêtre d'une vue, la retrouver, la fermer.
// Le tiroir, le volet d'un coin et le volet à plusieurs vues passent tous par lui.
import AppKit

enum VuesHorizon {
    struct Vue: Decodable, Hashable {
        let id: String
        let titre: String
    }

    static let bundle = "online.wakademy.horizon"
    static let appHorizon = "/Applications/Horizon.app"
    /// Le titre de la fenêtre principale d'Horizon (celle qui n'est pas une vue).
    static let titrePrincipal = "Horizon"
    static let préfixe = "horizon-vue://"
    /// L'ancien dossier des petites applications : les réglages qui y renvoient encore sont convertis (voir migrer).
    static let ancienDossier = "/Applications/Horizon Vues"

    /// Le dossier où Horizon écrit la liste de ses vues (vues.json) et leurs icônes (<id>.png).
    static var dossier: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/online.wakademy.horizon/Vues")
    }

    /// Les neuf vues d'Horizon, telles qu'il les écrit : pour reconnaître un ancien réglage quand vues.json manque.
    static let tableFixe: [Vue] = [
        Vue(id: "aujourdhui", titre: "Horizon Aujourd’hui"),
        Vue(id: "planifier", titre: "Horizon À planifier"),
        Vue(id: "projets", titre: "Horizon Projets"),
        Vue(id: "coffre", titre: "Horizon Coffre"),
        Vue(id: "reseaux", titre: "Horizon Réseaux"),
        Vue(id: "crm", titre: "Horizon CRM"),
        Vue(id: "projet1", titre: "Horizon Projet 1"),
        Vue(id: "projet2", titre: "Horizon Projet 2"),
        Vue(id: "projet3", titre: "Horizon Projet 3"),
    ]

    // MARK: La liste

    private static var gardée: (vues: [Vue], à: CFAbsoluteTime)?

    /// Les vues installées par Horizon sur ce Mac, dans l'ordre de vues.json. Vide sans Horizon (le fichier n'existe pas) :
    /// les lignes « vue d'Horizon » n'apparaissent alors nulle part. Relue au plus toutes les deux secondes : on la consulte
    /// souvent (à chaque recherche d'une fenêtre d'Horizon).
    static var liste: [Vue] {
        let maintenant = CFAbsoluteTimeGetCurrent()
        if let g = gardée, maintenant - g.à < 2 { return g.vues }
        let url = dossier.appendingPathComponent("vues.json")
        let vues = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Vue].self, from: $0) } ?? []
        gardée = (vues, maintenant)
        return vues
    }

    /// Les chemins de toutes les vues, dans l'ordre de la liste.
    static var chemins: [String] { liste.map { chemin($0.id) } }

    /// Tous les titres de fenêtre qui sont ceux d'une vue (ceux de la liste, et ceux de la table fixe).
    static var titres: Set<String> { Set((liste + tableFixe).map(\.titre)) }

    // MARK: Chemin, nom, icône

    static func chemin(_ id: String) -> String { préfixe + id }

    /// L'identifiant de la vue (« crm »), ou nil si ce chemin est celui d'une application ordinaire.
    static func id(_ chemin: String) -> String? {
        guard chemin.hasPrefix(préfixe) else { return nil }
        let id = String(chemin.dropFirst(préfixe.count))
        return id.isEmpty ? nil : id
    }

    static func estUneVue(_ chemin: String) -> Bool { id(chemin) != nil }

    /// Le chemin de la vue dont la fenêtre porte ce titre, ou nil (la fenêtre principale, ou une autre).
    static func chemin(deTitre titre: String) -> String? {
        (liste + tableFixe).first { $0.titre == titre }.map { chemin($0.id) }
    }

    /// La vue de ce chemin : d'abord dans la liste d'Horizon, puis dans la table fixe.
    static func vue(_ chemin: String) -> Vue? {
        guard let id = id(chemin) else { return nil }
        return liste.first { $0.id == id } ?? tableFixe.first { $0.id == id } ?? Vue(id: id, titre: "Horizon \(id)")
    }

    /// Le nom à afficher : le titre d'une vue, ou le nom d'une application sans « .app ».
    static func nom(_ chemin: String) -> String {
        if let v = vue(chemin) { return v.titre }
        return FileManager.default.displayName(atPath: chemin).replacingOccurrences(of: ".app", with: "")
    }

    private static var icônes: [String: NSImage] = [:]

    /// L'icône d'une vue (celle qu'Horizon a écrite à côté de la liste ; à défaut, celle d'Horizon), ou celle d'une application.
    static func icône(_ chemin: String) -> NSImage {
        guard let id = id(chemin) else { return NSWorkspace.shared.icon(forFile: chemin) }
        if let i = icônes[id] { return i }
        let png = dossier.appendingPathComponent("\(id).png")
        let i = NSImage(contentsOf: png) ?? NSWorkspace.shared.icon(forFile: appHorizon)
        icônes[id] = i
        return i
    }

    // MARK: Ouvrir, trouver, fermer

    static func app() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first { !$0.isTerminated }
    }

    /// Ouvre la fenêtre de la vue, ou la ramène devant si elle existe déjà. Lance Horizon s'il ne tourne pas.
    static func ouvrir(_ chemin: String, devant: Bool) {
        guard let id = id(chemin), let url = URL(string: préfixe + id) else { return }
        let c = NSWorkspace.OpenConfiguration()
        c.activates = devant
        c.addsToRecentItems = false
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: appHorizon), configuration: c, completionHandler: nil)
    }

    /// Les fenêtres d'Horizon, telles que l'Accessibilité les donne (vide s'il ne tourne pas).
    static func fenêtres() -> [AXUIElement] {
        guard let a = app() else { return [] }
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXWindowsAttribute as CFString, &v)
        return (v as? [AXUIElement]) ?? []
    }

    static func titre(_ f: AXUIElement) -> String {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(f, kAXTitleAttribute as CFString, &v)
        return (v as? String) ?? ""
    }

    static func numéro(_ f: AXUIElement) -> CGWindowID {
        var id: CGWindowID = 0
        _ = _AXUIElementGetWindow(f, &id)
        return id
    }

    /// Cette fenêtre d'Horizon est-elle celle d'une vue (et donc pas sa fenêtre principale) ?
    static func estFenêtreDeVue(_ f: AXUIElement) -> Bool { titres.contains(titre(f)) }

    /// Le numéro de la fenêtre de chaque vue, retenu dès qu'on l'a trouvée : on la reconnaît ensuite sans relire tous les titres.
    private static var numéros: [String: CGWindowID] = [:]

    /// La fenêtre de cette vue, si elle est ouverte : celle qui porte son titre.
    static func fenêtre(_ chemin: String, parmi données: [AXUIElement]? = nil) -> AXUIElement? {
        guard let v = vue(chemin) else { return nil }
        let toutes = données ?? fenêtres()
        if let n = numéros[v.id], let f = toutes.first(where: { numéro($0) == n }), titre(f) == v.titre { return f }
        guard let f = toutes.first(where: { titre($0) == v.titre }) else { numéros[v.id] = nil; return nil }
        let n = numéro(f)
        if n != 0 { numéros[v.id] = n }
        return f
    }

    /// La fenêtre principale d'Horizon (titre « Horizon »), jamais celle d'une vue. À défaut de ce titre (Horizon le change
    /// peut-être un instant au démarrage), une fenêtre ordinaire qui n'est pas une vue.
    static func fenêtrePrincipale(parmi données: [AXUIElement]? = nil) -> AXUIElement? {
        let toutes = données ?? fenêtres()
        if let f = toutes.first(where: { titre($0) == titrePrincipal }) { return f }
        let vues = titres
        return toutes.first { f in
            var s: CFTypeRef?
            AXUIElementCopyAttributeValue(f, kAXSubroleAttribute as CFString, &s)
            return (s as? String) == (kAXStandardWindowSubrole as String) && !vues.contains(titre(f))
        }
    }

    /// Ferme la fenêtre de la vue, par son bouton fermer : Horizon libère la vue et reste ouvert, avec ses autres fenêtres.
    /// (Jamais quitter ni masquer Horizon pour une vue : ce serait toucher à sa fenêtre principale et aux autres vues.)
    static func fermer(_ chemin: String) {
        guard let f = fenêtre(chemin) else { return }
        var b: CFTypeRef?
        AXUIElementCopyAttributeValue(f, kAXCloseButtonAttribute as CFString, &b)
        guard let b, CFGetTypeID(b) == AXUIElementGetTypeID() else { return }
        AXUIElementPerformAction(b as! AXUIElement, kAXPressAction as CFString)
    }

    /// La fenêtre ordinaire de ce processus la plus en avant à l'écran (son numéro, son cadre en coordonnées d'écran du haut),
    /// lue dans l'ordre des fenêtres de macOS : immédiat, sans rien demander à l'application (Horizon répond lentement à
    /// l'Accessibilité quand plusieurs de ses fenêtres sont ouvertes).
    static func fenêtreDevant(de pid: pid_t) -> (numéro: CGWindowID, cadre: CGRect)? {
        let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        for w in infos where (w[kCGWindowOwnerPID as String] as? pid_t) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let n = w[kCGWindowNumber as String] as? CGWindowID,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b), r.height > 40 else { continue }
            return (n, r)
        }
        return nil
    }

    // MARK: Les anciens réglages

    /// Un chemin enregistré avant le 20/11/2026 (« /Applications/Horizon Vues/Horizon CRM.app ») devient « horizon-vue://crm ».
    /// Le nom du fichier, sans « .app », est le titre de la vue. Tout autre chemin est rendu tel quel.
    static func migrer(_ chemin: String) -> String {
        guard chemin.hasPrefix(ancienDossier + "/"), chemin.hasSuffix(".app") else { return chemin }
        // Les noms de fichiers peuvent avoir leurs accents décomposés, et une apostrophe droite à la place de la typographique.
        func simple(_ s: String) -> String { s.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "'", with: "’") }
        let titre = simple(((chemin as NSString).lastPathComponent as NSString).deletingPathExtension)
        guard let v = (liste + tableFixe).first(where: { simple($0.titre) == titre }) else { return chemin }
        return Self.chemin(v.id)
    }
}
