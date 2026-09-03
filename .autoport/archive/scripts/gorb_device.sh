#!/usr/bin/env bash
# gorb_device.sh — Gorb-icon DEVICE capture (arm64 eae4df44).
#
# Warps to Geyser Rock gameplay (debug.opengoal.f1.warp=1) so the HUD orb (money
# merc model) draws, and captures the GORB-ICON-DIAG instrumentation:
#   GORB MODEL  — orb/fuel merc model texture refs (boot)
#   GORB LOAD   — orb-family texture source-avg + GL storage (rw/rh/glerr) at upload
#   GORB MERC   — orb-family textures actually BOUND by merc at draw (with handle)
# The decisive line is `GORB LOAD ... name=egg-ndimadman` (orb base texture):
#   x86 oracle = w=128 h=64 rw=128 rh=64 glerr=0x0 avg=149,50,35,47.
#
# Usage: gorb_device.sh <run_tag> [out_dir]
#   SKIP_BUILD=1  reuse already-built+deployed libgk
#   WATCH_S       seconds to watch in-game (default 150)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

RUN_TAG="${1:-run1}"
OUT_DIR="${2:-.autoport/reports/Gorb-icon}"
WATCH_S="${WATCH_S:-150}"
mkdir -p "$OUT_DIR"

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT_DIR/$RUN_TAG-logcat.log"
GORB="$OUT_DIR/$RUN_TAG-gorb.txt"

A() { "$ADB" -s "$SERIAL" "$@"; }
pkill -f 'logcat.*GK_STDOUT' 2>/dev/null || true

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "== build current-HEAD libgk.so =="
  bash .autoport/lib/d3_build.sh || { echo "FAIL: libgk build"; exit 1; }
  echo "== build SLIM jak1 debug APK (libgk-only) =="
  ( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 15 ) \
      || { echo "FAIL: gradle slim build failed"; exit 1; }
  [ -f "$APK" ] || { echo "FAIL: $APK not produced"; exit 1; }
  echo "== install + verify fresh HEAD libgk on device =="
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
  device_miui_unblock_install
  STAGE="/data/local/tmp/$(basename "$APK")"
  A push "$APK" "$STAGE" >/tmp/gorb-push.out 2>&1 || { cat /tmp/gorb-push.out; echo "FAIL: push"; exit 1; }
  A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gorb-pm.out 2>&1 || { cat /tmp/gorb-pm.out; echo "FAIL: pm install"; exit 1; }
  grep -q "Success" /tmp/gorb-pm.out || { cat /tmp/gorb-pm.out; echo "FAIL: pm install no Success"; exit 1; }
  A shell rm -f "$STAGE" >/dev/null 2>&1 || true
  bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL: deploy_verify"; exit 1; }
else
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
fi

echo "== open the title progress menu (draws the orb via do_hud_draws); tag=$RUN_TAG =="
INJECT="/data/data/$PACKAGE/files/cpad_inject"
inject() { printf '%s' "$1" | A shell "run-as $PACKAGE sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clear_inject() { inject ""; }
shot() { A shell screencap -p /sdcard/gorb-$1.png >/dev/null 2>&1 || true; A pull /sdcard/gorb-$1.png "$OUT_DIR/$RUN_TAG-shot-$1.png" >/dev/null 2>&1 || true; }
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
clear_inject
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c   >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime \
    opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V \
    libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGCAT_PID=$!
cleanup() {
  kill "$LOGCAT_PID" 2>/dev/null || true
  clear_inject
  A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
  device_stayon_restore 2>/dev/null || true
}
trap cleanup EXIT

# Warp to Geyser Rock, and arm the orb-HUD FX (spawns *money-sg* as a HUD object
# -> draw-bones-generic-merc, the owner's white-egg path).
A shell setprop debug.opengoal.f1.warp 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.gorb.fx 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.mouche.fx 0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.mouche.buzz 0 >/dev/null 2>&1 || true

A shell am start -W -n "$PACKAGE/$ACTIVITY" >/tmp/gorb-am.out 2>&1 || true
grep -q 'Error' /tmp/gorb-am.out && { cat /tmp/gorb-am.out; echo "FAIL: am start"; exit 1; }
# Record from boot so the window straddles the one-shot orb FX (~frame 540).
( A shell screenrecord --time-limit 150 --bit-rate 10000000 /sdcard/gorb-rec.mp4 >/dev/null 2>&1 & )

crash_seen() { grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG"; }
focus_is_app() { A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PACKAGE"; }
max_frame() { grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
n_fire() { grep -acaE 'MOUCHE-FIRE #' "$LOG" 2>/dev/null || echo 0; }
n_orbhud() { grep -acaE 'GORB HUD' "$LOG" 2>/dev/null || echo 0; }

echo "  warming to title (up to 150s)..."
for ((i=1;i<=50;i++)); do
  sleep 3
  if crash_seen; then echo "   crash during boot"; break; fi
  grep -qa "link finish: logo" "$LOG" && { echo "   title ~$((i*3))s"; break; }
done
echo "  waiting for warp + training (Geyser) load (up to 8min)..."
for ((i=1;i<=96;i++)); do
  sleep 5
  if grep -qaE "Adding level training|link finish: training-vis" "$LOG"; then echo "   >>> training active ~$((i*5))s"; break; fi
  if crash_seen; then echo "   >>> crash before training"; break; fi
  (( i % 6 == 0 )) && echo "   [load ${i}/96] waiting..."
done

echo "  watching ${WATCH_S}s for orb-HUD FX (MOUCHE-FIRE) + GORB HUD draw..."
for ((s=0; s<WATCH_S; s+=5)); do
  sleep 5
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  FM=$(max_frame); FM=${FM:-0}; NF=$(n_fire); NH=$(n_orbhud)
  (( s % 15 == 0 )) && echo "   [${s}/${WATCH_S}s] frame=$FM fx_fires=$NF gorb_hud=$NH focus=$(focus_is_app && echo yes || echo no)"
  if crash_seen; then echo "   >>> CRASH"; shot crash; break; fi
  [ "$s" -le 8 ] && shot "early$s"
  [ "$s" -eq 20 ] && shot 01
  [ "$s" -eq 40 ] && shot 02
  [ "$s" -eq 60 ] && shot 03
done
shot 04

# Pull the screen recording and extract frames (catch the one-shot orb FX).
A shell pkill -INT screenrecord >/dev/null 2>&1 || true
sleep 3
A pull /sdcard/gorb-rec.mp4 "$OUT_DIR/$RUN_TAG-rec.mp4" >/dev/null 2>&1 || true
if [ -f "$OUT_DIR/$RUN_TAG-rec.mp4" ] && command -v ffmpeg >/dev/null 2>&1; then
  rm -f "$OUT_DIR/$RUN_TAG-frame"*.png 2>/dev/null || true
  ffmpeg -y -i "$OUT_DIR/$RUN_TAG-rec.mp4" -vf fps=4 "$OUT_DIR/$RUN_TAG-frame%03d.png" >/dev/null 2>&1 || true
  echo "  extracted $(ls "$OUT_DIR/$RUN_TAG-frame"*.png 2>/dev/null | wc -l) frames from the recording"
fi

# Harvest GORB lines.
{
  echo "===== GORB HUD (the HUD/menu orb DRAW via Generic2 do_hud_draws — DECISIVE) ====="
  grep -aE 'GORB HUD' "$LOG" | sort -u
  echo "===== GORB MODEL (boot) ====="
  grep -aE 'GORB MODEL' "$LOG" | sort -u
  echo "===== GORB LOAD egg-ndimadman (orb base texture upload state) ====="
  grep -aE 'GORB LOAD' "$LOG" | grep -aF egg-ndimadman | sort -u
  echo "===== GORB LOAD fuel-cell controls (render FINE — contrast) ====="
  grep -aE 'GORB LOAD' "$LOG" | grep -aiE 'fuel-cell-endcaps|cmn-precursor-metal-plain-01small|fuel-cell-inside' | sort -u
  echo "===== GORB MERC (orb-family bound at draw via Merc2 world path) ====="
  grep -aE 'GORB MERC' "$LOG" | sort -u
  echo "===== generic2 / texture-pool MISS warnings ====="
  grep -aE 'Failed to find texture .*generic2|Failed to find texture' "$LOG" | sort -u | head
  echo "===== render / status ====="
  echo "max_frame=$(max_frame)"
  echo "focus_app=$(focus_is_app && echo yes || echo no)"
  echo "crash=$(crash_seen && echo YES || echo no)"
  echo "sig=$(grep -aoE 'GK-DIAG sig=[0-9]+|signal (11|6|4) \(SIG[A-Z]+' "$LOG" | tail -1)"
} | tee "$GORB"

kill "$LOGCAT_PID" 2>/dev/null || true
trap - EXIT
A shell setprop debug.opengoal.f1.warp 0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.gorb.fx 0 >/dev/null 2>&1 || true
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
device_stayon_restore 2>/dev/null || true
echo "== gorb_device.sh $RUN_TAG done; GORB -> $GORB =="
exit 0
