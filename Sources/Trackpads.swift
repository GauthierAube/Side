// Les trackpads du Mac, lus par le module privé MultitouchSupport. Partagé par les deux gestes à quatre doigts
// (Finder : Gestes4Doigts.swift ; plein écran : PleinEcranGlisse.swift).
// Avant le 15/11/2026, chacun lisait la liste une seule fois au lancement : un trackpad Bluetooth allumé après Side,
// ou reconnecté après une veille, n'était jamais écouté.

import AppKit

enum Trackpads {
    typealias Rappel = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias Liste = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Inscrire = @convention(c) (UnsafeMutableRawPointer?, Rappel) -> Void
    private typealias Lancer = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
    private typealias EnMarche = @convention(c) (UnsafeMutableRawPointer?) -> Bool
    private typealias Numero = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt64>) -> Int32

    private struct Fonctions { let liste: Liste; let inscrire: Inscrire; let lancer: Lancer; let enMarche: EnMarche?; let numero: Numero? }
    private static let fonctions: Fonctions? = {
        guard let m = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let l = dlsym(m, "MTDeviceCreateList"), let i = dlsym(m, "MTRegisterContactFrameCallback"),
              let s = dlsym(m, "MTDeviceStart") else { return nil }
        return Fonctions(liste: unsafeBitCast(l, to: Liste.self), inscrire: unsafeBitCast(i, to: Inscrire.self),
                         lancer: unsafeBitCast(s, to: Lancer.self),
                         enMarche: dlsym(m, "MTDeviceIsRunning").map { unsafeBitCast($0, to: EnMarche.self) },
                         numero: dlsym(m, "MTDeviceGetDeviceID").map { unsafeBitCast($0, to: Numero.self) })
    }()

    private static var rappels: [Rappel] = []
    /// Les trackpads déjà écoutés, par numéro d'appareil (gardés en vie : le module ne les retient pas).
    private static var connus: [UInt64: AnyObject] = [:]
    private static var veille: Timer?

    /// Ajoute une fonction appelée à chaque instant où des doigts touchent un trackpad (hors du fil principal).
    /// Renvoie le nombre de trackpads écoutés, ou -1 si le module est illisible.
    @discardableResult
    static func ecouter(_ rappel: Rappel) -> Int {
        guard let f = fonctions else { return -1 }
        rappels.append(rappel)
        for a in connus.values { f.inscrire(Unmanaged.passUnretained(a).toOpaque(), rappel) }
        chercher()
        if veille == nil {
            // Un trackpad allumé ou reconnecté plus tard : on refait la liste de temps en temps, et au réveil du Mac.
            veille = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in chercher() }
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { relancer(); chercher() }
            }
        }
        return connus.count
    }

    /// Inscrit les trackpads pas encore écoutés. Vrai si un nouveau est apparu.
    @discardableResult
    static func chercher() -> Bool {
        guard let f = fonctions, let appareils = f.liste()?.takeRetainedValue() as? [AnyObject] else { return false }
        var nouveau = false
        for (rang, a) in appareils.enumerated() {
            let p = Unmanaged.passUnretained(a).toOpaque()
            var n: UInt64 = 0
            // Sans numéro d'appareil (module ancien), le rang dans la liste en tient lieu.
            if let numero = f.numero, numero(p, &n) == 0 {} else { n = UInt64(rang) }
            guard connus[n] == nil else { continue }
            connus[n] = a
            for r in rappels { f.inscrire(p, r) }
            f.lancer(p, 0)
            nouveau = true
        }
        if nouveau { journal("Trackpads : %d écouté(s)", connus.count) }
        return nouveau
    }

    /// Au réveil du Mac, un trackpad peut avoir cessé d'envoyer ses touches : on le relance.
    static func relancer() {
        guard let f = fonctions else { return }
        for a in connus.values {
            let p = Unmanaged.passUnretained(a).toOpaque()
            if f.enMarche.map({ !$0(p) }) ?? true { f.lancer(p, 0) }
        }
    }
}
