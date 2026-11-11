import AppKit
// Icône de Side : une carte blanche dont le côté gauche est mis en valeur, sur un fond bleu nuit.
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
    // La carte : blanche, translucide, avec une ombre douce.
    let carte = CGRect(x: 262, y: 322, width: 500, height: 380)
    let cartePath = CGPath(roundedRect: carte, cornerWidth: 64, cornerHeight: 64, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: NSColor(red: 0.05, green: 0.08, blue: 0.3, alpha: 0.45).cgColor)
    c.addPath(cartePath); c.setFillColor(NSColor.white.withAlphaComponent(0.34).cgColor); c.fillPath()
    c.restoreGState()
    // Son côté gauche : blanc plein — le « side ».
    c.saveGState()
    c.addPath(cartePath); c.clip()
    c.setFillColor(NSColor.white.cgColor)
    c.fill(CGRect(x: carte.minX, y: carte.minY, width: 168, height: carte.height))
    c.restoreGState()
    // Un fin liseré clair autour de la carte.
    c.addPath(CGPath(roundedRect: carte.insetBy(dx: 3, dy: 3), cornerWidth: 61, cornerHeight: 61, transform: nil))
    c.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor); c.setLineWidth(6); c.strokePath()
    g.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}
let dossier = URL(fileURLWithPath: sortie)
try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
for (nom, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                  ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! dessiner(px).write(to: dossier.appendingPathComponent("icon_\(nom).png"))
}
