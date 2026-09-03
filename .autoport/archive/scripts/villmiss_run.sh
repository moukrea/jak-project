#!/usr/bin/env bash
# village-missing (autoport): capture the title ATTRACT flythrough over Sandover
# village and harvest per-bucket render evidence to NAME the missing geometry
# class (foliage/shrub vs tie-instance vs generic). No code change here — pure
# measurement. Captures device frames + the A37-MIPS2C scoreboard + (if the
# libgk has the temp probe) the A35-BUCKET per-bucket tri lines.
#
# Usage: bash .autoport/villmiss_run.sh <run-number> [skip-install]
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
RDIR=".autoport/reports/village-missing"
LOG="$RDIR/villmiss-routed-logcat-run${RUN}.log"
FOCUS="$RDIR/villmiss-focus-run${RUN}.txt"
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

frame_max() { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1; }
tris_max()  { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "tris=[0-9]+"  | grep -oE "[0-9]+" | sort -n | tail -1; }
sig_count() { grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$LOG" 2>/dev/null || true; }

cap() {  # cap <name>
  local name="$1"
  adb shell am force-stop com.xiaoji.egggameplus >/dev/null 2>&1 || true
  local foc fm tr
  foc=$(adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r')
  fm=$(frame_max); fm=${fm:-0}
  tr=$(tris_max); tr=${tr:-0}
  echo "$name :: frame=$fm tris=$tr :: $foc" >> "$FOCUS"
  adb shell screencap -p /sdcard/villmiss.png >/dev/null 2>&1 || true
  adb pull /sdcard/villmiss.png "$RDIR/device-run${RUN}-${name}.png" >/dev/null 2>&1 || true
  adb shell rm -f /sdcard/villmiss.png >/dev/null 2>&1 || true
  echo "    [$name] frame=$fm tris=$tr -> device-run${RUN}-${name}.png ($(stat -c %s "$RDIR/device-run${RUN}-${name}.png" 2>/dev/null || echo 0) B) :: $foc"
}

echo "== village-missing run $RUN (attract capture, no input) =="
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
adb shell am start -W -n "$PKG/$ACT" >/tmp/villmiss-amstart.out 2>&1 || true

CRASHED=""
for t in 3 6 10 14 18 24 30 38 46 54 62 72 82 92 102; do
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

echo "== A37-MIPS2C-FALLBACK (still-stubbed builders) =="
grep -a 'A37-MIPS2C-FALLBACK' "$LOG" 2>/dev/null | sed -E 's/.*A37-MIPS2C-FALLBACK //' | sort -u || echo "   (none)"
echo "== A37-MIPS2C-REAL (bound real) =="
grep -a 'A37-MIPS2C-REAL' "$LOG" 2>/dev/null | sed -E 's/.*A37-MIPS2C-REAL //' | sort -u || echo "   (none)"
echo "== A35-BUCKET per-bucket (temp probe, if present) — nonzero tris =="
grep -a 'A35-BUCKET' "$LOG" 2>/dev/null | grep -vE 'tris=0 draws=0' | sort -u | head -80 || echo "   (no probe)"
echo "log: $LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines), frame_max=$FM, tris_max=$TR, sig11=$SC"
echo "focus log: $FOCUS"
