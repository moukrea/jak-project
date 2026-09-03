#!/usr/bin/env bash
# rhud4_final_capture.sh — ROUND 4 final device evidence on the cell-fix build (eae4df44).
# Parts (each a FRESH warp to the open beach for reliable collection / open camera):
#   M. MENU: Recharged Settings row (before Advanced) + toggle + persist
#   A. GREEN: heart pop + green particle by heart + counter (recharged ON)
#   B. GAUGE: blue/red/yellow fill + center particle (per type)
#   C. CELL:  spawn cells ON Jak while standing still -> does the BODY render now?
#   D. OFF==STOCK: recharged #f, same green collect -> stock HUD (A/B vs part A)
#   E. LEAK: green collect then STOP eco -> heart shows, watch for stray world particles
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
SETF="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
OUT=.autoport/reports/Grecharged-hud-jak1/round4/final; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
setp(){ adb shell "setprop $1 '$2'"; }
getp(){ adb shell "getprop $1" | tr -d '\r'; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$OUT/device-$1.png" 2>/dev/null; echo "    shot device-$1.png ($(stat -c%s "$OUT/device-$1.png" 2>/dev/null||echo 0) B) fg=$(fg)"; }
setflag(){ # $1 = #t or #f
  adb shell run-as $PKG cat "$SETF" 2>/dev/null | tr -d '\r' > /tmp/rhud4-set.gc
  sed -i "s/^recharged-hud? = #[tf]/recharged-hud? = $1/" /tmp/rhud4-set.gc
  adb push /tmp/rhud4-set.gc /data/local/tmp/rhud4-set.gc >/dev/null 2>&1
  adb shell run-as $PKG cp /data/local/tmp/rhud4-set.gc "$SETF" >/dev/null 2>&1
  echo "  flag now: $(adb shell run-as $PKG cat "$SETF" 2>/dev/null | grep -a recharged | tr -d '\r')"
}
warp(){ # $1 eco.spawn string  $2 settle
  adb shell am force-stop $PKG >/dev/null 2>&1 || true; adb logcat -c >/dev/null 2>&1 || true
  setp debug.opengoal.f1.warp 1; setp debug.opengoal.eco.spawn "$1"; echo "  eco.spawn=$(getp debug.opengoal.eco.spawn)"
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true; echo "  warp settle ${2:-85}s"; sleep "${2:-85}"; echo "  fg=$(fg)"; }
rec(){ adb shell "screenrecord --time-limit $2 --bit-rate 8000000 /sdcard/f-$1.mp4" & local rp=$!; sleep 1; shift 2; "$@"; wait $rp 2>/dev/null || sleep 2; adb pull "/sdcard/f-$1.mp4" "$OUT/f-$1.mp4" >/dev/null 2>&1 && echo "  pulled f-$1.mp4 ($(stat -c%s "$OUT/f-$1.mp4" 2>/dev/null||echo 0) B)"; }
wig(){ for i in 1 2 3 4 5; do inject "ly=0.35"; sleep 1.1; clr; sleep 0.3; inject "lx=0.35"; sleep 0.9; clr; sleep 0.3; done; }
stand(){ sleep "${1:-20}"; }

adb get-state >/dev/null 2>&1 || { echo "no device"; exit 1; }
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true; adb shell svc power stayon true >/dev/null 2>&1 || true
adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && { echo "DEVICE_LOCKED"; exit 1; }

echo "###### M. MENU (recharged ON already) ######"
setflag '#t'
adb shell am force-stop $PKG >/dev/null 2>&1 || true; setp debug.opengoal.f1.warp 0; setp debug.opengoal.eco.spawn ""
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true; echo "  menu boot settle 55s"; sleep 55
tapb(){ inject "$1"; sleep 0.4; clr; sleep "${2:-0.7}"; }
tapb start 2.2; tapb down; tapb down; tapb x 2.0; tapb down; tapb x 2.0
for i in 1 2 3 4 5 6 7 8; do tapb down 0.5; done
shot M1-recharged-row
tapb x 1.6; shot M2-submenu-toggle
tapb down 0.8; tapb x 1.4; shot M3-back

echo "###### A. GREEN (recharged ON): heart+particle+counter ######"
warp "4 45 0.3 0.3 0.3" 85
rec green 22 wig
shot A-green

echo "###### B. GAUGE per type ######"
warp "3 45 0.3 0.3 0.3" 80; rec blue 16 wig; shot B-blue
setp debug.opengoal.eco.spawn "2 45 0.3 0.3 0.3"; sleep 3; rec red 14 wig; shot B-red
setp debug.opengoal.eco.spawn "1 45 0.3 0.3 0.3"; sleep 3; rec yellow 14 wig; shot B-yellow

echo "###### C. CELL body (spawn AT Jak exactly, stand still -> guaranteed trigger overlap) ######"
warp "6 50 0.0 0.0 0.0" 85
# also try nudging onto the falling cells in case exact-overlap doesn't auto-collect
rec cell 26 wig; shot C-cell
adb logcat -d -v brief 2>/dev/null | grep -aE 'ECO-SPAWN|fuel|cell|pickup' | tail -10 > "$OUT/cell-collect-logcat.txt" || true

echo "###### D. OFF == STOCK (recharged #f), same green ######"
setflag '#f'
warp "4 45 0.3 0.3 0.3" 85; rec offgreen 18 wig; shot D-off-green
setflag '#t'

echo "###### E. LEAK: green collect then STOP eco ######"
warp "4 45 0.3 0.3 0.3" 85
inject "ly=0.35"; sleep 2; clr
setp debug.opengoal.eco.spawn ""    # stop spawning; heart stays ~2s, group still spawns
rec leak 12 stand 11
shot E-leak

echo "###### harvest ######"
adb logcat -d -v threadtime 2>/dev/null | grep -aE 'ECO-SPAWN|recharged|Fatal signal|sig=11|sig=6|signal 11|signal 6' > "$OUT/final-logcat.txt" || true
echo "  crash sigs: $(grep -acE 'Fatal signal|sig=11|sig=6|signal 11|signal 6' "$OUT/final-logcat.txt" || echo 0)"
setp debug.opengoal.eco.spawn ""; setflag '#t'
echo "[rhud4-final] DONE fg=$(fg)"; ls -la "$OUT"/f-*.mp4 "$OUT"/device-*.png 2>/dev/null | tail -20
