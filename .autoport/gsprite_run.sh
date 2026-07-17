#!/usr/bin/env bash
# Phase Gsprite (autoport): device run harness — verify the "Sony Computer
# Entertainment presents" static screen RENDERS (not black) in the first frames
# of boot after un-noop'ing the arm64 sparticle sprite-DMA builders
# (particle-adgif / sp-launch-particles-var / sp-process-block-2d /
# sp-process-block-3d) in game/mips2c/mips2c_table_jak1_arm64.cpp's allowlist.
#
# This is a libgk-only change (the mips2c table compiles into libgk.so), so the
# DGOs are unchanged from Gsce — but the Gsce-built un-gated TIT.DGO + DEM.DGO
# must still be on the device (the .extracted_v1 sentinel survives reinstall),
# so this harness re-pushes them via run-as exactly like gsce_run.sh.
#
# Produces the Gsprite-* artifacts the validator inspects:
#   .autoport/reports/Gsprite-routed-logcat-run<N>.log
#   .autoport/reports/Gsprite-focus-run<N>.txt
#   .autoport/reports/Gsprite-device-run<N>-t??s.png
#
# NOT infra (lives at .autoport/ root). No input injected — the title attract
# plays the boot intro automatically (SCE presents -> ndi -> logo-intro).
#
# Usage: bash .autoport/gsprite_run.sh <run-number> [skip-install]
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
LOG="$RDIR/Gsprite-routed-logcat-run${RUN}.log"
FOCUS="$RDIR/Gsprite-focus-run${RUN}.txt"
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

# Push the un-gated arm64 TIT.DGO + DEM.DGO into the package filesDir. The
# sentinel survives reinstall, so this is what actually updates the DGOs.
push_dgos() {
  for f in TIT.DGO DEM.DGO; do
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
# Max tris reported in the EARLY (SCE) window — proves the sprite bucket built.
sce_tris() { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | awk -F'frame=' '{print $2}' | awk '$1+0<=120' | grep -oE 'tris=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1; }

cap() {  # cap <name>
  local name="$1"
  adb shell am force-stop com.xiaoji.egggameplus >/dev/null 2>&1 || true
  local foc fm sp st
  foc=$(adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r')
  fm=$(frame_max); fm=${fm:-0}
  sp=$(last_spool); sp=${sp:-none}
  st=$(sce_tris); st=${st:-0}
  echo "$name :: frame=$fm sce_tris=$st spool=$sp :: $foc" >> "$FOCUS"
  adb shell screencap -p /sdcard/gsprite.png >/dev/null 2>&1 || true
  adb pull /sdcard/gsprite.png "$RDIR/Gsprite-device-run${RUN}-${name}.png" >/dev/null 2>&1 || true
  adb shell rm -f /sdcard/gsprite.png >/dev/null 2>&1 || true
  echo "    [$name] frame=$fm sce_tris=$st spool=$sp -> Gsprite-device-run${RUN}-${name}.png ($(stat -c %s "$RDIR/Gsprite-device-run${RUN}-${name}.png" 2>/dev/null || echo 0) B)"
}

echo "== Gsprite run $RUN (SCE 'presents' sprites RENDER, sparticle builders un-noop'd, no input) =="
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
echo "== syncing arm64 TIT.DGO + DEM.DGO to device filesDir =="
push_dgos

adb logcat -G 16M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
START_MS=$(date +%s%3N)
adb shell am start -W -n "$PKG/$ACT" >/tmp/gsprite-amstart.out 2>&1 || true

# Dense EARLY time-series to catch the SCE presents screen (plays ~3 s at the
# very start of target-title, before ndi), then keep watching through ndi +
# title so frame_max climbs past 300 (the validator's boot-sustained gate).
CRASHED=""
for t in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 16 18 20 24 28 34 40; do
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
SC=$(sig_count); SC=${SC:-0}
ST=$(sce_tris); ST=${ST:-0}
echo "== final: frame_max=$FM sce_tris=$ST sig11=$SC crashed=${CRASHED:-no} =="

sleep 2
echo "== teardown =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== marker scoreboard (run $RUN) =="
for pat in "GSCE-SCE-SPAWN" "GSCE-SCE-RENDER" "static-screen" "renderer ready" \
           "A37-MIPS2C-REAL sp-" "A37-MIPS2C-REAL particle-adgif" \
           "A37-MIPS2C-FALLBACK sp-" "A35-RENDER frame" "ndi-intro" "logo-intro" \
           "GK-DIAG sig=11" ; do
  n=$(grep -ac "$pat" "$LOG" 2>/dev/null || echo 0)
  printf "  %-36s %s\n" "$pat" "$n"
done
echo "log: $LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines), frame_max=$FM, sce_tris=$ST, sig11=$SC"
echo "focus/spool log: $FOCUS"
