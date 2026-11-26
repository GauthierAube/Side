import SwiftUI
import UniformTypeIdentifiers

@main
struct SideApp: App {
    @StateObject private var presse = Presse()
    var body: some Scene {
        WindowGroup { Racine().environmentObject(presse) }
    }
}

struct Racine: View {
    @EnvironmentObject var presse: Presse
    @Environment(\.scenePhase) private var phase
    @State private var choix = false
    @State private var onglet = 0
    @State private var recherche = ""
    @State private var copie: UUID?
    private let minuterie = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if !presse.choisi { accueil } else if onglet == 0 { historique } else { listeLiens }
            }
            .navigationTitle(onglet == 0 ? "Presse-papiers" : "Liens")
            .toolbar {
                if presse.choisi {
                    ToolbarItem(placement: .principal) {
                        Picker("", selection: $onglet) { Text("Historique").tag(0); Text("Liens").tag(1) }
                            .pickerStyle(.segmented).frame(width: 220)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Changer de dossier", systemImage: "folder") { choix = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .searchable(text: $recherche, prompt: "Rechercher")
            .refreshable { presse.recharger() }
        }
        .fileImporter(isPresented: $choix, allowedContentTypes: [.folder]) { r in
            if case .success(let url) = r { presse.choisir(url) }
        }
        .onChange(of: phase) { _, p in if p == .active { presse.capturer(); presse.recharger() } }
        .onAppear { presse.recharger() }
        .onOpenURL { presse.ouvrir($0) }
        .overlay(alignment: .bottom) {
            if let a = presse.annonce {
                Text(a).font(.subheadline.weight(.medium)).lineLimit(1)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24).padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(minuterie) { _ in if phase == .active { presse.recharger() } }
    }

    private var accueil: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Retrouve ici l'historique du presse-papiers de Side.").font(.headline).multilineTextAlignment(.center)
            Text("Choisis une fois le dossier « Side » dans iCloud Drive : c'est là que le Mac range l'historique.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Choisir le dossier Side") { choix = true }.buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private var filtres: [Element] {
        let tous = presse.elements.filter(\.epingle) + presse.elements.filter { !$0.epingle }
        guard !recherche.isEmpty else { return tous }
        return tous.filter { $0.texte?.localizedCaseInsensitiveContains(recherche) ?? false }
    }

    private var historique: some View {
        List {
            Section {
                PasteButton(supportedContentTypes: [.image, .plainText, .text, .url]) { fournisseurs in
                    for f in fournisseurs {
                        if f.canLoadObject(ofClass: UIImage.self) {
                            _ = f.loadObject(ofClass: UIImage.self) { o, _ in
                                if let i = o as? UIImage { Task { @MainActor in presse.ajouter(image: i) } }
                            }
                        } else if f.canLoadObject(ofClass: String.self) {
                            _ = f.loadObject(ofClass: String.self) { o, _ in
                                if let t = o { Task { @MainActor in presse.ajouter(texte: t) } }
                            }
                        }
                    }
                }
                .labelStyle(.titleAndIcon)
            } footer: {
                if !presse.message.isEmpty { Text(presse.message) }
            }
            ForEach(filtres) { e in
                Button { presse.copier(e); copie = e.id; UINotificationFeedbackGenerator().notificationOccurred(.success) } label: {
                    ligne(e)
                }
                .tint(.primary)
                .swipeActions(edge: .trailing) {
                    Button("Effacer", systemImage: "trash", role: .destructive) { presse.effacer(e) }
                }
                .swipeActions(edge: .leading) {
                    Button(e.epingle ? "Désépingler" : "Épingler", systemImage: e.epingle ? "pin.slash" : "pin") { presse.epingler(e) }
                        .tint(.orange)
                }
                .contextMenu {
                    if let t = e.texte { ShareLink(item: t) }
                    Button(e.epingle ? "Désépingler" : "Épingler", systemImage: "pin") { presse.epingler(e) }
                    Button("Effacer", systemImage: "trash", role: .destructive) { presse.effacer(e) }
                }
            }
        }
        .overlay { if presse.elements.isEmpty && presse.message.isEmpty { ProgressView() } }
    }

    private func ligne(_ e: Element) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if let t = e.texte {
                    Text(t).lineLimit(4).font(.body)
                } else if let nom = e.image, let i = presse.image(nom) {
                    Image(uiImage: i).resizable().scaledToFit().frame(maxHeight: 140).clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("Image en cours de téléchargement…").foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    if e.epingle { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                    Text(e.date, format: .relative(presentation: .named))
                    if copie == e.id { Text("· Copié").foregroundStyle(.green) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var listeLiens: some View {
        let filtres = recherche.isEmpty ? presse.liens
            : presse.liens.filter { $0.titre.localizedCaseInsensitiveContains(recherche) || $0.texte.localizedCaseInsensitiveContains(recherche) }
        let groupes = Dictionary(grouping: filtres) { $0.groupe ?? "" }
        let noms = filtres.map { $0.groupe ?? "" }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return List {
            if presse.liens.isEmpty { Text("Aucun lien enregistré dans Side.").foregroundStyle(.secondary) }
            ForEach(noms, id: \.self) { g in
                Section(g) {
                    ForEach(groupes[g] ?? []) { l in
                        Button {
                            presse.copier(l); copie = l.id; UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.titre.isEmpty ? l.texte : l.titre)
                                Text(copie == l.id ? "Copié" : l.texte).font(.caption)
                                    .foregroundStyle(copie == l.id ? .green : .secondary).lineLimit(1)
                            }
                        }
                        .tint(.primary)
                        .contextMenu {
                            if let url = URL(string: l.texte), url.scheme?.hasPrefix("http") == true { Link("Ouvrir", destination: url) }
                            ShareLink(item: l.texte)
                        }
                    }
                }
            }
        }
    }
}
