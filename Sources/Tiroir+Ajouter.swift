// Ajouter, retirer, et faire passer une application du plein écran au tiroir.
// Partie de PanneauBas (PanneauBas.swift), rangée à part le 15/11/2026 sans changement.

import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

extension PanneauBas {
    // MARK: Ajouter et retirer des applications
    /// « Une seule note… » : la liste des notes de l'application Notes s'affiche, on clique sur celle qu'on veut.
    /// Sa tuile remplace alors celle de toute l'application Notes.
    func demanderUneNote() {
        guard let fenetre = plus.window else { return }
        let ancre = fenetre.convertToScreen(plus.convert(plus.bounds, to: nil))
        DispatchQueue.global().async { [weak self] in
            // Les titres des notes, dans l'ordre de Notes (les plus récentes d'abord). Rien d'autre n'est lu.
            var erreur: NSDictionary?
            // Avec leur identifiant, qui ne change pas quand on réécrit la première ligne d'une note.
            let reponse = NSAppleScript(source: "tell application \"Notes\" to get {name, id} of every note")?.executeAndReturnError(&erreur)
            var titres: [String] = [], ids: [String: String] = [:]
            if let reponse, reponse.numberOfItems == 2, let noms = reponse.atIndex(1), let idents = reponse.atIndex(2), noms.numberOfItems > 0 {
                for i in 1...noms.numberOfItems {
                    if let t = noms.atIndex(i)?.stringValue, !t.isEmpty, !titres.contains(t) {
                        titres.append(t)
                        ids[t] = idents.atIndex(i)?.stringValue
                    }
                    if titres.count >= 40 { break }
                }
            }
            if let erreur { journalBas("Notes a répondu %@", "\(erreur[NSAppleScript.errorMessage] ?? erreur)") }
            DispatchQueue.main.async {
                guard let self, self.ouvert else { return }
                let icone = NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app")
                let lignes = titres.map { t in
                    SelecteurTuilesBas.Ligne(icone: icone, nom: t, signe: "plus.circle.fill", couleur: .systemGreen) { [weak self] in self?.ajouterNote(t, id: ids[t]) }
                }
                let vide = [SelecteurTuilesBas.Ligne(icone: nil, nom: String(localized: "Aucune note trouvée dans Notes"), signe: nil, couleur: .clear, action: nil)]
                self.selecteur.montrer(pres: ancre, [(String(localized: "Choisir une note"), lignes.isEmpty ? vide : lignes)])
            }
        }
    }

    // MARK: Les vues d'Horizon (17/11/2026)
    /// Horizon (l'app de Gauthier) installe à côté de lui de petites applications qui ne montrent qu'une de ses vues
    /// (CRM, Aujourd'hui, À planifier…), rangées dans ce dossier. Ce sont des applications comme les autres : le tiroir
    /// n'a rien de particulier à faire pour elles, il les propose seulement d'un geste. Sans ce dossier, la ligne n'apparaît pas.
    static let dossierVuesHorizon = "/Applications/Horizon Vues"
    var vuesHorizon: [URL] {
        let dossier = URL(fileURLWithPath: Self.dossierVuesHorizon)
        let contenu = (try? FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: nil)) ?? []
        let vues = contenu.filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        // Horizon Mail aussi : étroite, elle devient un aperçu des boîtes, sans barre latérale (le bouton vert lui rend tout).
        let mail = URL(fileURLWithPath: "/Applications/Horizon Mail.app")
        guard !vues.isEmpty, FileManager.default.fileExists(atPath: mail.path) else { return vues }
        return [mail] + vues
    }

    /// « Une vue d'Horizon… » : la liste des vues qui ne sont pas encore dans le tiroir, on clique sur celle qu'on veut.
    func demanderUneVueHorizon() {
        guard let fenetre = plus.window else { return }
        let ancre = fenetre.convertToScreen(plus.convert(plus.bounds, to: nil))
        let libres = vuesHorizon.filter { url in !emprunts.contains { $0.chemin == url.path } }
        let lignes = libres.map { url in
            SelecteurTuilesBas.Ligne(icone: NSWorkspace.shared.icon(forFile: url.path),
                                     nom: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                                     signe: "plus.circle.fill", couleur: .systemGreen) { [weak self] in self?.ajouter(url) }
        }
        let vide = [SelecteurTuilesBas.Ligne(icone: nil, nom: String(localized: "Toutes les vues sont déjà dans le tiroir"), signe: nil, couleur: .clear, action: nil)]
        selecteur.montrer(pres: ancre, [(String(localized: "Choisir une vue d'Horizon"), lignes.isEmpty ? vide : lignes)])
    }

    /// Range une note précise dans le tiroir (par son titre). Aussi appelé depuis les réglages.
    func ajouterNote(_ titre: String, id: String? = nil) {
        guard !titre.isEmpty, !emprunts.contains(where: { $0.note == titre }) else { return }
        // La tuile de toute l'application Notes ferait double emploi (et prendrait la fenêtre de la note pour la sienne).
        for e in emprunts where e.bundle == "com.apple.Notes" && e.note == nil { rendreLaFenêtre(e) }
        emprunts.removeAll { $0.bundle == "com.apple.Notes" && $0.note == nil }
        emprunts.append(EmpruntBas(nom: String(localized: "Note \(titre)"), bundle: "com.apple.Notes", chemin: "/System/Applications/Notes.app", note: titre, noteId: id))
        journalBas("tuile ajoutée : une note")
        recharger(versLaFin: true)
    }

    /// Un clic dans le tiroir (case « + », sélecteur, page YouTube…) fait passer sa fenêtre devant celles des tuiles,
    /// qui disparaissent alors derrière lui. On le remet aussitôt juste sous la tuile la plus en arrière.
    func repasserSousLesTuiles() {
        guard ouvert, enPlace, !défile, !sansFenêtres, let p = panneau else { return }
        let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let ordre = infos.compactMap { $0[kCGWindowNumber as String] as? Int }
        guard let rangPanneau = ordre.firstIndex(of: p.windowNumber) else { return }
        var plusLoin: (rang: Int, numero: Int)?
        for (e, _) in entières(p.frame) where posées.contains(e.nom) {
            var wid: CGWindowID = 0
            guard let f = fenetre(e), _AXUIElementGetWindow(f, &wid) == .success, let rang = ordre.firstIndex(of: Int(wid)) else { continue }
            if rang > (plusLoin?.rang ?? -1) { plusLoin = (rang, Int(wid)) }
        }
        guard let cible = plusLoin, cible.rang > rangPanneau else { return }      // une tuile est passée derrière le tiroir
        p.order(.below, relativeTo: cible.numero)
    }

    /// La roue dentée : le tiroir se referme et la fenêtre Réglages s'ouvre.
    @objc func ouvrirLesRéglages() {
        fermer(rendreLaMain: false)
        AppDelegate.shared.ouvrirReglages()
    }

    @objc func ouvrirMenu(_ bouton: NSView) {
        if selecteur.ouvert { selecteur.fermer(); return }
        func icone(_ chemin: String) -> NSImage { NSWorkspace.shared.icon(forFile: chemin) }
        let presentes = emprunts.enumerated().map { i, e in
            var l = SelecteurTuilesBas.Ligne(icone: icone(e.chemin), nom: e.nom, signe: "minus.circle.fill", couleur: .systemRed) { [weak self] in
                // Par le nom, pas par le rang : la liste a pu changer depuis l'ouverture de ce menu.
                guard let self, let rang = self.emprunts.firstIndex(where: { $0.nom == e.nom }) else { return }
                self.retirer(rang)
            }
            if e.note == nil {
                l.signe2 = "arrow.up.left.and.arrow.down.right.circle.fill"
                l.aide2 = String(localized: "Passer en plein écran")
                l.action2 = { [weak self] in self?.passerEnPleinEcran(nom: e.nom) }
            }
            return l
        }
        let moi = Bundle.main.bundleIdentifier
        let ouvertes = NSWorkspace.shared.runningApplications.filter { a in
            a.activationPolicy == .regular && a.bundleIdentifier != moi && a.bundleURL != nil && !estEmpruntée(a)
                && !PanneauBas.refusées.contains(a.bundleIdentifier ?? "")
        }.sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
        let aAjouter = ouvertes.map { a in
            SelecteurTuilesBas.Ligne(icone: icone(a.bundleURL!.path), nom: a.localizedName ?? "?", signe: "plus.circle.fill", couleur: .systemGreen) { [weak self] in
                self?.ajouter(a.bundleURL!)
            }
        }
        let symbole: (String) -> NSImage? = { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) }
        let autre: [SelecteurTuilesBas.Ligne] = [
            SelecteurTuilesBas.Ligne(icone: symbole("square.grid.2x2"), nom: String(localized: "Choisir une application…"), signe: "chevron.right", couleur: .tertiaryLabelColor) { [weak self] in
                self?.choisirApplication()
            },
            // Une seule note, dans sa propre petite fenêtre, plutôt que toute l'application Notes.
            SelecteurTuilesBas.Ligne(icone: icone("/System/Applications/Notes.app"), nom: String(localized: "Une seule note…"), signe: "chevron.right", couleur: .tertiaryLabelColor) { [weak self] in
                self?.demanderUneNote()
            },
        ] + (vuesHorizon.first.map { premiere in
            // Une seule vue d'Horizon (le CRM, Aujourd'hui…), quand Horizon a installé ses vues sur ce Mac.
            [SelecteurTuilesBas.Ligne(icone: icone(premiere.path), nom: String(localized: "Une vue d'Horizon…"), signe: "chevron.right", couleur: .tertiaryLabelColor) { [weak self] in
                self?.demanderUneVueHorizon()
            }]
        } ?? [])
        guard let fenetre = bouton.window else { return }
        let ancre = fenetre.convertToScreen(bouton.convert(bouton.bounds, to: nil))
        journalBas("liste + ouverte")
        // Les deux façons d'ajouter d'abord, bien en vue ; puis les tuiles du tiroir, puis les applications ouvertes.
        selecteur.montrer(pres: ancre, [(String(localized: "Ajouter au tiroir"), autre), (String(localized: "Dans le tiroir"), presentes),
                                        (String(localized: "Applications ouvertes"), aAjouter)])
    }

    @objc func choisirApplication() {
        let p = NSOpenPanel()
        p.title = String(localized: "Ajouter au panneau")
        p.prompt = String(localized: "Ajouter")
        p.allowedContentTypes = [.applicationBundle]
        p.allowsMultipleSelection = true
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        guard Devant.panneau(p) == .OK else { return }
        p.urls.forEach { ajouter($0) }
    }

    func ajouter(_ url: URL) {
        guard let bundle = Bundle(url: url)?.bundleIdentifier, bundle != Bundle.main.bundleIdentifier,
              !PanneauBas.refusées.contains(bundle),
              !emprunts.contains(where: { $0.bundle == bundle && $0.note == nil }) else {
            journalBas("ajout refusé pour %@ (déjà dans le panneau, ou application illisible)", url.lastPathComponent)
            return
        }
        let nom = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        emprunts.append(EmpruntBas(nom: nom, bundle: bundle, chemin: url.path))
        journalBas("tuile ajoutée : %@", nom)
        // La nouvelle tuile arrive au bout de la bande : on y défile pour la montrer.
        recharger(versLaFin: true)
    }

    // MARK: Changer d'avis : du plein écran au tiroir, et retour
    /// L'application (de la grille, ou celle de devant) rejoint le tiroir, qui s'ouvre sur elle.
    func envoyerAuTiroir(pid: pid_t) {
        guard let a = NSRunningApplication(processIdentifier: pid), let url = a.bundleURL, let bundle = a.bundleIdentifier,
              bundle != Bundle.main.bundleIdentifier, !PanneauBas.refusées.contains(bundle) else { NSSound.beep(); return }
        if !emprunts.contains(where: { $0.bundle == bundle && $0.note == nil }) { ajouter(url) }
        journalBas("%@ envoyée au tiroir", a.localizedName ?? bundle)
        guard let i = emprunts.firstIndex(where: { $0.bundle == bundle && $0.note == nil }) else { return }
        let e = emprunts[i]
        tuileÀMontrer = i
        // La transition : la fenêtre rétrécit jusqu'à sa place dans le tiroir, pendant que le tiroir arrive.
        if !ouvert, uneApp, let f = fenetre(e), let c = AXBas.cadre(f), let ecran = Ecrans.deTravail {
            let image = photo(e, taille: c.size, fraîche: true)
            let départ = TransitionFenetre.versÉcran(c)
            // Le tiroir s'ouvre directement sur elle.
            if let p = panneau ?? Optional(construire()) { panneau = p; défilement = arrêts(cadre(ecran)).débuts.indices.contains(i) ? CGFloat(i) * (bande(cadre(ecran)).height + marge) : 0 }
            // Une fenêtre à taille fixe (la Calculette) garde sa taille : la photo rétrécit jusqu'à sa vraie place, pas plus.
            let zone = zoneÉcran(pour: cadre(ecran))
            let arrivée = Self.redimensionnable(f) ? zone
                : CGRect(x: zone.minX, y: zone.maxY - min(c.height, zone.height), width: min(c.width, zone.width), height: min(c.height, zone.height))
            AXBas.placer(f, CGRect(x: Ecrans.bordGarage - 1, y: c.minY, width: c.width, height: c.height))   // la photo la remplace
            TransitionFenetre.animer(image, de: départ, vers: arrivée, durée: 0.42, arrondiDépart: 10, arrondiArrivée: 20) {
                TransitionFenetre.effacer(après: 0.35)        // le temps que la vraie fenêtre se pose dans le tiroir
            }
            ouvrir()
            return
        }
        if !ouvert { ouvrir() } else { montrerTuile(i) }
    }

    /// L'application de cette tuile quitte le tiroir et remplit l'écran, comme une application de travail.
    /// Sa photo grandit de sa place dans le tiroir jusqu'à tout l'écran, pendant que le tiroir s'en va.
    func passerEnPleinEcran(nom: String) {
        guard let i = emprunts.firstIndex(where: { $0.nom == nom }) else { return }
        let e = emprunts[i]
        journalBas("%@ passe en plein écran", nom)
        let f = fenetre(e), c = f.flatMap { AXBas.cadre($0) }
        let image = c.map { photo(e, taille: $0.size, fraîche: true) }
        let visible = écranDuTiroir?.visibleFrame ?? .zero
        let finale = { [weak self] in
            guard let self, let a = self.app(e) else { return }
            if a.isHidden { a.unhide() }
            var v: CFTypeRef?
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXWindowsAttribute as CFString, &v)
            if let f = (v as? [AXUIElement])?.first { Agrandir.basculer(f, seulementAgrandir: true); AXBas.lever(f) }
            a.activate(options: [])
        }
        // La tuile quitte le tiroir sans que sa fenêtre soit rendue au milieu de l'écran : elle ira droit à sa place finale.
        numéros[e.nom] = nil
        emprunts.remove(at: i)
        if ouvert { fermer(rendreLaMain: false) } else { recharger(versLaFin: false) }
        if let c, let f, ouvert == false, image != nil {
            // Une fenêtre à taille fixe ne remplira pas l'écran : la photo va seulement à sa place, en haut à gauche.
            let vers = Self.redimensionnable(f) ? visible : CGRect(x: visible.minX, y: visible.maxY - c.height, width: c.width, height: c.height)
            TransitionFenetre.animer(image, de: TransitionFenetre.versÉcran(c), vers: vers, durée: 0.4, arrondiDépart: 20, arrondiArrivée: 0) {
                finale()
                TransitionFenetre.effacer(après: 0.15)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { finale() }
        }
    }

    /// La fenêtre accepte-t-elle qu'on change sa taille ?
    static func redimensionnable(_ f: AXUIElement) -> Bool {
        var ok: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(f, kAXSizeAttribute as CFString, &ok) == .success, ok.boolValue else { return false }
        // Certaines la déclarent modifiable mais n'ont pas de bouton vert utilisable (taille fixe).
        var b: CFTypeRef?
        AXUIElementCopyAttributeValue(f, kAXFullScreenButtonAttribute as CFString, &b)
        guard let b, CFGetTypeID(b) == AXUIElementGetTypeID() else { return true }
        var actif: CFTypeRef?
        AXUIElementCopyAttributeValue(b as! AXUIElement, kAXEnabledAttribute as CFString, &actif)
        return (actif as? Bool) ?? true
    }

    /// ⌃⌥↓ : l'application de devant va au tiroir. ⌃⌥↑ : l'application de devant, si elle est dans le tiroir, passe en plein écran.
    func brancherChangerDAvis() {
        TouchesBas.ajouter(50, touche: UInt32(kVK_DownArrow), modifs: UInt32(controlKey | optionKey)) { [weak self] in
            guard let a = NSWorkspace.shared.frontmostApplication else { return }
            self?.envoyerAuTiroir(pid: a.processIdentifier)
        }
        TouchesBas.ajouter(51, touche: UInt32(kVK_UpArrow), modifs: UInt32(controlKey | optionKey)) { [weak self] in
            guard let self, let b = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                  let e = self.emprunts.first(where: { $0.bundle == b }) else { NSSound.beep(); return }
            self.passerEnPleinEcran(nom: e.nom)
        }
    }

    /// Toutes les fenêtres garées hors de l'écran reviennent (Side quitte, ou le tiroir est coupé dans les réglages) :
    /// sans cela, elles resteraient invisibles jusqu'au prochain lancement de Side.
    func rendreToutesLesFenêtres() {
        guard !ouvert else { return }
        // Seulement celles qui sont vraiment garées : une fenêtre déjà à l'écran ne bouge pas.
        for e in emprunts where e.note == nil {
            guard let f = fenetre(e), let c = AXBas.cadre(f), c.minX >= Ecrans.bordGarage - 2 else { continue }
            rendreLaFenêtre(e)
        }
        if let notes = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").first {
            rendreLaGrandeFenêtreDeNotes(notes)
        }
    }

    func retirer(_ i: Int) {
        guard emprunts.indices.contains(i) else { return }
        let e = emprunts[i]
        rendreLaFenêtre(e)
        emprunts.remove(at: i)
        // Dernière note retirée : la grande fenêtre de Notes, garée hors de l'écran, revient aussi.
        if e.note != nil, let notes = app(e) { rendreLaGrandeFenêtreDeNotes(notes) }
        journalBas("tuile retirée : %@", e.nom)
        recharger(versLaFin: false)
    }

    /// La liste des tuiles a changé : on refait la bande.
    func recharger(versLaFin: Bool) {
        guard let p = panneau, ouvert else { return }
        if enPlace, !suiviDoigts {
            if !défile { défile = true; serie += 1; retenir(); ranger(sauf: []) }
            // La case « + » et la roue dentée ne sautent pas : elles glissent vers leur nouvelle place, au bord de la dernière tuile.
            let plusAvant = plus.frame, roueAvant = roue.frame
            poserImages()
            plus.frame = plusAvant
            roue.frame = roueAvant
            finDéfilement?.cancel()
            finirDéfilement(vers: versLaFin ? arrêts(p.frame).maxi : min(défilement, arrêts(p.frame).maxi))
        } else {
            poserImages()
        }
    }
}
