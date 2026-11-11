# Historique des changements de Side

Ce fichier garde la trace de tout ce qui change dans Side, du plus récent au plus ancien.
Il est mis à jour à chaque modification, en même temps que le code.

---

## 11/11/2026, fin d'après-midi

### Les captures d'écran arrivent toutes seules dans une zone de dépôt
- Dès qu'une capture d'écran est enregistrée, Side la range dans une zone de dépôt. Elle est prête à être glissée dans un mail, un message ou un dossier.
- Les captures se regroupent dans la même zone. Si aucune zone n'est libre, une nouvelle zone apparaît en dessous.
- Une capture déjà déposée à la main depuis la vignette de macOS n'est pas ajoutée une deuxième fois.
- Side reconnaît les captures grâce à l'index de recherche du Mac : peu importe le dossier où elles sont enregistrées.
- Réglage : Réglages, Zones de dépôt, « Ajouter mes captures d'écran à une zone de dépôt ». Activé par défaut.
- Avec le cadenas ouvert, la zone apparaît à la prochaine ouverture de Side. Avec le cadenas fermé, elle apparaît tout de suite à l'écran.

### La zone de dépôt bouge avec la carte, comme une seule fenêtre
- **Le problème :** à l'ouverture par les quatre doigts, la zone de dépôt apparaissait d'un coup alors que la carte suivait encore les doigts. Les deux n'arrivaient pas en même temps.
- **Maintenant :** la zone suit les doigts avec la carte. Elle part du même endroit, fait le même trajet, à la même vitesse et avec la même transparence, à l'ouverture comme à la fermeture.
- Même chose avec le raccourci, la souris ou le coin : la zone fait tout le trajet avec la carte, au lieu d'un petit glissement de son côté.

### Zone de dépôt invisible : corrigé
- **Le problème :** quand on ouvrait la carte avec les quatre doigts, la zone de dépôt restait invisible. Elle était bien là, mais complètement transparente, donc impossible de déposer quoi que ce soit.
- **La cause :** à l'ouverture, la zone devient transparente pour apparaître en fondu avec la carte. Avec les quatre doigts, ce fondu n'était jamais lancé.
- **La correction :** la zone arrive maintenant en fondu, quelle que soit la façon d'ouvrir la carte. Une sécurité ajoutée empêche aussi qu'une zone affichée reste transparente.
- Le journal de test (`--journal`) note maintenant chaque glisser et chaque affichage de la zone de dépôt.

### Dossier de données renommé « Side »
- L'historique du copier-coller et les fichiers déposés étaient rangés dans `~/Library/Application Support/Nook`. Ce dossier s'appelle maintenant `Side`.
- Au lancement, l'app déplace automatiquement l'ancien dossier, une seule fois.
- Le dossier du projet sur le Mac passe de `~/Github/tiroir` à `~/Github/side`. Le lien GitHub ne change pas.

### Renommage complet de « Tiroir » en « Side »
- Le fichier de code s'appelle maintenant `Sources/Side.swift`.
- L'identifiant interne de l'app passe de `com.gauthieraube.tiroir` à `com.gauthieraube.side`.
- Au premier lancement, l'app recopie automatiquement les anciens réglages : favoris, raccourci, position, gestes.
- **À savoir :** macOS lie les autorisations à cet identifiant. Il peut redemander une fois l'accès à l'Accessibilité. Pour le donner : Réglages Système, puis Confidentialité et sécurité, puis Accessibilité, et cocher Side.

### Quatre doigts : plus d'à-coup quand on lâche
- Quand on lâche les doigts en plein geste, la carte continue à la même vitesse, puis ralentit en douceur jusqu'à sa place ou jusqu'au bord.
- Avant, elle repartait avec une animation toujours identique. À l'ouverture elle faisait un bond ; à la fermeture elle s'arrêtait net puis repartait.

### La carte suit les quatre doigts
- La carte glisse depuis le bord de l'écran et suit le geste des quatre doigts, à l'ouverture comme à la fermeture.
- Nuage iCloud affiché au bord droit.
- Le clavier redevient utilisable après l'aperçu d'un fichier.

---

## 11/11/2026, début d'après-midi

### En-tête et recherche
- Le bouton + est retiré. Pour un nouvel onglet : Commande + T, ou le menu.
- La recherche devient un bouton rond qui se déplie au clic, pour laisser la place au nom du dossier.

### Ouvertures et fermetures involontaires
- Le cercle de souris ouvre Side mais ne le referme plus.
- Le coin actif demande d'abord un vrai éloignement de la souris avant de rouvrir.
- Après l'ouverture, le cercle attend que la souris s'arrête avant d'en reconnaître un autre.

### Sélection et flèches du clavier
- Les flèches marchent comme dans le Finder, en grille, en liste et en colonnes.
- L'affichage de la sélection n'a plus une flèche de retard.
- Sans sélection, on part du fichier sous la souris, dans sa colonne.
- En grille, la sélection suit aussi pendant l'aperçu, et gauche/droite s'arrêtent au bord de la ligne.
- Après une suppression, la sélection passe au fichier suivant, au précédent, ou au dossier parent, dans toutes les colonnes.

### Taille de la carte et colonnes épinglées
- Les bords et les coins de la carte servent à la redimensionner. Ils sont plus larges, avec les pointeurs habituels de macOS.
- Le trait entre le Finder et les colonnes partage la place sans changer la largeur de la carte.
- Colonnes épinglées : nom affiché en entier, choix présentation et grille dans le menu, boutons Précédent/Suivant toujours visibles.
- Les dossiers récents n'affichent plus les paquets (projets Logic, etc.).

### Ouverture et fermeture façon macOS
- Court glissement avec fondu, sans rebond.

### Mini-Dock et bouton Apps
- Bouton Apps dans le mini-Dock : recherche et grille d'apps. Le panneau sort de l'icône, sous le mini-Dock, aussi large que lui.
- Clic droit sur le bouton Apps pour le masquer.
- On retire une app du mini-Dock en la tirant dehors : une croix apparaît, comme dans le Dock.
- Les clics sur le mini-Dock sont mieux reconnus.

### Geste à quatre doigts (premières versions)
- Glisser quatre doigts sur le trackpad ouvre et ferme Side. C'est un réglage, désactivé par défaut.
- On choisit le sens : le sens choisi ouvre, le sens inverse ferme.
- Mesure doigt par doigt et seuil plus court. Le défilement parasite de la page est bloqué pendant le geste.

### Glisser-déposer
- Glisser un fichier le déplace ; avec Option, il le copie.
- La zone de dépôt oublie les fichiers qui ne sont plus là.
- Doublon au dépôt corrigé, et une zone vide apparaît automatiquement.
- Le chemin du dossier est affiché dans le titre.

---

## 11/11/2026, fin de matinée

### Zone de dépôt
- Zone de dépôt réunie avec la carte, et déplaçable en la tirant par son fond.
- Elle ne clignote plus, et la sélection y est visible.

### Presse-papiers
- Historique du copier-coller dans le mini-Dock : liste au survol, épinglage, recherche avec une loupe.
- Il garde 7 jours de textes et de noms de fichiers copiés.

### Fichiers et dossiers
- Un fichier iCloud pas encore téléchargé affiche un nuage ; un clic le télécharge.
- Rubrique Réseau.
- Un alias de dossier s'ouvre dans Side.
- Lignes resserrées dans les listes et les colonnes.

### Clic en dehors
- Un clic dans le vide à côté du mini-Dock ferme aussi Side, et un clic un peu glissé compte comme un clic.

### Geste de souris
- Choix simple entre secouer la souris et faire un cercle.
- Un petit cercle suffit, il n'a pas besoin d'être fermé, et les tremblements sont adoucis.
- Une secousse ne déclenche plus le cercle.
- Pendant un dépôt, Option ou le retour de la souris garde Side ouvert.

---

## 11/11/2026, matin

### Première version publiée sur GitHub
- Side : un Finder flottant pour macOS, accessible par-dessus une app en plein écran.
- Ouverture par le coin actif, une secousse de souris ou le raccourci Commande + @.
- Barre latérale façon Finder, onglets, vues Icônes/Liste/Colonnes, colonnes épinglées, zones de dépôt, mini-Dock d'apps, réglages façon Réglages Système.
