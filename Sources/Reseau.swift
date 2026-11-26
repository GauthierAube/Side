// Les serveurs du réseau local, pour la barre latérale.
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import NetFS
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Les ordinateurs du réseau local qui partagent des fichiers, comme la rubrique « Réseau » du Finder.
/// Side les repère (annonces Bonjour) et s'y connecte lui-même : macOS demande le mot de passe (gardé dans le trousseau)
/// et le dossier partagé à ouvrir, puis Side affiche ce dossier.
final class Reseau: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = Reseau()
    @Published var ordinateurs: [String] = []
    private var chercheurs: [NetServiceBrowser] = []
    private var services: [NetService] = []
    private var enAttente: NetService?

    /// Les ordinateurs qui partagent leur écran (Partage d'écran), et ceux qui partagent des fichiers.
    @Published var ecrans: Set<String> = []
    @Published var fichiers: Set<String> = []

    /// Lance la recherche (une seule fois) : partages Windows/Mac récents (SMB), anciens Mac (AFP), et partage d'écran
    /// (un Mac qui ne partage que son écran apparaît aussi).
    func chercher() {
        guard chercheurs.isEmpty else { return }
        for type in ["_smb._tcp.", "_afpovertcp._tcp.", "_rfb._tcp."] {
            let c = NetServiceBrowser()
            c.delegate = self
            c.searchForServices(ofType: type, inDomain: "local.")
            chercheurs.append(c)
        }
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        publier()
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        publier()
    }
    private func publier() {
        let moi = Host.current().localizedName
        let noms = Set(services.map(\.name)).filter { $0 != moi }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if noms != ordinateurs { ordinateurs = noms }
        let e = Set(services.filter { $0.type.hasPrefix("_rfb") }.map(\.name))
        let f = Set(services.filter { !$0.type.hasPrefix("_rfb") }.map(\.name))
        if e != ecrans { ecrans = e }
        if f != fichiers { fichiers = f }
    }
    /// Vrai quand la résolution en cours doit ouvrir l'écran de l'ordinateur plutôt que ses fichiers.
    private var pourEcran = false
    /// Se connecte aux dossiers partagés de l'ordinateur et les ouvre dans Side (après identification si besoin).
    /// Un ordinateur qui ne partage que son écran montre son écran.
    func ouvrir(_ nom: String) { resoudre(nom, ecran: !fichiers.contains(nom)) }
    /// Montre l'écran de l'ordinateur avec l'app Partage d'écran de macOS.
    func voirEcran(_ nom: String) { resoudre(nom, ecran: true) }
    private func resoudre(_ nom: String, ecran: Bool) {
        pourEcran = ecran
        let prefere = ecran ? "_rfb" : "_smb"
        guard let service = services.first(where: { $0.name == nom && $0.type.hasPrefix(prefere) })
                ?? services.first(where: { $0.name == nom && (ecran || !$0.type.hasPrefix("_rfb")) })
                ?? services.first(where: { $0.name == nom }) else { return }
        enAttente = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }
    @Published var enConnexion: String?
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard sender == enAttente, let hote = sender.hostName else { return }
        enAttente = nil
        let protocole = sender.type.hasPrefix("_afp") ? "afp" : "smb"
        var adresse = URLComponents()
        adresse.scheme = protocole
        adresse.host = hote.hasSuffix(".") ? String(hote.dropLast()) : hote
        if pourEcran {
            adresse.scheme = "vnc"
            guard let url = adresse.url else { return }
            DialoguesSysteme.commun.surveiller(pendant: 15)   // mot de passe du Mac distant : devant Side
            AppDelegate.shared.hide()                          // la carte s'efface pour laisser voir l'écran
            NSWorkspace.shared.open(url)
            ResolutionDynamique.activer()
            return
        }
        guard let url = adresse.url else { return }
        connecter(url, nom: sender.name)
    }
    /// Monte le partage comme le fait le Finder (fenêtre d'identification et choix du dossier de macOS),
    /// puis l'ouvre dans Side. Si le montage échoue, on laisse le Finder s'en charger.
    private func connecter(_ url: URL, nom: String) {
        enConnexion = nom
        DialoguesSysteme.commun.surveiller(pendant: 15)   // la fenêtre du mot de passe doit passer devant Side
        let options = NSMutableDictionary()
        options[kNAUIOptionKey] = kNAUIOptionAllowUI
        var requete: AsyncRequestID?
        let statut = NetFSMountURLAsync(url as CFURL, nil, nil, nil, options, nil, &requete, DispatchQueue.main) { erreur, _, points in
            self.enConnexion = nil
            let montes = (points as? [String]) ?? []
            if erreur == 0, let premier = montes.first {
                let dossier = URL(fileURLWithPath: premier, isDirectory: true)
                AppDelegate.shared.store.naviguer(.folder(dossier))
                self.objectWillChange.send()   // la barre latérale affiche le serveur connecté
            } else if erreur != 0, erreur != Int32(ECANCELED), erreur != -128 {
                NSWorkspace.shared.open(url)
            }
        }
        if statut != 0 { enConnexion = nil; NSWorkspace.shared.open(url) }
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        if sender == enAttente { enAttente = nil; NSSound.beep() }
    }
}

/// Active « Présentation > Résolution dynamique » dans Partage d'écran, que macOS ne retient pas (26/11/2026) :
/// l'écran du Mac distant prend alors la taille de la fenêtre, avec un texte de taille normale.
/// Side clique le menu à ta place (accès « Accessibilité »), une fois la session ouverte (après le mot de passe).
/// Si le menu est déjà coché, il n'y touche pas. Il abandonne après une minute.
enum ResolutionDynamique {
    private static let menus = ["Présentation", "View"]
    private static let elements = ["Résolution dynamique", "Dynamic Resolution",
                                   "Activer la résolution dynamique", "Enable Dynamic Resolution"]
    private static let dejaActive = ["Désactiver la résolution dynamique", "Disable Dynamic Resolution"]

    static func activer() {
        guard AXIsProcessTrusted() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let fin = Date().addingTimeInterval(60)
            Thread.sleep(forTimeInterval: 1)
            while Date() < fin {
                if essayer() { return }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    /// Vrai quand c'est réglé (cliqué, ou déjà actif).
    private static func essayer() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ScreenSharing").first
        else { return false }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        // Pas de fenêtre de session encore (mot de passe en cours) : on attend.
        guard let fenetres = valeur(ax, kAXWindowsAttribute) as? [AXUIElement], !fenetres.isEmpty,
              let barreObjet = valeur(ax, kAXMenuBarAttribute),
              let titres = valeur(barreObjet as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement],
              let menu = titres.first(where: { menus.contains(titre($0)) }),
              let sous = (valeur(menu, kAXChildrenAttribute) as? [AXUIElement])?.first,
              let items = valeur(sous, kAXChildrenAttribute) as? [AXUIElement] else { return false }
        if items.contains(where: { dejaActive.contains(titre($0)) }) { return true }
        guard let item = items.first(where: { elements.contains(titre($0)) }),
              (valeur(item, kAXEnabledAttribute) as? Bool) == true else { return false }
        // Coché = déjà active.
        if let coche = valeur(item, kAXMenuItemMarkCharAttribute) as? String, !coche.isEmpty { return true }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private static func valeur(_ e: AXUIElement, _ attribut: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, attribut as CFString, &v) == .success ? v : nil
    }
    private static func titre(_ e: AXUIElement) -> String { (valeur(e, kAXTitleAttribute) as? String) ?? "" }
}
