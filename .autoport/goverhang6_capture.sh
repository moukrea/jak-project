#!/usr/bin/env bash
# goverhang6_capture.sh — Grecharged-grass-overhang6 device evidence (serial eae4df44).
# Based on the PROVEN goverhang5_capture.sh. Adds: per-run focus check DURING recording,
# GOVERHANG6 census verification, EDGE side-pan aim, and a SCANPROOF run that flips
# recharged-grass-precomputed? #f to force the on-device LIVE scan path.
#
# Usage:  RUN=terr_on bash .autoport/goverhang6_capture.sh
#         RUN one of: terr_on terr_off edge_on edge_off scanproof
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=".autoport/reports/Grecharged-grass-overhang6"; mkdir -p "$OUT"
EXT=/storage/emulated/0/OpenGOAL/jak1/settings.ini
INT=/storage/emulated/0/OpenGOAL/jak1/settings.ini
say(){ echo; echo "######## $* ########"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null >/dev/null 2>&1; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.7}"; }
focus(){ $ADB shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

TERR="-1310.2 52.8 989.0"
EDGE="-1324.5 52.2 973.9"

# --- generic settings symbol flipper: $1=symbol $2=t|f (INI form, sole external file) ---
set_sym(){ local SYM="$1" V="$2"
  $ADB shell "sed -i 's/^$SYM = #[tf]/$SYM = #$V/' $EXT" >/dev/null 2>&1
}
set_overhang(){ # $1=t|f — keep grass ON
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  set_sym 'recharged-grass?' t
  set_sym 'recharged-grass-overhang?' "$1"
  echo "  overhang set #$1: ext=$($ADB shell grep -E 'recharged-grass-overhang\?' $EXT 2>/dev/null | tr -d '\r')"
}
set_precompute(){ # $1=t|f  (copy of set_overhang's sed pattern for the precomputed symbol)
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  set_sym 'recharged-grass-precomputed?' "$1"
  echo "  precomputed set #$1: ext=$($ADB shell grep -E 'recharged-grass-precomputed\?' $EXT 2>/dev/null | tr -d '\r')"
}

boot_warp(){ local POS="$1" LOG="$2" TRY ok
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
    stick neutral
    $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1 </dev/null
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1 </dev/null
    $ADB logcat -b all -c >/dev/null 2>&1
    kill "$(cat /tmp/g6_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/g6_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
    local t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 140 ]; do
      grep -qa "LEVEL-WARP-SPAWN name=training-start" "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|GK-DIAG pc\+0 @ 0x7f00000000' "$LOG" && { echo "  try#$TRY CRASH"; break; }
      sleep 3
    done
    if [ "$ok" = 1 ]; then
      local F=$(focus)
      echo "  try#$TRY warp_ok focus=$F"
      if echo "$F" | grep -q "$PKG"; then sleep 12; return 0
      else echo "  try#$TRY WRONG FOCUS (launcher/other up) — retry"; fi
    fi
  done
  return 1; }

# aim: terrace look-down + light pan (matches v5 do_aim)
aim_terr(){
  sleep 1
  pulse "rx=150" 1.0 0.6
  pulse "ry=120" 0.7 0.5
  stick neutral; sleep 1
  pulse "rx=140" 0.9 0.6
  stick neutral; sleep 1
}
# aim: pitch DOWN hard at the lip, then slow side pan sweep
aim_edge(){
  sleep 1
  pulse "ry=150" 1.2 0.6      # pitch camera down at the lip
  pulse "ry=110" 0.6 0.5
  stick neutral; sleep 1
  pulse "rx=90"  1.4 0.6      # slow side pan sweep
  pulse "rx=90"  1.4 0.6
  stick neutral; sleep 1
}

rec(){ local NAME="$1" AIMFN="$2" SECS="${3:-10}"
  $ADB shell rm -f /sdcard/${NAME}.mp4 >/dev/null 2>&1
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 12000000 /sdcard/${NAME}.mp4 >/dev/null 2>&1 &
  local RP=$!
  # focus DURING recording
  sleep 2; echo "  focus-during-rec=$(focus)" | tee -a "$OUT/${NAME}.focus"
  $AIMFN
  wait $RP 2>/dev/null || true
  sleep 1; $ADB pull /sdcard/${NAME}.mp4 "$OUT/${NAME}.mp4" >/dev/null 2>&1
  $ADB shell rm -f /sdcard/${NAME}.mp4 >/dev/null 2>&1
  mkdir -p "$OUT/${NAME}_frames"; rm -f "$OUT/${NAME}_frames"/*.png
  ffmpeg -y -loglevel error -i "$OUT/${NAME}.mp4" -vf fps=2 "$OUT/${NAME}_frames/f_%03d.png" 2>/dev/null
  echo "  rec $NAME: frames=$(ls "$OUT/${NAME}_frames" 2>/dev/null | wc -l)"; }

census(){ grep -a "GOVERHANG6 zones:" "$1" | tail -1 | tr -d '\r'; }

case "$RUN" in
 terr_on)
   say "RUN1 TERR ON ($TERR)"
   set_overhang t
   boot_warp "$TERR" "$OUT/terr_on-logcat.log" || { echo "[FAIL] terr_on boot"; exit 1; }
   census "$OUT/terr_on-logcat.log"
   rec terr_on aim_terr 10 ;;
 terr_off)
   say "RUN2 TERR OFF ($TERR)"
   set_overhang f
   boot_warp "$TERR" "$OUT/terr_off-logcat.log" || { echo "[FAIL] terr_off boot"; exit 1; }
   census "$OUT/terr_off-logcat.log"
   rec terr_off aim_terr 10 ;;
 edge_on)
   say "RUN3 EDGE ON ($EDGE)"
   set_overhang t
   boot_warp "$EDGE" "$OUT/edge_on-logcat.log" || { echo "[FAIL] edge_on boot"; exit 1; }
   census "$OUT/edge_on-logcat.log"
   rec edge_on aim_edge 12 ;;
 edge_off)
   say "RUN4 EDGE OFF ($EDGE)"
   set_overhang f
   boot_warp "$EDGE" "$OUT/edge_off-logcat.log" || { echo "[FAIL] edge_off boot"; exit 1; }
   census "$OUT/edge_off-logcat.log"
   rec edge_off aim_edge 12 ;;
 scanproof)
   say "RUN5 SCANPROOF — overhang ON, precomputed #f (LIVE scan), warp TERR"
   set_overhang t
   set_precompute f
   boot_warp "$TERR" "$OUT/scanproof-logcat.log" || { echo "[FAIL] scanproof boot"; set_precompute t; exit 1; }
   echo "  PLACE-TIME: $(grep -a 'PLACE-TIME mode=' "$OUT/scanproof-logcat.log" | tail -1 | tr -d '\r')"
   echo "  TRUE-RIM:   $(grep -a 'true-rim edge segments collected' "$OUT/scanproof-logcat.log" | tail -1 | tr -d '\r')"
   census "$OUT/scanproof-logcat.log"
   rec scanproof aim_terr 10
   set_precompute t
   echo "  RESTORED precomputed: $($ADB shell grep -E 'recharged-grass-precomputed\?' $EXT 2>/dev/null | tr -d '\r')" ;;
 *) echo "unknown RUN=$RUN"; exit 2 ;;
esac
say "RUN $RUN done"
