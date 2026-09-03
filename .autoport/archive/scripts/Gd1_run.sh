#!/usr/bin/env bash
# Gcine-camfov device capture+verify: drive NEW GAME -> intro cutscene via
# cpad_inject with GCINE-CAM armed, capture the cutscene camera at the M1/M2
# held beats (to confirm the 4:3 fix: c0.x ~0.29031, c1.y ~-0.24200), and PLAY
# THROUGH past frame 10500 crash-free with foreground=jak1 at end.
#
# Outputs under .autoport/reports/:
#   Gcine-camfov-routed-logcat-run<N>.log   (validator: A35-RENDER frame + crash sigs)
#   Gd1/arm64-cam.log                        (validator: re-captured device cam log)
#   Gd1/foreground-at-end.txt                (validator: foreground=jak1)
#   Gd1/device-shots/*.png                   (eye-confirm: pillarboxed 4:3 framing)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh
export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
INJECT="/data/data/$PKG/files/cpad_inject"
RUN="${1:-1}"
WATCH_MIN="${WATCH_MIN:-22}"; BREAK_FRAME="${BREAK_FRAME:-11000}"
RDIR=".autoport/reports"; OUT="$RDIR/Gd1"; SHOTS="$OUT/device-shots"
LOG="$RDIR/Gcine-camfov-routed-logcat-run${RUN}.log"
CAM="$OUT/arm64-cam.log"; FG="$OUT/foreground-at-end.txt"
mkdir -p "$SHOTS"; rm -f "$SHOTS"/*.png 2>/dev/null || true

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers(){ for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers(){ for p in "${INTERLOPERS[@]}"; do adb shell am force-stop "$p" >/dev/null 2>&1 || true; adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject: '$1'"; }
clear_inject(){ inject ""; }
read_focus(){ adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r'; }
cur_frame(){ grep -a 'A35-RENDER frame=' "$LOG" 2>/dev/null | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1; }
cam_frame(){ tail -n 600 "$LOG" 2>/dev/null | grep -aoE 'GCINE-CAM f=[0-9]+' | tail -1 | grep -oE '[0-9]+$'; }
lvl_onset(){ grep -a "lvl=$1 " "$LOG" 2>/dev/null | head -1 | grep -oE 'GCINE-CAM f=[0-9]+' | grep -oE '[0-9]+$'; }
seen_lvls(){ grep -aoE 'lvl=[a-zA-Z0-9_-]+' "$LOG" 2>/dev/null | sort -u | tr '\n' ' '; }
is_fg(){ case "$(read_focus)" in *"$PKG"*) return 0;; *) return 1;; esac; }
snap(){ is_fg || { echo "    snap[$1] SKIP (fg!=jak1)"; return; }; local o="$SHOTS/$1_f${2}.png"; adb -s "$ANDROID_SERIAL" exec-out screencap -p > "$o" 2>/dev/null && echo "    snap[$1] -> $(basename "$o") ($(identify -format '%wx%h' "$o" 2>/dev/null))" || echo "    snap[$1] FAIL"; }

echo "== Gcine-camfov device run $RUN (watch ${WATCH_MIN}min, break frame>=${BREAK_FRAME}) =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LCP:-0} ${LCP2:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space

adb shell am force-stop "$PKG" 2>/dev/null || true
adb shell setprop debug.opengoal.gcine.cam 1 2>/dev/null || true
echo "  armed gcine.cam=$(adb shell getprop debug.opengoal.gcine.cam | tr -d '\r')"
clear_inject
adb logcat -G 64M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
# SINGLE filtered logcat reader (matches the audit's lighter footprint that
# reached frame 15200; a second reader added pressure that correlated with an
# early flaky intro crash). Includes A35-RENDER frame + GCINE-CAM + crash sigs.
( adb logcat -v threadtime \
    | grep --line-buffered -aE 'A35-RENDER frame=|GCINE-CAM f=|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:|has died' \
    > "$LOG" ) &
LCP=$!
LCP2=0

echo "  launch $PKG/$ACT"; adb shell am start -W -n "$PKG/$ACT" >/tmp/gd1-amstart.out 2>&1 || true
echo "== warmup =="; sleep 40
echo "== START (progress menu) =="; inject "start"; sleep 1.2; clear_inject; sleep 4
echo "== nav to NEW GAME =="
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up";   sleep 0.4; clear_inject; sleep 1
inject "up";   sleep 0.4; clear_inject; sleep 1.5
echo "== X (NEW GAME) =="; inject "x"; sleep 0.6; clear_inject; sleep 3
echo "== CONTINUE WITHOUT SAVING =="
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "x";    sleep 0.6; clear_inject; sleep 4

echo "== watch + held-beat snaps (poll 3s) =="
declare -A DONE; M0=""; LASTFOC=""; GONE=0; CRASHED=""
ITERS=$(( WATCH_MIN * 60 / 3 ))
for ((i=1;i<=ITERS;i++)); do
  sleep 3
  FM=$(cur_frame); FM=${FM:-0}; CF=$(cam_frame); CF=${CF:-0}
  [ -z "$M0" ] && M0=$(lvl_onset misty)
  if [ -n "$M0" ]; then
    for off in 900 4200; do
      tag="mistyrel${off}"; lo=$(( M0 + off - 90 )); hi=$(( M0 + off + 240 ))
      if [ -z "${DONE[$tag]:-}" ] && [ "$CF" -ge "$lo" ] && [ "$CF" -le "$hi" ]; then snap "$tag" "$CF"; DONE[$tag]=1; fi
    done
  fi
  PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
  FG_OK=0; is_fg && FG_OK=1; LASTFOC=$(read_focus)
  if (( i % 5 == 0 )); then echo "   [${i}/${ITERS}] render=${FM} cam=${CF} misty0=${M0:-?} fg=${FG_OK} lvls:$(seen_lvls) pid='${PID:-gone}'"; fi
  CR=$(grep -acE "GK-DIAG sig=11|Fatal signal (11|6|4)|signal 4 \(SIGILL\)|signal 6 \(SIGABRT\)|signal 11 \(SIGSEGV\)" "$LOG" 2>/dev/null || true)
  if [ "${CR:-0}" -ge 1 ]; then echo "   >>> CRASH SIGNATURE"; CRASHED="trap"; sleep 2; break; fi
  if [ -z "$PID" ] && [ "$FG_OK" = "0" ]; then GONE=$((GONE+1)); else GONE=0; fi
  if [ "$GONE" -ge 4 ]; then echo "   >>> app GONE x4"; CRASHED="procgone"; break; fi
  if [ "${FM:-0}" -ge "$BREAK_FRAME" ]; then echo "   >>> reached BREAK_FRAME $FM"; break; fi
done

sleep 1; ENDFOC=$(read_focus); [ -z "$ENDFOC" ] && ENDFOC="$LASTFOC"
ENDPID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
{ echo "# Gcine-camfov end-of-run (run $RUN, $(date -Is))"; echo "mCurrentFocus_at_end: $ENDFOC"; echo "app_pid_at_end: ${ENDPID:-gone}"; echo "crashed: ${CRASHED:-no}"; echo "misty_onset_frame: ${M0:-none}"; } > "$FG"

echo "== teardown =="
kill ${LCP:-0} ${LCP2:-0} 2>/dev/null || true
trap - EXIT
# Derive the Gd1 camera log (validator artifact) from the single routed logcat.
grep -a 'GCINE-CAM f=' "$LOG" > "$CAM" 2>/dev/null || true
reenable_interlopers
adb shell setprop debug.opengoal.gcine.cam 0 2>/dev/null || true
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== scoreboard (run $RUN) =="
echo "  GCINE-CAM lines : $(grep -ac 'GCINE-CAM f=' "$CAM" 2>/dev/null || echo 0)"
echo "  cam frame range : $(grep -aoE 'GCINE-CAM f=[0-9]+' "$CAM" | grep -oE '[0-9]+$' | sort -n | sed -n '1p;$p' | tr '\n' ' ')"
echo "  highest render  : $(cur_frame)"
echo "  crash sigs      : $(grep -acE 'Fatal signal|signal [0-9]+ \(SIG|backtrace:' "$LOG" 2>/dev/null || echo 0)"
echo "  misty onset     : ${M0:-none}"
echo "  foreground end  : $ENDFOC  pid=${ENDPID:-gone}  crashed=${CRASHED:-no}"
echo "  shots           : $(ls "$SHOTS"/*.png 2>/dev/null | wc -l)"
echo "  routed-logcat   : $LOG"
