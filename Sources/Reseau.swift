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

    /// Lance la recherche (une seule fois) : partages Windows/Mac récents (SMB) et anciens Mac (AFP).
    func chercher() {
        guard chercheurs.isEmpty else { return }
        for type in ["_smb._tcp.", "_afpovertcp._tcp."] {
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
    }
    /// Vrai quand la résolution en cours doit ouvrir l'écran de l'ordinateur plutôt que ses fichiers.
    private var pourEcran = false
    /// Se connecte aux dossiers partagés de l'ordinateur et les ouvre dans Side (après identification si besoin).
    func ouvrir(_ nom: String) { resoudre(nom, ecran: false) }
    /// Montre l'écran de l'ordinateur avec l'app Partage d'écran de macOS.
    func voirEcran(_ nom: String) { resoudre(nom, ecran: true) }
    private func resoudre(_ nom: String, ecran: Bool) {
        pourEcran = ecran
        guard let service = services.first(where: { $0.name == nom && $0.type.hasPrefix("_smb") })
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
