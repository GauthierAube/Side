// La pastille de notification (14/11/2026), sur le modèle de celle d'Horizon : une pilule brune en bas de l'écran, texte
// blanc en gras, icône à gauche, petite croix ronde à droite. Elle monte avec un léger rebond, reste trois secondes et
// redescend en s'effaçant. Une seule à la fois ; le même message n'est pas répété tant qu'il est affiché.
import AppKit
import SwiftUI

enum Pilule {
    private static var panneau: NSPanel?
    private static var depart: Timer?
    private static var messageAffiche: String?
    static let encre = Color(red: 0x39 / 255, green: 0x29 / 255, blue: 0x1D / 255)

    private struct Vue: View {
        let message: String
        let symbole: String
        let couleur: Color
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: symbole).font(.system(size: 16, weight: .semibold)).foregroundStyle(couleur)
                Text(message).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Button { Pilule.cacher() } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                        .frame(width: 20, height: 20).background(Circle().fill(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Fermer")
            }
            .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 9)
            .background(Capsule().fill(Pilule.encre))
            .shadow(color: .black.opacity(0.25), radius: 12, y: -5)
            .padding(16)          // la place de l'ombre
            .fixedSize()
        }
    }

    /// Affiche `message` en bas de l'écran (celui de la souris).
    static func montrer(_ message: String, symbole: String = "info.circle.fill", couleur: Color = Color(red: 0.94, green: 0.60, blue: 0.47)) {
        if messageAffiche == message, panneau?.isVisible == true { relancer(); return }
        guard let ecran = Ecrans.deTravail else { return }
        let p = panneau ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.hidesOnDeactivate = false
            p.animationBehavior = .none
            return p
        }()
        panneau = p
        messageAffiche = message
        let vue = NSHostingView(rootView: Vue(message: message, symbole: symbole, couleur: couleur))
        let taille = vue.fittingSize
        p.contentView = vue
        let v = ecran.visibleFrame
        let arrivee = NSRect(x: (v.midX - taille.width / 2).rounded(), y: v.minY + 12, width: taille.width, height: taille.height)
        // Elle part de sous le bord de l'écran et monte avec un léger rebond.
        p.setFrame(arrivee.offsetBy(dx: 0, dy: -taille.height - 20), display: false)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.4, 0.64, 1)
            p.animator().setFrame(arrivee, display: true)
            p.animator().alphaValue = 1
        }
        relancer()
    }

    private static func relancer() {
        depart?.invalidate()
        depart = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: false) { _ in cacher() }
    }

    /// Elle redescend en s'effaçant.
    static func cacher() {
        depart?.invalidate(); depart = nil
        guard let p = panneau, p.isVisible else { return }
        let fin = p.frame.offsetBy(dx: 0, dy: -p.frame.height - 20)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrame(fin, display: true)
            p.animator().alphaValue = 0
        }) {
            p.orderOut(nil)
            messageAffiche = nil
        }
    }
}
