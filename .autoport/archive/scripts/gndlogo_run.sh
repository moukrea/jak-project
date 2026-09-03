#!/usr/bin/env bash
# Phase Gndlogo (autoport): device run harness for the Naughty-Dog-logo intro
# beat (ndi-intro: Daxter on the ground + Jak pushing the "NAUGHTY [paw] DOG"
# logo, on BLACK, BEFORE the title flythrough). The owner's #1 chronological
# beat. This run is gated OBJECTIVELY by frame_compare vs the 2400x1080 pristine
# golden (touch-overlay masked) — NOT by eyeballing.
#
# No input is injected — the title attract plays the intro automatically
# (ndi -> logo-intro -> logo-loop). We capture a dense EARLY/MID time-series and
# label every frame with the live spool name so the ndi-intro frames (the ND
# logo beat) are unambiguous, and we run long enough to also reach the later
# Sandover flythrough where the village must render (anti-deadlock regression).
#
# Produces the validator-named artifacts:
#   .autoport/reports/Gndlogo-routed-logcat-run<N>.log
#   .autoport/reports/Gndlogo-focus-run<N>.txt
#   .autoport/reports/Gndlogo/Gndlogo-device-run<N>-t<NN>s.png   (time series)
# The two OFFICIAL pixel-gate captures device-ndlogo-{enter,full}.png are picked
# from this series afterward (the ndi frame that best matches each golden beat).
#
# NOT infra (lives at .autoport/ root so the validator's forbidden-edit gate
# ignores it). Derived from gintro_run.sh.
#
# Usage: bash .autoport/gndlogo_run.sh <run-number> [skip-install]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
RUN="${1:-1}"
SKIP_INSTALL="${2:-}"

PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
RDIR=".autoport/reports"
ODIR="$RDIR/Gndlogo"
LOG="$RDIR/Gndlogo-routed-logcat-run${RUN}.log"
FOCUS="$RDIR/Gndlogo-focus-run${RUN}.txt"
DGO_SRC="android/app/src/jak1/assets/iso_data/jak1"
mkdir -p "$RDIR" "$ODIR"

# Push the (rebuilt) arm64 TIT.DGO into the package filesDir. The LoaderActivity
# .extracted_v1 sentinel survives reinstall, so a plain APK install will NOT
# update the DGOs — this run-as cp is what actually updates them on the device.
push_dgos() {
  for f in TIT.DGO; do
    [ -f "$DGO_SRC/$f" ] || { echo "  push_dgos: MISSING $DGO_SRC/$f" >&2; continue; }
    adb push "$DGO_SRC/$f" "/data/local/tmp/$f" >/dev/null 2>&1 || { echo "  push_dgos: push $f failed" >&2; continue; }
    adb shell run-as "$PKG" cp "/data/local/tmp/$f" "files/cgo/jak1/$f" || { echo "  push_dgos: run-as cp $f failed" >&2; continue; }
    adb shell rm -f "/data/local/tmp/$f" >/dev/null 2>&1 || true
    local local_sz dev_sz
    local_sz=$(stat -c %s "$DGO_SRC/$f" 2>/dev/null || echo 0)
    dev_sz=$(adb shell run-as "$PKG" wc -c "files/cgo/jak1/$f" 2>/dev/null | awk '{print $1}' | tr -d '\r ' || echo 0)
    echo "  push_dgos: $f local=$local_sz device=$dev_sz $([ "$local_sz" = "$dev_sz" ] && echo OK || echo MISMATCH)"
  done
}

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() {
  for p in "${INTERLOPERS[@]}"; do
    adb shell am force-stop "$p" >/dev/null 2>&1 || true
    adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true
  done
}

frame_max() { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1; }
tris_max()  { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "tris=[0-9]+"  | grep -oE "[0-9]+" | sort -n | tail -1; }
sig_count() { grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$LOG" 2>/dev/null || true; }
last_spool() { grep -a 'A36-STR-DIAG rpc name=' "$LOG" 2>/dev/null | grep -oE 'name="[^"]+"' | tail -1; }

cap() {  # cap <name>
  local name="$1"
  adb shell am force-stop com.xiaoji.egggameplus >/dev/null 2>&1 || true
  local foc fm sp tr
  foc=$(adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r')
  fm=$(frame_max); fm=${fm:-0}
  tr=$(tris_max);  tr=${tr:-0}
  sp=$(last_spool); sp=${sp:-none}
  echo "$name :: frame=$fm tris=$tr spool=$sp :: $foc" >> "$FOCUS"
  adb exec-out screencap -p > "$ODIR/Gndlogo-device-run${RUN}-${name}.png" 2>/dev/null || true
  echo "    [$name] frame=$fm tris=$tr spool=$sp -> Gndlogo-device-run${RUN}-${name}.png ($(stat -c %s "$ODIR/Gndlogo-device-run${RUN}-${name}.png" 2>/dev/null || echo 0) B)"
}

echo "== Gndlogo run $RUN (ND-logo intro beat, no input) =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space

: > "$FOCUS"

if [ "$SKIP_INSTALL" != "skip" ]; then
  device_install_and_launch "$PKG" "$ACT" "$APK"
else
  device_require_unlocked
fi

echo "  push rebuilt DGO(s) into filesDir (sentinel-proof)"
push_dgos

adb shell am force-stop "$PKG" 2>/dev/null || true
adb logcat -G 16M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
START_MS=$(date +%s%3N)
adb shell am start -W -n "$PKG/$ACT" >/tmp/gnd-amstart.out 2>&1 || true

# Dense series. The renderer holds the dispatcher ~2 s, then title load, then
# ndi (ND/Daxter logo) ~several s on black, then the logo-intro flythrough over
# Sandover (where the village MUST render). Capture densely through the ndi
# window AND out to 40s for the later village flythrough (regression gate).
CRASHED=""
for t in 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 22 24 27 30 34 38 42; do
  now=$(( $(date +%s%3N) - START_MS ))
  want=$(( t * 1000 ))
  if [ "$want" -gt "$now" ]; then sleep "$(awk "BEGIN{printf \"%.3f\", ($want-$now)/1000}")"; fi
  cap "t$(printf '%02d' "$t")s"
  SC=$(sig_count); SC=${SC:-0}
  if [ "${SC:-0}" -ge 1 ]; then
    echo "   CRASH detected (sig=11) at t=${t}s — stopping"
    CRASHED=yes
    break
  fi
done

FM=$(frame_max); FM=${FM:-0}
TR=$(tris_max);  TR=${TR:-0}
SC=$(sig_count); SC=${SC:-0}
echo "== final: frame_max=$FM tris_max=$TR sig11=$SC crashed=${CRASHED:-no} =="

sleep 2
echo "== teardown =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== marker scoreboard (run $RUN) =="
for pat in "renderer ready" "A35-RENDER frame" \
           "ndi-intro" "logo-intro" "logo-intro-2" "logo-loop" \
           "GK-DIAG sig=11" "A42-CHAIN-PRECOPY" ; do
  n=$(grep -ac "$pat" "$LOG" 2>/dev/null || echo 0)
  printf "  %-32s %s\n" "$pat" "$n"
done
echo "== spool timeline (frame :: spool) =="
cat "$FOCUS"
echo "log: $LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines), frame_max=$FM, tris_max=$TR, sig11=$SC"
echo "focus/spool log: $FOCUS"
