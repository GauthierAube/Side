// Le volet à plusieurs vues (18/11/2026) : une liste de vues d'Horizon sur le bord gauche ou droit, qu'on fait défiler
// comme des cartes avec quatre doigts à l'horizontale, quand le pointeur est sur le volet. Chaque côté a sa liste.
// Ce fichier tient les listes,
// la vue en cours et la reconnaissance du geste ; le volet lui-même (fenêtres, glissements) est dans VoletVue.swift.
// Essais : `Side --test-pages` (VoletGaucheEssais.swift).
import AppKit
import SwiftUI

/// La liste des vues d'un volet (gauche ou droit) et celle qu'il montre.
final class PileVues: ObservableObject {
    enum Côté: String { case gauche, droite }

    static let gauche = PileVues(défauts: .standard, côté: .gauche)
    static let droite = PileVues(défauts: .standard, côté: .droite)
    static let maximum = 5

    /// La liste qu'ouvre cette valeur de coin actif, ou nil si c'est le chemin d'une application.
    static func pour(_ valeur: String) -> PileVues? { [gauche, droite].first { $0.sentinelle == valeur } }

    let côté: Côté
    /// La valeur d'un coin actif qui ouvre ce volet (au lieu du chemin d'une application).
    var sentinelle: String { "pile:" + côté.rawValue }
    var àDroite: Bool { côté == .droite }

    private let défauts: UserDefaults
    // Les clés du volet de gauche gardent leur nom d'origine (réglages déjà enregistrés).
    private var clé: String { côté == .gauche ? "voletGauche" : "voletDroite" }

    /// Les chemins des applications, dans l'ordre des pages.
    @Published var vues: [String] {
        didSet { défauts.set(vues, forKey: clé + "Vues"); borner() }
    }
    /// La page en cours (toujours dans la liste, ou 0 si elle est vide).
    @Published var index: Int {
        didSet { borner(); défauts.set(index, forKey: clé + "Index") }
    }
    /// La largeur commune à toutes les vues du volet.
    var largeur: Double {
        get { défauts.object(forKey: clé + "Largeur") as? Double ?? 520 }
        set { défauts.set(newValue, forKey: clé + "Largeur") }
    }

    init(défauts: UserDefaults, côté: Côté) {
        self.défauts = défauts
        self.côté = côté
        let clé = côté == .gauche ? "voletGauche" : "voletDroite"
        vues = défauts.stringArray(forKey: clé + "Vues") ?? []
        index = défauts.integer(forKey: clé + "Index")
        borner()
    }

    private func borner() {
        let i = min(max(index, 0), max(vues.count - 1, 0))
        if i != index { index = i }
    }

    var cheminCourant: String? { vues.indices.contains(index) ? vues[index] : nil }

    /// La page voisine dans ce sens (+1 suivante, -1 précédente). Roulement sans fin : après la dernière, la première.
    /// Nil s'il n'y a pas d'autre vue.
    func page(_ sens: Int) -> Int? {
        guard vues.count > 1 else { return nil }
        return ((index + sens) % vues.count + vues.count) % vues.count
    }
}

/// Suit un glissement à quatre doigts vers la gauche ou la droite, image par image, pour que les cartes suivent les doigts.
/// Appelé hors du fil principal, à chaque image du trackpad.
enum GestePages {
    enum Événement: Equatable {
        case début(Int)               // +1 : doigts vers la gauche (carte suivante), -1 : vers la droite (précédente)
        case suivi(Float)             // avancée : 0 au départ, 1 quand la carte a fait tout le chemin
        case fin(Float, Float)        // avancée et élan (en courses par seconde, positif dans le sens du geste)
    }

    private static var départs: [Int32: (Float, Float)] = [:]
    private static var sens: Float = 0            // 0 : pas encore décidé
    private static var refusé = false              // ce geste n'est pas pour nous (vertical, pincement)
    private static var avancée: Float = 0
    private static var élan: Float = 0
    private static var instantPrécédent: TimeInterval = 0
    private static let seuil: Float = 0.02         // trajet avant de décider, en largeur de trackpad
    static let course: Float = 0.3                 // trajet des doigts pour une carte entière

    static func suivre(_ doigts: [(Int32, Float, Float)], instant: TimeInterval) -> Événement? {
        if doigts.count < 3 {
            defer { départs = [:]; sens = 0; refusé = false; avancée = 0; élan = 0 }
            return sens != 0 ? .fin(avancée, élan) : nil
        }
        for (id, x, y) in doigts where départs[id] == nil { départs[id] = (x, y) }
        guard !refusé else { return nil }
        let écarts = doigts.compactMap { id, x, y in départs[id].map { (x - $0.0, y - $0.1) } }
        guard écarts.count >= 3 else { return nil }
        let dx = écarts.map(\.0).reduce(0, +) / Float(écarts.count)
        let dy = écarts.map(\.1).reduce(0, +) / Float(écarts.count)
        if sens == 0 {
            guard doigts.count >= 4, écarts.count >= 4, max(abs(dx), abs(dy)) > seuil else { return nil }
            // Tous les doigts dans le même sens (pas un pincement), et nettement à l'horizontale.
            let mêmeSens = écarts.allSatisfy { dx > 0 ? $0.0 > -0.02 : $0.0 < 0.02 }
            guard mêmeSens, abs(dx) > 1.5 * abs(dy) else { refusé = true; return nil }
            sens = dx < 0 ? 1 : -1
            avancée = max(0, -dx * sens / course)
            instantPrécédent = instant
            return .début(Int(sens))
        }
        let a = max(0, -dx * sens / course)
        let dt = Float(instant - instantPrécédent)
        if dt > 0.004 { élan = élan * 0.5 + (a - avancée) / dt * 0.5; instantPrécédent = instant }
        avancée = a
        return .suivi(a)
    }
}

// MARK: - Les points en haut du volet

/// Un point par vue, celui de la vue en cours plein. Un clic sur un point montre cette vue. Rien s'il n'y a qu'une vue.
struct PointsPileVue: View {
    @ObservedObject var pile: PileVues
    var choisir: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(pile.vues.enumerated()), id: \.offset) { i, chemin in
                Button { choisir(i) } label: {
                    Circle()
                        .fill(Color.primary.opacity(i == pile.index ? 0.85 : 0.35))
                        .frame(width: 7, height: 7)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(FileManager.default.displayName(atPath: chemin).replacingOccurrences(of: ".app", with: ""))
                .accessibilityLabel(FileManager.default.displayName(atPath: chemin).replacingOccurrences(of: ".app", with: ""))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }
}

/// Le petit panneau des points, posé en haut du volet, au-dessus de sa fenêtre.
final class PointsPile {
    static let commun = PointsPile()
    private var panneau: NSPanel?

    func montrer(_ pile: PileVues, au cadre: NSRect, choisir: @escaping (Int) -> Void) {
        guard pile.vues.count > 1 else { cacher(); return }
        let p = panneau ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.hidesOnDeactivate = false
            panneau = p
            return p
        }()
        let vue = NSHostingView(rootView: PointsPileVue(pile: pile, choisir: choisir))
        p.contentView = vue
        let t = vue.fittingSize
        p.setFrame(NSRect(x: (cadre.midX - t.width / 2).rounded(), y: cadre.maxY - t.height - 8, width: t.width, height: t.height), display: true)
        p.orderFrontRegardless()
    }

    func cacher() { panneau?.orderOut(nil) }
}

// MARK: - Réglages

/// Les listes des volets à plusieurs vues, dans le volet de réglages des coins actifs. Une seule section, avec un choix
/// Gauche / Droite en tête : deux sections l'une sous l'autre dérangeaient la mise en page du formulaire.
struct ReglagesPileVues: View {
    @State private var côté = PileVues.Côté.gauche

    var body: some View {
        Section {
            Picker("Côté", selection: $côté) {
                Text("Gauche").tag(PileVues.Côté.gauche)
                Text("Droite").tag(PileVues.Côté.droite)
            }
            .pickerStyle(.segmented)
            ListeVues(pile: côté == .gauche ? PileVues.gauche : PileVues.droite)
        } header: {
            Text("Volets à plusieurs vues")
        } footer: {
            Text("Pour un coin réglé sur « Plusieurs vues » : les coins de gauche ouvrent le volet de gauche, ceux de droite le volet de droite. Quatre doigts à l’horizontale sur le volet passent d’une vue à l’autre, en boucle ; les points en haut du volet aussi. Avec plusieurs bureaux sur l’écran, macOS garde le geste pour changer de bureau : utilise alors les points. La flèche monte une vue d’un rang. Cinq vues au plus par côté.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Les vues d'un côté : une ligne par vue (monter, retirer), puis « Ajouter une vue ».
private struct ListeVues: View {
    @ObservedObject var pile: PileVues

    private func nom(_ chemin: String) -> String {
        FileManager.default.displayName(atPath: chemin).replacingOccurrences(of: ".app", with: "")
    }

    private var restantes: [String] {
        PanneauBas.commun.vuesHorizon.map(\.path).filter { !pile.vues.contains($0) }
    }

    var body: some View {
        ForEach(pile.vues, id: \.self) { chemin in
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: chemin)).resizable().frame(width: 18, height: 18)
                Text(nom(chemin))
                Spacer()
                Button {
                    if let i = pile.vues.firstIndex(of: chemin), i > 0 { pile.vues.swapAt(i, i - 1) }
                } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderless)
                    .disabled(pile.vues.first == chemin)
                    .help("Monter cette vue d'un rang")
                Button { pile.vues.removeAll { $0 == chemin } } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Retirer cette vue du volet")
            }
        }
        LabeledContent {
            Menu("Ajouter une vue") {
                ForEach(restantes, id: \.self) { chemin in
                    Button(nom(chemin)) { pile.vues.append(chemin) }
                }
            }
            .fixedSize()
            .disabled(restantes.isEmpty || pile.vues.count >= PileVues.maximum)
        } label: {
            Text("Vues : \(pile.vues.count) sur \(PileVues.maximum)").foregroundStyle(.secondary)
        }
    }
}
