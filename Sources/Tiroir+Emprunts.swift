// Les fenêtres empruntées aux autres applications : les trouver, les placer, les rendre.
// Partie de PanneauBas (PanneauBas.swift), rangée à part le 15/11/2026 sans changement.

import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

extension PanneauBas {
    // MARK: Fenêtres empruntées
    func titre(_ el: AXUIElement) -> String {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &v)
        return (v as? String) ?? ""
    }

    func enfants(_ el: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v)
        return (v as? [AXUIElement]) ?? []
    }

    /// La fenêtre à emprunter, si elle existe déjà : pour une note, celle qui porte son nom.
    func fenetre(_ e: EmpruntBas) -> AXUIElement? {
        // La réponse est gardée un court instant (17/11/2026). Demander ses fenêtres à une application se fait sur le fil
        // principal, et un seul geste dans le tiroir le demandait trois ou quatre fois de suite à chacune : le geste saccadait.
        // Pire, une application occupée (qui démarre, par exemple) fait attendre 0,3 s à chaque demande ; redemandée vingt
        // fois par seconde, elle figeait Side pendant plusieurs secondes. On ne lui repose donc la question qu'une fois par seconde.
        let maintenant = CFAbsoluteTimeGetCurrent()
        if let g = fenêtresGardées[e.nom], maintenant - g.à < (g.sansRéponse ? 1.0 : 0.12) {
            sansRéponse = g.sansRéponse
            return g.fenêtre
        }
        let f = chercherFenetre(e)
        let durée = CFAbsoluteTimeGetCurrent() - maintenant
        if durée > 0.05 { journalBas("%@ a mis %d ms à répondre", e.nom, Int(durée * 1000)) }
        fenêtresGardées[e.nom] = (f, sansRéponse, CFAbsoluteTimeGetCurrent())
        return f
    }

    /// La question posée à l'application, sans mémoire (voir fenetre).
    func chercherFenetre(_ e: EmpruntBas) -> AXUIElement? {
        sansRéponse = false
        guard let a = app(e), !a.isHidden else { return nil }
        let el = AXUIElementCreateApplication(a.processIdentifier)
        var v: CFTypeRef?
        // L'application ne répond pas (figée, occupée) : ce n'est pas « fenêtre fermée ». veiller() ne compte pas d'absence.
        if AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &v) == .cannotComplete { sansRéponse = true }
        let toutes = (v as? [AXUIElement]) ?? []
        guard let note = e.note else {
            // La fenêtre de l'application dans le tiroir garde sa place, même quand l'application en ouvre une autre
            // devant (ses réglages, une boîte de dialogue) : on la reconnaît à son numéro. Les fenêtres secondaires
            // s'ouvrent normalement, par-dessus, sans être rangées dans le tiroir.
            if let n = numéros[e.nom], let f = toutes.first(where: { w in var id: CGWindowID = 0; return _AXUIElementGetWindow(w, &id) == .success && id == n }) {
                return f
            }
            let f = toutes.first(where: { estFenêtrePrincipale($0) }) ?? toutes.first
            if let f { noterNuméro(e, f) }
            return f
        }
        // Une note déjà trouvée est reconnue à son numéro de fenêtre : son titre (sa première ligne) change dès qu'on l'écrit,
        // et la chercher par son titre la faisait passer pour fermée (elle quittait le tiroir et restait sur le bureau).
        if let n = numéros[e.nom], let f = toutes.first(where: { w in var id: CGWindowID = 0; return _AXUIElementGetWindow(w, &id) == .success && id == n }) {
            return f
        }
        let actuel = titresDeNotes[note] ?? note
        let f = toutes.first { titre($0) == actuel } ?? toutes.first { titre($0) == note }
        if let f { noterNuméro(e, f) }
        return f
    }

    /// Une vraie fenêtre de travail de l'application (pas ses réglages, ni une boîte de dialogue, ni une palette) :
    /// une fenêtre ordinaire qu'on peut agrandir.
    func estFenêtrePrincipale(_ f: AXUIElement) -> Bool {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(f, kAXSubroleAttribute as CFString, &v)
        guard (v as? String) == (kAXStandardWindowSubrole as String) else { return false }
        var b: CFTypeRef?
        AXUIElementCopyAttributeValue(f, kAXFullScreenButtonAttribute as CFString, &b)
        guard let b, CFGetTypeID(b) == AXUIElementGetTypeID() else { return false }
        var actif: CFTypeRef?
        AXUIElementCopyAttributeValue(b as! AXUIElement, kAXEnabledAttribute as CFString, &actif)
        return (actif as? Bool) ?? true
    }

    func noterNuméro(_ e: EmpruntBas, _ f: AXUIElement) {
        var id: CGWindowID = 0
        if _AXUIElementGetWindow(f, &id) == .success, id != 0, numéros[e.nom] != id { numéros[e.nom] = id }
    }

    /// L'application a bien une fenêtre, mais pas sur le bureau affiché (l'Accessibilité ne voit que le bureau courant).
    func surUnAutreBureau(_ e: EmpruntBas) -> Bool {
        guard let a = app(e), !a.isHidden, fenetre(e) == nil else { return false }
        // Une note a sa propre fenêtre, qu'on ouvre à la demande : la grande fenêtre de Notes, où qu'elle soit, ne compte pas.
        if e.note != nil { return false }
        // Le bureau affiché, et celui de chaque fenêtre de l'application : elle est « ailleurs » si elle a une vraie fenêtre
        // et qu'aucune n'est sur le bureau affiché. (Une fenêtre simplement garée hors de l'écran est bien sur ce bureau.)
        let ecrans = (CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]]) ?? []
        let courants = Set(ecrans.compactMap { (($0["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.intValue })
        guard !courants.isEmpty else { return false }
        let infos = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
        var ailleurs = false
        for w in infos {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == a.processIdentifier, (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat], (b["Width"] ?? 0) > 200, (b["Height"] ?? 0) > 200,
                  let numero = w[kCGWindowNumber as String] as? Int else { continue }
            let bureaux = (CGSCopySpacesForWindowsBas(CGSMainConnectionID(), 7, [numero] as CFArray) as? [Int]) ?? []
            if bureaux.isEmpty { continue }                              // fenêtre fantôme : ni ici ni ailleurs
            if !courants.isDisjoint(with: bureaux) { return false }      // elle en a une ici : on saura la trouver ou la rouvrir
            ailleurs = true
        }
        return ailleurs
    }

    /// Fait apparaître la fenêtre quand elle n'existe pas encore (une seule demande par installation).
    func demander(_ e: EmpruntBas) {
        guard !demandées.contains(e.nom), !notesIntrouvables.contains(e.nom), !CaptureEcran.enCours else { return }
        demandées.insert(e.nom)
        journalBas("ouverture demandée pour %@", e.nom)
        guard let note = e.note else {
            // « Ouvrir » plutôt qu'« activer » : si l'application tourne sans fenêtre, macOS lui en redonne une.
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: e.chemin), configuration: config, completionHandler: nil)
            return
        }
        // Notes : on affiche la note, puis on demande « Ouvrir la note dans une nouvelle fenêtre » dans le menu Fenêtre.
        // La grande fenêtre de Notes ne sert que d'intermédiaire : elle est tenue hors de l'écran pendant toute l'opération.
        écarterLaGrandeFenêtreDeNotes(pendant: 4.5)
        let maSerie = serie
        // Notes pas encore lancée : on la lance masquée, le temps de garer sa grande fenêtre, pour qu'elle ne passe pas à l'écran.
        let lancée = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Notes" }
        if !lancée {
            let config = NSWorkspace.OpenConfiguration()
            config.hides = true
            config.activates = false
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: e.chemin), configuration: config, completionHandler: nil)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + (lancée ? 0 : 1.2)) { [weak self] in
            var erreur: NSDictionary?
            // La note qui porte ce nom ; à défaut, celle dont le nom le contient (sa première ligne a pu être retouchée).
            let cherche = note.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            // D'abord par son identifiant (il ne change jamais), puis par son nom.
            let parId = e.noteId.map { "try\n set n to note id \"\($0.replacingOccurrences(of: "\"", with: ""))\"\n end try" } ?? ""
            let script = """
            tell application "Notes"
                set n to missing value
                \(parId)
                if n is missing value then
                    try
                        set n to first note whose name is "\(cherche)"
                    end try
                end if
                if n is missing value then set n to first note whose name contains "\(cherche)"
                show n
                return {name of n, id of n}
            end tell
            """
            let reponse = NSAppleScript(source: script)?.executeAndReturnError(&erreur)
            let titre = reponse?.atIndex(1)?.stringValue, ident = reponse?.atIndex(2)?.stringValue
            if let erreur { journalBas("Notes a répondu %@", "\(erreur[NSAppleScript.errorMessage] ?? erreur)") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                guard let titre else {
                    // Note introuvable (supprimée, ou renommée du tout au tout) : on ne clique surtout pas dans le menu de Notes
                    // (il ouvrirait une autre note), on ne la réclame plus, et on le dit.
                    self.notesIntrouvables.insert(e.nom)
                    self.messageBanniere.stringValue = String(localized: "La note « \(note) » est introuvable dans Notes : renommée ou supprimée. Retire sa tuile et choisis-la de nouveau avec le +.")
                    self.boutonBanniere?.isHidden = true
                    self.banniere.isHidden = !self.ouvert
                    self.fermerLeResteDeNotes()
                    return
                }
                self.titresDeNotes[note] = titre
                // Une tuile rangée avant que Side ne retienne les identifiants : on le retient maintenant.
                if let ident, let i = self.emprunts.firstIndex(where: { $0.nom == e.nom }), self.emprunts[i].noteId == nil {
                    self.emprunts[i].noteId = ident
                }
                guard self.ouvert, self.serie == maSerie, let a = self.app(e) else { return }
                // Le menu de Notes est dans la langue de Notes (celle du Mac), pas dans celle de Side : on cherche les deux.
                let ok = self.presserMenu(a, ["Ouvrir la note dans une nouvelle fenêtre", "Open Note in New Window"])
                journalBas("menu de Notes %@", ok ? "pressé" : "introuvable")
                // La note a maintenant sa fenêtre à elle : la grande fenêtre de Notes, qui a servi à l'ouvrir, se referme.
                for attente in [0.7, 1.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + attente) { [weak self] in self?.fermerLeResteDeNotes() }
                }
            }
        }
    }

    /// Cette fenêtre de Notes est-elle celle d'une note du tiroir ? D'abord par son numéro (le titre d'une note change dès
    /// qu'on écrit sa première ligne), puis par son titre. Sinon, c'est la grande fenêtre de Notes, que le tiroir écarte ou rend.
    func estUneNoteDuTiroir(_ f: AXUIElement, _ notes: Set<String>) -> Bool {
        var id: CGWindowID = 0
        if _AXUIElementGetWindow(f, &id) == .success, id != 0,
           emprunts.contains(where: { $0.note != nil && numéros[$0.nom] == id }) { return true }
        let t = titre(f)
        return notes.contains(t) || titresDeNotes.values.contains(t)
    }

    func écarterLaGrandeFenêtreDeNotes(pendant durée: TimeInterval) {
        écartNotes?.invalidate()
        let fin = Date().addingTimeInterval(durée)
        let pousser: () -> Void = { [weak self] in
            guard let self, let ecran = NSScreen.screens.first,
                  let a = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Notes" }) else { return }
            let notes = Set(self.emprunts.compactMap { $0.note })
            var v: CFTypeRef?
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXWindowsAttribute as CFString, &v)
            for f in (v as? [AXUIElement]) ?? [] where !self.estUneNoteDuTiroir(f, notes) {
                guard let c = AXBas.cadre(f), c.minX < Ecrans.bordGarage - 2 else { continue }
                AXBas.placer(f, Ecrans.garage(taille: c.size))
            }
        }
        pousser()      // tout de suite : si Notes est déjà ouverte, sa fenêtre part avant même d'être appelée
        écartNotes = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] t in
            if Date() > fin { t.invalidate(); self?.écartNotes = nil; return }
            pousser()
        }
    }

    /// Quand le tiroir montre une note seule : la grande fenêtre de Notes reste garée hors de l'écran, au lieu d'être refermée.
    /// Ainsi, la prochaine fois qu'on a besoin d'elle pour ouvrir une note, elle n'a pas à réapparaître : rien ne clignote.
    /// Elle revient à l'écran dès qu'on appelle Notes normalement (voir appActivée).
    func fermerLeResteDeNotes() {
        guard ouvert, emprunts.contains(where: { $0.note != nil }),
              !emprunts.contains(where: { $0.bundle == "com.apple.Notes" && $0.note == nil }) else { return }
        écarterLaGrandeFenêtreDeNotes(pendant: 0.2)
    }

    /// Notes appelée normalement (Dock, raccourci) alors que sa grande fenêtre est garée hors de l'écran : on la lui rend.
    func rendreLaGrandeFenêtreDeNotes(_ a: NSRunningApplication) {
        guard let ecran = NSScreen.screens.first, let visible = Ecrans.deTravail?.visibleFrame else { return }
        let notes = Set(emprunts.compactMap { $0.note })
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXWindowsAttribute as CFString, &v)
        for f in (v as? [AXUIElement]) ?? [] where !estUneNoteDuTiroir(f, notes) {
            guard let c = AXBas.cadre(f), c.minX >= Ecrans.bordGarage - 2 else { continue }
            let milieu = CGPoint(x: visible.midX, y: ecran.frame.height - visible.midY)
            AXBas.placer(f, CGRect(x: milieu.x - c.width / 2, y: milieu.y - c.height / 2, width: c.width, height: c.height))
            journalBas("grande fenêtre de Notes rendue")
        }
    }

    func presserMenu(_ a: NSRunningApplication, _ intitulés: [String]) -> Bool {
        let el = AXUIElementCreateApplication(a.processIdentifier)
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXMenuBarAttribute as CFString, &v)
        guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return false }
        for rubrique in enfants(v as! AXUIElement) {
            for menu in enfants(rubrique) {
                for ligne in enfants(menu) where intitulés.contains(titre(ligne)) {
                    return AXUIElementPerformAction(ligne, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }

    /// Pendant le glissement : chaque fenêtre visible déjà ouverte est amenée devant le panneau, l'une après l'autre,
    /// alors qu'elle est encore hors de l'écran. Une fois le panneau arrivé, on les installe d'un coup à la place de leurs photos.
    func préparer(_ visibles: [(EmpruntBas, CGRect)], serie maSerie: Int) {
        guard ouvert, serie == maSerie else { return }
        // Une app à la fois : plus de course pour passer devant le tiroir. On attend qu'il soit arrivé, puis on pose
        // la fenêtre une fois, dans le trou (voir Tiroir+Trou).
        if uneApp {
            guard glissé else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in self?.préparer(visibles, serie: maSerie) }
                return
            }
            activations = 0
            activéeÀ = .distantPast
            installéeÀ = nil
            installerUneApp(visibles, serie: maSerie)
            return
        }
        let prêtes = visibles.allSatisfy { fenetre($0.0).map { estDevant($0) } ?? true }
        if glissé && (prêtes || Date().timeIntervalSince(glisséÀ) > 0.4) {
            for (e, zone) in visibles { if let f = fenetre(e) { placer(e, f, zone) } }
            // Les photos restent un instant sous les vraies fenêtres, le temps qu'elles se posent.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.serie == maSerie else { return }
                for (e, _) in visibles where self.fenetre(e) != nil { self.images[e.nom]?.isHidden = true }
            }
            surveiller(visibles, essais: 80, serie: maSerie)
            return
        }
        if !prêtes { remonter(visibles.map { $0.0 }, attente: 0.05) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.préparer(visibles, serie: maSerie)
        }
    }

    /// La fenêtre est-elle devant le panneau ?
    func estDevant(_ f: AXUIElement) -> Bool {
        guard let p = panneau else { return false }
        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(f, &wid) == .success else { return false }
        let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let ordre = infos.compactMap { $0[kCGWindowNumber as String] as? Int }
        guard let rangPanneau = ordre.firstIndex(of: p.windowNumber), let rang = ordre.firstIndex(of: Int(wid)) else { return false }
        return rang < rangPanneau
    }

    /// Pendant quatre secondes : ouvre les fenêtres manquantes, les installe à leur place et les ramène devant.
    /// Une fenêtre installée n'est plus touchée ensuite : vous pouvez la redimensionner.
    func surveiller(_ visibles: [(EmpruntBas, CGRect)], essais: Int, serie maSerie: Int) {
        guard ouvert, serie == maSerie, essais > 0 else { return }
        for (e, zone) in visibles {
            if let f = fenetre(e) {
                placer(e, f, zone)
                if posées.contains(e.nom) { images[e.nom]?.isHidden = true }
            } else if !posées.contains(e.nom) {
                demander(e)
            }
        }
        remonter(visibles.map { $0.0 })
        rendreLeClavier(visibles.map { $0.0 })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.surveiller(visibles, essais: essais - 1, serie: maSerie)
        }
    }

    /// Toutes les tuiles sont devant. Pour y arriver, il a fallu activer leurs applications : la dernière garde le clavier
    /// (le champ de recherche de Mots de passe, par exemple). Side le reprend, et repasse aussitôt sous les tuiles.
    func rendreLeClavier(_ liste: [EmpruntBas]) {
        guard !uneApp, !PanneauBas.menuOuvert, mainRendue != serie, Date().timeIntervalSince(dernierLever) > 0.3 else { return }
        // Une app à la fois : le clavier va directement à l'application affichée, dès l'ouverture et à chaque changement,
        // sans avoir à cliquer dedans.
        if uneApp, emprunts.indices.contains(rangCourant) {
            let e = emprunts[rangCourant]
            guard liste.contains(where: { $0.nom == e.nom }), let f = fenetre(e) else { return }
            mainRendue = serie
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != e.bundle { app(e)?.activate(options: []) }
            AXBas.lever(f)
            AXUIElementSetAttributeValue(f, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            journalBas("clavier donné à %@", e.nom)
            return
        }
        let devant = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let devant, liste.contains(where: { $0.bundle == devant }) else { return }
        // Toutes les tuiles visibles ont leur fenêtre, devant le tiroir (une note encore en train de s'ouvrir : on attend).
        guard liste.allSatisfy({ e in fenetre(e).map { estDevant($0) } ?? false }) else { return }
        mainRendue = serie
        NSApp.activate(ignoringOtherApps: true)
        panneau?.makeKey()
        // L'activation de Side fait passer le tiroir devant les tuiles, un peu plus tard : on le repasse dessous, à plusieurs reprises.
        for attente in [0.0, 0.1, 0.25, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + attente) { [weak self] in self?.repasserSousLesTuiles() }
        }
        journalBas("clavier repris par Side (%@ était devant)", devant)
    }

    /// Une fenêtre empruntée restée derrière le panneau est ramenée devant, une seule à la fois :
    /// macOS ne fait passer devant qu'une application par demande.
    func remonter(_ liste: [EmpruntBas], attente: TimeInterval = 0.2) {
        // Un menu de Side est ouvert (clic droit sur la barre des lecteurs…) : activer une application le refermerait.
        guard !uneApp, !PanneauBas.menuOuvert else { return }
        // Side a repris le clavier : les tuiles sont déjà devant, on ne réactive plus leurs applications.
        guard mainRendue != serie else { return }
        guard Date().timeIntervalSince(dernierLever) > attente, levées < 12 else { return }
        for e in liste {
            guard let f = fenetre(e), !estDevant(f) else { continue }
            AXBas.lever(f)
            app(e)?.activate(options: [])
            dernierLever = Date()
            levées += 1
            return
        }

    }

    /// Redemande à l'application sa place, puis regarde 0,7 s plus tard : si elle dépasse toujours, c'est qu'elle refuse
    /// d'être plus petite. Alors seulement, sa taille minimum est retenue et le tiroir grandit pour elle.
    func verifierMinimum(_ e: EmpruntBas, _ f: AXUIElement, _ zone: CGRect) {
        guard !enVérification.contains(e.nom) else { return }
        enVérification.insert(e.nom)
        AXBas.placer(f, zone)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            self.enVérification.remove(e.nom)
            guard self.ouvert, !self.enDirect, let p = self.panneau,
                  let maintenant = self.entières(p.frame).first(where: { $0.0.nom == e.nom })?.1, maintenant == zone,
                  let c = AXBas.cadre(f) else { return }
            var change = false
            if c.height > zone.height + 3, (self.hauteursMini[e.bundle] ?? 0) < c.height {
                var m = self.hauteursMini; m[e.bundle] = c.height.rounded(.up); self.hauteursMini = m
                journalBas("%@ : hauteur minimum %.0f (vérifiée), le tiroir grandit", e.nom, c.height)
                change = true
            }
            if self.uneApp, c.width > zone.width + 3, (self.largeursMini[e.bundle] ?? 0) < c.width {
                var m = self.largeursMini; m[e.bundle] = c.width.rounded(.up); self.largeursMini = m
                journalBas("%@ : largeur minimum %.0f (vérifiée), le tiroir s'élargit", e.nom, c.width)
                change = true
            }
            if change { self.respecterLesLargeursMini() }
        }
    }

    func placer(_ e: EmpruntBas, _ f: AXUIElement, _ zone: CGRect) {
        vivantes.insert(e.nom)
        guard !posées.contains(e.nom), let avant = AXBas.cadre(f) else { return }
        let ecran = NSScreen.screens.first?.frame ?? .zero
        // Sa place d'avant l'emprunt, pour la lui rendre si on rouvre l'application normalement.
        if !vues.contains(e.nom) {
            vues.insert(e.nom)          // seulement la toute première fois, avant qu'on y touche
            if avant.minX < Ecrans.bordGarage - 2 { origines[e.nom] = avant }
        }
        let aSaPlace = abs(avant.minX - zone.minX) < 2 && abs(avant.minY - zone.minY) < 2
        let aSaTaille = abs(avant.width - zone.width) < 2 && abs(avant.height - zone.height) < 2
        // Bien placée six vérifications de suite (ou l'application refuse la taille demandée) : on la laisse tranquille.
        if aSaPlace && (aSaTaille || replacements[e.nom, default: 0] >= 2) {
            if uneApp, !aSaTaille, e.note == nil {
                let maxi = taillesMaxi[e.bundle]
                // Plus grande que la taille maximum retenue : l'application a changé d'avis, on l'oublie.
                if let m = maxi, m.count == 2, avant.width > CGFloat(m[0]) + 3 || avant.height > CGFloat(m[1]) + 3 {
                    var t = taillesMaxi; t[e.bundle] = nil; taillesMaxi = t
                    journalBas("%@ : taille maximum oubliée", e.nom)
                    stables[e.nom] = 0; replacements[e.nom] = 0
                    return
                }
                // Plus petite que sa place, et elle refuse de grandir : on retient sa taille, elle sera centrée.
                let pluspetite = avant.width < zone.width - 3 || avant.height < zone.height - 3
                if pluspetite, avant.width <= zone.width + 3, avant.height <= zone.height + 3 {
                    // Seule la dimension refusée est retenue : Réglages Système a une largeur fixe, mais sa hauteur est libre.
                    let libre = 100_000.0
                    let ancien = taillesMaxi[e.bundle] ?? [libre, libre]
                    var t = taillesMaxi
                    t[e.bundle] = [avant.width < zone.width - 3 ? Double(avant.width.rounded()) : (ancien.count == 2 ? ancien[0] : libre),
                                   avant.height < zone.height - 3 ? Double(avant.height.rounded()) : (ancien.count == 2 ? ancien[1] : libre)]
                    taillesMaxi = t
                    journalBas("%@ : taille fixe %.0f × %.0f, centrée dans le tiroir", e.nom, avant.width, avant.height)
                    stables[e.nom] = 0; replacements[e.nom] = 0
                    return
                }
            }
            if !aSaTaille, abs(avant.height - zone.height) > 3 { refusHauteur.insert(e.nom) }
            // Plus haute (ou plus large) que le tiroir : l'application refuse peut-être d'être plus petite. On ne le croit
            // qu'après l'avoir vérifié : redemandée à sa place, elle a encore dépassé une demi-seconde plus tard. (Retenir
            // la taille d'une application qui n'avait simplement pas encore suivi empêchait ensuite de réduire le tiroir.)
            let tropHaute = avant.height > zone.height + 3 && (hauteursMini[e.bundle] ?? 0) < avant.height
            let tropLarge = uneApp && avant.width > zone.width + 3 && (largeursMini[e.bundle] ?? 0) < avant.width
            if tropHaute || tropLarge { verifierMinimum(e, f, zone) }
            stables[e.nom, default: 0] += 1
            if stables[e.nom, default: 0] >= 6 { posées.insert(e.nom) }
            return
        }
        stables[e.nom] = 0
        guard replacements[e.nom, default: 0] < 6 else { posées.insert(e.nom); return }
        replacements[e.nom, default: 0] += 1
        AXBas.placer(f, zone)
    }

    /// Remet à l'écran la fenêtre d'une tuile rangée (application rouverte normalement, ou tuile retirée du panneau).
    func rendreLaFenêtre(_ e: EmpruntBas) {
        guard let ecran = NSScreen.screens.first, let visible = Ecrans.deTravail?.visibleFrame,
              let f = fenetre(e), let c = AXBas.cadre(f) else { return }
        let milieu = CGPoint(x: visible.midX, y: ecran.frame.height - visible.midY)
        let r = origines[e.nom] ?? CGRect(x: milieu.x - c.width / 2, y: milieu.y - c.height / 2, width: c.width, height: c.height)
        AXBas.placer(f, r)
        numéros[e.nom] = nil                       // elle n'est plus dans le tiroir : Square peut la ranger
        journalBas("fenêtre rendue à %@", e.nom)
    }

    /// Range hors de l'écran les fenêtres empruntées (sauf celles citées), sans masquer leur application
    /// (sinon elle se verrouille et se recrée).
    func ranger(sauf gardées: Set<String>) {
        guard let ecran = NSScreen.screens.first else { return }
        for e in emprunts where !gardées.contains(e.nom) && e.nom != libérée {
            guard let f = fenetre(e), let c = AXBas.cadre(f), c.minX < Ecrans.bordGarage - 2 else { continue }
            AXBas.placer(f, Ecrans.garage(taille: c.size))
        }
    }

    /// Une capture d'écran est-elle en train d'être choisie (⌘⇧4, ⌘⇧5) ? Son voile couvre tout l'écran.
    /// Tant qu'il est là, les clics servent à tracer la zone : le panneau ne se referme pas.
    func captureEnCours() -> Bool { CaptureEcran.enCours }

    @objc func appActivée(_ note: Notification) {
        guard let a = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if !ouvert {
            // (Même sans note dans le tiroir : la grande fenêtre a pu rester garée après le retrait de la dernière note.)
            if a.bundleIdentifier == "com.apple.Notes" { rendreLaGrandeFenêtreDeNotes(a) }
            // Tiroir coupé dans les réglages : il ne s'ouvrira pas, donc la fenêtre appelée revient simplement à l'écran.
            if !Partie.tiroir.active {
                emprunts.filter { $0.bundle == a.bundleIdentifier && $0.note == nil }.forEach(rendreLaFenêtre)
                return
            }
            // Une application empruntée rouverte normalement (Dock, raccourci) pendant que le panneau est fermé :
            // on lui rend sa fenêtre. Pas pour la note, qui ne sert que dans le panneau.
            // Une application du panneau appelée normalement (Dock, raccourci, Square) pendant que le panneau est fermé :
            // sa fenêtre ne sort pas du panneau. C'est le panneau qui s'ouvre, sur sa tuile.
            guard let ecran = NSScreen.screens.first, Date().timeIntervalSince(ferméÀ) > 1.0 else { return }
            for (i, e) in emprunts.enumerated() where e.bundle == a.bundleIdentifier && e.note == nil {
                guard let f = fenetre(e), let c = AXBas.cadre(f), c.minX >= Ecrans.bordGarage - 2 else { continue }
                journalBas("%@ appelée : le panneau s'ouvre sur sa tuile", e.nom)
                tuileÀMontrer = i
                ouvrir()
                break
            }
            return
        }
        // Juste après que Side a fait passer une application du tiroir devant, macOS rend parfois la main à l'application
        // d'avant (Safari, Claude…). Ce n'est pas vous : le tiroir restait ouvert une fraction de seconde puis se refermait
        // (20/11/2026). On l'ignore, et l'application du tiroir repasse devant.
        if uneApp, a.processIdentifier == pidAvant, Date().timeIntervalSince(activéeÀ) < 1.5 {
            journalBas("%@ revient devant juste après l'ouverture : ignoré", a.localizedName ?? "?")
            if let p = panneau, let (e, _) = entières(p.frame).first, let b = app(e), let f = fenetre(e), activations < 8 { activer(b, f) }
            return
        }
        guard Date().timeIntervalSince(ouvertÀ) > 0.4, !estEmpruntée(a),
              a.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        guard a.bundleIdentifier != "com.apple.screencaptureui", !captureEnCours() else { return }
        // Une application du tiroir qui quitte quand on ferme sa fenêtre (Réglages Système) : macOS passe aussitôt la main
        // à l'application d'avant. Ce n'est pas vous qui changez d'application : le tiroir reste ouvert, et la tuile s'en va.
        // On laisse un court instant à l'application pour finir de quitter avant de trancher.
        let nom = a.localizedName ?? "?"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.ouvert else { return }
            if let i = self.emprunts.firstIndex(where: { e in
                self.vivantes.contains(e.nom) && (self.app(e).map { $0.isTerminated } ?? true)
            }) {
                journalBas("%@ a quitté (fenêtre fermée) : sa tuile est retirée, le tiroir reste ouvert", self.emprunts[i].nom)
                self.retirer(i)
                return
            }
            journalBas("%@ passe devant", nom)
            self.fermer(rendreLaMain: false)
        }
    }
}
