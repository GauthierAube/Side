// Les serveurs du réseau local, pour la barre latérale.
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Les ordinateurs du réseau local qui partagent des fichiers, comme la rubrique « Réseau » du Finder.
/// Side les repère (annonces Bonjour) ; s'y connecter passe par le Finder, qui demande le mot de passe.
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
    /// Ouvre l'ordinateur dans le Finder, qui affiche ses dossiers partagés (après identification si besoin).
    func ouvrir(_ nom: String) {
        guard let service = services.first(where: { $0.name == nom && $0.type.hasPrefix("_smb") })
                ?? services.first(where: { $0.name == nom }) else { return }
        enAttente = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard sender == enAttente, let hote = sender.hostName else { return }
        enAttente = nil
        let protocole = sender.type.hasPrefix("_afp") ? "afp" : "smb"
        var adresse = URLComponents()
        adresse.scheme = protocole
        adresse.host = hote.hasSuffix(".") ? String(hote.dropLast()) : hote
        if let url = adresse.url { NSWorkspace.shared.open(url) }
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        if sender == enAttente { enAttente = nil; NSSound.beep() }
    }
}
