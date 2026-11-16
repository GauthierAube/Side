// Le plein écran : les images des fenêtres et des fonds d'écran.
// Sorti de PleinEcran.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

/// Photographie les fenêtres, même celles qui ne sont pas affichées, pour former l'image de chaque case.
final class Images {
    static let commun = Images()
    private var cache: [CGWindowID: CGImage] = [:]
    private var fonds: [String: CGImage] = [:]

    static var autorisé: Bool { CGPreflightScreenCaptureAccess() }

    private static func photo(_ wid: CGWindowID) -> CGImage? {
        var w = wid
        if let img = (CGSHWCaptureWindowList(CGSMainConnectionID(), &w, 1, 1 << 9)?.takeRetainedValue() as? [CGImage])?.first { return img }
        return CGWindowListCreateImageAncienne(.null, 8, wid, 1 | 16)?.takeRetainedValue()
    }

    func capturer(_ espaces: [Espace], chaque: @escaping () -> Void) {
        guard Images.autorisé else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            for e in espaces {
                var nouvelles: [CGWindowID: CGImage] = [:]
                for f in e.fenetres.prefix(16) { if let img = Images.photo(f.wid) { nouvelles[f.wid] = img } }
                if nouvelles.isEmpty { continue }
                DispatchQueue.main.async {
                    for (k, v) in nouvelles { self.cache[k] = v }
                    chaque()
                }
            }
        }
    }

    /// La dernière photo connue d'une fenêtre.
    func enCache(_ wid: CGWindowID) -> CGImage? { cache[wid] }

    func oublier(sauf vivantes: Set<CGWindowID>) { cache = cache.filter { vivantes.contains($0.key) } }

    private func fond(ecran: NSScreen?) -> CGImage? {
        guard let ecran, let url = NSWorkspace.shared.desktopImageURL(for: ecran) else { return nil }
        if let f = fonds[url.path] { return f }
        guard let img = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // Quelques fonds au plus (un par écran) : avec un fond d'écran qui change tout seul, la mémoire grossissait sans fin.
        if fonds.count >= 3 { fonds.removeAll(); flous.removeAll() }
        fonds[url.path] = img
        return img
    }

    private var flous: [String: CGImage] = [:]

    /// Le fond d'écran, flouté et un peu assombri : le fond de la grille.
    func fondFlou(ecran: NSScreen?) -> CGImage? {
        guard let ecran, let url = NSWorkspace.shared.desktopImageURL(for: ecran), let net = fond(ecran: ecran) else { return nil }
        if let f = flous[url.path] { return f }
        // Réduit d'abord (le flou n'a pas besoin de détails), puis flouté.
        let l = 640, h = max(1, Int(640 * CGFloat(net.height) / CGFloat(max(net.width, 1))))
        guard let ctx = CGContext(data: nil, width: l, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(net, in: CGRect(x: 0, y: 0, width: l, height: h))
        guard let petit = ctx.makeImage() else { return nil }
        let entree = CIImage(cgImage: petit)
        let flou = entree.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 22])
            .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.12, kCIInputSaturationKey: 1.15])
            .cropped(to: entree.extent)
        guard let sortie = CIContext().createCGImage(flou, from: entree.extent) else { return nil }
        flous[url.path] = sortie
        return sortie
    }

    /// Image d'une case. nil s'il n'y a rien à montrer (la case affiche alors la grande icône).
    func image(pour t: Tuile, espaces: [Espace]) -> CGImage? {
        switch t.cible {
        case .fenetre(let f, _): return cache[f.wid]
        case .groupe(let fs, let e):
            guard let tout = composer(fs, ecran: e.ecran, papier: true) else { return nil }
            let zone = Ecrans.cadreGlobal(Ecrans.ecran(e.ecran)), u = Tuile.englobant(fs)
            return tout.cropping(to: CGRect(x: u.minX - zone.minX, y: u.minY - zone.minY, width: u.width, height: u.height)) ?? tout
        case .espace(let e):
            if e.pleinEcran { return composer(e.fenetres, ecran: e.ecran, papier: false) }
            return composer(e.fenetres.filter { !$0.agrandie && !$0.masquee }, ecran: e.ecran, papier: true)
        }
    }

    /// Pose les fenêtres à leur place sur un fond (noir, ou le fond d'écran pour un bureau).
    private func composer(_ fenetres: [Fenetre], ecran identifiant: String, papier: Bool) -> CGImage? {
        let ecran = Ecrans.ecran(identifiant)
        let zone = Ecrans.cadreGlobal(ecran)
        let visibles = fenetres.filter { cache[$0.wid] != nil }
        let image = papier ? fond(ecran: ecran) : nil
        if visibles.isEmpty && image == nil { return nil }
        let l = Int(zone.width), h = Int(zone.height)
        guard l > 0, h > 0, let ctx = CGContext(data: nil, width: l, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: papier ? 0.2 : 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: l, height: h))
        if let f = image {
            let r = max(CGFloat(l) / CGFloat(f.width), CGFloat(h) / CGFloat(f.height))
            let fl = CGFloat(f.width) * r, fh = CGFloat(f.height) * r
            ctx.draw(f, in: CGRect(x: (CGFloat(l) - fl) / 2, y: (CGFloat(h) - fh) / 2, width: fl, height: fh))
        }
        for f in visibles.reversed() {
            guard let img = cache[f.wid] else { continue }
            ctx.draw(img, in: CGRect(x: f.cadre.minX - zone.minX, y: zone.height - (f.cadre.minY - zone.minY) - f.cadre.height,
                                     width: f.cadre.width, height: f.cadre.height))
        }
        return ctx.makeImage()
    }
}
