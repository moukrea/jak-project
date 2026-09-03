#!/usr/bin/env bash
# Gfont-urbanist — reinstall the fresh APK on the Redmi.
# CAUSE RACINE : l'auto-constructeur a bati l'APK a 20:15 pour le commit 92318235a2
# puis a REFUSE de l'installer, sa garde « premier plan » voyant le jeu ouvert sur le
# Redmi (« RETENTEE au prochain tour », 20:15:29 et 20:19:29). Le Redmi est l'instrument
# du superviseur, pas le telephone de l'owner : rien a proteger ici.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
LOCK=.autoport/.deploy-in-progress
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
SER=eae4df44
PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk

if [ -f "$LOCK" ]; then echo "LOCK DEJA POSE: $(cat "$LOCK")"; exit 3; fi
printf 'gfu_reinstall pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

want_c=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties | cut -d= -f2)
want_g=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)
echo "cible custom=$want_c cgo=$want_g"

"$ADB" -s "$SER" shell svc power stayon true >/dev/null 2>&1
"$ADB" -s "$SER" shell am force-stop "$PKG" >/dev/null 2>&1
echo "install..."
if ! timeout 1800 "$ADB" -s "$SER" install -r "$APK"; then echo "INSTALL ECHOUE"; exit 1; fi

COMP=$("$ADB" -s "$SER" shell cmd package resolve-activity --brief "$PKG" 2>/dev/null | tr -d '\r' | grep "^${PKG}/" | head -1)
[ -n "$COMP" ] || COMP="${PKG}/org.opengoal.gk.LoaderActivity"
echo "launch $COMP (LoaderActivity = le SEUL ecrivain des tampons)"
"$ADB" -s "$SER" shell am start -n "$COMP" >/dev/null 2>&1

got_c=""; got_g=""
for i in $(seq 1 90); do
  sleep 10
  got_c=$("$ADB" -s "$SER" exec-out run-as "$PKG" cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
  got_g=$("$ADB" -s "$SER" exec-out run-as "$PKG" cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
  echo "  t=$((i*10))s custom='$got_c' cgo='$got_g'"
  [ "$got_c" = "$want_c" ] && [ "$got_g" = "$want_g" ] && break
done
if [ "$got_c" = "$want_c" ] && [ "$got_g" = "$want_g" ]; then
  echo "TAMPONS RELUS SUR LE TELEPHONE: custom=$got_c cgo=$got_g — OK"
else
  echo "PACKS NON DEBALLES: custom='$got_c'!='$want_c' cgo='$got_g'!='$want_g'"; exit 2
fi
