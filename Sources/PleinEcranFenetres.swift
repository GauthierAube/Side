// Le plein écran : retrouver, placer, agrandir une fenêtre, et passer d'une fenêtre à l'autre.
// Sorti de PleinEcran.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

enum AX {
    private static var reperes: [CGWindowID: UInt64] = [:]     // déjà trouvées : on les retrouve tout de suite

    private static func element(pid: pid_t, numero: UInt64, wid: CGWindowID) -> AXUIElement? {
        var d = Data(count: 20)
        d.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        d.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        d.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        d.replaceSubrange(12..<20, with: withUnsafeBytes(of: numero) { Data($0) })
        guard let el = _AXUIElementCreateWithRemoteToken(d as CFData)?.takeRetainedValue() else { return nil }
        var w: CGWindowID = 0
        guard _AXUIElementGetWindow(el, &w) == .success, w == wid else { return nil }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        return (role as? String) == (kAXWindowRole as String) ? el : nil
    }

    /// Retrouve la fenêtre d'une application, même si elle est sur un autre espace.
    static func fenetre(pid: pid_t, wid: CGWindowID) -> AXUIElement? {
        if let n = reperes[wid], let el = element(pid: pid, numero: n, wid: wid) { return el }
        let debut = Date()
        for i: UInt64 in 0..<60000 {
            if i % 16 == 0, Date().timeIntervalSince(debut) > 0.6 { break }     // souvent : une application figée rend chaque essai lent
            if let el = element(pid: pid, numero: i, wid: wid) { reperes[wid] = i; return el }
        }
        return nil
    }

    static func vrai(_ el: AXUIElement, _ attribut: String) -> Bool {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, attribut as CFString, &v)
        return (v as? Bool) ?? false
    }

    static func cadre(_ el: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p)
        AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s)
        guard let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, taille = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &taille)
        return CGRect(origin: point, size: taille)
    }

    static func placer(_ el: AXUIElement, _ r: CGRect) {
        var p = r.origin, s = r.size
        guard let vp = AXValueCreate(.cgPoint, &p), let vs = AXValueCreate(.cgSize, &s) else { return }
        // Comme AeroSpace : taille, position, puis taille de nouveau (la première peut être bridée par l'ancienne position),
        // en coupant le temps du réglage le mode « interface enrichie » qui fait traîner certaines applications.
        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        let app = AXUIElementCreateApplication(pid)
        let enrichie = vrai(app, "AXEnhancedUserInterface")
        if enrichie { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, vs)
        AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, vp)
        AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, vs)
        if enrichie { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }

    static func lever(_ el: AXUIElement) {
        AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
    }
}

enum Agrandir {
    private static var anciens: [CGWindowID: CGRect] = [:]      // taille d'avant, pour pouvoir revenir en arrière

    /// Agrandit la fenêtre pour remplir l'écran (ou lui rend sa taille si elle l'est déjà).
    /// Un plein écran d'Apple est d'abord quitté.
    static func basculer(_ el: AXUIElement, seulementAgrandir: Bool = false) {
        if AX.vrai(el, "AXFullScreen") {
            AXUIElementSetAttributeValue(el, "AXFullScreen" as CFString, kCFBooleanFalse)
            attendreSortie(el, essais: 20)
            return
        }
        guard let cadre = AX.cadre(el) else { return }
        let zone = Ecrans.zoneVisible(contenant: cadre)
        var wid: CGWindowID = 0
        _ = _AXUIElementGetWindow(el, &wid)
        let commun = cadre.intersection(zone)
        let dejà = !commun.isNull && commun.width * commun.height >= 0.9 * zone.width * zone.height
        // Une vidéo aux proportions fixes (QuickTime) n'atteint jamais 90 % de l'écran : déjà suivie sur fond noir, elle compte comme agrandie.
        if dejà || FondNoir.estSuivie(wid) {
            // Taille d'avant inconnue (Side relancé, fenêtre rouverte déjà agrandie) : une taille réduite, centrée.
            // Avant, le bouton vert ne faisait alors plus rien.
            if !seulementAgrandir {
                let avant = anciens[wid] ?? zone.insetBy(dx: zone.width * 0.15, dy: zone.height * 0.12)
                AX.placer(el, avant); anciens[wid] = nil; FondNoir.oublier(wid)
            }
        } else {
            anciens[wid] = cadre
            Groupes.retirer(wid)             // agrandie, elle ne partage plus l'écran avec personne
            AX.placer(el, zone)
            FondNoir.verifier(el, zone: zone)
        }
    }

    private static func attendreSortie(_ el: AXUIElement, essais: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if AX.vrai(el, "AXFullScreen"), essais > 0 { attendreSortie(el, essais: essais - 1); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let cadre = AX.cadre(el) { AX.placer(el, Ecrans.zoneVisible(contenant: cadre)) }
            }
        }
    }

    static func fenetreActive() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute as CFString, &v)
        guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { NSSound.beep(); return }
        basculer(v as! AXUIElement)
    }

    /// Sort toutes les applications du plein écran d'Apple et les agrandit à la place.
    static func convertirTout() {
        let pleins = Relevé.tout().espaces.filter { $0.pleinEcran }
        journal("Square: conversion de %d plein écran", pleins.count)
        for (i, e) in pleins.enumerated() {
            guard let f = e.fenetres.first else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4) {
                if let el = AX.fenetre(pid: f.pid, wid: f.wid) { basculer(el, seulementAgrandir: true) }
            }
        }
    }
}

// MARK: - Aller quelque part

enum Bascule {
    static func fleche(gauche: Bool) {
        let src = CGEventSource(stateID: .hidSystemState)
        for appui in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: gauche ? 123 : 124, keyDown: appui) else { continue }
            e.flags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
            e.post(tap: .cghidEventTap)
            usleep(15000)
        }
    }

    /// Dernier recours pour changer d'espace : Contrôle + flèches, autant de fois qu'il faut.
    static func parFleches(vers cible: Espace, puis fin: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInteractive).async {
            for _ in 0..<12 {
                let (espaces, courants) = Relevé.tout()
                guard let ici = courants[cible.ecran], ici != cible.id,
                      let rangIci = espaces.first(where: { $0.id == ici })?.rang,
                      let rangCible = espaces.first(where: { $0.id == cible.id })?.rang else { break }
                fleche(gauche: rangCible < rangIci)
                let t = Date()
                while Date().timeIntervalSince(t) < 1.2, Relevé.espaceCourant(ecran: cible.ecran) == ici { usleep(30000) }
                if Relevé.espaceCourant(ecran: cible.ecran) == ici { break }   // la flèche n'a rien fait
            }
            DispatchQueue.main.async(execute: fin)
        }
    }

    /// Met une fenêtre devant. Si elle est sur un autre espace, macOS y glisse.
    static func montrer(_ f: Fenetre, dans e: Espace) {
        guard let app = NSRunningApplication(processIdentifier: f.pid) else { return }
        let el = AX.fenetre(pid: f.pid, wid: f.wid)
        journal("Square: vers %@ (fenêtre %d), accessibilité=%d, trouvée=%d", f.app, Int(f.wid), AXIsProcessTrusted() ? 1 : 0, el != nil ? 1 : 0)
        if app.isHidden { app.unhide() }
        // Une fenêtre de Side elle-même (la vidéo du tiroir en plein écran) : Side passe devant par ses propres moyens.
        // (Demander à macOS d'« activer » Side comme une autre application ne marche pas toujours : on voyait la vidéo
        // une seconde, puis l'application d'avant revenait devant.)
        if f.pid == ProcessInfo.processInfo.processIdentifier {
            NSApp.activate(ignoringOtherApps: true)
            if let w = NSApp.window(withWindowNumber: Int(f.wid)) {
                w.makeKeyAndOrderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { if !w.isKeyWindow { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil) } }
            }
            return
        }
        // Une fenêtre qui partage l'écran avec d'autres les amène devant avec elle.
        Groupes.monterLeGroupe(de: f) {
            if let el { AX.lever(el) }
            // Ses réglages ou ses boîtes de dialogue restent au-dessus d'elle, comme dans macOS.
            for s in Relevé.secondaires[f.pid] ?? [] { AX.lever(s) }
            app.activate(options: [])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if Relevé.espaceCourant(ecran: e.ecran) != e.id {
                journal("Square: pas arrivé, on finit avec les flèches")
                parFleches(vers: e) {}
            }
        }
    }

    /// Affiche le bureau : les applications agrandies sont masquées, les fenêtres normales reviennent devant.
    static func bureau(_ e: Espace) {
        let normales = e.fenetres.filter { !$0.agrandie && !$0.masquee }
        let pidsNormales = Set(normales.map { $0.pid })
        for pid in Set(e.fenetres.filter { $0.agrandie && !$0.masquee }.map { $0.pid }) where !pidsNormales.contains(pid) {
            NSRunningApplication(processIdentifier: pid)?.hide()
        }
        let finir = {
            for f in normales.prefix(8).reversed() { if let el = AX.fenetre(pid: f.pid, wid: f.wid) { AX.lever(el) } }
            if let premier = normales.first, let app = NSRunningApplication(processIdentifier: premier.pid) {
                app.activate(options: [])
            } else {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate(options: [])
            }
        }
        if Relevé.espaceCourant(ecran: e.ecran) == e.id { finir(); return }
        if let premier = normales.first {
            montrer(premier, dans: e)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: finir)
        } else {
            journal("Square: vers %@ par les flèches", e.nomBureau)
            parFleches(vers: e, puis: finir)
        }
    }

    static func aller(_ t: Tuile, espaces: [Espace]) {
        switch t.cible {
        case .groupe(let fs, let e):
            if let f = fs.first { montrer(f, dans: e) }
        case .fenetre(let f, let e):
            montrer(f, dans: e)
        case .espace(let e):
            if e.pleinEcran, let f = e.fenetres.first { montrer(f, dans: e) } else if !e.pleinEcran { bureau(e) }
        }
    }

    static func fenetre(deLApp pid: pid_t, espaces: [Espace]) -> (Fenetre, Espace)? {
        guard pid != 0 else { return nil }
        for e in espaces { if let f = e.fenetres.first(where: { $0.pid == pid }) { return (f, e) } }
        return nil
    }

    /// L'espace change-t-il d'écran (glissement de macOS) pour atteindre cette case ?
    static func espaceVise(_ t: Tuile, espaces: [Espace]) -> Espace? {
        switch t.cible {
        case .fenetre(_, let e): return e
        case .groupe(_, let e): return e
        case .espace(let e): return e
        }
    }
}
