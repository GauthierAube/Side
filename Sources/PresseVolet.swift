// Le volet du presse-papiers : un panneau étroit qui glisse depuis le bord droit de l'écran, sur toute sa hauteur,
// quand le pointeur va dans un coin (en bas à droite au départ). Chaque élément copié y est une carte, selon sa nature :
// une image se montre, un lien affiche son site, une couleur se voit, un fichier a son icône.
// Les données sont celles de l'historique déjà tenu par Side (`PressePapiers`) : rien de plus n'est gardé.
import AppKit
import SwiftUI
import Carbon.HIToolbox
import LinkPresentation
import Combine

// MARK: - Réglages

final class ConfigPresse: ObservableObject {
    static let commun = ConfigPresse()
    private let d = UserDefaults.standard

    /// Le volet s'ouvre par un coin de l'écran. « Aucun » : le volet ne s'ouvre pas tout seul.
    @Published var coin: Coin { didSet { d.set(coin.rawValue, forKey: "presseCoin") } }
    /// Largeur du volet, en points.
    @Published var largeur: Double { didSet { d.set(largeur, forKey: "presseLargeur") } }
    /// Un clic sur une carte la recopie ; le volet se referme alors tout seul.
    @Published var fermerApresCopie: Bool { didSet { d.set(fermerApresCopie, forKey: "presseFermer") } }
    /// Montrer l'aperçu officiel des liens (image et titre du site). Il faut pour cela contacter le site.
    @Published var apercuLiens: Bool { didSet { d.set(apercuLiens, forKey: "presseApercuLiens") } }
    /// Raccourci clavier : -1 = aucun, sinon le code de la touche. Au départ : Contrôle + Option + V.
    @Published var touche: Int { didSet { d.set(touche, forKey: "presseTouche") } }
    @Published var mods: Int { didSet { d.set(mods, forKey: "presseMods") } }
    @Published var libelle: String { didSet { d.set(libelle, forKey: "presseLibelle") } }
    private var ecouteur: Any?

    func definirRaccourci(touche: Int, mods: Int, libelle: String) {
        self.touche = touche
        self.mods = mods
        self.libelle = libelle
        VoletPresse.commun.installerRaccourci()
    }

    /// Attend la prochaine combinaison de touches tapée dans la fenêtre Réglages (Échap annule).
    func ecouterRaccourci(fin: @escaping () -> Void) {
        VoletPresse.commun.suspendreRaccourci()
        if let e = ecouteur { NSEvent.removeMonitor(e) }
        ecouteur = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self else { return ev }
            let f = ev.modifierFlags
            let annule = ev.keyCode == 53
            guard annule || !f.intersection([.command, .control, .option]).isEmpty else { NSSound.beep(); return nil }
            if let e = self.ecouteur { NSEvent.removeMonitor(e); self.ecouteur = nil }
            if annule { VoletPresse.commun.installerRaccourci(); fin(); return nil }
            var mods = 0, texte = ""
            if f.contains(.control) { mods |= controlKey; texte += "⌃" }
            if f.contains(.option) { mods |= optionKey; texte += "⌥" }
            if f.contains(.shift) { mods |= shiftKey; texte += "⇧" }
            if f.contains(.command) { mods |= cmdKey; texte += "⌘" }
            texte += ev.keyCode == UInt16(kVK_Space) ? String(localized: "Espace") : (ev.charactersIgnoringModifiers ?? "?").uppercased()
            self.definirRaccourci(touche: Int(ev.keyCode), mods: mods, libelle: texte)
            fin()
            return nil
        }
    }

    private init() {
        apercuLiens = d.object(forKey: "presseApercuLiens") as? Bool ?? true
        touche = d.object(forKey: "presseTouche") as? Int ?? kVK_ANSI_V
        mods = d.object(forKey: "presseMods") as? Int ?? (controlKey | optionKey)
        libelle = d.string(forKey: "presseLibelle") ?? "⌃⌥V"
        coin = d.string(forKey: "presseCoin").flatMap(Coin.init) ?? .basDroite
        largeur = d.object(forKey: "presseLargeur") as? Double ?? 340
        fermerApresCopie = d.object(forKey: "presseFermer") as? Bool ?? true
    }
}

/// Les lignes du volet dans les réglages de Side (rubrique Général, groupe « Presse-papiers »).
struct ReglagesVoletPresse: View {
    @ObservedObject private var presse = ConfigPresse.commun
    @State private var ecoute = false

    var body: some View {
        Picker("Volet du presse-papiers : coin actif", selection: $presse.coin) {
            ForEach(Coin.allCases, id: \.self) { Text($0.titre).tag($0) }
        }
        LabeledContent("Volet du presse-papiers : raccourci clavier") {
            HStack {
                Button(ecoute ? String(localized: "Tape le raccourci…") : presse.libelle) {
                    ecoute = true
                    presse.ecouterRaccourci { ecoute = false }
                }
                Button("Effacer") { presse.definirRaccourci(touche: -1, mods: 0, libelle: String(localized: "Aucun")) }
                    .disabled(presse.touche == -1)
            }
        }
        LabeledContent("Largeur du volet") {
            HStack {
                Slider(value: $presse.largeur, in: 260...520).frame(width: 190)
                Text(verbatim: "\(Int(presse.largeur.rounded())) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 84, alignment: .trailing)
            }
        }
        Toggle("Refermer le volet après avoir copié", isOn: $presse.fermerApresCopie)
        Toggle("Aperçu des liens (l'image et le titre du site)", isOn: $presse.apercuLiens)
            .help("Pour cela, Side contacte le site du lien, quand le volet l'affiche.")
        LabeledContent("Le volet glisse depuis le bord droit de l'écran") {
            Button("Afficher le volet") { VoletPresse.commun.basculer() }
        }
    }
}

// MARK: - La nature d'un élément copié

enum NaturePresse: String, CaseIterable {
    case image, lien, couleur, mail, fichier, secret, texte

    var titre: String {
        switch self {
        case .image: return String(localized: "Image")
        case .lien: return String(localized: "Lien")
        case .couleur: return String(localized: "Couleur")
        case .mail: return String(localized: "Adresse e-mail")
        case .fichier: return String(localized: "Fichier")
        case .secret: return String(localized: "Mot de passe")
        case .texte: return String(localized: "Texte")
        }
    }
    var symbole: String {
        switch self {
        case .image: return "photo.fill"
        case .lien: return "link"
        case .couleur: return "paintpalette.fill"
        case .mail: return "envelope.fill"
        case .fichier: return "doc.fill"
        case .secret: return "key.fill"
        case .texte: return "text.alignleft"
        }
    }
    var couleur: Color {
        switch self {
        case .image: return .purple
        case .lien: return .blue
        case .couleur: return .pink
        case .mail: return .teal
        case .fichier: return .orange
        case .secret: return .red
        case .texte: return .gray
        }
    }

    private static let hexa = try! NSRegularExpression(pattern: "^#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$")
    private static let adresseMail = try! NSRegularExpression(pattern: "^[^@\\s]+@[^@\\s]+\\.[A-Za-z]{2,}$")

    static func de(_ c: Copie) -> NaturePresse {
        if c.secret { return .secret }
        if c.image != nil { return .image }
        if !c.fichiers.isEmpty { return .fichier }
        let t = (c.texte ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tout = NSRange(t.startIndex..., in: t)
        if hexa.firstMatch(in: t, range: tout) != nil { return .couleur }
        if adresseMail.firstMatch(in: t, range: tout) != nil { return .mail }
        if !t.contains(where: \.isWhitespace), let u = URL(string: t), let s = u.scheme?.lowercased(), ["http", "https"].contains(s), u.host != nil {
            return .lien
        }
        return .texte
    }

    /// La couleur écrite en hexadécimal (« #D86F4A » ou « #D64 »).
    static func teinte(_ texte: String) -> Color? {
        var h = String(texte.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst()).lowercased()
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - L'aperçu d'un lien

/// L'aperçu officiel d'un site, celui que montrent Messages ou Notes : son image de partage, son titre, son icône.
/// Demandé une seule fois par adresse, quand une carte l'affiche, puis gardé en mémoire.
final class ApercuLien: ObservableObject {
    private static var connus: [String: ApercuLien] = [:]
    static func pour(_ adresse: String) -> ApercuLien {
        if let a = connus[adresse] { return a }
        let a = ApercuLien(adresse)
        connus[adresse] = a
        return a
    }

    let adresse: String
    @Published var titre: String?
    @Published var image: NSImage?
    @Published var icone: NSImage?
    @Published var enCours = false
    private var demande = false
    private init(_ adresse: String) { self.adresse = adresse }

    func charger() {
        guard !demande, let url = URL(string: adresse) else { return }
        demande = true
        enCours = true
        let fournisseur = LPMetadataProvider()
        fournisseur.timeout = 12
        fournisseur.startFetchingMetadata(for: url) { [weak self] meta, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.enCours = false
                guard let meta else { return }
                self.titre = meta.title
                meta.imageProvider?.loadObject(ofClass: NSImage.self) { objet, _ in
                    guard let i = objet as? NSImage else { return }
                    DispatchQueue.main.async { self.image = i }
                }
                meta.iconProvider?.loadObject(ofClass: NSImage.self) { objet, _ in
                    guard let i = objet as? NSImage else { return }
                    DispatchQueue.main.async { self.icone = i }
                }
            }
        }
    }
}

private struct ApercuLienVue: View {
    let texte: String
    @ObservedObject private var apercu: ApercuLien
    @ObservedObject private var presse = ConfigPresse.commun

    init(texte: String) {
        self.texte = texte
        apercu = ApercuLien.pour(texte)
    }

    private var site: String { (URL(string: texte)?.host ?? texte).replacingOccurrences(of: "www.", with: "") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if presse.apercuLiens, let image = apercu.image {
                // L'image de partage du site, comme dans Messages.
                Color.clear.frame(height: 130)
                    .overlay(Image(nsImage: image).resizable().scaledToFill())
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack(alignment: .top, spacing: 8) {
                if presse.apercuLiens, let icone = apercu.icone {
                    Image(nsImage: icone).resizable().scaledToFit().frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    if presse.apercuLiens, let titre = apercu.titre, !titre.isEmpty {
                        Text(verbatim: titre).font(.callout.weight(.semibold)).lineLimit(2)
                        Text(verbatim: site).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        HStack(spacing: 6) {
                            Text(verbatim: site).font(.callout.weight(.semibold)).lineLimit(1)
                            if presse.apercuLiens && apercu.enCours { ProgressView().controlSize(.mini) }
                        }
                        Text(verbatim: texte).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    }
                }
            }
        }
        .onAppear { if presse.apercuLiens { apercu.charger() } }
        .onChange(of: presse.apercuLiens) { _, oui in if oui { apercu.charger() } }
    }
}

// MARK: - Les liens gardés

/// Un lien (ou un petit texte) qu'on veut toujours retrouver en haut du volet, rangé dans un groupe.
struct LienGarde: Identifiable, Codable, Equatable {
    var id = UUID()
    var titre: String
    var texte: String
    var groupe: String = ""

    /// L'adresse, si le texte en est une (sinon, c'est un texte à coller tel quel).
    var url: URL? {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: \.isWhitespace), let u = URL(string: t), let s = u.scheme?.lowercased(),
              ["http", "https"].contains(s), u.host != nil else { return nil }
        return u
    }
    /// Ce qu'on affiche sous le titre : le site, ou la première ligne du texte.
    var detail: String {
        if let h = url?.host { return h.replacingOccurrences(of: "www.", with: "") + url!.path }
        return texte.split(separator: "\n").first.map(String.init) ?? texte
    }
}

/// Les liens gardés, sans limite de nombre ni de durée. Enregistrés dans les réglages de Side (`presseLiens`, en JSON).
final class LiensGardes: ObservableObject {
    static let commun = LiensGardes()
    private let d = UserDefaults.standard

    @Published var liens: [LienGarde] { didSet { sauver() } }
    /// Les groupes repliés.
    @Published var groupesFermes: Set<String> { didSet { d.set(Array(groupesFermes), forKey: "presseGroupesFermes") } }
    /// Le lien en cours d'ajout ou de modification (le formulaire du volet s'affiche quand il y en a un).
    @Published var brouillon: LienGarde?

    private init() {
        let json = d.string(forKey: "presseLiens") ?? "[]"
        liens = (try? JSONDecoder().decode([LienGarde].self, from: Data(json.utf8))) ?? []
        groupesFermes = Set(d.stringArray(forKey: "presseGroupesFermes") ?? [])
    }

    private func sauver() {
        guard let data = try? JSONEncoder().encode(liens) else { return }
        d.set(String(decoding: data, as: UTF8.self), forKey: "presseLiens")
    }

    /// Les groupes, dans l'ordre où ils apparaissent ; les liens sans groupe d'abord.
    var groupes: [String] {
        var vus: [String] = []
        for l in liens where !vus.contains(l.groupe) { vus.append(l.groupe) }
        return vus.sorted { $0.isEmpty && !$1.isEmpty }
    }

    func enregistrer(_ l: LienGarde) {
        var l = l
        l.titre = l.titre.trimmingCharacters(in: .whitespacesAndNewlines)
        l.groupe = l.groupe.trimmingCharacters(in: .whitespacesAndNewlines)
        l.texte = l.texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !l.texte.isEmpty else { return }
        // Sans titre : celui du site s'il est connu, sinon le site lui-même.
        if l.titre.isEmpty {
            if let u = l.url { l.titre = ApercuLien.pour(u.absoluteString).titre ?? (u.host ?? l.texte).replacingOccurrences(of: "www.", with: "") }
            else { l.titre = String(l.texte.prefix(40)) }
        }
        if let i = liens.firstIndex(where: { $0.id == l.id }) { liens[i] = l } else { liens.append(l) }
        groupesFermes.remove(l.groupe)
    }

    private var attentes: [UUID: AnyCancellable] = [:]

    /// Ce qu'on vient de glisser dans l'onglet : gardé tout de suite, sans formulaire. Déjà gardé : il change seulement de groupe.
    /// Le titre est d'abord le nom du site ; le vrai titre de la page le remplace dès qu'il arrive.
    func deposer(_ texte: String, groupe: String?) {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let i = liens.firstIndex(where: { $0.texte == t }) {
            guard let groupe, liens[i].groupe != groupe else { return }
            var l = liens.remove(at: i)
            l.groupe = groupe
            liens.append(l)
            groupesFermes.remove(groupe)
            return
        }
        let l = LienGarde(titre: "", texte: t, groupe: groupe ?? "")
        enregistrer(l)
        guard let u = l.url, ConfigPresse.commun.apercuLiens else { return }
        let apercu = ApercuLien.pour(u.absoluteString), provisoire = liens.first { $0.id == l.id }?.titre
        apercu.charger()
        attentes[l.id] = apercu.$titre.compactMap { $0 }.filter { !$0.isEmpty }.first().sink { [weak self] titre in
            guard let self, let i = self.liens.firstIndex(where: { $0.id == l.id }), self.liens[i].titre == provisoire else { return }
            self.liens[i].titre = titre
        }
    }
    func supprimer(_ l: LienGarde) { liens.removeAll { $0.id == l.id } }
    /// Monte ou descend un lien d'un cran dans son groupe.
    func deplacer(_ l: LienGarde, de pas: Int) {
        let memes = liens.indices.filter { liens[$0].groupe == l.groupe }
        guard let k = memes.firstIndex(where: { liens[$0].id == l.id }), memes.indices.contains(k + pas) else { return }
        liens.swapAt(memes[k], memes[k + pas])
    }
    func basculerGroupe(_ g: String) {
        if groupesFermes.contains(g) { groupesFermes.remove(g) } else { groupesFermes.insert(g) }
    }
}

/// Un lien enregistré : une carte comme celles du presse-papiers, avec l'image de partage du site, son icône, le titre.
private struct LigneLien: View {
    let lien: LienGarde
    let copie: Bool
    let action: () -> Void
    @ObservedObject private var liens = LiensGardes.commun
    @ObservedObject private var presse = ConfigPresse.commun
    @ObservedObject private var apercu: ApercuLien
    @State private var survol = false

    init(lien: LienGarde, copie: Bool, action: @escaping () -> Void) {
        self.lien = lien
        self.copie = copie
        self.action = action
        apercu = ApercuLien.pour(lien.url?.absoluteString ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if lien.url != nil, presse.apercuLiens, let image = apercu.image {
                Color.clear.frame(height: 120)
                    .overlay(Image(nsImage: image).resizable().scaledToFill())
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack(alignment: .top, spacing: 10) {
                IconeLien(lien: lien)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: lien.titre).font(.body.weight(.semibold)).lineLimit(2)
                    Text(verbatim: lien.url != nil ? lien.detail : lien.texte)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(lien.url != nil ? 1 : 3).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if copie { Text("Copié").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(copie ? Color.accentColor.opacity(0.20) : Color.primary.opacity(survol ? 0.10 : 0.055)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(copie ? Color.accentColor : Color.accentColor.opacity(survol ? 0.55 : 0), lineWidth: 1.5))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture(perform: action)
        .onDrag { NSItemProvider(object: lien.texte as NSString) }
        .contextMenu {
            Button("Copier") { action() }
            if let u = lien.url { Button("Ouvrir le lien") { NSWorkspace.shared.open(u) } }
            Button("Modifier…") { liens.brouillon = lien }
            Button("Monter") { liens.deplacer(lien, de: -1) }
            Button("Descendre") { liens.deplacer(lien, de: 1) }
            Divider()
            Button("Supprimer") { liens.supprimer(lien) }
        }
        .help(lien.texte)
        .animation(.easeOut(duration: 0.12), value: survol)
        .onAppear { if lien.url != nil, presse.apercuLiens { apercu.charger() } }
    }
}

/// L'icône d'un lien gardé : celle du site (si les aperçus sont permis), sinon un symbole.
private struct IconeLien: View {
    let lien: LienGarde
    @ObservedObject private var apercu: ApercuLien
    @ObservedObject private var presse = ConfigPresse.commun

    init(lien: LienGarde) {
        self.lien = lien
        apercu = ApercuLien.pour(lien.url?.absoluteString ?? "")
    }

    var body: some View {
        Group {
            if lien.url != nil, presse.apercuLiens, let i = apercu.icone {
                Image(nsImage: i).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: lien.url != nil ? "link" : "text.alignleft")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((lien.url != nil ? Color.blue : Color.gray).gradient))
            }
        }
        .frame(width: 30, height: 30)
        .onAppear { if lien.url != nil, presse.apercuLiens { apercu.charger() } }
    }
}

/// Le formulaire d'ajout ou de modification, dans le volet.
private struct FormulaireLien: View {
    @State var lien: LienGarde
    @ObservedObject private var liens = LiensGardes.commun
    private var nouveau: Bool { !liens.liens.contains { $0.id == lien.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(nouveau ? "Nouveau lien" : "Modifier le lien").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            champ("Lien ou texte à coller", $lien.texte)
            champ("Titre (facultatif)", $lien.titre)
            HStack(spacing: 6) {
                champ("Groupe (facultatif)", $lien.groupe)
                let existants = liens.groupes.filter { !$0.isEmpty }
                if !existants.isEmpty {
                    Menu {
                        ForEach(existants, id: \.self) { g in Button(g) { lien.groupe = g } }
                    } label: { Image(systemName: "chevron.down") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Choisir un groupe existant")
                }
            }
            HStack {
                Spacer()
                Button("Annuler") { liens.brouillon = nil }.keyboardShortcut(.cancelAction)
                Button(nouveau ? "Ajouter" : "Enregistrer") {
                    liens.enregistrer(lien)
                    liens.brouillon = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(lien.texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1))
    }

    private func champ(_ invite: LocalizedStringKey, _ valeur: Binding<String>) -> some View {
        TextField(invite, text: valeur).textFieldStyle(.plain)
            .padding(.horizontal, 8).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}

/// Lit ce qu'on vient de déposer (un lien glissé d'un navigateur, ou un texte) et le rend sur le fil principal.
private func lireDepot(_ fournisseurs: [NSItemProvider], _ suite: @escaping (String) -> Void) -> Bool {
    guard let f = fournisseurs.first else { return false }
    if f.canLoadObject(ofClass: NSURL.self) {
        _ = f.loadObject(ofClass: NSURL.self) { o, _ in
            guard let u = o as? NSURL, let t = u.absoluteString else { return }
            DispatchQueue.main.async { suite(t) }
        }
        return true
    }
    if f.canLoadObject(ofClass: NSString.self) {
        _ = f.loadObject(ofClass: NSString.self) { o, _ in
            guard let t = o as? String else { return }
            DispatchQueue.main.async { suite(t) }
        }
        return true
    }
    return false
}
private let typesDepot = ["public.url", "public.utf8-plain-text", "public.plain-text"]

/// L'onglet « Enregistrés » : les liens gardés pour toujours, par groupe. Une seule liste paresseuse :
/// l'aperçu d'un lien n'est demandé que lorsque sa carte arrive à l'écran.
private struct OngletLiens: View {
    let filtre: String
    let copie: UUID?
    let copier: (LienGarde) -> Void
    @ObservedObject private var liens = LiensGardes.commun
    /// Le groupe au-dessus duquel passe un glisser (son en-tête s'éclaire).
    @State private var groupeVise: String?

    private func visibles(_ g: String) -> [LienGarde] {
        let f = filtre.trimmingCharacters(in: .whitespaces)
        return liens.liens.filter { l in
            l.groupe == g && (f.isEmpty || l.titre.localizedCaseInsensitiveContains(f) || l.texte.localizedCaseInsensitiveContains(f)
                              || l.groupe.localizedCaseInsensitiveContains(f))
        }
    }

    private func vise(_ g: String) -> Binding<Bool> {
        Binding(get: { groupeVise == g }, set: { oui in
            if oui { groupeVise = g } else if groupeVise == g { groupeVise = nil }
        })
    }

    var body: some View {
        let cherche = !filtre.trimmingCharacters(in: .whitespaces).isEmpty
        let groupes = liens.groupes.filter { !visibles($0).isEmpty }
        LazyVStack(alignment: .leading, spacing: 8) {
            if liens.liens.isEmpty && liens.brouillon == nil {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark").font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text("Aucun lien enregistré").font(.headline)
                    Text("Glisse ici un élément du presse-papiers, ou ajoute un lien avec le +. Il restera là, sans limite.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 40)
            } else if groupes.isEmpty && cherche {
                Text("Aucun résultat").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 30)
            }
            ForEach(groupes, id: \.self) { g in
                let lignes = visibles(g), ferme = liens.groupesFermes.contains(g) && !cherche
                if !g.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(ferme ? 0 : 90))
                        Text(verbatim: g).font(.title3.weight(.semibold))
                        Spacer()
                        Text(verbatim: "\(lignes.count)").font(.caption.weight(.semibold)).monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.09)))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(groupeVise == g ? Color.accentColor.opacity(0.22) : Color.primary.opacity(ferme ? 0.055 : 0)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(groupeVise == g ? 0.9 : 0), lineWidth: 1.5))
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { liens.basculerGroupe(g) } }
                    .onDrop(of: typesDepot, isTargeted: vise(g)) { f in lireDepot(f) { liens.deposer($0, groupe: g) } }
                }
                if !ferme {
                    ForEach(lignes) { l in
                        LigneLien(lien: l, copie: copie == l.id) { copier(l) }
                            .onDrop(of: typesDepot, isTargeted: vise(g)) { f in lireDepot(f) { liens.deposer($0, groupe: g) } }
                    }
                }
            }
        }
    }
}

// MARK: - Une carte

private struct CartePresse: View {
    let c: Copie
    let copiee: Bool
    let action: () -> Void
    @ObservedObject private var presse = PressePapiers.shared
    @State private var survol = false

    private static let dates: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale.current
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        let nature = NaturePresse.de(c)
        VStack(alignment: .leading, spacing: 8) {
            // L'en-tête : la nature (pastille de couleur), l'épingle, et depuis quand.
            HStack(spacing: 7) {
                Image(systemName: nature.symbole)
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(nature.couleur.gradient))
                Text(nature.titre).font(.caption.weight(.semibold)).foregroundStyle(nature.couleur)
                Spacer(minLength: 0)
                if c.epingle { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Color.accentColor) }
                Text(copiee ? String(localized: "Copié") : Self.dates.localizedString(for: c.date, relativeTo: Date()))
                    .font(.caption2).foregroundStyle(copiee ? Color.accentColor : .secondary)
            }
            contenu(nature)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(copiee ? Color.accentColor.opacity(0.20) : Color.primary.opacity(survol ? 0.10 : 0.055)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(copiee ? Color.accentColor : nature.couleur.opacity(survol ? 0.55 : 0), lineWidth: 1.5))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture(perform: action)
        .onDrag {
            if let fichier = c.fichiers.first { return NSItemProvider(object: fichier as NSURL) }
            if let image = c.image { return NSItemProvider(object: image) }
            return NSItemProvider(object: (c.texte ?? "") as NSString)
        }
        .contextMenu {
            Button("Copier") { presse.recopier(c) }
            if nature == .lien, let u = URL(string: (c.texte ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) {
                Button("Ouvrir le lien") { NSWorkspace.shared.open(u) }
            }
            if !c.secret { Button(c.epingle ? "Désépingler" : "Épingler en haut de la liste") { presse.epingler(c) } }
            if !c.secret, let t = c.texte?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                Button("Garder dans les liens…") { LiensGardes.commun.brouillon = LienGarde(titre: "", texte: t) }
            }
            Button("Supprimer de l'historique") { presse.supprimer(c) }
            Divider()
            Button("Effacer l'historique (sauf les épinglés)") { presse.vider() }
        }
        .help("Clic : recopier. Clic droit : épingler. On peut aussi le glisser ailleurs.")
        .animation(.easeOut(duration: 0.12), value: survol)
    }

    @ViewBuilder private func contenu(_ nature: NaturePresse) -> some View {
        let texte = (c.texte ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch nature {
        case .image:
            if let image = c.image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(verbatim: "\(Int(image.size.width)) × \(Int(image.size.height))").font(.caption2).foregroundStyle(.secondary)
            }
        case .lien:
            ApercuLienVue(texte: texte)
        case .couleur:
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(NaturePresse.teinte(texte) ?? .clear)
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            Text(verbatim: texte.uppercased()).font(.system(.callout, design: .monospaced))
        case .mail:
            Text(verbatim: texte).font(.callout).lineLimit(1).truncationMode(.middle)
        case .fichier:
            ForEach(Array(c.fichiers.prefix(3)), id: \.self) { f in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: f.path)).resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: FileManager.default.displayName(atPath: f.path)).font(.callout).lineLimit(1).truncationMode(.middle)
                        Text(verbatim: f.deletingLastPathComponent().lastPathComponent).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            if c.fichiers.count > 3 { Text("et \(c.fichiers.count - 3) de plus").font(.caption2).foregroundStyle(.secondary) }
        case .secret:
            Text(verbatim: "••••••••••••").font(.title3).foregroundStyle(.secondary)
        case .texte:
            Text(verbatim: texte).font(.callout).lineLimit(5).truncationMode(.tail)
        }
    }
}

// MARK: - Le contenu du volet

struct VoletPresseVue: View {
    let fermer: () -> Void
    @ObservedObject private var presse = PressePapiers.shared
    @ObservedObject private var config = Config.shared
    @State private var filtre = ""
    @State private var nature: NaturePresse?
    @State private var copiee: UUID?
    @State private var lienCopie: UUID?
    @ObservedObject private var liens = LiensGardes.commun
    /// L'onglet affiché : 0 = presse-papiers, 1 = enregistrés. Retenu d'une fois sur l'autre.
    @AppStorage("presseOnglet") private var onglet = 0
    @State private var ongletsVises = false

    private var visibles: [Copie] {
        let f = filtre.trimmingCharacters(in: .whitespaces)
        return presse.tries.filter { c in
            if let nature, NaturePresse.de(c) != nature { return false }
            guard !f.isEmpty else { return true }
            if c.secret { return false }
            let texte = (c.texte ?? "") + " " + c.fichiers.map(\.lastPathComponent).joined(separator: " ")
            return texte.localizedCaseInsensitiveContains(f)
        }
    }

    /// Les natures présentes dans l'historique : on ne propose que les filtres qui servent.
    private var natures: [NaturePresse] {
        let presentes = Set(presse.elements.map { NaturePresse.de($0) })
        return NaturePresse.allCases.filter { presentes.contains($0) }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Les deux onglets (contrôle segmenté de macOS). On peut y déposer un élément pour l'enregistrer.
            HStack(spacing: 8) {
                Picker("Onglet", selection: $onglet) {
                    Text("Presse-papiers").tag(0)
                    Text("Enregistrés").tag(1)
                }
                .pickerStyle(.segmented).labelsHidden()
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2).opacity(ongletsVises ? 1 : 0))
                .onDrop(of: typesDepot, isTargeted: $ongletsVises) { f in
                    lireDepot(f) { liens.deposer($0, groupe: nil); onglet = 1 }
                }
                .onChange(of: ongletsVises) { _, vise in
                    // Rester un instant sur les onglets pendant un glisser ouvre « Enregistrés », pour viser un groupe.
                    guard vise else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if ongletsVises { onglet = 1 } }
                }
                if onglet == 1 {
                    Button { liens.brouillon = LienGarde(titre: "", texte: "") } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless).help("Ajouter un lien").accessibilityLabel("Ajouter un lien")
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher", text: $filtre).textFieldStyle(.plain)
                if !filtre.isEmpty {
                    Button { filtre = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Effacer la recherche")
                }
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            if onglet == 0 {
                // Les filtres par nature : une pastille par sorte d'élément présent.
                if natures.count > 1 {
                    HStack(spacing: 6) {
                        pastille(nil)
                        ForEach(natures, id: \.self) { pastille($0) }
                        Spacer(minLength: 0)
                    }
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if !config.historique {
                            vide("L'historique du copier-coller est désactivé dans les réglages de Side.")
                        } else if presse.elements.isEmpty {
                            vide("Ce que tu copies apparaîtra ici.")
                        } else if visibles.isEmpty {
                            vide("Aucun résultat")
                        } else {
                            ForEach(visibles) { c in
                                CartePresse(c: c, copiee: copiee == c.id) { copier(c) }
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
            } else {
                // Le formulaire d'ajout ou de modification reste au-dessus de la liste, toujours visible.
                // (Dans la liste paresseuse, il laissait un grand vide à sa place.)
                if let b = liens.brouillon { FormulaireLien(lien: b).id(b.id) }
                ScrollView {
                    OngletLiens(filtre: filtre, copie: lienCopie) { copier($0) }.padding(.bottom, 6)
                }
                // Tout l'onglet reçoit ce qu'on y glisse (hors d'un groupe : sans groupe).
                .onDrop(of: typesDepot, isTargeted: nil) { f in lireDepot(f) { liens.deposer($0, groupe: nil) } }
            }
            Text(onglet == 0 ? "Gardé 7 jours · clic pour copier" : "Gardé sans limite · clic pour copier")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZStack {
            VisualEffect()
            Color(nsColor: .windowBackgroundColor).opacity(config.opacite)
        })
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
        // « Garder dans les liens… » depuis une carte : le formulaire est dans l'onglet « Enregistrés ».
        .onChange(of: liens.brouillon) { _, b in if b != nil { onglet = 1 } }
    }

    private func vide(_ texte: LocalizedStringKey) -> some View {
        Text(texte).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .padding(.horizontal, 20).padding(.vertical, 30).frame(maxWidth: .infinity)
    }

    private func pastille(_ n: NaturePresse?) -> some View {
        let choisie = nature == n
        return Image(systemName: n?.symbole ?? "square.grid.2x2.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(choisie ? .white : (n?.couleur ?? Color.primary))
            .frame(width: 30, height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(choisie ? AnyShapeStyle((n?.couleur ?? Color.accentColor).gradient) : AnyShapeStyle(Color.primary.opacity(0.08))))
            .contentShape(Rectangle())
            .onTapGesture { nature = n }
            .help(n?.titre ?? String(localized: "Tout"))
            .accessibilityLabel(n?.titre ?? String(localized: "Tout"))
    }

    private func copier(_ l: LienGarde) {
        PressePapiers.shared.ecrireSansHistorique(l.texte)
        lienCopie = l.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            guard lienCopie == l.id else { return }
            lienCopie = nil
            if ConfigPresse.commun.fermerApresCopie { fermer() }
        }
    }

    private func copier(_ c: Copie) {
        presse.recopier(c)
        copiee = c.id
        // Le temps de voir « Copié », puis le volet se referme (si le réglage le veut).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            guard copiee == c.id else { return }
            copiee = nil
            if ConfigPresse.commun.fermerApresCopie { fermer() }
        }
    }
}

// MARK: - Le panneau

private final class PanneauPresse: NSPanel {
    override var canBecomeKey: Bool { true }       // pour taper dans la recherche, sans activer Side
}

final class VoletPresse {
    static let commun = VoletPresse()
    private var panneau: PanneauPresse?
    private var ecouteClics: Any?
    private(set) var ouvert = false
    private let idEchap: UInt32 = 41
    private let marge: CGFloat = 8

    private func cadre(_ e: NSScreen, sorti: Bool) -> NSRect {
        let z = e.visibleFrame, l = CGFloat(min(max(ConfigPresse.commun.largeur, 260), 520))
        return NSRect(x: sorti ? z.maxX - l - marge : z.maxX + 12, y: z.minY + marge, width: l, height: z.height - 2 * marge)
    }

    func basculer() { ouvert ? fermer() : ouvrir() }

    private let idRaccourci: UInt32 = 42
    /// (Ré)installe le raccourci clavier choisi dans les réglages (aucun si on l'a effacé).
    func installerRaccourci() {
        TouchesBas.retirer(idRaccourci)
        let c = ConfigPresse.commun
        guard c.touche >= 0 else { return }
        TouchesBas.ajouter(idRaccourci, touche: UInt32(c.touche), modifs: UInt32(c.mods)) { [weak self] in self?.basculer() }
    }
    /// Pendant qu'on tape un nouveau raccourci dans les réglages : l'ancien ne doit pas ouvrir le volet.
    func suspendreRaccourci() { TouchesBas.retirer(idRaccourci) }

    func ouvrir(sur ecran: NSScreen? = nil) {
        guard !ouvert, !CaptureEcran.enCours,
              let e = ecran ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let p = panneau ?? {
            let p = PanneauPresse(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.animationBehavior = .none
            p.contentView = NSHostingView(rootView: VoletPresseVue(fermer: { [weak self] in self?.fermer() }))
            return p
        }()
        panneau = p
        ouvert = true
        PressePapiers.shared.verifier()                      // ce qui vient d'être copié y est tout de suite
        p.setFrame(cadre(e, sorti: false), display: true)
        p.alphaValue = 0
        p.orderFrontRegardless()
        // Il glisse depuis le bord droit, avec élan, comme les autres panneaux de Side.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            p.animator().setFrame(cadre(e, sorti: true), display: true)
            p.animator().alphaValue = 1
        }
        TouchesBas.ajouter(idEchap, touche: UInt32(kVK_Escape), modifs: 0) { [weak self] in self?.fermer() }
        ecouteClics = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let p = self.panneau, !p.frame.contains(NSEvent.mouseLocation), !CaptureEcran.enCours else { return }
            self.fermer()
        }
    }

    func fermer() {
        guard ouvert, let p = panneau else { return }
        ouvert = false
        TouchesBas.retirer(idEchap)
        if let ecouteClics { NSEvent.removeMonitor(ecouteClics) }
        ecouteClics = nil
        let e = p.screen ?? NSScreen.main
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0.4)
            if let e { p.animator().setFrame(self.cadre(e, sorti: false), display: true) }
            p.animator().alphaValue = 0
        }) { [weak self] in
            if self?.ouvert == false { p.orderOut(nil) }
        }
    }

    // MARK: Le coin actif (appelé plusieurs fois par seconde par Side, avec la place du pointeur)

    private var coinArme = true
    private var debutCoin: Date?

    func surveillerCoin(_ p: NSPoint, _ e: NSScreen, taille: CGFloat) {
        let coin = ConfigPresse.commun.coin
        guard coin != .aucun, Config.shared.historique else { return }
        func dans(_ marge: CGFloat) -> Bool {
            let t = taille + marge, f = e.frame
            let gauche = p.x <= f.minX + t, droite = p.x >= f.maxX - t, haut = p.y >= f.maxY - t, bas = p.y <= f.minY + t
            switch coin {
            case .aucun: return false
            case .hautGauche: return haut && gauche
            case .hautDroite: return haut && droite
            case .basGauche: return bas && gauche
            case .basDroite: return bas && droite
            }
        }
        // Il faut s'éloigner nettement du coin avant qu'y revenir ne referme le volet.
        if !dans(140) { coinArme = true; debutCoin = nil; return }
        guard dans(0) else { debutCoin = nil; return }
        guard coinArme, NSEvent.pressedMouseButtons == 0 else { return }
        if debutCoin == nil { debutCoin = Date() }
        guard Date().timeIntervalSince(debutCoin!) >= 0.05 else { return }
        coinArme = false
        debutCoin = nil
        if ouvert { fermer() } else { ouvrir(sur: e) }
    }
}
