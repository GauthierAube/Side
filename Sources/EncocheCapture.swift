// La capture d'Horizon dans l'île de l'encoche (25/11/2026, à la demande de Gauthier) : un « + » toujours visible en bas
// de l'île ouverte. Un clic, on tape son idée, Entrée : elle part dans l'inbox d'Horizon (`00 Inbox 📥/Capture.md`, à la
// fin de « ## Tâches »), au même format que la capture de Safari d'Horizon (HorizonCapture/CaptureWriter.swift).
// Sans coffre Horizon sur le Mac, la ligne n'apparaît pas.
import AppKit
import SwiftUI

final class CaptureIle: ObservableObject {
    static let commun = CaptureIle()

    /// On est en train de taper : l'île garde le clavier et ne se referme pas quand le pointeur s'éloigne.
    @Published private(set) var saisie = false
    @Published var texte = ""
    /// Le petit « Dans l'inbox » après un envoi (ou le message d'erreur).
    @Published private(set) var retour: String?
    @Published private(set) var echec = false
    /// Le rouge d'Horizon (son terracotta, `AppColors.terracotta`).
    static let rouge = Color(red: 0xD8 / 255, green: 0x6F / 255, blue: 0x4A / 255)
    /// Un texte est en cours : l'île ne se referme pas quand le pointeur s'éloigne.
    var retient: Bool { saisie && !texte.trimmingCharacters(in: .whitespaces).isEmpty }
    /// L'application devant avant la saisie : elle reprend le clavier ensuite.
    private var avant: NSRunningApplication?
    private var finRetour: Timer?

    /// Le dossier `Contenu` du coffre d'Horizon dans iCloud Drive.
    static var contenu: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~online~wakademy~horizon/Documents/Contenu", isDirectory: true)
    }
    /// Horizon est sur ce Mac (sinon, pas de ligne de capture).
    static var disponible: Bool {
        var dossier: ObjCBool = false
        return FileManager.default.fileExists(atPath: contenu.path, isDirectory: &dossier) && dossier.boolValue
    }

    func commencer() {
        guard !saisie else { return }
        let devant = NSWorkspace.shared.frontmostApplication
        avant = devant?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : devant
        finRetour?.invalidate(); retour = nil
        withAnimation(Mouvement.ileSurvol) { saisie = true }
        // Side passe devant pendant la saisie : la dictée de Flow (qui colle dans l'application de devant) et les
        // autres outils de saisie arrivent ainsi dans le champ, pas dans l'application d'avant.
        NSApp.activate()
        Ile.commun.prendreClavier()
    }

    /// Échap ou l'île qui se referme : on garde le texte tapé pour la prochaine fois.
    func arreter() {
        guard saisie else { return }
        withAnimation(Mouvement.ileSurvol) { saisie = false }
        Ile.commun.rendreClavier()
        // L'application d'avant reprend la main, sauf si on vient de cliquer dans une autre.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            avant?.activate()
        }
        avant = nil
    }

    func envoyer() {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { arreter(); return }
        do {
            try EcritureInbox.capturer(t, contenu: CaptureIle.contenu)
            texte = ""
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            montrer(String(localized: "Dans l'inbox"), echec: false)
            journal("capture Horizon : %@", String(t.prefix(60)))
        } catch {
            montrer(error.localizedDescription, echec: true)
            journal("capture Horizon impossible : %@", error.localizedDescription)
            return
        }
        arreter()
    }

    private func montrer(_ m: String, echec e: Bool) {
        finRetour?.invalidate()
        withAnimation(Mouvement.ileSurvol) { retour = m; echec = e }
        finRetour = Timer.scheduledTimer(withTimeInterval: e ? 4 : 1.6, repeats: false) { [weak self] _ in
            withAnimation(Mouvement.ileSurvol) { self?.retour = nil }
        }
    }
}

/// La ligne de capture, en bas de l'île ouverte.
struct LigneCapture: View {
    @ObservedObject private var capture = CaptureIle.commun
    @FocusState private var focus: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(capture.retour != nil && !capture.echec ? Color.green : CaptureIle.rouge)
                    .shadow(color: CaptureIle.rouge.opacity(capture.saisie ? 0.55 : 0.3), radius: capture.saisie ? 8 : 4)
                Image(systemName: capture.retour != nil && !capture.echec ? "checkmark" : "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .contentTransition(.symbolEffect(.replace))
                    .rotationEffect(.degrees(capture.saisie ? 90 : 0))
            }
            .frame(width: 32, height: 32)
            .scaleEffect(capture.saisie ? 1.06 : 1)

            ZStack(alignment: .leading) {
                if capture.saisie {
                    TextField("", text: $capture.texte, prompt: Text("Une idée, une tâche…").foregroundColor(.white.opacity(0.4)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .focused($focus)
                        .onSubmit { capture.envoyer() }
                        .onAppear { DispatchQueue.main.async { focus = true } }
                        .transition(.ile)
                } else if let r = capture.retour {
                    Text(r).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(capture.echec ? Color.orange : Color.white.opacity(0.85))
                        .lineLimit(1)
                        .transition(.ile)
                } else {
                    Text(capture.texte.isEmpty ? String(localized: "Capturer une idée") : capture.texte)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(capture.texte.isEmpty ? 0.5 : 0.75))
                        .lineLimit(1)
                        .transition(.ile)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if capture.saisie {
                Text("↩︎").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.35)).transition(.ile)
            }
        }
        .padding(.leading, 5).padding(.trailing, 16)
        .frame(height: 42)
        .background(Capsule().fill(Color.white.opacity(capture.saisie ? 0.14 : 0.08)))
        .contentShape(Capsule())
        .onTapGesture { capture.commencer() }
        .onHover { if $0 { capture.commencer() } }
        .help("Capturer dans l'inbox d'Horizon")
    }
}

/// L'écriture dans `Capture.md`, comme `CaptureWriter` d'Horizon : une ligne ajoutée, jamais une ligne existante réécrite.
enum EcritureInbox {
    enum Erreur: LocalizedError {
        case introuvable, pasTelecharge, ecriture(String)
        var errorDescription: String? {
            switch self {
            case .introuvable: return String(localized: "Inbox d'Horizon introuvable")
            case .pasTelecharge: return String(localized: "iCloud télécharge l'inbox, réessaie")
            case .ecriture(let m): return String(localized: "Écriture impossible : \(m)")
            }
        }
    }

    private static let nomFichier = "Capture.md"
    private static let neuve = "---\nhorizon: inbox\n---\n# Capture\n\n## Tâches\n\n## Ressources\n"

    static func capturer(_ texte: String, contenu: URL) throws {
        let fm = FileManager.default
        guard let noms = try? fm.contentsOfDirectory(atPath: contenu.path),
              let dossier = noms.sorted().first(where: { n in
                  var d: ObjCBool = false
                  return n.hasPrefix("00") && fm.fileExists(atPath: contenu.appendingPathComponent(n).path, isDirectory: &d) && d.boolValue
              })
        else { throw Erreur.introuvable }
        let inbox = contenu.appendingPathComponent(dossier, isDirectory: true)
        let fichier = inbox.appendingPathComponent(nomFichier)

        // Fichier laissé dans iCloud seulement : surtout ne pas en écrire un vide par-dessus.
        let v = try? fichier.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if (v?.isUbiquitousItem == true && v?.ubiquitousItemDownloadingStatus == .notDownloaded)
            || (!fm.fileExists(atPath: fichier.path) && fm.fileExists(atPath: inbox.appendingPathComponent(".\(nomFichier).icloud").path)) {
            try? fm.startDownloadingUbiquitousItem(at: fichier)
            throw Erreur.pasTelecharge
        }

        let ligne = "- [ ] \(texte.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)) ➕ \(aujourdhui()) ^\(nouvelId())"
        var erreurCoord: NSError?
        var echec: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: fichier, options: .forMerging, error: &erreurCoord) { url in
            do {
                let existant = fm.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : neuve
                try inserer(ligne, dans: existant).write(to: url, atomically: true, encoding: .utf8)
            } catch { echec = error }
        }
        if let e = echec ?? erreurCoord { throw Erreur.ecriture(e.localizedDescription) }
    }

    /// À la fin de « ## Tâches » (la section est créée si elle manque, avant « ## Ressources »).
    static func inserer(_ ligne: String, dans contenu: String) -> String {
        let crlf = contenu.contains("\r\n")
        var l = contenu.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if l.last == "" { l.removeLast() }
        func titre(_ s: String) -> String? {
            guard s.hasPrefix("## ") else { return nil }
            return String(s.dropFirst(3)).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
                .trimmingCharacters(in: .whitespaces)
        }
        func vide(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }
        if let h = l.firstIndex(where: { titre($0) == "taches" }) {
            var fin = l[(h + 1)...].firstIndex(where: { $0.hasPrefix("## ") }) ?? l.count
            while fin > h + 1, vide(l[fin - 1]) { fin -= 1 }
            l.insert(ligne, at: fin)
        } else if let r = l.firstIndex(where: { titre($0) == "ressources" }) {
            l.insert(contentsOf: ["## Tâches", ligne, ""], at: r)
        } else {
            while let d = l.last, vide(d) { l.removeLast() }
            if !l.isEmpty { l.append("") }
            l.append(contentsOf: ["## Tâches", ligne])
        }
        let fin = crlf ? "\r\n" : "\n"
        return l.joined(separator: fin) + fin
    }

    private static func nouvelId() -> String {
        let a = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return "t-" + String((0..<6).map { _ in a.randomElement()! })
    }

    private static func aujourdhui() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
