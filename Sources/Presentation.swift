// La présentation de Side, à la première ouverture : quatre écrans, presque sans mots. Chacun montre le geste en mouvement
// sur un petit écran dessiné, avec en dessous le ou les déclencheurs sous forme de pastilles (ceux qui sont réglés).
// Et, à part : Side se met en retrait pendant une capture d'écran.
import AppKit
import SwiftUI

// MARK: - Capture d'écran

/// La capture d'écran de macOS est-elle en cours (⌘⇧4, ⌘⇧5) ? Son outil ne tourne que pendant qu'on choisit la zone.
/// Side ne s'ouvre alors par aucun geste : on doit pouvoir viser un coin de l'écran sans rien déclencher.
enum CaptureEcran {
    private static var valeur = false
    private static var verifieA: TimeInterval = 0

    /// Lu souvent (à chaque mouvement de doigts) : la réponse est gardée un quart de seconde.
    static var enCours: Bool {
        let maintenant = ProcessInfo.processInfo.systemUptime
        if maintenant - verifieA > 0.25 {
            verifieA = maintenant
            valeur = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.screencaptureui").isEmpty
        }
        return valeur
    }
}

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

private func centre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

/// Le petit écran dessiné : 420 × 262 points.
private enum EcranP {
    static let taille = CGSize(width: 420, height: 262)
    static let barre: CGFloat = 11
    static let bleu = Color(red: 0.36, green: 0.56, blue: 0.96)

    /// La carte de Side, ouverte (p = 1) ou rangée hors de l'écran (p = 0), du bord choisi dans les réglages.
    static func carte(_ p: CGFloat) -> CGRect {
        switch Config.shared.bord {
        case .bas: return CGRect(x: 60, y: 262 - 8 - 150 * p + 160 * (1 - p), width: 300, height: 150)
        case .gauche: return CGRect(x: 8 - 190 * (1 - p), y: 30, width: 180, height: 200)
        case .droite: return CGRect(x: 420 - 188 + 190 * (1 - p), y: 30, width: 180, height: 200)
        case .plein: return CGRect(x: 60, y: 56, width: 300, height: 150)
        default: return CGRect(x: 60, y: barre + 5 - 170 * (1 - p), width: 300, height: 150)
        }
    }
    /// En « position libre », la carte apparaît en fondu au lieu de glisser.
    static func opaciteCarte(_ p: CGFloat) -> Double { Config.shared.bord == .plein ? Double(p) : 1 }

    /// Les six fichiers dessinés dans la carte (trois dossiers en haut, trois documents en bas).
    static func fichier(_ i: Int, dans c: CGRect) -> CGRect {
        let zone = CGRect(x: c.minX + c.width * 0.30, y: c.minY + 12, width: c.width * 0.70 - 10, height: c.height - 22)
        let col = CGFloat(i % 3), ligne = CGFloat(i / 3), cote = min(zone.width / 3.6, zone.height / 2.5)
        return CGRect(x: zone.minX + (zone.width / 3) * (col + 0.5) - cote / 2, y: zone.minY + (zone.height / 2) * (ligne + 0.5) - cote / 2,
                      width: cote, height: cote)
    }
    /// Les lignes de la barre latérale.
    static func ligne(_ i: Int, dans c: CGRect) -> CGRect {
        CGRect(x: c.minX + 8, y: c.minY + 14 + CGFloat(i) * 15, width: c.width * 0.30 - 16, height: 9)
    }
}

/// Un fichier dessiné : un dossier (bleu) ou un document (blanc).
private struct FichierP: View {
    let cadre: CGRect
    let dossier: Bool
    var choisi = false
    var opacite: Double = 1
    var body: some View {
        ZStack {
            if choisi { RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.28)).padding(-4) }
            Image(systemName: dossier ? "folder.fill" : "doc.fill")
                .resizable().scaledToFit()
                .foregroundStyle(dossier ? AnyShapeStyle(EcranP.bleu.gradient) : AnyShapeStyle(Color(white: 0.62)))
        }
        .frame(width: cadre.width, height: cadre.height)
        .opacity(opacite)
        .position(centre(cadre))
    }
}

/// La carte de Side dessinée : sa barre latérale et ses fichiers.
private struct CarteP: View {
    let cadre: CGRect
    var opacite: Double = 1
    var favoriEnPlus: CGFloat = 0        // 0 à 1 : une ligne de plus apparaît dans la barre latérale
    var masques: Set<Int> = []           // fichiers qu'on ne dessine pas (ils sont sous la souris)
    var choisi: Int? = nil

    var body: some View {
        ZStack {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(white: 0.97))
                UnevenRoundedRectangle(topLeadingRadius: 11, bottomLeadingRadius: 11, style: .continuous)
                    .fill(Color(white: 0.89)).frame(width: cadre.width * 0.30)
            }
            .frame(width: cadre.width, height: cadre.height)
            .shadow(color: .black.opacity(0.35), radius: 9, y: 4)
            .position(centre(cadre))
            ForEach(0..<4, id: \.self) { i in
                let r = EcranP.ligne(i + 1, dans: cadre)
                Capsule().fill(Color(white: 0.70)).frame(width: r.width * [0.9, 0.7, 0.8, 0.6][i], height: r.height)
                    .position(x: r.minX + r.width * [0.9, 0.7, 0.8, 0.6][i] / 2, y: r.midY)
            }
            // La ligne ajoutée aux favoris.
            let f = EcranP.ligne(0, dans: cadre)
            Capsule().fill(Color.accentColor).frame(width: f.width * 0.85 * favoriEnPlus, height: f.height)
                .position(x: f.minX + f.width * 0.85 * favoriEnPlus / 2, y: f.midY)
                .opacity(Double(favoriEnPlus))
            ForEach(0..<6, id: \.self) { i in
                if !masques.contains(i) { FichierP(cadre: EcranP.fichier(i, dans: cadre), dossier: i < 3, choisi: choisi == i) }
            }
        }
        .opacity(opacite)
    }
}

private struct PointeurP: View {
    let en: CGPoint
    var clic: CGFloat = 0
    var body: some View {
        ZStack {
            Circle().stroke(Color.white, lineWidth: 2).frame(width: 10 + 26 * clic, height: 10 + 26 * clic)
                .opacity(clic > 0 && clic < 1 ? Double(1 - clic) : 0)
            Image(systemName: "cursorarrow").font(.system(size: 22)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 1.5, y: 1)
                .offset(x: 6, y: 9)
        }
        .position(en)
    }
}

/// Le fond du petit écran : le bureau, une fenêtre d'application derrière, la barre des menus.
private struct FondP: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.55, green: 0.36, blue: 0.62), Color(red: 0.20, green: 0.28, blue: 0.56),
                                    Color(red: 0.10, green: 0.13, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing)
            // Une application en plein écran, derrière : Side passe par-dessus.
            RoundedRectangle(cornerRadius: 0).fill(Color(red: 0.95, green: 0.55, blue: 0.33).opacity(0.55))
                .padding(.top, EcranP.barre)
            RoundedRectangle(cornerRadius: 0).fill(Color.white.opacity(0.80)).padding(.top, EcranP.barre + 26)
            Rectangle().fill(Color.white.opacity(0.22)).frame(height: EcranP.barre)
        }
    }
}

// MARK: - Les scènes

struct ScenePresentation: View {
    let etape: Int
    let t: Double

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                switch etape {
                case 0: ouvrir
                // Fichiers et dossiers, en deux temps dans la même boucle : un dossier ajouté aux favoris, puis l'aperçu d'un fichier.
                case 1: if t < 0.5 { dossiers(t * 2) } else { fichiers((t - 0.5) * 2) }
                case 2: depot
                default: tiroir
                }
            }
            .frame(width: EcranP.taille.width, height: EcranP.taille.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.25), lineWidth: 1.5))
            // Sous l'écran : le trackpad et ses quatre doigts, pour ouvrir le Finder et le tiroir (une place vide ailleurs).
            trackpad.frame(height: 62)
        }
    }

    /// Le Finder s'ouvre-t-il avec quatre doigts ? Et le tiroir ?
    private var doigtsFinder: Bool { Config.shared.quatreDoigts }
    private var doigtsTiroir: Bool { ConfigTiroir.commun.quatreDoigts && ConfigTiroir.gestePossible }

    /// Le trackpad, sous l'écran : quatre doigts qui glissent vers le bas ou vers le haut, puis se lèvent.
    @ViewBuilder private var trackpad: some View {
        let finder = etape == 0 && doigtsFinder, tir = etape == 3 && doigtsTiroir
        if finder || tir {
            // Le sens du geste : celui qui est réglé. (« Les deux » : on montre le sens d'où arrive la carte.)
            let versLeBas: Bool = finder ? (Config.shared.sensDoigts == "bas" || (Config.shared.sensDoigts == "deux" && Config.shared.bord != .bas))
                                         : ConfigTiroir.enHaut
            let glisse = tranche(t, 0.14, 0.42), poses = tranche(t, 0.06, 0.12) - tranche(t, 0.46, 0.54)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.10))
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                HStack(spacing: 7) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle().fill(Color.accentColor).frame(width: 13, height: 13).offset(y: [3, -3, -4, 2][i])
                    }
                }
                .offset(y: (versLeBas ? 1 : -1) * (-15 + 30 * glisse))
                .opacity(Double(poses))
                Image(systemName: versLeBas ? "arrow.down" : "arrow.up").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor).offset(x: 56)
            }
            .frame(width: 150)
        } else {
            Color.clear
        }
    }

    /// 1. Un geste (le coin, ici) : la carte arrive par-dessus l'application, puis repart.
    private var ouvrir: some View {
        // Avec les quatre doigts, la carte suit le geste ; sinon, c'est le pointeur qui va dans le coin.
        let k = (doigtsFinder ? tranche(t, 0.16, 0.44) : tranche(t, 0.30, 0.50)) - tranche(t, 0.84, 0.97)
        let coin: CGPoint = {
            switch Config.shared.coin {
            case .hautGauche: return CGPoint(x: 3, y: 3)
            case .hautDroite: return CGPoint(x: 417, y: 3)
            case .basDroite: return CGPoint(x: 417, y: 259)
            default: return CGPoint(x: 3, y: 259)
            }
        }()
        return ZStack {
            FondP()
            CarteP(cadre: EcranP.carte(k), opacite: EcranP.opaciteCarte(k))
            if !doigtsFinder { PointeurP(en: melange(CGPoint(x: 220, y: 190), coin, tranche(t, 0.06, 0.30))) }
        }
    }

    /// 2. Glisser un dossier sur la barre latérale : il s'ajoute aux favoris.
    private func dossiers(_ t: Double) -> some View {
        let c = EcranP.carte(1)
        let prise = tranche(t, 0.20, 0.24) - tranche(t, 0.56, 0.60)
        let depart = centre(EcranP.fichier(1, dans: c)), arrivee = centre(EcranP.ligne(0, dans: c))
        let p = melange(melange(CGPoint(x: 330, y: 230), depart, tranche(t, 0.06, 0.20)), arrivee, tranche(t, 0.26, 0.52))
        let ajoute = tranche(t, 0.56, 0.66) - tranche(t, 0.92, 0.99)
        return ZStack {
            FondP()
            CarteP(cadre: c, favoriEnPlus: ajoute)
            if prise > 0.5 { FichierP(cadre: CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26), dossier: true, opacite: 0.9) }
            PointeurP(en: p)
        }
    }

    /// 3. Un fichier choisi, la barre d'espace : l'aperçu s'ouvre.
    private func fichiers(_ t: Double) -> some View {
        let c = EcranP.carte(1)
        let cible = EcranP.fichier(4, dans: c)
        let p = melange(CGPoint(x: 340, y: 236), centre(cible), tranche(t, 0.06, 0.26))
        let touche = tranche(t, 0.36, 0.42) - tranche(t, 0.50, 0.58)
        let apercu = tranche(t, 0.44, 0.58) - tranche(t, 0.84, 0.94)
        let grand = CGRect(x: 130, y: 60, width: 160, height: 120)
        return ZStack {
            FondP()
            CarteP(cadre: c, choisi: t > 0.28 ? 4 : nil)
            // L'aperçu : il grandit depuis le fichier.
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white)
                Image(systemName: "photo").resizable().scaledToFit().foregroundStyle(Color(white: 0.70)).padding(18)
            }
            .frame(width: melange(cible, grand, apercu).width, height: melange(cible, grand, apercu).height)
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            .position(centre(melange(cible, grand, apercu)))
            .opacity(Double(min(1, apercu * 4)))
            // La barre d'espace, qu'on enfonce.
            RoundedRectangle(cornerRadius: 5).fill(Color.white).frame(width: 92, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                .scaleEffect(1 - 0.08 * touche)
                .position(x: 210, y: 244)
                .opacity(Double(tranche(t, 0.30, 0.36) - tranche(t, 0.60, 0.68)))
            PointeurP(en: p, clic: tranche(t, 0.24, 0.34))
        }
    }

    /// 4. Pendant un glisser, la zone de dépôt apparaît à côté de la carte. Ce qu'on y pose reste là, même Side refermé.
    private var depot: some View {
        let k = 1 - (tranche(t, 0.62, 0.76) - tranche(t, 0.93, 0.99))            // la carte se referme, puis revient
        let c = EcranP.carte(1), cMobile = EcranP.carte(k)
        let aDroite = Config.shared.bord != .droite
        let zone = CGRect(x: aDroite ? min(c.maxX + 8, 420 - 56) : max(c.minX - 56, 6), y: c.midY - 24, width: 48, height: 48)
        let prise = tranche(t, 0.16, 0.20) - tranche(t, 0.50, 0.54)
        let pose = tranche(t, 0.50, 0.56) - tranche(t, 0.93, 0.99)
        let depart = centre(EcranP.fichier(5, dans: c))
        let p = melange(melange(CGPoint(x: 250, y: 240), depart, tranche(t, 0.04, 0.16)), centre(zone), tranche(t, 0.22, 0.48))
        let zoneVisible = max(tranche(t, 0.22, 0.30) - tranche(t, 0.93, 0.99), 0)
        return ZStack {
            FondP()
            CarteP(cadre: cMobile, opacite: EcranP.opaciteCarte(k), masques: prise > 0.5 || pose > 0.5 ? [5] : [])
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.97))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: pose > 0.5 ? [] : [4, 3])))
                .frame(width: zone.width, height: zone.height)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                .position(centre(zone))
                .opacity(Double(zoneVisible))
            if pose > 0.5 { FichierP(cadre: zone.insetBy(dx: 13, dy: 13), dossier: false) }
            if prise > 0.5 { FichierP(cadre: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24), dossier: false, opacite: 0.9) }
            PointeurP(en: p).opacity(Double(1 - tranche(t, 0.58, 0.64) + tranche(t, 0.95, 1.0)))
        }
    }

    /// 4. Le tiroir : la musique et de petites applications (notes, réglages) qu'on consulte d'un coup d'œil avant de le refermer.
    private var tiroir: some View {
        let k = (doigtsTiroir ? tranche(t, 0.16, 0.44) : tranche(t, 0.22, 0.44)) - tranche(t, 0.84, 0.97)
        let enHaut = ConfigTiroir.enHaut
        let h: CGFloat = 104
        let y = enHaut ? EcranP.barre + 5 - (h + 12) * (1 - k) : 262 - 8 - h + (h + 12) * (1 - k)
        let r = CGRect(x: 20, y: y, width: 380, height: h)
        // Le coup d'œil : la tuile des notes s'éclaire un instant, puis le tiroir repart.
        let regard = tranche(t, 0.50, 0.58) - tranche(t, 0.74, 0.82)
        return ZStack {
            FondP()
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color(white: 0.93))
                HStack(spacing: 7) {
                    // La musique.
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(white: 0.12))
                        VStack(spacing: 7) {
                            Image(systemName: "music.note").font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color(red: 0.12, green: 0.84, blue: 0.38))
                            Capsule().fill(Color.white.opacity(0.35)).frame(width: 44, height: 3)
                        }
                    }
                    .frame(width: 84)
                    // Les notes : on y jette un œil.
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white)
                        VStack(alignment: .leading, spacing: 5) {
                            Image(systemName: "note.text").font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.15))
                            ForEach(0..<3, id: \.self) { i in
                                Capsule().fill(Color(white: 0.78)).frame(width: [92, 70, 82][i], height: 4)
                            }
                        }
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 3).opacity(Double(regard))
                    }
                    .scaleEffect(1 + 0.04 * regard)
                    // Les réglages.
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white)
                        VStack(spacing: 6) {
                            Image(systemName: "gearshape.fill").font(.system(size: 20)).foregroundStyle(Color(white: 0.50))
                            HStack(spacing: 5) {
                                Capsule().fill(Color.accentColor).frame(width: 18, height: 8)
                                Capsule().fill(Color(white: 0.78)).frame(width: 18, height: 8)
                            }
                        }
                    }
                }
                .padding(8)
            }
            .frame(width: r.width, height: r.height)
            .shadow(color: .black.opacity(0.35), radius: 9, y: enHaut ? 4 : -2)
            .position(centre(r))
        }
    }
}

// MARK: - La fenêtre de présentation

private struct PastilleP: View {
    let symbole: String?
    let texte: String?
    var body: some View {
        HStack(spacing: 6) {
            if let symbole { Image(systemName: symbole).font(.system(size: 13, weight: .semibold)) }
            if let texte { Text(texte).font(.system(size: 13, weight: .medium)) }
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(0.09)))
    }
}

struct PresentationVue: View {
    @State var etape = 0
    let fermer: () -> Void
    static let nombre = 4
    private static let periodes: [Double] = [4.6, 10.0, 6.0, 4.6]
    @ObservedObject private var config = Config.shared

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(0..<Self.nombre, id: \.self) { i in
                    Capsule().fill(i == etape ? Color.accentColor : Color.primary.opacity(0.18))
                        .frame(width: i == etape ? 18 : 6, height: 6)
                }
            }
            .padding(.top, 4)
            VStack(spacing: 4) {
                Text(["Le Finder", "Accède à tes fichiers et dossiers", "La zone de dépôt", "Le tiroir"][min(etape, 3)])
                    .font(.title2.weight(.semibold))
                // Une ligne d'explication, seulement là où le dessin ne suffit pas : à quoi sert le tiroir.
                Text(etape == 3 ? "La musique et les petites applis : un coup d'œil, et on referme." : " ")
                    .font(.callout).foregroundStyle(.secondary)
            }
            TimelineView(.animation) { horloge in
                let periode = Self.periodes[etape]
                ScenePresentation(etape: etape,
                                  t: horloge.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: periode) / periode)
            }
            HStack(spacing: 8) { pastilles }.frame(height: 30)
            HStack {
                if etape < Self.nombre - 1 { Button("Passer") { fermer() }.buttonStyle(.plain).foregroundStyle(.secondary) }
                Spacer()
                if etape == Self.nombre - 1 {
                    Button("Réglages…") { fermer(); AppDelegate.shared.ouvrirReglages() }
                }
                if etape > 0 { Button("Précédent") { etape -= 1 } }
                Button(etape < Self.nombre - 1 ? "Suivant" : "Terminer") {
                    if etape < Self.nombre - 1 { etape += 1 } else { fermer() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 18)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func symbole(_ c: Coin) -> String {
        switch c {
        case .hautGauche: return "arrow.up.left"
        case .hautDroite: return "arrow.up.right"
        case .basDroite: return "arrow.down.right"
        default: return "arrow.down.left"
        }
    }

    /// Les déclencheurs réglés, en pastilles : on ne montre que ceux qui servent vraiment.
    @ViewBuilder private var pastilles: some View {
        switch etape {
        case 0:
            if config.quatreDoigts {
                PastilleP(symbole: "hand.draw", texte: "Quatre doigts " + (config.sensDoigts == "haut" ? "↑" : (config.sensDoigts == "bas" ? "↓" : "↑ ↓")))
            }
            if config.coin != .aucun { PastilleP(symbole: symbole(config.coin), texte: "Coin") }
            if config.secouer { PastilleP(symbole: "cursorarrow.motionlines", texte: config.cercle ? "Cercle" : "Secousse") }
            if config.touche != -1 { PastilleP(symbole: "keyboard", texte: config.libelle) }
        case 1:
            PastilleP(symbole: "star", texte: "Favoris")
            PastilleP(symbole: "space", texte: "Aperçu")
            PastilleP(symbole: "cursorarrow.click.2", texte: "Ouvrir")
        case 2:
            PastilleP(symbole: "tray.and.arrow.down", texte: "Reste sous la main")
        default:
            if ConfigTiroir.commun.quatreDoigts && ConfigTiroir.gestePossible {
                PastilleP(symbole: "hand.draw", texte: "Quatre doigts " + (ConfigTiroir.enHaut ? "↓" : "↑"))
            }
            if ConfigTiroir.commun.touche != -1 { PastilleP(symbole: "keyboard", texte: ConfigTiroir.commun.libelle) }
            if ConfigTiroir.commun.coin != .aucun { PastilleP(symbole: symbole(ConfigTiroir.commun.coin), texte: "Coin") }
        }
    }
}

/// La fenêtre de présentation : affichée une fois, à la première ouverture, puis sur demande depuis les réglages.
enum PresentationSide {
    private static var fenetre: NSWindow?

    static func montrer() {
        if fenetre == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: PresentationVue(fermer: { PresentationSide.fermer() })))
            w.title = "Bienvenue dans Side"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.level = .floating
            fenetre = w
        }
        fenetre?.center()
        NSApp.activate(ignoringOtherApps: true)
        fenetre?.makeKeyAndOrderFront(nil)
    }

    static func fermer() {
        UserDefaults.standard.set(true, forKey: "accueilVu")
        fenetre?.close()
        fenetre = nil
    }

    /// Pour les essais : dessine chaque étape, à plusieurs instants de sa boucle, dans des images.
    static func images(vers dossier: URL) {
        for etape in 0..<PresentationVue.nombre {
            for (n, t) in [0.22, 0.46, 0.60, 0.80].enumerated() {
                let vue = NSHostingView(rootView: ScenePresentation(etape: etape, t: t).padding(10).background(Color(nsColor: .windowBackgroundColor)))
                vue.frame = NSRect(x: 0, y: 0, width: 440, height: 356)
                let w = NSWindow(contentRect: vue.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                w.contentView = vue
                vue.layoutSubtreeIfNeeded()
                guard let rep = vue.bitmapImageRepForCachingDisplay(in: vue.bounds) else { continue }
                vue.cacheDisplay(in: vue.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: dossier.appendingPathComponent("presentation-\(etape + 1)-\(n + 1).png"))
            }
        }
    }
}
