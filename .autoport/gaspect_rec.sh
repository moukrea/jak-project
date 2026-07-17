#!/usr/bin/env bash
# Phase Gaspect-unstub TITLE-beat capture (screenrecord variant). The title is a
# continuously-moving flythrough; sparse screencap can't land on the oracle's
# anim-phase (camera pose + day/night brightness trough). So we screenrecord the
# device at native res through the slow-camera beat, pull the mp4, extract EVERY
# frame, and pick the device frame whose anim-phase aligns to the golden. The
# ND-logo beat already matched via the screencap run; this run re-captures ONLY
# the title beat with the patch RETIRED (proving the global enum reaches the
# title path on device).
#
# Writes Gaspect-named artifacts so the title capture is backed by its own healthy
# Gaspect boot log:
#   .autoport/reports/Gaspect-routed-logcat-run<N>.log
#   .autoport/reports/Gaspect-focus-run<N>.txt
#   .autoport/reports/Gaspect/gaspect-rec-run<N>.mp4
#   .autoport/reports/Gaspect/rec<N>/r#####.png
#
# Usage: bash .autoport/gaspect_rec.sh <run-number> [skip]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
RUN="${1:-2}"
SKIP_INSTALL="${2:-}"
WANT_FRAME="${WANT_FRAME:-3900}"
REC_SECONDS="${REC_SECONDS:-110}"

PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
RDIR=".autoport/reports"
ODIR="$RDIR/Gaspect"
RECDIR="$ODIR/rec${RUN}"
LOG="$RDIR/Gaspect-routed-logcat-run${RUN}.log"
FOCUS="$RDIR/Gaspect-focus-run${RUN}.txt"
MP4="$ODIR/gaspect-rec-run${RUN}.mp4"
DEV_MP4="/sdcard/gaspect_rec_${RUN}.mp4"
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
clear_pc_settings() {
  adb shell rm -f /storage/emulated/0/OpenGOAL/jak1/settings.ini 2>/dev/null || true
  echo "  clear_pc_settings: remaining settings.ini: $(adb shell 'ls /storage/emulated/0/OpenGOAL/jak1/settings.ini 2>/dev/null' | tr -d '\r' | wc -l)"
}

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell am force-stop "$p" >/dev/null 2>&1 || true; adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }

frame_max() { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1; }
tris_max()  { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "tris=[0-9]+"  | grep -oE "[0-9]+" | sort -n | tail -1; }
sig_count() { grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$LOG" 2>/dev/null || true; }
last_spool() { grep -a 'A36-STR-DIAG rpc name=' "$LOG" 2>/dev/null | grep -oE 'name="[^"]+"' | tail -1; }
cur_focus() { adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r'; }

echo "== Gaspect TITLE REC run $RUN (screenrecord the slow-camera title beat, patch retired) =="
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
echo "  clear stale persisted aspect setting (so 16:9 boot default stands)"; clear_pc_settings

adb logcat -G 16M 2>/dev/null || true; adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 & LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
START_MS=$(date +%s%3N)
adb shell am start -W -n "$PKG/$ACT" >/tmp/gaspect-rec-amstart.out 2>&1 || true

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

if [ -s "$MP4" ]; then
  echo "  extracting frames with ffmpeg..."
  ffmpeg -nostdin -loglevel error -i "$MP4" -vsync 0 "$RECDIR/r%05d.png" 2>&1 | tail -3 || true
  echo "  extracted $(ls "$RECDIR"/r*.png 2>/dev/null | wc -l) frames -> $RECDIR"
  identify -format '%f %wx%h\n' "$RECDIR/r00001.png" 2>/dev/null || true
fi
echo "log=$LOG frame_max=$FM tris_max=$TR sig11=$SC ; mp4=$MP4 ; frames=$RECDIR ; focus=$FOCUS"
