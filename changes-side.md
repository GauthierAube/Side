# Historique des changements de Side

Ce fichier garde la trace de tout ce qui change dans Side, du plus récent au plus ancien.
Il est mis à jour à chaque modification, en même temps que le code.

---


## 12/11/2026, nuit

### Presse-papiers : un onglet « Enregistrés » pour les liens qu'on retrouve toujours
- Le volet a deux onglets, comme dans les apps d'Apple : « Presse-papiers » (l'historique, 7 jours) et « Enregistrés » (les liens ou petits textes qu'on colle souvent, gardés sans limite de nombre ni de durée).
- **Glisser** un élément du presse-papiers sur les onglets l'enregistre aussitôt, avec le titre de sa page. En restant un instant sur les onglets, « Enregistrés » s'ouvre : on lâche alors l'élément sur le groupe voulu. Un lien glissé depuis un navigateur marche aussi.
- Chaque lien enregistré est une carte, comme dans le presse-papiers : l'image de partage du site, son icône, le titre. Les groupes ont de grands en-têtes qu'on replie d'un clic ; glisser un lien sur un autre groupe l'y déplace.
- Le formulaire d'ajout ou de modification s'affiche au-dessus de la liste, toujours visible (il laissait un grand vide dans la liste).
- Un clic copie le lien (sans l'ajouter à l'historique) ; le clic droit l'ouvre, le modifie, le monte, le descend ou le supprime. Le + ajoute un lien à la main. La recherche cherche dans l'onglet affiché.

### Presse-papiers : les images restent, les liens ont leur aperçu
- **Les images** copiées n'étaient gardées qu'en mémoire : elles disparaissaient à chaque redémarrage de Side. Les 40 dernières sont maintenant gardées sur le Mac (lisibles par toi seul), et effacées avec l'historique.
- **Une image copiée depuis un navigateur** arrivait avec son adresse, et Side gardait l'adresse au lieu de l'image. C'est l'image qui est gardée.
- **Les liens** montrent l'aperçu officiel du site, comme dans Messages : l'image de partage, le titre et l'icône. Side contacte le site pour cela, seulement quand le volet affiche le lien ; un réglage le coupe.

### Le presse-papiers : un raccourci, et sa place dans la présentation
- **Raccourci clavier** pour ouvrir et fermer le volet : Contrôle + Option + V au départ. Il se change ou s'efface dans Réglages › Général › Presse-papiers.
- **La présentation** de la première ouverture a un cinquième écran : le pointeur va dans le coin en bas à droite, le volet glisse depuis le bord, un clic recopie une carte. Les pastilles rappellent le coin et le raccourci réglés.

### Le presse-papiers a son volet
- **Avant :** l'historique du copier-coller se déroulait depuis le mini-Dock, qui n'est plus affiché.
- **Maintenant :** un volet étroit glisse depuis le bord droit de l'écran, sur toute sa hauteur, quand le pointeur va dans un coin (en bas à droite au départ). Y revenir, Échap ou un clic ailleurs le referment.
- Chaque élément copié est une carte selon sa nature, avec sa pastille de couleur : une image se montre, un lien affiche son site, une couleur (« #D86F4A ») se voit, un fichier a son icône, un mot de passe reste masqué. Des pastilles en haut filtrent par nature, et un champ cherche dans les textes.
- Un clic recopie la carte (et referme le volet, si on veut) ; on peut aussi la glisser ailleurs ; le clic droit épingle, supprime ou ouvre un lien.
- Réglages › Général › Presse-papiers : le coin actif du volet, sa largeur, et s'il se referme après une copie.

### Tiroir : la note retrouvée, et les captures d'écran respectées
- **Une note dont la première ligne a changé** n'était plus retrouvée : le tiroir affichait un message d'erreur, puis réclamait la note en boucle en cliquant dans le menu de Notes. Il retrouve maintenant la note même si son titre a été retouché ; si elle a vraiment disparu, il le dit une fois et n'insiste pas.
- **Pendant une capture d'écran (⌘⇧4, ⌘⇧5)**, tiroir ouvert : Échap annule bien la capture au lieu de refermer le tiroir, un clic ne le referme pas, et aucune fenêtre n'est ramenée devant.
- La capture est reconnue à sa fenêtre de sélection : Side et le tiroir se rouvrent dès qu'elle est finie, sans attendre quelques secondes.

### La barre des lecteurs se règle sur place
- **Clic droit** sur la barre (Spotify, YouTube, Arte…) : retirer ce lecteur, en ajouter un parmi les mêmes propositions que dans les réglages, ou ouvrir les réglages du tiroir.
- **Glisser** un lecteur le change de place : les autres se poussent, et l'ordre est retenu.

### Le bord du tiroir se tire vraiment
- **Avant :** pour régler la hauteur du tiroir, il fallait viser une bande très fine ; le plus souvent, c'était la fenêtre d'une tuile qui attrapait le clic et se redimensionnait à la place.
- **Maintenant :** le bord du tiroir (quelques points au-dehors, toute sa marge au-dedans) lui est réservé, devant les fenêtres. Le pointeur y devient une double flèche.

### Side en anglais
- **Avant :** Side n'existait qu'en français.
- **Maintenant :** Side s'affiche en anglais sur tout Mac qui n'est pas réglé en français, et reste en français sinon. Réglages › Général › Langue permet de choisir : automatique (langue du Mac), français ou English ; Side redémarre pour changer de langue.
- Les textes viennent d'un catalogue de traduction Apple (`Localizable.xcstrings`), mis à jour à chaque compilation quand Xcode est installé ; les fichiers compilés (`Resources/en.lproj`) sont gardés dans le dépôt, pour compiler sans Xcode. Les demandes d'autorisation de macOS sont traduites aussi.
- Les dates suivent la langue de Side au lieu d'être toujours en français.
- Le tiroir retrouve le menu « Ouvrir la note dans une nouvelle fenêtre » de Notes, que Notes soit en français ou en anglais.
## 12/11/2026, soir

### Tiroir : une seule note, et des tuiles qui restent visibles
- La liste « + » propose « Une seule note… » : on choisit une note dans la liste de ses notes, elle s'ouvre seule dans sa propre fenêtre au lieu de toute l'application Notes.
- **Avant :** un clic dans le tiroir pouvait le faire passer devant les fenêtres de ses tuiles, qui semblaient disparaître. **Maintenant :** après chaque clic, le tiroir se replace sous ses tuiles.

### Tiroir : fermer une application qui quitte avec sa fenêtre
- **Avant :** fermer la fenêtre d'une application comme Réglages Système (qui quitte alors complètement) refermait le tiroir, et l'application y revenait à l'ouverture suivante.
- **Maintenant :** le tiroir reste ouvert et la tuile de l'application s'en va.

### Une présentation en images
- **Avant :** la visite guidée posait des bulles de texte sur la carte ouverte.
- **Maintenant :** une fenêtre à part montre quatre écrans en mouvement, presque sans mots : le Finder (quatre doigts sur le trackpad), les fichiers et dossiers (favoris, aperçu avec Espace), la zone de dépôt, le tiroir (quatre doigts dans l'autre sens). Sous chaque écran, des pastilles rappellent les déclencheurs réellement réglés (coin, secousse, raccourci, quatre doigts).
- Elle s'affiche à la première ouverture et se retrouve dans les réglages (« Revoir la présentation »).

### Side se met en retrait pendant une capture d'écran
- Pendant une capture (⌘⇧4, ⌘⇧5), ni le coin, ni la secousse, ni les quatre doigts n'ouvrent le Finder ou le tiroir : on peut viser un coin de l'écran sans rien déclencher.

### Side a maintenant deux panneaux : le Finder et le tiroir
- **Avant :** Side était un Finder flottant, avec un mini-Dock.
- **Maintenant :** un second panneau, le tiroir, arrive du bord opposé au Finder. Il a une partie multimédia (YouTube dans une page intégrée, un lecteur Spotify, ou n'importe quel site ajouté dans les réglages) et une bande où ranger les fenêtres de ses applications à usage rapide (case « + »).
- Le tiroir a son coin actif, son raccourci (⌃⌥Espace au départ) et son geste à quatre doigts, dans l'autre sens que le Finder.
- La visite guidée présente le Finder, puis ouvre le tiroir pour le présenter à son tour.

### Réglages repensés
- La fenêtre est rangée comme les Réglages Système : Général ; Ouvrir et fermer (Coins actifs, Raccourcis clavier, Souris et trackpad) ; Finder ; Tiroir.
- Coins actifs : un écran dessiné avec un menu à chaque coin, pour choisir ce que chaque coin ouvre.
- Le mini-Dock et les raccourcis de l'app Raccourcis ne sont plus proposés dans les réglages.
- Réglages > Général signale les applications compagnes, Square et Mulot.

---

## 12/11/2026, matin

### Secouer pendant un glisser ouvre la zone de dépôt seule
- **Avant :** Side fermé, secouer la souris avec un fichier sous le pointeur ouvrait toute la carte.
- **Maintenant :** seule la zone de dépôt apparaît, à côté du pointeur, façon Dropover. C'est la même zone que celle de la carte.
- Secouer encore pendant le glisser ajoute une autre zone.
- Rien n'est posé : la zone disparaît à la fin du glisser. Un fichier posé : elle reste à l'écran (une minute au moins si le cadenas est ouvert).
- Ce geste marche pendant un glisser même si le geste de souris est désactivé dans les réglages, ou réglé sur le cercle.

### Carte venue du haut : zone de dépôt en bas
- Quand la carte arrive du haut, la zone de dépôt se place en bas de la carte, et les zones suivantes s'empilent au-dessus.
- Dans les autres cas, rien ne change : zone en haut, les suivantes en dessous.
- L'ancien emplacement choisi à la main pour la zone est oublié une fois, pour repartir du nouvel emplacement.

### Présentation en colonnes : aperçu du fichier sélectionné
- **Le problème :** en présentation « colonnes », cliquer sur un fichier laissait la partie droite vide.
- **Maintenant :** le fichier sélectionné s'affiche à droite, comme dans le Finder : grand aperçu, nom, type et taille, puis les informations (Créé le, Modifié le, Ouvert le, Dimensions, Durée ou Pages selon le fichier) et les tags.
- L'aperçu suit la sélection, à la souris comme aux flèches du clavier. Un double-clic sur l'aperçu ouvre le fichier.
- Pas repris du Finder : le lien « Plus de détails » et l'ajout de tags depuis ce panneau.

---

## 11/11/2026, soir

### Une app déposée dans le mini-Dock se pose là où tu la lâches
- **Le problème :** une app déposée dans le mini-Dock arrivait toujours au bout, à droite. Il fallait la déplacer ensuite.
- **Maintenant :** pendant le glisser, les icônes s'écartent sous la souris pour lui faire une place. Elle se pose là où tu la lâches.
- Si tu ressors du mini-Dock sans lâcher, la place se referme et rien ne change.
- Lâchée dans le vide du mini-Dock (pas sur une icône), elle se range au bout, comme avant.

### Le mini-Dock reprend les apps du Dock au premier lancement
- Au tout premier lancement, le mini-Dock affiche les apps gardées dans le Dock de macOS, dans le même ordre.
- Aucune autorisation n'est demandée pour cela.
- Ensuite le mini-Dock est indépendant : modifier le Dock de macOS ne change plus rien dans Side.
- Avant, le mini-Dock partait vide, avec seulement les apps ouvertes.

### Les favoris du Finder sont repris au premier lancement
- Au tout premier lancement, la rubrique Favoris de Side reprend les dossiers favoris de la barre latérale du Finder, dans le même ordre.
- Aucune autorisation n'est demandée pour cela.
- Si le Finder n'a aucun dossier favori : Bureau, Documents et Téléchargements.
- Ensuite les favoris de Side sont indépendants : en ajouter ou en retirer dans le Finder ne change plus rien dans Side.
- Avant, Side partait des dossiers de Documents commençant par deux chiffres, plus Téléchargements.

### Les réglages de départ sont ceux de Gauthier
Sur un Mac où Side n'a jamais été réglé, il démarre maintenant ainsi (tes propres réglages ne changent pas) :
- **Ouverture :** coin actif en bas à gauche (zone de 50 points), glissement à quatre doigts activé, geste du cercle plutôt que la secousse, secousse désactivée, sensibilité 67 %.
- **Carte :** hauteur 53 % de l'écran, largeur 53 % seule et 70 % avec colonnes, colonnes épinglées de 248 points, barre latérale de 438 points, fond presque transparent (14 %).
- **Mini-Dock :** sous la carte, icônes de 45 points, grossissement + 25 %, sans le bouton « Apps ».
- **Barre latérale :** Fichiers récents, Dossiers récents, iCloud Drive, Maison, Applications, Tags, Disques, Réseau. Tags et Réseau repliés.
- **Présentation :** grande zone en colonnes, Fichiers récents en grille.
- Non repris, car personnels : tes apps favorites, masquées et leur ordre, ton raccourci, ta colonne épinglée.

### Un point sous les apps ouvertes
- Comme dans le Dock de macOS, un petit point marque les apps ouvertes dans le mini-Dock.
- Il se place sur le bord extérieur du mini-Dock : dessous si le mini-Dock est sous la carte, dessus s'il est au-dessus, sur le côté s'il est à gauche ou à droite.
- Il est blanc en mode sombre et foncé en mode clair.

### Le mini-Dock grossit comme le Dock de macOS
- **Avant :** seule l'icône sous la souris grossissait un peu, d'un coup, sans toucher à ses voisines.
- **Maintenant :** l'icône sous le pointeur grossit le plus, ses voisines un peu moins, et ainsi de suite jusqu'à deux icônes et demie de distance. Les icônes s'écartent pour se faire de la place et l'effet suit la souris en continu.
- Les icônes grossissent vers la carte : le bord extérieur du mini-Dock ne bouge pas.
- La loupe s'allume et s'éteint en douceur quand le pointeur entre ou sort. Elle se met en pause pendant qu'on déplace une icône.
- Réglage : Réglages, mini-Dock, « Grossissement au survol », de « Aucun » à + 100 %. Par défaut + 50 %.
- Le presse-papiers a sa propre petite pastille, à côté du mini-Dock. Son icône ne grossit pas et ne bouge pas quand les apps s'écartent.
- Méthode : la courbe en cosinus utilisée par les reproductions connues du Dock. Apple ne publie pas sa formule exacte.

### Les apps d'Apple apparaissent dans Applications
- **Le problème :** le dossier Applications ne montrait que les apps installées par toi. Mail, Notes, Photos, Calendrier et les autres apps d'Apple manquaient, car macOS les range à part, dans le dossier Système.
- **Maintenant :** elles sont réunies dans la même liste, comme dans le Finder. Pareil pour le dossier Utilitaires.

### Ranger les apps du mini-Dock dans l'ordre voulu
- Glisse une icône d'app sur une autre : elle prend sa place et les suivantes se décalent, comme dans le Dock de macOS.
- Pendant le glisser, la place de l'icône reste vide dans le mini-Dock : on voit où elle va se poser.
- L'ordre est retenu. Une app ouverte que tu n'as jamais déplacée se range à la fin.
- Sortir l'icône du mini-Dock et la lâcher la retire toujours, comme avant.

### Le presse-papiers se déroule du côté libre
- **Le problème :** carte en haut de l'écran et mini-Dock dessous, la liste du presse-papiers montait au-dessus de l'icône et cachait la carte.
- **Maintenant :** la liste se déroule sous l'icône, dans la place libre. Pareil dans l'autre sens : carte en bas et mini-Dock au-dessus, la liste monte.
- S'il reste peu de place sous le mini-Dock, la liste raccourcit pour tenir dans l'écran. En dessous de 200 points de libre, elle repasse par-dessus la carte, comme avant.
- Un liseré apparaissait autour de la liste quand elle sortait de la carte : c'était l'ombre de la fenêtre qui suivait le halo de la liste. Il n'y a plus qu'une seule ombre.
- Un petit triangle relie la liste à l'icône du presse-papiers.

### Dossiers récents : 6 dossiers, en grille
- La rubrique « Dossiers récents » montre 6 dossiers au lieu de 60.
- Elle s'affiche en grille par défaut, et garde sa propre présentation, séparée des autres dossiers.
- Réglage : Réglages, Finder, « Nombre de dossiers récents » (3, 6, 9, 12, 20 ou 40).

---

## 11/11/2026, fin d'après-midi

### Les captures d'écran arrivent toutes seules dans une zone de dépôt
- Dès qu'une capture d'écran est enregistrée, Side la range dans une zone de dépôt. Elle est prête à être glissée dans un mail, un message ou un dossier.
- Les captures se regroupent dans la même zone. Si aucune zone n'est libre, une nouvelle zone apparaît en dessous.
- Une capture déjà déposée à la main depuis la vignette de macOS n'est pas ajoutée une deuxième fois.
- Side reconnaît les captures grâce à l'index de recherche du Mac : peu importe le dossier où elles sont enregistrées.
- Réglage : Réglages, Zones de dépôt, « Ajouter mes captures d'écran à une zone de dépôt ». Activé par défaut.
- La zone apparaît tout de suite à l'écran, même quand Side est fermé et le cadenas ouvert. Elle reste une minute, comme une vignette de macOS qui durerait plus longtemps. Tant que la souris est dessus ou qu'un glisser est en cours, elle ne part pas.

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
