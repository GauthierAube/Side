// La fenêtre des réglages (façon Réglages Système) et ses volets.
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Les volets de la fenêtre de réglages, rangés comme les Réglages Système : d'abord ce qui vaut pour tout Side,
/// puis les façons d'ouvrir, puis chacune des deux parties de Side : le Finder (la carte) et le tiroir du bas.
enum Volet: String, CaseIterable, Identifiable {
    /// Volet affiché à l'ouverture des réglages (« --volet nom » le choisit, pour les tests).
    static var depart: Volet {
        let a = CommandLine.arguments
        if let v = demande { demande = nil; return v }
        return a.firstIndex(of: "--volet").flatMap { $0 + 1 < a.count ? Volet(rawValue: a[$0 + 1]) : nil } ?? .general
    }
    /// Volet demandé (le plein écran renvoie ici, à sa rubrique ou à celle des coins actifs).
    static var demande: Volet?
    /// Rouvre la fenêtre des réglages directement sur ce volet.
    static func demandeDirecte(_ v: Volet) {
        AppDelegate.shared.fermerReglages()
        demande = v
        AppDelegate.shared.ouvrirReglages()
    }
    /// La rubrique correspondante des réglages du plein écran.
    var pleinEcran: VoletReglages? {
        switch self {
        case .grille: return .grille
        case .dock: return .dock
        case .carrousel: return .gestes
        case .fenetres: return .fenetres
        default: return nil
        }
    }
    case general, coins, clavier, gestes, apparence, fermeture, fichiers, colonnes, depot, tiroir, multimedia, applications, presse
    case grille, dock, carrousel, fenetres          // le plein écran (ex-Square)
    var id: String { rawValue }

    /// Les rubriques de la barre latérale, avec leur intitulé.
    static let groupes: [(String?, [Volet])] = [
        (nil, [.general]),
        (String(localized: "Ouvrir et fermer"), [.coins, .clavier, .gestes]),
        ("Finder", [.apparence, .fermeture, .fichiers, .colonnes, .depot]),
        (String(localized: "Plein écran"), [.grille, .dock, .carrousel, .fenetres]),   // les applications de travail (ex-Square)
        (String(localized: "Tiroir"), [.tiroir, .multimedia, .applications]),     // le second panneau de Side, au bord opposé au Finder
        (String(localized: "Presse-papiers"), [.presse]),                         // le volet de droite : historique et liens enregistrés
    ]

    var titre: String {
        switch self {
        case .general: return String(localized: "Général")
        case .coins: return String(localized: "Coins actifs")
        case .clavier: return String(localized: "Raccourcis clavier")
        case .gestes: return String(localized: "Souris et trackpad")
        case .apparence: return String(localized: "Apparence")
        case .fermeture: return String(localized: "Fermeture")
        case .fichiers: return String(localized: "Barre latérale et fichiers")
        case .colonnes: return String(localized: "Dossiers et colonnes")
        case .depot: return String(localized: "Zones de dépôt")
        case .tiroir: return String(localized: "Ouverture et fermeture")
        case .multimedia: return String(localized: "Multimédia")
        case .applications: return String(localized: "Applications")
        case .presse: return String(localized: "Historique et liens")
        case .grille: return String(localized: "Grille")
        case .dock: return String(localized: "Dock")
        case .carrousel: return String(localized: "Carrousel")
        case .fenetres: return String(localized: "Fenêtres")
        }
    }
    /// Une phrase sous le titre du volet, pour dire de quoi il s'agit.
    var resume: String {
        switch self {
        case .general: return String(localized: "Ce qui vaut pour tout Side.")
        case .coins: return String(localized: "Amener le pointeur dans un coin de l'écran ouvre le Finder, le tiroir ou le presse-papiers.")
        case .clavier: return String(localized: "Un raccourci pour le Finder, le tiroir et le presse-papiers.")
        case .gestes: return String(localized: "Ouvrir le Finder et le tiroir d'un geste, à la souris ou au trackpad.")
        case .apparence: return String(localized: "Le Finder de Side : d'où il arrive, sa taille, son fond.")
        case .fermeture: return String(localized: "Quand le Finder de Side se referme.")
        case .fichiers: return String(localized: "Ce que le Finder de Side affiche, et comment.")
        case .colonnes: return String(localized: "Le dossier de départ et les colonnes épinglées du Finder de Side.")
        case .depot: return String(localized: "Les zones où poser des fichiers en attente, à côté du Finder de Side.")
        case .tiroir: return String(localized: "Le tiroir, second panneau de Side.")
        case .multimedia: return String(localized: "Musique et vidéo, au début du tiroir.")
        case .applications: return String(localized: "Les applications rangées dans le tiroir.")
        case .presse: return String(localized: "Le volet de droite : ce que tu as copié, et les liens que tu gardes.")
        case .grille: return String(localized: "Toutes tes applications de travail en vignettes, pour passer de l'une à l'autre.")
        case .dock: return String(localized: "Le Dock affiché dans la grille.")
        case .carrousel: return String(localized: "Quatre doigts vers la gauche ou la droite, pour passer d'une application de travail à l'autre.")
        case .fenetres: return String(localized: "Les applications de travail remplissent l'écran, sans le plein écran d'Apple.")
        }
    }
    /// La partie de Side dont ce volet fait partie (aucune pour les réglages communs).
    var partie: Partie? {
        switch self {
        case .apparence, .fermeture, .fichiers, .colonnes, .depot: return .finder
        case .grille, .dock, .carrousel, .fenetres: return .pleinEcran
        case .tiroir, .multimedia, .applications: return .tiroir
        case .presse: return .presse
        default: return nil
        }
    }
    var symbole: String {
        switch self {
        case .general: return "gearshape.fill"
        case .coins: return "rectangle.inset.topleft.filled"
        case .clavier: return "keyboard.fill"
        case .gestes: return "hand.draw.fill"
        case .apparence: return "paintbrush.fill"
        case .fermeture: return "xmark"
        case .fichiers: return "folder.fill"
        case .colonnes: return "rectangle.split.3x1.fill"
        case .depot: return "tray.and.arrow.down.fill"
        case .tiroir: return "rectangle.bottomthird.inset.filled"
        case .multimedia: return "play.rectangle.fill"
        case .applications: return "square.grid.2x2.fill"
        case .presse: return "doc.on.clipboard.fill"
        case .grille: return "square.grid.2x2.fill"
        case .dock: return "dock.rectangle"
        case .carrousel: return "rectangle.stack.fill"
        case .fenetres: return "macwindow"
        }
    }
    var couleur: Color {
        switch self {
        case .general: return .gray
        case .coins: return .blue
        case .clavier: return .indigo
        case .gestes: return .teal
        case .apparence: return .purple
        case .fermeture: return .red
        case .fichiers: return .cyan
        case .colonnes: return .orange
        case .depot: return .green
        case .tiroir: return .pink
        case .multimedia: return .red
        case .applications: return .mint
        case .presse: return .yellow
        case .grille: return .blue
        case .dock: return .green
        case .carrousel: return .orange
        case .fenetres: return .purple
        }
    }
}

struct ReglagesView: View {
    @ObservedObject var config = Config.shared
    @ObservedObject var store = AppDelegate.shared.store
    @ObservedObject var tiroir = ConfigTiroir.commun
    @State private var volet: Volet = Volet.depart
    @State private var parties = 0          // change quand une partie est activée ou coupée : la barre latérale se redessine
    @State private var demarrage = SMAppService.mainApp.status == .enabled
    @State private var ecoute = false

    var body: some View {
        HStack(spacing: 0) {
            // La barre latérale défile quand elle ne tient pas en hauteur, et commence sous les boutons de la fenêtre
            // (rouge, jaune, vert), comme dans les Réglages Système.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(Volet.groupes.enumerated()), id: \.offset) { _, groupe in
                        // Chaque partie de Side a son en-tête à sa couleur ; ses volets en reprennent la couleur.
                        if let partie = groupe.1.first?.partie {
                            HStack(spacing: 6) {
                                EtiquettePartie(partie: partie, petite: true)
                                if !partie.active {
                                    Text("désactivé").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.leading, 8).padding(.top, 16).padding(.bottom, 3)
                        } else if let nom = groupe.0 {
                            Text(nom).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.leading, 8).padding(.top, 12).padding(.bottom, 2)
                        }
                        ForEach(groupe.1) { ligne($0) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            // Pas de marge automatique sous la barre de titre : la barre latérale commence exactement sous les boutons.
            .contentMargins(.top, 0, for: .scrollContent)
            .ignoresSafeArea(.container, edges: .top)
            .padding(.top, 50)
            .frame(width: 230)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(ZStack {
                Color(nsColor: .windowBackgroundColor)
                Gris.leger
            })
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                // En tête du volet : la partie de Side où l'on est, à sa couleur.
                if let partie = volet.partie {
                    HStack(spacing: 8) {
                        EtiquettePartie(partie: partie)
                        if !partie.active {
                            Text("— désactivé").font(.callout).foregroundStyle(.secondary)
                            Button("Activer") { partie.active = true }.controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 26).padding(.top, 14)
                }
                Text(volet.titre).font(.title2.weight(.semibold))
                    .padding(.horizontal, 26).padding(.top, volet.partie == nil ? 16 : 4)
                Text(volet.resume).font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 26).padding(.top, 2).padding(.bottom, 2)
                Form { contenu }
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)   // remplit toute la fenêtre
        .ignoresSafeArea()
        .id(parties)
        .onReceive(NotificationCenter.default.publisher(for: Partie.changement)) { _ in parties += 1 }
    }

    private func ligne(_ v: Volet) -> some View {
        let choisi = v == volet
        return HStack(spacing: 9) {
            Image(systemName: v.symbole)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: Rayon.ligne, style: .continuous).fill((v.partie?.couleur ?? v.couleur).gradient))
                .opacity(v.partie?.active == false ? 0.45 : 1)
            Text(v.titre).foregroundStyle(v.partie?.active == false ? Color.secondary : Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Rayon.vignette, style: .continuous)
            .fill(choisi ? Gris.fort : .clear))
        .contentShape(Rectangle())
        .onTapGesture { volet = v }
        .accessibilityAddTraits(choisi ? [.isButton, .isSelected] : .isButton)
    }

    private func pourcent(_ x: Double) -> String { String(localized: "\(Int((x * 100).rounded())) %") }

    private func curseur(_ titre: LocalizedStringKey, _ valeur: Binding<Double>, _ plage: ClosedRange<Double>, _ texte: String) -> some View {
        LabeledContent(titre) {
            HStack {
                Slider(value: valeur, in: plage).frame(width: 190)
                Text(texte).monospacedDigit().foregroundStyle(.secondary).frame(width: 84, alignment: .trailing)
            }
        }
    }

    private func note(_ texte: LocalizedStringKey) -> some View {
        Text(texte).font(.caption).foregroundStyle(.secondary)
    }

    /// Case à cocher d'une entrée de la barre latérale.
    private func entree(_ titre: String, _ symbole: String, _ cle: String) -> some View {
        Toggle(isOn: Binding(
            get: { config.barre.contains(cle) },
            set: { oui in
                if oui { if !config.barre.contains(cle) { config.barre.append(cle) } }
                else { config.barre.removeAll { $0 == cle } }
            })) {
            Label(titre, systemImage: symbole)
        }
    }

    @ViewBuilder private var contenu: some View {
        switch volet {
        case .general:
            SectionParties()
            Section {
                Picker("Langue", selection: Binding(get: { Langue.choisie }, set: { Langue.choisir($0) })) {
                    ForEach(Langue.allCases) { Text($0.nom).tag($0) }
                }
            } header: { Text("Langue") } footer: {
                note("Side redémarre pour changer de langue.")
            }
            SectionCompagnes()
            Section("Présentation") {
                LabeledContent("La visite guidée de Side, en sept étapes") {
                    Button("Revoir la présentation") { AppDelegate.shared.revoirAccueil() }
                }
            }
            Section {
                Toggle("Ouvrir Side à l'ouverture de session", isOn: Binding(
                    get: { demarrage },
                    set: { _ in
                        AppDelegate.shared.basculerDemarrage()
                        demarrage = SMAppService.mainApp.status == .enabled
                    }))
            }
        case .presse:
            ReglagesVoletPresse()
        case .grille, .dock, .carrousel, .fenetres:
            if let v = volet.pleinEcran { ContenuPleinEcran(volet: v) }
        case .coins:
            Section {
                CoinsActifsView()
                curseur("Taille des coins", $config.tailleCoin, 6...120, "\(Int(config.tailleCoin.rounded())) pt")
                    .disabled(config.coin == .aucun && tiroir.coin == .aucun && ConfigPresse.commun.coin == .aucun && ConfigSquare.commun.coin == .aucun)
            } footer: {
                note("Choisis pour chaque coin ce qu'il ouvre : le Finder, le tiroir, le presse-papiers, la grille des applications, ou rien. Revenir dans le coin referme. Si macOS utilise déjà ce coin, désactive-le dans Réglages Système > Bureau et Dock > Coins actifs.")
            }
        case .clavier:
            Section("Finder") {
                LabeledContent("Ouvrir et fermer le Finder") {
                    HStack {
                        Button(ecoute ? String(localized: "Tape le raccourci…")
                               : (config.touche == -1 ? String(localized: "Aucun") : config.libelle)) {
                            ecoute = true
                            AppDelegate.shared.ecouterRaccourci { ecoute = false }
                        }
                        Button("Effacer") { AppDelegate.shared.definirRaccourci(touche: -1, mods: 0, libelle: "Aucun") }
                            .disabled(config.touche == -1)
                    }
                }
            }
            Section {
                RaccourciTiroirLigne()
            } header: { Text("Tiroir") }
            Section {
                LabeledContent("Envoyer l'application de devant au tiroir") { Text(verbatim: "⌃⌥↓").monospaced().foregroundStyle(.secondary) }
                LabeledContent("Passer l'application du tiroir en plein écran") { Text(verbatim: "⌃⌥↑").monospaced().foregroundStyle(.secondary) }
            } header: { Text("Changer de place") } footer: {
                note("Le plus simple : le bouton jaune d'une application l'envoie au tiroir, et le bouton vert d'une application du tiroir la remet en plein écran (Option + clic : le comportement habituel de macOS). Aussi au clic droit sur une case de la grille, et dans la liste du « + » du tiroir.")
            }
            Section {
                RaccourciPresseLigne()
            } header: { Text("Presse-papiers") } footer: {
                note("Clique sur un raccourci, puis tape la nouvelle combinaison : elle doit contenir Commande, Contrôle ou Option. Échap annule. La touche Échap referme toujours le Finder comme le tiroir.")
            }
        case .gestes:
            Section {
                Toggle("Geste de la souris", isOn: $config.secouer)
                Picker("Geste", selection: $config.cercle) {
                    Text("Secouer le pointeur").tag(false)
                    Text("Faire un cercle").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(!config.secouer)
                curseur("Sensibilité", $config.sensibilite, 0...1,
                        config.sensibilite > 0.66 ? String(localized: "Élevée")
                            : (config.sensibilite > 0.33 ? String(localized: "Moyenne") : String(localized: "Faible")))
                    .disabled(!config.secouer)
            } header: { Text("Souris : ouvrir le Finder") } footer: {
                if config.cercle {
                    note("Fais un cercle avec le pointeur, d'un seul mouvement rapide, sans cliquer, pour ouvrir le Finder. Il peut être grossier, petit ou grand, dans un sens ou dans l'autre. Le cercle ne referme pas le Finder : utilise un clic à côté, Échap, le coin ou le raccourci.")
                }
            }
            Section {
                Toggle("Glisser quatre doigts sur le trackpad", isOn: $config.quatreDoigts)
                Picker("Pour ouvrir", selection: $config.sensDoigts) {
                    Text("Vers le bas").tag("bas")
                    Text("Vers le haut").tag("haut")
                    Text("Les deux").tag("deux")
                }
                .pickerStyle(.segmented)
                .disabled(!config.quatreDoigts)
                if config.quatreDoigts {
                    LabeledContent("Gestes de macOS") {
                        Button("Ouvrir les réglages du trackpad") {
                            if let u = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") {
                                NSWorkspace.shared.open(u)
                            }
                        }
                    }
                }
            } header: { Text("Trackpad : ouvrir le Finder") } footer: {
                if config.sensDoigts == "deux" {
                    note("Chaque geste, vers le haut ou vers le bas, ouvre ou ferme le Finder. Attention : macOS utilise déjà ces gestes, vers le haut pour Mission Control et vers le bas pour « Exposé des apps ». Pour que les deux ne se déclenchent pas ensemble, mets-les sur « Désactivé » dans Réglages Système > Trackpad > Autres gestes. Side ne change pas ces réglages lui-même.")
                } else {
                    note("Le geste dans l'autre sens referme le Finder. Attention : macOS utilise déjà ces gestes, vers le haut pour Mission Control et vers le bas pour « Exposé des apps ». Pour que les deux ne se déclenchent pas ensemble, mets-les sur « Désactivé » dans Réglages Système > Trackpad > Autres gestes. Side ne change pas ces réglages lui-même.")
                }
            }
            Section {
                Toggle(String(localized: "Glisser quatre doigts \(ConfigTiroir.sensGeste)"), isOn: $tiroir.quatreDoigts)
                    .disabled(!ConfigTiroir.gestePossible)
            } header: { Text("Trackpad : ouvrir le tiroir") } footer: {
                switch (ConfigTiroir.gestePossible, ConfigTiroir.enHaut) {
                case (true, true):
                    note("Le tiroir arrive du haut de l'écran, à l'opposé du Finder : quatre doigts \(ConfigTiroir.sensGeste) l'ouvrent, dans l'autre sens le referment. Il suit les doigts.")
                case (true, false):
                    note("Le tiroir arrive du bas de l'écran, à l'opposé du Finder : quatre doigts \(ConfigTiroir.sensGeste) l'ouvrent, dans l'autre sens le referment. Il suit les doigts.")
                case (false, true):
                    note("Le tiroir arrive du haut de l'écran : son geste est quatre doigts \(ConfigTiroir.sensGeste). Il n'est libre que si le Finder s'ouvre, lui, avec quatre doigts « Vers le haut ».")
                case (false, false):
                    note("Le tiroir arrive du bas de l'écran : son geste est quatre doigts \(ConfigTiroir.sensGeste). Il n'est libre que si le Finder s'ouvre, lui, avec quatre doigts « Vers le bas ».")
                }
            }
        case .apparence:
            Section("Position et taille") {
                Picker("Le Finder arrive", selection: $config.bord) {
                    ForEach(Bord.allCases, id: \.self) { Text($0.titre).tag($0) }
                }
                .onChange(of: config.bord) { _, b in ConfigTiroir.reglerBord(b) }      // les gestes à quatre doigts suivent
                LabeledContent("Le tiroir arrive") {
                    Text(ConfigTiroir.enHaut ? "Du haut" : "Du bas").foregroundStyle(.secondary)
                }
                note("Le tiroir prend toujours le bord opposé au Finder : du haut quand le Finder vient du bas, du bas dans tous les autres cas. Le geste à quatre doigts s'inverse avec lui.")
                if config.bord == .plein {
                    HStack {
                        note("La carte apparaît au centre. Tire-la par sa barre du haut pour la déplacer : Side retient l'endroit.")
                        Spacer()
                        Button("Recentrer") { AppDelegate.shared.recentrerCarte() }
                    }
                }
                curseur("Hauteur du Finder", $config.tailleHauteur, 0.15...0.9, pourcent(config.tailleHauteur))
                curseur("Largeur (sans les colonnes épinglées)", $config.largeurSeule, 0.35...1, pourcent(config.largeurSeule))
            }
            Section {
                curseur("Opacité", $config.opacite, 0...1, pourcent(config.opacite))
            } header: { Text("Fond") } footer: {
                note("Le même fond flou sert au Finder de Side, au volet du presse-papiers et aux onglets du coin multimédia du tiroir : cette opacité vaut pour tous.")
            }
            Section {
                Toggle("Flouter l'arrière-plan quand le Finder est ouvert", isOn: $config.flou)
                curseur("Intensité", $config.flouForce, 0.3...1, pourcent(config.flouForce))
                    .disabled(!config.flou)
            } header: { Text("Arrière-plan") } footer: {
                note("L'écran derrière la carte s'estompe en fondu. On peut toujours cliquer et glisser des fichiers au travers.")
            }
        case .fermeture:
            Section {
                Picker("Au changement de bureau ou d'app plein écran", selection: $config.suivi) {
                    Text("Fermer, sauf si Commande est maintenue").tag("commande")
                    Text("Toujours rester affichée").tag("toujours")
                    Text("Toujours fermer").tag("jamais")
                }
                Toggle("Fermer d'un clic en dehors", isOn: $config.fermerAuClic)
                Toggle("Fermer quand la souris en sort", isOn: $config.fermerEnSortant)
            } footer: {
                note("Le Finder se ferme toujours avec le raccourci clavier, la touche Échap, une secousse ou en revenant dans le coin actif.")
            }
        case .fichiers:
            Section {
                entree(String(localized: "Fichiers récents"), "clock", "recents")
                entree(String(localized: "Dossiers récents"), "clock.arrow.circlepath", "dossiers")
                entree("iCloud Drive", "icloud", "icloud")
                entree(NSUserName(), "house", "maison")
                entree(String(localized: "Applications"), "square.grid.3x3", "applications")
                entree(String(localized: "Bureau"), "menubar.dock.rectangle", "bureau")
                entree(String(localized: "Documents"), "doc", "documents")
                entree(String(localized: "Téléchargements"), "arrow.down.circle", "telechargements")
                entree(String(localized: "Corbeille"), "trash", "corbeille")
                entree(String(localized: "Disques externes et serveurs connectés"), "externaldrive", "disques")
                entree(String(localized: "Réseau (ordinateurs qui partagent des fichiers)"), "network", "reseau")
                entree(String(localized: "Tags"), "circle.fill", "tags")
            } header: { Text("Afficher dans la barre latérale") } footer: {
                note("Tes favoris se gèrent directement dans la barre : glisse un dossier sur « Favoris » pour l'ajouter, clic droit pour le retirer.")
            }
            Section {
                Picker("Nombre de dossiers récents", selection: $config.nombreDossiers) {
                    ForEach([3, 6, 9, 12, 20, 40], id: \.self) { Text("\($0)").tag($0) }
                }
            } header: { Text("Dossiers récents") } footer: {
                note("La rubrique « Dossiers récents » montre les derniers dossiers où tu as travaillé, en grille.")
            }
            Section("Présentation par icônes") {
                curseur("Taille des icônes", $config.tailleIcones, 32...128,
                        "\(Int(config.tailleIcones.rounded())) × \(Int(config.tailleIcones.rounded()))")
                curseur("Espacement de la grille", $config.espacement, 2...40, "\(Int(config.espacement.rounded())) pt")
                Picker("Taille du texte", selection: $config.tailleTexte) {
                    ForEach([10, 11, 12, 13, 14, 15, 16], id: \.self) { Text("\($0)").tag(Double($0)) }
                }
                Picker("Position du texte", selection: $config.texteADroite) {
                    Text("En bas").tag(false)
                    Text("À droite").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("Afficher les informations", isOn: $config.infos)
                Toggle("Utiliser un aperçu comme icône", isOn: $config.apercus)
            }
            Section("Options avancées") {
                Toggle("Afficher toutes les extensions de fichiers", isOn: $config.extensions)
                Toggle("Laisser les dossiers en haut lors du tri par nom", isOn: $config.dossiersEnHaut)
                Picker("En effectuant une recherche", selection: $config.rechercheMac) {
                    Text("Rechercher sur ce Mac").tag(true)
                    Text("Rechercher dans le dossier affiché").tag(false)
                }
            }
        case .colonnes:
            Section("Grande zone") {
                Picker("Au lancement de Side, afficher", selection: $config.ouverture) {
                    Text("Le dernier dossier consulté").tag("")
                    ForEach(store.favoris, id: \.self) { Text(Fichiers.nom($0)).tag($0.path) }
                }
            }
            Section {
                curseur("Largeur d'une colonne",
                        $config.tailleColonne, 180...700, "\(Int(config.tailleColonne.rounded())) pt")
                Picker("Quand la place manque", selection: $config.ajuster) {
                    Text("Rétrécir pour tout afficher").tag(true)
                    Text("Taille fixe, à faire défiler").tag(false)
                }
            } header: { Text("Colonnes épinglées") } footer: {
                note("Pour épingler un dossier : glisse-le vers le bord droit de la carte, ou utilise le bouton + de la dernière colonne.")
            }
        case .depot:
            Section {
                LabeledContent("Zones affichées", value: "\(store.etageres.count)")
                Toggle("Refermer Side après un dépôt", isOn: $config.fermerApresDepot)
                if config.fermerApresDepot {
                    note("Pour le garder ouvert cette fois-là : maintiens Option (⌥) en lâchant le fichier, ou ramène tout de suite la souris sur la carte.")
                }
                Toggle("Garder les zones remplies à l'écran quand Side est fermé", isOn: $config.depotReste)
                Toggle("Ajouter mes captures d'écran à une zone de dépôt", isOn: $config.capturesAuto)
                if config.capturesAuto {
                    note("Dès qu'une capture d'écran est enregistrée, elle t'attend dans une zone, prête à être glissée ailleurs. Les captures se rangent ensemble dans la même zone.")
                }
            } header: { Text("Zones de dépôt") } footer: {
                note("Une zone apparaît en haut à droite de la carte quand tu fais glisser un fichier. Tant qu'elle contient quelque chose, elle reste à l'écran même quand Side est fermé, pour que tu puisses glisser son contenu ailleurs. Side fermé, secoue le pointeur pendant que tu glisses un fichier : la zone apparaît seule, à côté de la souris. Secoue encore pour en ajouter une autre. Si la carte vient du haut, la zone se place en bas de la carte et les suivantes s'empilent au-dessus. Les zones vides disparaissent toutes seules.")
            }
        case .tiroir:
            SectionsTiroir(partie: .ouverture)
        case .multimedia:
            SectionsTiroir(partie: .multimedia)
        case .applications:
            SectionsTiroir(partie: .applications)
        }
    }
}
