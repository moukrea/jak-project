#!/usr/bin/env bash
# gmam_redeploy_race.sh — la appareil de test ne peut faire demarrer aucune application tant que
# son volume USB adopte est en `checking` (Zygote avorte au fork : voir §10c du rapport).
# Apres un redemarrage il existe une FENETRE — le volume n'est pas encore repris par vold
# — pendant laquelle tout marche. On redemarre et on tient la sequence complete dans
# cette fenetre : install, lancement (LoaderActivity depaquette), verification.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; S=eae4df44
PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
LOG=.autoport/logs/gmam-redeploy-race.log
LOCK=.autoport/.deploy-in-progress
printf 'gmam_redeploy_race pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
exec > >(tee -a "$LOG") 2>&1
say(){ echo "[$(date +%T)] $*"; }
WANT=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties | cut -d= -f2)
say "APK=$(stat -c %y "$APK" | cut -d. -f1)  pack attendu=$WANT  HEAD=$(git rev-parse --short HEAD)"

say "redemarrage"
"$ADB" -s $S reboot >/dev/null 2>&1 || true
sleep 40
for i in $(seq 1 20); do
  "$ADB" connect $S >/dev/null 2>&1
  [ "$("$ADB" -s $S shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && { say "boot_completed apres $((40+i*10))s"; break; }
  sleep 10
done
"$ADB" -s $S shell svc power stayon true >/dev/null 2>&1 || true
say "volume: $("$ADB" -s $S shell sm list-volumes all 2>/dev/null | grep ff091cb1 | tr -d '\r' || echo absent)"

say "install"
"$ADB" -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3
say "lancement"
"$ADB" -s $S shell am force-stop $PKG; "$ADB" -s $S shell logcat -c
"$ADB" -s $S shell am start -n $PKG/org.opengoal.gk.LoaderActivity >/dev/null 2>&1
for i in $(seq 1 30); do
  sleep 6
  ST=$("$ADB" -s $S exec-out run-as $PKG cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r\n' || true)
  M=$("$ADB" -s $S shell logcat -d -s opengoal-gk 2>/dev/null | grep -cE 'master-mode=game' || true)
  say "  [${i}] stamp='${ST:-vide}' master=$M vol=$("$ADB" -s $S shell sm list-volumes all 2>/dev/null | grep -o 'checking\|mounted ff' | head -1)"
  [ "$ST" = "$WANT" ] && [ "${M:-0}" -gt 0 ] && { say "PACK A JOUR + master-mode=game"; break; }
done
say "deploy_verify"
bash .autoport/lib/deploy_verify.sh $S jak1
say "RC=$?"
