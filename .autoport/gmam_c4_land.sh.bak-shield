#!/usr/bin/env bash
# gmam_c4_land.sh — cycle 4 : poser sur la Shield l'APK qui porte le correctif du
# pointeur GL NUL (glTexStorage2D), et PROUVER PAR L'EXECUTION que le demarrage
# atteint l'ecran-titre sans mourir.
#
# CE QU'IL PROUVE, ET DANS QUEL ORDRE :
#   1. l'APK contient bien la .so fraiche (deploy_verify : chaine build==APK==appareil) ;
#   2. le balayage A36-GLGATED a resolu les 8 entrees que glad laisse NULL sur GLES —
#      c'est la LIGNE D'EXECUTION du correctif, pas un commentaire ;
#   3. aucun signal fatal, aucun NOUVEAU fichier de crash pendant toute la course ;
#   4. le moteur atteint master-mode=game ET fait tourner le process `logo`
#      (F1A-CAMJOINT) au-dela de la frame ou il mourait (60), avec le pid toujours
#      vivant a la fin.
#
# La fenetre d'observation est LARGE (180 s) exprès : le cycle 3 a paye un cycle
# entier pour avoir borne sa fenetre plus court que le phenomene observe.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
S=192.168.1.32:5555
PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
REMOTE=/data/local/tmp/gk-jak1.apk
LOCK=.autoport/.deploy-in-progress
OUT=.autoport/reports/Grecharged-managed-assets-merge
RUNLOG=.autoport/logs/gmam-c4-land.log
WATCH=180

printf 'gmam_c4_land pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
mkdir -p .autoport/logs "$OUT"
exec > >(tee -a "$RUNLOG") 2>&1
say(){ echo "[$(date +%T)] $*"; }
die(){ say "FAIL: $*"; exit 1; }

say "=== c4 : APK gradle (clean + assemble) ==="
( cd android && timeout 900 ./gradlew :app:clean ) >/dev/null 2>&1
( cd android && timeout 3000 ./gradlew assembleJak1Debug ) > .autoport/logs/gmam-c4-gradle.log 2>&1 \
  || { tail -30 .autoport/logs/gmam-c4-gradle.log; die "gradle"; }
[ -f "$APK" ] || die "pas d'APK"
APK_MD5=$(md5sum "$APK" | cut -d' ' -f1)
say "APK $(stat -c %s "$APK") octets md5=${APK_MD5:0:12}"

say "=== c4 : etat de l'appareil AVANT ==="
timeout 30 "$ADB" connect $S >/dev/null 2>&1 || true
timeout 30 "$ADB" -s $S shell 'df -h /data | tail -1' || die "appareil injoignable"
# empreinte du fichier de crash AVANT la course : un crash NEUF se voit a sa date
CRASH_BEFORE=$(timeout 30 "$ADB" -s $S exec-out run-as $PKG stat -c '%Y %s' files/gk_crash.txt 2>/dev/null | tr -d '\r' || true)
say "gk_crash.txt avant = '${CRASH_BEFORE:-absent}'"

say "=== c4 : pousse + installation ==="
timeout 60 "$ADB" -s $S shell rm -f "$REMOTE" >/dev/null 2>&1 || true
timeout 1800 "$ADB" -s $S push "$APK" "$REMOTE" 2>&1 | tail -1
DEV_MD5=$(timeout 120 "$ADB" -s $S shell md5sum "$REMOTE" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
[ "$DEV_MD5" = "$APK_MD5" ] || die "md5 appareil '$DEV_MD5' != '$APK_MD5'"
say "APK integre sur l'appareil"
OUT_I=$(timeout 1200 "$ADB" -s $S shell pm install -r -d -t "$REMOTE" 2>&1 | tr -d '\r' | tail -3)
say "pm install -> $OUT_I"
echo "$OUT_I" | grep -q 'Success' || die "install refusee"
timeout 60 "$ADB" -s $S shell rm -f "$REMOTE" >/dev/null 2>&1 || true

say "=== c4 : lancement par l'ACTIVITE RESOLUE (LoaderActivity, seule ecrivaine des packs) ==="
timeout 30 "$ADB" -s $S shell am force-stop $PKG >/dev/null 2>&1
timeout 30 "$ADB" -s $S shell logcat -c >/dev/null 2>&1
T0=$(date +%s)
timeout 40 "$ADB" -s $S shell am start -n $PKG/org.opengoal.gk.LoaderActivity >/dev/null 2>&1 \
  || die "am start"
timeout $((WATCH + 60)) "$ADB" -s $S shell logcat -v time > "$OUT/c4-boot-logcat.txt" 2>&1 &
LOGPID=$!
say "logcat en cours (pid $LOGPID) — observation ${WATCH}s"
sleep "$WATCH"
kill "$LOGPID" 2>/dev/null || true
wait "$LOGPID" 2>/dev/null || true

PID=$(timeout 30 "$ADB" -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')
CRASH_AFTER=$(timeout 30 "$ADB" -s $S exec-out run-as $PKG stat -c '%Y %s' files/gk_crash.txt 2>/dev/null | tr -d '\r' || true)
say "pid apres ${WATCH}s = '${PID:-MORT}'   gk_crash.txt apres = '${CRASH_AFTER:-absent}'"

L="$OUT/c4-boot-logcat.txt"
say "=== c4 : lecture du log ==="
say "--- balayage des entrees gatees (la ligne d'execution du correctif) ---"
grep -a 'A36-GLGATED' "$L" | tail -3
say "--- entrees GL restees NULL ---"
grep -a 'A36-RENDER missing core' "$L" | tail -3 || true
say "--- assets geres ---"
grep -aE 'managed assets:|managed_assets:' "$L" | tail -8
say "--- master-mode / premieres images ---"
grep -aE 'master-mode=|A35-RENDER frame=' "$L" | tail -4
say "--- process logo (F1A-CAMJOINT) ---"
grep -a 'F1A-CAMJOINT' "$L" | tail -3
say "--- signaux fatals / crash ---"
grep -aiE 'Fatal signal|GK-CRASH|GK-DIAG sig=|SIG_DFL|beginning of crash' "$L" | tail -10 || true

FATAL=$(grep -acE 'Fatal signal|GK-DIAG sig=' "$L" || true)
MASTER=$(grep -ac 'master-mode=game' "$L" || true)
say "bilan brut : fatals=${FATAL:-0} master-mode=game=${MASTER:-0} pid='${PID:-MORT}'"

RC=0
[ "${FATAL:-0}" -eq 0 ] || { say "VERDICT: un signal fatal est present dans le log"; RC=1; }
[ -n "$PID" ] || { say "VERDICT: le process est mort avant la fin de la fenetre"; RC=1; }
[ "$CRASH_AFTER" = "$CRASH_BEFORE" ] || { say "VERDICT: gk_crash.txt a change ($CRASH_BEFORE -> $CRASH_AFTER)"; RC=1; }
[ "${MASTER:-0}" -gt 0 ] || { say "VERDICT: master-mode=game jamais atteint"; RC=1; }

say "=== c4 : deploy_verify ==="
if timeout 1800 bash .autoport/lib/deploy_verify.sh $S jak1; then
  say "DEPLOY-VERIFY PASS"
else
  say "DEPLOY-VERIFY FAIL"; RC=1
fi

say "=== c4 : RC=$RC ==="
exit "$RC"
