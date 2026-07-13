#!/usr/bin/env bash
# release_verify.sh <apk> <game> — GATE avant tout push jak-builds:
# 1. le manifest du bundle DANS l'APK doit porter la version CONTENT-HASH calculée depuis out/<game>/iso+fr3
# 2. version différente de la précédente publiée si les CGOs ont changé (le point de la saga HONOR)
set -uo pipefail
APK="$1"; GAME="${2:-jak1}"
cd "$(git rev-parse --show-toplevel)"
EXPECT="c$( (find out/${GAME}/iso -maxdepth 1 -type f -print0; find out/${GAME}/fr3 -maxdepth 1 -type f \( -name '*.fr3' -o -name '*.grassbake' \) -print0) | sort -z | xargs -0 md5sum | md5sum | cut -c1-12 )"
TMP=$(mktemp -d /home/emeric/tmp_j2audit/relverif.XXXX)
unzip -o -q "$APK" "assets/bundle/${GAME}.manifest.properties" -d "$TMP" || { echo "[release FAIL] pas de manifest dans l'APK"; exit 1; }
GOT=$(grep -E '^version=' "$TMP/assets/bundle/${GAME}.manifest.properties" | cut -d= -f2)
rm -rf "$TMP"
if [ "$GOT" = "$EXPECT" ]; then echo "[release PASS] bundle version=$GOT == contenu out/${GAME} (ré-extraction garantie chez l'owner si contenu changé)"; exit 0
else echo "[release FAIL] bundle version=$GOT != attendu=$EXPECT — l'APK embarque des CGOs périmés, PUSH INTERDIT"; exit 1; fi
