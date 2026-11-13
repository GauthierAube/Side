// La présentation de Square, à la première ouverture : six écrans, presque sans mots. Chacun montre le geste en mouvement
// sur un petit écran dessiné, avec en dessous le ou les déclencheurs sous forme de pastilles.
import AppKit
import SwiftUI

// MARK: - Outils de dessin

/// Avancement entre deux instants d'une boucle (0 avant `a`, 1 après `b`), avec un départ et une arrivée en douceur.
private func tranche(_ t: Double, _ a: Double, _ b: Double) -> CGFloat {
    let x = min(max((t - a) / (b - a), 0), 1)
    return CGFloat(x * x * (3 - 2 * x))
}

private func melange(_ a: CGRect, _ b: CGRect, _ p: CGFloat) -> CGRect {
    CGRect(x: a.minX + (b.minX - a.minX) * p, y: a.minY + (b.minY - a.minY) * p,
           width: a.width + (b.width - a.width) * p, height: a.height + (b.height - a.height) * p)
}

private func melange(_ a: CGPoint, _ b: CGPoint, _ p: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
}

/// Le petit écran dessiné : 420 × 262 points.
private enum Ecran {
    static let taille = CGSize(width: 420, height: 262)
    static let barre: CGFloat = 11                                   // la barre des menus
    static let plein = CGRect(x: 0, y: barre, width: 420, height: 262 - barre)
    static let couleurs: [Color] = [Color(red: 0.36, green: 0.56, blue: 0.96), Color(red: 0.95, green: 0.55, blue: 0.33),
                                    Color(red: 0.36, green: 0.78, blue: 0.56), Color(red: 0.66, green: 0.48, blue: 0.93),
                                    Color(red: 0.93, green: 0.42, blue: 0.56), Color(red: 0.30, green: 0.74, blue: 0.80)]
    /// Les quatre cases de la grille (deux en haut, deux en bas), dans une zone donnée.
    static func cases(dans zone: CGRect = CGRect(x: 0, y: barre, width: 420, height: 262 - barre)) -> [CGRect] {
        let l = min(zone.width * 0.36, zone.height * 0.40 * 1.6), h = l / 1.6, ex = zone.width * 0.07, ey = zone.height * 0.09
        let x0 = zone.midX - l - ex / 2, y0 = zone.midY - h - ey / 2
        return [CGRect(x: x0, y: y0, width: l, height: h), CGRect(x: x0 + l + ex, y: y0, width: l, height: h),
                CGRect(x: x0, y: y0 + h + ey, width: l, height: h), CGRect(x: x0 + l + ex, y: y0 + h + ey, width: l, height: h)]
    }
}

/// Une fenêtre dessinée : un rectangle de couleur avec sa barre de titre.
private struct Fenetrette: View {
    let cadre: CGRect
    let couleur: Color
    var opacite: Double = 1
    var contour = false
    var feux = false                 // les trois boutons rouge, jaune, vert, en grand

    var body: some View {
        let rayon = min(8, cadre.height * 0.09)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: rayon, style: .continuous).fill(couleur.gradient)
            RoundedRectangle(cornerRadius: rayon, style: .continuous).fill(Color.white.opacity(0.92))
                .padding(.top, max(6, cadre.height * 0.16)).padding([.horizontal, .bottom], 2.5)
            if feux {
                HStack(spacing: 4) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
                }
                .frame(width: 32, height: 8).padding(.leading, 6).padding(.top, 4)
            }
            if contour {
                RoundedRectangle(cornerRadius: rayon, style: .continuous).strokeBorder(Color(nsColor: orange), lineWidth: 3)
            }
        }
        .frame(width: max(cadre.width, 1), height: max(cadre.height, 1))
        .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
        .opacity(opacite)
        .position(x: cadre.midX, y: cadre.midY)
    }
}

/// Le pointeur de la souris.
private struct Pointeur: View {
    let en: CGPoint
    var clic: CGFloat = 0            // 0 à 1 : une onde part du pointeur
    var body: some View {
        ZStack {
            Circle().stroke(Color.white, lineWidth: 2).frame(width: 10 + 26 * clic, height: 10 + 26 * clic)
                .opacity(clic > 0 && clic < 1 ? Double(1 - clic) : 0)
            Image(systemName: "cursorarrow").font(.system(size: 22, weight: .regular)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 1.5, y: 1)
                .offset(x: 6, y: 9)
        }
        .position(en)
    }
}

/// Le fond du petit écran : un fond d'écran flou, et la barre des menus.
private struct FondEcran: View {
    var sombre: CGFloat = 0          // 0 : le bureau ; 1 : le fond flou et assombri de la grille
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.55, green: 0.36, blue: 0.62), Color(red: 0.20, green: 0.28, blue: 0.56),
                                    Color(red: 0.10, green: 0.13, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Color.black.opacity(0.30 * Double(sombre))
            Rectangle().fill(Color.white.opacity(0.22)).frame(height: Ecran.barre)
        }
    }
}

// MARK: - Les six scènes

/// Dessine la scène d'une étape à l'instant `t` de sa boucle (0 à 1).
struct SceneAccueil: View {
    let etape: Int
    let t: Double

    /// Seulement le petit écran, sans cadre ni trackpad : la présentation de Side l'encadre elle-même.
    var nu = false
    /// La scène ne revient pas à son point de départ : elle s'enchaîne avec la suivante dans la même boucle.
    var sansRetour = false

    @ViewBuilder private var ecran: some View {
        switch etape {
        case 0: grille
        case 1: choisir
        case 2: quatreDoigts
        case 3: ranger
        case 4: dock
        case 10: troisPlaces
        case 11: tiroirDefile
        case 12: changerDAvis
        default: boutonVert
        }
    }

    var body: some View {
        if nu { ZStack { ecran }.frame(width: Ecran.taille.width, height: Ecran.taille.height) } else { avecCadre }
    }

    private var avecCadre: some View {
        VStack(spacing: 12) {
            ZStack { ecran }
            .frame(width: Ecran.taille.width, height: Ecran.taille.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.25), lineWidth: 1.5))
            // Sous l'écran : le trackpad, pour l'étape des quatre doigts (une place vide ailleurs, pour que rien ne bouge).
            trackpad.frame(height: 62).opacity(etape == 2 ? 1 : 0)
        }
    }

    /// 1. Le pointeur file dans le coin : la fenêtre rétrécit, les autres apparaissent en grille.
    private var grille: some View {
        let c = Ecran.cases()
        let k = tranche(t, 0.30, 0.52) - (sansRetour ? 0 : tranche(t, 0.86, 0.97))
        let coin = CoinGrille.choix
        let cible = CGPoint(x: coin.hasSuffix("g") ? 3 : 417, y: coin.hasPrefix("b") ? 259 : 3)
        let p = melange(CGPoint(x: 230, y: 160), cible, tranche(t, 0.06, 0.30))
        return ZStack {
            FondEcran(sombre: k)
            ForEach(1..<4, id: \.self) { i in
                Fenetrette(cadre: c[i].insetBy(dx: c[i].width * 0.07 * (1 - k), dy: c[i].height * 0.07 * (1 - k)),
                           couleur: Ecran.couleurs[i], opacite: Double(k))
            }
            Fenetrette(cadre: melange(Ecran.plein, c[0], k), couleur: Ecran.couleurs[0])
            Pointeur(en: p, clic: 0)
        }
    }

    /// 2. Dans la grille : on vise une fenêtre, un clic, elle reprend tout l'écran.
    private var choisir: some View {
        let c = Ecran.cases()
        let k = tranche(t, 0.46, 0.64) - (sansRetour ? 0 : tranche(t, 0.88, 0.98))
        let p = melange(CGPoint(x: 330, y: 236), CGPoint(x: c[2].midX, y: c[2].midY), tranche(t, 0.08, 0.32))
        return ZStack {
            FondEcran(sombre: 1 - k)
            ForEach([0, 1, 3], id: \.self) { i in Fenetrette(cadre: c[i], couleur: Ecran.couleurs[i], opacite: Double(1 - k)) }
            Fenetrette(cadre: melange(c[2], Ecran.plein, k), couleur: Ecran.couleurs[2], contour: t > 0.30 && k < 0.05)
            Pointeur(en: p, clic: tranche(t, 0.38, 0.50)).opacity(sansRetour ? Double(1 - tranche(t, 0.64, 0.72)) : 1)
            // Fin de la boucle : fondu vers l'application du début, pour que la boucle reparte sans saut.
            if sansRetour { Fenetrette(cadre: Ecran.plein, couleur: Ecran.couleurs[0], opacite: Double(tranche(t, 0.90, 1.0))) }
        }
    }

    /// 3. Quatre doigts glissent : les cartes défilent, celle du centre grandit ; doigts levés, elle passe devant.
    private var quatreDoigts: some View {
        let apparition = tranche(t, 0.10, 0.18) - tranche(t, 0.52, 0.60)
        let pos = 0.0 + 1.0 * Double(tranche(t, 0.14, 0.50))                 // de la carte 0 à la carte 1
        let zoom = tranche(t, 0.54, 0.70)                                   // la carte choisie grandit, et reste
        let grande = CGSize(width: 150, height: 94), petit: CGFloat = 0.55
        let centre = CGPoint(x: 210, y: 136)
        return ZStack {
            FondEcran()
            Fenetrette(cadre: Ecran.plein, couleur: Ecran.couleurs[0])
            Color.black.opacity(0.3 * Double(apparition))
            ForEach(0..<4, id: \.self) { i in
                let d = CGFloat(Double(i) - pos), proche = 1 - min(abs(d), 1)
                let s = petit + (1 - petit) * proche
                let x = centre.x + d * (grande.width * petit + 14) + (d > 0 ? 1 : (d < 0 ? -1 : 0)) * min(abs(d), 1) * grande.width * (1 - petit) / 2
                Fenetrette(cadre: CGRect(x: x - grande.width * s / 2, y: centre.y - grande.height * s / 2,
                                         width: grande.width * s, height: grande.height * s),
                           couleur: Ecran.couleurs[i], opacite: Double(apparition) * Double(0.6 + 0.4 * proche), contour: proche > 0.5)
            }
            // Doigts levés : la carte du centre devient la fenêtre de devant.
            Fenetrette(cadre: melange(CGRect(x: centre.x - 75, y: centre.y - 47, width: 150, height: 94), Ecran.plein, zoom),
                       couleur: Ecran.couleurs[1], opacite: zoom > 0.01 ? Double(1 - tranche(t, 0.92, 1.0)) : 0)   // fondu : la boucle repart
        }
    }

    /// Le trackpad, sous l'écran : quatre doigts qui glissent vers la gauche puis se lèvent.
    private var trackpad: some View {
        let glisse = tranche(t, 0.12, 0.50), poses = tranche(t, 0.04, 0.10) - tranche(t, 0.52, 0.58)
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.10))
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
            HStack(spacing: 7) {
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(Color(nsColor: orange)).frame(width: 13, height: 13).offset(y: [3, -3, -4, 2][i])
                }
            }
            .offset(x: 26 - 52 * glisse)
            .opacity(Double(poses))
        }
        .frame(width: 150)
    }

    /// 4. Ranger : glisser une fenêtre sur le milieu d'une autre la met à sa place ; sur un bord, elles partagent l'écran.
    private var ranger: some View {
        let c = Ecran.cases()
        // Première moitié : la fenêtre 3 va prendre la place de la fenêtre 0, les autres se poussent d'un cran.
        let tenue1 = tranche(t, 0.06, 0.10) - tranche(t, 0.36, 0.40)
        let trajet1 = tranche(t, 0.10, 0.28)
        let pousse = tranche(t, 0.24, 0.36)
        // Seconde moitié : la fenêtre 2 (maintenant en bas à droite) va sur le bord droit de la fenêtre 3 (en haut à gauche).
        let tenue2 = tranche(t, 0.52, 0.56) - tranche(t, 0.82, 0.86)
        let trajet2 = tranche(t, 0.56, 0.76)
        let partage = tranche(t, 0.80, 0.90)
        let fin = tranche(t, 0.95, 1.0)
        // Places après le premier geste : 3 → case 0, 0 → case 1, 1 → case 2, 2 → case 3.
        let apres: [Int] = [1, 2, 3, 0]
        func place(_ i: Int) -> CGRect { melange(c[i], c[apres[i]], pousse) }
        let moitieG = CGRect(x: c[0].minX, y: c[0].minY, width: c[0].width / 2 - 1, height: c[0].height)
        let moitieD = CGRect(x: c[0].midX + 1, y: c[0].minY, width: c[0].width / 2 - 1, height: c[0].height)
        let depart1 = CGPoint(x: c[3].midX, y: c[3].midY), arrivee1 = CGPoint(x: c[0].midX, y: c[0].midY)
        let depart2 = CGPoint(x: c[3].midX, y: c[3].midY), arrivee2 = CGPoint(x: c[0].maxX - 14, y: c[0].midY)
        let p: CGPoint = t < 0.46 ? melange(melange(CGPoint(x: 250, y: 232), depart1, tranche(t, 0.0, 0.06)), arrivee1, trajet1)
                                  : melange(melange(arrivee1, depart2, tranche(t, 0.44, 0.52)), arrivee2, trajet2)
        return ZStack {
            FondEcran(sombre: 1)
            Group {
                Fenetrette(cadre: place(0), couleur: Ecran.couleurs[0])
                Fenetrette(cadre: place(1), couleur: Ecran.couleurs[1])
                // La fenêtre 2 : poussée en bas à droite, puis emportée, puis posée dans la moitié droite de la première case.
                Fenetrette(cadre: partage > 0 ? melange(place(2), moitieD, partage) : place(2), couleur: Ecran.couleurs[2],
                           opacite: tenue2 > 0.5 && partage == 0 ? 0.3 : 1)
                // La fenêtre 3 : emportée vers la première case, puis resserrée dans sa moitié gauche.
                Fenetrette(cadre: melange(place(3), moitieG, partage), couleur: Ecran.couleurs[3], opacite: tenue1 > 0.5 ? 0.3 : 1)
                // Le repère orange : la moitié où la fenêtre va se poser.
                RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: orange).opacity(0.45))
                    .frame(width: moitieD.width, height: moitieD.height).position(x: moitieD.midX, y: moitieD.midY)
                    .opacity(Double(tranche(t, 0.70, 0.76) - tranche(t, 0.80, 0.84)))
                // Les vignettes transportées, sous le pointeur.
                if tenue1 > 0.5 { Fenetrette(cadre: CGRect(x: p.x - 45, y: p.y - 28, width: 90, height: 56), couleur: Ecran.couleurs[3]) }
                if tenue2 > 0.5 { Fenetrette(cadre: CGRect(x: p.x - 45, y: p.y - 28, width: 90, height: 56), couleur: Ecran.couleurs[2]) }
            }
            .opacity(Double(1 - fin))
            Pointeur(en: p, clic: 0).opacity(Double(1 - fin))
        }
    }

    /// 5. Le Dock de la grille : la loupe suit le pointeur, un clic ouvre l'application.
    private var dock: some View {
        let zone = CGRect(x: 0, y: Ecran.barre, width: 420, height: 262 - Ecran.barre - 44)
        let c = Ecran.cases(dans: zone)
        let n = 7, taille: CGFloat = 22, ecart: CGFloat = 6
        let repos = CGFloat(n) * taille + CGFloat(n - 1) * ecart + 12
        let x0 = 210 - repos / 2 + 6
        let vise = x0 + (CGFloat(n) * (taille + ecart)) * tranche(t, 0.10, 0.50) * 0.72
        let force = tranche(t, 0.08, 0.14) - tranche(t, 0.74, 0.80)
        let zoom = tranche(t, 0.58, 0.74) - tranche(t, 0.90, 0.98)
        let choisie = 4
        // Les tailles des icônes : la loupe en cosinus, comme dans le vrai Dock.
        let echelles: [CGFloat] = (0..<n).map { i in
            let milieu = x0 + CGFloat(i) * (taille + ecart) + taille / 2
            let d = min(1, abs(milieu - vise) / (2.5 * (taille + ecart)))
            return 1 + 0.55 * force * 0.5 * (1 + cos(.pi * d))
        }
        let enPlus = echelles.reduce(0) { $0 + taille * ($1 - 1) }
        var x = x0 - enPlus / 2
        let cadres: [CGRect] = echelles.map { e in
            let r = CGRect(x: x, y: 246 - taille * e, width: taille * e, height: taille * e)
            x += taille * e + ecart
            return r
        }
        return ZStack {
            FondEcran(sombre: 1)
            ForEach(0..<4, id: \.self) { i in Fenetrette(cadre: c[i], couleur: Ecran.couleurs[i], opacite: Double(1 - zoom)) }
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.2))
                .frame(width: repos + enPlus, height: 32).position(x: 210, y: 234)
            ForEach(0..<n, id: \.self) { i in
                RoundedRectangle(cornerRadius: cadres[i].width * 0.24, style: .continuous)
                    .fill(i == 0 ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(Ecran.couleurs[(i + 3) % 6].gradient))
                    .frame(width: cadres[i].width, height: cadres[i].height)
                    .position(x: cadres[i].midX, y: cadres[i].midY)
            }
            Fenetrette(cadre: melange(cadres[choisie], Ecran.plein, zoom), couleur: Ecran.couleurs[(choisie + 3) % 6],
                       opacite: zoom > 0.01 ? 1 : 0)
            Pointeur(en: CGPoint(x: vise, y: 240), clic: tranche(t, 0.50, 0.60)).opacity(Double(1 - zoom))
        }
    }

    /// 6. Le bouton vert : la fenêtre remplit l'écran, sans quitter le bureau (la barre des menus reste là).
    private var boutonVert: some View {
        let petite = CGRect(x: 110, y: 70, width: 200, height: 126)
        let k = tranche(t, 0.40, 0.58) - tranche(t, 0.86, 0.97)
        let cadre = melange(petite, Ecran.plein, k)
        let vert = CGPoint(x: cadre.minX + 31, y: cadre.minY + 8)
        let p = melange(CGPoint(x: 300, y: 220), vert, tranche(t, 0.08, 0.30))
        return ZStack {
            FondEcran()
            Fenetrette(cadre: cadre, couleur: Ecran.couleurs[2], feux: true)
            Pointeur(en: t < 0.40 ? p : vert, clic: t < 0.6 ? tranche(t, 0.32, 0.44) : tranche(t, 0.78, 0.90))
        }
    }
}

// MARK: - Les scènes ajoutées à la fusion (13/11/2026) : les trois places, le tiroir, changer d'avis

/// Le tiroir dessiné : le coin multimédia à gauche, une seule application, la barre d'icônes à droite.
private struct TiroirDessin: View {
    let cadre: CGRect
    var app: Int? = 1                // couleur de l'application affichée (nil : sa place est vide, les cartes défilent)
    var choisie = 0                  // l'icône mise en avant dans la barre
    static func zoneApp(_ r: CGRect) -> CGRect { CGRect(x: r.minX + 90, y: r.minY, width: r.width - 90 - 30, height: r.height) }

    var body: some View {
        ZStack {
            // La musique.
            let m = CGRect(x: cadre.minX, y: cadre.minY, width: 82, height: cadre.height)
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(white: 0.12))
                VStack(spacing: 7) {
                    Image(systemName: "music.note").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(red: 0.12, green: 0.84, blue: 0.38))
                    Capsule().fill(Color.white.opacity(0.35)).frame(width: 40, height: 3)
                }
            }
            .frame(width: m.width, height: m.height)
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            .position(x: m.midX, y: m.midY)
            if let app { Fenetrette(cadre: Self.zoneApp(cadre), couleur: Ecran.couleurs[app % 6]) }
            // La barre d'icônes flottante.
            let b = CGRect(x: cadre.maxX - 22, y: cadre.midY - 42, width: 20, height: 84)
            ZStack {
                Capsule().fill(Color.white.opacity(0.85))
                VStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous).fill(Ecran.couleurs[(i + 1) % 6].gradient)
                            .frame(width: 12, height: 12)
                            .overlay(RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                .strokeBorder(Color(nsColor: orange), lineWidth: 1.5).padding(-2).opacity(i == choisie ? 1 : 0))
                    }
                }
            }
            .frame(width: b.width, height: b.height)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .position(x: b.midX, y: b.midY)
        }
    }
}

/// Le Finder dessiné : une carte claire avec sa barre latérale et quelques fichiers.
private struct FinderDessin: View {
    let cadre: CGRect
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.97))
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10, style: .continuous)
                .fill(Color(white: 0.88)).frame(width: cadre.width * 0.32)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<4, id: \.self) { i in Capsule().fill(Color(white: 0.68)).frame(width: [26, 20, 24, 16][i], height: 5) }
            }
            .padding(.leading, 7).padding(.top, 12)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 8), count: 3), spacing: 10) {
                ForEach(0..<6, id: \.self) { i in
                    Image(systemName: i < 3 ? "folder.fill" : "doc.fill").resizable().scaledToFit().frame(width: 20, height: 20)
                        .foregroundStyle(i < 3 ? AnyShapeStyle(Color(red: 0.36, green: 0.56, blue: 0.96).gradient) : AnyShapeStyle(Color(white: 0.62)))
                }
            }
            .padding(.leading, cadre.width * 0.32 + 8).padding(.top, 16)
        }
        .frame(width: cadre.width, height: cadre.height)
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .position(x: cadre.midX, y: cadre.midY)
    }
}

/// Une touche du clavier dessinée.
private struct ToucheDessin: View {
    let texte: String
    var body: some View {
        Text(texte).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Color(white: 0.2))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
}

extension SceneAccueil {
    /// Le tiroir, du bas de l'écran (ou du haut, s'il est réglé ainsi) : k = 1 ouvert, 0 caché.
    fileprivate func tiroirCadre(_ k: CGFloat) -> CGRect {
        let h: CGFloat = 104
        let y = ConfigTiroir.enHaut ? Ecran.barre + 5 - (h + 16) * (1 - k) : 262 - 7 - h + (h + 16) * (1 - k)
        return CGRect(x: 18, y: y, width: 384, height: h)
    }

    /// Le Finder, ouvert (k = 1) ou rangé (k = 0), du bord choisi dans les réglages (le haut, en général).
    fileprivate func finderCadre(_ k: CGFloat) -> CGRect {
        switch Config.shared.bord {
        case .bas: return CGRect(x: 90, y: 262 - 8 - 112 + 130 * (1 - k), width: 240, height: 112)
        case .gauche: return CGRect(x: 8 - 190 * (1 - k), y: 24, width: 170, height: 118)
        case .droite: return CGRect(x: 420 - 178 + 190 * (1 - k), y: 24, width: 170, height: 118)
        case .plein: return CGRect(x: 90, y: 26, width: 240, height: 112)
        default: return CGRect(x: 90, y: Ecran.barre + 5 - 130 * (1 - k), width: 240, height: 112)
        }
    }

    /// 1. Les trois places : une application de travail en grand, le Finder qui arrive de son bord, le tiroir du bord opposé.
    var troisPlaces: some View {
        let kF = tranche(t, 0.10, 0.26) - tranche(t, 0.84, 0.95)
        let kT = tranche(t, 0.34, 0.50) - tranche(t, 0.84, 0.95)
        return ZStack {
            FondEcran()
            Fenetrette(cadre: Ecran.plein, couleur: Ecran.couleurs[0])
            FinderDessin(cadre: finderCadre(kF)).opacity(Config.shared.bord == .plein ? Double(kF) : (kF > 0.001 ? 1 : 0))
            TiroirDessin(cadre: tiroirCadre(kT), app: 2, choisie: 1).opacity(kT > 0.001 ? 1 : 0)
        }
    }

    /// 4. Le tiroir : il monte avec une seule application. Le geste continue : les applications du tiroir défilent en cartes,
    /// sur une roue ; doigts levés, la carte du centre prend la place.
    var tiroirDefile: some View {
        let k = tranche(t, 0.06, 0.22) - tranche(t, 0.90, 0.98)
        let r = tiroirCadre(k), zone = TiroirDessin.zoneApp(r)
        let cartes = tranche(t, 0.28, 0.33) - tranche(t, 0.64, 0.69)
        let pos = 2 * tranche(t, 0.32, 0.62)                     // de la première application à la troisième
        let apres = t > 0.64
        let sens: CGFloat = ConfigTiroir.enHaut ? 1 : -1
        let largeur: CGFloat = 92, hauteur: CGFloat = 58
        return ZStack {
            FondEcran()
            Fenetrette(cadre: Ecran.plein, couleur: Ecran.couleurs[0])
            Color.black.opacity(0.25 * Double(cartes))
            TiroirDessin(cadre: r, app: cartes > 0.5 ? nil : (apres ? 3 : 1), choisie: apres ? 2 : (cartes > 0.5 ? Int(pos.rounded()) : 0))
                .opacity(k > 0.001 ? 1 : 0)
            ForEach(0..<4, id: \.self) { i in
                let d = CGFloat(i) - pos
                let proche = 1 - min(abs(d), 1)
                let s = (0.62 + 0.38 * proche) * max(0.4, 1 - 0.18 * abs(d))
                Fenetrette(cadre: CGRect(x: zone.midX - largeur * s / 2, y: zone.midY + sens * d * 46 - hauteur * s / 2,
                                         width: largeur * s, height: hauteur * s),
                           couleur: Ecran.couleurs[(i + 1) % 6], opacite: Double(cartes) * Double(max(0, 1 - 0.45 * abs(d))),
                           contour: proche > 0.5)
            }
        }
    }

    /// 5. Changer d'avis : le bouton jaune d'une application de travail la range dans le tiroir. Dans le tiroir, le bouton vert
    /// la ressort : elle se pose au centre de l'écran, à sa taille (pas en plein écran).
    var changerDAvis: some View {
        let monte = tranche(t, 0.24, 0.38) - tranche(t, 0.62, 0.74)
        let ouvert = tiroirCadre(1), zone = TiroirDessin.zoneApp(ouvert)
        let centre = CGRect(x: 120, y: 78, width: 180, height: 112)
        let cadre: CGRect = t < 0.60 ? melange(Ecran.plein, zone, tranche(t, 0.24, 0.38)) : melange(zone, centre, tranche(t, 0.62, 0.74))
        let jaune = CGPoint(x: Ecran.plein.minX + 22, y: Ecran.plein.minY + 8)
        let vert = CGPoint(x: zone.minX + 34, y: zone.minY + 8)
        let p: CGPoint = t < 0.40 ? melange(CGPoint(x: 250, y: 190), jaune, tranche(t, 0.04, 0.16))
                                  : melange(CGPoint(x: 300, y: 120), vert, tranche(t, 0.42, 0.54))
        let pointeurVisible = (1 - tranche(t, 0.24, 0.30)) + (tranche(t, 0.40, 0.44) - tranche(t, 0.62, 0.68))
        return ZStack {
            FondEcran()
            Fenetrette(cadre: Ecran.plein, couleur: Ecran.couleurs[0])
            TiroirDessin(cadre: tiroirCadre(monte), app: nil, choisie: 1).opacity(monte > 0.001 ? 1 : 0)
            Fenetrette(cadre: cadre, couleur: Ecran.couleurs[2], feux: true)
                .opacity(Double(tranche(t, 0.0, 0.04) - tranche(t, 0.92, 0.98)))
            Pointeur(en: p, clic: t < 0.40 ? tranche(t, 0.16, 0.26) : tranche(t, 0.54, 0.64)).opacity(Double(pointeurVisible))
        }
    }
}
