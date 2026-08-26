#!/usr/bin/env bash
# Saisir la premiere fenetre ou la Shield repond pour reinstaller l'APK courant et
# reverifier. L'appareil bat de l'aile (il tombe et revient) : on sonde serre.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; S=192.168.1.32:5555; PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
LOCK=.autoport/.deploy-in-progress
printf 'gmam_grab_window pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
exec > >(tee -a .autoport/logs/gmam-grab-window.log) 2>&1
say(){ echo "[$(date +%T)] $*"; }
WANT=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties | cut -d= -f2)
say "chasse a la fenetre — pack attendu $WANT"
for try in 1 2 3 4 5 6; do
  for i in $(seq 1 40); do
    ping -c 1 -W 2 192.168.1.32 >/dev/null 2>&1 || { sleep 15; continue; }
    "$ADB" disconnect $S >/dev/null 2>&1; sleep 1; "$ADB" connect $S >/dev/null 2>&1; sleep 2
    [ "$(timeout 15 "$ADB" -s $S shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
    sleep 15
  done
  [ "$(timeout 15 "$ADB" -s $S shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] || { say "tentative $try : pas de fenetre"; continue; }
  say "tentative $try : fenetre ouverte, install"
  timeout 420 "$ADB" -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2
  timeout 20 "$ADB" -s $S shell am force-stop $PKG >/dev/null 2>&1
  timeout 20 "$ADB" -s $S shell logcat -c >/dev/null 2>&1
  timeout 20 "$ADB" -s $S shell am start -n $PKG/org.opengoal.gk.LoaderActivity >/dev/null 2>&1
  for i in $(seq 1 25); do
    sleep 6
    ST=$(timeout 15 "$ADB" -s $S exec-out run-as $PKG cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r\n' || true)
    M=$(timeout 15 "$ADB" -s $S shell logcat -d -s opengoal-gk 2>/dev/null | grep -cE 'master-mode=game' || echo 0)
    [ $((i % 3)) -eq 0 ] && say "   stamp='${ST:-vide}' master=$M"
    if [ "$ST" = "$WANT" ] && [ "${M:-0}" -gt 0 ]; then
      say "PACK A JOUR + master-mode=game"
      timeout 900 bash .autoport/lib/deploy_verify.sh $S jak1 && { say "DEPLOY-VERIFY PASS"; exit 0; }
      say "deploy_verify a echoue"; break
    fi
  done
  say "tentative $try infructueuse"
done
say "ABANDON — la Shield n'a pas offert de fenetre exploitable"
exit 2
