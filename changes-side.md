# Historique des changements de Side

Ce fichier garde la trace de tout ce qui change dans Side, du plus récent au plus ancien.
Il est mis à jour à chaque modification, en même temps que le code.

---


## 13/11/2026

### Finder : Imprimer
- Clic droit sur un fichier : « Imprimer » le confie à son application pour l'imprimer, comme Fichier > Imprimer dans le Finder. Avec plusieurs fichiers sélectionnés, ils sont tous imprimés.

### Finder : la zone de dépôt compte comme le Finder
- Avec « Fermer quand la souris en sort », passer la souris sur la zone de dépôt ne referme plus le Finder.

### Les quatre parties de Side, activables et reconnaissables
- Réglages > Général : « Les parties de Side » permet d'activer ou de couper le Finder, le plein écran (grille, carrousel, agrandissement, numéros), le tiroir et le presse-papiers. Une partie coupée ne s'ouvre plus, ni par son coin, ni par son raccourci, ni par son geste ; ses réglages restent.
- Chaque partie a sa couleur et son symbole : Finder en bleu, plein écran en orange, tiroir en rose, presse-papiers en jaune. La barre latérale des réglages en reprend la couleur pour tous ses volets, et chaque volet affiche en tête la partie où l'on est (avec « désactivé » et un bouton « Activer » si elle est coupée).

### Tiroir : redimensionnement en direct
- Une application à largeur fixe mais à hauteur libre (Réglages Système) prend maintenant toute la hauteur du tiroir, et se redimensionne en hauteur avec lui : la taille fixe est retenue dimension par dimension.
- **Le relais** : attraper un bord du tiroir (haut, gauche, droite) revient à attraper le bord de la fenêtre de l'application affichée. C'est l'application qui se redimensionne elle-même, comme partout sur le Mac, et le tiroir (coin multimédia, barre d'icônes) ne fait que la suivre ; au lâcher, il se recentre. Les applications à taille fixe gardent l'ancien redimensionnement.
- Après un redimensionnement rapide, une application occupée pouvait ignorer sa nouvelle taille (seul le coin multimédia suivait) : sa place est revérifiée juste après, et corrigée.
- **Les applications du tiroir ne sont plus agrandies en plein écran** : depuis la fusion, l'agrandissement automatique ne retrouvait plus la liste du tiroir et agrandissait chaque application à sa première apparition (clignotements, application restée en grand, tuile crue fermée).
- Pendant le redimensionnement, la fenêtre est posée en deux réglages dans le bon ordre (moins d'à-coups), et le tiroir ne suit une fenêtre que si on la tire vraiment par son bord.
- Tirer un bord du tiroir (haut ou côtés) redimensionne en direct la vraie fenêtre de l'application affichée, comme si on la tirait elle-même ; plus de photo figée pendant le geste.
- Élargir la fenêtre de l'application par son bord fait suivre le tiroir : la barre d'icônes est poussée au lieu d'être recouverte, puis le tiroir se recentre d'un mouvement doux.
- Le petit trait au-dessus du tiroir est retiré (le tiroir se redimensionne par tous ses bords).

### Mes applications, grille et carrousel
- Réglages : les lignes de « Mes applications » se réordonnent en les glissant vers le haut ou le bas (elles suivent la souris).
- Réorganiser la grille change aussi les numéros de « Mes applications » : les deux façons de ranger disent la même chose.
- Carrousel : une petite pastille ronde avec le numéro de la case est posée sur le coin de l'icône de chaque application, pour savoir où l'on est.
- Réglages du carrousel : l'aperçu s'efface tout seul peu après le dernier réglage, ou au premier clic (il restait affiché).

### Carrousel plein écran : la roue du tiroir, couchée
- Roue resserrée, cartes plus petites. Réglages, Carrousel : « Forme » permet de choisir entre la bande (par défaut, qui s'arrête aux deux bouts) et la roue sans fin.
- Le carrousel à quatre doigts reprend le mini carrousel du tiroir, à l'horizontale : les cartes sont posées sur une roue, rapetissent et s'effacent en s'éloignant, puis reviennent de l'autre côté. Il tourne sans fin : après la dernière fenêtre revient la première (avant, il s'arrêtait aux deux bouts).
- Même chose avec la molette ou les crans de la souris.

### Nettoyage d'après la fusion avec Square
- Réglages, Général : Square ne figure plus parmi les applications compagnes (il fait partie de Side) ; il ne reste que Mulot.
- Les textes qui parlaient de Square comme d'une application à part sont réécrits (tiroir, fenêtres, raccourci de la grille). L'ancien menu de Square, inutilisé, est retiré.
- « La visite guidée de Side, en sept étapes » (elle en avait cinq avant la fusion).

### Tiroir : le glissement horizontal revient aux applications
- Avec une application à la fois, le glissement à deux doigts de côté n'est plus pris par le tiroir : on peut de nouveau balayer un message dans Messages ou Mail, revenir en arrière dans Safari…

### Mes applications : un numéro pour chaque application de travail
- Réglages, Grille : une liste numérotée de 1 à 9 (Safari en 1, Claude en 2, Mail en 3…). On ajoute une application avec le bouton ou en la déposant depuis le Finder, on glisse une ligne sur une autre pour changer son numéro.
- Chaque application garde sa case dans la grille, sa place dans le carrousel et son raccourci (⌘ + chiffre). Si elle n'est pas ouverte, son raccourci l'ouvre.
- Au lancement de Side, les applications de la liste qui ne sont pas ouvertes s'ouvrent, dans l'ordre (réglable).
- Partage entre plusieurs Mac : un petit fichier dans iCloud Drive (dossier Side), relu au lancement et chaque minute.

### Tiroir : pas de Finder
- Le Finder ne peut plus être mis dans le tiroir (il n'a souvent aucune fenêtre à prêter, et Side a son propre Finder). Un Finder déjà ajouté en est retiré.
- Clic droit (ou ⌃-clic) sur la carte d'une application du tiroir : le même menu que sur son icône de la barre.

### Zone de dépôt refaite sur le modèle de Dropover
- **Plus de zones vides en trop** : la croix retire la zone (il en reste toujours une), et les zones vides restées d'avant sont retirées. Attraper un fichier ne montre plus qu'une zone ; les suivantes naissent de la secousse.
- **Quatre zones au plus, sur la hauteur du Finder** : les zones s'empilent (la nouvelle au-dessus) et rapetissent ensemble s'il le faut pour ne jamais dépasser la hauteur du Finder de Side.
- **Secousse fiable** : pendant un glisser, Side suit lui-même le pointeur (macOS ne transmettait pas toujours les mouvements, notamment avec des dossiers ou depuis la zone elle-même).
- **Nouvelle zone seulement à la secousse** : une zone vide n'apparaît plus toute seule dès qu'on attrape un fichier. Elle se crée en secouant ce qu'on tient (une seule zone vide à la fois). Sans secousse, on pose dans une zone déjà là.
- **Captures d'écran** : chaque capture va dans sa propre zone (vide ou nouvelle), jamais dans une zone qui contient déjà quelque chose.
- **Taille** : la tuile fait 198 × 207 points, comme l'étagère de Dropover (au lieu de 150 × 150), avec de grands coins arrondis.
- **La pile** : les fichiers déposés s'empilent en vignettes (aperçu du fichier). Attraper la pile les emmène tous d'un coup.
- **Dépliée** : la pastille « 3 éléments › » (ou un double-clic sur la pile) ouvre la grille des fichiers, avec nom et poids, pour les prendre un par un ; la flèche de retour la replie.
- **Ce qui sort de la zone la quitte** : un fichier déposé ailleurs disparaît de la zone, et une zone vidée se referme.
- La croix vide la zone ; le cadenas est remplacé par « Garder à l'écran quand Side est fermé » dans le menu.
- Un clic dans la zone ne peut plus refermer le Finder de Side.

### Quatre doigts : réponse immédiate après une pause
- Side attendait en arrière-plan et macOS le mettait en sommeil (App Nap) au bout de quelques minutes : le premier geste à quatre doigts tardait. Side reste maintenant toujours prêt (sans empêcher la veille du Mac).
- Au réveil du Mac, le trackpad est relancé s'il a cessé d'envoyer ses touches.

### Une seule présentation
- Retouches : le Finder arrive de son bord réglé (le haut) dans « Trois places » ; les animations ne reviennent plus en arrière avant de recommencer (grille, carrousel, Finder) ; « Changer d'avis » montre le bouton jaune qui range au tiroir, puis le bouton vert du tiroir qui ressort l'app au centre de l'écran (pas en plein écran).
- Les présentations de Side et de Square, qui s'enchaînaient dans deux fenêtres (onze écrans), deviennent une seule présentation de sept écrans : Trois places, Le plein écran, Passer d'une app à l'autre, Le tiroir (avec le défilement des apps aux quatre doigts), Changer d'avis (bouton jaune, ⌃⌥↑ / ⌃⌥↓, clic droit dans la barre), Le Finder, Le presse-papiers.
- Le mot d'accueil séparé du tiroir n'apparaît plus.
- Presse-papiers : mêmes coins arrondis que le Finder.

### Applications à taille fixe et liste d'ajout
- Une application qui refuse de grandir (la Calculette…) est centrée dans sa place du tiroir, au lieu d'être collée à gauche avec du vide à côté. Sa taille est retenue.
- Liste « + » : plus de petit coin carré clair qui dépasse (coins arrondis par un masque).

### Boutons jaune et vert dans le tiroir
- **Vert** : l'application sort du tiroir à sa taille, au centre de l'écran, avec un petit glissement (plus d'agrandissement en plein écran). Elle reste une application du tiroir et y retourne à sa prochaine ouverture.
- **Jaune** : range, comme partout dans macOS : le tiroir se referme, l'application y reste.
- Le menu d'Apple « Déplacer et redimensionner » ne s'ouvre plus au survol du bouton vert d'une application du tiroir.

### Fond noir à l'ouverture du tiroir
- Le fond noir posé derrière les vidéos à proportions fixes prenait certaines applications du tiroir (Mots de passe, une note) pour de telles vidéos et recouvrait tout l'écran. Les fenêtres du tiroir sont désormais ignorées.

### Grille, barre du tiroir, transitions et icône
- **Grille** : plus de numéros au survol des cases. À côté de la croix, une flèche vers le bas envoie l'application au tiroir.
- **Barre du tiroir** : on glisse les icônes pour changer l'ordre, comme dans le Dock (les autres s'écartent). Clic droit sur une icône : Afficher, Passer en plein écran, Retirer du tiroir, Quitter.
- **Transitions** : passer du tiroir au plein écran (ou l'inverse) n'est plus saccadé. Une photo de la fenêtre grandit en un seul mouvement de sa place dans le tiroir jusqu'à tout l'écran, ou rétrécit jusqu'au tiroir pendant qu'il s'ouvre ; la vraie fenêtre se pose à l'arrivée. Une fenêtre à taille fixe (la Calculette) garde sa taille.
- **Icône** : un triptyque, trois volets pour trois sortes d'applications (le Finder à gauche, les applications de travail au centre, le tiroir en bas).

### Changer une application de place avec les boutons des fenêtres
- **Bouton jaune** d'une application de travail : elle rejoint le tiroir (qui s'ouvre sur elle), au lieu de se cacher dans le Dock. Option + clic : le Dock, comme d'habitude. Réglage : Réglages › Tiroir.
- **Bouton vert** d'une application du tiroir : elle en sort pour de bon et remplit l'écran.
- Les raccourcis ⌃⌥↓ et ⌃⌥↑, le clic droit de la grille et la liste du « + » restent possibles.

### Le reste
- Colonne du tiroir réunie dans une seule barre flottante (fond flou réglable comme le Finder), icônes nettes, l'application affichée mise en avant.
- Vidéo YouTube du tiroir : ses coins sont arrondis par un liseré de la couleur du fond posé par-dessus (l'image de la vidéo, dessinée à part par le Mac, ignore tout arrondi) ; la lueur colorée de YouTube derrière la vidéo est retirée dans la tuile.
- Mini carrousel : une fois apparu, il ne referme jamais le tiroir pendant que les doigts sont posés, même en redescendant.

### Tiroir : sa largeur se règle
- Tirer le bord gauche du tiroir (celui du coin multimédia) ou son bord droit le réduit ou l'élargit ; il reste centré, et l'application affichée suit. Le pointeur devient une double flèche horizontale sur ces bords.
- Réglages › Tiroir › « Largeur du tiroir » : la même chose, de 30 % à 100 % de l'écran.
- Une application qui refuse d'être plus étroite (Réglages Système : 865 points) fixe la largeur minimum du tiroir : il ne peut plus être réduit en dessous, et s'élargit tout seul s'il l'était. Le tiroir apprend cette largeur la première fois qu'il pose l'application.
- Plus fluide : la colonne d'icônes ne redemande plus les icônes à chaque mouvement, et tirer un bord ne recalcule le tiroir qu'une fois à la fois.
- Quand la place manque, le coin multimédia cède d'abord (jusqu'à sa largeur minimum) et l'application garde la sienne, comme dans les vues partagées de macOS. Le tiroir peut ainsi rétrécir même avec Réglages Système.
- Une application plus haute que le tiroir (Réglages Système) ne dépasse plus : le tiroir retient sa hauteur minimum et grandit.
- Le mini carrousel est une roue, comme les sélecteurs à molette d'Apple : en tournant, les cartes rapetissent et s'effacent vers l'arrière, puis reviennent de l'autre côté en grossissant. Plus de saut au moment de faire le tour.
- Cartes du mini carrousel un peu plus grandes (un quart de la hauteur de l'application, de 90 à 160 points).
- Coins arrondis de la vidéo YouTube rétablis : l'image de la vidéo, dessinée à part par le Mac, est arrondie elle-même.
- Le clavier va directement à l'application affichée dans le tiroir, dès l'ouverture et à chaque changement d'application : plus besoin de cliquer dedans.

### Tiroir : une application à la fois
- Le tiroir montre le coin multimédia (fixe, à gauche) et une seule application, sur toute la place restante.
- Un geste court à quatre doigts l'ouvre sur la dernière application regardée. En prolongeant le geste, un **mini carrousel vertical** apparaît par-dessus l'application : le même que celui du plein écran, en miniature, aussi sensible (une application tous les 7 % de la hauteur du trackpad). Les cartes suivent les doigts ; doigts levés, celle du centre grandit jusqu'à sa place et l'application la remplace. Tiroir déjà ouvert, repartir dans le sens d'ouverture fait aussi apparaître le mini carrousel. Les cartes sont de vraies miniatures, et le mini carrousel tourne sans fin : après la dernière application revient la première, dans les deux sens.
- À droite, une colonne : le « + » en haut, une icône par application (celle qu'on regarde est mise en avant, un clic en amène une autre), la roue dentée en bas.
- Réglages › Tiroir › « Une application à la fois » : décoché, on retrouve la bande de tuiles.

### Changer une application de place d'un geste
- **⌃⌥↓** envoie l'application de devant au tiroir (qui s'ouvre sur elle) ; **⌃⌥↑** fait passer l'application du tiroir en plein écran.
- Clic droit sur une case de la grille : « Envoyer au tiroir » (au-dessus de « Quitter »).
- Dans la liste du « + » du tiroir, chaque application a un bouton bleu « Passer en plein écran ».
- Le tiroir range une application entière, pas une seule fenêtre. Une application à taille fixe (la Calculette) quitte le tiroir sans pouvoir remplir l'écran.

### Side et Square ne font plus qu'une app
- **Avant :** deux apps qui se parlaient sans arrêt (coin de la grille, vidéo plein écran, fenêtres du tiroir), avec des réglages, une langue et des gestes en double.
- **Maintenant :** une seule app. Elle garde tout de Side (réglages, liens, tuiles, autorisations) et reprend tout de Square : la grille (coin, ⌥ Tab, Dock), le carrousel à quatre doigts, l'agrandissement des fenêtres sans le plein écran d'Apple, l'écran partagé, les raccourcis ⌘1 à ⌘9, les vidéos sur fond noir.
- Les réglages de Square sont repris une fois, tout seuls, au premier lancement. L'ancienne app Square est arrêtée et mise à la corbeille.
- Une seule fenêtre de réglages : nouvelle rubrique « Plein écran » (Grille, Dock, Carrousel, Fenêtres). Les coins actifs proposent la « Grille des applications ».
- Une seule icône dans la barre des menus, avec « Afficher la grille » et « Agrandir la fenêtre en cours ».
- La présentation de Side se poursuit par celle du plein écran.
- Mulot envoie toujours ses commandes de grille et de carrousel : l'app les écoute.
- Le nom définitif de l'app reste à choisir ; l'identité technique de Side est gardée pour ne rien perdre.

### Finder : les raccourcis sur un clavier français
- **La vraie cause du ⌘A qui ne marchait pas :** les raccourcis étaient repérés par l'emplacement des touches d'un clavier américain. Sur un clavier AZERTY, la touche A est ailleurs : ⌘A n'était jamais reconnu (et ⌘W réagissait à ⌘Z).
- **Maintenant :** chaque raccourci est reconnu à sa lettre, quel que soit le clavier (AZERTY, QWERTY…).

### Finder : ⌘A après un clic, et la double flèche du tiroir
- **⌘A après un clic sur un fichier :** le menu « Édition › Tout sélectionner » de Side attrapait le raccourci avant le Finder. Les raccourcis avec ⌘ du Finder passent maintenant en premier.
- **Double flèche du tiroir :** elle n'apparaît plus quand une autre fenêtre (les réglages de Side, la liste du « + », une autre application) est par-dessus le bord du tiroir.

### Réglages : la barre latérale défile
- **Avant :** avec la rubrique « Presse-papiers » en plus, la barre latérale dépassait de la fenêtre : on ne pouvait pas la faire défiler, et « Général » passait sous les boutons rouge, jaune et vert.
- **Maintenant :** elle commence sous ces boutons et défile si besoin. La fenêtre est plus haute au départ (tout y tient) et peut être agrandie.

### Finder : sélection multiple et raccourcis du Finder
- **Avant :** un seul fichier pouvait être sélectionné ; ⌘A, Maj-clic et ⌘-clic ne faisaient rien.
- **Maintenant, comme dans le Finder :** ⌘-clic ajoute ou retire un élément ; Maj-clic sélectionne toute la plage depuis le dernier clic ; Maj + flèches étendent la sélection ; ⌘A sélectionne tout ce qui est affiché. Un clic droit sur un élément sélectionné garde la sélection.
- **Raccourcis ajoutés :** ⌘C (copier les fichiers), ⌘V (coller dans le dossier), ⌥⌘V (déplacer ici), ⌘D (dupliquer), ⌘I (informations), ⇧⌘N (nouveau dossier, prêt à être renommé), ⌘⌫ (corbeille, pour toute la sélection), ⌘O et ⌘↓ (ouvrir), ⌘↑ (dossier parent), ⌘[ et ⌘] (précédent, suivant), ⌘1, ⌘2, ⌘3 (icônes, liste, colonnes), ⌘F (rechercher), et les dossiers : ⇧⌘H (départ), ⇧⌘D (bureau), ⇧⌘O (documents), ⌥⌘L (téléchargements), ⇧⌘A (applications), ⇧⌘U (utilitaires). Restent : Espace (Coup d'œil), Entrée (renommer), ⌘T et ⌘W (onglets).

### Tiroir : la vidéo a ses marges
- Dans la tuile YouTube, la vidéo n'est plus collée aux bords : elle a les mêmes marges que le reste de la page.

### Tiroir : le coin multimédia aux couleurs de macOS
- Les lecteurs (YouTube, Spotify, sites) et les photos des tuiles ont le grand arrondi « continu » des fenêtres de macOS, au lieu d'un petit arrondi simple.
- Les onglets des lecteurs ressemblent à un contrôle segmenté de macOS : une piste en gélule et le lecteur choisi en pastille claire. Leur fond est celui du Finder de Side (flou, puis teinte de fenêtre) : il suit le mode clair ou sombre, et le réglage Apparence › Fond › Opacité, qui vaut désormais pour le Finder, le volet du presse-papiers et le tiroir.

### Tiroir : le clavier reste à Side, Square ignore les tuiles
- **Avant :** pour faire passer les tuiles devant, le tiroir activait leurs applications ; la dernière gardait le clavier (le champ de recherche de Mots de passe prenait la main), et un clic droit sur la barre des lecteurs se refermait aussitôt.
- **Maintenant :** une fois les tuiles en place, Side reprend le clavier et repasse sous elles. Pendant qu'un menu de Side est ouvert, le tiroir n'active plus aucune application.
- Square ne met plus les fenêtres des tuiles dans sa grille ni dans son carrousel à quatre doigts (Side lui donne leurs numéros).
- Apple Podcasts rejoint les lecteurs proposés.

### Tiroir : YouTube plus soigné
- La vidéo a des coins arrondis (sauf en plein écran).
- En plein écran, un bouton en haut à droite de la fenêtre montre ou cache la colonne des vidéos suivantes, comme sur le site de YouTube ; la vidéo se resserre à côté.
- Correction : le premier arrondi des coins rendait la vidéo noire dans le tiroir, le deuxième ne marchait pas. La vidéo est maintenant découpée aux coins arrondis.
- En plein écran, un clic sur la vidéo la met en pause ou la relance ; un double-clic la ramène dans le tiroir.

### Tiroir : le menu du + plus clair
- Les deux façons d'ajouter (« Choisir une application… » et « Une seule note… ») sont en tête, sous « Ajouter au tiroir », avec une icône et une flèche. Viennent ensuite les tuiles du tiroir, puis les applications ouvertes.
- Le menu est plus large : les noms ne sont plus coupés.
- Réglages › Tiroir › Multimédia › « Masquer les Shorts » : leurs rangées, leur onglet et les vidéos courtes disparaissent, tout de suite, sans recharger la page.

### Tiroir : une note qu'on modifie reste dans le tiroir
- **Avant :** écrire dans une note du tiroir changeait son titre (sa première ligne) ; le tiroir, qui la cherchait par son titre, la croyait fermée. Il retirait sa tuile, et la fenêtre de la note restait sur le bureau, où Square la rangeait comme une application.
- **Et maintenant aussi :** le tiroir retient l'identifiant de chaque note dans Notes, qui ne change jamais. Même après un redémarrage de Side, une note dont on a réécrit la première ligne est retrouvée (avant : « introuvable dans Notes »). Les notes déjà rangées gardent leur identifiant à la première ouverture réussie.
- **Maintenant :** une fois trouvée, la note est reconnue au numéro de sa fenêtre, quoi qu'on y écrive. Cela vaut aussi quand le tiroir se referme : la fenêtre d'une note modifiée était prise pour la grande fenêtre de Notes, et ramenée au milieu de l'écran (puis rangée par Square).

### Coins actifs : le presse-papiers et la grille de Square
- Chaque coin peut ouvrir le Finder, le tiroir, le presse-papiers, ou la grille de Square (si Square est installé). Un coin ne fait qu'une chose.
- La grille de Square reprend la première fois le coin réglé dans Square (en haut à droite au départ). Tant que Side est ouvert, c'est lui qui surveille ce coin : Square grise son propre réglage et renvoie aux réglages de Side.
- Revenir dans un coin referme ce qu'il a ouvert dès qu'on en est sorti d'un peu (40 points, comme dans Square). Avant, il fallait s'en éloigner de 140 points : en restant en bas du volet du presse-papiers, revenir au coin ne le refermait pas.
- Le presse-papiers a son propre volet dans les réglages (« Historique et liens ») : historique, volet, aperçu et présentation des liens. Son raccourci est dans « Raccourcis clavier ».

### Tiroir : la vidéo YouTube en plein écran, gérée par Square
- **Avant :** le bouton plein écran de YouTube ne faisait qu'agrandir la vidéo dans sa tuile.
- **Maintenant :** il sort la vidéo du tiroir dans une fenêtre qui remplit l'écran (sans le plein écran d'Apple, qui crée un bureau à part). Le tiroir se referme ; la lecture continue sans coupure, c'est le même lecteur qui change de place.
- Square range cette fenêtre comme celle d'une application : elle est dans sa grille, son carrousel et ses raccourcis ⌘1 à ⌘9, et peut partager l'écran.
- **Pour revenir :** Échap, le bouton de sortie du plein écran de YouTube (en bas à droite de la vidéo), la touche F, ou le bouton rouge de la fenêtre. Rouvrir le tiroir ne la ramène pas : sa tuile affiche « La vidéo est en plein écran », avec « Afficher la vidéo » et « Ramener dans le tiroir ».

### Tiroir : plus de fond derrière les tuiles
- Le fond flouté du tiroir est retiré : les tuiles flottent seules. Réglages › Tiroir › « Fond derrière les tuiles » le remet.
- Sans fond, le tiroir garde un voile presque invisible, pour que les clics et les glisser restent pour lui (une zone tout à fait transparente les laissait passer à l'application de derrière).
- **Déplacer une tuile** (par sa barre de titre) : comme dans la grille de Square, elle prend sa nouvelle place pendant le geste, et les autres se poussent tout de suite. Avant, rien ne bougeait jusqu'au lâcher.

## 12/11/2026, nuit

### Presse-papiers : trois présentations pour les liens
- Un petit bouton de réglage, en haut du volet, choisit la présentation des cartes de liens : grande image (comme avant), petite image à gauche (avec l'icône du site dans un rond, sur son coin), ou sans image.
- Le choix vaut pour le presse-papiers comme pour les liens enregistrés ; il se trouve aussi dans Réglages › Général › Presse-papiers.

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
