// Le collage en cascade (17/11/2026) : ⌘V colle le dernier copié, comme toujours ; ⌘ gardé enfoncé et V de nouveau
// ouvre une petite fenêtre des 5 derniers copiés, sur l'avant-dernier ; chaque V descend d'un cran (après le 5ᵉ, retour
// au 1ᵉʳ) ; lâcher ⌘ colle l'élément choisi ; Échap referme sans rien coller.
// Le premier ⌘V est retenu jusqu'au lâcher de ⌘ : ainsi rien n'est jamais collé deux fois (design :
// docs/superpowers/specs/2026-11-16-collage-en-cascade-design.md).
import AppKit
import SwiftUI

/// Ce que le filtre clavier transmet à la cascade.
enum ToucheCascade {
    case commandeV(repetition: Bool)   // ⌘V « nu » (sans ⇧, ⌥ ni ⌃)
    case echap
    case autreTouche                   // n'importe quelle autre touche
    case commandeLachee
}

final class CollageCascade: ObservableObject {
    static let commun = CollageCascade()

    /// Nombre d'éléments proposés.
    static let nombre = 5
    /// Au-delà, ⌘ resté enfoncé sans rien faire : on colle quand même (jamais de collage perdu).
    static let delaiSecurite: TimeInterval = 10

    /// Les éléments montrés dans la fenêtre (vide : fenêtre fermée).
    @Published fileprivate(set) var elements: [Copie] = []
    @Published fileprivate(set) var choix = 0
    /// Un ⌘V attend le lâcher de ⌘.
    private(set) var retenu = false
    var ouvert: Bool { !elements.isEmpty }

    /// Colle : `nil` = ce qui est déjà dans le presse-papiers (le ⌘V ordinaire), sinon cet élément.
    /// Remplacé par les essais (`--test-cascade`) pour ne rien coller pour de vrai.
    var coller: (Copie?) -> Void = { CollageCascade.collerPourDeVrai($0) }
    /// Où lire l'historique (remplacé par les essais).
    var historique: () -> [Copie] = {
        PressePapiers.shared.verifier()   // une copie faite il y a moins d'une demi-seconde n'est peut-être pas encore notée
        return PressePapiers.shared.elements
    }
    private var minuteur: Timer?

    /// Reçoit une touche ; rend `true` si elle doit être bloquée (ne pas arriver à l'application).
    func recevoir(_ t: ToucheCascade) -> Bool {
        switch t {
        case .commandeV(let repetition):
            if repetition { return retenu }   // V maintenu : on ne défile pas à toute vitesse
            if !retenu {
                retenu = true
                choix = 0
                armerSecurite()
                return true
            }
            if !ouvert {
                journalBas("collage en cascade : second V, fenêtre ouverte")
                let liste = Array(historique().sorted { $0.date > $1.date }.prefix(Self.nombre))
                guard liste.count >= 2 else { return true }   // rien d'autre à proposer : le ⌘V reste retenu
                elements = liste
                choix = 1
                if self === Self.commun { FenetreCascade.montrer() }
            } else {
                choix = (choix + 1) % elements.count
            }
            armerSecurite()
            return true
        case .echap:
            guard retenu else { return false }
            finir(coller: false)
            return true
        case .autreTouche:
            // ⌘V puis ⌘C sans lâcher ⌘ : le collage retenu part d'abord, la touche suit.
            if retenu { finir(coller: true) }
            return false
        case .commandeLachee:
            if retenu { finir(coller: true) }
            return false
        }
    }

    private func finir(coller doitColler: Bool) {
        // Le 1ᵉʳ de la liste est déjà dans le presse-papiers : un ⌘V ordinaire suffit.
        let element = ouvert && choix > 0 ? elements[choix] : nil
        retenu = false
        minuteur?.invalidate(); minuteur = nil
        if ouvert { elements = []; if self === Self.commun { FenetreCascade.cacher() } }
        guard doitColler else { return }
        coller(element)
    }

    private func armerSecurite() {
        minuteur?.invalidate()
        minuteur = Timer.scheduledTimer(withTimeInterval: Self.delaiSecurite, repeats: false) { [weak self] _ in
            self?.finir(coller: true)
        }
    }

    // MARK: Clavier

    /// Marque posée sur les ⌘V envoyés par Side, pour que le filtre les laisse passer.
    private static let marque: Int64 = 0x5349_4445_4356   // « SIDECV »
    private static let toucheV: Int64 = 9                 // la touche V (même place en AZERTY et en QWERTY)
    private static let toucheEchap: Int64 = 53
    private static var filtre: CFMachPort?

    /// Branche le filtre clavier (une fois, au lancement). Sans l'autorisation Accessibilité, ⌘V reste celui de macOS.
    static func demarrer() {
        guard filtre == nil else { return }
        let masque = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        filtre = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                   eventsOfInterest: masque, callback: { _, type, ev, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let f = CollageCascade.filtre { CGEvent.tapEnable(tap: f, enable: true) }
                return Unmanaged.passUnretained(ev)
            }
            guard ev.getIntegerValueField(.eventSourceUserData) != CollageCascade.marque,
                  let touche = CollageCascade.traduire(type, ev) else { return Unmanaged.passUnretained(ev) }
            return CollageCascade.commun.recevoir(touche) ? nil : Unmanaged.passUnretained(ev)
        }, userInfo: nil)
        journalBas("collage en cascade : filtre clavier %@", filtre == nil ? "REFUSÉ (autorisation Accessibilité ?)" : "actif")
        guard let filtre else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, filtre, 0), .commonModes)
        CGEvent.tapEnable(tap: filtre, enable: true)
    }

    /// Ce que l'évènement veut dire pour la cascade (`nil` : rien, il passe tel quel).
    private static func traduire(_ type: CGEventType, _ ev: CGEvent) -> ToucheCascade? {
        let c = Config.shared
        let actif = c.collageCascade && c.historique
        if type == .flagsChanged {
            return commun.retenu && !ev.flags.contains(.maskCommand) ? .commandeLachee : nil
        }
        guard type == .keyDown else { return nil }
        let code = ev.getIntegerValueField(.keyboardEventKeycode)
        let f = ev.flags
        let commandeSeule = f.contains(.maskCommand) && f.isDisjoint(with: [.maskShift, .maskAlternate, .maskControl])
        if code == toucheV && commandeSeule && (actif || commun.retenu) {
            return .commandeV(repetition: ev.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        }
        guard commun.retenu else { return nil }
        return code == toucheEchap ? .echap : .autreTouche
    }

    /// Met l'élément choisi dans le presse-papiers (s'il y en a un), puis envoie un ⌘V ordinaire à l'application.
    static func collerPourDeVrai(_ element: Copie?) {
        if let element { PressePapiers.shared.recopier(element) }
        // Juste après : le lâcher de ⌘ arrive d'abord à l'application.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            let source = CGEventSource(stateID: .combinedSessionState)
            for appui in [true, false] {
                guard let ev = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(toucheV), keyDown: appui) else { continue }
                ev.flags = .maskCommand
                ev.setIntegerValueField(.eventSourceUserData, value: marque)
                ev.post(tap: .cgSessionEventTap)
            }
        }
    }

    // MARK: Essais

    /// `Side --test-cascade` : rejoue des suites de touches sans clavier ni collage réels, et affiche ce qui serait collé.
    static func essais() {
        let c = CollageCascade()
        let maintenant = Date()
        let histo = (0..<7).map { Copie(date: maintenant.addingTimeInterval(Double(-$0 * 60)), texte: "copie \($0 + 1)") }
        c.historique = { histo }
        var colle: [String] = []
        c.coller = { colle.append($0?.texte ?? "(dernier copié)") }
        func suite(_ nom: String, _ touches: [ToucheCascade]) {
            colle = []
            let bloquees = touches.map { c.recevoir($0) }
            print(nom.padding(toLength: 34, withPad: " ", startingAt: 0), "→ collé :", colle, "| bloquées :", bloquees.map { $0 ? "o" : "-" }.joined(),
                  "| fenêtre ouverte après :", c.ouvert)
        }
        let v = ToucheCascade.commandeV(repetition: false)
        suite("⌘V puis lâcher", [v, .commandeLachee])
        suite("⌘V V puis lâcher", [v, v, .commandeLachee])
        suite("⌘V V V puis lâcher", [v, v, v, .commandeLachee])
        suite("⌘V ×5 (5ᵉ copié)", [v, v, v, v, v, .commandeLachee])
        suite("⌘V ×6 (revient au 1ᵉʳ)", [v, v, v, v, v, v, .commandeLachee])
        suite("⌘V V Échap", [v, v, .echap, .commandeLachee])
        suite("⌘V puis ⌘C (sans lâcher)", [v, .autreTouche, .commandeLachee])
        suite("⌘V V + V maintenu", [v, v, .commandeV(repetition: true), .commandeLachee])
        suite("lâcher ⌘ sans ⌘V", [.commandeLachee])
        exit(0)
    }

    /// Dessine la fenêtre (sur le 3ᵉ élément) dans une image, avec un historique d'exemple.
    static func imageEssai(vers sortie: URL) {
        let c = CollageCascade.commun
        let d = Date()
        c.elements = [
            Copie(date: d, texte: "Bonjour, merci pour votre message, je reviens vers vous demain."),
            Copie(date: d.addingTimeInterval(-60), texte: "https://github.com/GauthierAube/Side"),
            Copie(date: d.addingTimeInterval(-120), fichiers: [URL(fileURLWithPath: "/Applications/Safari.app")]),
            Copie(date: d.addingTimeInterval(-180), texte: "motdepasse", secret: true),
            Copie(date: d.addingTimeInterval(-240), texte: "FR76 0000 0000 0000 0000 0000 000"),
        ]
        c.choix = 2
        let vue = NSHostingView(rootView: VueCascade(modele: c))
        vue.frame = NSRect(origin: .zero, size: vue.fittingSize)
        let w = NSWindow(contentRect: vue.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = vue
        vue.layoutSubtreeIfNeeded()
        if let rep = vue.bitmapImageRepForCachingDisplay(in: vue.bounds) {
            vue.cacheDisplay(in: vue.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: sortie)
        }
    }
}

/// La petite fenêtre des derniers copiés, au centre de l'écran de la souris. Elle ne prend pas le clavier :
/// l'application où l'on écrit reste active.
enum FenetreCascade {
    private static var panneau: NSPanel?

    static func montrer() {
        guard let ecran = Ecrans.deTravail else { return }
        let p = panneau ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.hidesOnDeactivate = false
            p.ignoresMouseEvents = true
            p.contentView = NSHostingView(rootView: VueCascade(modele: CollageCascade.commun))
            return p
        }()
        panneau = p
        let taille = p.contentView?.fittingSize ?? NSSize(width: 440, height: 300)
        let v = ecran.visibleFrame
        p.setFrame(NSRect(x: (v.midX - taille.width / 2).rounded(), y: (v.midY - taille.height / 2).rounded(),
                          width: taille.width, height: taille.height), display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()
    }

    static func cacher() { panneau?.orderOut(nil) }
}

struct VueCascade: View {
    @ObservedObject var modele: CollageCascade

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(modele.elements.enumerated()), id: \.element.id) { rang, copie in
                LigneCascade(copie: copie, rang: rang, choisi: rang == modele.choix)
            }
            Text("V : suivant · lâcher ⌘ : coller · Échap : annuler")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
        .padding(8)
        .frame(width: 440)
        .background(ZStack {
            VisualEffect()
            Color(nsColor: .windowBackgroundColor).opacity(0.6)
        })
        .clipShape(RoundedRectangle(cornerRadius: Rayon.panneau, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Rayon.panneau, style: .continuous).strokeBorder(Gris.filet, lineWidth: 1))
        .animation(Mouvement.survol, value: modele.choix)
    }
}

private struct LigneCascade: View {
    let copie: Copie
    let rang: Int
    let choisi: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rang + 1)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(choisi ? Color.white.opacity(0.85) : Color.secondary)
                .frame(width: 14)
            vignette.frame(width: 28, height: 28)
            Text(resume)
                .font(.system(size: 13))
                .foregroundStyle(choisi ? Color.white : Color.primary)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Rayon.encadre, style: .continuous).fill(choisi ? Selection.bleu : .clear))
    }

    @ViewBuilder private var vignette: some View {
        if let image = copie.image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: Rayon.puce))
        } else if let f = copie.fichiers.first {
            Image(nsImage: Icones.petite(f.path)).resizable()
        } else {
            Image(systemName: copie.secret ? "key.fill" : "doc.text")
                .font(.system(size: 15))
                .foregroundStyle(choisi ? Color.white : Color.secondary)
        }
    }

    private var resume: String {
        if copie.secret { return "••••••••" }
        if !copie.fichiers.isEmpty {
            let noms = copie.fichiers.map { FileManager.default.displayName(atPath: $0.path) }
            return noms.count == 1 ? noms[0] : "\(noms[0]) + \(noms.count - 1)"
        }
        if copie.image != nil { return String(localized: "Image") }
        return (copie.texte ?? "").split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}
