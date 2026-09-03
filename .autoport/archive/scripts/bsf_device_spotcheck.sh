#!/usr/bin/env bash
# bsf_device_spotcheck.sh — Grecharged-buildsys-flags deliverable-4 device proof:
# DEFAULT (no-flags) android build boots clean 90s + menu captures proving the
# flagged rows are ABSENT (graphics page: no VULKAN RENDERER row; recharged page:
# no RECHARGED HUD row, no ENHANCED MODELS row, no GRASS OVERHANG row) while the
# validated features (grass settings, AO) are PRESENT. Screenshot every nav step;
# foreground + crash-scan asserts per feedback_crash_capture_window /
# feedback_device_screencap_foreground_check. Non-destructive: no edits committed.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
SERIAL=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-buildsys-flags/device-spotcheck; mkdir -p "$OUT"
LOGF="$OUT/spotcheck-log.txt"; : > "$LOGF"
say(){ echo "$*" | tee -a "$LOGF"; }
adbx(){ "$ADB" -s "$SERIAL" "$@"; }
inject(){ printf '%s' "$1" | adbx shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.4; inject ""; sleep "${2:-0.9}"; }
shot(){ adbx exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; local f; f=$(adbx shell dumpsys window 2>/dev/null | grep -i mCurrentFocus | head -1 | tr -d '\r'); say "  [shot $1] $(stat -c %s "$OUT/$1.png" 2>/dev/null || echo 0)B focus=$f"; }

# NOTE: do NOT include this script's own name in the pattern — the invoking
# wrapper shell's command line contains it too and can't be excluded by PID.
LEFT=$(pgrep -af 'gjak2|f1d_run|gtf_|capture_device|ao_menu' | grep -v $$ | grep -v grep || true)
[ -n "$LEFT" ] && { say "LEFTOVER RUNNERS — aborting: $LEFT"; exit 3; }

adbx shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
adbx shell svc power stayon true >/dev/null 2>&1
say "== fresh boot (default flag-set build) =="
adbx shell am force-stop $PKG; sleep 2; inject ""
adbx logcat -c 2>/dev/null || true
adbx shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
T0=$(date +%s)
sleep 90
PID=$(adbx shell pidof $PKG | tr -d '\r ')
[ -n "$PID" ] || { say "FAIL: app dead at t+90s"; adbx logcat -d | grep -aE 'FATAL|SIGSEGV|SIGILL|SIGABRT' | tail -8 | tee -a "$LOGF"; exit 4; }
FOC=$(adbx shell dumpsys window 2>/dev/null | grep -i mCurrentFocus | head -1 | tr -d '\r')
echo "$FOC" | grep -q "$PKG" || { say "FAIL: not foreground at t+90s: $FOC"; exit 5; }
CR=$(adbx logcat -d 2>/dev/null | grep -a "Fatal signal" | grep -aE "pid $PID|pid: $PID" || true)
[ -z "$CR" ] && CR=$(adbx logcat -d 2>/dev/null | grep -aE "FATAL EXCEPTION.*$PKG" || true)
[ -n "$CR" ] && { say "FAIL: crash in 90s window: $CR"; exit 6; }
MARK=$(adbx exec-out run-as $PKG cat files/cgo/jak1/GAME.CGO 2>/dev/null | grep -a -o 'ogflags:[a-zA-Z0-9:_.-]*' | head -1)
say "BOOT OK: pid=$PID foreground, 0 fatal signals in 90s; device GAME.CGO marker=$MARK"
shot 00-title-90s

say "== nav: title -> OPTIONS -> GRAPHIC OPTIONS =="
tapb start 2.5; shot 01-title-menu
tapb down 0.7; tapb down 0.7; tapb x 2.0; shot 02-options
tapb down 0.8; tapb x 2.0; shot 03-graphics-top
say "== graphics page: capture every row (expect NO 'VULKAN RENDERER' row) =="
for i in 1 2 3 4 5 6 7 8 9 10 11; do tapb down 0.5; shot "04-gfx-row$i"; done
say "== re-enter graphics top, 7x down -> RECHARGED SETTINGS, X =="
tapb triangle 1.2; shot 05-back-options
tapb x 2.0
for i in 1 2 3 4 5 6 7; do tapb down 0.5; done
shot 06-recharged-highlight
tapb x 2.0; shot 07-recharged-top
say "== recharged page: capture every row (expect NO hud/enhanced-models/grass-overhang rows; grass + AO present) =="
for i in 1 2 3 4 5 6 7 8 9 10; do tapb down 0.5; shot "08-rch-row$i"; done

PID2=$(adbx shell pidof $PKG | tr -d '\r ')
[ -n "$PID2" ] && [ "$PID2" = "$PID" ] || { say "FAIL: app died/restarted during menu nav (pid $PID -> ${PID2:-dead})"; exit 7; }
CR2=$(adbx logcat -d 2>/dev/null | grep -a "Fatal signal" | grep -aE "pid $PID|pid: $PID" || true)
[ -n "$CR2" ] && { say "FAIL: crash during nav: $CR2"; exit 8; }
say "SPOTCHECK PASS: 90s clean boot + menu captures at $OUT (pid stable $PID, foreground, 0 fatal signals)"
inject ""
adbx shell am force-stop $PKG
