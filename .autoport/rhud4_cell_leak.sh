#!/usr/bin/env bash
# rhud4_cell_leak.sh — focused round-4 tests, each with a FRESH warp to the OPEN beach
# (game-start) so Jak isn't buried in the cave:
#   CELL: spawn fuel cells right ON Jak (0,0.8,0) so he collects them -> does the HUD
#         fuel-cell BODY render, or only the glow? (owner obs #2)
#   LEAK: spawn green eco FAR (7m) so the pills' own effects are away from Jak; collect a
#         few -> is the green HUD particle ONLY by the heart (screen space, FIXED) or are
#         there stray green particles near Jak in WORLD space (owner obs #5 leak)?
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-hud-jak1/round4; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
setp(){ adb shell "setprop $1 '$2'"; }
getp(){ adb shell "getprop $1" | tr -d '\r'; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$OUT/device-$1.png" 2>/dev/null; echo "    shot device-$1.png ($(stat -c%s "$OUT/device-$1.png" 2>/dev/null||echo 0) B) fg=$(fg)"; }
warp(){ adb shell am force-stop $PKG >/dev/null 2>&1 || true; adb logcat -c >/dev/null 2>&1 || true;
  setp debug.opengoal.f1.warp 1; setp debug.opengoal.eco.spawn "$1"; echo "  eco.spawn=$(getp debug.opengoal.eco.spawn)";
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true; echo "  warping, settle ${2:-85}s..."; sleep "${2:-85}"; echo "  fg=$(fg)"; }
record(){ adb shell "screenrecord --time-limit $2 --bit-rate 8000000 /sdcard/rl-$1.mp4" & local rp=$!; sleep 1; shift 2; "$@"; wait $rp 2>/dev/null || sleep 2;
  adb pull "/sdcard/rl-$1.mp4" "$OUT/rl-$1.mp4" >/dev/null 2>&1; }
# collection wiggle (small, stays in the open)
wig(){ for i in 1 2 3 4 5; do inject "ly=0.3"; sleep 1.0; clr; sleep 0.3; inject "lx=0.3"; sleep 0.8; clr; sleep 0.3; done; }

adb get-state >/dev/null 2>&1 || { echo "no device"; exit 1; }
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb shell svc power stayon true >/dev/null 2>&1 || true

echo "=== CELL TEST (fresh warp, cells on Jak) ==="
warp "6 90 0.0 0.8 0.0" 85
adb shell "screenrecord --time-limit 26 --bit-rate 8000000 /sdcard/rl-cell.mp4" & RP=$!
sleep 1; wig; wait $RP 2>/dev/null || sleep 2
adb pull /sdcard/rl-cell.mp4 "$OUT/rl-cell.mp4" >/dev/null 2>&1 && echo "  pulled rl-cell.mp4 ($(stat -c%s "$OUT/rl-cell.mp4" 2>/dev/null||echo 0) B)"
shot cell2-still
adb logcat -d -v brief 2>/dev/null | grep -aE 'ECO-SPAWN|fuel|cell|CELL' | tail -8 > "$OUT/cell2-logcat.txt" || true

echo "=== LEAK TEST (fresh warp, green eco FAR 7m) ==="
warp "4 60 7.0 1.0 7.0" 85
adb shell "screenrecord --time-limit 24 --bit-rate 8000000 /sdcard/rl-leak.mp4" & RP=$!
sleep 1; wig; wait $RP 2>/dev/null || sleep 2
adb pull /sdcard/rl-leak.mp4 "$OUT/rl-leak.mp4" >/dev/null 2>&1 && echo "  pulled rl-leak.mp4 ($(stat -c%s "$OUT/rl-leak.mp4" 2>/dev/null||echo 0) B)"
shot leak-still

setp debug.opengoal.eco.spawn ""
echo "[rhud4-cell-leak] DONE fg=$(fg)"
ls -la "$OUT"/rl-*.mp4 2>/dev/null
