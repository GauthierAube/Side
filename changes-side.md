# Historique des changements de Side

Ce fichier garde la trace de tout ce qui change dans Side, du plus récent au plus ancien.
Il est mis à jour à chaque modification, en même temps que le code.

---

## 20/11/2026

### Tiroir (une application à la fois) : fiable, sans clignotement
- Demandé par Gauthier : les applications du tiroir étaient parfois dedans, parfois non, et clignotaient.
- La cause : le tiroir passait derrière l'application affichée et se battait avec macOS pour qu'elle reste devant lui (réactiver l'application, reprendre la main, repasser dessous, plusieurs fois par seconde). Chaque essai pouvait rater.
- Maintenant, le tiroir laisse un trou à la place de l'application : on la voit au travers, et un clic dans le trou va directement à elle, quel que soit l'ordre des fenêtres. Il ne reste qu'à poser sa fenêtre et à la faire passer devant, une fois. La photo ne s'efface que lorsque c'est bien elle qu'on voit.
- macOS rendait souvent la main à l'application d'avant (Safari, Claude…) une fraction de seconde après l'ouverture : le tiroir se refermait tout seul, ou l'application restait derrière. Le tiroir le repère et ramène son application devant.
- Une application du tiroir cliquée dans le Dock ouvre le tiroir sans que ce même clic le referme aussitôt.
- La bande de tuiles côte à côte (réglage « une application à la fois » coupé) ne change pas.

## 19/11/2026

### Île de l'encoche : le calendrier d'abord, sans « Aujourd'hui » ni bac
- Demandé par Gauthier : arriver directement sur la deuxième vue (le calendrier du mois), retirer la première (« Aujourd'hui ») et le bac à fichiers, dont il ne se sert pas.
- L'île ouverte montre maintenant deux vues : le calendrier, puis la lecture en cours. Approcher un fichier de l'encoche ne l'ouvre plus.
- Réglages › Île de l'encoche : « Afficher le calendrier » remplace « Afficher l'agenda » ; l'interrupteur du bac est retiré.

### Raccourci de la recherche sur le web : la saisie est plus sûre
- Demandé par Gauthier : il n'arrivait pas à changer le raccourci qui ouvre la recherche sur le web (Réglages › Raccourcis clavier › Recherche sur le web).
- Pendant la saisie, Side prend le clavier et met tous ses propres raccourcis de côté : une combinaison déjà utilisée par Side arrive dans la saisie au lieu d'ouvrir le Finder ou le tiroir.
- Si macOS refuse la combinaison (déjà prise par Side ou par une autre application), un message en rouge le dit et l'ancien raccourci est gardé. Avant, rien ne s'affichait.
- La note sous le réglage explique quoi faire quand rien ne se passe (combinaison tenue par macOS, comme ⌘ Espace pour Spotlight).

### Carte du Finder : elle ne s'ouvre plus sur des dossiers techniques
- Demandé par Gauthier : en rouvrant la carte, il tombait sans cesse sur un dossier « bizarre » au lieu de ses dossiers de tous les jours.
- Le journal de Side montrait la cause : les fichiers créés en continu par les compilations dans GitHub (Horizon, Side, Flow, Parole), par les modifications de Claude, par la sauvegarde du site Wakademy et par le presse-papiers de Side (dans iCloud Drive › Side) passaient pour des fichiers enregistrés.
- Ces dossiers sont maintenant ignorés : tout `~/GitHub`, tout `~/Sauvegardes`, iCloud Drive › Side, et partout les dossiers de compilation (`build`, `DerivedData`, `node_modules`, `Pods`, `vendor`). Un export dans Documents ou un téléchargement ouvre toujours la carte sur son dossier.

## 18/11/2026

### Volets à plusieurs vues : dans chaque coin, à gauche ou à droite
- Demandé par Gauthier : pouvoir mettre le volet à plusieurs vues dans n'importe quel coin, et le faire apparaître à gauche ou à droite.
- Chaque coin propose « Plusieurs vues ». Les coins de gauche ouvrent le volet de gauche, ceux de droite le volet de droite. Chaque côté a sa propre liste de vues (cinq au plus), sa vue en cours et sa largeur.
- À droite, tout est en miroir : le volet flotte à 10 points du bord droit, la carte en cours part vers la droite, et quatre doigts vers la droite donnent la vue suivante.
- Réglages › Coins actifs : une seule section « Volets à plusieurs vues », avec un choix Gauche / Droite. Une flèche monte une vue d'un rang (le glisser-déposer est retiré : il dérangeait la mise en page des réglages).

### Volet de gauche : cartes fluides, roulement sans fin, fenêtre qui flotte
- Demandé par Gauthier : l'animation des cartes n'était « pas fluide » ; il voulait la fluidité du carrousel du tiroir, un roulement sans fin et une fenêtre qui semble flotter.
- Les cartes sont maintenant dessinées comme le carrousel du tiroir (des calques déplacés par la carte graphique, au lieu de fenêtres dont on changeait la taille à chaque image). Vérifié sur un film de l'écran : une image nouvelle à presque chaque soixantième de seconde.
- Les photos des vues voisines sont prises d'avance, à chaque arrivée : au départ du geste, les cartes sont posées en 30 à 50 millisecondes.
- Roulement sans fin : après la dernière vue, on revient à la première, et inversement.
- Le volet flotte : 10 points de bord à gauche, en haut et en bas ; les cartes ont une ombre portée et des coins arrondis.
- Pour les essais sans trackpad, Side joue un geste fabriqué quand il reçoit la notification « com.gauthieraube.side.essai-cartes » (objet « 1 » ou « -1 »).

### Volet de gauche : les vues sont des cartes, comme Slide Over sur l'iPad
- Demandé par Gauthier : l'ancien glissement « page par page » ne lui plaisait pas ; il voulait les cartes de Slide Over de l'iPad.
- La carte suit maintenant les doigts en direct. Vers la gauche : la vue en cours glisse vers le bord de l'écran et découvre la suivante, qui attendait derrière, un peu plus petite et assombrie, et grandit pour prendre sa place. Vers la droite : la vue précédente revient du bord par-dessus, et la vue en cours recule derrière.
- En levant les doigts : passé la moitié du chemin, ou d'un geste vif, la carte change ; sinon elle revient. Un retour vif annule.
- Au bout de la liste, la carte suit un peu les doigts puis revient, comme un élastique.
- Un clic sur un point fait le même mouvement.

### Volet de gauche : plusieurs vues d'Horizon, d'un geste
- Demandé par Gauthier : sur le bord gauche, plusieurs fenêtres d'Horizon entre lesquelles passer « très facilement ».
- Réglages › Coins actifs : un coin de gauche peut ouvrir « Plusieurs vues ». La section « Volet de gauche » en dessous choisit les vues (cinq au plus), leur ordre (glisser) et en retire.
- Le volet s'ouvre sur la dernière vue montrée. Quatre doigts vers la gauche : vue suivante ; vers la droite : vue précédente. Les vues défilent comme des pages. Au bout de la liste, rien ne se passe.
- Des points en haut du volet montrent la vue en cours ; un clic sur un point y va.
- Le geste n'est pris que quand le pointeur est sur le volet : ailleurs, quatre doigts à l'horizontale font toujours défiler le carrousel des applications.
- Toutes les vues du volet ont la même largeur : tirer le bord l'élargit pour toutes.
- Le volet de droite et le tiroir ne changent pas.

## 17/11/2026

### Tiroir : Horizon Mail parmi les vues d'Horizon
- Demandé par Gauthier : Horizon Mail dans le tiroir comme les autres vues, « juste un aperçu pour avoir une vue très rapide d'un mail », et le bouton vert pour la passer en plein écran.
- « + » du tiroir › « Une vue d'Horizon… » propose Horizon Mail en tête de liste (et les coins actifs aussi).
- Pas de seconde application Mail : elle relèverait les boîtes en double. C'est Horizon Mail elle-même qui change d'allure selon sa largeur (le changement est côté Horizon) :
  - à la largeur d'une tuile du tiroir (moins de 1100 points) : pas de barre latérale ; en haut, des pastilles « Toutes » puis chaque boîte avec sa couleur et ses mails sans réponse, un clic n'affiche qu'elle ; « Nouveau message » et « Relever » en petites icônes au bout ; la liste commence directement aux onglets Personnes, Notifications, Reçus (ni titre, ni « Mis à jour », ni recherche) ;
  - le bouton vert de la tuile la passe en plein écran, où elle retrouve sa barre latérale et sa recherche.
- Deux réglages en cours de route, à la demande de Gauthier (captures à l'appui) : le seuil, d'abord à 780 points, laissait la barre latérale dans sa tuile de 920 points ; puis l'en-tête de la liste prenait trop de place (« je veux voir mes mails »).
- Validé par Gauthier dans le tiroir le 17/11.

### Coins actifs : une vue d'Horizon qui glisse depuis le bord de l'écran
- Demandé par Gauthier : faire apparaître une vue d'Horizon (Aujourd'hui, CRM, un projet…) depuis un coin, « qui viendrait de la gauche et prendrait toute la hauteur », à redimensionner librement. (Sa première idée, le survol de l'île de l'encoche, a été écartée avec lui : l'île s'ouvre déjà au survol, et une grande page surgirait au milieu de l'écran par accident.)
- Réglages > Coins actifs : chaque coin peut recevoir une vue d'Horizon (la liste vient de `/Applications/Horizon Vues`). Plusieurs coins peuvent avoir chacun la leur.
- La vue glisse depuis le bord du côté du coin (la gauche pour les coins de gauche, la droite pour ceux de droite) et prend toute la hauteur. Sa largeur se règle en tirant son bord, comme une fenêtre ; Side s'en souvient, vue par vue.
- Elle repart quand la souris la quitte (0,6 s), quand une autre application passe devant, avec Échap, ou en retournant dans le coin.
- Comme pour le tiroir, c'est la vraie fenêtre de l'application : elle attend hors de l'écran entre deux usages, et le glissement se fait avec sa photo. Les vues des coins sont lancées avec Side, pour arriver tout de suite.
- Un seul volet à la fois sur le bord droit : ouvrir le presse-papiers referme une vue ouverte à droite, et l'inverse.
- Le plein écran de Side n'agrandit pas la fenêtre du volet.
- Code : `Sources/VoletVue.swift`. Essais : commande « vue:hautGauche », ou « vue:basDroite:/chemin/Appli.app » sans toucher aux réglages.
- Essayé par Gauthier avec Horizon Projet 1 en haut à gauche : « ça marche très bien ». Cas pas encore au point : une vue dont la fenêtre avait été fermée est rouverte, mais arrive une fois en grand avant de prendre sa place.

### Tiroir : passer d'une application à l'autre ne saccade plus
- Signalé par Gauthier : le geste à quatre doigts saccadait, ou bloquait, surtout sur un grand geste rapide vers une application éloignée.
- Gestes enchaînés : quand un nouveau geste commençait moins de deux dixièmes de seconde après le précédent, Side posait quand même la fenêtre de l'application de passage, sous le carrousel (il la déplaçait, la lançait au besoin, lui donnait le clavier). Maintenant il attend la fin du dernier geste : les applications de passage ne sont ni lancées ni activées.
- Une application qui met du temps à répondre (une vue d'Horizon qui démarre, par exemple) n'est plus interrogée qu'une fois par seconde, au lieu de vingt fois : c'est ce qui figeait Side plusieurs secondes. Et la réponse d'une application est gardée un court instant (0,12 s), au lieu de lui redemander trois ou quatre fois ses fenêtres pour un seul geste.
- Les miniatures du carrousel sont gardées d'un geste à l'autre au lieu d'être refaites à chaque fois, et retrouver une application ne passe plus en revue toutes les applications ouvertes.
- Mesuré en rejouant le même geste huit fois (`sample`) : le temps pendant lequel Side ne répond pas est divisé par trois sur de petits gestes, et bien plus sur de grands gestes enchaînés.
- Le journal note maintenant toute application qui met plus de 50 ms à répondre (« … a mis 72 ms à répondre ») : les vues d'Horizon sont lentes sur ce point (50 à 100 ms).
- Essayé avec des gestes rejoués par commande, pas au trackpad : à confirmer par Gauthier.

### Tiroir : la colonne de droite suit le geste
- Demandé par Gauthier : quand on passe d'une application à l'autre dans le tiroir (geste à quatre doigts, mini carrousel), la mise en avant de la colonne d'icônes à droite suit maintenant l'application qui passe au centre, pendant le geste. Avant, elle ne bougeait qu'une fois les doigts levés.

### Tiroir : une vue d'Horizon comme tuile
- Horizon (l'app de Gauthier) installe maintenant de petites applications qui ne montrent qu'une de ses vues : Horizon CRM, Horizon Aujourd'hui, Horizon À planifier, Horizon Projets, Horizon Coffre, Horizon Réseaux. Elles sont rangées dans `/Applications/Horizon Vues`.
- La liste « + » du tiroir gagne « Une vue d'Horizon… » : la liste des vues qui ne sont pas encore dans le tiroir s'affiche, on clique sur celle qu'on veut. La ligne n'apparaît que si ce dossier existe sur le Mac.
- Ce sont des applications comme les autres : le tiroir les range, les agrandit et les retire comme n'importe quelle tuile, sans code particulier. (Un premier plan prévoyait une seule application à plusieurs fenêtres ; le tiroir reconnaît une application à son identifiant, donc une petite application par vue est plus simple et plus sûr.)
- Essais : la commande « tuile:N » affiche maintenant la tuile de n'importe quel rang (avant : les quatre premières).
- Chaque vue a sa propre icône (dessinée côté Horizon), pour s'y retrouver dans la colonne d'icônes.
- Vérifié : Horizon CRM rangée dans le tiroir, à sa taille de tuile ; Gauthier a ajouté lui-même Horizon Aujourd'hui et confirmé que ça marche.

### Recherche sur le web, dans une pilule qui descend de l'encoche
- Un raccourci (⇧⌘ Espace au départ) fait descendre de l'encoche une pilule noire avec un champ, comme Spotlight. Sur un écran sans encoche, elle descend du haut de l'écran.
- On tape une recherche ou une adresse, puis Entrée : la pilule s'élargit et s'étire vers le bas, avec le ressort de l'île, et montre la page (même moteur que Safari).
- Échap, un clic ailleurs ou le raccourci la referment : elle remonte dans l'encoche. La page reste en mémoire : à la prochaine ouverture, une pastille à droite du champ (ou Entrée, champ vide) la reprend.
- Ce n'est pas un onglet de Safari (Apple ne le permet pas) : le bouton Safari, ou ⌘ Entrée, envoie la page dans un vrai onglet de Safari. Les connexions aux sites sont donc séparées de celles de Safari.
- Aussi : page précédente et suivante (boutons, ou deux doigts de côté), ⌘L pour revenir au champ, ⌘R pour recharger.
- Réglages > Raccourcis clavier > Recherche sur le web : le raccourci et le moteur (Google, DuckDuckGo, Ecosia, Qwant, Bing).
- Essais : `Side --test-recherche` (ce que le champ fait de quelques saisies) ; commande « recherche:texte » (ouvre sans prendre le clavier).
- PAS ENCORE ESSAYÉ au clavier par Gauthier.

### L'encoche devient une île (comme la Dynamic Island de l'iPhone)
- Idées reprises des meilleures applications du genre (Alcove, MediaMate, Boring Notch, Droppy), avec l'animation d'abord : une seule forme noire qui s'étire avec un ressort et un léger rebond, la pochette qui glisse de sa petite place jusqu'au lecteur, le contenu qui arrive flou puis se précise.
- Au repos, l'île se confond avec l'encoche. Quand de la musique joue (Spotify ou Musique), elle s'élargit : la pochette à gauche, une petite onde à la couleur de la pochette à droite.
- Elle s'ouvre dès que le pointeur passe dessus : elle gonfle un instant (avec un petit retour du trackpad), puis s'ouvre ; un passage très rapide vers un menu ne l'ouvre pas. Aussi d'un clic, de deux doigts vers le bas, ou quand on en approche un fichier. Elle se referme quand le pointeur s'éloigne, d'un clic ailleurs, d'Échap ou de deux doigts vers le haut.
- Ouverte, elle reste étroite (460 points) et montre une seule vue à la fois. Des points en haut à droite disent où l'on est (un clic sur un point y mène) ; deux doigts de côté passent d'une vue à l'autre, et la vue glisse dans le sens du geste :
  - « Aujourd'hui », à l'ouverture : la frise de la journée (de 8 h à 20 h, plus si besoin) avec les rendez-vous en couleur et l'heure qu'il est, puis ce qu'il reste à faire, avec « En cours » ou « Dans 20 min » ;
  - « Calendrier » : le mois, un point sous les jours qui ont des rendez-vous ; un clic sur un jour montre ses rendez-vous à côté ;
  - « Lecture » : la pochette, le titre, la progression, les boutons ;
  - « Bac » : des fichiers mis de côté (ils restent où ils sont), les quatre derniers en vue.
- Le Finder de Side descend de l'encoche quand on l'ouvre (raccourci, coin, secousse) : une forme noire part de l'encoche, s'étire jusqu'à la place de la fenêtre avec l'icône qui grandit, puis se fond dans la fenêtre. Réglable.
- Volume et luminosité : à la place du carré gris de macOS, l'île s'étire avec l'icône et une jauge. ⇧⌥ pour des pas plus fins. Si Side ne peut pas régler (sortie audio sans volume), la touche est rendue à macOS.
- Nouvelle partie « Encoche » dans Réglages > Général, et son volet de réglages (ouverture au survol, gestes, agenda, bac, musique, volume et luminosité, Finder qui descend). « Réduire les animations » coupe tous ces mouvements.
- Essayée par Gauthier le 17/11/2026, puis revue à sa demande : ouverture au survol, plus étroite, plus de rangée d'applications, une vue à la fois.
- Essais sans souris : commandes « encoche », « encoche:suivante », « encoche:finder », « encoche:hud ».

### Collage en cascade : ⌘V V V
- ⌘V colle le dernier copié, comme toujours. Mais si l'on garde ⌘ enfoncé et qu'on tape V une deuxième fois, une petite fenêtre s'ouvre au centre de l'écran avec les 5 derniers copiés, sur l'avant-dernier. Chaque V de plus descend d'un cran (après le 5ᵉ, retour au 1ᵉʳ). Lâcher ⌘ colle l'élément choisi ; Échap referme sans rien coller.
- Le premier ⌘V est retenu jusqu'au lâcher de ⌘ : rien n'est jamais collé deux fois. Seul ⌘V « nu » est concerné (⌘⇧V, ⌥⌘V… restent ceux de macOS). La fenêtre ne prend pas le clavier : on reste dans l'application où l'on écrit.
- Réglage dans Presse-papiers > Historique : « Collage en cascade », coché au départ. Sans historique, ⌘V reste celui de macOS.
- Essais sans clavier : `Side --test-cascade` ; image de la fenêtre : `Side --image-cascade fichier.png [--clair|--sombre]`.
- Essayé par Gauthier dans une vraie application le 17/11/2026 : ça marche.

## 16/11/2026

### Fil d'Ariane dans une pastille
- Tout le fil (la flèche du dossier parent et le chemin) tient dans une pastille arrondie, posée en bas de la grande zone, au lieu d'une barre sur toute la largeur.
- Le dossier personnel a une maison bleue pour icône, comme dans la barre latérale.
- Chaque dossier du chemin se surligne au passage de la souris.

### Fil d'Ariane : plus haut, dossier parent et sous-dossiers comme sous Windows
- La barre du chemin est plus haute (34 points), avec un texte et des icônes plus grands.
- Une flèche vers le haut, à gauche, remonte au dossier parent (comme la flèche « Haut » de l'Explorateur de Windows).
- Chaque chevron du chemin se clique : il déroule les sous-dossiers du dossier qui le précède, pour sauter directement dans l'un d'eux. Le chevron au bout du chemin montre les sous-dossiers du dossier ouvert.

### Fil d'Ariane en bas du Finder
- Une barre du chemin en bas de la grande zone, comme dans le Finder : on voit où l'on est (depuis le dossier personnel, iCloud Drive ou le disque), jusqu'à l'élément sélectionné.
- Cliquer un dossier du chemin y remonte (Précédent et Suivant restent utilisables) ; cliquer le fichier sélectionné l'ouvre.

### Finder : éjecter les disques
- Les disques externes (DD, SSD, clés, cartes mémoire), les images disque et les serveurs connectés ont un bouton ⏏ à droite de leur nom dans la barre latérale, et « Éjecter » au clic droit, comme dans le Finder.
- Si la carte affichait ce disque, elle passe au dossier personnel avant l'éjection (et une colonne épinglée sur ce disque est retirée), pour que Side ne le garde pas occupé. Un disque encore utilisé par une application le dit dans une fenêtre.

### Finder : présentation « Arborescence », comme l'Explorateur de Windows
- Quatrième présentation de la grande zone, à côté des icônes, de la liste et des colonnes (quatrième bouton, ou ⌘4) : à gauche, l'arbre des dossiers ; à droite, le contenu du dossier choisi, en liste (avec la date et la taille quand la place le permet).
- Un clic sur un dossier de l'arbre l'affiche à droite ; son chevron (ou un double-clic) le déplie ou le replie sans changer de dossier. Entrer dans un dossier à droite déplie l'arbre jusqu'à lui.
- On peut déposer des fichiers sur un dossier de l'arbre. Le trait entre l'arbre et la liste se tire pour régler la largeur de l'arbre.

### Le Finder de Side s'ouvre sur ce qu'on vient d'enregistrer
- La carte se rouvre toujours là où l'on était, sauf quand un fichier vient d'être enregistré (un export de Logic Pro, un téléchargement, moins de 10 minutes avant) : elle s'ouvre alors sur lui, le fichier choisi, avec toute son arborescence : les colonnes partent du favori qui le contient (sinon de Documents, d'iCloud Drive, du dossier personnel ou du disque) et descendent jusqu'à lui, comme dans le Finder. Side repère ces fichiers dans le dossier personnel, iCloud Drive et les disques branchés, sans compter les fichiers cachés ou temporaires, ceux de la Bibliothèque, ni ceux rangés à l'intérieur d'un projet (Logic, Photos…). Les disques de sauvegarde (Time Machine) ne sont pas surveillés.
- Réglages > Barre latérale et fichiers > « Ouvrir les dossiers dans Side » : Side devient le visualiseur de fichiers du Mac. « Afficher dans le Finder » des autres applications, et l'ouverture d'un dossier, montrent la carte de Side. Décoché : le Finder de macOS, comme avant. « Afficher dans le Finder » de Side lui-même ouvre toujours le vrai Finder.

### Renommer sur place, et les fenêtres secondaires à leur place
- Finder : Entrée (ou « Renommer » du clic droit) rend le nom modifiable sur place, surligné en bleu sans son extension, comme dans le Finder. Entrée valide, Échap annule, un clic ailleurs valide. Plus de fenêtre « Renommer », qui passait derrière la carte.
- Les fenêtres de question de Side (erreur, ouvrir, enregistrer) passent toujours devant la carte et le tiroir : macOS leur remettait son propre niveau en les affichant, plus bas que Side.
- Plein écran : les réglages ou une boîte de dialogue d'une application (les réglages de Safari) n'ont plus leur propre case dans la grille ni dans le carrousel. Ils restent au-dessus de la grande fenêtre de leur application, et repassent devant quand Side la ramène.
- Tiroir : les réglages ou une boîte de dialogue de l'application affichée s'ouvrent au-dessus d'elle, centrés sur sa place dans le tiroir (une seule fois : on peut ensuite les déplacer).
### IA locale : les captures d'écran prennent un nom qui dit ce qu'on y voit
- Quelques secondes après une capture d'écran, Side la renomme d'après son contenu, suivi de sa date : « gestion de cartes wakatoo 2026-11-16 12.20.05.png ». Le nom vient d'un modèle d'IA qui tourne sur ton Mac avec Ollama (`gemma4:26b`).
- Rien ne part sur Internet : l'image, réduite, n'est envoyée qu'au serveur Ollama de ce Mac (`localhost`), sinon à celui du Mac mini (`mac-mini-de-gauthier.local`). Side essaie les adresses dans l'ordre et garde cinq minutes la première qui répond.
- La capture arrive d'abord dans sa zone de dépôt, tout de suite, comme avant ; son nom change ensuite sur place, et la zone suit le fichier. Le nom se demande hors du fil principal.
- Serveur éteint, réponse bizarre (une phrase, juste « capture d'écran »), fichier déplacé entre-temps : la capture garde son nom, sans message. Un fichier n'est jamais écrasé (« 2 », « 3 »… au besoin), et une capture n'est jamais renommée deux fois.
- Seules les captures nommées par macOS (« Capture d'écran 2026-11-16 à 14.32.05 ») sont renommées. Celles qu'un outil enregistre sous un nom choisi (les images d'un dépôt, par exemple) gardent ce nom, comme les vidéos de l'écran.
- Nouveau volet Réglages > IA locale : l'interrupteur (activé au départ), les adresses du serveur, le modèle, et un bouton « Tester » qui dit si le serveur répond et si le modèle y est installé. Réglages gardés par `ConfigIA` (clés `iaRenommerCaptures`, `iaServeurs`, `iaModele`).
- `Info.plist` : les connexions en clair sont permises vers le réseau local seulement (`NSAllowsLocalNetworking`), pour joindre le Mac mini ; le message de la demande d'accès au réseau local parle maintenant aussi de l'IA locale.
- Essais : `Side --test-capture fichier` affiche le nom proposé sans rien renommer ; `Side --test-nom-capture` vérifie le nettoyage des réponses, sans serveur. `tools/snap.sh` photographie le nouveau volet (40 images).

### Deux écrans (revue BAMA, `docs/architecture-review-2026-11-16.md`)
- Nouveau module `Ecrans.swift` : le seul endroit qui choisit un écran, passe d'un repère à l'autre (AppKit, AX) et gare les fenêtres. Avant, Side faisait ce choix à 77 endroits avec quatre règles différentes : invisible avec un seul écran, faux avec deux.
- Essai sans écran : `Side --test-ecrans` vérifie le tout sur trois dispositions (un écran ; Mac mini avec l'écran LG à gauche ; MacBook Air avec un écran à droite).
- Fenêtres garées par le tiroir : partout après le bord droit de tous les écrans. Deux endroits utilisaient encore le bord de l'écran principal (fenêtre envoyée au tiroir, boutons vert et jaune) : avec un écran à droite, la fenêtre « garée » s'y montrait.
- Le tiroir s'ouvre sur l'écran de la souris (avant : celui de la fenêtre active, qui pouvait être l'autre écran), et y reste tant qu'il est ouvert. Ses tuiles, la liste du « + », les fenêtres sorties en grand et Spotify prennent la taille de cet écran-là : plus de tuiles calculées pour l'autre écran (fond gris, tuiles trop larges).
- Une fenêtre rendue par le tiroir revient sur l'écran de la souris.
- « Plein écran d'Apple : macOS empêche d'y afficher les tuiles » : le tiroir regarde maintenant son propre écran. Avant, il regardait toujours le premier : une app en plein écran sur un écran faisait croire au tiroir ouvert sur l'autre qu'il ne pouvait rien montrer.
- Même règle partout : la carte du Finder (raccourci, zones de dépôt), le volet du presse-papiers, la pastille d'information et le plein écran s'ouvrent sur l'écran de la souris quand rien d'autre ne le dit (avant : l'écran de la fenêtre active).
- Sélecteur vertical du tiroir à la souris : avec Mulot, bouton de pouce tenu et souris qui continue vers le haut, le tiroir s'ouvre (s'il ne l'est pas) et son sélecteur d'applications apparaît, comme au trackpad à quatre doigts. Il suit la souris ; au relâchement, l'application du centre prend la place. Avant, il n'existait qu'au trackpad.
- Avec Mulot, le tiroir monte en suivant la souris (bouton de pouce tenu), exactement comme avec les doigts au trackpad, et le sélecteur prend le relais dans le même mouvement. Revenir au point de départ le fait redescendre. Tiroir déjà ouvert : le sélecteur apparaît dès l'appui sur le bouton de pouce. Side note dans ses réglages si le tiroir est ouvert (« tiroirOuvert »), pour Mulot.
- Tiroir sur grand écran : sa largeur (Réglages > Tiroir, ou en tirant ses côtés) se compte sur 1800 points au plus. 87 % d'un Studio Display (2880 points) donnait 2500 points, avec un grand vide entre le coin multimédia et l'application ; c'est maintenant 1565 points, centré. Rien ne change sur un écran de portable.
- Le mini-Dock sous le Finder est masqué au départ. Son réglage n'est plus proposé depuis le 12/11 mais restait « affiché » par défaut : un Mac qui ne l'avait jamais coupé (le Mac mini) le montrait encore.
- Les réglages de Side restent propres à chaque Mac (barre latérale, largeurs, mini-Dock). Pour reprendre ceux d'un autre Mac : `defaults export com.gauthieraube.side fichier.plist` d'un côté, `defaults import` de l'autre, Side quitté (et corriger les chemins si le nom du dossier personnel diffère).

### Presse-papiers : l'historique et les liens enregistrés, partagés entre mes Mac
- Ce que tu copies sur un Mac apparaît dans le presse-papiers de Side sur l'autre, en moins d'une minute (Side y jette un œil toutes les 20 secondes, et à chaque ouverture du volet).
- Un élément effacé ou épinglé sur un Mac l'est aussi sur l'autre. « Effacer » sur un Mac efface aussi l'autre (sauf les épinglés). Le même texte copié sur les deux Mac ne compte qu'une fois.
- Les liens enregistrés suivent aussi : la liste modifiée le plus récemment (ajout, groupe, ordre, suppression) remplace l'autre. La toute première fois sur un Mac, les deux listes sont réunies, pour ne rien perdre.
- Tout passe par iCloud Drive, dans le dossier Side (à côté de « Mes applications ») : « Presse-papiers.json », « Presse-papiers images » et « Liens enregistrés.json ».
- Restent sur leur Mac : les mots de passe (jamais écrits sur le disque) et les fichiers copiés (leur emplacement ne vaut que sur ce Mac).
- Réglage : Réglages > Presse-papiers > « Entre mes Mac ». Activé au départ, sur chaque Mac.


## 15/11/2026

### Tiroir : taille fixe avec Peinard, et la bande des suggestions
- Avec Peinard comme lecteur YouTube, le tiroir ne se redimensionne plus (demande de Gauthier : trop pénible, et source de bugs). Il garde la taille qu'il avait ; plus de bord du haut ni de côtés à tirer, plus de relais avec la fenêtre de l'application.
- Peinard suit les règles d'Apple pour une app iPhone portée sur Mac : page affichée à 77 % (elle était trop grosse), loupe de recherche dans l'en-tête au lieu du bouton rond en bas, boutons d'en-tête à la taille du pointeur avec bulles d'aide, raccourcis ⌘F (recherche), ⌘[ (retour), ⌘Y (historique), ⌘, (profil).
- Le coin multimédia fait 740 points au départ : à 77 %, YouTube y dispose de 960 points et met de lui-même la vidéo à gauche et les vidéos suivantes à droite. La séparation entre le coin multimédia et les applications se tire toujours (poignée) : seule la taille du tiroir est fixe.
- (Deux essais du même jour abandonnés : une bande de suggestions ajoutée à la main, qui cassait l'accueil avec un bloc noir, et un tiroir sur toute la largeur.)
- Sans Peinard (version publique de Side), rien ne change : le tiroir reste réglable.

### Plein écran : le Dock de la grille ouvre en grand, et la grille ne garde plus de trous
- Clic sur une application dans le Dock de la grille : son icône grandit jusqu'à couvrir l'écran (le même mouvement qu'une carte choisie), l'application s'ouvre, passe devant, et sa fenêtre est agrandie. Avant, la grille se fermait et l'application s'ouvrait derrière, à sa taille : on croyait qu'il ne se passait rien.
- Une application déjà ouverte choisie depuis le Dock garde le zoom de sa carte, et sa fenêtre est agrandie en plus.
- Si l'application remet d'elle-même sa taille d'avant juste après son lancement, Side la réagrandit (trois secondes au plus).
- « Mes applications » : seules celles qui sont ouvertes prennent les premières cases, dans l'ordre de leurs numéros. Une application de la liste qui est fermée ne laisse plus de case vide : la grille se resserre. ⌘1 à ⌘9 suivent toujours les numéros (et ouvrent l'application si elle est fermée).
- Plus de trou dans la grille en général : une fenêtre fermée libère sa case, et les suivantes se resserrent dans le même ordre.

### Tiroir : le lecteur YouTube est maintenant Peinard
- La tuile YouTube du tiroir est Peinard, l'app iPhone de Gauthier, dans sa version Mac : logo, historique, profil, bouton loupe de recherche, résumés par Apple Intelligence, « En bref », envoi dans Horizon. Un seul code pour l'iPhone et le Mac : une correction dans Peinard profite aux deux.
- Le code de Peinard reste dans son dossier (~/Github/sans-pub) ; `build.sh` le compile quand il est présent (`tools/peinard.sh`). Sans lui, ou s'il ne compile pas pour Mac, Side garde son ancien lecteur YouTube.
- Avec Peinard, Side demande macOS 26 ou plus récent (Apple Intelligence). Sans Peinard, toujours macOS 14.
- Historique, Profil, Résumé et Connexion de Peinard s'ouvrent exactement sur la tuile, à sa taille (ils apparaissaient au milieu du tiroir, à droite, écrasés).
- Plein écran d'une vidéo de Peinard (bouton du lecteur) : la vidéo sort du tiroir dans une grande fenêtre Mac ordinaire (titre de la vidéo, boutons habituels, redimensionnable) qui remplit l'écran, avec la mise en page large de YouTube : la vidéo à gauche, les vidéos suivantes à droite. La tuile, élargie au-delà d'environ 900 points, passe aussi en deux colonnes, et le tiroir se referme, comme avec l'ancien lecteur ; Échap, le bouton du lecteur ou la croix de la fenêtre la ramènent. (Dans les premières heures de Peinard dans le tiroir, ce bouton ne faisait rien.)
- Réglages > Multimédia : les anciens réglages YouTube (Shorts, posts, sponsors…) laissent la place à un renvoi vers les réglages de Peinard ; le minuteur de sommeil reste et met aussi Peinard en pause.

### Tiroir : plus de tuile blanche au chargement de YouTube
- Pendant les premières secondes, la tuile YouTube était blanc vif au milieu du tiroir sombre. Elle reste sombre jusqu'à ce que la page s'affiche.

### Finder : la barre de commande est retirée
- La barre sous le Finder (« Aucun fichier sélectionné… », actions sur les fichiers par Apple Intelligence) est supprimée, à la demande de Gauthier, avec son réglage. La carte du Finder s'ouvre et se ferme seule, comme avant le 13/11/2026.

### Design : animations et arrondis harmonisés
- Toutes les animations de Side passent par quatre mouvements nommés (survol, bascule, glissement, ressort) au lieu d'une quinzaine de réglages voisins. Elles s'arrêtent toutes quand « Réduire les animations » est activé dans les réglages d'accessibilité du Mac (seules 4 le faisaient).
- Les gris (fonds de pastilles, survol, sélection, contours) passent par cinq valeurs nommées au lieu de seize : le survol et la sélection ont maintenant la même force partout (barre latérale, colonnes, Dock).
- Bulles d'aide (et noms lus par VoiceOver) sur les boutons-icônes qui n'en avaient pas : les cinq boutons du lecteur Spotify, le bouton d'envoi de la barre de commande, la croix de la pastille d'information.
- Tous les arrondis passent par une échelle de neuf valeurs. Les écarts corrigés sont de 1 à 2 points : rien de visible à l'œil nu (vérifié sur les photos).

### Tiroir, plein écran, presse-papiers : les bugs restants de la relecture
- Tiroir : avec un second écran à droite, les fenêtres rangées par le tiroir ne s'affichent plus sur cet écran : elles sont garées après le bord droit de tous les écrans.
- Tiroir : un clic à l'emplacement des boutons vert ou jaune d'une tuile n'est plus pris par le tiroir quand une boîte de dialogue de l'application est par-dessus.
- « Mes applications » partagées par iCloud : une liste pas encore descendue sur ce Mac n'est plus écrasée, et une liste vide n'est jamais déposée.
- Les journaux de diagnostic (`~/Library/Logs`) sont ramenés à un demi-mégaoctet au lancement quand ils dépassent 2 Mo.
- Presse-papiers : l'aperçu des liens (image et titre du site) ne se charge plus tout seul pour un lien simplement copié, seulement pour les liens enregistrés. Visiter un lien copié pouvait consommer un lien à usage unique (connexion, confirmation, désinscription). Réglages > Historique et liens > « Aussi pour les liens simplement copiés » rétablit l'ancien comportement.
- Presse-papiers : les images d'aperçu gardées en mémoire ne s'accumulent plus sans fin.
- Grille : une capture ne reste plus collée sur la grille quand on enchaîne deux choix ; Échap pendant qu'on tire une case ne laisse plus de vignette fantôme.
- Écran partagé : les fenêtres fermées sont retirées des groupes (après un redémarrage du Mac, deux fenêtres sans rapport pouvaient se retrouver groupées).
- Finder : brancher ou débrancher un écran, ou changer de résolution, referme la carte ouverte (elle gardait l'ancienne place).
- Les textes ajoutés ces derniers jours (minuteur de sommeil, réglages YouTube, aperçu des liens) ont leur version anglaise.

### Finder : quatre bugs de plus
- Zones de dépôt : un fichier rangé sur un disque externe ou un serveur n'est plus oublié quand on débranche le disque. Il réapparaît au rebranchement.
- Zones de dépôt : deux fichiers différents mais identiques (une copie volontaire) restent tous les deux. Seules les images que Side a lui-même créées sont encore fusionnées.
- Geste à quatre doigts : un trackpad allumé après Side, ou reconnecté après une veille, est maintenant écouté (Side refait la liste toutes les 20 secondes et au réveil). Vaut pour le Finder et pour le plein écran.
- Après être entré dans un dossier, un clic droit, un glisser ou Espace dans le vide ne visent plus l'ancien élément qui était sous la souris.
- Dupliquer (⌘D) se fait en arrière-plan : un gros dossier ne fige plus Side.
- Outil de photos : les copies de test ont maintenant leurs propres réglages (une copie figée des tiens) ; `tools/snap.sh dossier --rafraichir` reprend tes réglages du moment.

### Raccourcis clavier : un seul aiguillage pour toute l'application
- Avant, le Finder, le plein écran et le tiroir avaient chacun leur propre façon d'enregistrer un raccourci, et chacun sa façon d'en saisir un nouveau dans les réglages : trois copies, d'où les bugs corrigés plus bas. Tout passe maintenant par un seul endroit (`Raccourcis.swift`).
- Un raccourci refusé par macOS (déjà pris) est noté dans le journal avec le nom de la partie de Side qui l'occupe déjà.
- Commencer à saisir un raccourci abandonne une saisie restée en cours ailleurs.

### Photos d'écran de test : plus aucun effet sur le vrai Side
- Les copies de Side lancées par `tools/snap.sh` partagent les réglages du vrai Side. Elles démarraient pourtant tout : surveillance du trackpad, raccourcis, tiroir, presse-papiers (qui pouvait réécrire l'historique). Elles ne font plus que dessiner leur image et quitter.

### Code rangé : Side.swift découpé en vingt-deux fichiers
- Rien ne change dans l'application : le code a été déplacé tel quel, sans une ligne modifiée (vérifié ligne par ligne, et les 38 photos d'écran sont identiques).
- `Side.swift` passe de 7 764 à 2 946 lignes. Le reste est rangé par thème (réglages, fichiers, carte, barre latérale, colonnes, Dock, zones de dépôt, gestes, réglages…).
- Le cœur de l'application (`AppDelegate`, 2 840 lignes) est à son tour réparti en huit fichiers `Carte+…` (affichage, souris, clavier, clic droit, dépôt, menus…). `Side.swift` ne garde que ses variables et le lancement : 714 lignes.
- Même chose pour le tiroir : `PanneauBas.swift` passe de 3 440 à 840 lignes, le reste en dix fichiers `Tiroir+…`.
- Et pour le plein écran : `PleinEcran.swift` est réparti en six fichiers par thème (modèle, fenêtres, images, raccourcis, grille, pilotage).
- Plus aucun fichier ne dépasse 1 100 lignes (le plus gros en faisait 7 764).
- `ARCHITECTURE.md` dit où se trouve quoi.

### Grande relecture du code : une trentaine de bugs corrigés
Side a été relu en entier avec la méthode BAMA (branche `refonte-bama`). Rien ne change à l'écran : les 38 photos d'écran de contrôle sont identiques avant et après.

Raccourcis clavier
- Le raccourci du Finder et celui de la grille écrivaient le même réglage : effacer l'un pouvait empêcher Side de démarrer, changer l'autre pouvait faire capturer une lettre seule dans tout le Mac. Chacun a maintenant son réglage.
- Chaque raccourci n'est plus traité que par sa partie (le raccourci du Finder pouvait ouvrir la grille à sa place).
- Un raccourci déjà pris par une autre partie de Side est refusé avec un bip, au lieu d'être affiché comme actif.
- Fermer les réglages pendant le choix d'un raccourci (Finder, tiroir, presse-papiers) annule ce choix : le raccourci ne reste plus coupé, et la combinaison suivante tapée dans Side n'est plus prise pour un raccourci.
- Une touche seule, sans Commande, Contrôle ni Option, ne peut plus devenir un raccourci global.

Finder
- Le geste à quatre doigts marche dès la première installation (il fallait décocher puis recocher le réglage).
- Coller, déposer dans un dossier et vider la corbeille se font en arrière-plan : une grosse copie ne fige plus Side ni les clics du reste du Mac.
- Un dossier ne peut plus être collé dans lui-même.
- La recherche ne reste plus coincée sur d'anciens résultats quand on tape vite.
- Après la fermeture de la carte, Espace ou le clic droit ne visent plus l'élément qui était sous la souris la fois d'avant.
- « Dernier dossier consulté » : le dossier retrouvé au lancement est le bon, même si Side a été quitté carte ouverte.
- Une colonne épinglée ne change plus de place toute seule après un glisser abandonné.
- Avec « Fermer quand la souris en sort », la carte reste ouverte pendant un aperçu (Espace) ou pendant qu'on renomme.
- Un texte copié de plus d'un million de caractères n'entre plus dans l'historique du presse-papiers (il ralentissait tout pendant sept jours).

Tiroir
- Quitter Side, ou couper le tiroir dans les réglages, rend à l'écran les fenêtres que le tiroir gardait hors de l'écran (elles restaient invisibles jusqu'au prochain lancement).
- La grande fenêtre de Notes revient quand on retire la dernière note du tiroir.
- Une application figée ne fige plus Side, et sa tuile n'est plus retirée du tiroir par erreur.
- Retirer YouTube (ou un site) du tiroir l'arrête vraiment : le son ne continue plus, sans moyen de l'arrêter.
- Une page du tiroir que macOS a arrêtée faute de mémoire se recharge, au lieu de rester blanche.
- Spotify : une panne de réseau ne déconnecte plus le compte ; un seul renouvellement de connexion part à la fois ; si le port 8765 est pris, Side le dit au lieu d'attendre sans fin ; un titre choisi quand Spotify est fermé se lance une fois Spotify ouvert.
- Minuteur de sommeil : le menu garde la durée choisie quand on rouvre les réglages, et « Jamais » l'annule vraiment.
- Le signe moins de la liste « + » retire toujours la bonne tuile, même si la liste a changé entre-temps ; plus de plantage possible si une application du tiroir quitte pendant le geste à quatre doigts.
- Les commandes d'essai qui agissent sur des fichiers ou sur la page YouTube ne sont plus écoutées par défaut (`defaults write com.gauthieraube.side essais -bool true` pour les rallumer).

Plein écran
- Le bouton vert marche encore sur une fenêtre déjà agrandie dont Side ne connaît pas l'ancienne taille (après un redémarrage de Side) : elle reprend une taille réduite, centrée.
- Partie « Plein écran » coupée : ⌘1 à ⌘9, ⌥ Tab, le coin de la grille et ⌃⌥Entrée sont vraiment coupés (⌘1 à ⌘9 restaient pris dans toutes les applications).
- Plus de plantage de la grille avec une fenêtre réglée sur « tous les bureaux ».
- Une application figée bloque la grille beaucoup moins longtemps.
- Le fond noir des vidéos cesse de surveiller l'écran quatre fois par seconde une fois la vidéo fermée.
- La mémoire prise par les fonds d'écran de la grille ne grossit plus sans fin.
- La présentation fermée par sa croix rouge ne revient plus à chaque lancement.

Design
- Début du système de design : `Sources/Design.swift` nomme les sept arrondis de Side (de 4 à 22) et trois vitesses d'animation ; 82 arrondis du code y sont rattachés, sans changement à l'écran. Le mode d'emploi et la liste de ce qui reste à aligner sont dans `design/DESIGN-SYSTEM.md`.
- Ce qui reste à faire (bugs à essayer à l'écran, découpage du code) est noté dans `docs/relecture-2026-11-15.md`.

Outil
- `tools/snap.sh` photographie les 19 écrans vérifiables hors écran (la carte et les 17 volets de réglages), en clair et en sombre, sans rien installer ni afficher.

## 14/11/2026

### Tiroir : tailles minimum fiables, pastille d'explication, réglages des applications
- La pastille nomme aussi l'application qui impose sa taille quand ce n'est pas celle qu'on regarde (DeepL, par exemple, quand on réduit le tiroir avec Réglages Système affiché) : le tiroir revient à sa taille, et on sait pourquoi.
- Une taille minimum n'est plus retenue pour une application qu'après vérification : redemandée à sa place, elle dépasse encore une demi-seconde plus tard. (Une application qui n'avait simplement pas encore suivi faisait retenir une taille trop grande, et le tiroir regrandissait ensuite tout seul.)
- Quand on essaie de réduire le tiroir plus que ce qu'une application accepte, une pastille monte du bas de l'écran, comme dans Horizon : « « Notes » ne peut pas être moins haute : le tiroir s'arrête à 680 points ». Elle explique aussi la limite propre au tiroir.
- Les réglages d'une application du tiroir (et ses autres fenêtres secondaires) s'ouvrent par-dessus, normalement : ils ne prennent plus la place de sa fenêtre dans le tiroir.

## 13/11/2026

### Vidéo et plein écran
- Carrousel vers ou depuis un plein écran d'Apple (vidéo de Safari) : la carte ne grandit plus jusqu'à sa place pendant que macOS fait glisser l'écran d'un espace à l'autre (deux mouvements à la fois, ça sautait) ; le carrousel s'efface simplement et laisse macOS faire sa transition.
- La vidéo du tiroir en plein écran ne revient plus d'elle-même dans le tiroir quand on passe à une autre application (YouTube quittait son plein écran dès que la page n'était plus visible). Seuls le bouton du lecteur, la touche f, le double-clic, Échap ou un changement de page la ramènent.
- Aller à la vidéo par le carrousel ou la grille : Side passe devant par ses propres moyens (l'application d'avant revenait devant au bout d'une seconde).
- Quatre doigts : si le balayage de macOS entre les plein écran d'Apple est coupé (Réglages du trackpad), Side prend toujours le geste, même quand une vidéo de Safari est dans un plein écran d'Apple ; il devient une carte du carrousel. Les réglages du carrousel l'expliquent, avec un bouton vers les réglages du trackpad.

### Finder : la barre de commande (comme Substage)
- Une pilule d'une seule ligne (38 points de haut). Sans sélection, elle dit « Aucun fichier sélectionné : sélectionne des fichiers dans le Finder » ; avec une sélection, elle donne le nombre de fichiers et un exemple qui leur va, et propose ses actions rapides sur la même ligne. Elle ne s'agrandit que pour une proposition, un résultat ou une erreur. En français et en anglais.
- La barre descend et remonte avec le Finder, dans la même animation que lui, exactement comme la zone de dépôt. Ouvert ou fermé aux quatre doigts, elle suit les doigts avec lui (elle apparaissait seule, au milieu de l'écran, pendant que le Finder suivait encore les doigts).
- Sous le Finder de Side, une barre où l'on écrit ce qu'on veut faire des fichiers sélectionnés : « convertis en JPG », « réduis à 1080 px de haut », « tourne vers la gauche », « enlève le fond », « fais-en un PDF », « fusionne ces PDF », « extrais le texte », « zippe tout », « convertis en MP4 720p », « extrais le son ».
- Les mots simples (jpg, zip, mp4…) sont compris tout de suite ; le reste par Apple Intelligence, sur le Mac, sans Internet ni compte. Des boutons rapides proposent les actions qui vont avec la sélection.
- Sécurité : la barre choisit une action dans une liste connue (jamais une commande inventée), montre ce qu'elle va faire et attend Entrée. Les originaux ne sont jamais modifiés : le résultat est un nouveau fichier, à côté.
- Réglages > Finder > Barre latérale et fichiers : la barre peut être masquée.

### Tiroir : les liens extérieurs de YouTube s'ouvrent dans le navigateur
- Un lien dans la description d'une vidéo YouTube (qui passe par « youtube.com/redirect ») s'ouvrait dans la tuile multimédia. Il s'ouvre maintenant dans le navigateur par défaut, comme tout lien qui mènerait la tuile hors de YouTube.

### Finder : Imprimer
- Clic droit sur un fichier : « Imprimer » le confie à son application pour l'imprimer, comme Fichier > Imprimer dans le Finder. Avec plusieurs fichiers sélectionnés, ils sont tous imprimés.

### Finder : la zone de dépôt compte comme le Finder
- Avec « Fermer quand la souris en sort », passer la souris sur la zone de dépôt ne referme plus le Finder.

### Les quatre parties de Side, activables et reconnaissables
- Réglages > Général : « Les parties de Side » permet d'activer ou de couper le Finder, le plein écran (grille, carrousel, agrandissement, numéros), le tiroir et le presse-papiers. Une partie coupée ne s'ouvre plus, ni par son coin, ni par son raccourci, ni par son geste ; ses réglages restent.
- Chaque partie a sa couleur et son symbole : Finder en bleu, plein écran en orange, tiroir en rose, presse-papiers en jaune. La barre latérale des réglages en reprend la couleur pour tous ses volets, et chaque volet affiche en tête la partie où l'on est (avec « désactivé » et un bouton « Activer » si elle est coupée).

### Tiroir : redimensionnement en direct
- Le tiroir ne regrandit plus une seconde après qu'on l'a réduit : une hauteur minimum retenue trop grande pour une application (Notes, 680 points) l'en empêchait. Quand l'application se laisse rendre plus petite, la taille retenue est corrigée ; les anciennes tailles retenues ont été effacées.
- **macOS 27.2** : le Centre de notifications garde désormais une fenêtre transparente sur tout l'écran. Side la prenait pour une fenêtre posée sur le tiroir, et ses bords ne se laissaient plus attraper. Elle est ignorée : on peut de nouveau changer la hauteur et la largeur du tiroir.
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
