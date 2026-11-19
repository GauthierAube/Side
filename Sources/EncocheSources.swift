// Ce que l'île de l'encoche montre (voir Encoche.swift) : la lecture en cours (Spotify et Musique) et l'agenda.
// Le travail lent (AppleScript, calendrier, images) se fait hors du fil principal.
import AppKit
import CoreImage
import EventKit
import SwiftUI

// MARK: - Lecture en cours

final class LectureIle: ObservableObject {
    static let commun = LectureIle()

    enum Source: String { case spotify = "com.spotify.client", musique = "com.apple.Music" }

    @Published private(set) var source: Source?
    @Published private(set) var titre = ""
    @Published private(set) var artiste = ""
    @Published private(set) var joue = false
    @Published private(set) var duree: Double = 0
    @Published private(set) var pochette: NSImage?
    /// La couleur moyenne de la pochette, éclaircie : l'onde et la barre de progression la reprennent.
    @Published private(set) var teinte = Color.white

    private var position: Double = 0
    private var depuis = Date()
    private var morceau = ""
    private let file = DispatchQueue(label: "side.encoche.lecture")

    var enActivite: Bool { source != nil && joue }

    func position(a d: Date) -> Double {
        let p = position + (joue ? d.timeIntervalSince(depuis) : 0)
        return duree > 0 ? min(duree, p) : p
    }

    func demarrer() {
        let c = DistributedNotificationCenter.default()
        c.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] n in
            self?.recu(.spotify, n.userInfo ?? [:])
        }
        c.addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] n in
            self?.recu(.musique, n.userInfo ?? [:])
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                                          queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let self, app?.bundleIdentifier == self.source?.rawValue { self.vider() }
        }
        rafraichir()
    }

    private static func ouverte(_ s: Source) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == s.rawValue }
    }

    /// Spotify et Musique annoncent eux-mêmes chaque changement (lecture, pause, morceau suivant).
    private func recu(_ s: Source, _ info: [AnyHashable: Any]) {
        let etat = info["Player State"] as? String ?? ""
        if etat == "Stopped" { if source == s { vider() }; return }
        let jouant = etat == "Playing"
        // Une source en pause ne prend pas la place de celle qui joue.
        if let source, source != s, joue, !jouant { return }
        let nom = info["Name"] as? String ?? ""
        let qui = info["Artist"] as? String ?? ""
        let ms = (info[s == .spotify ? "Duration" : "Total Time"] as? NSNumber)?.doubleValue ?? 0
        let pos = (info["Playback Position"] as? NSNumber)?.doubleValue
        maj(s, titre: nom, artiste: qui, joue: jouant, duree: ms / 1000, position: pos)
        if pos == nil { lirePosition(s) }
    }

    private func maj(_ s: Source, titre t: String, artiste a: String, joue j: Bool, duree d: Double, position p: Double?) {
        let cle = s.rawValue + t + a
        withAnimation(Mouvement.ile) {
            source = s; joue = j
        }
        titre = t; artiste = a; duree = d
        if let p { position = p; depuis = Date() } else if !j { position = position(a: Date()); depuis = Date() }
        if cle != morceau {
            morceau = cle
            if p == nil { position = 0; depuis = Date() }
            chargerPochette(s, cle)
        }
    }

    private func vider() {
        withAnimation(Mouvement.ile) { source = nil; joue = false }
        titre = ""; artiste = ""; duree = 0; pochette = nil; morceau = ""; teinte = .white
    }

    /// Relit l'état complet (à l'ouverture de l'île et au lancement de Side).
    func rafraichir() {
        if LectureIle.ouverte(.spotify) {
            SpotifyBas.lire { [weak self] e in
                guard let self, e.enCours, !e.titre.isEmpty else { return }
                if let s = self.source, s != .spotify, self.joue, !e.joue { return }
                self.maj(.spotify, titre: e.titre, artiste: e.artiste, joue: e.joue, duree: e.duree, position: e.position)
            }
        }
        if LectureIle.ouverte(.musique) {
            file.async { [weak self] in
                let r = LectureIle.script("""
                tell application "Music"
                    set e to player state as string
                    if e is "stopped" then return e
                    return e & linefeed & (player position as string) & linefeed & ((duration of current track) as string) & linefeed & (name of current track) & linefeed & (artist of current track)
                end tell
                """)?.stringValue ?? ""
                let l = r.components(separatedBy: "\n")
                guard l.count >= 5 else { return }
                let n = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
                DispatchQueue.main.async {
                    guard let self else { return }
                    let jouant = l[0] == "playing"
                    if let s = self.source, s != .musique, self.joue, !jouant { return }
                    self.maj(.musique, titre: l[3], artiste: l[4], joue: jouant, duree: n(l[2]), position: n(l[1]))
                }
            }
        }
    }

    private func lirePosition(_ s: Source) {
        guard s == .musique else { return }
        file.async { [weak self] in
            guard let r = LectureIle.script("tell application \"Music\" to player position")?.stringValue,
                  let p = Double(r.replacingOccurrences(of: ",", with: ".")) else { return }
            DispatchQueue.main.async { self?.position = p; self?.depuis = Date() }
        }
    }

    // MARK: Commandes

    func lecturePause() {
        guard let s = source else { return }
        withAnimation(Mouvement.ile) { joue.toggle() }
        position = position(a: Date()); depuis = Date()
        ordre(s, "playpause")
    }
    func suivant() { if let s = source { ordre(s, "next track") } }
    func precedent() { if let s = source { ordre(s, "previous track") } }

    private func ordre(_ s: Source, _ o: String) {
        switch s {
        case .spotify: SpotifyBas.commande(o) { [weak self] in self?.rafraichir() }
        case .musique: file.async { _ = LectureIle.script("tell application \"Music\" to \(o)") }
        }
    }

    // MARK: Pochette

    private func chargerPochette(_ s: Source, _ cle: String) {
        let fin: (NSImage?) -> Void = { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.morceau == cle else { return }
                let t = image.map(LectureIle.teinte) ?? .white
                withAnimation(Mouvement.bascule) { self.pochette = image; self.teinte = t }
            }
        }
        switch s {
        case .spotify:
            SpotifyBas.lire { e in
                guard let u = URL(string: e.pochette), !e.pochette.isEmpty else { fin(nil); return }
                URLSession.shared.dataTask(with: u) { d, _, _ in fin(d.flatMap(NSImage.init(data:))) }.resume()
            }
        case .musique:
            file.async {
                let d = LectureIle.script("tell application \"Music\" to if exists artwork 1 of current track then return data of artwork 1 of current track")?.data
                fin(d.flatMap(NSImage.init(data:)))
            }
        }
    }

    private static func script(_ source: String) -> NSAppleEventDescriptor? {
        var erreur: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&erreur)
    }

    /// La couleur moyenne d'une image, rendue assez vive pour se voir sur le noir de l'île.
    private static func teinte(_ image: NSImage) -> Color {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
        let ci = CIImage(cgImage: cg)
        guard let f = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let sortie = f.outputImage else { return .white }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(sortie, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        let c = NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(1, s * 1.15), brightness: max(b, 0.82))
    }
}

// MARK: - Agenda du jour

final class CalendrierIle: ObservableObject {
    static let commun = CalendrierIle()

    struct Rdv: Identifiable, Equatable {
        let id: String
        let titre: String
        let debut: Date
        let fin: Date
        let journee: Bool
        let couleur: Color

        var heures: String {
            if journee { return String(localized: "Toute la journée") }
            let f = Date.FormatStyle(date: .omitted, time: .shortened)
            return "\(debut.formatted(f)) – \(fin.formatted(f))"
        }
    }

    /// Les rendez-vous d'aujourd'hui (la vue « Aujourd'hui »).
    @Published private(set) var aujourdhui: [Rdv] = []
    /// Le jour choisi dans le calendrier, ses rendez-vous, le mois affiché et ses jours qui ont des rendez-vous.
    @Published private(set) var jour = Calendar.current.startOfDay(for: .now)
    @Published private(set) var duJour: [Rdv] = []
    @Published private(set) var mois = CalendrierIle.debutMois(.now)
    @Published private(set) var marques: Set<Int> = []
    @Published private(set) var autorise = false
    @Published private(set) var refuse = false
    private let magasin = EKEventStore()
    private let file = DispatchQueue(label: "side.encoche.agenda")
    private var ecoute = false

    static func debutMois(_ d: Date) -> Date { Calendar.current.dateInterval(of: .month, for: d)?.start ?? d }

    /// À chaque ouverture de l'île : le calendrier revient sur aujourd'hui.
    func revenirAujourdhui() {
        jour = Calendar.current.startOfDay(for: .now)
        mois = CalendrierIle.debutMois(.now)
        rafraichir()
    }

    func choisir(_ d: Date) {
        withAnimation(Mouvement.ileSurvol) { jour = Calendar.current.startOfDay(for: d) }
        rafraichir()
    }

    func changerMois(_ n: Int) {
        guard let m = Calendar.current.date(byAdding: .month, value: n, to: mois) else { return }
        withAnimation(Mouvement.bascule) { mois = m }
        rafraichir()
    }

    func rafraichir() {
        let s = EKEventStore.authorizationStatus(for: .event)
        autorise = s == .fullAccess
        refuse = s == .denied || s == .restricted
        guard autorise else { return }
        if !ecoute {
            ecoute = true
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: magasin, queue: .main) { [weak self] _ in
                self?.rafraichir()
            }
        }
        let jour = self.jour, mois = self.mois
        file.async { [weak self] in
            guard let self else { return }
            let cal = Calendar.current
            func lendemain(_ d: Date) -> Date { cal.date(byAdding: .day, value: 1, to: d) ?? d }
            func evenements(_ debut: Date, _ fin: Date) -> [EKEvent] {
                self.magasin.events(matching: self.magasin.predicateForEvents(withStart: debut, end: fin, calendars: nil))
                    .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            }
            func rdv(_ e: EKEvent) -> Rdv {
                Rdv(id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)",
                    titre: e.title ?? "", debut: e.startDate, fin: e.endDate, journee: e.isAllDay,
                    couleur: Color(nsColor: e.calendar.color))
            }
            let debutAujourdhui = cal.startOfDay(for: Date())
            let aujourdhui = evenements(debutAujourdhui, lendemain(debutAujourdhui)).map(rdv)
            let duJour = evenements(jour, lendemain(jour)).map(rdv)
            let finMois = cal.date(byAdding: .month, value: 1, to: mois) ?? mois
            var marques = Set<Int>()
            for e in evenements(mois, finMois) {
                var d = max(cal.startOfDay(for: e.startDate), mois)
                let fin = min(e.endDate, finMois)
                repeat {
                    marques.insert(cal.component(.day, from: d))
                    d = lendemain(d)
                } while d < fin
            }
            DispatchQueue.main.async {
                withAnimation(Mouvement.bascule) {
                    self.aujourdhui = aujourdhui
                    if self.jour == jour { self.duJour = duJour }
                    if self.mois == mois { self.marques = marques }
                }
            }
        }
    }

    func demander() {
        magasin.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async { self?.rafraichir() }
        }
    }
}
