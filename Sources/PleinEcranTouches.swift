// Le plein écran : ses raccourcis clavier globaux.
// Sorti de PleinEcran.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

/// Les raccourcis du plein écran, rangés sous le nom « pleinEcran.<numéro> » dans le registre commun de Side.
enum Touches {
    static func ajouter(_ id: UInt32, touche: UInt32, modifs: UInt32, action: @escaping () -> Void) {
        RaccourcisGlobaux.ajouter("pleinEcran.\(id)", touche: touche, modifs: modifs, action: action)
    }
    static func retirer(_ id: UInt32) { RaccourcisGlobaux.retirer("pleinEcran.\(id)") }
}

struct Raccourci {
    var touche: UInt32
    var modifs: UInt32      // au format Carbon
    var nom: String

    static let défaut = Raccourci(touche: UInt32(kVK_Tab), modifs: UInt32(optionKey), nom: "⌥ Tab")

    static var actuel: Raccourci {
        get {
            let d = UserDefaults.standard
            guard let nom = d.string(forKey: "raccourciNom") else { return défaut }
            guard let touche = UInt32(exactly: d.integer(forKey: "raccourciTouche")) else { return défaut }
            return Raccourci(touche: touche,
                             modifs: UInt32(d.integer(forKey: "raccourciModifs")), nom: nom)
        }
        set {
            let d = UserDefaults.standard
            d.set(Int(newValue.touche), forKey: "raccourciTouche")
            d.set(Int(newValue.modifs), forKey: "raccourciModifs")
            d.set(newValue.nom, forKey: "raccourciNom")
        }
    }

    static func depuis(_ e: NSEvent) -> Raccourci? {
        let m = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let speciales: [Int: String] = [
            kVK_Tab: "Tab", kVK_Space: String(localized: "Espace"), kVK_Return: String(localized: "Entrée"), kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3",
            kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
            kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓"]
        let code = Int(e.keyCode)
        let touche = speciales[code] ?? (e.charactersIgnoringModifiers ?? "?").uppercased()
        let estF = (speciales[code] ?? "").hasPrefix("F")
        if m.isEmpty && !estF { return nil }            // une lettre seule bloquerait la frappe
        var carbon: UInt32 = 0
        var nom = ""
        if m.contains(.control) { carbon |= UInt32(controlKey); nom += "⌃" }
        if m.contains(.option) { carbon |= UInt32(optionKey); nom += "⌥" }
        if m.contains(.shift) { carbon |= UInt32(shiftKey); nom += "⇧" }
        if m.contains(.command) { carbon |= UInt32(cmdKey); nom += "⌘" }
        return Raccourci(touche: UInt32(code), modifs: carbon, nom: nom.isEmpty ? touche : nom + " " + touche)
    }
}
