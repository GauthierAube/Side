#!/bin/zsh
# Compile l'app iPhone « Side » (le presse-papiers de Side sur l'iPhone) et l'installe
# sur l'iPhone (branché, ou déverrouillé sur le même Wi-Fi que le Mac).
set -e -o pipefail
cd "$(dirname "$0")"
IPHONE=$(xcrun devicectl list devices 2>/dev/null | grep "physical" | grep "iPhone" | grep -v "unavailable" | grep -E "available|connected" \
  | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)
if [[ -z "$IPHONE" ]]; then
  echo "iPhone introuvable : branche-le ou déverrouille-le sur le même Wi-Fi que le Mac."
  exit 1
fi
TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject | sed -E 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/')
xcodebuild -project SidePresse.xcodeproj -scheme SidePresse -configuration Release -derivedDataPath build \
  -destination "id=$IPHONE" DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates build | grep -E "error|BUILD" || true
[[ -d build/Build/Products/Release-iphoneos/Side.app/PlugIns/Widget.appex ]] || exit 1
xcrun devicectl device install app --device "$IPHONE" "build/Build/Products/Release-iphoneos/Side.app" \
  | grep -iE "error|installed" || true
echo "Installé sur l'iPhone : l'app s'appelle « Side »."
