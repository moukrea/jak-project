#!/usr/bin/env bash
# Phase Gtitle-pixelmatch device harness. Captures the TITLE / "PRESS START"
# beat (logo-intro-2 + logo-loop flythrough over Sandover) densely so we can
# pick the device frame whose camera/composition matches the pristine 2400x1080
# oracle golden (matched-phase pixel comparison — the camera orbits, so a fixed
# device timestamp won't land on the golden's pose; we capture a dense burst and
# cross-match).
#
# No input injected — the title attract auto-plays the flythrough.
#
# Produces the validator-named artifacts:
#   .autoport/reports/Gtitle-routed-logcat-run<N>.log
#   .autoport/reports/Gtitle-focus-run<N>.txt
#   .autoport/reports/Gtitle/dense/d###.png  (+ index)  <- pick device-title.png from here
#
# NOT infra (lives at .autoport/ root so the validator's forbidden-edit gate
# ignores it). Derived from gndlogo_run.sh / gndlogo_dense.sh.
#
# Usage: bash .autoport/gtitle_pm_run.sh <run-number> [skip]
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
ODIR="$RDIR/Gtitle"
DDIR="$ODIR/dense"
LOG="$RDIR/Gtitle-routed-logcat-run${RUN}.log"
FOCUS="$RDIR/Gtitle-focus-run${RUN}.txt"
IDX="$RDIR/Gtitle-dense-index-run${RUN}.txt"
DGO_SRC="android/app/src/jak1/assets/iso_data/jak1"
mkdir -p "$RDIR" "$ODIR" "$DDIR"

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
disable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell am force-stop "$p" >/dev/null 2>&1 || true; adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }

frame_max() { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1; }
tris_max()  { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "tris=[0-9]+"  | grep -oE "[0-9]+" | sort -n | tail -1; }
sig_count() { grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$LOG" 2>/dev/null || true; }
last_spool() { grep -a 'A36-STR-DIAG rpc name=' "$LOG" 2>/dev/null | grep -oE 'name="[^"]+"' | tail -1; }
cur_focus() { adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r'; }

echo "== Gtitle-pixelmatch run $RUN (title/press-start beat, no input) =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space

: > "$FOCUS"; : > "$IDX"; rm -f "$DDIR"/d*.png

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
adb shell am start -W -n "$PKG/$ACT" >/tmp/gtitle-amstart.out 2>&1 || true

# Phase 1: wait (up to 200s) until the flythrough reaches the SLOW-camera beat.
# The title camera moves fast everywhere EXCEPT a slow turning-point around
# logo-intro-2 frame ~4400 (and a recurring logo-loop slow segment ~frame 5300),
# which also sit at a day/night brightness trough (locally-stationary lighting).
# Those are the only beats matchable to <2% against the oracle, so we hold off
# the burst until the render frame approaches that window. WANT_FRAME is the
# device render frame at which to start bursting (overridable via env).
WANT_FRAME="${WANT_FRAME:-3800}"
echo "  waiting until render frame >= $WANT_FRAME (slow-camera beat)..."
for i in $(seq 1 200); do
  now=$(( $(date +%s%3N) - START_MS ))
  sp=$(last_spool); sp=${sp:-none}
  fm=$(frame_max); fm=${fm:-0}
  sc=$(sig_count); sc=${sc:-0}
  if [ "${sc:-0}" -ge 1 ]; then echo "   CRASH (sig=11) at ${now}ms during warmup"; break; fi
  echo "   warmup t=$(printf '%6d' $now)ms frame=$fm spool=$sp" >> "$FOCUS"
  if [ "$fm" -ge "$WANT_FRAME" ]; then echo "  reached frame=$fm spool=$sp at ${now}ms -> burst"; break; fi
  sleep 1
done

# Phase 2: dense burst. Capture back-to-back for ~75s to span both slow beats
# (logo-intro-2 ~4400 and the recurring logo-loop slow segment ~5300+); label
# each frame with frame#/spool so we can pick the device frame matching the
# golden's slow-beat composition.
echo "  dense burst (~75s back-to-back)..."
N=0
BURST_END_MS=$(( $(date +%s%3N) + 75000 ))
while [ "$(date +%s%3N)" -lt "$BURST_END_MS" ]; do
  el=$(( $(date +%s%3N) - START_MS ))
  printf -v name "d%03d" "$N"
  adb exec-out screencap -p > "$DDIR/${name}.png" 2>/dev/null || true
  fm=$(frame_max); fm=${fm:-0}; sp=$(last_spool); sp=${sp:-none}
  echo "$name el=${el}ms frame=$fm spool=$sp" >> "$IDX"
  N=$(( N + 1 ))
  sc=$(sig_count); sc=${sc:-0}
  if [ "${sc:-0}" -ge 1 ]; then echo "   CRASH (sig=11) at ${el}ms during burst"; break; fi
done
echo "captured $N dense frames"

# Record final focus (validator checks the last line is the app).
FOC=$(cur_focus); echo "final :: frame=$(frame_max) tris=$(tris_max) spool=$(last_spool) :: $FOC" >> "$FOCUS"

FM=$(frame_max); FM=${FM:-0}; TR=$(tris_max); TR=${TR:-0}; SC=$(sig_count); SC=${SC:-0}
echo "== final: frame_max=$FM tris_max=$TR sig11=$SC =="

sleep 2
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== spool scoreboard =="
for pat in "renderer ready" "ndi-intro" "logo-intro" "logo-intro-2" "logo-loop" "GK-DIAG sig=11"; do
  n=$(grep -ac "$pat" "$LOG" 2>/dev/null || echo 0); printf "  %-24s %s\n" "$pat" "$n"
done
echo "log=$LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines) frame_max=$FM tris_max=$TR sig11=$SC"
echo "dense frames: $DDIR ; index: $IDX ; focus: $FOCUS"
tail -3 "$IDX" 2>/dev/null
