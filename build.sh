#!/bin/bash
# Compile Side, l'installe dans ~/Applications et le relance.
set -e
cd "$(dirname "$0")"
APP=build.noindex/Side.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Les textes viennent du catalogue Apple Localizable.xcstrings : texte source en français, traduction anglaise.
# Avec Xcode, le catalogue est mis à jour depuis le code à chaque compilation, puis compilé dans Resources/<langue>.lproj.
# Ces fichiers compilés sont gardés dans le dépôt : sans Xcode (outils en ligne de commande seuls), on compile avec eux.
EXTRAIRE=()
if xcrun --find xcstringstool >/dev/null 2>&1; then
  mkdir -p build.noindex/textes
  EXTRAIRE=(-emit-localized-strings -emit-localized-strings-path build.noindex/textes)
  [ -f Localizable.xcstrings ] || echo '{"sourceLanguage":"fr","strings":{},"version":"1.0"}' > Localizable.xcstrings
fi
# Le lecteur YouTube du tiroir est Peinard (~/Github/sans-pub) quand il est sur ce Mac : il demande macOS 26.
PEINARD_OPTS=$(tools/peinard.sh build.noindex/peinard "$APP/Contents/Resources")
CIBLE=arm64-apple-macos14.0
if [ -n "$PEINARD_OPTS" ]; then CIBLE=arm64-apple-macos26.0; echo "Avec Peinard comme lecteur YouTube."; fi
swiftc -O -swift-version 5 -parse-as-library -target $CIBLE \
  Sources/*.swift -o "$APP/Contents/MacOS/Side" "${EXTRAIRE[@]}" $PEINARD_OPTS
if [ ${#EXTRAIRE[@]} -gt 0 ]; then
  xcrun xcstringstool sync Localizable.xcstrings --stringsdata build.noindex/textes/*.stringsdata
  xcrun xcstringstool compile Localizable.xcstrings -o Resources
  mkdir -p Resources/fr.lproj
  # Le français est la langue des textes du code, mais l'outil d'Apple ne produit que les traductions. Sans fichier
  # français, macOS se rabattrait sur l'anglais (langue de développement) : on écrit donc la table française, à l'identique.
  /usr/bin/python3 -c 'import json,plistlib,sys; c=json.load(open("Localizable.xcstrings")); plistlib.dump({k: k for k in c["strings"]}, open(sys.argv[1], "wb"))' Resources/fr.lproj/Localizable.strings
  if [ -f InfoPlist.xcstrings ]; then xcrun xcstringstool compile InfoPlist.xcstrings -o Resources; fi
fi
mkdir -p Resources/en.lproj Resources/fr.lproj
cp -R Resources/*.lproj "$APP/Contents/Resources/"   # anglais et français
cp Info.plist "$APP/Contents/Info.plist"
cp Icone/Side.icns "$APP/Contents/Resources/Side.icns"
# Signature stable : avec le certificat « Apple Development » du trousseau, macOS reconnaît Side d'une
# compilation à l'autre et ne redemande plus les autorisations (dossiers, Accessibilité).
# Sans certificat, on retombe sur une signature jetable : les autorisations sont alors redemandées à chaque fois.
IDENT=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/')
if [ -n "$IDENT" ] && codesign --force --deep --sign "$IDENT" "$APP"; then
  echo "Signé avec : $IDENT"
  # Les vues d'Horizon lisent les clés du site et de Meta dans le trousseau de l'app Horizon (tools/trousseau-horizon.sh).
  # Seule l'app elle-même reçoit ce droit (pas --deep) ; sans profil pour ce Mac, Side reste signé comme avant.
  DROITS=""
  [ -n "$HORIZON_OPTS" ] && DROITS=$(tools/trousseau-horizon.sh "$APP" build.noindex/trousseau)
  if [ -n "$DROITS" ]; then
    cp build.noindex/trousseau/embedded.provisionprofile "$APP/Contents/embedded.provisionprofile"
    if codesign --force --sign "$IDENT" --entitlements "$DROITS" "$APP"; then
      echo "Avec le trousseau d'Horizon (clés du site et de Meta, en lecture)."
    else
      rm -f "$APP/Contents/embedded.provisionprofile"
      codesign --force --deep --sign "$IDENT" "$APP"
    fi
  fi
else
  codesign --force --deep --sign - "$APP"
  echo "Signature jetable (pas de certificat utilisable)."
fi
mkdir -p ~/Applications
pkill -x Side || true
# Square fait désormais partie de Side (13/11/2026) : l'ancienne app est arrêtée et mise à la corbeille (récupérable).
pkill -x Square || true
if [ -d ~/Applications/Square.app ]; then mv ~/Applications/Square.app ~/.Trash/Square-$(date +%Y%m%d-%H%M%S).app; fi
pkill -x Nook || true
pkill -x Tiroir || true
sleep 0.5
rm -rf ~/Applications/Side.app ~/Applications/Nook.app ~/Applications/Tiroir.app
# Premier lancement sur un Mac : si Side n'a encore aucun réglage ici et qu'une sauvegarde existe dans iCloud Drive
# (faite avec « defaults export com.gauthieraube.side <fichier> »), on la reprend. Ce fichier reste dans iCloud, jamais dans le dépôt.
REGLAGES=~/Library/Mobile\ Documents/com~apple~CloudDocs/side-reglages.plist
if ! defaults read com.gauthieraube.side >/dev/null 2>&1 && [ -f "$REGLAGES" ]; then
  defaults import com.gauthieraube.side "$REGLAGES" && echo "Réglages repris depuis iCloud Drive."
fi
cp -R "$APP" ~/Applications/
open -g ~/Applications/Side.app --args "$@"   # -g : sans prendre le clavier à l'app en cours
echo "Side installé et lancé."
