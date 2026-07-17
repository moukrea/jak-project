#!/usr/bin/env bash
# gjungle_device.sh — Forbidden Jungle (level 'jungle / JUN.DGO) load repro on the
# Redmi (arm64 eae4df44). Arms the JUNGLE-WARP hook (debug.opengoal.jungle.warp=1)
# which replays (start 'play (get-continue-by-name *game-info* "jungle-start"))
# on the GOAL kernel thread — the exact load-triggered path the owner hits crossing
# the village1->jungle bridge. Captures the crash signal + forensics, OR proves the
# jungle loads + renders crash-free for a sustained run.
#
# Usage: gjungle_device.sh <run_tag> [out_dir]
#   SKIP_BUILD=1   reuse the already-built+deployed libgk (skip build+install)
#   WATCH_S        seconds to observe AFTER the warp fires (default 180)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

RUN_TAG="${1:-run1}"
OUT_DIR="${2:-.autoport/reports/Gcrash-jungle}"
WATCH_S="${WATCH_S:-180}"
mkdir -p "$OUT_DIR"

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT_DIR/$RUN_TAG-logcat.log"
RESULT="$OUT_DIR/$RUN_TAG-result.txt"

A() { "$ADB" -s "$SERIAL" "$@"; }
pkill -f 'logcat.*GK_STDOUT' 2>/dev/null || true

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "== build current-HEAD libgk.so =="
  bash .autoport/lib/d3_build.sh || { echo "FAIL: libgk build"; exit 1; }
  echo "== build SLIM jak1 debug APK (libgk-only) =="
  ( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 12 ) \
      || { echo "FAIL: gradle slim build failed"; exit 1; }
  [ -f "$APK" ] || { echo "FAIL: $APK not produced"; exit 1; }
  echo "== install + verify fresh HEAD libgk on device =="
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
  device_miui_unblock_install
  STAGE="/data/local/tmp/$(basename "$APK")"
  A push "$APK" "$STAGE" >/tmp/gjun-push.out 2>&1 || { cat /tmp/gjun-push.out; echo "FAIL: push"; exit 1; }
  A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gjun-pm.out 2>&1 || { cat /tmp/gjun-pm.out; echo "FAIL: pm install"; exit 1; }
  grep -q "Success" /tmp/gjun-pm.out || { cat /tmp/gjun-pm.out; echo "FAIL: pm install no Success"; exit 1; }
  A shell rm -f "$STAGE" >/dev/null 2>&1 || true
  bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL: deploy_verify"; exit 1; }
  # The slim APK ships manifest version=2 but NO jak1_assets.zip. If the device's
  # .asset_bundle_stamp != 2, LoaderActivity.unpackBundleIfNeeded WIPES
  # files/cgo/jak1 + files/out/jak1/fr3 then fails to re-unpack (no zip) ->
  # "asset setup failed" -> boot aborts. So: restore the asset set under test
  # (CGO/DGO from $ASSET_SRC, fr3 textures from out/jak1/fr3) and stamp the device
  # to the slim manifest version so the boot fast-path skips decompress.
  echo "== restore data set under test + stamp (slim-APK data-wipe guard) =="
  ASSET_SRC="${ASSET_SRC:-.autoport/backups/jungle-arm64-withfix}"
  A shell run-as "$PACKAGE" mkdir -p files/cgo/jak1 files/out/jak1/fr3 >/dev/null 2>&1 || true
  for f in "$ASSET_SRC"/*.CGO "$ASSET_SRC"/*.DGO; do
    n=$(basename "$f")
    A push "$f" "/data/local/tmp/$n" >/dev/null 2>&1 && \
      A shell run-as "$PACKAGE" cp "/data/local/tmp/$n" "files/cgo/jak1/$n" >/dev/null 2>&1
    A shell rm -f "/data/local/tmp/$n" >/dev/null 2>&1 || true
  done
  for f in out/jak1/fr3/*.fr3; do
    n=$(basename "$f")
    A push "$f" "/data/local/tmp/$n" >/dev/null 2>&1 && \
      A shell run-as "$PACKAGE" cp "/data/local/tmp/$n" "files/out/jak1/fr3/$n" >/dev/null 2>&1
    A shell rm -f "/data/local/tmp/$n" >/dev/null 2>&1 || true
  done
  A shell "run-as $PACKAGE sh -c 'printf 2 > files/.asset_bundle_stamp'" >/dev/null 2>&1 || true
  echo "   restored $(A shell run-as "$PACKAGE" ls files/cgo/jak1/ 2>/dev/null | tr -d '\r' | wc -l) iso files, $(A shell run-as "$PACKAGE" ls files/out/jak1/fr3/ 2>/dev/null | tr -d '\r' | wc -l) fr3; stamp=$(A shell run-as "$PACKAGE" cat files/.asset_bundle_stamp 2>/dev/null | tr -d '\r')"
else
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
fi

echo "== device CGO/DGO set (what's being tested) =="
A shell run-as "$PACKAGE" sha256sum files/cgo/jak1/JUN.DGO files/cgo/jak1/KERNEL.CGO files/cgo/jak1/GAME.CGO 2>/dev/null | tr -d '\r' | tee "$OUT_DIR/$RUN_TAG-deviceset.txt"

echo "== arm JUNGLE-WARP; tag=$RUN_TAG =="
A shell setprop debug.opengoal.jungle.warp 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f1.warp     0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.echo.intro  0 >/dev/null 2>&1 || true

A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c   >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime \
    opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V \
    libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGCAT_PID=$!
cleanup() {
  kill "$LOGCAT_PID" 2>/dev/null || true
  A shell setprop debug.opengoal.jungle.warp 0 >/dev/null 2>&1 || true
  A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
  device_stayon_restore 2>/dev/null || true
}
trap cleanup EXIT

A shell am start -W -n "$PACKAGE/$ACTIVITY" >/tmp/gjun-am.out 2>&1 || true
grep -q 'Error' /tmp/gjun-am.out && { cat /tmp/gjun-am.out; echo "FAIL: am start"; exit 1; }

crash_seen() { grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG"; }
focus_is_app() { A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PACKAGE"; }
max_frame() { grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }

echo "  warming to title (link finish: logo, up to 150s)..."
for i in $(seq 1 150); do grep -qa "link finish: logo" "$LOG" && { echo "  title ~${i}s"; break; }; crash_seen && { echo "  CRASH before title"; break; }; sleep 1; done

echo "  waiting for JUNGLE-WARP to fire (up to 120s)..."
WARP_OK=0
for i in $(seq 1 120); do
  grep -qaE "JUNGLE-WARP-SPAWN|\[JUNGLE-WARP\] \(start 'play jungle-start\)" "$LOG" && { echo "  warp fired ~${i}s"; WARP_OK=1; break; }
  crash_seen && { echo "  CRASH before warp fired ~${i}s"; break; }
  sleep 1
done

echo "  observing jungle load for up to ${WATCH_S}s (crash or sustained-clean)..."
JUN_LOADED=0
CRASHED=0
for ((i=1;i<=WATCH_S;i++)); do
  if grep -qaE "Adding level jungle|link finish: (jungle|junglesnake|jungle-obs|junglefish|jun-vis|jungle-vis)" "$LOG"; then
    [ "$JUN_LOADED" = 0 ] && echo "   >>> jungle DGO link/add ~${i}s"
    JUN_LOADED=1
  fi
  if crash_seen; then echo "   >>> CRASH during jungle load/run ~${i}s"; CRASHED=1; break; fi
  (( i % 20 == 0 )) && echo "   [watch ${i}/${WATCH_S}s] frame=$(max_frame) loaded=$JUN_LOADED"
  sleep 1
done
sleep 2

# ── Forensics harvest ──
FRAME=$(max_frame); FRAME=${FRAME:-0}
FOC="no"; focus_is_app && FOC="yes"
SIG=$(grep -aoE 'GK-DIAG sig=[0-9]+|signal (11|6|4) \(SIG[A-Z]+' "$LOG" | tail -1)
GKDIAG=$(grep -aE 'GK-DIAG sig=[0-9]+ fault=' "$LOG" | tail -1)
NEARFN=$(grep -aE 'nearest-fn|A38-TRIPWIRE|A34-DIAG|GSPARK-STATE' "$LOG" | tail -8 | tr '\n' ';')
RFTD=$(grep -aoE '(GCINE3-DEACT-STOMP|GMATCH-RFTD-STOMP|RFTD-STOMP-REPAIR|RFTD-NULLRET-REDIRECT|ENTER-STATE-CODE-REPAIR|DBLEE-DROP-KERNELCODE)' "$LOG" | sort | uniq -c | tr '\n' ';')
A34=$(grep -aE 'A34-DIAG|fp-walk|A37-PCWIN|A37-LRWIN|A16-DIAG|A12-DIAG|A18-DIAG' "$LOG" | tail -10 | tr '\n' ';')
BT=$(grep -aE '#[0-9]{2} pc [0-9a-f]+' "$LOG" | head -18 | tr '\n' ';')
LASTLINK=$(grep -aoE 'link finish: [a-z0-9-]+' "$LOG" | tail -8 | tr '\n' ' ')

STATUS="UNKNOWN"
if [ "$CRASHED" = 1 ]; then
  STATUS="JUNGLE-LOAD-CRASH(sig=${SIG:-?})"
elif [ "$JUN_LOADED" = 1 ] && [ "$FOC" = "yes" ]; then
  STATUS="JUNGLE-LOAD-CLEAN(frame=$FRAME,foreground)"
elif [ "$WARP_OK" = 1 ]; then
  STATUS="WARP-FIRED-NO-JUNGLE-MARKER(frame=$FRAME,focus=$FOC)"
else
  STATUS="INCONCLUSIVE(warp=$WARP_OK,frame=$FRAME,focus=$FOC)"
fi

{
  echo "=== Gcrash-jungle device repro (tag=$RUN_TAG) $(date -Is) ==="
  echo "RESULT tag=$RUN_TAG status=$STATUS"
  echo "  warp_fired=$WARP_OK  jungle_loaded=$JUN_LOADED  render_frame(max)=$FRAME  focus_app=$FOC"
  echo "  sig=${SIG:-none}"
  echo "  gk-diag: ${GKDIAG:-none}"
  echo "  last link-finish: ${LASTLINK:-none}"
  echo "  near-fn/state: ${NEARFN:-none}"
  echo "  rftd/repair-markers: ${RFTD:-none}"
  echo "  a-diag/fp-walk: ${A34:-none}"
  echo "  backtrace: ${BT:-none}"
} | tee "$RESULT"

kill "$LOGCAT_PID" 2>/dev/null || true
trap - EXIT
A shell setprop debug.opengoal.jungle.warp 0 >/dev/null 2>&1 || true
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
device_stayon_restore 2>/dev/null || true
echo "== gjungle_device.sh $RUN_TAG done: $STATUS =="
exit 0
