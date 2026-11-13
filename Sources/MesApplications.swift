// « Mes applications » (13/11/2026) : une liste numérotée de 1 à 9, réglée une fois pour toutes. Safari en 1, Claude en 2,
// Mail en 3… Chaque application garde son numéro : sa case dans la grille, sa place dans le carrousel, son raccourci
// (⌘ + chiffre). Au lancement de Side, celles qui ne sont pas ouvertes s'ouvrent, et tout est prêt pour travailler.
// La liste peut être partagée entre plusieurs Mac par un petit fichier dans iCloud Drive.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MonApp: Codable, Equatable, Identifiable, Hashable {
    var bundle: String
    var nom: String
    var id: String { bundle }
}

final class MesApps: ObservableObject {
    static let commun = MesApps()
    static let maximum = 9

    @Published var liste: [MonApp] = [] {
        didSet { guard liste != oldValue, !enLecture else { return }; enregistrer() }
    }
    @Published var ouvrirAuLancement: Bool = true {
        didSet { guard ouvrirAuLancement != oldValue, !enLecture else { return }; enregistrer() }
    }
    @Published var partage: Bool = false {
        didSet {
            guard partage != oldValue else { return }
            UserDefaults.standard.set(partage, forKey: "mesAppsPartage")
            // Partage activé : si un autre Mac a déjà déposé sa liste, on la reprend ; sinon on dépose la nôtre.
            if partage { if !lireICloud() { ecrireICloud() } }
        }
    }
    @Published private(set) var etatPartage = ""
    private var enLecture = false
    private var dernierFichier: Date?
    private var veille: Timer?

    /// Les identifiants des applications, dans l'ordre de leurs numéros.
    var bundles: [String] { liste.map(\.bundle) }

    private init() {
        let d = UserDefaults.standard
        enLecture = true
        if let data = d.data(forKey: "mesApps"), let l = try? JSONDecoder().decode([MonApp].self, from: data) { liste = l }
        ouvrirAuLancement = d.object(forKey: "mesAppsOuvrir") as? Bool ?? true
        partage = d.bool(forKey: "mesAppsPartage")
        enLecture = false
    }

    // MARK: Enregistrement, sur ce Mac et dans iCloud Drive

    private func enregistrer() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(liste) { d.set(data, forKey: "mesApps") }
        d.set(ouvrirAuLancement, forKey: "mesAppsOuvrir")
        if partage { ecrireICloud() }
    }

    /// Le dossier d'iCloud Drive (s'il est activé sur ce Mac).
    static var dossierICloud: URL? {
        let racine = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        guard FileManager.default.fileExists(atPath: racine.path) else { return nil }
        return racine.appendingPathComponent("Side", isDirectory: true)
    }
    static var fichierICloud: URL? { dossierICloud?.appendingPathComponent("Mes applications.json") }

    private struct Partage: Codable { var applications: [MonApp]; var ouvrirAuLancement: Bool }

    private func ecrireICloud() {
        guard let dossier = Self.dossierICloud, let fichier = Self.fichierICloud else {
            etatPartage = String(localized: "iCloud Drive n'est pas activé sur ce Mac.")
            return
        }
        do {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(Partage(applications: liste, ouvrirAuLancement: ouvrirAuLancement)).write(to: fichier, options: .atomic)
            dernierFichier = (try? fichier.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            etatPartage = String(localized: "Partagé dans iCloud Drive, dossier Side.")
        } catch {
            etatPartage = String(localized: "Impossible d'écrire dans iCloud Drive.")
        }
    }

    /// Reprend la liste déposée par un autre Mac, si elle a changé depuis la dernière fois. Vrai si un fichier existe.
    @discardableResult
    func lireICloud() -> Bool {
        guard partage, let fichier = Self.fichierICloud else { return false }
        // Un fichier pas encore descendu d'iCloud : on demande à macOS de le télécharger, il sera lu au prochain passage.
        if !FileManager.default.fileExists(atPath: fichier.path) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: fichier)
            return false
        }
        let date = (try? fichier.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let date, let dernierFichier, date <= dernierFichier { return true }
        guard let data = try? Data(contentsOf: fichier), let p = try? JSONDecoder().decode(Partage.self, from: data) else { return true }
        dernierFichier = date
        enLecture = true
        if p.applications != liste { liste = p.applications }
        if p.ouvrirAuLancement != ouvrirAuLancement { ouvrirAuLancement = p.ouvrirAuLancement }
        enLecture = false
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(liste) { d.set(data, forKey: "mesApps") }
        d.set(ouvrirAuLancement, forKey: "mesAppsOuvrir")
        etatPartage = String(localized: "Partagé dans iCloud Drive, dossier Side.")
        return true
    }

    // MARK: Au lancement de Side

    /// Reprend la liste partagée, puis ouvre les applications de la liste qui ne le sont pas encore (sans voler la main).
    func demarrer() {
        lireICloud()
        guard Partie.pleinEcran.active else { return }
        // Un autre Mac peut changer la liste pendant que Side tourne : on y jette un œil de temps en temps.
        veille = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.lireICloud() }
        guard ouvrirAuLancement, !liste.isEmpty else { return }
        let ouvertes = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let aOuvrir = liste.filter { !ouvertes.contains($0.bundle) }
        for (i, a) in aOuvrir.enumerated() {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: a.bundle) else { continue }
            // Les unes après les autres, dans l'ordre des numéros : chacune prend sa case.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + Double(i) * 0.8) {
                let c = NSWorkspace.OpenConfiguration()
                c.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: c, completionHandler: nil)
            }
        }
    }

    // MARK: Modifier la liste

    func ajouter(_ url: URL) {
        guard liste.count < Self.maximum, let b = Bundle(url: url)?.bundleIdentifier, !bundles.contains(b) else { return }
        liste.append(MonApp(bundle: b, nom: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")))
    }

    /// Ouvre la fenêtre de choix d'une application (dans le dossier Applications).
    func choisir() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]
        p.allowsMultipleSelection = true
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.prompt = String(localized: "Ajouter")
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK { p.urls.forEach(ajouter) }
    }
}

/// La section « Mes applications » des réglages du plein écran.
struct MesAppsSection: View {
    @ObservedObject var m = MesApps.commun
    /// La ligne qu'on est en train de glisser, et de combien (en points, vers le bas).
    @State private var tenue: String?
    @State private var decalage: CGFloat = 0
    @State private var hauteurLigne: CGFloat = 44

    var body: some View {
        Section {
            if m.liste.isEmpty {
                Text("Aucune application pour l'instant. Ajoute celles avec qui tu travailles tous les jours.").foregroundStyle(.secondary)
            }
            ForEach(Array(m.liste.enumerated()), id: \.element.id) { i, a in
                HStack(spacing: 10) {
                    Text("\(i + 1)").font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                    Image(nsImage: icone(a)).resizable().frame(width: 22, height: 22)
                    Text(a.nom)
                    Spacer()
                    Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).help("Glisse pour changer le numéro")
                    Button { m.liste.removeAll { $0.id == a.id } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).help("Retirer de la liste")
                }
                .contentShape(Rectangle())
                .background(GeometryReader { g in Color.clear.onAppear { hauteurLigne = max(30, g.size.height + 1) } })
                // Glisser une ligne vers le haut ou le bas : elle suit la souris, et prend la place où on la lâche.
                .offset(y: tenue == a.id ? decalage : 0)
                .zIndex(tenue == a.id ? 1 : 0)
                .opacity(tenue == a.id ? 0.85 : 1)
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { v in tenue = a.id; decalage = v.translation.height }
                    .onEnded { v in
                        let sauts = Int((v.translation.height / hauteurLigne).rounded())
                        let vers = min(max(i + sauts, 0), m.liste.count - 1)
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            if vers != i { m.liste.move(fromOffsets: IndexSet(integer: i), toOffset: vers > i ? vers + 1 : vers) }
                            tenue = nil; decalage = 0
                        }
                    })
            }
            HStack {
                Button("Ajouter une application…") { m.choisir() }.disabled(m.liste.count >= MesApps.maximum)
                Spacer()
            }
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: nil) { fournisseurs in
                for f in fournisseurs {
                    _ = f.loadObject(ofClass: URL.self) { url, _ in
                        if let url, url.pathExtension == "app" { DispatchQueue.main.async { m.ajouter(url) } }
                    }
                }
                return true
            }
            Toggle("Ouvrir ces applications au lancement de Side", isOn: $m.ouvrirAuLancement)
            Toggle("Partager entre mes Mac (iCloud Drive)", isOn: $m.partage)
            if m.partage, !m.etatPartage.isEmpty {
                Text(m.etatPartage).font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text("Mes applications") } footer: {
            Text("Chaque application garde son numéro : sa case dans la grille, sa place dans le carrousel et son raccourci (par exemple ⌘ 1 pour la première). Glisse une ligne vers le haut ou le bas pour changer son numéro — ou réorganise la grille elle-même, c'est retenu ici aussi. Tu peux aussi déposer une application depuis le Finder sur « Ajouter ». Si une application n'est pas ouverte, son raccourci l'ouvre.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func icone(_ a: MonApp) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: a.bundle) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
