#!/bin/bash
# hd2_x86_ab.sh — Grecharged-hd-models2 attempt 3: x86 ON/OFF A/B with OBJECTIVE
# loaded-model discriminators (owner challenge 2026-07-14):
#   1. HD-MODELS fr3-select lines  (which fr3 file each level load actually read)
#   2. HD-MODELS merc-load lines   (per-model tri counts at load — HD is several x stock)
#   3. GJ2VIS-MERCMODEL lines      (model actually DRAWN in the same run)
#   4. HD-MODELS toggle push lines (any mid-run flag flip is evidence, not mystery)
# 4 boots: {samos,keira} x {off,on}, same vantage per pair -> unambiguous ON/OFF pairs.
# Modeled on round2_x86_verify.sh (goalc fifo listener + (pc-screen-shot)).
set -u
cd "$(git rev-parse --show-toplevel)"
OUT=/tmp/hd2_ab
DEST=".autoport/reports/Grecharged-hd-models2/x86-ab"
SHOTDIR="build/game/OpenGOAL/jak1/screenshots"
SETTINGS="build/game/OpenGOAL/jak1/settings/settings.ini"
mkdir -p "$OUT" "$DEST" "$SHOTDIR"

pkill -f 'build/game/gk' 2>/dev/null; sleep 1
pkill -f 'goalc --user-auto' 2>/dev/null; sleep 1

set_toggle(){ # t|f — replace-or-insert (INI form, under the [settings] header)
  if grep -q "^recharged-enhanced-models? = " "$SETTINGS"; then
    sed -i "s/^recharged-enhanced-models? = #[tf]/recharged-enhanced-models? = #$1/" "$SETTINGS"
  else
    sed -i "s/^\[settings\]/[settings]\nrecharged-enhanced-models? = #$1/" "$SETTINGS"
  fi
  grep -q "^recharged-enhanced-models? = #$1" "$SETTINGS" || { echo "TOGGLE INJECT FAILED"; exit 9; }
  echo "  toggle in portable settings: $(grep -o '^recharged-enhanced-models? = #[tf]' "$SETTINGS")"
}

# goalc listener (for pc-screen-shot only — NO (mi): CGOs must stay as-committed)
rm -f "$OUT/fifo"; mkfifo "$OUT/fifo"
./build/goalc/goalc --user-auto < "$OUT/fifo" > "$OUT/goalc.log" 2>&1 &
GOALC_PID=$!
exec 3>"$OUT/fifo"
snd(){ echo "$1" >&3; sleep "${2:-1.5}"; }
GK_PID=""
finish(){ [ -n "$GK_PID" ] && { kill -INT "$GK_PID" 2>/dev/null; sleep 2; kill "$GK_PID" 2>/dev/null; }; kill "$GOALC_PID" 2>/dev/null; exec 3>&- 2>/dev/null; }
trap finish EXIT
sleep 3

shot(){
  local f="$SHOTDIR/screenshot.png" t=0
  rm -f "$f"
  snd '(pc-screen-shot)' 1
  while [ $t -lt 12 ]; do
    if [ -f "$f" ]; then sleep 0.6; cp "$f" "$DEST/$1.png"; echo "  shot $1 ($(stat -c%s "$DEST/$1.png") B)"; return 0; fi
    sleep 1; t=$((t+1))
  done
  echo "  shot $1 MISSING"; return 1
}

run_one(){ # $1 tag-prefix  $2 t|f  $3 "x y z"
  local TAG="$1-$([ "$2" = t ] && echo on || echo off)" TOG=$2 POS=$3
  echo "== RUN $TAG (pos $POS) =="
  [ -n "$GK_PID" ] && { kill -INT "$GK_PID" 2>/dev/null; sleep 3; kill "$GK_PID" 2>/dev/null; GK_PID=""; }
  pkill -f 'build/game/gk' 2>/dev/null; sleep 2
  set_toggle "$TOG"
  local LOG="$DEST/gk-$TAG.log"
  DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 \
  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 GJ2VIS_TFTREE=1 \
  OG_LEVEL_WARP=village1-hut OG_LEVEL_WARP_POS="$POS" \
  stdbuf -oL -eL ./build/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data out/jak1/iso -- -boot -debug-mem > "$LOG" 2>&1 &
  GK_PID=$!
  local deadline=$(( $(date +%s) + 240 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    kill -0 "$GK_PID" 2>/dev/null || { echo "  $TAG: GK EXITED EARLY"; tail -20 "$LOG"; return 1; }
    grep -qa "LEVEL-WARP-SPAWN" "$LOG" && break
    sleep 3
  done
  grep -qa "LEVEL-WARP-SPAWN" "$LOG" || { echo "  $TAG: NEVER SPAWNED"; return 1; }
  # connect listener to THIS gk instance
  local c=0
  for i in 1 2 3 4 5 6; do
    snd '(lt)' 4
    grep -qa "Socket connected established" "$OUT/goalc.log" && { c=1; break; }
  done
  [ "$c" = 1 ] || echo "  $TAG: listener connect FAILED (shots will be missing)"
  sleep 12
  shot "$TAG-1"; sleep 4; shot "$TAG-2"; sleep 4; shot "$TAG-3"
  # per-run discriminator dump
  echo "  --- discriminators $TAG ---"
  grep -a "HD-MODELS fr3-select" "$LOG" | sed 's/^/  /'
  grep -aE "HD-MODELS merc-load .*model=(eichar|sidekick|sage|assistant)-lod0" "$LOG" | sed 's/^/  /'
  grep -a "HD-MODELS toggle push" "$LOG" | sed 's/^/  /'
  grep -aE "GJ2VIS-MERCMODEL name=(eichar|sidekick|sage|assistant)" "$LOG" | sed 's/^/  /'
  echo "  link-finish-logo: $(grep -ac 'link finish: logo' "$LOG")"
  # truncate goalc log so next (lt) detection is fresh
  : > "$OUT/goalc.log"
  return 0
}

run_one samos f "-132.7 48 216.5"
run_one samos t "-132.7 48 216.5"
run_one keira f "-134.5 36 205.5"
run_one keira t "-134.5 36 205.5"
echo "== ALL RUNS DONE =="
