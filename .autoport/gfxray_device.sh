#!/usr/bin/env bash
# gfxray_device.sh — DEVICE logo-volumes (title light-rays) lifetime dump.
# Pushes the arm64 TIT.DGO (already staged in the APK assets by
# gfxray_build_arm64_tit.sh, carrying the GFXRAY (format 0 ...) per-frame dump)
# to the device's package filesDir, launches the title attract (no input), and
# captures the GFXRAY lines from logcat (on arm64/HEAD, (format 0 ...) -> the
# GK_STDOUT logcat tag). Records logcat wall-clock timestamps so we can compute the
# rays' WALL-CLOCK lifetime and compare it to x86 (slow-mo vs frozen vs late-deactivate).
# Deterministic STATE dump, NOT pixels. Restores known-good on crash.
#
# Args: <tag> (report suffix, def "before"). Env: CAPTURE (secs, def 130)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh
export ANDROID_SERIAL=eae4df44
TAG="${1:-before}"
CAPTURE="${CAPTURE:-200}"
PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
DGO_SRC="android/app/src/jak1/assets/iso_data/jak1"
RDIR=".autoport/reports/Gfix-title-rays"
LOG="$RDIR/device-${TAG}-logcat.log"
OUT="$RDIR/device-${TAG}.txt"
mkdir -p "$RDIR"
INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable(){ for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable(){ for p in "${INTERLOPERS[@]}"; do adb shell am force-stop "$p" >/dev/null 2>&1 || true; adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }

[ -f "$DGO_SRC/TIT.DGO" ] || { echo "[dev] missing $DGO_SRC/TIT.DGO (run gfxray_build_arm64_tit.sh first)"; exit 1; }

device_require_attached
device_require_unlocked || { echo "[dev] DEVICE LOCKED — need owner to unlock (see device-pin-lock-wait-for-owner)"; exit 2; }
disable
trap 'reenable; kill ${LCPID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space || true

echo "[dev] push arm64 TIT.DGO -> device filesDir"
adb push "$DGO_SRC/TIT.DGO" /data/local/tmp/TIT.DGO >/dev/null 2>&1 || { echo "[dev] push failed"; exit 1; }
adb shell run-as "$PKG" cp /data/local/tmp/TIT.DGO files/iso_data/jak1/TIT.DGO || { echo "[dev] run-as cp failed"; exit 1; }
adb shell rm -f /data/local/tmp/TIT.DGO >/dev/null 2>&1 || true
lsz=$(stat -c %s "$DGO_SRC/TIT.DGO"); dsz=$(adb shell run-as "$PKG" wc -c files/iso_data/jak1/TIT.DGO 2>/dev/null | awk '{print $1}' | tr -d '\r ')
echo "[dev] TIT.DGO local=$lsz device=$dsz $([ "$lsz" = "$dsz" ] && echo OK || echo MISMATCH)"

adb shell am force-stop "$PKG" 2>/dev/null || true
adb logcat -G 16M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 &
LCPID=$!
echo "[dev] launch attract; capture ${CAPTURE}s (no input)"
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
# NOTE: a crash is ONLY our app's own GK-DIAG sig=4/6/11 (or a Fatal signal 4/6/11).
# SIGKILL (signal 9) on the disabled interloper PIDs is NOT a crash (signal9-not-a-crash).
SIG=0; SAWRAY=0; RAYDONE=0
for ((t=5; t<=CAPTURE; t+=5)); do
  sleep 5
  s=$(grep -acE "GK-DIAG sig=(4|6|11)|Fatal signal[^0-9]+(4|6|11)\b" "$LOG" 2>/dev/null); s=${s%%$'\n'*}; s=${s:-0}
  if [ "$s" -ge 1 ] 2>/dev/null; then echo "[dev] REAL CRASH sig=4/6/11 at ~${t}s"; SIG=1; break; fi
  # progress trace: note when the rays appear (vol=1) and when they vanish (back to vol=0)
  r1=$(grep -acE "GFXRAY f=[0-9]+ vol=1" "$LOG" 2>/dev/null); r1=${r1%%$'\n'*}; r1=${r1:-0}
  if [ "$r1" -ge 1 ] 2>/dev/null && [ "$SAWRAY" = 0 ]; then SAWRAY=1; echo "[dev] rays APPEARED (vol=1) by ~${t}s"; fi
  if [ "$SAWRAY" = 1 ] && [ "$RAYDONE" = 0 ]; then
    # rays seen, and the most recent GFXRAY is vol=0 -> they vanished; capture ~30s more then stop
    last=$(grep -aE "GFXRAY f=[0-9]" "$LOG" 2>/dev/null | tail -1)
    if [[ "$last" == *"vol=0"* ]]; then RAYDONE=$t; echo "[dev] rays VANISHED (vol back to 0) by ~${t}s — capturing 30s more"; fi
  fi
  if [ "$RAYDONE" != 0 ] && [ $((t - RAYDONE)) -ge 30 ]; then echo "[dev] post-vanish window captured; stopping at ~${t}s"; break; fi
done
sleep 2
kill ${LCPID:-0} 2>/dev/null || true
trap - EXIT
reenable
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

# Extract GFXRAY (timestamped). logcat threadtime: "MM-DD HH:MM:SS.mmm PID TID I tag: GFXRAY ..."
grep -aE "GFXRAY f=[0-9]" "$LOG" > "$OUT" 2>/dev/null || true
N=$(grep -acE "GFXRAY f=[0-9]" "$LOG" 2>/dev/null || echo 0)
echo "[dev] GFXRAY lines=$N -> $OUT (crash=$SIG)"
echo "[dev] --- transition window (vol 1->0) with wall-clock ---"
awk '
  /GFXRAY f=/ {
    ts=$2;                                  # HH:MM:SS.mmm
    match($0,/f=([0-9]+) vol=([0-9]+) bga=([-0-9.]+) vil=([a-zA-Z0-9_-]+)/,m);
    f=m[1]; vol=m[2]; bga=m[3]+0; vil=m[4];
    if (vol==1 && bga>0.5){ blackframes++; }     # frames where rays pop on a BLACK screen
    if (prevvol==0 && vol==1){ appf=f; appts=ts; print "  APPEAR vol @"ts" frame="f" bga="bga" vil="vil; }
    if (prevvol==1 && prevbga>0.5 && bga<=0.5) print "  bg-a DROP (black->scene) @"ts" frame="f" (rays were on black until here)";
    if (prevvol==1 && vol==0){ print "  VANISH vol @"ts" frame="f" bga="bga" vil="vil"  (prev frame "prevf" bga "prevbga" vil "prevvil")";
                               print "  -> appeared @"appts" frame="appf"  (logical-frame span="f-appf", black-bg frames during rays="blackframes")"; }
    prevvol=vol; prevf=f; prevbga=bga; prevvil=vil;
  }' "$OUT" || true
if [ "$SIG" = "1" ]; then echo "[dev] restoring known-good after crash"; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; fi
[ "$N" -gt 0 ]
