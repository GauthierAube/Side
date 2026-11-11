<p align="center"><img src="Icone/Side.png" width="128" alt="Icône de Side"></p>

# Side

Un petit Finder qui apparaît par-dessus n'importe quelle app du Mac, même en plein écran.

Side est une carte flottante : on la fait venir d'un geste, on attrape un fichier, on la referme. Pas besoin de quitter l'app en cours ni de changer de bureau.

## Ce que fait Side

- **S'ouvre d'un geste** : un coin de l'écran, une secousse de souris ou un raccourci clavier (⌘@ par défaut).
- **Un vrai navigateur de fichiers** : barre latérale (favoris, récents, tags, disques et serveurs connectés), onglets, présentations en icônes, liste ou colonnes, recherche Spotlight, menu du clic droit, aperçu avec Espace.
- **Une zone de dépôt** : pendant un glisser, une case apparaît à côté de la carte. Ce qu'on y pose reste sous la main, même Side fermé, pour le glisser ailleurs plus tard.
- **Des colonnes épinglées** : glisser un dossier sur le bord droit de la carte le garde affiché en colonne.
- **Un mini-Dock** : les apps ouvertes ou favorites, et des raccourcis de l'app Raccourcis de macOS.
- **Un historique du copier-coller** : il se déroule en passant la souris sur son icône, au bout du mini-Dock.
- **Des réglages** façon Réglages Système : position et taille de la carte, flou de l'arrière-plan, options reprises du Finder.

## Installation

Il faut un Mac à puce Apple, macOS 14 ou plus récent, et les outils de ligne de commande d'Apple (`xcode-select --install`).

```bash
git clone https://github.com/GauthierAube/Side.git
cd Side
./build.sh
```

Le script compile Side, l'installe dans `~/Applications` et le lance. Une icône apparaît dans la barre des menus, et une courte présentation s'affiche à la première ouverture.

À savoir : sans certificat de développeur Apple dans le trousseau, Side est signé avec une signature jetable. macOS redemande alors les autorisations (accès aux dossiers) après chaque compilation.

## Autorisations et vie privée

- Side ne se connecte à aucun serveur : rien ne quitte le Mac.
- macOS demande l'accès aux dossiers que Side affiche (Documents, Téléchargements, Bureau).
- macOS demande aussi l'accès au réseau local : Side s'en sert uniquement pour repérer les ordinateurs qui partagent des fichiers (rubrique Réseau). On peut refuser ; la rubrique reste alors vide.
- L'autorisation Accessibilité est facultative ; elle ne sert qu'à rejoindre une app en plein écran depuis le mini-Dock.
- L'historique du copier-coller garde 7 jours de textes et de noms de fichiers copiés, dans un fichier lisible par toi seul (`~/Library/Application Support/Nook/presse-papiers.json`). Les images et les mots de passe copiés depuis un gestionnaire de mots de passe ne sont jamais écrits sur le disque. Un réglage coupe l'historique et efface tout.

## Limites connues

- Projet personnel, écrit rapidement avec l'aide d'une IA : il reste sûrement des bugs.
- L'interface est en français uniquement.
- Tout le code tient dans un seul fichier, `Sources/Tiroir.swift`. Le fichier et l'identifiant de l'app portent encore le premier nom du projet, « Tiroir ».
- La corbeille et AirDrop ne sont pas pris en charge. Pour le réseau, Side repère les ordinateurs mais la première connexion se fait dans le Finder.

## Licence

MIT — voir [LICENSE](LICENSE).
