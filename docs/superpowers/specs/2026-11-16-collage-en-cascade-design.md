# Collage en cascade (⌘V V V) — design court

## Pourquoi
Gauthier veut coller un des derniers éléments copiés sans ouvrir le volet du presse-papiers :
⌘V colle le dernier copié comme d'habitude ; ⌘ gardé enfoncé + V de nouveau ouvre une mini-fenêtre
des 5 derniers copiés et passe au précédent ; chaque V suivant descend d'un cran ; lâcher ⌘ colle.
Inspiré de Paste Switch (⌘⇧V qui remplace le collage en place), mais en plus fluide.

## Objectifs / non-objectifs
- Partout sur le Mac (toutes les applis), avec l'historique déjà tenu par `PressePapiers`.
- Les 5 derniers éléments de l'historique (texte, image, fichiers), dans l'ordre de l'historique.
- Non-objectif : recherche, plus de 5 éléments, édition (le volet du presse-papiers reste pour ça).
- Anti-objectif : coller deux fois, ou casser un ⌘V ordinaire.

## Approches
1. **Collage retardé au lâcher de ⌘ (choisi par Gauthier).** Side retient le ⌘V ; au lâcher de ⌘ sans
   second V il colle le dernier copié ; avec un second V la fenêtre s'ouvre. Rien n'est jamais collé deux fois.
2. Collage immédiat puis ⌘Z et recollage (façon Paste Switch) : écarté, ⌘Z annule parfois plus que le collage.

## Fonctionnement décidé
- Un filtre clavier (`CGEvent.tapCreate`, comme `Gestes4Doigts`) intercepte ⌘V « nu » (sans ⇧, ⌥, ⌃) ;
  les répétitions automatiques de V sont ignorées.
- Premier V : bloqué et retenu. ⌘ lâché sans autre V → Side envoie un ⌘V ordinaire (marqué pour ne pas être
  intercepté à son tour).
- Deuxième V : mini-fenêtre (non activante, ne vole pas le focus) au centre de l'écran de la souris, 5 lignes,
  le n° 2 choisi. V suivant : un cran plus bas ; après le 5ᵉ, retour au 1ᵉʳ. Lâcher ⌘ → `recopier(élément)`
  puis ⌘V ordinaire. Échap (⌘ encore enfoncé) → ferme sans rien coller.
- Réglage « Collage en cascade (⌘V V) » dans le volet du presse-papiers, activé par défaut. Sans historique
  (réglage coupé) ou sans autorisation Accessibilité, ⌘V reste celui de macOS.

## Laissé au constructeur (choix de Claude)
- Aspect de la fenêtre : celle de Side (`Rayon`, `Gris`, `Mouvement`), aperçu d'une ligne de texte, vignette
  pour une image, nom pour des fichiers.
- Sécurité : si ⌘ reste enfoncé plus de 10 s sans rien, on relâche le collage retenu (pas de collage perdu).
