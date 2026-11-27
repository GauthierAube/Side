#!/bin/bash
# Le droit de LIRE le trousseau de l'app Horizon (groupe TJZP4L6UH5.online.wakademy.horizon) : sans lui, les vues
# d'Horizon dans Side ne voient pas les clés du site (CRM « Site non connecté », « Aucun élève ») ni celles de Meta.
# Sur Mac, ce droit demande un profil d'Apple posé dans l'app. On prend celui que Xcode a déjà fait pour ce Mac
# (« Mac Team Provisioning Profile: * » ou un profil de Side) : rien n'est demandé à Apple, aucune clé n'est lue ici.
# Usage : tools/trousseau-horizon.sh <app> <dossier de travail>
# Écrit sur la sortie le chemin du fichier de droits à donner à codesign, ou rien (Side se signe alors sans ce droit).
APP=$1
TRAVAIL=$2
EQUIPE=TJZP4L6UH5
GROUPE=$EQUIPE.online.wakademy.horizon
ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Contents/Info.plist" 2>/dev/null) || exit 0
UDID=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Provisioning UDID/ {print $2}')
[ -n "$UDID" ] || exit 0
mkdir -p "$TRAVAIL"
for DOSSIER in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
  for P in "$DOSSIER"/*.provisionprofile; do
    [ -f "$P" ] || continue
    security cms -D -i "$P" > "$TRAVAIL/profil.plist" 2>/dev/null || continue
    if /usr/bin/python3 - "$TRAVAIL/profil.plist" "$EQUIPE" "$ID" "$UDID" "$GROUPE" <<'PY'
import plistlib, sys, datetime, fnmatch
chemin, equipe, ident, udid, groupe = sys.argv[1:]
p = plistlib.load(open(chemin, "rb"))
d = p.get("Entitlements", {})
ok = ("OSX" in p.get("Platform", [])
      and p.get("ExpirationDate", datetime.datetime.min) > datetime.datetime.now()
      and udid in p.get("ProvisionedDevices", [])
      and fnmatch.fnmatchcase(f"{equipe}.{ident}", d.get("com.apple.application-identifier", ""))
      and any(fnmatch.fnmatchcase(groupe, g) for g in d.get("keychain-access-groups", [])))
sys.exit(0 if ok else 1)
PY
    then
      cp "$P" "$TRAVAIL/embedded.provisionprofile"
      cat > "$TRAVAIL/Side.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.application-identifier</key>
	<string>$EQUIPE.$ID</string>
	<key>com.apple.developer.team-identifier</key>
	<string>$EQUIPE</string>
	<key>keychain-access-groups</key>
	<array>
		<string>$GROUPE</string>
	</array>
</dict>
</plist>
EOF
      echo "$TRAVAIL/Side.entitlements"
      exit 0
    fi
  done
done
exit 0
