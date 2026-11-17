// Les touches du volume et de la luminosité (17/11/2026), idée reprise de MediaMate : au lieu du carré gris de macOS au
// milieu de l'écran, l'île de l'encoche s'étire et montre la jauge. Side intercepte la touche, règle lui-même le son ou
// la luminosité, puis l'affiche. S'il ne sait pas régler (sortie audio sans volume, écran externe), la touche est rendue
// à macOS, qui fait comme d'habitude. ⇧⌥ + touche : pas fins (un quart de cran), comme dans macOS.
import AppKit
import AudioToolbox
import CoreAudio

enum ToucheIle {
    private static var tap: CFMachPort?
    private static var source: CFRunLoopSource?
    /// Les touches enfoncées que Side a prises : leur relâché ne doit pas non plus arriver à macOS.
    private static var prises = Set<Int>()

    /// Allume ou éteint l'interception selon les réglages et la présence de l'encoche.
    static func majActivation() {
        let veut = Partie.encoche.active && ConfigEncoche.commun.touches && Ile.commun.ecran != nil
        if veut, tap == nil { demarrer() }
        if !veut, let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(t)
            tap = nil; source = nil; prises = []
        }
    }

    private static func demarrer() {
        // 14 = NX_SYSDEFINED : les touches spéciales (son, luminosité, lecture).
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(1 << 14),
                                        callback: { _, type, ev, _ in ToucheIle.recu(type, ev) }, userInfo: nil) else { return }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    private static func recu(_ type: CGEventType, _ ev: CGEvent) -> Unmanaged<CGEvent>? {
        let laisser = Unmanaged.passUnretained(ev)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return laisser
        }
        guard type.rawValue == 14, let e = NSEvent(cgEvent: ev), e.subtype.rawValue == 8 else { return laisser }
        let code = (e.data1 & 0xFFFF_0000) >> 16
        let enfonce = ((e.data1 & 0xFF00) >> 8) == 0xA
        guard [0, 1, 2, 3, 7].contains(code) else { return laisser }
        if !enfonce { return prises.remove(code) != nil ? nil : laisser }
        let mods = e.modifierFlags.intersection([.shift, .option, .command, .control])
        // ⌥ seul ouvre les réglages Son ou Moniteurs, ⌘ et ⌃ ont leurs usages : macOS s'en occupe.
        if mods == .option || mods.contains(.command) || mods.contains(.control) { return laisser }
        let fin = mods == [.shift, .option]
        let fait: Bool
        switch code {
        case 0: fait = Son.changer(+1, fin: fin)
        case 1: fait = Son.changer(-1, fin: fin)
        case 7: fait = Son.basculerMuet()
        case 2: fait = Lumiere.changer(+1, fin: fin)
        case 3: fait = Lumiere.changer(-1, fin: fin)
        default: fait = false
        }
        guard fait else { return laisser }
        prises.insert(code)
        return nil
    }
}

/// Le volume de la sortie audio en cours.
enum Son {
    private static func appareil() -> AudioObjectID? {
        var id = AudioObjectID(0)
        var taille = UInt32(MemoryLayout<AudioObjectID>.size)
        var adresse = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let r = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &adresse, 0, nil, &taille, &id)
        return r == noErr && id != 0 ? id : nil
    }

    private static var adresseVolume = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                                  mScope: kAudioDevicePropertyScopeOutput,
                                                                  mElement: kAudioObjectPropertyElementMain)
    private static var adresseMuet = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                                mScope: kAudioDevicePropertyScopeOutput,
                                                                mElement: kAudioObjectPropertyElementMain)

    private static func volume(_ id: AudioObjectID) -> Float? {
        var v: Float32 = 0
        var taille = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(id, &adresseVolume, 0, nil, &taille, &v) == noErr ? v : nil
    }

    private static func reglable(_ id: AudioObjectID, _ adresse: inout AudioObjectPropertyAddress) -> Bool {
        var oui: DarwinBoolean = false
        return AudioObjectHasProperty(id, &adresse) && AudioObjectIsPropertySettable(id, &adresse, &oui) == noErr && oui.boolValue
    }

    private static func muet(_ id: AudioObjectID) -> Bool {
        var m: UInt32 = 0
        var taille = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &adresseMuet, 0, nil, &taille, &m) == noErr && m != 0
    }

    private static func mettreMuet(_ id: AudioObjectID, _ oui: Bool) -> Bool {
        guard reglable(id, &adresseMuet) else { return false }
        var m: UInt32 = oui ? 1 : 0
        return AudioObjectSetPropertyData(id, &adresseMuet, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m) == noErr
    }

    static func changer(_ sens: Int, fin: Bool) -> Bool {
        guard let id = appareil(), reglable(id, &adresseVolume), let actuel = volume(id) else { return false }
        let pas: Float = fin ? 1 / 64 : 1 / 16
        var etaitMuet = muet(id)
        if etaitMuet, sens > 0, mettreMuet(id, false) { etaitMuet = false }
        var v = max(0, min(1, ((actuel / pas).rounded() + Float(sens)) * pas))
        guard AudioObjectSetPropertyData(id, &adresseVolume, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr else { return false }
        Ile.commun.montrerHud(.volume, niveau: Double(v), muet: etaitMuet)
        return true
    }

    static func basculerMuet() -> Bool {
        guard let id = appareil() else { return false }
        let devient = !muet(id)
        guard mettreMuet(id, devient) else { return false }
        Ile.commun.montrerHud(.volume, niveau: Double(volume(id) ?? 0), muet: devient)
        return true
    }
}

/// La luminosité de l'écran du MacBook (par DisplayServices, la bibliothèque qu'utilise macOS lui-même).
enum Lumiere {
    private typealias Lire = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Ecrire = @convention(c) (UInt32, Float) -> Int32
    private static let bibliotheque = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let lire: Lire? = bibliotheque.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Lire.self) }
    private static let ecrire: Ecrire? = bibliotheque.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Ecrire.self) }

    private static var ecranInterne: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &n) == .success else { return nil }
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func changer(_ sens: Int, fin: Bool) -> Bool {
        guard let lire, let ecrire, let ecran = ecranInterne else { return false }
        var actuel: Float = 0
        guard lire(ecran, &actuel) == 0 else { return false }
        let pas: Float = fin ? 1 / 64 : 1 / 16
        let v = max(0, min(1, ((actuel / pas).rounded() + Float(sens)) * pas))
        guard ecrire(ecran, v) == 0 else { return false }
        Ile.commun.montrerHud(.luminosite, niveau: Double(v))
        return true
    }
}
