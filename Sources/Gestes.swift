// Les gestes : le cercle à la souris.
// Sorti de Side.swift le 15/11/2026, sans changement.

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Reconnaît un cercle fait à la souris, sans clic. On ne compare pas la forme : il suffit que le pointeur
/// fasse un tour à peu près complet, dans un sens ou dans l'autre. Un cercle grossier ou tremblé convient.
enum Geste {
    static let nombre = 32

    static func longueur(_ p: [CGPoint]) -> CGFloat {
        zip(p, p.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }
    static func boite(_ p: [CGPoint]) -> CGRect {
        guard let a = p.first else { return .zero }
        return p.reduce(CGRect(origin: a, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
    /// Rééchantillonne en `nombre` points régulièrement espacés le long du tracé.
    static func regulier(_ p: [CGPoint]) -> [CGPoint] {
        guard p.count > 1 else { return p }
        let pas = longueur(p) / CGFloat(nombre - 1)
        guard pas > 0 else { return p }
        var sortie = [p[0]], reste: CGFloat = 0, points = p, i = 1
        while i < points.count {
            let a = points[i - 1], b = points[i], d = hypot(b.x - a.x, b.y - a.y)
            if reste + d >= pas, d > 0 {
                let t = (pas - reste) / d
                let q = CGPoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y))
                sortie.append(q)
                points.insert(q, at: i)
                reste = 0
            } else { reste += d }
            i += 1
        }
        while sortie.count < nombre { sortie.append(p[p.count - 1]) }
        return Array(sortie.prefix(nombre))
    }
    /// De combien le tracé tourne, en degrés (positif dans un sens, négatif dans l'autre),
    /// et à quel point il tourne toujours du même côté (1 = toujours, 0 = autant à gauche qu'à droite).
    static func rotation(_ p: [CGPoint]) -> (degres: CGFloat, constance: CGFloat) {
        // Un point sur deux : les petits tremblements de la main ne comptent pas comme des virages.
        // Chaque point est aussi adouci avec ses deux voisins.
        let brut = regulier(p)
        let doux: [CGPoint] = brut.indices.map { i in
            let a = brut[max(i - 1, 0)], b = brut[i], c = brut[min(i + 1, brut.count - 1)]
            return CGPoint(x: (a.x + b.x + c.x) / 3, y: (a.y + b.y + c.y) / 3)
        }
        let r = doux.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        guard r.count >= 3 else { return (0, 0) }
        var somme: CGFloat = 0, absolue: CGFloat = 0
        for i in 1..<(r.count - 1) {
            let a = atan2(r[i].y - r[i - 1].y, r[i].x - r[i - 1].x)
            let b = atan2(r[i + 1].y - r[i].y, r[i + 1].x - r[i].x)
            var d = b - a
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            somme += d
            absolue += abs(d)
        }
        return (somme * 180 / .pi, absolue > 0 ? abs(somme) / absolue : 0)
    }
    /// Rondeur d'un tracé : 1 pour un cercle, proche de 0 pour un aller-retour, quel que soit son angle.
    /// (Rapport entre l'étalement des points dans leur direction la plus courte et dans la plus longue.)
    static func rondeur(_ p: [CGPoint]) -> CGFloat {
        let r = regulier(p), n = CGFloat(r.count)
        guard n > 2 else { return 0 }
        let mx = r.reduce(0) { $0 + $1.x } / n, my = r.reduce(0) { $0 + $1.y } / n
        var xx: CGFloat = 0, yy: CGFloat = 0, xy: CGFloat = 0
        for q in r { xx += (q.x - mx) * (q.x - mx); yy += (q.y - my) * (q.y - my); xy += (q.x - mx) * (q.y - my) }
        let moitie = (xx + yy) / 2, ecart = (((xx - yy) / 2) * ((xx - yy) / 2) + xy * xy).squareRoot()
        let grand = moitie + ecart, petit = max(0, moitie - ecart)
        return grand > 0 ? (petit / grand).squareRoot() : 0
    }
    /// Un tour à peu près complet, dans un sens ou dans l'autre, pas trop aplati.
    static func boucle(_ p: [CGPoint], degres: CGFloat) -> Bool {
        let b = boite(p)
        guard max(b.width, b.height) >= 24 else { return false }   // 24 points : un petit rond du poignet suffit
        // Une secousse dessine aussi une boucle, mais très aplatie : on exige une forme assez ronde.
        guard rondeur(p) >= 0.45 else { return false }
        let r = rotation(p)
        return abs(r.degres) >= degres && r.constance >= 0.65
    }
}
