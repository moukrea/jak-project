#!/usr/bin/env bash
# Phase Gtitle (autoport): device run harness — capture the title ATTRACT over a
# LONG window to observe the spurious "Press <CIRCLE> to use" prompt and the
# logo scene-script progression (ndi-intro -> logo-intro -> logo-intro-2 ->
# logo-loop). The logo command-lists KILL the village1 interactables
# (warp-gate-switch-3, fishermans-boat-2, NPCs) at anim frames 261/61; if the
# spool stalls before those frames, the interactables stay alive and draw their
# proximity "use" prompt. This harness watches long enough to tell stall from
# slow-but-progressing.
#
# Produces the Gtitle-* artifacts the validator inspects:
#   .autoport/reports/Gtitle-routed-logcat-run<N>.log
#   .autoport/reports/Gtitle-focus-run<N>.txt
#   .autoport/reports/Gtitle-device-run<N>-t??s.png
#
# NOT infra (lives at .autoport/ root). No input injected — the title attract
# plays the boot intro automatically.
#
# Usage: bash .autoport/gtitle_run.sh <run-number> [skip-install]
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
LOG="$RDIR/Gtitle-routed-logcat-run${RUN}.log"
FOCUS="$RDIR/Gtitle-focus-run${RUN}.txt"
DGO_SRC="android/app/src/jak1/assets/iso_data/jak1"
mkdir -p "$RDIR"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() {
  for p in "${INTERLOPERS[@]}"; do
    adb shell am force-stop "$p" >/dev/null 2>&1 || true
    adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true
  done
}

# Push the arm64 TIT.DGO + DEM.DGO into the package filesDir (the .extracted_v1
# sentinel survives reinstall, so this is what actually updates the DGOs). Add
# any extra DGOs passed as args (for instrumented engine/village builds).
push_dgos() {
  local extra=( "$@" )
  for f in TIT.DGO DEM.DGO "${extra[@]}"; do
    if [ ! -f "$DGO_SRC/$f" ]; then echo "  push_dgos: MISSING $DGO_SRC/$f" >&2; continue; fi
    adb push "$DGO_SRC/$f" "/data/local/tmp/$f" >/dev/null 2>&1 || { echo "  push_dgos: push $f failed" >&2; continue; }
    adb shell run-as "$PKG" cp "/data/local/tmp/$f" "files/cgo/jak1/$f" || { echo "  push_dgos: run-as cp $f failed" >&2; continue; }
    adb shell rm -f "/data/local/tmp/$f" >/dev/null 2>&1 || true
    local local_sz dev_sz
    local_sz=$(stat -c %s "$DGO_SRC/$f" 2>/dev/null || echo 0)
    dev_sz=$(adb shell run-as "$PKG" wc -c "files/cgo/jak1/$f" 2>/dev/null | awk '{print $1}' | tr -d '\r ' || echo 0)
    echo "  push_dgos: $f local=$local_sz device=$dev_sz $([ "$local_sz" = "$dev_sz" ] && echo OK || echo MISMATCH)"
  done
}

frame_max() { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1; }
sig_count() { grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$LOG" 2>/dev/null || true; }
last_spool() { grep -a 'A36-STR-DIAG rpc name=' "$LOG" 2>/dev/null | grep -oE 'name="[^"]+"' | tail -1; }

cap() {  # cap <name>
  local name="$1"
  adb shell am force-stop com.xiaoji.egggameplus >/dev/null 2>&1 || true
  local foc fm sp
  foc=$(adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r')
  fm=$(frame_max); fm=${fm:-0}
  sp=$(last_spool); sp=${sp:-none}
  echo "$name :: frame=$fm spool=$sp :: $foc" >> "$FOCUS"
  adb shell screencap -p /sdcard/gtitle.png >/dev/null 2>&1 || true
  adb pull /sdcard/gtitle.png "$RDIR/Gtitle-device-run${RUN}-${name}.png" >/dev/null 2>&1 || true
  adb shell rm -f /sdcard/gtitle.png >/dev/null 2>&1 || true
  echo "    [$name] frame=$fm spool=$sp -> Gtitle-device-run${RUN}-${name}.png ($(stat -c %s "$RDIR/Gtitle-device-run${RUN}-${name}.png" 2>/dev/null || echo 0) B)"
}

echo "== Gtitle run $RUN (LONG attract capture, no input) =="
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

adb shell am force-stop "$PKG" 2>/dev/null || true
echo "== syncing arm64 DGOs to device filesDir =="
push_dgos "${@:3}"

adb logcat -G 16M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
START_MS=$(date +%s%3N)
adb shell am start -W -n "$PKG/$ACT" >/tmp/gtitle-amstart.out 2>&1 || true

# Long capture: dense early (SCE/ndi), then sample through the WHOLE attract so
# we can see logo-intro-2 -> logo-loop and whether the use-prompt persists.
CRASHED=""
for t in 3 5 8 11 14 18 22 26 30 36 42 48 54 60 70 80 90 100 110 120; do
  now=$(( $(date +%s%3N) - START_MS ))
  want=$(( t * 1000 ))
  if [ "$want" -gt "$now" ]; then sleep "$(awk "BEGIN{printf \"%.3f\", ($want-$now)/1000}")"; fi
  cap "t$(printf '%03d' "$t")s"
  SC=$(sig_count); SC=${SC:-0}
  if [ "${SC:-0}" -ge 1 ]; then
    echo "   CRASH detected (sig=11) at t=${t}s — stopping"
    CRASHED=yes
    break
  fi
done

FM=$(frame_max); FM=${FM:-0}
SC=$(sig_count); SC=${SC:-0}
echo "== final: frame_max=$FM sig11=$SC crashed=${CRASHED:-no} =="

sleep 2
echo "== teardown =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== marker scoreboard (run $RUN) =="
for pat in "ndi-intro" "logo-intro" "logo-intro-2" "logo-loop" "target-title" \
           "fishermans-boat-ride-to-misty" "warp-gate" "GTITLE-KILL" \
           "GTITLE-WARP-PROMPT" "GTITLE-BOAT-PROMPT" "GTITLE-LOGOFRAME" \
           "A35-RENDER frame" "GK-DIAG sig=11" ; do
  n=$(grep -ac "$pat" "$LOG" 2>/dev/null || echo 0)
  printf "  %-36s %s\n" "$pat" "$n"
done
echo "log: $LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines), frame_max=$FM, sig11=$SC"
echo "focus/spool log: $FOCUS"
