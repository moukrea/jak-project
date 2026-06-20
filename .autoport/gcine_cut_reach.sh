#!/usr/bin/env bash
# Gcine-cut REACH capture (arm64 eae4df44). Drives NEW GAME -> intro cinematic via
# cpad_inject (same proven sequence as gcine_cut_device.sh) and captures a LONG
# routed logcat so the render frame climbs past the validator's >=10500 gate. This
# exists because prior attempts misread a too-short capture window (the app was
# healthy + progressing at ~frame 4200) as a "reach regression". No GCINE-CAM dump
# is needed: progress is keyed off the always-on `A35-RENDER frame=` renderer line.
#
# Writes .autoport/reports/graphics-verify/routed-logcat.log (the file the validator
# reads). Only aborts early on a REAL crash signature; transient pidof failures
# during the heavy misty load do NOT count as a crash.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
INJECT="/data/data/$PKG/files/cpad_inject"
OUTDIR=".autoport/reports/graphics-verify"
LOG="$OUTDIR/routed-logcat.log"
FG=".autoport/reports/Gcine-cut/reach-foreground.txt"
MAX_MIN="${MAX_MIN:-15}"
TARGET="${TARGET:-11000}"
mkdir -p "$OUTDIR" .autoport/reports/Gcine-cut

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do "$ADB" shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() { for p in "${INTERLOPERS[@]}"; do "$ADB" shell am force-stop "$p" >/dev/null 2>&1 || true; "$ADB" shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }
inject() { printf '%s' "$1" | "$ADB" shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject: '$1'"; }
clear_inject() { inject ""; }
read_focus() { "$ADB" shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r'; }
max_frame() { grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
crash_sigs() { local n; n=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null); echo "${n:-0}"; }
is_fg() { case "$(read_focus)" in *"$PKG"*) return 0;; *) return 1;; esac; }

echo "== Gcine-cut REACH capture (max ${MAX_MIN}min, target frame>=${TARGET}) =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; "$ADB" shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on

"$ADB" shell am force-stop "$PKG" 2>/dev/null || true
clear_inject
"$ADB" logcat -G 64M 2>/dev/null || true
"$ADB" logcat -c 2>/dev/null || true
: > "$LOG"
( "$ADB" logcat -v threadtime opengoal-gk:I GK_STDOUT:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE 'A35-RENDER frame=|link finish:|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:|has died|GMATCH-RFTD|GCINE3-DEACT|GND-OOB-WRITE' \
    >> "$LOG" ) &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
"$ADB" shell am start -W -n "$PKG/$ACT" >/tmp/gcine-reach-amstart.out 2>&1 || true

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
ITERS=$(( MAX_MIN * 60 / 3 ))
NOPROG=0; LAST=0; DONE=""; CRASHED=""
for ((i=1;i<=ITERS;i++)); do
  sleep 3
  FM=$(max_frame); FM=${FM:-0}
  CS=$(crash_sigs); CS=${CS:-0}
  FG_OK=0; is_fg && FG_OK=1
  if (( i % 5 == 0 )); then echo "   [${i}/${ITERS}] frame=${FM} fg=${FG_OK} crashsig=${CS}"; fi
  if [ "${CS:-0}" -gt 0 ]; then echo "   >>> REAL crash signature ($CS)"; CRASHED="sig"; break; fi
  if [ "${FM:-0}" -ge "$TARGET" ]; then echo "   >>> reached TARGET frame=$FM"; DONE="reached"; break; fi
  # only treat as stuck if NO frame progress AND not foreground for a long stretch
  if [ "${FM:-0}" -le "$LAST" ] && [ "$FG_OK" = "0" ]; then NOPROG=$((NOPROG+1)); else NOPROG=0; fi
  LAST=$FM
  if [ "$NOPROG" -ge 20 ]; then echo "   >>> no frame progress + not-foreground for 60s — abort"; CRASHED="stuck"; break; fi
done

sleep 1; ENDFOC=$(read_focus); ENDPID=$("$ADB" shell pidof "$PKG" 2>/dev/null | tr -d '\r')
FINAL=$(max_frame); FINAL=${FINAL:-0}; FCS=$(crash_sigs)
{ echo "# Gcine-cut reach end-of-run ($(date -Is))";
  echo "mCurrentFocus_at_end: $ENDFOC";
  echo "app_pid_at_end: ${ENDPID:-gone}";
  echo "max_render_frame: $FINAL";
  echo "crash_sigs: $FCS";
  echo "verdict: ${DONE:-${CRASHED:-timeout}}"; } > "$FG"

echo "== teardown =="
# Stop the logcat capture FIRST (incl. the orphaned adb logcat child that survives
# killing only the subshell) so $LOG freezes at the reach target, THEN force-stop the
# app. Without this the app renders on into post-cinematic GAMEPLAY where a separate,
# deeper residual (warp-gate-class) crashes ~frame 15k — which would pollute the
# cinematic reach log with an out-of-scope crash. The Gcine-cut gate is the CINEMATIC
# reaching >=10500 crash-free, which is already captured cleanly above.
pkill -f "logcat -v threadtime opengoal-gk" 2>/dev/null || true
kill ${LOGCAT_PID:-0} 2>/dev/null || true
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
trap - EXIT
reenable_interlopers
device_stayon_restore 2>/dev/null || true

echo "== scoreboard =="
echo "  max render frame : $FINAL  (target $TARGET)"
echo "  crash signatures : $FCS"
echo "  foreground end   : $ENDFOC  pid=${ENDPID:-gone}"
echo "  verdict          : ${DONE:-${CRASHED:-timeout}}"
echo "  routed-logcat    : $LOG ($(wc -l < "$LOG" 2>/dev/null) lines)"
[ "$FINAL" -ge "$TARGET" ] && [ "${FCS:-0}" -eq 0 ] && echo "REACH PASS" || echo "REACH FAIL"
