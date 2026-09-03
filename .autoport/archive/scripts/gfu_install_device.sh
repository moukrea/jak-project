#!/usr/bin/env bash
# gfu_install_device.sh — installe la paire coherente (APK + packs) sur le Redmi et
# ATTEND que LoaderActivity ait deballe, en citant les tampons RELUS sur le telephone.
# Convention de verrou obligatoire (DIRECTIVES 2026-08-14 07:10) : PID + trap.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44; P=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
LOCK=.autoport/.deploy-in-progress
if [ -f "$LOCK" ]; then echo "VERROU DEJA POSE: $(cat "$LOCK")"; exit 3; fi
printf 'gfu_install_device pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

want_c=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties | cut -d= -f2)
want_g=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)
echo "$(date +%T) cible custom=$want_c cgo=$want_g"

# Ecran eteint = am start bloque en TOP_SLEEPING (piege connu) : reveiller et VERIFIER.
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
W=$($ADB -s $S shell dumpsys power 2>/dev/null | grep -ao 'mWakefulness=[A-Za-z]*' | head -1)
echo "$(date +%T) $W"

$ADB -s $S shell am force-stop $P >/dev/null 2>&1
echo "$(date +%T) install..."
if ! timeout 1800 $ADB -s $S install -r "$APK"; then echo "ECHEC: adb install"; exit 1; fi

COMP=$($ADB -s $S shell cmd package resolve-activity --brief $P 2>/dev/null | tr -d '\r' | grep "^${P}/" | head -1)
[ -n "$COMP" ] || COMP="$P/org.opengoal.gk.LoaderActivity"
echo "$(date +%T) lancement $COMP (LoaderActivity deballe les packs)"
$ADB -s $S shell am start -n "$COMP" >/dev/null 2>&1

got_c=""; got_g=""
for i in $(seq 1 90); do
  sleep 10
  got_c=$($ADB -s $S exec-out run-as $P cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
  got_g=$($ADB -s $S exec-out run-as $P cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
  [ $((i % 6)) -eq 0 ] && echo "$(date +%T) [t+$((i*10))s] custom='$got_c' cgo='$got_g'"
  [ "$got_c" = "$want_c" ] && [ "$got_g" = "$want_g" ] && break
done
if [ "$got_c" = "$want_c" ] && [ "$got_g" = "$want_g" ]; then
  echo "$(date +%T) OK installe et deballe — tampons RELUS custom='$got_c' cgo='$got_g'"; exit 0
fi
echo "$(date +%T) ECHEC deballage: custom='$got_c'!='$want_c' cgo='$got_g'!='$want_g'"; exit 2
