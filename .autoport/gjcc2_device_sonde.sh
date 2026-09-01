#!/usr/bin/env bash
# Gjak1-crate-collision-2 — LA SONDE PROGRAMMATIQUE SUR L'APPAREIL (Redmi eae4df44).
#
# Correction de methode de l'owner (2026-09-01) : « fais ça de façon programmatique
# [...] impossible que tu couvre toutes les caisses de Geyser Rock à la vue ».
# Le niveau est charge NORMALEMENT (spawn autorise `f1.warp`), PERSONNE NE PILOTE, et
# la sonde interroge CHAQUE caisse par le code : sphere finie ? requete de collision
# synthetique -> contact ? Aucune image n'est regardee, aucun bouton n'est presse.
#
# usage : gjcc2_device_sonde.sh <tag> <mode> <fps> <duree_s> [forceactors]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
[ -x "$ADB" ] || ADB=$(command -v adb)
SER=eae4df44; PKG=org.opengoal.gk.jak1
TAG="${1:-p1}"; MODE="${2:-129}"; FPS="${3:-20}"; DUR="${4:-300}"; FORCE="${5:-1}"
OUT=.autoport/reports/Gjak1-crate-collision/device3; mkdir -p "$OUT"
LOG="$OUT/dev-$TAG-logcat.txt"; SUM="$OUT/dev-$TAG-resume.txt"
a(){ "$ADB" -s "$SER" "$@"; }
exec > >(tee "$SUM") 2>&1
cleanup(){
  a shell "setprop debug.opengoal.cpad_inject ''" >/dev/null 2>&1
  a shell "setprop debug.opengoal.f1.warp ''"     >/dev/null 2>&1
  [ -n "${LCPID:-}" ] && { kill "$LCPID" 2>/dev/null; sleep 1; kill -9 "$LCPID" 2>/dev/null; }
  for _p in $(pgrep -f "${SER} logcat" 2>/dev/null); do kill -9 "$_p" 2>/dev/null; done
  a shell am force-stop $PKG >/dev/null 2>&1
  return 0
}
trap cleanup EXIT
a devices | grep -qE "^${SER}[[:space:]]+device$" || { echo "FAIL: $SER absent"; exit 1; }

echo "== FRAICHEUR DE L'INSTALLATION =="
echo "  cgo pack telephone : $(a exec-out run-as $PKG cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r')"
echo "  la SONDE est-elle dans le GAME.CGO deploye ? GJCC-PROBESUM : $(a exec-out run-as $PKG sh -c "grep -c GJCC-PROBESUM files/cgo/jak1/GAME.CGO" 2>/dev/null | tr -d '\r')"
echo "  md5 GAME.CGO sur le telephone : $(a exec-out run-as $PKG md5sum files/cgo/jak1/GAME.CGO 2>/dev/null | tr -d '\r')"
echo "  md5 GAME.CGO arm64 dans l'arbre : $(md5sum out/jak1-arm64-full/iso/GAME.CGO 2>/dev/null)"

echo "== REGLAGES : gjcc=$MODE fps=$FPS force-actors=$FORCE =="
SET=/storage/emulated/0/OpenGOAL/jak1/settings.ini
a shell cat "$SET" > /tmp/gjcc2_sonde_settings.ini 2>/dev/null
# `gjcc`, `fps` et `force-actors?` sont tous les trois lus par le MEME groupe
# (`handle-input-settings`, pckernel-common.gc:857) : une cle posee dans un autre
# groupe serait ignoree en silence — un faux zero.
_put(){ if grep -q "^$1 *=" /tmp/gjcc2_sonde_settings.ini
        then sed -i "s/^$1 *=.*/$1 = $2/" /tmp/gjcc2_sonde_settings.ini
        else sed -i "0,/^fps *=/s//$1 = $2\nfps =/" /tmp/gjcc2_sonde_settings.ini; fi; }
_put gjcc "$MODE"
_put fps "$FPS"
[ "$FORCE" = "1" ] && _put "force-actors?" "#t"
grep -qE '^gjcc *=' /tmp/gjcc2_sonde_settings.ini || { echo "FAIL: cle gjcc non posee"; exit 1; }
a push /tmp/gjcc2_sonde_settings.ini /sdcard/gjcc2_sonde_settings.ini >/dev/null 2>&1
a shell "cp /sdcard/gjcc2_sonde_settings.ini $SET" >/dev/null 2>&1
echo "  relu : $(a shell "grep -E '^(gjcc|fps|force-actors)' $SET" 2>/dev/null | tr -d '\r' | paste -sd' ')"

echo "== DEMARRAGE (spawn autorise, aucun pilotage) =="
a shell am force-stop $PKG >/dev/null 2>&1
a shell "setprop debug.opengoal.cpad_inject ''" >/dev/null 2>&1
a shell "setprop debug.opengoal.f1.warp 1" >/dev/null 2>&1
a shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
a shell svc power stayon true >/dev/null 2>&1
a logcat -c >/dev/null 2>&1
a logcat -v threadtime > "$LOG" & LCPID=$!
sleep 1
a shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
ok=0
for i in $(seq 1 150); do sleep 2; grep -qa 'GJCC-MODE' "$LOG" && { echo "  GJCC-MODE vu a ~$((i*2))s"; ok=1; break; }; done
[ "$ok" = 1 ] || echo "  ATTENTION: pas de GJCC-MODE"
grep -a 'GJCC-MODE' "$LOG" | tail -1 | sed 's/.*GJCC-MODE/  GJCC-MODE/'

echo "== LE JEU TOURNE ${DUR}s SANS PILOTE — la sonde interroge les caisses =="
sleep "$DUR"
kill "$LCPID" 2>/dev/null; sleep 1

echo "== RESULTAT $TAG =="
echo "  lignes logcat : $(wc -l < "$LOG")"
echo "  passes de sonde : $(grep -ac 'GJCC-PROBESUM' "$LOG")"
grep -a 'GJCC-PROBESUM' "$LOG" | sed 's/^.*GJCC-PROBESUM/  GJCC-PROBESUM/'
echo "  --- caisses en echec (ok=0) ---"
grep -a 'GJCC-PROBE ' "$LOG" | grep 'ok=0' | sed 's/^.*GJCC-PROBE/  GJCC-PROBE/' | head -20
echo "  --- bw / incache ---"
grep -a 'GJCC-PROBE ' "$LOG" | grep -o 'bw=[^ ]*' | sort | uniq -c | sort -rn | head -5
grep -a 'GJCC-PROBE ' "$LOG" | grep -o 'incache=[0-9]*' | sort | uniq -c
echo "  cadence [dyn-rs] : $(grep -a 'dyn-rs.*avg-fps' "$LOG" | sed 's/.*avg-fps=\([0-9.]*\).*/\1/' | sort -n | awk '{v[NR]=$1} END{if(NR>0) printf "n=%d min=%s med=%s max=%s", NR, v[1], v[int((NR+1)/2)], v[NR]; else printf "n=0"}')"
echo "  plantages : Fatal=$(grep -ac 'Fatal signal' "$LOG")  ANR=$(grep -ac 'ANR in' "$LOG")"
echo "GJCC2-SONDE-DEV-DONE tag=$TAG mode=$MODE fps=$FPS force=$FORCE"
