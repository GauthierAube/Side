// Le plein écran : ce qu'il sait des fenêtres, des espaces et des écrans.
// Sorti de PleinEcran.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

struct Fenetre {
    let wid: CGWindowID
    let pid: pid_t
    let app: String
    let titre: String
    let cadre: CGRect          // coordonnées globales, origine en haut à gauche
    let agrandie: Bool         // remplit l'écran (mode Square), sans être un plein écran d'Apple
    let masquee: Bool          // son application est masquée
}

struct Espace {
    let id: UInt64
    let pleinEcran: Bool       // plein écran d'Apple
    let ecran: String          // identifiant de l'écran
    let rang: Int              // position dans l'ordre de Mission Control, sur son écran
    let fenetres: [Fenetre]    // de la plus en avant à la plus en arrière
    var nomBureau = "Bureau"
}

enum Cible {
    case espace(Espace)                 // un plein écran d'Apple, ou un bureau
    case fenetre(Fenetre, Espace)       // une fenêtre
    case groupe([Fenetre], Espace)      // des fenêtres qui se partagent l'écran : une seule case, une seule « page »
}

struct Tuile {
    let cle: String
    let titre: String
    let icone: NSImage?
    let cible: Cible
    let pid: pid_t
    /// La zone de l'écran occupée : le cadre de la fenêtre, ou celui qui englobe toutes les fenêtres d'un groupe.
    var cadre: CGRect? {
        switch cible {
        case .fenetre(let f, _): return f.cadre
        case .groupe(let fs, _): return Tuile.englobant(fs)
        case .espace: return nil
        }
    }
    static func englobant(_ fs: [Fenetre]) -> CGRect { fs.dropFirst().reduce(fs.first?.cadre ?? .zero) { $0.union($1.cadre) } }
    var place = 0              // case occupée dans la grille : elle ne change jamais tant que la fenêtre existe
}

enum Ecrans {
    static func ecran(_ identifiant: String) -> NSScreen? {
        for s in NSScreen.screens where self.identifiant(s) == identifiant { return s }
        return NSScreen.main
    }
    static func identifiant(_ s: NSScreen?) -> String {
        guard let n = s?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let u = CGDisplayCreateUUIDFromDisplayID(n)?.takeRetainedValue() else { return "Main" }
        return CFUUIDCreateString(nil, u) as String
    }
    static func cadreGlobal(_ s: NSScreen?) -> CGRect {
        guard let n = s?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return CGDisplayBounds(CGMainDisplayID())
        }
        return CGDisplayBounds(n)
    }
    /// Zone utilisable (sans barre de menus ni Dock) de l'écran qui contient ce cadre, origine en haut à gauche.
    static func zoneVisible(contenant r: CGRect) -> CGRect {
        let centre = CGPoint(x: r.midX, y: r.midY)
        let s = NSScreen.screens.first { cadreGlobal($0).contains(centre) } ?? NSScreen.main
        guard let s else { return r }
        let h = NSScreen.screens.first?.frame.height ?? s.frame.height
        let v = s.visibleFrame
        return CGRect(x: v.minX, y: h - v.maxY, width: v.width, height: v.height)
    }
}

enum Relevé {
    /// Tous les espaces (plein écran d'Apple et bureaux) avec leurs fenêtres, et l'espace affiché sur chaque écran.
    static func tout() -> (espaces: [Espace], courants: [String: UInt64]) {
        let cid = CGSMainConnectionID()
        let infos = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
        var parId: [CGWindowID: [String: Any]] = [:]
        for i in infos { if let n = i[kCGWindowNumber as String] as? CGWindowID { parId[n] = i } }
        let moi = ProcessInfo.processInfo.processIdentifier
        var apps: [pid_t: NSRunningApplication] = [:]
        for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular { apps[a.processIdentifier] = a }
        // Side n'a pas de fenêtre à ranger, sauf une : la vidéo qu'il sort de son tiroir en plein écran. Il en donne le numéro.
        let videoSide = Relevé.videoDeSide(parId)
        if let v = videoSide { apps[v.pid] = v.app }
        // Les fenêtres rangées dans le tiroir de Side ne sont pas à Square : ni grille, ni carrousel.
        let tiroir = Relevé.fenetresDuTiroir()

        var espaces: [Espace] = []
        var courants: [String: UInt64] = [:]
        let ecrans = (CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]]) ?? []
        for e in ecrans {
            let ecran = (e["Display Identifier"] as? String) ?? "Main"
            if let c = ((e["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value { courants[ecran] = c }
            var numeroBureau = 0
            let liste = (e["Spaces"] as? [[String: Any]]) ?? []
            let nbBureaux = liste.filter { ($0["type"] as? Int) == 0 }.count
            for (rang, s) in liste.enumerated() {
                guard let id = (s["id64"] as? NSNumber)?.uint64Value else { continue }
                let plein = (s["type"] as? Int) == 4
                var a: UInt64 = 0, b: UInt64 = 0
                let espace = [NSNumber(value: id)] as CFArray
                // Option 2 : fenêtres visibles, dans l'ordre. Option 7 : aussi celles des applications masquées (et les réduites).
                let visibles = (CGSCopyWindowsWithOptionsAndTags(cid, 0, espace, 2, &a, &b) as? [NSNumber])?.map { $0.uint32Value } ?? []
                let toutes = (CGSCopyWindowsWithOptionsAndTags(cid, 0, espace, 7, &a, &b) as? [NSNumber])?.map { $0.uint32Value } ?? []
                var fenetres: [Fenetre] = []
                for (w, masquee) in visibles.map({ ($0, false) }) + toutes.filter({ !visibles.contains($0) }).map({ ($0, true) }) {
                    guard let i = parId[w],
                          (i[kCGWindowLayer as String] as? Int) == 0,
                          // Les fenêtres de l'app elle-même ne comptent pas, sauf la vidéo sortie du tiroir en plein écran.
                          let pid = i[kCGWindowOwnerPID as String] as? pid_t, pid != moi || w == videoSide?.wid, let app = apps[pid],
                          app.activationPolicy == .regular || w == videoSide?.wid,
                          !tiroir.contains(w),
                          !masquee || app.isHidden,                 // une fenêtre réduite dans le Dock ne compte pas
                          let d = i[kCGWindowBounds as String] as? NSDictionary,
                          let cadre = CGRect(dictionaryRepresentation: d),
                          cadre.width >= 120, cadre.height >= 80,
                          // Une fenêtre rangée hors de l'écran (le panneau du bas de Side range ainsi les siennes) ne compte pas.
                          NSScreen.screens.contains(where: { s in
                              let commun = Ecrans.cadreGlobal(s).intersection(cadre)
                              return !commun.isNull && commun.width * commun.height >= 0.1 * cadre.width * cadre.height
                          }),
                          ((i[kCGWindowAlpha as String] as? Double) ?? 1) > 0.05 else { continue }
                    var agrandie = false
                    if !plein {
                        let zone = Ecrans.zoneVisible(contenant: cadre)
                        let commun = cadre.intersection(zone)
                        agrandie = !commun.isNull && commun.width * commun.height >= 0.9 * zone.width * zone.height
                    }
                    fenetres.append(Fenetre(wid: w, pid: pid, app: app.localizedName ?? "?",
                                            titre: (i[kCGWindowName as String] as? String) ?? "",
                                            cadre: cadre, agrandie: agrandie, masquee: masquee))
                }
                var esp = Espace(id: id, pleinEcran: plein, ecran: ecran, rang: rang, fenetres: fenetres)
                if !plein {
                    numeroBureau += 1
                    esp.nomBureau = nbBureaux > 1 ? "Bureau \(numeroBureau)" : "Bureau"
                }
                espaces.append(esp)
            }
        }
        return (espaces, courants)
    }

    static func espaceCourant(ecran: String) -> UInt64? { tout().courants[ecran] }

    static let side = "com.gauthieraube.side"
    /// La fenêtre de la vidéo que Side affiche en grand (réglage `videoPleinEcran` de Side), si elle existe bien et lui appartient.
    static func videoDeSide(_ parId: [CGWindowID: [String: Any]]) -> (wid: CGWindowID, pid: pid_t, app: NSRunningApplication)? {
        CFPreferencesAppSynchronize(side as CFString)
        guard let n = CFPreferencesCopyAppValue("videoPleinEcran" as CFString, side as CFString) as? Int, n > 0,
              let i = parId[CGWindowID(n)], let pid = i[kCGWindowOwnerPID as String] as? pid_t,
              let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == side else { return nil }
        return (CGWindowID(n), pid, app)
    }
    /// Side dit-il avoir une vidéo en grand ? (Sans vérifier la fenêtre : pour les tests rapides.)
    static var videoDeSideAnnoncee: Bool {
        ((CFPreferencesCopyAppValue("videoPleinEcran" as CFString, side as CFString) as? Int) ?? 0) > 0
    }
    /// Les numéros des fenêtres rangées dans le tiroir de Side (réglage `fenetresDuTiroir`, tenu par Side), si Side tourne.
    static func fenetresDuTiroir() -> Set<CGWindowID> {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: side).isEmpty else { return [] }
        CFPreferencesAppSynchronize(side as CFString)
        let ids = (CFPreferencesCopyAppValue("fenetresDuTiroir" as CFString, side as CFString) as? [Int]) ?? []
        return Set(ids.map { CGWindowID($0) })
    }
    /// Ferme une fenêtre par son bouton rouge, sans quitter l'application.
    static func fermerFenetre(pid: pid_t, wid: CGWindowID) {
        guard let el = AX.fenetre(pid: pid, wid: wid) else { return }
        var bouton: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXCloseButtonAttribute as CFString, &bouton)
        if let bouton, CFGetTypeID(bouton) == AXUIElementGetTypeID() { AXUIElementPerformAction(bouton as! AXUIElement, kAXPressAction as CFString) }
    }
}
