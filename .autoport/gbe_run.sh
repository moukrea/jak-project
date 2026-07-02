#!/usr/bin/env bash
# Phase Gcrash-blueeco — Forbidden Jungle blue-eco vent crash repro/verify driver.
#
# Warps Jak DIRECTLY to the jungle blue-eco vent using the level-warp continue
# override (debug.opengoal.level.warp=jungle-start) + the NEW spawn-position
# override (debug.opengoal.level.warp.pos="x y z" meters, patches the continue's
# trans before (start 'play ...)). Default position = ecovent-193 at
# (341.98, 55.50, -218.48) m from decompiler_out/jak1/entities/jungle-actors.json.
#
# Usage: gbe_run.sh <run_tag> [out_dir]
#   SKIP_BUILD=1      reuse the already-built+deployed libgk
#   GBE_POS="x y z"   spawn position override in meters (default: at ecovent-193)
#   GBE_SETTLE=30     seconds to stand still at the vent before wiggle taps
#   GBE_OBSERVE=90    seconds to observe past the trigger (crash-capture-window)
#
# Produces under <out_dir> (default .autoport/reports/Gcrash-blueeco):
#   <tag>-logcat.log   full run logcat (-b all, threadtime)
#   <tag>-result.txt   one-line structured verdict
#   <tag>-snap-*.png   screencaps (validity requires focus_app=yes)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

RUN_TAG="${1:-run1}"
OUT_DIR="${2:-.autoport/reports/Gcrash-blueeco}"
mkdir -p "$OUT_DIR"

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
POS="${GBE_POS:-354.15 57.5 -213.95}"  # 1.8m above ecovent-@(354.15,55.67,-213.95); ventblue alt=455.06 18.5 -292.86
SETTLE="${GBE_SETTLE:-30}"
OBSERVE="${GBE_OBSERVE:-90}"
LOG="$OUT_DIR/$RUN_TAG-logcat.log"
RESULT="$OUT_DIR/$RUN_TAG-result.txt"

A() { "$ADB" -s "$SERIAL" "$@"; }
inject() { A shell "setprop debug.opengoal.cpad_inject '$1'" >/dev/null 2>&1 || true; }
clear_inject() { A shell "setprop debug.opengoal.cpad_inject '\"\"'" >/dev/null 2>&1 || true; }

pkill -f "logcat.*$SERIAL" 2>/dev/null || true

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "== build current-HEAD libgk.so =="
  bash .autoport/lib/d3_build.sh || { echo "FAIL: d3_build"; exit 1; }
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
  A push "$APK" "$STAGE" >/tmp/gbe-push.out 2>&1 || { cat /tmp/gbe-push.out; echo "FAIL: push"; exit 1; }
  A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gbe-pm.out 2>&1 || { cat /tmp/gbe-pm.out; echo "FAIL: pm install"; exit 1; }
  grep -q "Success" /tmp/gbe-pm.out || { cat /tmp/gbe-pm.out; echo "FAIL: pm install no Success"; exit 1; }
  A shell rm -f "$STAGE" >/dev/null 2>&1 || true
  bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL: deploy_verify"; exit 1; }
  # The slim APK ships manifest version=2 but NO jak1_assets.zip. If the device's
  # .asset_bundle_stamp != 2, LoaderActivity.unpackBundleIfNeeded WIPES
  # files/iso_data/jak1 + files/out/jak1/fr3 then fails to re-unpack (no zip) ->
  # boot aborts. So restore the KNOWN-GOOD arm64 CGO/DGO set (NOT host out/jak1/iso,
  # which is the x86 gold set: GAME.CGO 8.7MB vs arm64 11.9MB) + fr3 textures, and
  # stamp the device to the slim manifest version so the boot fast-path skips unpack.
  echo "== restore arm64 data set under test + stamp (slim-APK data-wipe guard) =="
  ASSET_SRC="${ASSET_SRC:-.autoport/backups/jungle-arm64-bothfixes}"
  SLIM_VER="${SLIM_VER:-2}"
  A shell run-as "$PACKAGE" mkdir -p files/iso_data/jak1 files/out/jak1/fr3 >/dev/null 2>&1 || true
  for f in "$ASSET_SRC"/*.CGO "$ASSET_SRC"/*.DGO; do
    n=$(basename "$f")
    A push "$f" "/data/local/tmp/$n" >/dev/null 2>&1 && \
      A shell run-as "$PACKAGE" cp "/data/local/tmp/$n" "files/iso_data/jak1/$n" >/dev/null 2>&1
    A shell rm -f "/data/local/tmp/$n" >/dev/null 2>&1 || true
  done
  for f in out/jak1/fr3/*.fr3; do
    n=$(basename "$f")
    A push "$f" "/data/local/tmp/$n" >/dev/null 2>&1 && \
      A shell run-as "$PACKAGE" cp "/data/local/tmp/$n" "files/out/jak1/fr3/$n" >/dev/null 2>&1
    A shell rm -f "/data/local/tmp/$n" >/dev/null 2>&1 || true
  done
  A shell "run-as $PACKAGE sh -c 'printf $SLIM_VER > files/.asset_bundle_stamp'" >/dev/null 2>&1 || true
  echo "   restored $(A shell run-as "$PACKAGE" ls files/iso_data/jak1/ 2>/dev/null | tr -d '\r' | wc -l) iso files, $(A shell run-as "$PACKAGE" ls files/out/jak1/fr3/ 2>/dev/null | tr -d '\r' | wc -l) fr3; stamp=$(A shell run-as "$PACKAGE" cat files/.asset_bundle_stamp 2>/dev/null | tr -d '\r')"
else
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
fi

echo "== arm jungle warp + pos override + census; tag=$RUN_TAG pos='$POS' =="
A shell setprop debug.opengoal.f1.census 1 >/dev/null 2>&1 || true
A shell "setprop debug.opengoal.f1.warp '\"\"'" >/dev/null 2>&1 || true
A shell setprop debug.opengoal.level.warp jungle-start >/dev/null 2>&1 || true
A shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1 || true
clear_inject

A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -b all -c >/dev/null 2>&1 || true
: > "$LOG"
A logcat -b all -v threadtime > "$LOG" 2>&1 &
LOGCAT_PID=$!
cleanup() {
  clear_inject
  kill "$LOGCAT_PID" 2>/dev/null || true
  A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
  A shell "setprop debug.opengoal.level.warp '\"\"'" >/dev/null 2>&1 || true
  A shell "setprop debug.opengoal.level.warp.pos '\"\"'" >/dev/null 2>&1 || true
  device_stayon_restore 2>/dev/null || true
}
trap cleanup EXIT

A shell am start -W -n "$PACKAGE/$ACTIVITY" >/tmp/gbe-am.out 2>&1 || true
grep -q 'Error' /tmp/gbe-am.out && { cat /tmp/gbe-am.out; echo "FAIL: am start"; exit 1; }

crash_seen() {
  grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG"
}
focus_is_app() {
  A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PACKAGE"
}
last_pos() { grep -a 'F1-STATE tx=' "$LOG" | tail -1 | grep -aoE 'tx=[-0-9.]+ ty=[-0-9.]+ tz=[-0-9.]+'; }
snap() {
  A shell screencap -p /sdcard/gbe.png >/dev/null 2>&1 || true
  A pull /sdcard/gbe.png "$OUT_DIR/$RUN_TAG-snap-$1.png" >/dev/null 2>&1 || true
}

echo "  warming to title (link finish: logo, up to 150s)..."
for i in $(seq 1 150); do grep -qa "link finish: logo" "$LOG" && { echo "  title ~${i}s"; break; }; sleep 1; done

echo "  waiting for LEVEL-WARP-SPAWN (up to 120s)..."
WARP_OK=0
for i in $(seq 1 120); do
  grep -qa "LEVEL-WARP-SPAWN name=jungle-start" "$LOG" && { echo "  warp fired ~${i}s"; WARP_OK=1; break; }
  grep -qa "LEVEL-WARP-FAIL" "$LOG" && { echo "  >>> LEVEL-WARP-FAIL"; break; }
  crash_seen && { echo "  >>> crash before warp"; break; }
  sleep 1
done
grep -a "LEVEL-WARP-POS\|LEVEL-WARP-SPAWN\|pos override" "$LOG" | tail -5

if [ "$WARP_OK" = 1 ]; then
  echo "  waiting for jungle load + F1-STATE stream (up to 4min)..."
  JUNGLE_OK=0
  for ((i=1;i<=48;i++)); do
    sleep 5
    if grep -qaE "Adding level jungle|link finish: jungle-vis" "$LOG" && grep -qa 'F1-STATE tx=' "$LOG"; then
      echo "   >>> jungle loaded + target streaming ~$((i*5))s"; JUNGLE_OK=1; break
    fi
    crash_seen && { echo "   >>> crash during jungle load"; break; }
  done
  snap spawn
  echo "   spawn pos: $(last_pos)"

  if [ "$JUNGLE_OK" = 1 ] && ! crash_seen; then
    echo "== stand in the vent ${SETTLE}s (no input) =="
    clear_inject
    for ((i=1;i<=SETTLE;i++)); do sleep 1; crash_seen && { echo "   >>> CRASH during settle (${i}s)"; break; }; done
    snap settle
    if ! crash_seen; then
      echo "== gentle in-place wiggle taps (ensure vent touch) =="
      for w in 1 2 3 4 5 6; do
        inject "ly=100"; sleep 0.4
        inject "ly=154"; sleep 0.4
        clear_inject; sleep 0.7
        crash_seen && { echo "   >>> CRASH during wiggle $w"; break; }
      done
      snap wiggle
    fi
  fi
fi

echo "== observe ${OBSERVE}s past the trigger (crash-capture-window) =="
clear_inject
for ((i=1;i<=OBSERVE;i++)); do
  sleep 1
  if crash_seen && [ $((i % 15)) -eq 0 ]; then echo "   (crash seen; continuing capture ${i}/${OBSERVE}s)"; fi
done
snap end

SIG=$(grep -aoE 'GK-DIAG sig=[0-9]+[^"]*' "$LOG" | head -3)
FATAL=$(grep -aE 'Fatal signal' "$LOG" | head -2)
FOC="no"; focus_is_app && FOC="yes"
NF=$(grep -ac 'F1-STATE tx=' "$LOG" 2>/dev/null || echo 0)
echo "RESULT tag=$RUN_TAG warp=$WARP_OK sig='${SIG:-none}' fatal='${FATAL:-none}' focus_app=$FOC f1state=$NF pos='$(last_pos)'" | tee "$RESULT"
echo "log: $LOG"
