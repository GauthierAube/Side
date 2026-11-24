// Les écrans : le seul endroit qui choisit un écran, convertit les coordonnées et gare les fenêtres.
// Créé le 16/11/2026 (revue BAMA « deux écrans », docs/architecture-review-2026-11-16.md) : avant, Side faisait ce
// choix à 77 endroits avec quatre règles différentes, ce qui n'était pas visible avec un seul écran.
//
// Deux repères :
//  - AppKit (NSScreen, NSWindow) : origine en bas à gauche de l'écran principal, y vers le haut.
//  - AX et CGWindow (fenêtres des autres apps, événements CGEvent) : origine en haut à gauche de l'écran principal,
//    y vers le bas. L'écran principal est le premier de NSScreen.screens (celui de la barre des menus).

import AppKit

@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray

/// La logique pure : une disposition d'écrans en valeurs simples, testable sans écran réel (`Side --test-ecrans`).
struct DispositionEcrans {
    /// Chaque écran : son cadre et sa zone visible (sans barre des menus ni Dock), en coordonnées AppKit.
    /// Le premier est l'écran principal.
    var cadres: [CGRect]
    var visibles: [CGRect]

    var hauteurPrincipal: CGFloat { cadres.first?.height ?? 0 }

    /// AppKit → AX (et l'inverse : la même formule, elle est sa propre réciproque).
    func versAX(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: hauteurPrincipal - r.maxY, width: r.width, height: r.height)
    }
    func versNS(_ r: CGRect) -> CGRect { versAX(r) }

    /// L'écran qui contient ce point AppKit (avec un point de tolérance sur les bords), sinon le principal.
    func indice(sous p: CGPoint) -> Int {
        cadres.firstIndex { $0.contains(p) } ?? cadres.firstIndex { $0.insetBy(dx: -1, dy: -1).contains(p) } ?? 0
    }
    /// L'écran qui contient le centre de ce cadre AX, sinon le principal.
    func indice(contenantAX r: CGRect) -> Int {
        let c = versNS(CGRect(x: r.midX, y: r.midY, width: 0, height: 0)).origin
        return indice(sous: c)
    }

    /// Le bord droit de tous les écrans : une fenêtre posée au-delà n'est visible sur aucun.
    var bordGarage: CGFloat { cadres.map(\.maxX).max() ?? 0 }
    /// Où garer une fenêtre (AX) : après le bord droit de tous les écrans, tout en bas de l'écran principal.
    func garage(taille: CGSize) -> CGRect {
        CGRect(x: bordGarage - 1, y: hauteurPrincipal - 1, width: taille.width, height: taille.height)
    }
    /// La zone visible d'un écran, en coordonnées AX.
    func zoneVisibleAX(_ i: Int) -> CGRect { visibles.indices.contains(i) ? versAX(visibles[i]) : .zero }
}

enum Ecrans {
    static var disposition: DispositionEcrans {
        DispositionEcrans(cadres: NSScreen.screens.map(\.frame), visibles: NSScreen.screens.map(\.visibleFrame))
    }

    // MARK: Choisir un écran

    /// L'écran où l'on travaille : celui de la souris (sinon le principal). La règle de Side pour tout ce qui s'ouvre.
    static var deTravail: NSScreen? {
        let s = NSScreen.screens
        guard !s.isEmpty else { return nil }
        return s[disposition.indice(sous: NSEvent.mouseLocation)]
    }
    /// L'écran qui contient ce cadre AX (une fenêtre d'une autre app), sinon le principal.
    static func contenant(_ r: CGRect) -> NSScreen? {
        let s = NSScreen.screens
        guard !s.isEmpty else { return nil }
        return s[disposition.indice(contenantAX: r)]
    }

    static func ecran(_ identifiant: String) -> NSScreen? {
        for s in NSScreen.screens where self.identifiant(s) == identifiant { return s }
        return NSScreen.main
    }
    static func identifiant(_ s: NSScreen?) -> String {
        guard let n = s?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let u = CGDisplayCreateUUIDFromDisplayID(n)?.takeRetainedValue() else { return "Main" }
        return CFUUIDCreateString(nil, u) as String
    }

    // MARK: Convertir

    static func versAX(_ r: NSRect) -> CGRect { disposition.versAX(r) }
    static func versNS(_ r: CGRect) -> NSRect { disposition.versNS(r) }
    static func cadreGlobal(_ s: NSScreen?) -> CGRect {
        guard let n = s?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return CGDisplayBounds(CGMainDisplayID())
        }
        return CGDisplayBounds(n)
    }
    /// Zone utilisable (sans barre de menus ni Dock) d'un écran, en coordonnées AX.
    /// Pendant la grille, le Dock de macOS est sorti pour elle : on agrandit comme s'il était masqué (voir `DockNatif`).
    static func zoneVisible(_ e: NSScreen) -> CGRect { versAX(DockNatif.zoneSansDock(e) ?? e.visibleFrame) }
    /// Zone utilisable de l'écran qui contient ce cadre AX, en coordonnées AX.
    static func zoneVisible(contenant r: CGRect) -> CGRect {
        guard let s = contenant(r) else { return r }
        return zoneVisible(s)
    }

    // MARK: Garer

    static var bordGarage: CGFloat { disposition.bordGarage }
    static func garage(taille: CGSize) -> CGRect { disposition.garage(taille: taille) }

    // MARK: Plein écran d'Apple

    /// L'espace affiché sur cet écran est-il un plein écran d'Apple ?
    /// (Quand les écrans ne partagent pas leurs espaces, macOS n'en donne qu'un, nommé « Main ».)
    static func pleinEcranApple(sur e: NSScreen?) -> Bool {
        let liste = (CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]]) ?? []
        let id = identifiant(e)
        let entree = liste.first { ($0["Display Identifier"] as? String) == id } ?? liste.first
        return ((entree?["Current Space"] as? [String: Any])?["type"] as? Int) == 4
    }

    // MARK: Essai (Side --test-ecrans)

    /// Vérifie la logique pure sur trois dispositions, sans écran réel. Rend le nombre d'erreurs.
    static func essai() -> Int {
        var erreurs = 0
        func verifier(_ nom: String, _ obtenu: CGRect, _ attendu: CGRect) {
            let ok = obtenu.integral == attendu.integral
            if !ok { erreurs += 1 }
            print(ok ? "ok    " : "ÉCHEC ", nom, ok ? "" : "— obtenu \(obtenu), attendu \(attendu)")
        }
        func verifier(_ nom: String, _ obtenu: Int, _ attendu: Int) {
            let ok = obtenu == attendu
            if !ok { erreurs += 1 }
            print(ok ? "ok    " : "ÉCHEC ", nom, ok ? "" : "— obtenu \(obtenu), attendu \(attendu)")
        }
        func verifier(_ nom: String, _ obtenu: CGFloat, _ attendu: CGFloat) {
            let ok = abs(obtenu - attendu) < 0.5
            if !ok { erreurs += 1 }
            print(ok ? "ok    " : "ÉCHEC ", nom, ok ? "" : "— obtenu \(obtenu), attendu \(attendu)")
        }
        // 1. Un seul écran (MacBook Air), barre des menus de 33 points.
        let seul = DispositionEcrans(cadres: [CGRect(x: 0, y: 0, width: 1470, height: 956)],
                                     visibles: [CGRect(x: 0, y: 0, width: 1470, height: 923)])
        verifier("un écran : zone visible AX", seul.zoneVisibleAX(0), CGRect(x: 0, y: 33, width: 1470, height: 923))
        verifier("un écran : garage", seul.garage(taille: CGSize(width: 800, height: 600)), CGRect(x: 1469, y: 955, width: 800, height: 600))
        verifier("un écran : souris hors écran → principal", seul.indice(sous: CGPoint(x: 5000, y: 5000)), 0)

        // 2. Mac mini : Studio Display principal, LG à gauche aligné en haut (comme le 16/11/2026).
        let mini = DispositionEcrans(cadres: [CGRect(x: 0, y: 0, width: 2880, height: 1620),
                                              CGRect(x: -2304, y: 324, width: 2304, height: 1296)],
                                     visibles: [CGRect(x: 0, y: 0, width: 2880, height: 1590),
                                                CGRect(x: -2304, y: 324, width: 2304, height: 1296)])
        verifier("Mac mini : souris sur le LG", mini.indice(sous: CGPoint(x: -1000, y: 900)), 1)
        verifier("Mac mini : souris sur le Studio", mini.indice(sous: CGPoint(x: 1000, y: 900)), 0)
        verifier("Mac mini : zone visible du LG en AX", mini.zoneVisibleAX(1), CGRect(x: -2304, y: 0, width: 2304, height: 1296))
        verifier("Mac mini : fenêtre AX au milieu du LG", mini.indice(contenantAX: CGRect(x: -1500, y: 400, width: 600, height: 400)), 1)
        verifier("Mac mini : garage après le Studio", mini.bordGarage, 2880)
        let r = CGRect(x: -2000, y: 500, width: 300, height: 200)
        verifier("Mac mini : aller-retour AppKit ↔ AX", mini.versNS(mini.versAX(r)), r)

        // 3. MacBook Air + écran externe à droite : une fenêtre garée au bord du principal se verrait sur l'externe.
        let air = DispositionEcrans(cadres: [CGRect(x: 0, y: 0, width: 1470, height: 956),
                                             CGRect(x: 1470, y: 0, width: 2560, height: 1440)],
                                    visibles: [CGRect(x: 0, y: 0, width: 1470, height: 923),
                                               CGRect(x: 1470, y: 0, width: 2560, height: 1440)])
        verifier("Air + droite : garage après l'externe", air.bordGarage, 4030)
        verifier("Air + droite : souris sur l'externe", air.indice(sous: CGPoint(x: 2000, y: 100)), 1)
        print(erreurs == 0 ? "Écrans : tout est bon." : "Écrans : \(erreurs) échec(s).")
        return erreurs
    }
}
