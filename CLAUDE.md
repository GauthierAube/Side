# Side

Application Mac (Swift 5, AppKit et SwiftUI, compilée avec `swiftc` par `build.sh`, sans Xcode).

- Règles de design : `design/DESIGN-SYSTEM.md`. Utiliser ses noms (`Rayon`, `Mouvement`) ; jamais un arrondi ou une durée en dur.
- Vérifier un changement d'écran : `tools/snap.sh [dossier]` photographie la carte et les 17 volets de réglages, en clair et
  en sombre, sans rien installer ni afficher. Regarder les images avant d'annoncer un résultat. Les copies de test ont leurs
  propres réglages figés (`com.gauthieraube.side.photo`) ; `--rafraichir` en second argument les reprend du vrai Side.
- `./build.sh` compile, installe dans `~/Applications` et relance Side : à ne lancer que quand le changement est prêt.
- Chaque changement se note en haut de `changes-side.md`, en français simple, dans le même enregistrement que le code.
- Relecture du 15/11/2026 (bugs restants, pistes d'architecture) : `docs/relecture-2026-11-15.md`.

Méthode BAMA, adaptée à Side :

| Chez BAMA | Dans Side |
| --- | --- |
| `./build.sh` | `./build.sh` (installe et relance) |
| mode photo (`APP_SNAPSHOT`) | `Side --image fichier.png [--volet nom] [--sombre]`, ou `tools/snap.sh` |
| `swift test` | pas encore de tests ; essais par arguments (`--test-fleches`, `--test-geste`) |
