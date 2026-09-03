#!/usr/bin/env bash
# Gcine-cut REACH capture, 2026-09-03 reprise (arm64 eae4df44).
# Same gate as gcine_cut_reach.sh (render frame climbs past the validator's >=10500,
# 0 crash signatures, game foreground) but the NEW-GAME intro cinematic is driven by
# the built-in deterministic warp `debug.opengoal.echo.intro=1` (kmachine.cpp
# echo_intro_warp_maybe: replays (initialize! *game-info* 'game #f "intro-start") on
# the kernel thread) instead of the June-2026 cpad_inject menu walk, which no longer
# matches the recharged menu layout. Writes the file the validator reads:
#   .autoport/reports/graphics-verify/routed-logcat.log
# and a scoreboard in .autoport/reports/Gcine-cut/reach2-foreground.txt.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
OUTDIR=".autoport/reports/graphics-verify"
LOG="$OUTDIR/routed-logcat.log"
FG=".autoport/reports/Gcine-cut/reach2-foreground.txt"
MAX_MIN="${MAX_MIN:-18}"
TARGET="${TARGET:-11000}"
mkdir -p "$OUTDIR" .autoport/reports/Gcine-cut

read_focus() { "$ADB" shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r'; }
max_frame() { grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
crash_sigs() { local n; n=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null); echo "${n:-0}"; }
# exact-PID teardown of OUR capture pipeline only (never a pattern kill).
stop_logcat() {
  local kids; kids=$(pgrep -P "${LOGCAT_PID:-0}" 2>/dev/null | tr '\n' ' ')
  for k in $kids; do kill "$k" 2>/dev/null || true; done
  kill "${LOGCAT_PID:-0}" 2>/dev/null || true
}
is_fg() { case "$(read_focus)" in *"$PKG"*) return 0;; *) return 1;; esac; }

echo "== Gcine-cut REACH capture v2 / echo.intro (max ${MAX_MIN}min, target frame>=${TARGET}) =="
device_require_attached
cleanup() {
  stop_logcat
  "$ADB" shell setprop debug.opengoal.echo.intro 0 >/dev/null 2>&1 || true
  "$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
  device_stayon_restore 2>/dev/null || true
}
trap cleanup EXIT
device_stayon_on

"$ADB" shell am force-stop "$PKG" 2>/dev/null || true
"$ADB" shell setprop debug.opengoal.cpad_inject release >/dev/null 2>&1 || true
"$ADB" shell setprop debug.opengoal.echo.intro 1
"$ADB" shell logcat -G 64M 2>/dev/null || true
"$ADB" logcat -c 2>/dev/null || true
: > "$LOG"
( "$ADB" logcat -v threadtime opengoal-gk:I GK_STDOUT:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE 'A35-RENDER frame=|link finish:|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:|has died|ECHO-INTRO-WARP|JAK-HD-TGT|GCINE3-DEACT|GND-OOB-WRITE' \
    >> "$LOG" ) &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT (echo.intro=1)"
"$ADB" shell am start -W -n "$PKG/$ACT" >/tmp/gcine-reach2-amstart.out 2>&1 || true

echo "== watch (poll 3s) =="
ITERS=$(( MAX_MIN * 60 / 3 ))
NOPROG=0; LAST=0; DONE=""; CRASHED=""; WARP=0
for ((i=1;i<=ITERS;i++)); do
  sleep 3
  FM=$(max_frame); FM=${FM:-0}
  CS=$(crash_sigs); CS=${CS:-0}
  FG_OK=0; is_fg && FG_OK=1
  if [ "$WARP" = 0 ] && grep -aq 'ECHO-INTRO-WARP' "$LOG"; then WARP=1; echo "   echo-intro warp fired at iter $i (frame=$FM)"; fi
  if (( i % 5 == 0 )); then echo "   [${i}/${ITERS}] frame=${FM} fg=${FG_OK} crashsig=${CS} warp=${WARP} loads=$(grep -ac 'link finish:' "$LOG")"; fi
  if [ "${CS:-0}" -gt 0 ]; then echo "   >>> REAL crash signature ($CS)"; CRASHED="sig"; break; fi
  if [ "${FM:-0}" -ge "$TARGET" ]; then echo "   >>> reached TARGET frame=$FM"; DONE="reached"; break; fi
  if [ "${FM:-0}" -le "$LAST" ] && [ "$FG_OK" = "0" ]; then NOPROG=$((NOPROG+1)); else NOPROG=0; fi
  LAST=$FM
  if [ "$NOPROG" -ge 20 ]; then echo "   >>> no frame progress + not-foreground for 60s — abort"; CRASHED="stuck"; break; fi
done

sleep 1; ENDFOC=$(read_focus); ENDPID=$("$ADB" shell pidof "$PKG" 2>/dev/null | tr -d '\r')
FINAL=$(max_frame); FINAL=${FINAL:-0}; FCS=$(crash_sigs)
{ echo "# Gcine-cut reach2 (echo.intro) end-of-run ($(date -Is))";
  echo "mCurrentFocus_at_end: $ENDFOC";
  echo "app_pid_at_end: ${ENDPID:-gone}";
  echo "max_render_frame: $FINAL";
  echo "crash_sigs: $FCS";
  echo "echo_intro_warp_lines: $(grep -ac 'ECHO-INTRO-WARP' "$LOG")";
  echo "level_loads: $(grep -a 'link finish:' "$LOG" | sed 's/.*link finish: //' | tr -d '\r' | tr '\n' ' ')";
  echo "target_clone_states: $(grep -a 'JAK-HD-TGT' "$LOG" | sed 's/.*st=//' | tr -d '\r' | uniq | tr '\n' ' ')";
  echo "verdict: ${DONE:-${CRASHED:-timeout}}"; } > "$FG"

# Freeze the log at the reach target BEFORE stopping the app (see gcine_cut_reach.sh).
stop_logcat
"$ADB" shell setprop debug.opengoal.echo.intro 0 >/dev/null 2>&1 || true
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
trap - EXIT
device_stayon_restore 2>/dev/null || true

echo "== scoreboard =="
cat "$FG"
echo "  routed-logcat    : $LOG ($(wc -l < "$LOG" 2>/dev/null) lines)"
[ "$FINAL" -ge "$TARGET" ] && [ "${FCS:-0}" -eq 0 ] && echo "REACH PASS" || echo "REACH FAIL"
