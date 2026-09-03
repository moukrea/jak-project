#!/usr/bin/env bash
# gmenu_sprcap.sh — capture-only (libgk already deployed). Boot to title (a progress
# screen), harvest GK-SPR3 (renderer per-sprite px/py + consumed mtx index + user-hvdf
# uhx/uhy), then press START and harvest again. Localizes the menu-texture bunch:
#   mtx=1..34 + uhx/uhy spread + px/py spread  => placed correctly (NOT bunched)
#   mtx=1..34 + uhx/uhy=0                       => user-hvdf content/upload broken (arm64)
#   mtx=0 at renderer                           => copy lost downstream / renderer reads wrong field
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="/home/emeric/Android/platform-tools/adb"
S=eae4df44
PKG=org.opengoal.gk.jak1
ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Gmenu-textures
LOG="$OUT/sprcap.log"
SUM="$OUT/sprcap-summary.txt"
RUNLOG="$OUT/sprcap-run.log"
mkdir -p "$OUT"
exec > >(tee "$RUNLOG") 2>&1
A(){ "$ADB" -s $S "$@"; }
say(){ echo "[$(date +%H:%M:%S)] $*"; }
inject(){ printf '%s' "$1" | A shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
sigs(){ local n; n=$(grep -acE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" 2>/dev/null); echo "${n:-0}"; }

A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
A shell svc power stayon true >/dev/null 2>&1 || true
A shell am force-stop $PKG >/dev/null 2>&1 || true
clr
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c >/dev/null 2>&1 || true
: > "$LOG"
GREP='GK-SPR3 mode=|GMENU-ALLOC|A35-RENDER frame=|link finish: logo|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:'
( A logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE "$GREP" >> "$LOG" ) &
LCPID=$!
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

say "boot: waiting for title (frame>=1500, up to 180s)"
for ((i=1;i<=60;i++)); do
  sleep 3; FM=$(maxframe); FM=${FM:-0}; CS=$(sigs)
  (( i % 5 == 0 )) && say "  [boot ${i}] frame=$FM sigs=$CS spr3=$(grep -ac 'GK-SPR3 mode=2' "$LOG" 2>/dev/null)"
  [ "$CS" -gt 0 ] && { say "  crash sigs=$CS"; break; }
  [ "$FM" -ge 1500 ] && { say "  title frame=$FM"; break; }
done
say "hold title 15s harvesting GK-SPR3"; sleep 15
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
say "press START -> main/options menu, hold 25s"
inject "start"; sleep 2; clr; sleep 1
for ((s=0;s<25;s+=5)); do
  sleep 5; A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  say "  [+${s}s] spr3_hud=$(grep -ac 'GK-SPR3 mode=2' "$LOG" 2>/dev/null) frame=$(maxframe) sigs=$(sigs)"
  inject "down"; sleep 0.4; inject "up"; sleep 0.4; clr
done

kill ${LCPID:-0} 2>/dev/null || true
pkill -f "logcat -v threadtime GK_STDOUT" 2>/dev/null || true
FINAL=$(maxframe); FINAL=${FINAL:-0}; FCS=$(sigs)
A shell am force-stop $PKG >/dev/null 2>&1 || true
{
echo "# Gmenu-textures GK-SPR3 device dump $(date -Is)"
echo "device=$S reached_frame=$FINAL crash_sigs=$FCS"
echo
echo "## GK-SPR3 mode=2 (ModeHUD) distinct sprites: px py = on-screen pos, mtx = matrix index, uhx uhy = user-hvdf offset"
grep -aoE 'GK-SPR3 mode=2 .*' "$LOG" 2>/dev/null | sort -u
echo
echo "## mtx histogram (consumed matrix index at draw; mtx=0 => sprite uses global hud offset = center)"
grep -aoE 'GK-SPR3 mode=2 .*mtx=-?[0-9]+' "$LOG" 2>/dev/null | grep -aoE 'mtx=-?[0-9]+' | sort -t= -k2 -n | uniq -c
echo
echo "## px (on-screen X) distinct values for HUD sprites (spread vs bunched)"
grep -aoE 'GK-SPR3 mode=2 idx=[0-9]+ px=-?[0-9.]+' "$LOG" 2>/dev/null | grep -aoE 'px=-?[0-9.]+' | sort -u
echo
echo "## uhx (user-hvdf X) distinct values (the per-sprite hud offset that positions the sprite)"
grep -aoE 'uhx=-?[0-9.]+' "$LOG" 2>/dev/null | sort -u
echo
echo "## mode=0 (Mode2D) distinct sprites"
grep -aoE 'GK-SPR3 mode=0 .*' "$LOG" 2>/dev/null | sort -u | head -40
echo
echo "## crash signatures"
grep -aiE 'GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:' "$LOG" 2>/dev/null | tail -6
} | tee "$SUM"
say "DONE. summary=$SUM log=$LOG"
