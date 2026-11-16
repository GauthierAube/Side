// La hauteur du tiroir, et le relais quand une application se redimensionne elle-même.
// Partie de PanneauBas (PanneauBas.swift), rangée à part le 15/11/2026 sans changement.

import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

extension PanneauBas {
    // MARK: Hauteur du panneau (on tire son bord haut, comme pour la carte de Side)
    /// Le bouton a-t-il été enfoncé sur un bord gauche ou droit de cette fenêtre ? (Seul ce geste-là fait suivre le tiroir :
    /// un clic sur la barre, ou une fenêtre qui se pose après un changement d'application, ne doit rien déplacer.)
    func appuiSurUnBord(_ c: CGRect) -> Bool {
        let p = CGPoint(x: pointAppui.x, y: Ecrans.disposition.hauteurPrincipal - pointAppui.y)
        guard p.y > c.minY - 10, p.y < c.maxY + 10 else { return false }
        return abs(p.x - c.maxX) < 60 || abs(p.x - c.minX) < 60
    }
    func commencerEnDirect() -> Bool {
        guard uneApp, ouvert, enPlace, !sansFenêtres, !suiviDoigts, panneau != nil else { return false }
        selecteur.fermer()
        rangDirect = rangCourant
        enDirect = true
        return true
    }
    /// Pose la fenêtre de l'application affichée à sa place, pour le nouveau cadre du tiroir.
    func suivreEnDirect(_ fin: CGRect) {
        // Le défilement se compte en hauteurs de tiroir : la hauteur change, il est recalculé pour garder la même application.
        défilement = CGFloat(rangDirect) * (bande(fin).height + marge)
        for (e, zone) in entières(fin) {
            guard let f = fenetre(e) else { continue }
            // Deux réglages au lieu de trois, dans le bon ordre : la fenêtre ne saute pas à chaque mouvement.
            // Elle rapetisse : d'abord la taille, puis la place ; elle grandit : d'abord la place, puis la taille.
            var p = zone.origin, t = zone.size
            guard let vp = AXValueCreate(.cgPoint, &p), let vt = AXValueCreate(.cgSize, &t) else { continue }
            let avant = AXBas.cadre(f)
            let rapetisse = (avant?.height ?? 0) > zone.height || (avant?.width ?? 0) > zone.width
            if rapetisse {
                AXUIElementSetAttributeValue(f, kAXSizeAttribute as CFString, vt)
                AXUIElementSetAttributeValue(f, kAXPositionAttribute as CFString, vp)
            } else {
                AXUIElementSetAttributeValue(f, kAXPositionAttribute as CFString, vp)
                AXUIElementSetAttributeValue(f, kAXSizeAttribute as CFString, vt)
            }
        }
    }

    // MARK: Relais : l'application se redimensionne elle-même, le tiroir la suit
    func commencerRelais() {
        piluleDuGeste = false
        selecteur.fermer()
        rangDirect = rangCourant
        enDirect = true                 // la veille ne touche à rien pendant le geste
        journalBas("bord du tiroir : relayé à la fenêtre de l'application (côté %d)", PanneauBas.relaisCôté)
    }

    /// Le tiroir prend la taille qui va à la fenêtre, telle que l'application vient de la redimensionner.
    func suivreRelais() {
        guard enDirect, let p = panneau, let e = entières(p.frame).first?.0 ?? emprunts.indices.contains(rangDirect).then({ emprunts[rangDirect] }),
              let f = fenetre(e), let c = AXBas.cadre(f), let ecran = p.screen ?? NSScreen.main else { return }
        // L'application se laisse rendre plus petite que la taille minimum retenue pour elle (retenue un jour où elle
        // n'avait pas encore suivi) : on corrige, sinon le tiroir regrandissait une seconde après qu'on l'a lâché.
        if let m = hauteursMini[e.bundle], c.height < m - 2 { var t = hauteursMini; t[e.bundle] = c.height.rounded(.up); hauteursMini = t }
        if let m = largeursMini[e.bundle], c.width < m - 2 { var t = largeursMini; t[e.bundle] = c.width.rounded(.up); largeursMini = t }
        // La souris va plus loin que le bord de la fenêtre : l'application refuse d'être plus petite. On dit pourquoi.
        if !piluleDuGeste, let d = PanneauBas.relais {
            let haut = Ecrans.disposition.hauteurPrincipal
            let m = NSEvent.mouseLocation
            let cible = CGPoint(x: m.x + d.x, y: haut - m.y + d.y)
            let bloque: Bool
            switch PanneauBas.relaisCôté {
            case 0: bloque = enHaut ? cible.y < c.maxY - 30 : cible.y > c.minY + 30
            case 1: bloque = cible.x < c.maxX - 30
            default: bloque = cible.x > c.minX + 30
            }
            if bloque {
                piluleDuGeste = true
                direLimite(app: e.nom, hauteur: PanneauBas.relaisCôté == 0, points: PanneauBas.relaisCôté == 0 ? c.height : c.width)
            }
        }
        let haut = Ecrans.disposition.hauteurPrincipal
        let z = ecran.visibleFrame
        var g = panneauGlobal(p.frame)
        if PanneauBas.relaisCôté == 0 {
            // Le bord tourné vers le milieu de l'écran suit la fenêtre ; l'autre reste collé au bord de l'écran.
            if enHaut { g.size.height = max(200, c.maxY + marge - g.minY) }
            else { let bas = g.maxY; g.origin.y = c.minY - marge; g.size.height = max(200, bas - g.minY) }
        } else {
            g.origin.x = max(z.minX, c.minX - débutTuiles - marge)
            g.size.width = min(z.maxX - g.minX, c.width + débutTuiles + largeurColonne + 3 * marge)
        }
        let cadre = CGRect(x: g.minX, y: haut - g.maxY, width: g.width, height: g.height)
        guard abs(cadre.minX - p.frame.minX) > 0.5 || abs(cadre.width - p.frame.width) > 0.5
                || abs(cadre.minY - p.frame.minY) > 0.5 || abs(cadre.height - p.frame.height) > 0.5 else { return }
        p.setFrame(cadre, display: true)
        disposerLeFond(cadre)
        défilement = CGFloat(rangDirect) * (bande(cadre).height + marge)
    }

    /// Bouton relâché : le tiroir retient sa nouvelle taille, se recale (bornes, centrage) et la fenêtre avec lui.
    func finirRelais() {
        suivreRelais()
        guard let p = panneau, let ecran = p.screen ?? NSScreen.main else { enDirect = false; return }
        let z = ecran.visibleFrame
        if PanneauBas.relaisCôté == 0 { hauteurChoisie = p.frame.height }
        else { largeurChoisie = min(1, max(0.3, p.frame.width / z.width)) }
        let fin = cadre(ecran)
        if PanneauBas.relaisCôté == 0 { hauteurChoisie = fin.height }
        // L'application affichée se laissait rendre plus petite, mais une autre application du tiroir ne le permet pas :
        // le tiroir revient à la taille qu'elle impose. On dit laquelle (sinon on ne comprend pas pourquoi il regrandit).
        // Ce message passe avant celui du geste : c'est lui qui explique la taille finale.
        do {
            if PanneauBas.relaisCôté == 0, fin.height > p.frame.height + 10 {
                piluleDuGeste = true
                let laPlusHaute = emprunts.max { (hauteursMini[$0.bundle] ?? 0) < (hauteursMini[$1.bundle] ?? 0) }
                let parElle = laPlusHaute.flatMap { hauteursMini[$0.bundle] }.map { $0 + 2 * marge >= fin.height - 1 } ?? false
                direLimite(app: parElle ? laPlusHaute?.nom : nil, hauteur: true,
                           points: parElle ? (laPlusHaute.flatMap { hauteursMini[$0.bundle] } ?? fin.height) : fin.height)
            } else if PanneauBas.relaisCôté != 0, fin.width > p.frame.width + 10 {
                piluleDuGeste = true
                let laPlusLarge = emprunts.max { (largeursMini[$0.bundle] ?? 0) < (largeursMini[$1.bundle] ?? 0) }
                let parElle = laPlusLarge.flatMap { largeursMini[$0.bundle] } != nil
                direLimite(app: parElle ? laPlusLarge?.nom : nil, hauteur: false,
                           points: parElle ? (laPlusLarge.flatMap { largeursMini[$0.bundle] } ?? fin.width) : fin.width)
            }
        }
        let terminer = { [weak self] in
            guard let self else { return }
            self.disposerLeFond(fin)
            self.finirEnDirect()
        }
        if abs(fin.minX - p.frame.minX) > 1 || abs(fin.width - p.frame.width) > 1 || abs(fin.height - p.frame.height) > 1 {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                p.animator().setFrame(fin, display: true)
            }, completionHandler: terminer)
        } else { terminer() }
    }

    /// La pastille qui explique pourquoi le tiroir ne va pas plus loin.
    func direLimite(app: String?, hauteur: Bool, points: CGFloat) {
        let n = Int(points.rounded())
        let texte: String
        if let app {
            texte = hauteur ? String(localized: "« \(app) » ne peut pas être moins haute : le tiroir s'arrête à \(n) points")
                            : String(localized: "« \(app) » ne peut pas être moins large : le tiroir s'arrête à \(n) points")
        } else {
            texte = hauteur ? String(localized: "Le tiroir ne descend pas sous \(n) points de haut")
                            : String(localized: "Le tiroir ne se réduit pas sous \(n) points de large")
        }
        Pilule.montrer(texte, symbole: hauteur ? "arrow.up.and.down" : "arrow.left.and.right")
    }

    func commencerHauteur() {
        piluleDuGeste = false
        if commencerEnDirect() { hauteurAuDepart = panneau?.frame.height ?? 0; return }
        guard let p = panneau, commencerDéfilement() else { return }     // les tuiles deviennent des photos le temps du geste
        finDéfilement?.cancel()
        hauteurAuDepart = p.frame.height
    }

    func tirerHauteur(_ montée: CGFloat) {
        guard ouvert, défile || enDirect, let p = panneau, let ecran = p.screen ?? NSScreen.main else { return }
        hauteurChoisie = hauteurAuDepart + (enHaut ? -montée : montée)          // bornée par cadre() : un minimum, et presque tout l'écran au plus
        let voulue = hauteurChoisie
        let fin = cadre(ecran)
        hauteurChoisie = fin.height
        // On voudrait plus bas que le tiroir ne peut aller : on dit qui l'en empêche.
        if !piluleDuGeste, voulue < fin.height - 20, fin.height < (ecran.visibleFrame.height * 0.9) {
            piluleDuGeste = true
            let laPlusHaute = emprunts.max { (hauteursMini[$0.bundle] ?? 0) < (hauteursMini[$1.bundle] ?? 0) }
            let parElle = laPlusHaute.flatMap { hauteursMini[$0.bundle] }.map { $0 + 2 * marge >= fin.height - 1 } ?? false
            direLimite(app: parElle ? laPlusHaute?.nom : nil, hauteur: true, points: parElle ? (hauteursMini[laPlusHaute!.bundle] ?? fin.height) : fin.height)
        }
        p.setFrame(fin, display: true)
        disposerLeFond(fin)
        if enDirect { suivreEnDirect(fin); return }
        poser(1)
        déplacerImages(animé: false)                      // toutes les tuiles prennent la nouvelle hauteur, ensemble
    }

    /// Pendant qu'on élargit (ou rétrécit) la fenêtre de l'application affichée par son bord : le tiroir change de largeur
    /// avec elle, en direct. La barre d'icônes est poussée (ou ramenée) au lieu d'être recouverte.
    func suivreLaFenêtre(_ c: CGRect) {
        guard let p = panneau, let ecran = p.screen ?? NSScreen.main else { return }
        let z = ecran.visibleFrame
        let x = max(z.minX, c.minX - débutTuiles - marge)
        let l = min(z.maxX - x, max(min(largeurTiroirMini, z.width), c.width + débutTuiles + largeurColonne + 3 * marge))
        var f = p.frame
        guard abs(f.minX - x) > 0.5 || abs(f.width - l) > 0.5 else { return }
        f.origin.x = x; f.size.width = l
        p.setFrame(f, display: true)
        disposerLeFond(f)
    }

    /// Fenêtre lâchée : le tiroir retient sa nouvelle largeur et revient au centre de l'écran, d'un mouvement doux.
    func recentrerAprèsLaFenêtre() {
        guard let p = panneau, let ecran = p.screen ?? NSScreen.main else { return }
        let z = ecran.visibleFrame
        largeurChoisie = min(1, max(0.3, p.frame.width / z.width))
        let fin = cadre(ecran)
        journalBas("largeur du tiroir suivie depuis la fenêtre : %.0f", fin.width)
        guard abs(fin.minX - p.frame.minX) > 1 || abs(fin.width - p.frame.width) > 1 else { recaler(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            p.animator().setFrame(fin, display: true)
        }) { [weak self] in
            guard let self else { return }
            self.disposerLeFond(fin)
            self.recaler()
        }
    }

    func commencerLargeur() {
        piluleDuGeste = false
        if commencerEnDirect() { largeurAuDépart = panneau?.frame.width ?? 0; return }
        guard let p = panneau, commencerDéfilement() else { return }
        finDéfilement?.cancel()
        largeurAuDépart = p.frame.width
    }

    /// `écart` : le chemin fait par la souris depuis le début, vers l'intérieur du tiroir (positif = plus étroit).
    func tirerLargeur(_ écart: CGFloat) {
        guard ouvert, défile || enDirect, let p = panneau, let ecran = p.screen ?? NSScreen.main else { return }
        let z = ecran.visibleFrame
        let voulue = largeurAuDépart - 2 * écart
        largeurChoisie = min(1, max(0.3, voulue / z.width))     // les deux côtés bougent ensemble
        let fin = cadre(ecran)
        p.setFrame(fin, display: true)
        disposerLeFond(fin)
        if !piluleDuGeste, voulue < fin.width - 20 {
            piluleDuGeste = true
            let laPlusLarge = emprunts.max { (largeursMini[$0.bundle] ?? 0) < (largeursMini[$1.bundle] ?? 0) }
            direLimite(app: laPlusLarge.flatMap { largeursMini[$0.bundle] } != nil ? laPlusLarge?.nom : nil, hauteur: false, points: fin.width)
        }
        if enDirect { suivreEnDirect(fin); return }
        poser(1)
        déplacerImages(animé: false)
    }

    func finirLargeur() {
        if enDirect { finirEnDirect(); return }
        guard ouvert, défile else { return }
        journalBas("largeur du tiroir : %.0f", panneau?.frame.width ?? 0)
        défile = false
        panneau?.invalidateShadow()
        installer(déjàArrivé: true)
    }

    func finirEnDirect() {
        enDirect = false
        finDirectÀ = Date()
        refusHauteur = []
        journalBas("tiroir redimensionné en direct : %.0f × %.0f", panneau?.frame.width ?? 0, panneau?.frame.height ?? 0)
        panneau?.invalidateShadow()
        if let p = panneau { suivreEnDirect(p.frame) }
        stables = [:]; replacements = [:]; posées = []          // la fenêtre est revérifiée à sa nouvelle place
        // Une application occupée peut ignorer la demande : on vérifie un peu plus tard qu'elle a bien pris sa place.
        for délai in [0.15, 0.5, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + délai) { [weak self] in
                guard let self, self.ouvert, !self.enDirect, !self.défile, let p = self.panneau else { return }
                for (e, zone) in self.entières(p.frame) {
                    guard let f = self.fenetre(e), let c = AXBas.cadre(f) else { journalBas("après redimensionnement : fenêtre de %@ introuvable", e.nom); continue }
                    if abs(c.height - zone.height) > 3 || abs(c.width - zone.width) > 3 || abs(c.minY - zone.minY) > 3 {
                        journalBas("après redimensionnement : %@ est en %.0f × %.0f au lieu de %.0f × %.0f, replacée", e.nom, c.width, c.height, zone.width, zone.height)
                        AXBas.placer(f, zone)
                    }
                }
            }
        }
    }

    func finirHauteur() {
        if enDirect { finirEnDirect(); return }
        guard ouvert, défile else { return }
        journalBas("hauteur du panneau : %.0f", panneau?.frame.height ?? 0)
        refusHauteur = []
        défile = false
        panneau?.invalidateShadow()
        installer(déjàArrivé: true)
    }
}
