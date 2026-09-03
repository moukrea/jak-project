#!/usr/bin/env bash
# village-water (autoport): test whether the title-attract OCEAN actually
# ANIMATES. Capture the slow flythrough, then at the SENTINEL-BEACH ocean
# moment grab a burst of consecutive frames (~0.4s apart) so the water surface
# can be compared frame-to-frame. Also harvest the ocean mips2c binding state
# and any A35-RENDER ocean skip lines. Pure measurement (no build).
#
# Usage: bash .autoport/villwater_run.sh <tag> [skip-install]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
TAG="${1:-before}"
SKIP_INSTALL="${2:-}"

PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
RDIR=".autoport/reports/village-water"
LOG="$RDIR/villwater-routed-logcat-${TAG}.log"
FOCUS="$RDIR/villwater-focus-${TAG}.txt"
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
tris_max()  { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "tris=[0-9]+"  | grep -oE "[0-9]+" | sort -n | tail -1; }
sig_count() { grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$LOG" 2>/dev/null || true; }

cap() {  # cap <name>
  local name="$1"
  local foc fm tr
  foc=$(adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r')
  fm=$(frame_max); fm=${fm:-0}
  tr=$(tris_max); tr=${tr:-0}
  echo "$name :: frame=$fm tris=$tr :: $foc" >> "$FOCUS"
  adb shell screencap -p /sdcard/villwater.png >/dev/null 2>&1 || true
  adb pull /sdcard/villwater.png "$RDIR/device-${TAG}-${name}.png" >/dev/null 2>&1 || true
  adb shell rm -f /sdcard/villwater.png >/dev/null 2>&1 || true
  echo "    [$name] frame=$fm tris=$tr -> device-${TAG}-${name}.png ($(stat -c %s "$RDIR/device-${TAG}-${name}.png" 2>/dev/null || echo 0) B) :: $foc"
}

echo "== village-water $TAG (attract capture + ocean burst, no input) =="
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
adb shell am start -W -n "$PKG/$ACT" >/tmp/villwater-amstart.out 2>&1 || true

# coarse samples through the attract; then bursts at the ocean moments.
CRASHED=""
for t in 4 8 12 16 22 28 36 44 52 60 70 80 92; do
  now=$(( $(date +%s%3N) - START_MS ))
  want=$(( t * 1000 ))
  if [ "$want" -gt "$now" ]; then sleep "$(awk "BEGIN{printf \"%.3f\", ($want-$now)/1000}")"; fi
  cap "t$(printf '%03d' "$t")s"
  SC=$(sig_count); SC=${SC:-0}
  if [ "${SC:-0}" -ge 1 ]; then
    echo "   CRASH detected (sig=11) at t=${t}s — stopping"; CRASHED=yes; break
  fi
  # at the SENTINEL-BEACH ocean window (~t44-52), grab a rapid burst.
  if [ "$t" = "44" ] || [ "$t" = "52" ]; then
    for b in 1 2 3 4 5 6; do
      cap "t$(printf '%03d' "$t")s-burst$b"
      sleep 0.4
    done
  fi
done

FM=$(frame_max); FM=${FM:-0}
TR=$(tris_max); TR=${TR:-0}
SC=$(sig_count); SC=${SC:-0}
echo "== final: frame_max=$FM tris_max=$TR sig11=$SC crashed=${CRASHED:-no} =="

sleep 2
echo "== teardown =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== ocean mips2c binding (REAL vs FALLBACK) =="
grep -aoE "A37-MIPS2C-(REAL|FALLBACK) (init-ocean-far-regs|render-ocean-quad|ocean-interp-wave|ocean-generate-verts|draw-large-polygon-ocean)" "$LOG" 2>/dev/null | sort | uniq -c || echo "   (none)"
echo "== A35-RENDER ocean skip buckets =="
grep -aiE 'A35-RENDER skip bucket=ocean' "$LOG" 2>/dev/null | sort -u || echo "   (no ocean skip)"
echo "== all skip buckets =="
grep -a 'A35-RENDER skip bucket=' "$LOG" 2>/dev/null | sed -E 's/.*A35-RENDER //' | sort -u || echo "   (none)"
echo "log: $LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines), frame_max=$FM, tris_max=$TR, sig11=$SC"
echo "focus: $FOCUS"
