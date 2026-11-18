# Volet de gauche à plusieurs vues d'Horizon — design court (18/11/2026)

## Pourquoi
Gauthier veut garder plusieurs vues d'Horizon (Aujourd'hui, CRM, Projet 1…) sous la main sur le bord gauche et passer
de l'une à l'autre d'un geste, sans refermer le volet ni retourner dans un coin. Aujourd'hui (`Sources/VoletVue.swift`),
un coin actif = une seule application ; trois vues à gauche demanderaient trois coins, et aucun passage de l'une à l'autre.

## Objectifs
- Un « volet de gauche » qui contient une liste ordonnée de vues d'Horizon (2 à 5).
- Quatre doigts à l'horizontale, **seulement quand le pointeur est sur ce volet**, passent à la vue suivante ou précédente.
- Les vues défilent comme des pages, à l'horizontale ; des points en haut du volet montrent la vue en cours (et se cliquent).

## Hors sujet
- Le volet de droite reste à une seule vue, comme aujourd'hui.
- Le carrousel des applications du bas (panneau bas) ne change pas.
- Pas de raccourcis clavier ⌘1/⌘2/⌘3 dans cette version.

## À ne surtout pas faire
- Le geste ne doit jamais changer aussi d'application dans le carrousel de Square (plein écran) quand le pointeur est sur le volet.
- Hors du volet, le geste à quatre doigts horizontal doit continuer de servir à Square exactement comme avant.
- Pas de saccade : comme à l'ouverture, le glissement se fait avec les photos des fenêtres, les vraies prennent la place à l'arrivée.

## Approches envisagées
1. **Quatre doigts horizontaux, seulement sur le volet** — retenue par Gauthier. Naturel, et ne gêne pas le reste.
2. Trois doigts — écartée : « glisser avec trois doigts » est activé sur son Mac, le geste sélectionnerait du texte ou déplacerait la fenêtre.
3. Seulement des points cliquables / clavier — écartée comme moyen principal (moins naturel), mais les points restent en complément.

Sens choisi : horizontal (le vertical se confondrait avec le défilement dans la vue).

## Ce qui est décidé
- Réglages, Coins actifs : pour les deux coins de gauche, une nouvelle entrée de menu « Volet de gauche (plusieurs vues) ».
- Une petite section de réglages liste les vues du volet de gauche : ajouter (parmi les vues d'Horizon installées), retirer, réordonner.
- Quatre doigts vers la gauche = vue suivante, vers la droite = vue précédente ; on s'arrête aux bouts (pas de boucle).

## Mes choix (à corriger si besoin)
- Le volet rouvre sur la dernière vue montrée.
- Toutes les vues du volet de gauche partagent la même largeur (le glissement reste net) ; tirer le bord change la largeur de toutes.
- Le geste se déclenche une fois passé un seuil (il ne suit pas les doigts au pixel près) : plus simple et plus sûr pour une première version.
- Toutes les vues de la liste sont lancées et rangées hors de l'écran au démarrage, comme aujourd'hui, pour arriver tout de suite.

## Laissé au développeur
- Brancher le tri du geste dans `FiltreHorizontalBas` / le module de Square pour que le volet passe avant Square quand le pointeur est dessus.
- Le dessin des points et l'animation de page (durées `Mouvement`, arrondis `Rayon`).
- Note dans `changes-side.md`.
