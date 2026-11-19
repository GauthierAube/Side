// Le dessin de l'île de l'encoche (voir Encoche.swift). Tout est noir, comme l'encoche elle-même : l'île en paraît le
// prolongement. Ce qui compte le plus ici, c'est le mouvement : une seule forme qui s'étire avec un ressort, la pochette
// qui glisse de sa petite place à côté de l'encoche jusqu'au lecteur, le contenu qui arrive flou puis se précise.
import AppKit
import SwiftUI

// MARK: - La forme

/// La forme de l'encoche : deux petits évasements en haut, qui la raccordent au bord de l'écran, et le bas arrondi.
/// Les deux rayons s'animent : l'île s'arrondit davantage en s'ouvrant.
struct FormeEncoche: Shape {
    var haut: CGFloat
    var bas: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(haut, bas) }
        set { haut = newValue.first; bas = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let h = min(haut, r.width / 4)
        let b = max(0, min(bas, r.height - h, (r.width - 2 * h) / 2))
        let k: CGFloat = 0.45          // courbes douces, à la façon des arrondis d'Apple
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + h, y: r.minY + h), control: CGPoint(x: r.minX + h, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + h, y: r.maxY - b))
        p.addCurve(to: CGPoint(x: r.minX + h + b, y: r.maxY),
                   control1: CGPoint(x: r.minX + h, y: r.maxY - b * k), control2: CGPoint(x: r.minX + h + b * k, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - h - b, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX - h, y: r.maxY - b),
                   control1: CGPoint(x: r.maxX - h - b * k, y: r.maxY), control2: CGPoint(x: r.maxX - h, y: r.maxY - b * k))
        p.addLine(to: CGPoint(x: r.maxX - h, y: r.minY + h))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - h, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Ce qui apparaît dans l'île arrive flou, un peu plus petit et transparent, puis se précise (et repart de même).
private struct Apparition: ViewModifier {
    let actif: Bool
    func body(content: Content) -> some View {
        content
            .blur(radius: actif ? 8 : 0)
            .scaleEffect(actif ? 0.86 : 1, anchor: .top)
            .opacity(actif ? 0 : 1)
    }
}

extension AnyTransition {
    static var ile: AnyTransition {
        .modifier(active: Apparition(actif: true), identity: Apparition(actif: false))
    }
}

// MARK: - L'île

struct VueIle: View {
    @ObservedObject private var ile = Ile.commun
    @ObservedObject private var lecture = LectureIle.commun
    @ObservedObject private var config = ConfigEncoche.commun
    @Namespace private var ns

    var body: some View {
        let t = ile.taille
        let ouverte = ile.ouverte
        let haut: CGFloat = ouverte ? 14 : 6
        let bas: CGFloat = ouverte ? Rayon.ile : (ile.survol ? 12 : 10)
        let forme = FormeEncoche(haut: haut, bas: bas)
        ZStack(alignment: .top) {
            switch ile.etat {
            case .repos: compacte.transition(.ile)
            case .hud: if let h = ile.hud { HudVue(hud: h).transition(.ile) }
            case .ouvert: VueOuverte(ns: ns).transition(.ile.animation(Mouvement.ile?.delay(0.05)))
            }
        }
        .frame(width: t.width, height: t.height, alignment: .top)
        .padding(.horizontal, haut)
        .background(forme.fill(Color.black))
        .clipShape(forme)
        .contentShape(forme)
        .shadow(color: .black.opacity(ouverte ? 0.5 : 0), radius: ouverte ? 24 : 0, y: 10)
        .onTapGesture { if !ile.ouverte { ile.ouvrir() } }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    /// Au repos : rien (l'île se confond avec l'encoche), ou la musique de part et d'autre de l'encoche.
    @ViewBuilder private var compacte: some View {
        if ile.activite {
            HStack(spacing: 0) {
                Pochette(image: lecture.pochette, taille: ile.encoche.height - 12, rayon: Rayon.puce + 2)
                    .matchedGeometryEffect(id: "pochette", in: ns)
                    .frame(width: ile.aile)
                Spacer(minLength: 0)
                Onde(joue: lecture.joue, teinte: lecture.teinte)
                    .frame(width: 16, height: 12)
                    .frame(width: ile.aile)
            }
            .frame(height: ile.encoche.height)
            .frame(maxHeight: .infinity)
        } else {
            Color.clear
        }
    }
}

// MARK: - Volume et luminosité

private struct HudVue: View {
    let hud: HudIle
    var body: some View {
        HStack(spacing: 0) {
            icone
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: hud.coup)
                .frame(width: Ile.aileHud)
            Spacer(minLength: 0)
            Jauge(niveau: hud.muet ? 0 : hud.niveau)
                .frame(width: 54, height: 5)
                .frame(width: Ile.aileHud)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var icone: some View {
        switch hud.genre {
        case .volume:
            if hud.muet || hud.niveau == 0 { Image(systemName: "speaker.slash.fill") }
            else { Image(systemName: "speaker.wave.3.fill", variableValue: hud.niveau) }
        case .luminosite:
            Image(systemName: hud.niveau < 0.5 ? "sun.min.fill" : "sun.max.fill")
        }
    }
}

/// Une jauge qui glisse avec un ressort à chaque appui.
struct Jauge: View {
    let niveau: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Color.white).frame(width: max(0, g.size.width * niveau))
            }
        }
        .animation(Mouvement.ileSurvol, value: niveau)
    }
}

/// Quatre barres qui ondulent tant que la musique joue, à la couleur de la pochette.
struct Onde: View {
    let joue: Bool
    let teinte: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !joue)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let v = joue ? 0.35 + 0.65 * abs(sin(t * (5.2 + Double(i) * 1.7) + Double(i) * 1.3)) : 0.2
                    Capsule().fill(teinte).frame(width: 2.5, height: max(2.5, 12 * v))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// La pochette du titre en cours (une note de musique sur un dégradé quand il n'y en a pas).
struct Pochette: View {
    let image: NSImage?
    let taille: CGFloat
    let rayon: CGFloat
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note").font(.system(size: taille * 0.42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: taille, height: taille)
        .clipShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
    }
}

// MARK: - L'île ouverte

/// Une vue qui change glisse de côté, floue, dans le sens du geste.
private struct Feuillet: ViewModifier {
    let dx: CGFloat
    let actif: Bool
    func body(content: Content) -> some View {
        content.offset(x: actif ? dx : 0).blur(radius: actif ? 6 : 0).opacity(actif ? 0 : 1)
    }
}

extension AnyTransition {
    static func feuillet(_ sens: CGFloat) -> AnyTransition {
        .asymmetric(insertion: .modifier(active: Feuillet(dx: 56 * sens, actif: true), identity: Feuillet(dx: 0, actif: false)),
                    removal: .modifier(active: Feuillet(dx: -56 * sens, actif: true), identity: Feuillet(dx: 0, actif: false)))
    }
}

/// Une seule vue à la fois : le nom de la vue à gauche de l'encoche, les points pour changer de vue à droite.
private struct VueOuverte: View {
    let ns: Namespace.ID
    @ObservedObject private var ile = Ile.commun

    var body: some View {
        VStack(spacing: 0) {
            bandeau.frame(height: ile.encoche.height)
            ZStack(alignment: .top) {
                page.id(ile.page).transition(.feuillet(ile.sens))
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder private var page: some View {
        switch ile.page {
        case .calendrier: MoisVue()
        case .lecture: LectureVue(ns: ns)
        }
    }

    private var bandeau: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: ile.page.symbole).font(.system(size: 10, weight: .semibold))
                Text(ile.page.nom).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.75))
            .id(ile.page)
            .transition(.feuillet(ile.sens))
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: ile.encoche.width)     // la caméra
            Group {
                if let h = ile.hud {
                    HStack(spacing: 7) {
                        Image(systemName: h.genre == .volume ? (h.muet ? "speaker.slash.fill" : "speaker.wave.3.fill") : "sun.max.fill")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                        Jauge(niveau: h.muet ? 0 : h.niveau).frame(width: 60, height: 5)
                    }
                    .transition(.ile)
                } else {
                    Points().transition(.ile)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }
}

/// Un point par vue ; celui de la vue affichée s'allonge. Un clic sur un point y mène.
private struct Points: View {
    @ObservedObject private var ile = Ile.commun
    @Namespace private var trait

    var body: some View {
        HStack(spacing: 5) {
            ForEach(ile.pages, id: \.self) { p in
                Button { ile.allerA(p) } label: {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.3)).frame(width: 6, height: 6)
                        if p == ile.page {
                            Capsule().fill(Color.white).frame(width: 16, height: 6)
                                .matchedGeometryEffect(id: "point", in: trait)
                        }
                    }
                    .frame(width: p == ile.page ? 16 : 6, height: 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BoutonIle())
                .help(p.nom)
            }
        }
    }
}

/// Un bouton de l'île : il s'enfonce sous le doigt et rebondit au relâché.
struct BoutonIle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .animation(Mouvement.ileSurvol, value: configuration.isPressed)
    }
}

// MARK: - Lecture en cours

private struct LectureVue: View {
    let ns: Namespace.ID
    @ObservedObject private var lecture = LectureIle.commun

    var body: some View {
        if lecture.source != nil {
            HStack(spacing: 14) {
                Pochette(image: lecture.pochette, taille: 84, rayon: Rayon.panneau)
                    .matchedGeometryEffect(id: "pochette", in: ns)
                    .shadow(color: lecture.teinte.opacity(0.45), radius: 14, y: 4)
                    .scaleEffect(lecture.joue ? 1 : 0.92)
                    .animation(Mouvement.ile, value: lecture.joue)
                VStack(alignment: .leading, spacing: 5) {
                    Text(lecture.titre).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(lecture.artiste).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    Progression()
                    HStack(spacing: 26) {
                        commande("backward.fill", 13) { lecture.precedent() }
                        commande(lecture.joue ? "pause.fill" : "play.fill", 20) { lecture.lecturePause() }
                        commande("forward.fill", 13) { lecture.suivant() }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Pochette(image: nil, taille: 44, rayon: Rayon.vignette).matchedGeometryEffect(id: "pochette", in: ns)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rien en lecture").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        Text("Lance un morceau dans Spotify ou Musique.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    }
                }
                HStack(spacing: 8) {
                    lanceur("Spotify", "com.spotify.client")
                    lanceur(String(localized: "Musique"), "com.apple.Music")
                }
            }
        }
    }

    private func commande(_ symbole: String, _ taille: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole).font(.system(size: taille, weight: .semibold)).foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(BoutonIle())
    }

    @ViewBuilder private func lanceur(_ nom: String, _ bundle: String) -> some View {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil {
            Button { Descente.application(bundle) } label: {
                Text(nom).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(BoutonIle())
        }
    }
}

/// La barre de progression du titre, et les temps de part et d'autre.
private struct Progression: View {
    @ObservedObject private var lecture = LectureIle.commun
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let pos = lecture.position(a: ctx.date)
            let part = lecture.duree > 0 ? min(1, pos / lecture.duree) : 0
            HStack(spacing: 7) {
                Text(temps(pos)).frame(width: 30, alignment: .trailing)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(lecture.teinte).frame(width: g.size.width * part)
                    }
                }
                .frame(height: 4)
                .animation(.linear(duration: Mouvement.duree(0.5)), value: part)
                Text(temps(lecture.duree)).frame(width: 30, alignment: .leading)
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
        .frame(height: 12)
    }
    private func temps(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "0:00" }
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Agenda

/// Avant l'accès au calendrier : une phrase et le bouton qui le demande.
private struct AccesAgenda: View {
    @ObservedObject private var cal = CalendrierIle.commun
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            Text(cal.refuse ? "Autorise Side dans Réglages Système > Confidentialité > Calendriers."
                            : "Tes rendez-vous, ici.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            if !cal.refuse {
                Button { cal.demander() } label: {
                    Text("Afficher mon agenda").font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(BoutonIle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Un rendez-vous : sa couleur, son titre, ses heures ; à droite, « en cours » ou « dans 20 min ».
private struct LigneRdv: View {
    let rdv: CalendrierIle.Rdv
    var maintenant: Date? = nil

    var body: some View {
        let passe = maintenant.map { !rdv.journee && rdv.fin <= $0 } ?? false
        HStack(spacing: 8) {
            Capsule().fill(rdv.couleur).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(rdv.titre).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Text(rdv.heures).font(.system(size: 10).monospacedDigit()).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let m = maintenant, let e = etiquette(m) {
                Text(e).font(.system(size: 10, weight: .semibold)).foregroundStyle(rdv.couleur)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(rdv.couleur.opacity(0.18)))
            }
        }
        .opacity(passe ? 0.4 : 1)
    }

    private func etiquette(_ m: Date) -> String? {
        guard !rdv.journee else { return nil }
        if rdv.debut <= m && m < rdv.fin { return String(localized: "En cours") }
        let min = Int(rdv.debut.timeIntervalSince(m) / 60)
        guard min >= 0, min < 180 else { return nil }
        return min < 60 ? String(localized: "Dans \(max(1, min)) min") : String(localized: "Dans \(min / 60) h \(String(format: "%02d", min % 60))")
    }
}

/// Le calendrier du mois à gauche (un clic sur un jour), les rendez-vous de ce jour à droite.
private struct MoisVue: View {
    @ObservedObject private var cal = CalendrierIle.commun

    var body: some View {
        if !cal.autorise {
            AccesAgenda()
        } else {
            HStack(alignment: .top, spacing: 16) {
                GrilleMois().frame(width: 172)
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
                VStack(alignment: .leading, spacing: 7) {
                    Text(cal.jour.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized(with: .current))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        .id(cal.jour).transition(.ile)
                    if cal.duJour.isEmpty {
                        Text("Rien de prévu.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    } else {
                        ForEach(cal.duJour.prefix(3)) { r in LigneRdv(rdv: r).transition(.ile) }
                        if cal.duJour.count > 3 {
                            Text("Et \(cal.duJour.count - 3) de plus").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct GrilleMois: View {
    @ObservedObject private var cal = CalendrierIle.commun

    var body: some View {
        let c = Calendar.current
        let premier = c.component(.weekday, from: cal.mois)
        let decalage = (premier - c.firstWeekday + 7) % 7
        let nombre = c.range(of: .day, in: .month, for: cal.mois)?.count ?? 30
        let cases: [Int?] = Array(repeating: nil, count: decalage) + (1...nombre).map { Optional($0) }
        let lignes = Int(ceil(Double(cases.count) / 7))
        let initiales = (0..<7).map { c.veryShortStandaloneWeekdaySymbols[(c.firstWeekday - 1 + $0) % 7] }
        VStack(spacing: 2) {
            HStack {
                Text(cal.mois.formatted(.dateTime.month(.wide).year()).capitalized(with: .current))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                fleche("chevron.left") { cal.changerMois(-1) }
                fleche("chevron.right") { cal.changerMois(1) }
            }
            .frame(height: 16)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(initiales[i]).font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<lignes, id: \.self) { l in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let i = l * 7 + col
                        if i < cases.count, let j = cases[i] { caseJour(j) } else { Color.clear.frame(maxWidth: .infinity) }
                    }
                }
                .frame(height: lignes > 5 ? 16 : 18)
            }
        }
        .id(cal.mois)
        .transition(.ile)
    }

    private func caseJour(_ j: Int) -> some View {
        let c = Calendar.current
        let date = c.date(byAdding: .day, value: j - 1, to: cal.mois) ?? cal.mois
        let choisi = c.isDate(date, inSameDayAs: cal.jour)
        let auj = c.isDateInToday(date)
        return Button { cal.choisir(date) } label: {
            Text("\(j)")
                .font(.system(size: 10, weight: auj || choisi ? .bold : .regular).monospacedDigit())
                .foregroundStyle(choisi ? (auj ? Color.white : Color.black) : (auj ? Color.red : Color.white.opacity(0.85)))
                .frame(width: 18, height: 15)
                .background { if choisi { Circle().fill(auj ? Color.red : Color.white) } }
                .overlay(alignment: .bottom) {
                    if cal.marques.contains(j) && !choisi {
                        Circle().fill(Color.white.opacity(0.55)).frame(width: 3, height: 3).offset(y: 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(BoutonIle())
    }

    private func fleche(_ symbole: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                .frame(width: 18, height: 16).contentShape(Rectangle())
        }
        .buttonStyle(BoutonIle())
    }
}
