#!/bin/bash
# Compile Side, l'installe dans ~/Applications et le relance.
# (Le dossier du projet et l'identifiant interne gardent l'ancien nom « tiroir » pour conserver les réglages.)
set -e
cd "$(dirname "$0")"
APP=build/Side.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 \
  Sources/Tiroir.swift -o "$APP/Contents/MacOS/Side"
mkdir -p "$APP/Contents/Resources/fr.lproj"
cp Info.plist "$APP/Contents/Info.plist"
cp Icone/Side.icns "$APP/Contents/Resources/Side.icns"
# Signature stable : avec le certificat « Apple Development » du trousseau, macOS reconnaît Side d'une
# compilation à l'autre et ne redemande plus les autorisations (dossiers, Accessibilité).
# Sans certificat, on retombe sur une signature jetable : les autorisations sont alors redemandées à chaque fois.
IDENT=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/')
if [ -n "$IDENT" ] && codesign --force --deep --sign "$IDENT" "$APP"; then
  echo "Signé avec : $IDENT"
else
  codesign --force --deep --sign - "$APP"
  echo "Signature jetable (pas de certificat utilisable)."
fi
mkdir -p ~/Applications
pkill -x Side || true
pkill -x Nook || true
pkill -x Tiroir || true
sleep 0.5
rm -rf ~/Applications/Side.app ~/Applications/Nook.app ~/Applications/Tiroir.app
cp -R "$APP" ~/Applications/
open -g ~/Applications/Side.app --args "$@"   # -g : sans prendre le clavier à l'app en cours
echo "Side installé et lancé."
