#!/bin/bash
# Compile Peinard (l'app iPhone de Gauthier, dossier ~/Github/sans-pub, ou $PEINARD) en une brique pour Side :
# le lecteur YouTube du tiroir. Usage : tools/peinard.sh <dossier de la brique> <dossier Resources de l'app>
# Écrit sur la sortie les options à donner à swiftc pour Side, ou rien si Peinard n'est pas sur ce Mac
# (Side garde alors son ancien lecteur YouTube).
set -e
SRC=${PEINARD:-"$(cd "$(dirname "$0")/../.." && pwd)/sans-pub"}
OUT=$1
RES=$2
[ -d "$SRC/SansPub" ] || exit 0
mkdir -p "$OUT" "$RES"
swiftc -O -parse-as-library -swift-version 6 -target arm64-apple-macos26.0 -module-name Peinard \
  -emit-library -static -emit-module -emit-module-path "$OUT/Peinard.swiftmodule" -o "$OUT/libPeinard.a" \
  $(find "$SRC/SansPub" -name '*.swift') > "$OUT/compilation.log" 2>&1 || {
    # Peinard ne compile pas pour Mac (par exemple une branche sans sa version Mac) : Side se construit quand même,
    # avec son ancien lecteur YouTube.
    echo "Peinard ne compile pas pour Mac (voir $OUT/compilation.log) : ancien lecteur YouTube." >&2
    exit 0
  }
# Les scripts et le style que Peinard injecte dans la page, et son logo.
find "$SRC/SansPub" \( -name '*.js' -o -name '*.css' \) -exec cp {} "$RES/" \;
xcrun actool "$SRC/SansPub/Assets.xcassets" --compile "$RES" --platform macosx \
  --minimum-deployment-target 26.0 --output-format human-readable-text >/dev/null 2>&1 || true
echo "-I $OUT -L $OUT -lPeinard"
