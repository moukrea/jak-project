#!/usr/bin/env bash
# Gcutscene-npc-flicker — LE RECENSEMENT DES PNJ SUR L'APPAREIL (Redmi eae4df44).
#
# POURQUOI L'APPAREIL. L'owner voit le defaut sur SON telephone. Les courses x86 de ce cycle
# rendent zero cycle de cause defectueuse sur trois cinematiques ; une mesure prise sur une
# machine ou le defaut n'apparait pas ne prouve rien sur celle ou il apparait. La capture est
# STREAMEE depuis le lancement (jamais `logcat -t N` : la fenetre serait fausse, pas le cablage)
# et on publie le nombre de lignes capturees a cote du compte.
#
# usage : npcf_device_run.sh <continue-point> <duree_s> <hd 0|1> [tag]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
[ -x "$ADB" ] || ADB=$(command -v adb)
SER=eae4df44
PKG=org.opengoal.gk.jak1
SCENE="${1:-intro-start}"; DUR="${2:-200}"; HD="${3:-1}"; TAG="${4:-$SCENE-hd$HD}"
INJECT="${5:-}"   # "<fragment>:<periode>:<duree>" — controle positif SUR L'APPAREIL
OUT=.autoport/reports/Gcutscene-npc-flicker/device; mkdir -p "$OUT"
LOG="$OUT/dev-$TAG-logcat.txt"; SUM="$OUT/dev-$TAG-resume.txt"
a(){ "$ADB" -s "$SER" "$@"; }
exec > >(tee "$SUM") 2>&1

cleanup(){
  a shell "setprop debug.opengoal.level.warp ''"      >/dev/null 2>&1
  a shell "setprop debug.opengoal.cpad_inject ''"     >/dev/null 2>&1
  a shell "setprop debug.opengoal.npcf.inject ''"     >/dev/null 2>&1
  [ -n "${LCPID:-}" ] && { kill "$LCPID" 2>/dev/null; sleep 1; kill -9 "$LCPID" 2>/dev/null; }
  for _p in $(pgrep -f "${SER} logcat" 2>/dev/null); do kill -9 "$_p" 2>/dev/null; done
  # On ARRETE le jeu en sortant : sinon l'auto-constructeur voit l'application au premier plan et
  # refuse d'installer pendant 1500 s — une campagne qui ne nettoie pas bloque la livraison.
  a shell am force-stop $PKG >/dev/null 2>&1
  return 0
}
trap cleanup EXIT

a devices | grep -qE "^${SER}[[:space:]]+device$" || { echo "FAIL: $SER absent"; exit 1; }
echo "===== appareil $SER — scene=$SCENE hd=$HD duree=${DUR}s — $(date -Is) ====="
echo "-- fraicheur de l'installation"
a shell dumpsys package $PKG 2>/dev/null | grep -E "lastUpdateTime|versionName" | head -2 | tr -d '\r'
echo "   pack custom telephone : $(a exec-out run-as $PKG cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r')"
echo "   pack cgo    telephone : $(a exec-out run-as $PKG cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r')"
echo "   pack cgo    arbre     : $(grep '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)"
# LE RECENSEMENT EST-IL DANS LE MOTEUR LIVRE ? Un `.so` perime rendrait zero ligne, ce qui se
# lirait comme « pas de defaut ». Les bibliotheques natives ne sont pas extraites sur cet appareil
# (extractNativeLibs=false : elles restent dans l'APK), donc on lit l'APK LIVRE, pas le repertoire
# de donnees — et on croise avec l'heure d'installation ci-dessus.
APK=$(ls -t out/artifacts/*jak1*.apk android/app/build/outputs/apk/jak1/debug/*.apk 2>/dev/null | head -1)
if [ -n "$APK" ]; then
  N=$(unzip -p "$APK" 'lib/arm64-v8a/libgk.so' 2>/dev/null | grep -ac NPCFLICK || true)
  echo "   marqueur NPCFLICK dans $APK : $N"
else
  echo "   APK introuvable — la preuve de presence sera les lignes NPCFLICK elles-memes"
fi

SET=/storage/emulated/0/OpenGOAL/jak1/settings.ini
a shell cat "$SET" > /tmp/npcf_settings.ini 2>/dev/null
cp -f /tmp/npcf_settings.ini "$OUT/.settings.pre-$TAG.ini" 2>/dev/null || true
val=$([ "$HD" = 1 ] && echo '#t' || echo '#f')
if grep -q '^recharged-enhanced-models? = ' /tmp/npcf_settings.ini; then
  sed -i "s|^recharged-enhanced-models? = .*|recharged-enhanced-models? = $val|" /tmp/npcf_settings.ini
else
  echo "FAIL: pas de cle recharged-enhanced-models? dans les reglages de l'appareil"; exit 1
fi
a push /tmp/npcf_settings.ini "$SET" >/dev/null 2>&1
echo "-- reglage pose : recharged-enhanced-models? = $val"

a shell am force-stop $PKG >/dev/null 2>&1
a shell "setprop debug.opengoal.level.warp '$SCENE'" >/dev/null 2>&1
a shell "setprop debug.opengoal.npcf.inject '$INJECT'" >/dev/null 2>&1
[ -n "$INJECT" ] && echo "-- CONTROLE POSITIF arme sur l'appareil : $INJECT"
a logcat -c >/dev/null 2>&1
a logcat > "$LOG" 2>/dev/null &
LCPID=$!
a shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
# On attend le MARQUEUR de warp au lieu d'un delai fixe : le telephone demarre plus lentement que
# le bureau, et une fenetre d'observation posee a l'aveugle mesurerait l'ecran de titre.
W=0
for i in $(seq 1 240); do
  grep -aq "LEVEL-WARP.*start .play" "$LOG" && { W=1; break; }
  sleep 1
done
if [ "$W" = 1 ]; then echo "-- warp parti, observation ${DUR}s"; else echo "-- AUCUN warp vu en 240s — on publie quand meme ce qui est sorti"; fi
sleep "$DUR"
kill "$LCPID" 2>/dev/null; sleep 1

CAP=$(grep -ac . "$LOG" || true)
echo "-- lignes capturees : $CAP"
echo "-- NPCSCENE : $(grep -ac 'NPCSCENE ' "$LOG" || true)   NPCFLICK : $(grep -ac 'NPCFLICK ' "$LOG" || true)   evenements : $(grep -ac 'NPCFLICK-EV ' "$LOG" || true)"
grep -a 'NPCSCENE \|NPCFLICK \|NPCFLICK-EV \|NPCFLICK-LONG ' "$LOG" | sed 's/^.*NPC/NPC/' | tail -60
echo "-- injection : $(grep -ac 'NPCF-INJECT arme' "$LOG" || true) ligne(s) d'armement"
echo "-- miroir HD : $(grep -ac 'JAK-HD\] mirror' "$LOG" || true) transitions   noanim-run : $(grep -ac 'noanim-run' "$LOG" || true)"
grep -a 'JAK-HD\] noanim-run' "$LOG" | sed 's/^.*\[JAK-HD\]/[JAK-HD]/' | sort | uniq -c | sort -rn | head -20
grep -a 'hd-flicker\] calls=' "$LOG" | tail -2
echo "===== fin — $(date -Is) ====="
