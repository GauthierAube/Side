// Le lecteur YouTube du tiroir est Peinard, l'app iPhone de Gauthier, dans sa version Mac (15/11/2026).
// Le code de Peinard vit dans son propre dépôt (~/Github/sans-pub) : build.sh le compile en une brique « Peinard »
// quand ce dossier est présent. Sans lui (version publique de Side), le tiroir garde son ancien lecteur YouTube.
import AppKit
import SwiftUI
#if canImport(Peinard)
import Peinard
#endif

enum TuilePeinard {
    /// Vrai quand Side a été compilé avec Peinard.
    static var disponible: Bool {
        #if canImport(Peinard)
        true
        #else
        false
        #endif
    }

    /// La vidéo de Peinard sort en grand : le tiroir se referme, comme avec l'ancien lecteur.
    private static var suivi: NSObjectProtocol?
    private static func suivreLaVideo() {
        guard suivi == nil else { return }
        suivi = NotificationCenter.default.addObserver(forName: Notification.Name("PeinardVideoEnGrand"), object: nil, queue: .main) { note in
            if (note.object as? Bool) == true { PanneauBas.commun.fermerPourLaVideo() }
        }
    }

    /// Une nouvelle tuile Peinard, ou rien si Side a été compilé sans Peinard.
    /// (Le tiroir appelle ces fonctions sur le fil principal : Peinard, écrit en Swift 6, veut qu'on le lui dise.)
    static func creer() -> NSView? {
        #if canImport(Peinard)
        suivreLaVideo()
        return MainActor.assumeIsolated {
            let tuile = CadrePeinard()
            let vue = NSHostingView(rootView: PeinardVue())
            vue.frame = tuile.bounds
            vue.autoresizingMask = [.width, .height]
            tuile.addSubview(vue)
            return tuile
        }
        #else
        return nil
        #endif
    }

    /// Ouvre un lien YouTube dans Peinard.
    static func ouvrir(_ url: URL) {
        #if canImport(Peinard)
        MainActor.assumeIsolated { PeinardVue.ouvrir(url) }
        #endif
    }

    /// Met les vidéos de Peinard en pause (minuteur de sommeil, tuile retirée).
    static func mettreEnPause() {
        #if canImport(Peinard)
        MainActor.assumeIsolated { PeinardVue.mettreEnPause() }
        #endif
    }
}

/// Le cadre de la tuile : mêmes coins arrondis et même bordure que les autres tuiles du tiroir, en sombre.
final class CadrePeinard: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Rayon.tuile
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor
        layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        appearance = NSAppearance(named: .darkAqua)       // comme l'ancien lecteur et la tuile Spotify
    }
    required init?(coder: NSCoder) { fatalError() }
}
