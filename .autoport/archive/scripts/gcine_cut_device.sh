#!/usr/bin/env bash
# Gcine-cut DEVICE capture (arm64 eae4df44). Installs the CURRENT HEAD APK, drives
# NEW GAME -> intro cinematic via cpad_inject with the per-frame GCINE-CAM camera
# log armed (debug.opengoal.gcine.cam 1), and harvests the device camera-position
# stream + crash signatures + foreground state. Cut detection on the device is by
# one-frame camera-position JUMP (GCINE-CAM has no num-slaves/interp-val); a cut
# that became an INTERP shows up as a MISSING jump (gradual sub-threshold motion).
#
# Outputs under .autoport/reports/Gcine-cut/:
#   device-cam.log         GCINE-CAM + frame markers + crash sigs (lean)
#   device-foreground.txt  mCurrentFocus + pid + crash verdict at end-of-run
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=".autoport/reports/Gcine-cut"
CAM="$OUT/device-cam.log"
FG="$OUT/device-foreground.txt"
WATCH_MIN="${WATCH_MIN:-22}"
BREAK_FRAME="${BREAK_FRAME:-30000}"
mkdir -p "$OUT"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell am force-stop "$p" >/dev/null 2>&1 || true; adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }
inject() { printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject: '$1'"; }
clear_inject() { inject ""; }
read_focus() { adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r'; }
cur_frame() { tail -n 250 "$CAM" 2>/dev/null | grep -aoE 'GCINE-CAM f=[0-9]+' | tail -1 | grep -oE '[0-9]+$'; }
lvl_onset() { grep -a "lvl=$1 " "$CAM" 2>/dev/null | head -1 | grep -oE 'GCINE-CAM f=[0-9]+' | grep -oE '[0-9]+$'; }
seen_lvls()  { grep -aoE 'lvl=[a-zA-Z0-9_-]+' "$CAM" 2>/dev/null | sort -u | tr '\n' ' '; }
is_fg() { case "$(read_focus)" in *"$PKG"*) return 0;; *) return 1;; esac; }

echo "== Gcine-cut DEVICE capture (watch ${WATCH_MIN}min, break frame>=${BREAK_FRAME}) =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space
device_install_and_launch "$PKG" "$ACT" "$APK"
adb shell am force-stop "$PKG" 2>/dev/null || true

adb shell setprop debug.opengoal.gcine.cam 1 2>/dev/null || true
echo "  armed debug.opengoal.gcine.cam=$(adb shell getprop debug.opengoal.gcine.cam | tr -d '\r')"
clear_inject
adb logcat -G 64M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
( adb logcat -v threadtime opengoal-gk:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE 'GCINE-CAM f=|GCINE-CUT-DIAG|GCINE-SPOOL|A42-STRCLK|loader stall|spool anim loop|abort|frame=|Fatal signal|signal [0-9]+ \(SIG|backtrace:|has died' \
    > "$CAM" ) &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
adb shell am start -W -n "$PKG/$ACT" >/tmp/gcine-cut-amstart.out 2>&1 || true

echo "== warmup (title attract settle) =="; sleep 40
echo "== START (open progress menu) =="; inject "start"; sleep 1.2; clear_inject; sleep 4
echo "== nav to NEW GAME =="
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up";   sleep 0.4; clear_inject; sleep 1
inject "up";   sleep 0.4; clear_inject; sleep 1.5
echo "== X (select NEW GAME) =="; inject "x"; sleep 0.6; clear_inject; sleep 3
echo "== CONTINUE WITHOUT SAVING =="
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "x";    sleep 0.6; clear_inject; sleep 4

echo "== watch (poll 3s) =="
M0=""; CRASHED=""; GONE=0
ITERS=$(( WATCH_MIN * 60 / 3 ))
for ((i=1;i<=ITERS;i++)); do
  sleep 3
  FM=$(cur_frame); FM=${FM:-0}
  [ -z "$M0" ] && M0=$(lvl_onset misty)
  PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
  FG_OK=0; is_fg && FG_OK=1
  if (( i % 5 == 0 )); then echo "   [${i}/${ITERS}] frame=${FM} misty0=${M0:-?} fg=${FG_OK} lvls:$(seen_lvls) pid='${PID:-gone}'"; fi
  if [ -z "$PID" ] && [ "$FG_OK" = "0" ]; then GONE=$((GONE+1)); else GONE=0; fi
  if [ "$GONE" -ge 4 ]; then echo "   >>> app GONE x4 — crash/exit"; CRASHED="procgone"; break; fi
  if [ "${FM:-0}" -ge "$BREAK_FRAME" ]; then echo "   >>> reached BREAK_FRAME $FM"; break; fi
  if seen_lvls | grep -q 'lvl=training' && [ "${FM:-0}" -ge "$(( ${M0:-0} + 19000 ))" ]; then echo "   >>> training past misty"; break; fi
done

sleep 1; ENDFOC=$(read_focus); ENDPID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
{ echo "# Gcine-cut device end-of-run ($(date -Is))"; echo "mCurrentFocus_at_end: $ENDFOC"; echo "app_pid_at_end: ${ENDPID:-gone}"; echo "crashed: ${CRASHED:-no}"; echo "misty_onset_frame: ${M0:-none}"; } > "$FG"

echo "== teardown =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell setprop debug.opengoal.gcine.cam 0 2>/dev/null || true
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== scoreboard =="
echo "  GCINE-CAM lines : $(grep -ac 'GCINE-CAM f=' "$CAM" 2>/dev/null || echo 0)"
echo "  frame range     : $(grep -aoE 'GCINE-CAM f=[0-9]+' "$CAM" | grep -oE '[0-9]+$' | sort -n | sed -n '1p;$p' | tr '\n' ' ')"
echo "  distinct levels : $(seen_lvls)"
echo "  level onsets    : misty=$(lvl_onset misty) village1=$(lvl_onset village1) beach=$(lvl_onset beach) training=$(lvl_onset training)"
echo "  foreground end  : $ENDFOC  pid=${ENDPID:-gone}  crashed=${CRASHED:-no}"
echo "  crash signatures: $(grep -acE 'Fatal signal|signal [0-9]+ \(SIG|backtrace:' "$CAM" 2>/dev/null || echo 0)"
