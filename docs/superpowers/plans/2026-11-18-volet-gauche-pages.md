# Volet de gauche à plusieurs vues — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un volet sur le bord gauche qui contient plusieurs vues d'Horizon, où l'on passe d'une vue à l'autre avec quatre doigts à l'horizontale quand le pointeur est sur le volet.

**Architecture:** La logique pure (liste des vues, page en cours, reconnaissance du geste) vit dans un nouveau fichier `Sources/VoletGauche.swift`, testable par l'argument `--test-pages`. `VoletVue` (déjà responsable de l'ouverture/fermeture d'une vue par coin) apprend une valeur spéciale de coin, `pile:gauche`, et un changement de page animé par photos. `Glisse` (Square) cède le geste quand le pointeur est sur le volet.

**Tech Stack:** Swift 5, AppKit + SwiftUI, compilé par `swiftc` (pas d'Xcode), module MultitouchSupport via `Trackpads.ecouter`.

**Spec:** `docs/superpowers/specs/2026-11-18-volet-gauche-pages-design.md`

## Global Constraints

- Arrondis et durées : uniquement `Rayon.*` et `Mouvement.*` (`design/DESIGN-SYSTEM.md`), jamais en dur.
- Une clé UserDefaults n'appartient qu'à un fichier. Nouvelles clés : `voletGaucheVues` ([String]), `voletGaucheIndex` (Int), `voletGaucheLargeur` (Double) — toutes dans `VoletGauche.swift`.
- Textes de l'interface en français, via `String(localized:)` / `Text("…")` (catalogue `Localizable.xcstrings`).
- Le volet de droite et le carrousel du bas ne changent pas de comportement.
- Chaque changement est noté en haut de `changes-side.md`, en français simple, dans le même commit.
- Compiler sans installer (pour les tests) :
  `swiftc -Onone -swift-version 5 -parse-as-library -target arm64-apple-macos26.0 Sources/*.swift $(tools/peinard.sh build-test/peinard build-test/Side.app/Contents/Resources) -o build-test/Side.app/Contents/MacOS/Side`
  (si `tools/peinard.sh` ne renvoie rien, cible `arm64-apple-macos14.0`). `./build.sh` seulement à la fin.

## Review Focus

1. Pointeur sur le volet, quatre doigts horizontaux : Square ne doit **pas** changer d'application en même temps (test manuel, tâche 2).
2. Geste un peu diagonal ou pincement sur le volet : pas de changement de page (test `--test-pages`, tâche 1).
3. Pile d'une seule vue, ou vue en cours retirée de la liste dans les réglages : l'index retombe dans les bornes, rien ne plante (test `--test-pages`, tâche 1).
4. Un nouveau geste pendant l'animation d'une page : l'animation dépassée ne fait rien (compteur `tour`, tâche 3).
5. Une application de la pile pas encore lancée : la page montre la carte à icône, puis la vraie fenêtre (tâche 3).

---

### Task 1: Logique pure — liste, page en cours, geste

**Files:**
- Create: `Sources/VoletGauche.swift`
- Modify: `Sources/Side.swift` (près de `--test-geste`, ~ligne 564) : bloc `--test-pages`

**Interfaces:**
- Produces:
  - `final class PileGauche: ObservableObject { static let commun; @Published var vues: [String]; @Published var index: Int; var largeur: Double; var cheminCourant: String?; func page(_ sens: Int) -> Int?; static let sentinelle = "pile:gauche" }`
    - `page(+1)` renvoie l'index suivant ou `nil` au bout (pas de boucle) ; `page(-1)` idem au début.
    - `index` est toujours ramené dans `0..<max(vues.count,1)` quand `vues` change.
    - `largeur` : défaut 520, bornée plus tard par `VoletVue` (380 … 80 % de l'écran).
  - `enum GestePages { static func recevoir(_ doigts: [(Int32, Float, Float)]) -> Int }` — renvoie `+1` (doigts vers la gauche = vue suivante), `-1` (doigts vers la droite), `0` sinon ; une seule fois par geste, remis à zéro quand moins de 3 doigts. Il faut ≥ 4 doigts suivis, trajet horizontal moyen > `0.06`, et `abs(dx) > 1.5 * abs(dy)`. Appelé hors du fil principal.

- [ ] **Step 1: Écrire `--test-pages`** dans `Side.swift`, sur le modèle de `--test-geste` (trames fabriquées, `print` reconnu/refusé, `exit(0)`). Cas et résultats attendus :
  - 4 doigts de x 0.5 → 0.35, y fixe : `+1`
  - 4 doigts de x 0.5 → 0.65 : `-1`
  - 4 doigts en diagonale (dx 0.1, dy 0.1) : `0`
  - pincement (deux doigts vers la gauche, deux vers la droite) : `0`
  - 3 doigts seulement : `0`
  - un geste qui continue après avoir déclenché : une seule réponse non nulle
  - `PileGauche` avec 3 vues, index 2 : `page(+1) == nil`, `page(-1) == 1` ; vues réduites à 1 → `index == 0`.
  Le test utilise une `PileGauche` créée à part (initialiseur `init(défauts: UserDefaults)`) pour ne pas toucher aux vrais réglages.
- [ ] **Step 2: Compiler** — échoue (types absents).
- [ ] **Step 3: Écrire `Sources/VoletGauche.swift`** avec `PileGauche` et `GestePages` comme ci-dessus.
- [ ] **Step 4: Compiler et lancer** `build-test/Side.app/Contents/MacOS/Side --test-pages` — tous les cas donnent le résultat attendu.
- [ ] **Step 5: Commit** `feat(volet gauche): liste des vues et reconnaissance du geste`

### Task 2: Le geste passe au volet quand le pointeur est dessus

**Files:**
- Modify: `Sources/VoletVue.swift` (`surveillerCoin`, `surveillerSortie`)
- Modify: `Sources/PleinEcranGlisse.swift` (`Glisse.recevoir`, avant le tri `phase == 0`)

**Interfaces:**
- Consumes: `GestePages.recevoir`, `PileGauche`.
- Produces: `VoletVue.pointeurSurPile: Bool` (static, écrit sur le fil principal à chaque relevé de souris, lu hors du fil principal) — vrai quand le volet ouvert est la pile et que le pointeur est dans son cadre ; `VoletVue.commun.changerDePage(_ sens: Int)` (déclaré ici, vide jusqu'à la tâche 3, appelé sur le fil principal).

- [ ] **Step 1:** Dans `Glisse.recevoir`, si `VoletVue.pointeurSurPile` : passer les doigts à `GestePages.recevoir`, mettre `phase = -1` pour ce geste (Square n'en fait rien), et si le résultat ≠ 0, `DispatchQueue.main.async { VoletVue.commun.changerDePage(r) }`. Le sens suit `Glisse.inverse` comme Square.
- [ ] **Step 2:** Mettre à jour `pointeurSurPile` dans `surveillerSortie` (même zone que la fermeture automatique, sans la marge de 60 pt).
- [ ] **Step 3: Compiler et relancer `--test-pages`** — toujours vert.
- [ ] **Step 4: Commit** `feat(volet gauche): Square cède le geste horizontal sur le volet`

### Task 3: Le volet ouvre la pile et change de page

**Files:**
- Modify: `Sources/VoletVue.swift`

**Interfaces:**
- Consumes: `PileGauche.commun` (`vues`, `index`, `cheminCourant`, `largeur`, `page`), `PileGauche.sentinelle`.
- Produces: `func changerDePage(_ sens: Int)` ; `func allerÀ(_ index: Int)` (utilisé par les points, tâche 4).

- [ ] **Step 1:** Un coin dont la valeur est `PileGauche.sentinelle` ouvre `PileGauche.commun.cheminCourant` sur le bord gauche (rouvre donc la dernière vue). `préparer()` et `rendreLesFenêtres()` couvrent aussi toutes les vues de la pile.
- [ ] **Step 2:** Pour la pile, `cadreCible` et la mémoire de largeur à la fermeture utilisent `PileGauche.commun.largeur` (largeur commune) au lieu de `largeurs[chemin]`.
- [ ] **Step 3:** `allerÀ(i)` : photo de la fenêtre en cours posée dans `panneau` à sa place, fenêtre en cours rangée au garage ; photo (ou carte à icône) de la nouvelle vue dans un second panneau hors du cadre, du côté d'où elle arrive ; les deux glissent ensemble d'une largeur (durée `Mouvement.ample`, même courbe que `glisser`) ; à l'arrivée, `poser(...)` met la vraie fenêtre. Nouveau `tour` à chaque appel : une animation dépassée ne fait rien. `PileGauche.commun.index = i`. Au bout de la liste, petit rebond (décalage de 24 pt aller-retour, `Mouvement.bref`).
- [ ] **Step 4:** `changerDePage(sens)` = `PileGauche.commun.page(sens).map(allerÀ)` ou le rebond.
- [ ] **Step 5: Compiler** sans erreur ; `--test-pages` vert.
- [ ] **Step 6: Commit** `feat(volet gauche): changement de page animé`

### Task 4: Les points en haut du volet

**Files:**
- Modify: `Sources/VoletGauche.swift` (vue SwiftUI `PointsPile` + petit `NSPanel` non activant)
- Modify: `Sources/VoletVue.swift` (montrer/cacher les points avec la pile)

**Interfaces:**
- Consumes: `PileGauche.commun`, `VoletVue.commun.allerÀ(_:)`.

- [ ] **Step 1:** `PointsPile` : un point par vue, le point courant plein, les autres à 35 % ; clic sur un point = `allerÀ(i)` ; aide au survol = nom de la vue. Pastille de fond en verre, arrondi `Rayon.*`. Masquée s'il n'y a qu'une vue.
- [ ] **Step 2:** Panneau des points centré en haut du cadre du volet (8 pt sous le haut de la zone visible), au-dessus de la fenêtre (`.floating`), affiché quand la pile est arrivée, caché à la fermeture et pendant un changement de page.
- [ ] **Step 3: Compiler** sans erreur.
- [ ] **Step 4: Commit** `feat(volet gauche): points de navigation`

### Task 5: Réglages

**Files:**
- Modify: `Sources/PanneauBasReglages.swift` (`CoinsActifsView.menu` et une nouvelle section sous les coins)

**Interfaces:**
- Consumes: `PileGauche.commun`, `PileGauche.sentinelle`, `PanneauBas.commun.vuesHorizon`.

- [ ] **Step 1:** Dans le menu des coins **de gauche seulement** (`.hautGauche`, `.basGauche`), entrée « Volet de gauche (plusieurs vues) », icône `rectangle.stack`, valeur `vue:` + sentinelle (donc rangée dans `VoletVue.coins` comme une vue). Couleur du coin : orange, comme les vues.
- [ ] **Step 2:** Section « Volet de gauche » : liste des vues de la pile (nom sans `.app`), glisser pour réordonner, bouton moins pour retirer, menu « Ajouter une vue » parmi `vuesHorizon` non encore présentes ; 5 vues au plus (le menu se grise ensuite).
- [ ] **Step 3: Vérifier l'écran** avec `tools/snap.sh /tmp/side-pile --rafraichir` et regarder le volet de réglages concerné, en clair et en sombre.
- [ ] **Step 4: Commit** `feat(volet gauche): réglages de la pile`

### Task 6: Note, installation, essai réel

**Files:**
- Modify: `changes-side.md` (en haut)

- [ ] **Step 1:** Note en français simple : volet de gauche à plusieurs vues, quatre doigts à l'horizontale sur le volet, points cliquables, réglages.
- [ ] **Step 2:** `./build.sh`.
- [ ] **Step 3: Essai réel** (Gauthier) : régler un coin de gauche sur la pile avec 3 vues ; ouvrir ; quatre doigts à gauche/droite sur le volet → la vue change, Square ne bouge pas ; pointeur hors du volet → le geste refait défiler Square ; fermer puis rouvrir → même vue ; tirer le bord → toutes les vues prennent la largeur.
- [ ] **Step 4: Commit** `docs: note du volet de gauche à plusieurs vues`
