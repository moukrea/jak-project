#!/usr/bin/env bash
# Phase Gtitle-pixelmatch device harness (screenrecord variant). The title is a
# continuously-moving flythrough; coarse `screencap` (~1.1s/frame) can't land on
# the oracle's anim-phase. So we screenrecord the device at ~30fps during the
# slow-camera/brightness-trough beat (logo-intro-2 ~frame 4400 + the recurring
# logo-loop slow segment), pull the mp4, and extract every frame. The matcher
# then finds the device frame whose anim-phase aligns to the dense oracle golden.
#
# Produces validator-named artifacts + a dense device frame dir:
#   .autoport/reports/Gtitle-routed-logcat-run<N>.log
#   .autoport/reports/Gtitle-focus-run<N>.txt
#   .autoport/reports/Gtitle/gtitle-rec-run<N>.mp4
#   .autoport/reports/Gtitle/rec/r#####.png   (extracted frames -> pick device-title.png)
#
# Usage: bash .autoport/gtitle_pm_rec.sh <run-number> [skip]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
RUN="${1:-1}"
SKIP_INSTALL="${2:-}"
WANT_FRAME="${WANT_FRAME:-3900}"
REC_SECONDS="${REC_SECONDS:-80}"

PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
RDIR=".autoport/reports"
ODIR="$RDIR/Gtitle"
RECDIR="$ODIR/rec${RUN}"
LOG="$RDIR/Gtitle-routed-logcat-run${RUN}.log"
FOCUS="$RDIR/Gtitle-focus-run${RUN}.txt"
MP4="$ODIR/gtitle-rec-run${RUN}.mp4"
DEV_MP4="/sdcard/gtitle_rec_${RUN}.mp4"
DGO_SRC="android/app/src/jak1/assets/iso_data/jak1"
mkdir -p "$RDIR" "$ODIR" "$RECDIR"

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

echo "== Gtitle-pixelmatch REC run $RUN (screenrecord the slow-camera title beat) =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space
: > "$FOCUS"; rm -f "$RECDIR"/r*.png
adb shell rm -f "$DEV_MP4" >/dev/null 2>&1 || true

if [ "$SKIP_INSTALL" != "skip" ]; then
  device_install_and_launch "$PKG" "$ACT" "$APK"
else
  device_require_unlocked
fi
echo "  push rebuilt DGO(s) into filesDir (sentinel-proof)"; push_dgos

adb shell am force-stop "$PKG" 2>/dev/null || true
adb logcat -G 16M 2>/dev/null || true; adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 & LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
START_MS=$(date +%s%3N)
adb shell am start -W -n "$PKG/$ACT" >/tmp/gtitle-amstart.out 2>&1 || true

echo "  waiting until render frame >= $WANT_FRAME (approach slow-camera beat)..."
for i in $(seq 1 200); do
  now=$(( $(date +%s%3N) - START_MS )); sp=$(last_spool); sp=${sp:-none}; fm=$(frame_max); fm=${fm:-0}; sc=$(sig_count); sc=${sc:-0}
  if [ "${sc:-0}" -ge 1 ]; then echo "   CRASH (sig=11) at ${now}ms during warmup"; break; fi
  echo "   warmup t=$(printf '%6d' $now)ms frame=$fm spool=$sp" >> "$FOCUS"
  if [ "$fm" -ge "$WANT_FRAME" ]; then echo "  reached frame=$fm spool=$sp at ${now}ms -> screenrecord"; break; fi
  sleep 1
done

echo "  screenrecord ${REC_SECONDS}s @ native res, high bitrate..."
adb shell screenrecord --time-limit "$REC_SECONDS" --bit-rate 90000000 "$DEV_MP4" &
REC_PID=$!
# Sample focus/markers while recording.
for i in $(seq 1 "$REC_SECONDS"); do
  sleep 1
  now=$(( $(date +%s%3N) - START_MS )); echo "rec t=$(printf '%6d' $now)ms frame=$(frame_max) tris=$(tris_max) spool=$(last_spool) :: $(cur_focus)" >> "$FOCUS"
  sc=$(sig_count); [ "${sc:-0}" -ge 1 ] && { echo "   CRASH during recording"; break; }
done
wait $REC_PID 2>/dev/null || true
echo "  recording done; pulling mp4"
adb pull "$DEV_MP4" "$MP4" 2>/dev/null || echo "  WARN: pull failed"
adb shell rm -f "$DEV_MP4" >/dev/null 2>&1 || true

echo "final :: frame=$(frame_max) tris=$(tris_max) spool=$(last_spool) :: $(cur_focus)" >> "$FOCUS"
FM=$(frame_max); FM=${FM:-0}; TR=$(tris_max); TR=${TR:-0}; SC=$(sig_count); SC=${SC:-0}
echo "== final: frame_max=$FM tris_max=$TR sig11=$SC mp4=$(stat -c %s "$MP4" 2>/dev/null||echo 0)B =="

sleep 1
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

# Extract every frame from the mp4 (lossless PNG; mp4 was H.264 high-bitrate).
if [ -s "$MP4" ]; then
  echo "  extracting frames with ffmpeg..."
  ffmpeg -nostdin -loglevel error -i "$MP4" -vsync 0 "$RECDIR/r%05d.png" 2>&1 | tail -3 || true
  echo "  extracted $(ls "$RECDIR"/r*.png 2>/dev/null | wc -l) frames -> $RECDIR"
  identify -format '%f %wx%h\n' "$RECDIR/r00001.png" 2>/dev/null || true
fi
echo "log=$LOG frame_max=$FM tris_max=$TR sig11=$SC ; mp4=$MP4 ; frames=$RECDIR ; focus=$FOCUS"
