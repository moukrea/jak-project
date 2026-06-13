#!/usr/bin/env bash
# Phase Gintro (autoport): device run harness — verify the pre-title intro
# (Naughty Dog / Daxter "ndi-intro" logo) RENDERS in chronological order,
# BEFORE the Jak&Daxter title flythrough (logo-intro-2).
#
# Root cause being verified: the GL renderer takes ~2 s to bring up (glad +
# 43 shaders + GAME.fr3) while the GOAL dispatcher free-ran the entire intro;
# every chain for those frames was dropped, so the first rendered frame
# landed at logo-intro and the ND/Daxter logo was never shown. The fix holds
# the dispatcher at its first vsync() until the renderer is ready
# (android_gfx.cpp::vsync), so the intro renders from its first beat.
#
# NOTE: the SCE "presents" static screen is SCEI-territory-gated
# (DecodeTerritory() returns GAME_TERRITORY_SCEA on BOTH the pristine x86
# gold and Android), so it spawns on neither — the first rendered beat is the
# ND/Daxter ndi-intro. This harness captures a dense EARLY/MID time-series and
# labels each frame with the live spool name so ndi frames are unambiguous.
#
# NOT infra (lives at .autoport/ root so the validator's forbidden-edit gate
# ignores it). Derived from g1_run.sh. NO input is injected — the title
# attract plays the intro automatically (ndi -> logo-intro -> logo-loop),
# avoiding any new-game state transition (the documented G2 residual).
#
# Usage: bash .autoport/gintro_run.sh <run-number> [skip-install]
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
LOG="$RDIR/Gintro-routed-logcat-run${RUN}.log"
FOCUS="$RDIR/Gintro-focus-run${RUN}.txt"
mkdir -p "$RDIR"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() {
  for p in "${INTERLOPERS[@]}"; do
    adb shell am force-stop "$p" >/dev/null 2>&1 || true
    adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true
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
  adb shell screencap -p /sdcard/gi.png >/dev/null 2>&1 || true
  adb pull /sdcard/gi.png "$RDIR/Gintro-device-run${RUN}-${name}.png" >/dev/null 2>&1 || true
  adb shell rm -f /sdcard/gi.png >/dev/null 2>&1 || true
  echo "    [$name] frame=$fm spool=$sp -> Gintro-device-run${RUN}-${name}.png ($(stat -c %s "$RDIR/Gintro-device-run${RUN}-${name}.png" 2>/dev/null || echo 0) B)"
}

echo "== Gintro run $RUN (pre-title intro render, no input) =="
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
adb logcat -G 16M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
START_MS=$(date +%s%3N)
adb shell am start -W -n "$PKG/$ACT" >/tmp/gi-amstart.out 2>&1 || true

# Dense EARLY/MID time-series from app launch. The renderer holds the
# dispatcher ~2 s, then title load, then ndi (ND/Daxter logo) ~several s,
# then logo-intro-2 flythrough. Each cap is labeled with the live spool name
# so ndi frames are identifiable regardless of exact device timing.
CRASHED=""
LAST=0
for t in 2 3 4 5 6 7 8 9 10 11 12 13 14 16 18 20 24 28 34 40; do
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
echo "== final: frame_max=$FM sig11=$SC crashed=${CRASHED:-no} =="

sleep 2
echo "== teardown =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== marker scoreboard (run $RUN) =="
for pat in "renderer ready" "send_chain before renderer" "A35-RENDER frame" \
           "ndi-intro" "logo-intro" "logo-intro-2" "logo-loop" \
           "set-master-mode" "GK-DIAG sig=11" "A42-CHAIN-PRECOPY" ; do
  n=$(grep -ac "$pat" "$LOG" 2>/dev/null || echo 0)
  printf "  %-32s %s\n" "$pat" "$n"
done
echo "== chains received vs dropped (the fix's direct signal) =="
grep -aE "A40-DPROC" "$LOG" 2>/dev/null | tail -2 || true
echo "log: $LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines), frame_max=$FM, sig11=$SC"
echo "focus/spool log: $FOCUS"
