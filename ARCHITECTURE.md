# Architecture de Side

Une seule application, compilée d'un bloc par `swiftc` (tous les fichiers de `Sources/` ensemble, sans Xcode ni paquet).
Un fichier = un thème. Les quatre parties de Side (Finder, Plein écran, Tiroir, Presse-papiers) se reconnaissent au nom.

## Le Finder (la carte)

| Fichier | Contient |
| --- | --- |
| `Side.swift` | la fenêtre de la carte, et `AppDelegate` : ses variables, le lancement de l'application |
| `Carte+Affichage.swift` | ouvrir et fermer la carte, la faire suivre les quatre doigts |
| `Carte+Surveillance.swift` | coins actifs, fermeture quand la souris sort |
| `Carte+Menus.swift` | menu de la barre des menus, raccourci du Finder |
| `Carte+Clavier.swift`, `Carte+Souris.swift` | clavier et souris dans la carte, comme dans le Finder |
| `Carte+MenuContextuel.swift` | clic droit, coup d'œil |
| `Carte+Depot.swift`, `Carte+Secousse.swift` | fichiers et applications déposés, secousse du pointeur |
| `Reglages.swift` | valeurs fixes (`Reglages`) et choix de l'utilisateur (`Config`) |
| `Fichiers.swift` | lecture des dossiers (`Fichiers`), zones de dépôt (`Etagere`), colonnes (`Column`), magasin de la carte (`Store`) |
| `Carte.swift` | vue principale (`DrawerView`), bienvenue, onglets |
| `BarreLaterale.swift` | barre latérale, corbeille, modificateurs de glisser-déposer |
| `Colonnes.swift` | listes, icônes, colonnes Miller, aperçu, sélection |
| `Arborescence.swift` | la présentation « Arborescence » (arbre des dossiers à gauche, liste à droite), comme l'Explorateur de Windows |
| `Renommage.swift`, `Enregistrements.swift` | renommer sur place ; fichiers enregistrés ailleurs (la carte s'ouvre sur eux) et Side comme visualiseur de fichiers |
| `Zones.swift` | zones de dépôt et colonnes épinglées (affichage) |
| `Dock.swift` | mini-Dock et lanceur d'applications |
| `DepotFlottant.swift` | la zone de dépôt flottante |
| `FenetreReglages.swift` | la fenêtre des réglages et ses volets |

## Les autres parties

| Fichiers | Partie |
| --- | --- |
| `PleinEcran*.swift` | le plein écran (ex-Square) : modèle des fenêtres, placement, images, raccourcis, grille, pilotage (`PleinEcranAppli`), Dock, carrousel, écran partagé, bouton vert |
| `PanneauBas*.swift`, `Tiroir*.swift`, `MesApplications.swift` | le tiroir : `PanneauBas.swift` garde ses variables et ses petites pièces ; `Tiroir+…` ses fonctions par thème (ouvrir et fermer, taille, défilement, fenêtres empruntées…) ; YouTube et Spotify à part |
| `PresseVolet.swift`, `PressePapiers.swift` | le presse-papiers : volet et historique |
| `Encoche*.swift`, `Descente.swift` | l'île de l'encoche : fenêtre, souris et réglages (`Encoche`), dessin (`EncocheVues`), musique, agenda et bac (`EncocheSources`), volume et luminosité (`EncocheTouches`), fenêtres qui descendent de l'encoche (`Descente`) |
| `Recherche.swift` | la recherche sur le web : la pilule qui descend de l'encoche, la page (moteur de Safari), son raccourci et ses réglages |

## Commun

| Fichier | Contient |
| --- | --- |
| `Design.swift` | arrondis et durées nommés (voir `design/DESIGN-SYSTEM.md`) |
| `Gestes.swift`, `Gestes4Doigts.swift` | cercle à la souris, geste à quatre doigts |
| `Ecrans.swift` | les écrans : le seul endroit qui choisit un écran (`Ecrans.deTravail`, celui de la souris), passe d'AppKit à AX (`versAX`, `versNS`), gare les fenêtres (`garage`) et lit le plein écran d'Apple d'un écran. Logique pure dans `DispositionEcrans`, vérifiée par `Side --test-ecrans` |
| `Systeme.swift`, `Reseau.swift` | ce que Side lit de macOS : captures en cours, raccourcis du système, serveurs du réseau |
| `IALocale.swift` | l'IA locale (serveur Ollama du Mac ou du réseau, jamais Internet) : ses réglages (`ConfigIA`), le client (`IALocale`), le nom des captures d'écran (`NomDeCapture`, vérifié par `Side --test-nom-capture` et `--test-capture fichier`), son volet de réglages |
| `Parties.swift` | les quatre parties et leur interrupteur |
| `Raccourcis.swift` | tous les raccourcis clavier globaux, et la saisie d'un nouveau raccourci |
| `Pilule.swift`, `Presentation.swift`, `Langue.swift` | pastille d'information, présentation, langue |

## Règles

- `AppDelegate` (`Carte+*.swift`) et `PanneauBas` (`Tiroir+*.swift`) sont répartis en extensions. Ses variables restent dans la classe (`Side.swift`) : Swift n'en accepte pas dans une extension.

- Les réglages sont lus et écrits par `Config` (Finder), `ConfigTiroir` (tiroir), `ConfigPresse` (presse-papiers),
  `Appli` (plein écran), `ConfigIA` (IA locale). Une clé `UserDefaults` n'appartient qu'à un seul d'entre eux.
- Un seul registre de raccourcis globaux : `RaccourcisGlobaux` (`Raccourcis.swift`), un nom par raccourci (« finder »,
  « tiroir.42 », « pleinEcran.200 »). `Touches` et `TouchesBas` ne font que préfixer le nom. Une seule saisie de raccourci
  dans les réglages : `SaisieRaccourci` (sauf la grille, qui a sa petite fenêtre).
- Mode photo (`--image`) : `lancerModePhoto()` est appelé avant tout démarrage. La copie partage les réglages du vrai Side :
  elle ne doit rien écouter ni rien écrire.
- Écrans : jamais `NSScreen.main` ni `NSScreen.screens.first` pour choisir un écran ou convertir des coordonnées : passer par `Ecrans`. Le tiroir garde l'écran choisi à l'ouverture (`écranDuTiroir`).
- Le travail lent (copie de fichiers, disques réseau, questions aux autres applications) ne se fait pas sur le fil principal :
  les filtres d'événements de Side tournent dessus, et un blocage retiendrait les clics de tout le Mac.
- Les réglages des autres applications sont interrogés avec un délai maximum de 0,3 s.

## Preuve qu'un déplacement ne change rien

`tools/snap.sh` avant et après : les 40 images doivent être identiques à l'octet près.
