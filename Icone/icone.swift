import AppKit
// Icône de l'app : un triptyque, sur un fond bleu nuit. Trois volets pour trois sortes d'applications :
// à gauche, le Finder (blanc) ; au centre, le grand volet des applications de travail ; en bas, le tiroir (orangé).
let sortie = CommandLine.arguments[1]
func dessiner(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    let c = g.cgContext
    let k = CGFloat(px) / 1024
    c.scaleBy(x: k, y: k)
    // Fond : le carré arrondi de macOS (824 pt dans 1024), dégradé bleu nuit.
    let fond = CGRect(x: 100, y: 100, width: 824, height: 824)
    let forme = CGPath(roundedRect: fond, cornerWidth: 186, cornerHeight: 186, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    c.addPath(forme); c.setFillColor(NSColor.black.cgColor); c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(forme); c.clip()
    let esp = CGColorSpaceCreateDeviceRGB()
    let degrade = CGGradient(colorsSpace: esp, colors: [
        NSColor(red: 0.36, green: 0.52, blue: 0.98, alpha: 1).cgColor,
        NSColor(red: 0.16, green: 0.22, blue: 0.62, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(degrade, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Un reflet très léger en haut.
    let reflet = CGGradient(colorsSpace: esp, colors: [
        NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(reflet, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    c.restoreGState()
    // Le triptyque : trois volets séparés par de fins espaces, comme un retable, avec une ombre douce.
    let ombre = NSColor(red: 0.05, green: 0.08, blue: 0.3, alpha: 0.45).cgColor
    func volet(_ r: CGRect, _ rayon: CGFloat, _ couleur: CGColor, liseré: Bool = false) {
        let path = CGPath(roundedRect: r, cornerWidth: rayon, cornerHeight: rayon, transform: nil)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: ombre)
        c.addPath(path); c.setFillColor(couleur); c.fillPath()
        c.restoreGState()
        if liseré {
            c.addPath(CGPath(roundedRect: r.insetBy(dx: 3, dy: 3), cornerWidth: rayon - 3, cornerHeight: rayon - 3, transform: nil))
            c.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor); c.setLineWidth(6); c.strokePath()
        }
    }
    // Le Finder : un volet étroit, blanc, à gauche, sur toute la hauteur.
    volet(CGRect(x: 232, y: 290, width: 150, height: 444), 44, NSColor.white.cgColor)
    // Les applications de travail : le grand volet du centre, translucide.
    volet(CGRect(x: 404, y: 420, width: 388, height: 314), 44, NSColor.white.withAlphaComponent(0.36).cgColor, liseré: true)
    // Le tiroir : un volet bas, chaud, sous le grand volet.
    volet(CGRect(x: 404, y: 290, width: 388, height: 108), 36, NSColor(red: 0.97, green: 0.58, blue: 0.38, alpha: 1).cgColor)
    g.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}
let dossier = URL(fileURLWithPath: sortie)
try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
for (nom, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                  ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! dessiner(px).write(to: dossier.appendingPathComponent("icon_\(nom).png"))
}
