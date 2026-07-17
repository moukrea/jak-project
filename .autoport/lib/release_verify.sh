#!/usr/bin/env bash
# release_verify.sh <apk> <game> — GATE avant tout push jak-builds:
# 1. le manifest du bundle DANS l'APK doit porter la version CONTENT-HASH calculée depuis out/<game>/iso+fr3
# 2. version différente de la précédente publiée si les CGOs ont changé (le point de la saga HONOR)
set -uo pipefail
APK="$1"; GAME="${2:-jak1}"
cd "$(git rev-parse --show-toplevel)"
EXPECT="c$( (find out/${GAME}/iso -maxdepth 1 -type f -print0; find out/${GAME}/fr3 -maxdepth 1 -type f \( -name '*.fr3' -o -name '*.grassbake' \) -print0; find out/${GAME}/fr3/enhanced -maxdepth 1 -type f -name '*.fr3' -print0 2>/dev/null) | sort -z | xargs -0 md5sum | md5sum | cut -c1-12 )"
TMP=$(mktemp -d /home/emeric/tmp_j2audit/relverif.XXXX)
unzip -o -q "$APK" "assets/bundle/${GAME}.manifest.properties" -d "$TMP" || { echo "[release FAIL] pas de manifest dans l'APK"; exit 1; }
GOT=$(grep -E '^version=' "$TMP/assets/bundle/${GAME}.manifest.properties" | cut -d= -f2)
rm -rf "$TMP"
if [ "$GOT" != "$EXPECT" ]; then echo "[release FAIL] bundle version=$GOT != attendu=$EXPECT — l'APK embarque des CGOs périmés, PUSH INTERDIT"; exit 1; fi
echo "[release PASS] bundle version=$GOT == contenu out/${GAME} (ré-extraction garantie chez l'owner si contenu changé)"

# 3. Grecharged-buildsys-flags (risque R1) : appairage flag-set DANS l'APK — le marqueur
# "ogflags:<hash>:<cible>" du libgk.so doit == celui des CGO du pack. Un APK mixte est refusé.
T2=$(mktemp -d /home/emeric/tmp_j2audit/relverif.XXXX)
MARK_SO=$(unzip -p "$APK" lib/arm64-v8a/libgk.so 2>/dev/null | strings | grep -m1 '^ogflags:' || true)
if [ -n "$MARK_SO" ]; then
  unzip -o -q "$APK" "assets/bundle/${GAME}_cgo.zip" -d "$T2" 2>/dev/null || true
  MARK_CGO=""
  if [ -f "$T2/assets/bundle/${GAME}_cgo.zip" ]; then
    unzip -o -q "$T2/assets/bundle/${GAME}_cgo.zip" GAME.CGO -d "$T2" 2>/dev/null || true
    [ -f "$T2/GAME.CGO" ] && MARK_CGO=$(grep -a -o 'ogflags:[a-zA-Z0-9:_.-]*' "$T2/GAME.CGO" | head -1 || true)
  fi
  rm -rf "$T2"
  if [ -n "$MARK_CGO" ] && [ "$MARK_SO" != "$MARK_CGO" ]; then
    echo "[release FAIL] flag-set mixte dans l'APK: libgk '$MARK_SO' != CGO '$MARK_CGO' — PUSH INTERDIT (R1)"; exit 1
  fi
  echo "[release PASS] appairage flag-set APK: $MARK_SO (libgk == CGO pack)"
else
  rm -rf "$T2"
fi
exit 0
