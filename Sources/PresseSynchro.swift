// Le presse-papiers et les liens enregistrés, partagés entre plusieurs Mac (16/11/2026).
// Tout passe par iCloud Drive, dans le dossier Side (le même que « Mes applications ») :
// - « Presse-papiers.json » : l'historique. Les deux Mac copient sans arrêt, donc on fusionne : chaque élément garde son
//   identifiant, le changement le plus récent l'emporte, et un élément effacé laisse une trace (7 jours) pour que l'autre
//   Mac l'efface aussi au lieu de le renvoyer.
// - « Presse-papiers images » : les images de l'historique, en PNG.
// - « Liens enregistrés.json » : la liste entière ; la plus récente remplace l'autre (l'ordre et les groupes comptent).
// Jamais partagés : les mots de passe (déjà jamais écrits sur le disque) et les fichiers copiés (leur chemin ne vaut que
// sur ce Mac).
import AppKit
import Foundation

final class SynchroPresse: ObservableObject {
    static let commun = SynchroPresse()
    private let d = UserDefaults.standard
    private let fm = FileManager.default

    /// Réglage : partager entre mes Mac. Activé au départ.
    @Published var actif: Bool {
        didSet {
            d.set(actif, forKey: "pressePartage")
            if actif { aEnvoyer = true; liensAEnvoyer = true; synchroniser() } else { etat = "" }
        }
    }
    @Published private(set) var etat = ""

    /// Les éléments effacés ici ou sur l'autre Mac, avec la date de l'effacement.
    private var supprimes: [String: Date]
    private var aEnvoyer = true          // un changement fait ici n'est pas encore dans iCloud
    private var liensAEnvoyer = false
    private var dernierLu: Date?         // date du fichier de l'historique la dernière fois qu'on l'a lu ou écrit
    private var dernierLuLiens: Date?
    private var attente: DispatchWorkItem?
    private var veille: Timer?

    private init() {
        actif = d.object(forKey: "pressePartage") as? Bool ?? true
        supprimes = (d.dictionary(forKey: "presseSupprimes") as? [String: Date]) ?? [:]
    }

    // MARK: Les fichiers

    private var dossier: URL? { MesApps.dossierICloud }
    private var fichier: URL? { dossier?.appendingPathComponent("Presse-papiers.json") }
    private var fichierLiens: URL? { dossier?.appendingPathComponent("Liens enregistrés.json") }
    private var dossierImages: URL? { dossier?.appendingPathComponent("Presse-papiers images", isDirectory: true) }

    private struct Element: Codable {
        var id: UUID; var date: Date; var modifie: Date; var texte: String?; var image: String?; var epingle: Bool
    }
    private struct Historique: Codable { var elements: [Element]; var supprimes: [String: Date] }
    private struct Liens: Codable { var liens: [LienGarde]; var date: Date }

    /// Un fichier présent dans iCloud mais pas encore descendu sur ce Mac (macOS laisse un « .nom.icloud » à sa place).
    private func enAttente(_ url: URL) -> Bool {
        let fantome = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        guard fm.fileExists(atPath: fantome.path) else { return false }
        try? fm.startDownloadingUbiquitousItem(at: url)
        return true
    }
    private func dateDe(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    // MARK: Quand synchroniser

    /// Au lancement : une première fois, puis un coup d'œil toutes les 20 secondes (l'autre Mac a pu copier).
    func demarrer() {
        guard veille == nil else { return }
        if !d.bool(forKey: "presseLiensPartages") { liensAEnvoyer = true }
        synchroniser()
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.synchroniser() }
        RunLoop.main.add(t, forMode: .common)
        veille = t
    }

    /// Quelque chose a changé ici : envoyé deux secondes plus tard (plusieurs copies d'affilée partent ensemble).
    func plusTard() {
        aEnvoyer = true
        attente?.cancel()
        let a = DispatchWorkItem { [weak self] in self?.synchroniser() }
        attente = a
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: a)
    }

    func liensModifies() {
        d.set(Date(), forKey: "presseLiensModifies")
        liensAEnvoyer = true
        plusTard()
    }

    /// Des éléments effacés ici : l'autre Mac doit les effacer aussi.
    func oublier(_ ids: [UUID]) {
        let maintenant = Date()
        for id in ids { supprimes[id.uuidString] = maintenant }
        d.set(supprimes, forKey: "presseSupprimes")
    }

    func synchroniser() {
        guard actif else { return }
        guard let dossier else { etat = String(localized: "iCloud Drive n'est pas activé sur ce Mac."); return }
        try? fm.createDirectory(at: dossier, withIntermediateDirectories: true)
        if Config.shared.historique { synchroniserHistorique() }
        synchroniserLiens()
    }

    // MARK: L'historique

    private func synchroniserHistorique() {
        guard let fichier, let dossierImages else { return }
        if enAttente(fichier) { return }   // on attend la version de l'autre Mac avant d'écrire quoi que ce soit
        let date = dateDe(fichier)
        let nouveau = date != nil && date != dernierLu
        guard nouveau || aEnvoyer else { return }

        let presse = PressePapiers.shared
        var distant = Historique(elements: [], supprimes: [:])
        if fm.fileExists(atPath: fichier.path) {
            guard let data = try? Data(contentsOf: fichier), let h = try? JSONDecoder().decode(Historique.self, from: data) else {
                etat = String(localized: "Le fichier partagé est illisible pour l'instant.")
                return
            }
            distant = h
        }

        // Les effacements : ceux des deux Mac, gardés sept jours.
        let limite = Date().addingTimeInterval(-PressePapiers.duree)
        for (id, quand) in distant.supprimes where quand > (supprimes[id] ?? .distantPast) { supprimes[id] = quand }
        supprimes = supprimes.filter { $0.value > limite }

        var elements = presse.elements
        var change = false
        for e in distant.elements {
            if let i = elements.firstIndex(where: { $0.id == e.id }) {
                // Le même élément des deux côtés : le changement le plus récent l'emporte (épinglé, recopié).
                guard e.modifie > elements[i].modifie else { continue }
                elements[i].date = e.date; elements[i].modifie = e.modifie; elements[i].epingle = e.epingle
                change = true
            } else {
                if let quand = supprimes[e.id.uuidString], quand >= e.modifie { continue }
                if !e.epingle && e.date < limite { continue }
                var c = Copie(id: e.id, date: e.date, texte: e.texte, epingle: e.epingle, modifie: e.modifie)
                if let nom = e.image {
                    // L'image vient de l'autre Mac : recopiée dans le dossier de ce Mac. Pas encore arrivée : au prochain passage.
                    let local = PressePapiers.dossierImages.appendingPathComponent(nom)
                    if !fm.fileExists(atPath: local.path) {
                        let source = dossierImages.appendingPathComponent(nom)
                        if enAttente(source) || !fm.fileExists(atPath: source.path) { continue }
                        try? fm.createDirectory(at: PressePapiers.dossierImages, withIntermediateDirectories: true)
                        try? fm.copyItem(at: source, to: local)
                        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: local.path)
                    }
                    guard let image = NSImage(contentsOf: local) else { continue }
                    c.image = image
                    c.fichierImage = nom
                }
                elements.append(c)
                change = true
            }
        }
        // Ce qui a été effacé sur l'autre Mac disparaît ici.
        let avant = elements.count
        elements.removeAll { c in supprimes[c.id.uuidString].map { $0 >= c.modifie } ?? false }
        if elements.count != avant { change = true }
        // Le même texte copié sur les deux Mac : un seul élément, le plus récent.
        var vus: [String: Int] = [:]
        var doublons: [Int] = []
        for (i, c) in elements.enumerated() {
            guard let t = c.texte, c.fichiers.isEmpty, c.image == nil else { continue }
            if let j = vus[t] {
                let (garde, jete) = elements[j].date >= c.date ? (j, i) : (i, j)
                if elements[jete].epingle { elements[garde].epingle = true }
                doublons.append(jete)
                supprimes[elements[jete].id.uuidString] = Date()
                vus[t] = garde
            } else { vus[t] = i }
        }
        if !doublons.isEmpty {
            for i in doublons.sorted(by: >) { elements.remove(at: i) }
            change = true
        }
        d.set(supprimes, forKey: "presseSupprimes")

        if change {
            elements.sort { $0.date > $1.date }
            while elements.count > PressePapiers.maximum, let i = elements.lastIndex(where: { !$0.epingle }) { elements.remove(at: i) }
            while elements.filter({ $0.image != nil && !$0.epingle }).count > PressePapiers.maximumImages,
                  let i = elements.lastIndex(where: { $0.image != nil && !$0.epingle }) { elements.remove(at: i) }
            presse.elements = elements
            presse.purger()
            presse.sauver(partager: false)
        }

        // Ce qu'on envoie : les textes et les images, jamais les mots de passe ni les fichiers.
        let partages = presse.elements.filter { !$0.secret && $0.fichiers.isEmpty && ($0.texte != nil || $0.fichierImage != nil) }
        var imagesManquantes = false
        try? fm.createDirectory(at: dossierImages, withIntermediateDirectories: true)
        for c in partages {
            guard let nom = c.fichierImage else { continue }
            let cible = dossierImages.appendingPathComponent(nom)
            if fm.fileExists(atPath: cible.path) || fm.fileExists(atPath: dossierImages.appendingPathComponent("." + nom + ".icloud").path) { continue }
            let local = PressePapiers.dossierImages.appendingPathComponent(nom)
            if fm.fileExists(atPath: local.path) { try? fm.copyItem(at: local, to: cible) } else { imagesManquantes = true }   // PNG pas encore écrit
        }
        let sortant = Historique(
            elements: partages.map { Element(id: $0.id, date: $0.date, modifie: $0.modifie, texte: $0.texte, image: $0.fichierImage, epingle: $0.epingle) },
            supprimes: supprimes)
        let identique = sortant.elements.map(\.id) == distant.elements.map(\.id)
            && sortant.elements.map(\.modifie) == distant.elements.map(\.modifie) && sortant.supprimes == distant.supprimes
        if !identique {
            do {
                try JSONEncoder().encode(sortant).write(to: fichier, options: .atomic)
            } catch {
                etat = String(localized: "Impossible d'écrire dans iCloud Drive.")
                return
            }
        }
        dernierLu = dateDe(fichier)
        aEnvoyer = imagesManquantes

        // Les images que plus personne n'utilise : effacées d'iCloud.
        let gardees = Set(partages.compactMap(\.fichierImage))
        for f in (try? fm.contentsOfDirectory(atPath: dossierImages.path)) ?? [] where f.hasSuffix(".png") && !gardees.contains(f) {
            try? fm.removeItem(at: dossierImages.appendingPathComponent(f))
        }
        etat = String(localized: "Partagé dans iCloud Drive, dossier Side.")
    }

    // MARK: Les liens enregistrés

    private func synchroniserLiens() {
        guard let fichier = fichierLiens else { return }
        if enAttente(fichier) { return }
        let date = dateDe(fichier)
        guard date != dernierLuLiens || liensAEnvoyer else { return }
        let liens = LiensGardes.commun
        var distant: Liens?
        if fm.fileExists(atPath: fichier.path) {
            guard let data = try? Data(contentsOf: fichier), let l = try? JSONDecoder().decode(Liens.self, from: data) else { return }
            distant = l
        }
        let modifieIci = d.object(forKey: "presseLiensModifies") as? Date ?? .distantPast
        var aEcrire = liens.liens

        if !d.bool(forKey: "presseLiensPartages") {
            // Première fois sur ce Mac : on réunit les deux listes (sans doublon), pour ne rien perdre d'un côté ni de l'autre.
            if let distant {
                aEcrire = distant.liens + liens.liens.filter { l in !distant.liens.contains { $0.texte == l.texte } }
                remplacer(par: aEcrire)
            }
            d.set(true, forKey: "presseLiensPartages")
        } else if let distant, distant.date > modifieIci {
            // L'autre Mac a changé la liste plus récemment : on la reprend telle quelle.
            if distant.liens != liens.liens { remplacer(par: distant.liens) }
            d.set(distant.date, forKey: "presseLiensModifies")
            dernierLuLiens = date
            liensAEnvoyer = false
            return
        } else if let distant, distant.liens == liens.liens {
            dernierLuLiens = date
            liensAEnvoyer = false
            return
        }
        // Jamais une liste vide par-dessus celle de l'autre Mac, sauf si on l'a vidée ici exprès.
        if aEcrire.isEmpty && distant == nil { liensAEnvoyer = false; return }
        let quand = Date()
        guard (try? JSONEncoder().encode(Liens(liens: aEcrire, date: quand)).write(to: fichier, options: .atomic)) != nil else {
            etat = String(localized: "Impossible d'écrire dans iCloud Drive.")
            return
        }
        d.set(quand, forKey: "presseLiensModifies")
        dernierLuLiens = dateDe(fichier)
        liensAEnvoyer = false
    }

    private func remplacer(par nouveaux: [LienGarde]) {
        let liens = LiensGardes.commun
        liens.enLecture = true
        liens.liens = nouveaux
        liens.enLecture = false
    }
}
