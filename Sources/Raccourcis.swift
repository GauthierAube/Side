// Les raccourcis clavier globaux de Side, et la saisie d'un nouveau raccourci dans les réglages.
// Avant le 15/11/2026, il y en avait trois copies (Finder, plein écran, tiroir) : trois gestionnaires qui se volaient
// les touches, et trois saisies qui oubliaient de s'arrêter. Tout passe maintenant par ici.

import AppKit
import Carbon.HIToolbox

/// Tous les raccourcis globaux de Side : un seul gestionnaire pour toute l'application, un nom par raccourci
/// (« finder », « tiroir.42 », « pleinEcran.200 »…).
enum RaccourcisGlobaux {
    private static let signature = OSType(0x5349_4445)   // "SIDE"
    private static var installé = false
    private static var numéros: [String: UInt32] = [:]
    private static var actions: [UInt32: () -> Void] = [:]
    private static var refs: [UInt32: EventHotKeyRef] = [:]
    private static var combinaisons: [String: (touche: UInt32, modifs: UInt32)] = [:]

    private static func installer() {
        guard !installé else { return }
        installé = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, ev, _ in
            var hk = EventHotKeyID()
            GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard hk.signature == RaccourcisGlobaux.signature else { return OSStatus(eventNotHandledErr) }
            RaccourcisGlobaux.actions[hk.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }

    private static func numéro(_ nom: String) -> UInt32 {
        if let n = numéros[nom] { return n }
        let n = UInt32(numéros.count + 1)
        numéros[nom] = n
        return n
    }

    /// Enregistre (ou remplace) le raccourci de ce nom. Faux si macOS le refuse : combinaison déjà prise,
    /// par une autre partie de Side ou par une autre application.
    @discardableResult
    static func ajouter(_ nom: String, touche: UInt32, modifs: UInt32, action: @escaping () -> Void) -> Bool {
        installer()
        retirer(nom)
        let id = numéro(nom)
        var ref: EventHotKeyRef?
        let etat = RegisterEventHotKey(touche, modifs, EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(), 0, &ref)
        guard etat == noErr, let ref else {
            let autre = propriétaire(touche: touche, modifs: modifs).map { " (déjà pris par « \($0) »)" } ?? ""
            journal("Raccourci « %@ » refusé : touche %d, erreur %d%@", nom, Int(touche), Int(etat), autre)
            return false
        }
        refs[id] = ref
        actions[id] = action
        combinaisons[nom] = (touche, modifs)
        return true
    }

    static func retirer(_ nom: String) {
        guard let id = numéros[nom] else { return }
        if let r = refs[id] { UnregisterEventHotKey(r) }
        refs[id] = nil
        actions[id] = nil
        combinaisons[nom] = nil
    }

    /// Le nom du raccourci de Side qui utilise déjà cette combinaison, s'il y en a un.
    static func propriétaire(touche: UInt32, modifs: UInt32) -> String? {
        combinaisons.first { $0.value.touche == touche && $0.value.modifs == modifs }?.key
    }
}

/// La saisie d'un nouveau raccourci dans les réglages. Une seule à la fois pour toute l'application :
/// en commencer une abandonne la précédente, et fermer les réglages abandonne celle en cours.
enum SaisieRaccourci {
    private static var écouteur: Any?
    private static var reprendre: (() -> Void)?

    /// Une saisie est-elle en cours ? (Les autres touches de Side, comme Espace pour l'aperçu, la laissent passer.)
    static var enCours: Bool { écouteur != nil }

    /// Attend la prochaine combinaison tapée. `suspendre` coupe l'ancien raccourci pendant la saisie ; `reprendre` le remet
    /// (Échap, ou saisie abandonnée) ; `choisi` reçoit la touche, les modificateurs (format Carbon) et le libellé.
    static func attendre(suspendre: () -> Void, reprendre: @escaping () -> Void,
                         choisi: @escaping (_ touche: Int, _ mods: Int, _ libellé: String) -> Void,
                         fin: @escaping () -> Void) {
        annuler()
        suspendre()
        Self.reprendre = reprendre
        écouteur = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            let f = ev.modifierFlags
            let annule = ev.keyCode == UInt16(kVK_Escape)
            // Il faut au moins Commande, Contrôle ou Option, sinon on bloquerait une touche normale dans tout le Mac.
            guard annule || !f.intersection([.command, .control, .option]).isEmpty else { NSSound.beep(); return nil }
            arrêter()
            if annule { reprendre(); fin(); return nil }
            var mods = 0, texte = ""
            if f.contains(.control) { mods |= controlKey; texte += "⌃" }
            if f.contains(.option) { mods |= optionKey; texte += "⌥" }
            if f.contains(.shift) { mods |= shiftKey; texte += "⇧" }
            if f.contains(.command) { mods |= cmdKey; texte += "⌘" }
            texte += ev.keyCode == UInt16(kVK_Space) ? String(localized: "Espace") : (ev.charactersIgnoringModifiers ?? "?").uppercased()
            choisi(Int(ev.keyCode), mods, texte)
            fin()
            return nil
        }
    }

    /// Abandonne la saisie en cours, s'il y en a une, et remet l'ancien raccourci en service.
    static func annuler() {
        guard écouteur != nil else { return }
        let r = reprendre
        arrêter()
        r?()
    }

    private static func arrêter() {
        if let e = écouteur { NSEvent.removeMonitor(e) }
        écouteur = nil
        reprendre = nil
    }
}
