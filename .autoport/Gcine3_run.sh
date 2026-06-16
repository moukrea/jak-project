#!/usr/bin/env bash
# Phase Gcine-crash3 device run: drive NEW GAME -> intro cinematic via
# cpad_inject and let it PLAY THROUGH the Gol/Maia portal (misty) scene and
# WELL PAST the prior ~9960 capture window into sustained gameplay.
#
# This is the LONG run that Gcine-crash2 / Gcine-pose never did: it does NOT
# break at frame>=9300 — it keeps watching until frame>=BREAK_FRAME (default
# 11200, comfortably past the 10500 gate) OR the app dies (native sig / process
# gone). At end-of-run it records the REAL mCurrentFocus (the owner's actual
# symptom: launcher = app died = crash; jak1 = survived).
#
# Output:
#   .autoport/reports/Gcine3-routed-logcat-run<N>.log   (validator AFTER-run path)
#   .autoport/reports/Gcine3/crash-logcat.log           (repro copy)
#   .autoport/reports/Gcine3/foreground-at-end.txt       (mCurrentFocus at end)
#
# Usage: bash .autoport/Gcine3_run.sh <run-number> [skip-install]
# Env:   WATCH_MIN=<minutes> (default 20)   BREAK_FRAME=<n> (default 11200)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
RUN="${1:-1}"
SKIP_INSTALL="${2:-}"
WATCH_MIN="${WATCH_MIN:-20}"
BREAK_FRAME="${BREAK_FRAME:-11200}"

PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
INJECT="/data/data/$PKG/files/cpad_inject"
RDIR=".autoport/reports"
LOG="$RDIR/Gcine3-routed-logcat-run${RUN}.log"
mkdir -p "$RDIR/Gcine3"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() {
  for p in "${INTERLOPERS[@]}"; do
    adb shell am force-stop "$p" >/dev/null 2>&1 || true
    adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true
  done
}
inject() { printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject: '$1'"; }
clear_inject() { inject ""; }
read_focus() { adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r'; }

echo "== Gcine3 LONG run $RUN (watch ${WATCH_MIN} min, break at frame>=${BREAK_FRAME}) =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space

if [ "$SKIP_INSTALL" != "skip" ]; then
  device_install_and_launch "$PKG" "$ACT" "$APK"
else
  device_require_unlocked
fi

adb shell am force-stop "$PKG" 2>/dev/null || true
# Arm the joint-sanity tripwire so any residual NaN bone activity is visible in
# the long window (the parent/output repair itself is always-on in the build).
adb shell setprop debug.opengoal.gpose.tripwire 1 2>/dev/null || true
echo "  armed debug.opengoal.gpose.tripwire=$(adb shell getprop debug.opengoal.gpose.tripwire | tr -d '\r')"
# Optional: arm the A38 mprotect tripwire on a GOAL band to NAME a stomp writer.
if [ "${A38:-0}" = "1" ]; then
  adb shell setprop debug.opengoal.a38.tripwire 1 2>/dev/null || true
  [ -n "${BANDLO:-}" ] && adb shell setprop debug.opengoal.gnd.bandlo "$BANDLO" 2>/dev/null || true
  [ -n "${BANDHI:-}" ] && adb shell setprop debug.opengoal.gnd.bandhi "$BANDHI" 2>/dev/null || true
  echo "  armed A38 tripwire band=[$(adb shell getprop debug.opengoal.gnd.bandlo|tr -d '\r'),$(adb shell getprop debug.opengoal.gnd.bandhi|tr -d '\r'))"
else
  adb shell setprop debug.opengoal.a38.tripwire 0 2>/dev/null || true
fi
clear_inject
adb logcat -G 16M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
adb shell am start -W -n "$PKG/$ACT" >/tmp/gcine3-amstart.out 2>&1 || true

echo "== stage 1: warmup (title + flythrough settle) =="
sleep 40

echo "== stage 2: START (open progress menu) =="
inject "start"; sleep 1.2; clear_inject; sleep 4

echo "== stage 3: DOWN x2 then back UP to NEW GAME =="
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up"; sleep 0.4; clear_inject; sleep 1
inject "up"; sleep 0.4; clear_inject; sleep 1.5

echo "== stage 4: X (select NEW GAME -> save-file screen) =="
inject "x"; sleep 0.6; clear_inject; sleep 3

echo "== stage 5: navigate to CONTINUE WITHOUT SAVING + confirm =="
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "x"; sleep 0.6; clear_inject
sleep 4

CONFIRM_OFS=$(wc -l < "$LOG" 2>/dev/null || echo 0)
echo "   post-confirm log offset: $CONFIRM_OFS"

echo "== stage 6: LONG play-through watch (${WATCH_MIN} min, poll 15s, break frame>=${BREAK_FRAME}) =="
CRASH_RE="GK-DIAG sig=|Fatal signal [0-9]|signal 11 \(SIGSEGV\)|signal 4 \(SIGILL\)|signal 6 \(SIGABRT\)|A18-DIAG method-not-implemented"
ITERS=$(( WATCH_MIN * 60 / 15 ))
CRASHED=""
GONE=0
LASTFOC=""
for ((i=1; i<=ITERS; i++)); do
  sleep 15
  FM=$(grep -a 'A35-RENDER frame=' "$LOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)
  CR=$(grep -acE "$CRASH_RE" "$LOG" 2>/dev/null || true)
  GG=$(grep -ac 'GPOSE-GLITCH' "$LOG" 2>/dev/null || true)
  PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
  LASTFOC=$(read_focus)
  echo "   [${i}/${ITERS}] frame=${FM:-0} glitch_frames=${GG:-0} crash=${CR:-0} pid='${PID:-gone}' focus='${LASTFOC##*mCurrentFocus=}'"
  if [ "${CR:-0}" -ge 1 ]; then echo "   >>> CRASH/TRAP SIGNATURE detected"; CRASHED="trap"; sleep 3; break; fi
  if [ -z "$PID" ]; then GONE=$((GONE+1)); else GONE=0; fi
  if [ "$GONE" -ge 2 ]; then echo "   >>> app PROCESS GONE twice (crash/exit)"; CRASHED="procgone"; sleep 2; break; fi
  if [ "${FM:-0}" -ge "$BREAK_FRAME" ]; then echo "   >>> played through long window (frame=$FM >= $BREAK_FRAME)"; sleep 2; break; fi
done

# Record the REAL end-of-run focus BEFORE any teardown force-stop. If the app
# crashed/exited this is com.miui.home; if it survived it is org.opengoal.gk.jak1.
sleep 1
ENDFOC=$(read_focus)
[ -z "$ENDFOC" ] && ENDFOC="$LASTFOC"
ENDPID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
{
  echo "# Gcine3 end-of-run foreground check (run $RUN, $(date -Is))"
  echo "mCurrentFocus_at_end: $ENDFOC"
  echo "app_pid_at_end: ${ENDPID:-gone}"
  echo "crashed: ${CRASHED:-no}"
} > "$RDIR/Gcine3/foreground-at-end.txt"

echo "== teardown =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

# Copy the repro log for the validator's crash-logcat.log path.
cp -f "$LOG" "$RDIR/Gcine3/crash-logcat.log"

echo "== scoreboard (run $RUN) =="
FM=$(grep -a 'A35-RENDER frame=' "$LOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal (11|6|4)|signal 4 \(SIGILL\)|signal 6 \(SIGABRT\)" "$LOG" 2>/dev/null || true)
GG=$(grep -ac 'GPOSE-GLITCH' "$LOG" 2>/dev/null || true)
echo "  highest A35-RENDER frame   : ${FM:-0}"
echo "  native crash-signal lines  : ${CR:-0}"
echo "  GPOSE-GLITCH frames        : ${GG:-0}"
echo "  CRASHED                    : ${CRASHED:-no}"
echo "  mCurrentFocus at end       : $ENDFOC"
echo "  app pid at end             : ${ENDPID:-gone}"
echo "log: $LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines)"
echo "-- tail of any crash/abort markers --"
grep -anE "$CRASH_RE|has died|exited cleanly|Zygote|libc :|Cmdline:|backtrace:|signal " "$LOG" 2>/dev/null | tail -25
