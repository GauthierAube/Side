// Les quatre parties de Side (13/11/2026) : le Finder, le plein écran (grille, carrousel, fenêtres agrandies), le tiroir et
// le presse-papiers. Chacune s'active ou se coupe dans Réglages > Général, selon ce dont chacun a besoin. Chacune a aussi sa
// couleur et son symbole, repris dans la barre latérale et en tête de ses réglages, pour savoir d'un coup d'œil où l'on est.
import SwiftUI

enum Partie: String, CaseIterable, Identifiable {
    case finder, pleinEcran, tiroir, presse
    var id: String { rawValue }

    private var cle: String { "partie." + rawValue }

    /// La partie est-elle activée ? (Toutes le sont au départ.)
    var active: Bool {
        get { UserDefaults.standard.object(forKey: cle) as? Bool ?? true }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: cle)
            NotificationCenter.default.post(name: Partie.changement, object: self)
        }
    }
    static let changement = Notification.Name("SidePartieChangee")

    var nom: String {
        switch self {
        case .finder: return "Finder"
        case .pleinEcran: return String(localized: "Plein écran")
        case .tiroir: return String(localized: "Tiroir")
        case .presse: return String(localized: "Presse-papiers")
        }
    }
    var description: String {
        switch self {
        case .finder: return String(localized: "Tes fichiers par-dessus n'importe quelle application, et les zones de dépôt.")
        case .pleinEcran: return String(localized: "Tes applications de travail en grand : la grille, le carrousel, les numéros.")
        case .tiroir: return String(localized: "Les petites applications et la musique, une à la fois.")
        case .presse: return String(localized: "Tout ce que tu as copié, et les liens que tu gardes.")
        }
    }
    var symbole: String {
        switch self {
        case .finder: return "folder.fill"
        case .pleinEcran: return "macwindow"
        case .tiroir: return "rectangle.bottomthird.inset.filled"
        case .presse: return "doc.on.clipboard.fill"
        }
    }
    var couleur: Color {
        switch self {
        case .finder: return .blue
        case .pleinEcran: return .orange
        case .tiroir: return .pink
        case .presse: return .yellow
        }
    }
}

/// L'étiquette d'une partie : son symbole sur sa couleur, et son nom.
struct EtiquettePartie: View {
    let partie: Partie
    var petite = false
    var body: some View {
        HStack(spacing: petite ? 5 : 7) {
            Image(systemName: partie.symbole)
                .font(.system(size: petite ? 9 : 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: petite ? 16 : 20, height: petite ? 16 : 20)
                .background(RoundedRectangle(cornerRadius: petite ? 4 : 5, style: .continuous).fill(partie.couleur.gradient))
            Text(partie.nom).font(petite ? .caption.weight(.semibold) : .callout.weight(.semibold))
                .foregroundStyle(partie.couleur == .yellow ? Color.orange : partie.couleur)
        }
    }
}

/// Réglages > Général : les quatre parties, à activer ou non.
struct SectionParties: View {
    @State private var etats: [Partie: Bool] = Dictionary(uniqueKeysWithValues: Partie.allCases.map { ($0, $0.active) })

    var body: some View {
        Section {
            ForEach(Partie.allCases) { p in
                Toggle(isOn: Binding(get: { etats[p] ?? true }, set: { etats[p] = $0; p.active = $0 })) {
                    HStack(spacing: 10) {
                        Image(systemName: p.symbole)
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(p.couleur.gradient))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.nom)
                            Text(p.description).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: { Text("Les parties de Side") } footer: {
            Text("Une partie coupée ne s'ouvre plus : ni par son coin, ni par son raccourci, ni par son geste. Ses réglages restent là pour le jour où tu la rallumes.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
