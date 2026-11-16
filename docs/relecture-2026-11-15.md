# Relecture de Side du 15/11/2026 (méthode BAMA)

Tout le code (21 700 lignes) a été relu par quatre relecteurs. Une trentaine de bugs sont corrigés
(voir `changes-side.md`). Ce document garde ce qui reste.

## Bugs repérés : état au 15/11/2026 au soir

Tous corrigés (voir `changes-side.md`), sauf :

- Photos des fenêtres de la grille gardées en mémoire grille fermée (environ 15 Mo par fenêtre). Laissé exprès :
  les vider rendrait la réouverture de la grille plus lente. À revoir si la mémoire de Side pose problème.
- Fenêtres agrandies par Side qui gardent leur taille quand Side quitte. Pas un bug : c'est le comportement attendu.
- Non essayés à l'écran (corrigés d'après le code) : second écran à droite, disque débranché, trackpad Bluetooth
  reconnecté, boîte de dialogue sur une tuile du tiroir.

## Architecture : trois pistes

### 1. Découper `Side.swift` (7 700 lignes)  [Forte]  FAIT le 15/11/2026
Signal : BAMA alerte à 600 lignes par fichier, agit à 1 000. `Side.swift` mélange les réglages, les fichiers, la carte,
la barre latérale, la fenêtre de réglages et tout le pilotage de l'application.
Proposition : le découper sans rien changer au code, par simple déplacement, un fichier par enregistrement :
`Reglages.swift`, `Fichiers.swift`, `PressePapiers.swift`, `Carte.swift`, `BarreLaterale.swift`, `FenetreReglages.swift`, `Pilotage.swift`.
Preuve : les 38 photos de `tools/snap.sh` identiques avant et après.
Même traitement ensuite pour `PanneauBas.swift` (3 400 lignes) et `PleinEcran.swift` (2 450 lignes).

### 2. Un seul gestionnaire de raccourcis  [Forte]  FAIT le 15/11/2026
Signal : le même genre de bug est arrivé trois fois (trois gestionnaires, trois saisies de raccourci copiées-collées,
deux réglages sur la même clé).
Proposition : un seul type `Raccourcis` qui enregistre, refuse les doublons, et une seule ligne de réglage « choisir un raccourci ».

### 3. Sortir la logique pure pour pouvoir la tester  [À explorer]
Signal : aucun test automatique. La reconnaissance des gestes, le choix des noms de fichiers, le tri, la recherche
sont mêlés à l'affichage.
Proposition : les isoler dans des fichiers sans interface, avec un petit programme de test lancé par `tools/`.

Recommandation : la piste 1 d'abord (sans risque, vérifiable par photos), puis la 2.
