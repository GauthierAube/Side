# Revue d'architecture du 16/11/2026 : deux écrans (méthode BAMA)

Contexte : sur le Mac mini, Side tourne avec deux écrans (Studio Display principal, 2880 × 1620 ;
LG UltraFine à sa gauche, 2304 × 1296, alignés en haut). Le tiroir et le plein écran s'y comportent mal,
alors que tout va bien sur le MacBook Air (un seul écran). La relecture du 15/11 notait déjà
« second écran : non essayé à l'écran ».

Relevé : Side choisit un écran à **77 endroits** dans 20 fichiers, avec quatre règles différentes :

| Règle | Endroits | Ce qu'elle veut dire |
| --- | --- | --- |
| `NSScreen.main` | 35 | l'écran de la fenêtre active (pas forcément celui de la souris) |
| `NSScreen.screens.first` | 30 | l'écran principal (celui de la barre des menus) |
| `panneau.screen ?? NSScreen.main` | 12 | l'écran où le tiroir se trouve déjà |
| écran sous la souris | 7 | là où l'on travaille (carte du Finder, pastille, presse-papiers, grille) |

Un module `Ecrans` existe déjà (`PleinEcranModele.swift` : identifiant, cadre global, zone visible),
mais seul le plein écran s'en sert. Le tiroir refait tout à la main, et la fonction privée d'Apple
`CGSCopyManagedDisplaySpaces` est déclarée deux fois (`PanneauBas.swift`, `PleinEcran.swift`).

## Bugs repérés (d'après le code)

1. **Le tiroir s'ouvre sur l'écran de la fenêtre active** (`NSScreen.main`, Tiroir+OuvrirFermer:14), pas sur celui
   de la souris. Souris sur le Studio, fenêtre active sur le LG : le tiroir sort sur le LG.
2. **Largeur des tuiles calculée sur le mauvais écran** : `Tiroir+Tuiles:31` et `PanneauBas:368` lisent `NSScreen.main`
   alors que le tiroir est peut-être sur l'autre écran (2880 contre 2304 points de large) : tuiles trop larges ou trop
   étroites, fond gris.
3. **« Plein écran d'Apple » lu sur le premier écran seulement** (`dansUnPleinÉcranApple`, Tiroir+OuvrirFermer:290) :
   une app en plein écran d'Apple sur le Studio fait croire au tiroir ouvert sur le LG qu'il ne peut pas montrer
   ses tuiles (bandeau « macOS empêche d'y afficher les tuiles »), et l'inverse.
4. **Garage incohérent** : le correctif du 15/11 (`PanneauBas.bordGarage`, après le bord droit de *tous* les écrans)
   n'est pas appliqué partout. `Tiroir+Ajouter:166` et `Tiroir+BoutonsFenetres:131` utilisent encore le bord droit
   de l'écran principal. Avec un écran à droite (MacBook Air + écran externe), la fenêtre « garée » s'y affiche.
5. **Fenêtres rendues sur un autre écran** : `rendreLaFenêtre`, la grande fenêtre de Notes et les boutons vert/jaune
   (Tiroir+Emprunts:214 et 424, Tiroir+BoutonsFenetres:166 et 223, Tiroir+OuvrirFermer:319) centrent la fenêtre
   sur `NSScreen.main`, pas sur l'écran du tiroir.

## Écrans : un seul module pour choisir l'écran, convertir et garer  [Forte]  ÉTAPES 1 À 4 FAITES le 16/11/2026

Fichiers : 20 fichiers, 77 endroits (surtout `Tiroir+*.swift`, `PanneauBas.swift`, `PleinEcranModele.swift`).
Signal : le même genre de bug revient (garage corrigé le 15/11 mais pas partout) ; une fonctionnalité (le tiroir)
touche plus de 6 fichiers pour une seule question : « sur quel écran ? ».
Problème : chaque appel choisit sa propre règle. Corriger le tiroir pour deux écrans demande aujourd'hui de
retoucher 40 endroits, et d'en oublier.
Proposition : `Sources/Ecrans.swift`, qui reprend l'`Ecrans` du plein écran et devient le seul à lire `NSScreen` :

```swift
enum Ecrans {
    static var deTravail: NSScreen               // LA règle : l'écran sous la souris (sinon le principal)
    static func contenant(_ r: CGRect) -> NSScreen  // r en coordonnées AX (origine en haut à gauche)
    static func versAX(_ r: NSRect) -> CGRect    // et versNS : une seule conversion, avec la hauteur du principal
    static func versNS(_ r: CGRect) -> NSRect
    static func zoneVisible(_ e: NSScreen) -> CGRect   // en coordonnées AX
    static func garage(taille: CGSize) -> CGRect       // après le bord droit de tous les écrans
    static func pleinEcranApple(sur e: NSScreen) -> Bool   // l'espace affiché sur CET écran
}
```

Avantages : localité (une règle à un seul endroit), levier (les 77 appels deviennent simples). La logique pure
(conversion, garage, choix d'écran) prend une liste d'écrans en valeurs simples : elle se teste sans écran réel.
Preuve que rien ne change : `Side --test-ecrans` (nouveau, comme `--test-fleches`) vérifie conversions, garage et choix
d'écran sur trois dispositions : un écran ; écran externe à gauche, aligné en haut (Mac mini) ; écran externe à droite
(MacBook Air). Plus `tools/snap.sh` identique à l'octet avant/après pour les étapes 1 et 2.
Plan (un commit par étape) :
1. Créer `Ecrans.swift` et `--test-ecrans`, sans toucher aux appels. Une seule déclaration de `CGSCopyManagedDisplaySpaces`.
2. Passer les conversions et le garage sur `Ecrans` (bug 4 corrigé, rien d'autre ne change).
3. Le tiroir prend `Ecrans.deTravail` à l'ouverture et garde son écran ensuite (`panneau.screen`) : bugs 1, 2 et 5.
4. `pleinEcranApple(sur:)` par écran : bug 3.
5. Plein écran, carte du Finder, presse-papiers : même règle, puis essai à l'écran sur les deux Mac.

## Considéré, pas recommandé

- Corriger les cinq bugs un par un, sans module : plus rapide aujourd'hui, mais la prochaine fonction refera le choix
  d'écran à sa façon (c'est exactement ce qui s'est passé avec le garage).
- Un tiroir par écran : beaucoup plus de travail, et rien ne dit que c'est utile.

## Recommandation

Le module `Écrans` (Forte), étapes 1 à 4 d'abord. Décision à prendre avant l'étape 3 : sur quel écran le tiroir
s'ouvre-t-il ? (Proposé : celui de la souris, comme la carte du Finder.)

## Fait le 16/11/2026

Étapes 1 à 4, un commit chacune. Décision : le tiroir s'ouvre sur l'écran de la souris. Essai réel sur le Mac mini :
souris sur le LG, le tiroir sort en bas du LG (1843 points, 80 % de 2304) ; souris sur le Studio, en bas du Studio
(2304 points, 80 % de 2880). Reste l'étape 5 (plein écran, carte du Finder, presse-papiers : 13 `NSScreen.main` restants, hors du tiroir).
