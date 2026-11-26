// Le widget « Side » (écran d'accueil et écran verrouillé) et le bouton du centre de contrôle (26/11/2026).
// Toucher une ligne du widget ouvre Side et copie cet élément.
import SwiftUI
import WidgetKit
import AppIntents

@main
struct Widgets: WidgetBundle {
    var body: some Widget {
        DerniersCopies()
        ControleSide()
    }
}

// MARK: Le bouton du centre de contrôle

struct ControleSide: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "fr.gauthieraube.side-presse.controle") {
            ControlWidgetButton(action: OuvrirSide()) {
                Label("Side", systemImage: "doc.on.clipboard")
            }
        }
        .displayName("Side")
        .description("Ouvre Side et ajoute ce que tu viens de copier.")
    }
}

// MARK: Le widget

struct Entree: TimelineEntry {
    let date: Date
    let elements: [ApercuElement]
}

struct Fournisseur: TimelineProvider {
    func placeholder(in context: Context) -> Entree {
        Entree(date: .now, elements: [
            ApercuElement(id: UUID(), texte: "Un texte copié sur le Mac", vignette: nil, epingle: false),
            ApercuElement(id: UUID(), texte: "https://wakademy.online", vignette: nil, epingle: false),
            ApercuElement(id: UUID(), texte: "Une adresse, un numéro…", vignette: nil, epingle: false),
        ])
    }
    func getSnapshot(in context: Context, completion: @escaping (Entree) -> Void) {
        completion(Entree(date: .now, elements: Apercu.lire()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entree>) -> Void) {
        // Un coup d'œil dans iCloud (ce que les Mac ont copié) ; sinon le dernier aperçu laissé par l'app.
        _ = Stockage.acceder { d -> Bool? in
            guard let h = Stockage.historique(dans: d) else { return nil }
            return Apercu.construire(Stockage.visibles(h), dossier: d)
        }
        let entree = Entree(date: .now, elements: Apercu.lire())
        completion(Timeline(entries: [entree], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct DerniersCopies: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fr.gauthieraube.side-presse.derniers", provider: Fournisseur()) { entree in
            VueWidget(entree: entree).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Side")
        .description("Les derniers éléments copiés. Touche-en un pour le copier.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct VueWidget: View {
    @Environment(\.widgetFamily) private var famille
    let entree: Entree

    var body: some View {
        switch famille {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "doc.on.clipboard").font(.title3)
            }
            .widgetURL(URL(string: "side-presse://ouvrir"))
        case .accessoryInline:
            Label(entree.elements.first?.texte ?? "Side", systemImage: "doc.on.clipboard")
                .widgetURL(entree.elements.first?.lien)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Side", systemImage: "doc.on.clipboard").font(.caption.weight(.semibold))
                Text(entree.elements.first?.texte ?? "Rien de copié").font(.caption).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(entree.elements.first?.lien)
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                entete
                if let e = entree.elements.first { contenu(e, lignes: 5) } else { vide }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(entree.elements.first?.lien ?? URL(string: "side-presse://ouvrir"))
        default:
            let nombre = famille == .systemLarge ? 7 : 3
            VStack(alignment: .leading, spacing: 0) {
                entete.padding(.bottom, 6)
                if entree.elements.isEmpty { vide }
                ForEach(Array(entree.elements.prefix(nombre).enumerated()), id: \.element.id) { i, e in
                    if i > 0 { Divider().padding(.vertical, 5) }
                    Link(destination: e.lien) {
                        contenu(e, lignes: famille == .systemLarge ? 2 : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(URL(string: "side-presse://ouvrir"))
        }
    }

    private var entete: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.on.clipboard")
            Text("Side")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private var vide: some View {
        Text("Rien de copié pour l'instant.").font(.footnote).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func contenu(_ e: ApercuElement, lignes: Int) -> some View {
        HStack(spacing: 6) {
            if e.epingle { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange) }
            if let nom = e.vignette, let url = Apercu.vignette(nom), let i = UIImage(contentsOfFile: url.path) {
                Image(uiImage: i).resizable().scaledToFill()
                    .frame(width: lignes > 2 ? 90 : 36, height: lignes > 2 ? 70 : 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(e.texte ?? "Image").font(lignes > 2 ? .footnote : .subheadline).lineLimit(lignes)
            }
        }
    }
}
