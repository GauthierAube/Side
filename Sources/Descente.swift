// Le Finder et les applications qui descendent de l'encoche (17/11/2026), comme une application qui s'ouvre depuis la
// Dynamic Island de l'iPhone : une forme noire part de l'encoche, s'étire avec un ressort jusqu'à la place de la fenêtre
// (l'icône grandit en son centre), puis se dissout et laisse voir la fenêtre arrivée dessous.
import AppKit
import SwiftUI

final class Descente: ObservableObject {
    static let commun = Descente()

    /// La forme, en coordonnées de la vue (origine en haut à gauche de l'écran).
    @Published fileprivate var cadre: CGRect = .zero
    @Published fileprivate var rayonHaut: CGFloat = 0
    @Published fileprivate var rayonBas: CGFloat = 10
    @Published fileprivate var opacite: Double = 1
    @Published fileprivate var icone: NSImage?
    @Published fileprivate var echelleIcone: CGFloat = 0.3

    private var panneau: NSPanel?
    private var tour = 0
    /// Le temps que met la forme à atteindre sa place, avant de se dissoudre.
    static let arrivee: Double = 0.38

    // MARK: Le Finder

    /// Ouvre (ou referme) le Finder de Side en le faisant descendre de l'encoche.
    static func finder() {
        let a = AppDelegate.shared
        if a.visible { a.hide(); return }
        guard let e = Ile.commun.ecran else { return }
        Ile.commun.fermer()
        a.show(sur: e, encoche: true)
    }

    /// Appelé par la carte quand elle s'ouvre depuis l'encoche : elle est en place mais encore invisible.
    static func versCarte(_ cible: NSRect, sur e: NSScreen) {
        commun.jouer(vers: cible, rayon: Rayon.fenetre, icone: NSWorkspace.shared.icon(for: .folder), sur: e)
    }

    // MARK: Les applications

    static func application(_ bundle: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        let c = NSWorkspace.OpenConfiguration()
        c.activates = true
        if let e = Ile.commun.ecran {
            Ile.commun.fermer()
            let cible = cadreFenetre(bundle, sur: e) ?? e.visibleFrame.insetBy(dx: e.visibleFrame.width * 0.14,
                                                                              dy: e.visibleFrame.height * 0.12)
            commun.jouer(vers: cible, rayon: Rayon.carte, icone: NSWorkspace.shared.icon(forFile: url.path), sur: e)
        }
        NSWorkspace.shared.openApplication(at: url, configuration: c)
    }

    /// La fenêtre de premier plan de l'application, si elle est ouverte sur cet écran.
    private static func cadreFenetre(_ bundle: String, sur e: NSScreen) -> NSRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return nil }
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for i in infos {      // de la plus en avant à la plus en arrière
            guard (i[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (i[kCGWindowLayer as String] as? Int) == 0,
                  let b = i[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b), r.width > 200, r.height > 150 else { continue }
            let ns = Ecrans.versNS(r)
            if e.frame.intersects(ns) { return ns }
        }
        return nil
    }

    // MARK: L'animation

    private func jouer(vers cible: NSRect, rayon: CGFloat, icone: NSImage?, sur e: NSScreen) {
        let f = e.frame
        let p = panneau ?? creerPanneau()
        p.setFrame(f, display: false)
        tour += 1
        let ce = tour
        func vue(_ r: NSRect) -> CGRect { CGRect(x: r.minX - f.minX, y: f.maxY - r.maxY, width: r.width, height: r.height) }
        let depart = Ile.commun.cadreEncoche
        var sans = Transaction()
        sans.disablesAnimations = true
        withTransaction(sans) {
            cadre = vue(depart); rayonHaut = 0; rayonBas = 10; opacite = 1
            self.icone = icone; echelleIcone = 0.3
        }
        p.orderFrontRegardless()
        DispatchQueue.main.async { [self] in
            guard tour == ce else { return }
            withAnimation(Mouvement.descente) {
                cadre = vue(cible); rayonHaut = rayon; rayonBas = rayon; echelleIcone = 1
            }
        }
        // La forme se dissout pendant que la fenêtre apparaît dessous : un fondu enchaîné.
        DispatchQueue.main.asyncAfter(deadline: .now() + Mouvement.duree(Descente.arrivee)) { [self] in
            guard tour == ce else { return }
            withAnimation(.easeOut(duration: Mouvement.duree(0.26))) { opacite = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in if tour == ce { p.orderOut(nil) } }
        }
    }

    private func creerPanneau() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.animationBehavior = .none
        p.contentView = NSHostingView(rootView: VueDescente())
        panneau = p
        return p
    }
}

private struct VueDescente: View {
    @ObservedObject private var d = Descente.commun
    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                UnevenRoundedRectangle(topLeadingRadius: d.rayonHaut, bottomLeadingRadius: d.rayonBas,
                                       bottomTrailingRadius: d.rayonBas, topTrailingRadius: d.rayonHaut, style: .continuous)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                if let i = d.icone {
                    Image(nsImage: i).resizable().frame(width: 76, height: 76).scaleEffect(d.echelleIcone)
                }
            }
            .frame(width: d.cadre.width, height: d.cadre.height)
            .offset(x: d.cadre.minX, y: d.cadre.minY)
            .opacity(d.opacite)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
