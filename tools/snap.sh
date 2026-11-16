#!/bin/bash
# Photographie chaque écran de Side, en clair et en sombre, SANS rien afficher ni installer :
# compile dans build-test/ (le Side installé n'est pas touché), puis dessine chaque écran dans une image.
# Usage : tools/snap.sh [dossier de sortie] [--rafraichir]   (par défaut /tmp/Side-shots)
set -e
cd "$(dirname "$0")/.."
SORTIE=${1:-/tmp/Side-shots}
APP=build-test/Side.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SORTIE"
PEINARD_OPTS=$(tools/peinard.sh build-test/peinard "$APP/Contents/Resources")
CIBLE=arm64-apple-macos14.0; [ -n "$PEINARD_OPTS" ] && CIBLE=arm64-apple-macos26.0
swiftc -Onone -swift-version 5 -parse-as-library -target $CIBLE \
  Sources/*.swift -o "$APP/Contents/MacOS/Side" $PEINARD_OPTS 2>&1 | grep -E "error:" && exit 1
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
# Les copies de test ont leur propre nom d'application, donc leurs propres réglages : une copie figée des tiens.
# Ainsi les photos ne changent pas quand tu changes un réglage dans le vrai Side, et le vrai Side n'est jamais touché.
# « tools/snap.sh dossier --rafraichir » reprend tes réglages du moment.
plutil -replace CFBundleIdentifier -string com.gauthieraube.side.photo "$APP/Contents/Info.plist"
if [ "$2" = "--rafraichir" ] || ! defaults read com.gauthieraube.side.photo >/dev/null 2>&1; then
  defaults export com.gauthieraube.side - | defaults import com.gauthieraube.side.photo -
  echo "Réglages des photos repris de Side."
fi
BIN="$APP/Contents/MacOS/Side"
# Garde-fou : une photo qui ne rend pas la main au bout de 30 s est arrêtée (elle manquera dans la liste).
( sleep 30; pkill -f "$BIN --image" ) &
GARDE=$!
VOLETS="general coins clavier gestes apparence fermeture fichiers colonnes depot tiroir multimedia applications presse grille dock carrousel fenetres"
for mode in clair sombre; do
  "$BIN" --image "$SORTIE/carte-$mode.png" --$mode >/dev/null 2>&1 &
  "$BIN" --image "$SORTIE/carte-presse-$mode.png" --presse --$mode >/dev/null 2>&1 &
  for v in $VOLETS; do
    "$BIN" --image "$SORTIE/reglages-$v-$mode.png" --volet "$v" --$mode >/dev/null 2>&1 &
  done
  wait $(jobs -p | grep -v "^$GARDE$")
done
kill $GARDE 2>/dev/null || true
for f in "$SORTIE"/*.png; do echo "SNAPSHOT $f"; done
echo "SNAPSHOT done $SORTIE"
