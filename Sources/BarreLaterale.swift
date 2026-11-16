// La barre latérale de la carte, la corbeille, et les petits modificateurs de glisser-déposer.
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// La barre latérale, façon Finder : étagère, récents, favoris, emplacements.
/// Un ordinateur du réseau dans la barre latérale : un clic l'ouvre dans le Finder pour s'y connecter.
struct LigneReseau: View {
    let nom: String
    @State private var survol = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "desktopcomputer").foregroundStyle(Color.accentColor).frame(width: 18)
            Text(nom).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Rayon.ligne).fill(survol ? Gris.moyen : .clear))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture { Reseau.shared.ouvrir(nom) }
        .help("Se connecter à « \(nom) » dans le Finder. Une fois connecté, il apparaît ici et se parcourt dans Side.")
        .accessibilityLabel("Se connecter à \(nom)")
        .accessibilityAddTraits(.isButton)
    }
}

struct SidebarView: View {
    @ObservedObject var store: Store
    @ObservedObject var reseau = Reseau.shared
    @ObservedObject var config = Config.shared
    @State private var depotFavori = false
    /// Sections repliées (mémorisées). Les tags sont repliés au départ.
    @State private var repliees: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "sectionsRepliees") ?? ["Tags", "Réseau"])

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                let b = Set(config.barre)
                if b.contains("recents") || b.contains("dossiers") { titre("Récents") }
                if ouverte("Récents") {
                    if b.contains("recents") {
                        LigneBarre(store: store, kind: .recents, nom: String(localized: "Fichiers récents"), symbole: "clock")
                    }
                    if b.contains("dossiers") {
                        LigneBarre(store: store, kind: .dossiers, nom: String(localized: "Dossiers récents"), symbole: "clock.arrow.circlepath")
                    }
                }
                titre("Favoris")
                    .background(RoundedRectangle(cornerRadius: Rayon.ligne).fill(depotFavori ? Color.accentColor.opacity(0.35) : .clear))
                    .modifier(Depot(action: { AppDelegate.shared.ajouterFavoris($0) }, cible: $depotFavori))
                    .help("Clique pour replier. Glisse un dossier ici pour l'ajouter aux favoris.")
                if ouverte("Favoris") {
                    ForEach(store.favoris, id: \.self) { url in
                        LigneBarre(store: store, kind: .folder(url), nom: Fichiers.nom(url), symbole: "folder")
                            .contextMenu { Button("Retirer des favoris") { store.retirerFavori(url) } }
                    }
                }
                titre("Emplacements")
                if ouverte("Emplacements") {
                    if b.contains("icloud") {
                        LigneBarre(store: store, kind: .folder(Fichiers.icloud), nom: "iCloud Drive", symbole: "icloud")
                    }
                    if b.contains("maison") {
                        LigneBarre(store: store, kind: .folder(Fichiers.home), nom: NSUserName(), symbole: "house")
                    }
                    if b.contains("applications") {
                        LigneBarre(store: store, kind: .folder(URL(fileURLWithPath: "/Applications")), nom: String(localized: "Applications"), symbole: "square.grid.3x3")
                    }
                    if b.contains("bureau") {
                        LigneBarre(store: store, kind: .folder(Fichiers.desktop), nom: String(localized: "Bureau"), symbole: "menubar.dock.rectangle")
                    }
                    if b.contains("documents") {
                        LigneBarre(store: store, kind: .folder(Fichiers.documents), nom: String(localized: "Documents"), symbole: "doc")
                    }
                    if b.contains("telechargements") {
                        LigneBarre(store: store, kind: .folder(Fichiers.downloads), nom: String(localized: "Téléchargements"), symbole: "arrow.down.circle")
                    }
                    if b.contains("disques") {
                        ForEach(Fichiers.disques(), id: \.self) { disque in
                            LigneBarre(store: store, kind: .folder(disque), nom: Fichiers.nom(disque),
                                       symbole: Fichiers.estReseau(disque) ? "server.rack" : "externaldrive")
                        }
                    }
                    if b.contains("corbeille") { LigneCorbeille(store: store) }
                }
                if b.contains("reseau") {
                    titre("Réseau")
                    if ouverte("Réseau") {
                        // D'abord les serveurs déjà connectés (on peut les parcourir), puis les ordinateurs repérés.
                        ForEach(Fichiers.disques().filter(Fichiers.estReseau), id: \.self) { serveur in
                            LigneBarre(store: store, kind: .folder(serveur), nom: Fichiers.nom(serveur), symbole: "server.rack")
                        }
                        ForEach(reseau.ordinateurs, id: \.self) { nom in LigneReseau(nom: nom) }
                        if reseau.ordinateurs.isEmpty {
                            Text("Aucun ordinateur repéré").font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                        }
                    }
                }
                if b.contains("tags") { titre("Tags") }
                if b.contains("tags") && ouverte("Tags") {
                    let noms = NSWorkspace.shared.fileLabels, couleurs = NSWorkspace.shared.fileLabelColors
                    ForEach(Array(noms.indices.dropFirst()), id: \.self) { i in
                        LigneBarre(store: store, kind: .tag(noms[i]), nom: noms[i], symbole: "circle.fill",
                                   couleur: i < couleurs.count ? Color(nsColor: couleurs[i]) : nil)
                    }
                }
            }
        }
        .padding(8)
        // La recherche d'ordinateurs ne démarre que si la rubrique Réseau est affichée.
        .onAppear { if config.barre.contains("reseau") { reseau.chercher() } }
        .onChange(of: config.barre) { _, b in if b.contains("reseau") { reseau.chercher() } }
    }

    private func ouverte(_ section: String) -> Bool { !repliees.contains(section) }

    /// Le nom affiché d'une section. Le nom français reste la clé enregistrée des sections repliées.
    private func libelle(_ section: String) -> String {
        switch section {
        case "Récents": return String(localized: "Récents")
        case "Favoris": return String(localized: "Favoris")
        case "Emplacements": return String(localized: "Emplacements")
        case "Réseau": return String(localized: "Réseau")
        case "Tags": return String(localized: "Tags")
        default: return section
        }
    }

    /// Titre de section : un clic la replie ou la déplie, comme dans le Finder.
    private func titre(_ texte: String) -> some View {
        HStack(spacing: 4) {
            Text(libelle(texte)).font(.subheadline).fontWeight(.semibold)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(ouverte(texte) ? 90 : 0))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6).padding(.top, 14).padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Mouvement.bascule) {
                if repliees.contains(texte) { repliees.remove(texte) } else { repliees.insert(texte) }
            }
            UserDefaults.standard.set(Array(repliees), forKey: "sectionsRepliees")
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(ouverte(texte) ? String(localized: "\(libelle(texte)), section ouverte")
                                           : String(localized: "\(libelle(texte)), section repliée"))
    }
}

/// Un raccourci macOS dans la barre latérale : un clic le lance ;
/// déposer des fichiers dessus le lance avec ces fichiers en entrée.
struct LigneRaccourci: View {
    let nom: String
    @ObservedObject var raccourcis = Raccourcis.shared
    @State private var survol = false
    @State private var depot = false

    var body: some View {
        let actif = raccourcis.enCours == nom
        HStack(spacing: 7) {
            Image(systemName: actif ? "hourglass" : "bolt.fill").foregroundStyle(Color.accentColor).frame(width: 18)
            Text(nom).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Rayon.ligne).fill(
            depot ? Color.accentColor.opacity(0.35) : (actif ? Gris.fort : (survol ? Gris.moyen : .clear))))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture { raccourcis.lancer(nom) }
        .onDrop(of: [UTType.fileURL], isTargeted: $depot) { fournisseurs in
            AppDelegate.shared.lancerRaccourci(nom, fournisseurs)
            return true
        }
        .help("Lancer « \(nom) ». Dépose un fichier pour le lui passer.")
        .accessibilityAddTraits(.isButton)
    }
}

/// L'historique du copier-coller : un clic recopie l'élément, on peut aussi le glisser ailleurs.
struct PressePapiersView: View {
    @ObservedObject var presse = PressePapiers.shared
    var filtre = ""
    var apresCopie: (() -> Void)?
    @State private var copie: UUID?

    private var visibles: [Copie] {
        let f = filtre.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return presse.tries }
        return presse.tries.filter { !$0.secret && apercu($0).localizedCaseInsensitiveContains(f) }
    }

    private static let dates: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale.current   // la langue de Side : français ou anglais
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        if presse.elements.isEmpty {
            Text("Ce que tu copies apparaîtra ici.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibles.isEmpty {
            Text("Aucun résultat").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(visibles) { ligne($0) }
                }
                .padding(6)
            }
        }
    }

    private func ligne(_ c: Copie) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Group {
                if let image = c.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: Rayon.ligne))
                } else if let fichier = c.fichiers.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: fichier.path)).resizable().frame(width: 28, height: 28)
                } else {
                    Image(systemName: c.secret ? "key.fill" : "text.alignleft").foregroundStyle(.secondary).frame(width: 28, height: 28)
                }
            }
            .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(apercu(c)).lineLimit(2).truncationMode(.tail)
                Text(copie == c.id ? String(localized: "Copié — prêt à coller") : Self.dates.localizedString(for: c.date, relativeTo: Date()))
                    .font(.caption).foregroundStyle(copie == c.id ? Color.accentColor : .secondary)
            }
            Spacer(minLength: 0)
            if c.epingle { Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.accentColor).padding(.top, 3) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Rayon.ligne).fill(copie == c.id ? Color.accentColor.opacity(0.18) : Gris.leger))
        .contentShape(Rectangle())
        .onTapGesture {
            presse.recopier(c)
            copie = c.id
            // Le temps de lire « Copié », puis la liste se referme.
            DispatchQueue.main.asyncAfter(deadline: .now() + (apresCopie == nil ? 1.5 : 0.6)) {
                if copie == c.id { copie = nil; apresCopie?() }
            }
        }
        .onDrag {
            if let fichier = c.fichiers.first { return NSItemProvider(object: fichier as NSURL) }
            if let image = c.image { return NSItemProvider(object: image) }
            return NSItemProvider(object: (c.texte ?? "") as NSString)
        }
        .contextMenu {
            Button("Copier") { presse.recopier(c) }
            if c.secret {
                // Un mot de passe ne s'épingle pas : il serait écrit sur le disque.
            } else {
                Button(c.epingle ? "Désépingler" : "Épingler en haut de la liste") { presse.epingler(c) }
            }
            Button("Supprimer de l'historique") { presse.supprimer(c) }
            Divider()
            Button("Effacer l'historique (sauf les épinglés)") { presse.vider() }
        }
        .help("Clic : recopier. Clic droit : épingler. On peut aussi le glisser ailleurs.")
    }

    private func apercu(_ c: Copie) -> String {
        if c.secret { return String(localized: "••••••••••  (mot de passe)") }
        if !c.fichiers.isEmpty {
            let noms = c.fichiers.map { FileManager.default.displayName(atPath: $0.path) }
            return noms.count == 1 ? noms[0] : String(localized: "\(noms.count) fichiers : \(noms.prefix(3).joined(separator: ", "))")
        }
        if c.image != nil { return String(localized: "Image") }
        return (c.texte ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Toute fenêtre d'avertissement ou de choix de fichier de Side doit apparaître DEVANT la carte, le panneau du bas et leurs
/// menus, jamais derrière : ils flottent au-dessus des fenêtres ordinaires, et une alerte ordinaire resterait cachée dessous.
enum Devant {
    /// Au-dessus de tout ce que Side affiche (carte, mini-Dock, panneau du bas, listes).
    static let niveau = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 6)

    /// Affiche l'alerte devant tout le reste et attend la réponse.
    @discardableResult
    static func alerte(_ a: NSAlert) -> NSApplication.ModalResponse {
        a.window.level = niveau
        NSApp.activate(ignoringOtherApps: true)
        remonter(a.window)
        return a.runModal()
    }

    /// Affiche un panneau d'ouverture ou d'enregistrement devant tout le reste et attend la réponse.
    static func panneau(_ p: NSSavePanel) -> NSApplication.ModalResponse {
        p.level = niveau
        NSApp.activate(ignoringOtherApps: true)
        remonter(p)
        return p.runModal()
    }

    /// En lançant une fenêtre modale, macOS lui remet son propre niveau (celui des fenêtres modales), plus bas que la carte
    /// et le tiroir de Side : elle passait derrière (16/11/2026). On la remonte une fois affichée.
    private static func remonter(_ w: NSWindow) {
        RunLoop.main.perform(inModes: [.modalPanel, .common]) {
            w.level = niveau
            w.orderFrontRegardless()
        }
    }
}

/// La corbeille s'affiche dans la carte, comme un dossier. macOS ne laisse une application lire son contenu que si elle a
/// l'« Accès complet au disque » : sans lui, Side l'explique et propose d'ouvrir le bon réglage.
enum Corbeille {
    static var dossier: URL? { FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first }

    static var lisible: Bool {
        guard let d = dossier else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: d.path)) != nil
    }

    /// Ce dossier est-il la corbeille ?
    static func est(_ u: URL) -> Bool { dossier.map { $0.standardizedFileURL.path == u.standardizedFileURL.path } ?? false }

    /// Vide la corbeille, après confirmation : la suppression est définitive.
    static func vider() {
        guard let d = dossier, let elements = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) else { return }
        let aSupprimer = elements.filter { $0.lastPathComponent != ".DS_Store" }
        guard !aSupprimer.isEmpty else { NSSound.beep(); return }
        let alerte = NSAlert()
        alerte.alertStyle = .warning
        alerte.messageText = String(localized: "Vider la corbeille ?")
        alerte.informativeText = aSupprimer.count == 1
            ? String(localized: "L'élément qu'elle contient sera supprimé définitivement. Cette action est irréversible.")
            : String(localized: "Les \(aSupprimer.count) éléments qu'elle contient seront supprimés définitivement. Cette action est irréversible.")
        alerte.addButton(withTitle: String(localized: "Vider la corbeille"))
        alerte.addButton(withTitle: String(localized: "Annuler"))
        guard Devant.alerte(alerte) == .alertFirstButtonReturn else { return }
        // En arrière-plan : une grosse corbeille figerait Side (et le défilement de tout le Mac) le temps de la vider.
        DispatchQueue.global(qos: .userInitiated).async {
            var rates = 0
            for u in aSupprimer { do { try FileManager.default.removeItem(at: u) } catch { rates += 1 } }
            DispatchQueue.main.async {
                if rates > 0 { NSSound.beep() }
                AppDelegate.shared.store.reloadAll()
            }
        }
    }

    /// Affiche la corbeille dans la carte (qui doit être ouverte), ou explique pourquoi ce n'est pas possible.
    static func montrer() {
        guard let d = dossier else { return }
        if lisible { AppDelegate.shared.store.naviguer(.folder(d)); return }
        let alerte = NSAlert()
        alerte.messageText = String(localized: "Side n'a pas le droit de lire la corbeille")
        alerte.informativeText = String(localized: "macOS réserve le contenu de la corbeille aux applications qui ont l'« Accès complet au disque ». Ouvre le réglage, active Side dans la liste, puis relance Side : la corbeille s'affichera dans la carte.")
        alerte.addButton(withTitle: String(localized: "Ouvrir le réglage"))
        alerte.addButton(withTitle: String(localized: "Plus tard"))
        if Devant.alerte(alerte) == .alertFirstButtonReturn,
           let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(u)
        }
    }
}

/// La corbeille, dans la barre latérale : un clic l'affiche dans la carte.
struct LigneCorbeille: View {
    @ObservedObject var store: Store
    @State private var survol = false

    var body: some View {
        let actif = Corbeille.dossier.map { store.courante == .folder($0) } ?? false
        HStack(spacing: 7) {
            Image(systemName: "trash").foregroundStyle(Color.accentColor).frame(width: 18)
            Text("Corbeille").lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Rayon.ligne).fill(
            actif ? Gris.fort : (survol ? Gris.moyen : .clear)))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture { Corbeille.montrer() }
        .help("Afficher la corbeille")
    }
}

struct LigneBarre: View {
    @ObservedObject var store: Store
    let kind: Column.Kind
    let nom: String
    let symbole: String
    var couleur: Color?
    @State private var survol = false
    @State private var depot = false

    private var dossier: URL? { if case .folder(let u) = kind { return u } else { return nil } }

    var body: some View {
        let actif = store.courante == kind
        HStack(spacing: 7) {
            Image(systemName: symbole).foregroundStyle(couleur ?? Color.accentColor)
                .font(couleur == nil ? .body : .system(size: 11)).frame(width: 18)
            Text(nom).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Rayon.ligne).fill(
            depot ? Color.accentColor.opacity(0.35)
                : (actif ? Gris.fort : (survol ? Gris.moyen : .clear))))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture { store.naviguer(kind) }
        .modifier(Glissable(kind: kind))   // on peut emmener le dossier ailleurs (bouton +, autre app…)
        // Déposer un fichier sur un dossier de la barre le range dedans, comme dans le Finder.
        .modifier(Depot(action: dossier.map { d in { AppDelegate.shared.deposer($0, dans: d) } }, cible: $depot))
        .help(nom)
    }
}

/// Rend une ligne de la barre latérale glissable : un dossier part comme un vrai dossier,
/// les autres entrées (Récents, Tags) comme un repère que seul le bouton « + » comprend.
struct Glissable: ViewModifier {
    static let prefixe = "side-entree:"
    let kind: Column.Kind
    func body(content: Content) -> some View {
        content.onDrag {
            if case .folder(let url) = kind { return NSItemProvider(object: url as NSURL) }
            return NSItemProvider(object: (Glissable.prefixe + kind.code) as NSString)
        }
    }
}

/// En position libre, tirer l'en-tête de la grande zone déplace la carte, comme une fenêtre du Finder.
struct Deplacable: ViewModifier {
    let actif: Bool
    func body(content: Content) -> some View {
        if actif {
            content.gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in AppDelegate.shared.deplacerCarte() }
                .onEnded { _ in AppDelegate.shared.finDeplacement() })
        } else {
            content
        }
    }
}

/// Permet de réorganiser les colonnes épinglées en glissant leur titre.
struct Reorganisable: ViewModifier {
    let column: Column
    let store: Store
    let actif: Bool

    func body(content: Content) -> some View {
        if actif {
            content
                .onDrag {
                    store.glissee = column
                    return NSItemProvider(object: "side-colonne" as NSString)
                }
                .onDrop(of: [UTType.utf8PlainText], delegate: DeplacementColonne(cible: column, store: store))
                .help("Glisse le titre pour déplacer la colonne")
        } else {
            content
        }
    }
}
