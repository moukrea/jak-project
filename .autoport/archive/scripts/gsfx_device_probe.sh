#!/usr/bin/env bash
# gsfx_device_probe.sh — capture the SFX-PROBE lines from the device during the
# title flythrough (ambient bird/water SFX auto-fire there, same static-sound-name
# path as crate/orb/eco). Probe libgk is libgk-only; CGOs = known-good (still has
# the bug). Compares device sound-name bytes vs the x86 ground truth.
#
# Usage: gsfx_device_probe.sh <out_label> [capture_secs]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
LABEL="${1:-device}"; SECS="${2:-70}"
OUTDIR=.autoport/reports/Gsfx-actions
RAW="$OUTDIR/${LABEL}-logcat.log"; OUT="$OUTDIR/${LABEL}-sfxprobe.txt"
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[gsfx-dev FAIL] $*" >&2; exit 1; }
mkdir -p "$OUTDIR"

adb get-state >/dev/null 2>&1 || die "device $S not attached"
# keep screen awake (device PIN-locks on sleep -> 0 frames)
adb shell settings put global stay_on_while_plugged_in 7 >/dev/null 2>&1 || true
adb shell svc power stayon true >/dev/null 2>&1 || true
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true

echo "== enable SFX probe prop =="
adb shell setprop debug.opengoal.sfx.probe 1 >/dev/null 2>&1 || true
echo "  prop: $(adb shell getprop debug.opengoal.sfx.probe | tr -d '\r')"

echo "== relaunch app + capture for ${SECS}s =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
: > "$RAW"
( "$ADB" -s "$S" logcat -v threadtime | grep --line-buffered -aE 'SFX-PROBE|link finish:|Fatal signal|signal (11|6|4) \(SIG' > "$RAW" ) &
LCP=$!
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt "$SECS" ]; do
  adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  sleep 5
done
kill ${LCP:-0} 2>/dev/null || true

FOCUS=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
grep -a "SFX-PROBE" "$RAW" > "$OUT" 2>/dev/null || true
N=$(grep -ac "SFX-PROBE] play" "$OUT" 2>/dev/null || echo 0)
LF=$(grep -ac "link finish: logo" "$RAW" 2>/dev/null || echo 0)
CRASH=$(grep -acE "Fatal signal|signal (11|6|4) \(SIG" "$RAW" 2>/dev/null || echo 0)
echo "[gsfx-dev] label=$LABEL SFX_PROBE_play_lines=$N link_finish_logo=$LF crash_lines=$CRASH"
echo "[gsfx-dev] focus: $FOCUS"
echo "[gsfx-dev] wrote $OUT and $RAW"
echo "== distinct device sound names (name + hex) =="
grep -a "SFX-PROBE] play" "$OUT" 2>/dev/null | sed -E "s/.*play name=('[^']*' hex=[0-9a-f]+).*/\1/" | sort -u | head -40
echo "== device lookup idx distribution =="
grep -a "lookup idx=" "$OUT" 2>/dev/null | sed -E "s/.*lookup idx=(-?[0-9]+).*/\1/" | sort | uniq -c | sort -rn | head
