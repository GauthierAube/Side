// Le système de design de Side : les quelques valeurs que tous les écrans partagent.
// Règles et mode d'emploi : design/DESIGN-SYSTEM.md. Un écran utilise ces noms, jamais un nombre écrit en dur.

import SwiftUI

/// Les arrondis, du plus petit au plus grand. Un élément posé dans un autre a un arrondi plus petit que lui
/// (arrondi intérieur = arrondi extérieur moins la marge).
enum Rayon {
    /// Pastilles, étiquettes, très petits éléments.
    static let puce: CGFloat = 4
    /// Lignes de liste, fond d'un élément survolé ou sélectionné, petits boutons.
    static let ligne: CGFloat = 6
    /// Vignettes et images, boutons, champs.
    static let vignette: CGFloat = 8
    /// Encadrés, zones de dépôt, groupes de réglages.
    static let encadre: CGFloat = 10
    /// Cartes (presse-papiers, tuiles).
    static let carte: CGFloat = 12
    /// Ce qui est posé à 6 à 8 points du bord d'une grande surface (bouton d'une tuile, mini-Dock, image du carrousel) :
    /// arrondi intérieur = arrondi extérieur moins la marge.
    static let interieur: CGFloat = 14
    /// Panneaux flottants posés sur la carte (menus maison, lanceur).
    static let panneau: CGFloat = 16
    /// Les tuiles du tiroir (YouTube, Spotify, applications) et leurs photos.
    static let tuile: CGFloat = 20
    /// Les grandes surfaces flottantes : la carte du Finder elle-même.
    static let fenetre: CGFloat = 22

    /// Les dessins de la présentation (fenêtres en miniature, à l'échelle) : valeur libre, gardée telle quelle.
    static func dessin(_ v: CGFloat) -> CGFloat { v }
}

/// Les durées des animations. Trois vitesses suffisent ; « Réduire les animations » (réglage du Mac) les ramène à zéro.
enum Mouvement {
    /// Survol, appui, petit changement d'état.
    static let bref: Double = 0.12
    /// Un élément qui apparaît, disparaît ou change de place.
    static let normal: Double = 0.2
    /// Un panneau entier qui glisse.
    static let ample: Double = 0.3

    /// Les quatre mouvements de l'interface (SwiftUI). Aucun quand le Mac demande de réduire les animations.
    /// Survol : un fond qui s'allume sous la souris, un petit bouton qui change d'état.
    static var survol: Animation? { reduit ? nil : .easeOut(duration: bref) }
    /// Bascule : une page qui change, une liste qui se réordonne, un défilement vers un élément.
    static var bascule: Animation? { reduit ? nil : .easeInOut(duration: normal) }
    /// Glissement : des éléments d'une rangée qui changent de place (mini-Dock).
    static var glissement: Animation? { reduit ? nil : .smooth(duration: 0.25) }
    /// Ressort : un panneau ou une zone qui apparaît, s'ouvre ou se déplie.
    static var ressort: Animation? { reduit ? nil : .spring(response: ample, dampingFraction: 0.82) }

    private static var reduit: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// La durée à utiliser : nulle si le Mac demande de réduire les animations.
    static func duree(_ d: Double) -> Double {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : d
    }
}

/// Les gris neutres. Ils sont faits sur la couleur du texte : ils suivent tout seuls le mode clair ou sombre.
enum Gris {
    /// Fond au repos : un champ, une carte, une zone de saisie.
    static let leger = Color.primary.opacity(0.06)
    /// Pastille, bouton rond, ligne sous la souris.
    static let moyen = Color.primary.opacity(0.10)
    /// Élément choisi ou appuyé.
    static let fort = Color.primary.opacity(0.16)
    /// Contour fin d'une carte ou d'un panneau.
    static let filet = Color.primary.opacity(0.12)
    /// Contour marqué : une case à cocher maison, le cadre d'un dessin.
    static let bord = Color.primary.opacity(0.25)
}
