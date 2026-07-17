#!/bin/bash
# goverhang7_x86_beach.sh — Grecharged-grass-overhang7 STEP-2 desktop sanity: the round-7 fix
# extends the grass system to Sentinel Beach (the owner's real vantage — his session publishes
# beach crates 214/216/219). Two x86 boots at his spot, overhang ON vs OFF, 3 shots each +
# placement census lines. Modeled on hd2_x86_ab.sh (goalc fifo listener + (pc-screen-shot)).
set -u
cd "$(git rev-parse --show-toplevel)"
OUT=/tmp/gov7_x86
DEST=".autoport/reports/Grecharged-grass-overhang7/x86-beach"
SHOTDIR="build/game/OpenGOAL/jak1/screenshots"
SETTINGS="build/game/OpenGOAL/jak1/settings/settings.ini"
POS="${POS_OVERRIDE:--90 22 -268}"   # ~10m from the owner's published crates (-79,21,-276)
mkdir -p "$OUT" "$DEST" "$SHOTDIR"

pkill -f 'build/game/gk' 2>/dev/null; sleep 1
pkill -f 'goalc --user-auto' 2>/dev/null; sleep 1

set_key(){ # key value  — replace-or-insert (INI form)
  local k="$1" v="$2"
  if grep -q "^$k = " "$SETTINGS"; then
    sed -i "s/^$k = .*/$k = $v/" "$SETTINGS"
  else
    sed -i "s/^\[settings\]/[settings]\n$k = $v/" "$SETTINGS"
  fi
  grep -q "^$k = $v" "$SETTINGS" || { echo "KEY INJECT FAILED: $k"; exit 9; }
}

# Mirror the OWNER's file: grass ON, precomputed ON, density 150, near 30, card 95.
set_key "recharged-grass?" "#t"
set_key "recharged-grass-precomputed?" "#t"
set_key "recharged-grass-density" "150.0000"
set_key "recharged-grass-near-dist" "30.0000"
set_key "recharged-grass-card-dist" "95.0000"

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

run_one(){ # $1 on|off
  local TAG="beach-$1"
  echo "== RUN $TAG (pos $POS) =="
  [ -n "$GK_PID" ] && { kill -INT "$GK_PID" 2>/dev/null; sleep 3; kill "$GK_PID" 2>/dev/null; GK_PID=""; }
  pkill -f 'build/game/gk' 2>/dev/null; sleep 2
  set_key "recharged-grass-overhang?" "$([ "$1" = on ] && echo '#t' || echo '#f')"
  local LOG="$DEST/gk-$TAG.log"
  DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 \
  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
  OG_LEVEL_WARP=beach-start OG_LEVEL_WARP_POS="$POS" \
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
  local c=0
  for i in 1 2 3 4 5 6; do
    snd '(lt)' 4
    grep -qa "Socket connected established" "$OUT/goalc.log" && { c=1; break; }
  done
  [ "$c" = 1 ] || echo "  $TAG: listener connect FAILED (shots will be missing)"
  sleep 12
  shot "$TAG-1"; sleep 4; shot "$TAG-2"; sleep 4; shot "$TAG-3"
  echo "  --- placement census $TAG ---"
  grep -a "PLACE-TIME\|GOVERHANG6 zones\|STATIC place\|PRECOMPUTED unavailable" "$LOG" | tail -6 | cut -c1-300 | sed 's/^/  /'
  : > "$OUT/goalc.log"
  return 0
}

run_one on
run_one off
echo "== ALL RUNS DONE =="
