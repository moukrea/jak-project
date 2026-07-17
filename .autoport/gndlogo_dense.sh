#!/usr/bin/env bash
# Gndlogo dense capture — grab back-to-back device frames through the whole ndi
# logo beat so we can pick the device frame whose logo+Jak+Daxter animation moment
# best matches each pristine golden (the 1s time-series is too coarse: the
# characters animate and a frame must land on the golden's exact pose). No input;
# the title attract auto-plays ndi. Frames -> .autoport/reports/Gndlogo/dense/.
#
# Usage: bash .autoport/gndlogo_dense.sh <run-number>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
RUN="${1:-1}"
PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
RDIR=".autoport/reports"
DDIR="$RDIR/Gndlogo/dense"
LOG="$RDIR/Gndlogo-dense-logcat-run${RUN}.log"
IDX="$RDIR/Gndlogo-dense-index-run${RUN}.txt"
DGO_SRC="android/app/src/jak1/assets/iso_data/jak1"
mkdir -p "$DDIR"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell am force-stop "$p" >/dev/null 2>&1 || true; adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }

push_dgos() {
  for f in TIT.DGO GAME.CGO; do
    [ -f "$DGO_SRC/$f" ] || continue
    adb push "$DGO_SRC/$f" "/data/local/tmp/$f" >/dev/null 2>&1 || continue
    adb shell run-as "$PKG" cp "/data/local/tmp/$f" "files/cgo/jak1/$f" || true
    adb shell rm -f "/data/local/tmp/$f" >/dev/null 2>&1 || true
    echo "  push_dgos: $f $(stat -c %s "$DGO_SRC/$f")"
  done
}
frame_max() { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1; }
last_spool() { grep -a 'A36-STR-DIAG rpc name=' "$LOG" 2>/dev/null | grep -oE 'name="[^"]+"' | tail -1; }

echo "== Gndlogo DENSE capture run $RUN =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_unlocked
push_dgos
rm -f "$DDIR"/d*.png
: > "$IDX"

adb shell am force-stop "$PKG" 2>/dev/null || true
adb logcat -G 16M 2>/dev/null || true; adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 & LOGCAT_PID=$!
START_MS=$(date +%s%3N)
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

# Hold off until ~3.5s (renderer up + ndi spool started), then capture back-to-back
# for ~20s (covers the whole ndi-intro window on the slow loader).
sleep 3.5
N=0
END_MS=$(( START_MS + 24000 ))
while [ "$(date +%s%3N)" -lt "$END_MS" ]; do
  el=$(( $(date +%s%3N) - START_MS ))
  printf -v name "d%03d" "$N"
  adb exec-out screencap -p > "$DDIR/${name}.png" 2>/dev/null || true
  fm=$(frame_max); fm=${fm:-0}; sp=$(last_spool); sp=${sp:-none}
  echo "$name el=${el}ms frame=$fm spool=$sp" >> "$IDX"
  N=$(( N + 1 ))
done
echo "captured $N dense frames"

sleep 1
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true
echo "== dense index (frame/spool per capture) =="
cat "$IDX"
echo "frames in $DDIR ; logcat $LOG"
