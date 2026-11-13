<p align="center"><img src="Icone/Side.png" width="128" alt="Icône de Side"></p>

# Side

Une app pour organiser le Mac autour de trois sortes d'applications :

- **les applications de travail** (navigateur, mail, montage…) : chacune remplit l'écran, sur un seul bureau, et une grille ou quatre doigts passent de l'une à l'autre ;
- **les applications de passage** (une note, un réglage, la musique) : rangées dans un tiroir qu'on ouvre d'un geste, le temps d'un coup d'œil ;
- **le Finder**, toujours disponible par-dessus tout.

Depuis novembre 2026, Side contient aussi Square (le plein écran et la grille), qui était une app à part.

## Ce que fait Side

### Le Finder

- **S'ouvre d'un geste** : un coin de l'écran, un geste de souris, quatre doigts sur le trackpad ou un raccourci clavier (⌘@ par défaut).
- **Un vrai navigateur de fichiers** : barre latérale (favoris, récents, tags, disques et serveurs connectés), onglets, présentations en icônes, liste ou colonnes, recherche Spotlight, menu du clic droit, aperçu avec Espace.
- **Les raccourcis du Finder** : sélection multiple (⌘-clic, Maj-clic, Maj + flèches, ⌘A), ⌘C, ⌘V, ⌥⌘V, ⌘D, ⌘I, ⇧⌘N, ⌘⌫, ⌘O, ⌘↑, ⌘[ ⌘], ⌘1 à ⌘3, ⌘F, et ⇧⌘H, ⇧⌘D, ⇧⌘O, ⌥⌘L, ⇧⌘A, ⇧⌘U pour aller aux dossiers.
- **Une zone de dépôt** : pendant un glisser, une case apparaît à côté de la carte. Ce qu'on y pose reste sous la main, même Side fermé, pour le glisser ailleurs plus tard.
- **Des colonnes épinglées** : glisser un dossier sur le bord droit de la carte le garde affiché en colonne.
- **Un historique du copier-coller**, gardé 7 jours : un volet glisse depuis le bord droit de l'écran, par un coin (en bas à droite par défaut) ou un raccourci clavier (⌃⌥V par défaut). Chaque élément copié y est une carte selon sa nature (image, lien, couleur, fichier…) ; un clic la recopie. Un second onglet, « Enregistrés », garde pour toujours, par groupes, les liens qu'on colle souvent : il suffit d'y glisser un élément.

### Le plein écran (ex-Square)

- **Le bouton vert** remplit l'écran sans le plein écran d'Apple : tout reste sur un seul bureau, et Side passe par-dessus. Les nouvelles fenêtres peuvent s'agrandir toutes seules ; une vidéo aux proportions fixes (QuickTime) se pose sur un fond noir.
- **La grille** : un coin de l'écran ou ⌥ Tab affiche toutes les applications de travail en vignettes, avec un Dock. On y change l'ordre, on partage l'écran entre deux à quatre fenêtres, on ferme une application.
- **Quatre doigts vers la gauche ou la droite** : un carrousel passe d'une application à l'autre. ⌘1 à ⌘9 vont droit à l'une d'elles.
- **Changer de place** : ⌃⌥↓ envoie l'application de devant au tiroir, ⌃⌥↑ la ramène en plein écran (aussi au clic droit dans la grille).

### Le tiroir

Il arrive du bord opposé au Finder (du bas, en général).

- **Multimédia** : YouTube dans une page intégrée, un lecteur Spotify, ou n'importe quel site ajouté dans les réglages (Deezer, Apple Music, Twitch…). Un seul est affiché, les autres continuent de jouer, même tiroir fermé.
- **Tes applications** : la case « + » range une application dans le tiroir ; sa fenêtre ne traîne plus sur le bureau. Le tiroir en montre une à la fois, sur toute la place : prolonger le geste à quatre doigts fait apparaître un mini carrousel vertical, comme celui du plein écran, et une colonne d'icônes à droite permet d'en choisir une. (Les afficher toutes en bande reste possible dans les réglages.)
- **S'ouvre comme le Finder** : son propre coin actif, son raccourci (⌃⌥Espace par défaut), quatre doigts dans l'autre sens.

### Les réglages

Une fenêtre façon Réglages Système : coins actifs, raccourcis, gestes, puis le Finder et le tiroir, chacun avec ses volets.

## Installation

Il faut un Mac à puce Apple, macOS 14 ou plus récent, et les outils de ligne de commande d'Apple (`xcode-select --install`).

```bash
git clone https://github.com/GauthierAube/Side.git
cd Side
./build.sh
```

Le script compile Side, l'installe dans `~/Applications` et le lance. Une icône apparaît dans la barre des menus, et une courte présentation s'affiche à la première ouverture du Finder, puis du tiroir.

À savoir : sans certificat de développeur Apple dans le trousseau, Side est signé avec une signature jetable. macOS redemande alors les autorisations (accès aux dossiers) après chaque compilation.

## Autorisations et vie privée

- Le Finder de Side ne se connecte à aucun serveur. Le tiroir, lui, affiche les sites que tu y mets (YouTube…) : ils voient ce que voit un navigateur. Side ne récolte rien.
- macOS demande l'accès aux dossiers que Side affiche (Documents, Téléchargements, Bureau).
- macOS demande aussi l'accès au réseau local : Side s'en sert uniquement pour repérer les ordinateurs qui partagent des fichiers (rubrique Réseau). On peut refuser ; la rubrique reste alors vide.
- L'autorisation Accessibilité sert au tiroir : sans elle, Side ne peut pas y ranger la fenêtre d'une autre application. Le Finder et la partie multimédia marchent sans.
- L'autorisation Enregistrement de l'écran est facultative : elle rend plus joli le glissement des applications du tiroir.
- Le lecteur Spotify pilote l'application Spotify du Mac. Son accueil, sa recherche et sa bibliothèque demandent un accès développeur Spotify (gratuit), expliqué dans le lecteur ; le jeton reste dans le trousseau du Mac.
- Couper les publicités de YouTube est un réglage, désactivé au départ : c'est contraire aux conditions d'utilisation de YouTube, à chacun de décider.
- L'historique du copier-coller garde 7 jours de textes et de noms de fichiers copiés, dans un fichier lisible par toi seul (`~/Library/Application Support/Side/presse-papiers.json`), et les 40 dernières images copiées dans le dossier `images` à côté. Les mots de passe copiés depuis un gestionnaire de mots de passe ne sont jamais écrits sur le disque. Un réglage coupe l'historique et efface tout.
- Pour montrer l'aperçu d'un lien copié (image et titre du site), Side contacte ce site, et seulement quand le volet du presse-papiers affiche le lien. Un réglage coupe ces aperçus.

## Limites connues

- Projet personnel, écrit rapidement avec l'aide d'une IA : il reste sûrement des bugs.
- L'interface existe en français et en anglais : elle suit la langue du Mac (anglais si le Mac n'est pas en français), et se choisit dans les réglages.
- Le Finder tient dans un seul fichier, `Sources/Side.swift` ; le tiroir dans les fichiers `Sources/PanneauBas*.swift`.
- Le tiroir déplace les fenêtres d'autres applications : certaines s'y prêtent mal (taille minimale, plusieurs bureaux, plein écran d'Apple).
- YouTube change souvent sa page : les réglages propres à YouTube peuvent demander une mise à jour.
- AirDrop n'est pas pris en charge. La corbeille s'affiche dans la carte, mais demande l'« Accès complet au disque ». Pour le réseau, Side repère les ordinateurs mais la première connexion se fait dans le Finder.

## L'application compagne

Side va bien avec une autre petite application, signalée dans ses réglages :

- [Mulot](https://github.com/GauthierAube/Mulot) : les boutons et les gestes de la souris MX Master, sans le logiciel de Logitech.

## Licence

MIT — voir [LICENSE](LICENSE).

## Historique

Tous les changements sont notés dans [changes-side.md](changes-side.md), du plus récent au plus ancien.
