// Le volet du presse-papiers : un panneau étroit qui glisse depuis le bord droit de l'écran, sur toute sa hauteur,
// quand le pointeur va dans un coin (en bas à droite au départ). Chaque élément copié y est une carte, selon sa nature :
// une image se montre, un lien affiche son site, une couleur se voit, un fichier a son icône.
// Les données sont celles de l'historique déjà tenu par Side (`PressePapiers`) : rien de plus n'est gardé.
import AppKit
import SwiftUI
import Carbon.HIToolbox

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
            let u = URL(string: texte)
            Text(verbatim: (u?.host ?? texte).replacingOccurrences(of: "www.", with: ""))
                .font(.callout.weight(.semibold)).lineLimit(1)
            Text(verbatim: texte).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
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
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard.fill").foregroundStyle(Color.accentColor)
                Text("Presse-papiers").font(.headline)
                Spacer()
                Text(verbatim: "\(presse.elements.count)").font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.09)))
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
            // Les filtres par nature : une pastille par sorte d'élément présent.
            if natures.count > 1 {
                HStack(spacing: 6) {
                    pastille(nil)
                    ForEach(natures, id: \.self) { pastille($0) }
                    Spacer(minLength: 0)
                }
            }
            if !config.historique {
                vide("L'historique du copier-coller est désactivé dans les réglages de Side.")
            } else if presse.elements.isEmpty {
                vide("Ce que tu copies apparaîtra ici.")
            } else if visibles.isEmpty {
                vide("Aucun résultat")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibles) { c in
                            CartePresse(c: c, copiee: copiee == c.id) { copier(c) }
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
            Text("Gardé 7 jours · clic pour copier").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZStack {
            VisualEffect()
            Color(nsColor: .windowBackgroundColor).opacity(config.opacite)
        })
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
    }

    private func vide(_ texte: LocalizedStringKey) -> some View {
        Text(texte).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .padding(.horizontal, 20).frame(maxWidth: .infinity, maxHeight: .infinity)
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
