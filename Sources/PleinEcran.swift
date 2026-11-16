// Square : une grille plein écran pour naviguer sur le Mac sans Mission Control.
// Chaque fenêtre agrandie (un faux plein écran, sans changement d'espace) a sa case, plus le bureau et les plein écran d'Apple restants.
// Un raccourci ouvre la grille ; un clic ou un chiffre envoie sur la case choisie, sans glissement d'écran.
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Fonctions système non documentées (liste des espaces, photo et repérage des fenêtres)

@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray
@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
func CGSCopyWindowsWithOptionsAndTags(_ cid: Int32, _ owner: Int32, _ spaces: CFArray, _ options: Int32,
                                      _ setTags: inout UInt64, _ clearTags: inout UInt64) -> CFArray
@_silgen_name("CGSHWCaptureWindowList")
func CGSHWCaptureWindowList(_ cid: Int32, _ liste: UnsafePointer<CGWindowID>, _ n: UInt32, _ options: UInt32) -> Unmanaged<CFArray>?
@_silgen_name("CGWindowListCreateImage")
func CGWindowListCreateImageAncienne(_ zone: CGRect, _ options: UInt32, _ wid: CGWindowID, _ image: UInt32) -> Unmanaged<CGImage>?
@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

/// Petit journal dans ~/Library/Logs/Square.log, pour comprendre un souci après coup.
func journal(_ format: String, _ args: CVarArg...) {
    let ligne = ISO8601DateFormatter().string(from: Date()) + " " + String(format: format, arguments: args) + "\n"
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Square.log")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(ligne.data(using: .utf8)!); try? h.close() }
    else { try? ligne.data(using: .utf8)!.write(to: url) }
}


/// Le plein écran (ex-Square) n'est plus une application à part : c'est un module, démarré par l'AppDelegate de l'app.
enum Programme {
    static let appli = Appli()
}
