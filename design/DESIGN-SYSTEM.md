# Le système de design de Side

Side garde l'allure de macOS (Finder, Réglages Système). Ce document dit quelles valeurs partagées utiliser,
pour que tous les écrans restent cohérents. Les valeurs vivent dans `Sources/Design.swift`.

Règle de base : un écran utilise un nom (`Rayon.carte`), jamais un nombre écrit en dur.

## Arrondis : `Rayon`

| Nom | Valeur | Pour |
| --- | --- | --- |
| `Rayon.puce` | 4 | pastilles, étiquettes, très petits éléments |
| `Rayon.ligne` | 6 | lignes de liste, fond d'un élément survolé ou sélectionné |
| `Rayon.vignette` | 8 | vignettes, images, boutons, champs |
| `Rayon.encadre` | 10 | encadrés, zones de dépôt, groupes de réglages |
| `Rayon.carte` | 12 | cartes (presse-papiers) |
| `Rayon.interieur` | 14 | ce qui est posé à 6 à 8 points du bord d'une grande surface (bouton d'une tuile, mini-Dock, image du carrousel) |
| `Rayon.panneau` | 16 | panneaux flottants posés sur la carte, zones de dépôt |
| `Rayon.tuile` | 20 | les tuiles du tiroir et leurs photos |
| `Rayon.fenetre` | 22 | la carte du Finder et les grandes surfaces flottantes |
| `Rayon.ile` | 30 | le bas de l'île de l'encoche, ouverte |
| `Rayon.dessin(x)` | libre | les dessins à l'échelle de la présentation, et les traits de 2 à 3 points |

- Un élément posé dans un autre a un arrondi plus petit : arrondi intérieur = arrondi extérieur moins la marge.
- Toujours `style: .continuous` (l'arrondi d'Apple).

## Animations : `Mouvement`

SwiftUI : quatre mouvements, et rien d'autre.

| Nom | Ce que c'est | Pour |
| --- | --- | --- |
| `Mouvement.survol` | 0,12 s, ralenti à la fin | un fond qui s'allume sous la souris, un petit bouton qui change d'état |
| `Mouvement.bascule` | 0,2 s, doux aux deux bouts | une page qui change, une liste qui se réordonne, un défilement vers un élément |
| `Mouvement.glissement` | 0,25 s | des éléments d'une rangée qui changent de place (mini-Dock) |
| `Mouvement.ressort` | ressort de 0,3 s | un panneau ou une zone qui apparaît, s'ouvre ou se déplie |
| `Mouvement.ile` | ressort de 0,42 s, léger rebond | l'île de l'encoche qui s'ouvre ou s'étire, ce qui y apparaît |
| `Mouvement.ileRetour` | ressort de 0,34 s, sans rebond | l'île qui se referme |
| `Mouvement.ileSurvol` | ressort vif de 0,26 s, élastique | l'île sous le pointeur, une jauge, un bouton de l'île qui rebondit |
| `Mouvement.descente` | ressort de 0,46 s | une fenêtre qui descend de l'encoche (Finder, applications) |

- Ils valent `nil` (pas d'animation) quand le Mac demande de réduire les animations.
- Core Animation (grille, carrousels, tiroir) : `CATransaction.setAnimationDuration(Mouvement.duree(x))`. Ces durées suivent
  le geste à quatre doigts et ont été réglées à la main : on les garde, mais toujours à travers `Mouvement.duree`.
- Les listes de résultats et les sélections ne s'animent pas : la vitesse d'abord.
- Le survol ne déplace jamais la sélection. Seuls un clic ou une touche le font.

## Couleurs

- Textes : `.primary`, `.secondary`, `.tertiary`. Jamais un gris fixe.
- Une seule couleur d'accent : `Color.accentColor` (celle choisie dans les Réglages du Mac).
- Les quatre couleurs des parties (Finder bleu, Plein écran orange, Tiroir rose, Presse-papiers jaune) ne servent qu'à
  repérer une partie : icônes des réglages et titres de rubrique. Pas sur les boutons.
- Gris neutres : toujours `Gris` (faits sur la couleur du texte, ils suivent le mode clair ou sombre).

  | Nom | Force | Pour |
  | --- | --- | --- |
  | `Gris.leger` | 0,06 | fond au repos : champ, carte, zone de saisie |
  | `Gris.moyen` | 0,10 | pastille, bouton rond, ligne sous la souris |
  | `Gris.fort` | 0,16 | élément choisi ou appuyé |
  | `Gris.filet` | 0,12 | contour fin d'une carte ou d'un panneau |
  | `Gris.bord` | 0,25 | contour marqué : case à cocher maison, cadre d'un dessin |
- Les lecteurs Spotify et YouTube restent sombres exprès (aux couleurs de ces services) : c'est la seule exception.
- Chaque écran se vérifie en clair et en sombre (`tools/snap.sh`).

## Textes

- Tailles de macOS : 13 pour le texte courant, 11 pour les notes, jamais moins de 10.
- Préférer les styles (`.body`, `.caption`, `.headline`) à une taille écrite en dur.

## Espacements

- Échelle de 4 : 4, 8, 12, 16, 20, 24, 32. Marges de fenêtre 20, entre contrôles liés 8, entre groupes 20.

## Boutons et accessibilité

- Tout bouton sans texte (une icône seule) a une bulle d'aide `.help("Ce qu'il fait (raccourci)")`.
- Ce qui se clique est un `Button`, pas un `onTapGesture` : sinon le clavier et VoiceOver ne le voient pas.

## Ce qui reste à aligner (à faire écran par écran, photos avant et après)

Relevé du 15/11/2026, après le rattachement des 82 arrondis qui tombaient déjà sur l'échelle :

- Arrondis : FAIT le 15/11/2026 (tous passent par `Rayon`).
- Animations : FAIT le 15/11/2026 (toutes passent par `Mouvement` et respectent « Réduire les animations »).
- Gris neutres : FAIT le 15/11/2026 (63 rattachés à `Gris`).
- Tailles sous 10 points : vérifié le 15/11/2026, ce sont toutes des icônes (croix, chevrons), pas du texte. Rien à changer.
- Marges : 24 valeurs, dont beaucoup hors de l'échelle de 4 (3, 5, 7, 9, 11, 14).
- Bulles d'aide : 15/11/2026, ajoutées aux boutons-icônes qui n'en avaient pas (lecteur Spotify, barre de commande, pastille).
  Un relevé plus fin des vues AppKit du tiroir et de la grille reste à faire.
- Étiquettes pour VoiceOver : 36 dans toute l'application, presque toutes dans le Finder.

Ces écrans ne se photographient pas hors écran : le tiroir, la grille, le carrousel, le lecteur Spotify,
le volet du presse-papiers. Les aligner demande de les regarder à l'écran.
