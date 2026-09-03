#!/usr/bin/env bash
# Gecho-pool x86 ORACLE capture: launch OUR build-x86 gk with the generic-draw
# census armed (OG_GECHO_GEN=1), connect goalc listener, trigger the NEW-GAME
# intro cinematic directly (initialize! ... "intro-start"), and harvest the
# GECHO-DRAW lines so we can see the dark-eco-pool's generic draw (by texture
# name) on the x86 oracle. Single-user desktop resource. Never pkill bare 'gk'.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ROOT="$(pwd)"

GK="$ROOT/build-x86/game/gk"
GOALC="$ROOT/build-x86/goalc/goalc"
[ -x "$GK" ] || GK="$ROOT/build/game/gk"
[ -x "$GOALC" ] || GOALC="$ROOT/build/goalc/goalc"
OUT="$ROOT/.autoport/reports/Gecho-pool"
LOG="$OUT/x86-cine-gecho.log"
GLOG="$OUT/x86-cine-goalc.log"
mkdir -p "$OUT"; : > "$LOG"; : > "$GLOG"

# --- X display autodetect (need a GL context) ---
export DISPLAY="${DISPLAY:-:0}"
if [ -z "${XAUTHORITY:-}" ]; then
  for x in /run/user/1000/.mutter-Xwaylandauth.* "$HOME/.Xauthority"; do
    [ -e "$x" ] && { export XAUTHORITY="$x"; break; }
  done
fi
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
echo "DISPLAY=$DISPLAY XAUTHORITY=${XAUTHORITY:-<none>} GK=$GK GOALC=$GOALC" | tee -a "$LOG"

echo "== launch gk with OG_GECHO_GEN=1 ==" | tee -a "$LOG"
OG_GECHO_GEN=1 "$GK" --game jak1 --portable --verbose --disable-ansi \
   -iso-data "$ROOT/out/jak1/iso" -- -boot -debug >> "$LOG" 2>&1 &
GK_PID=$!
trap 'kill -INT $GK_PID 2>/dev/null; sleep 2; kill -KILL $GK_PID 2>/dev/null; wait $GK_PID 2>/dev/null' EXIT
echo "  gk pid=$GK_PID"

echo "== wait for boot (link finish: logo) =="
dl=$(( $(date +%s) + 180 )); booted=0
while [ "$(date +%s)" -lt "$dl" ]; do
  kill -0 "$GK_PID" 2>/dev/null || { echo "  gk EXITED during boot; tail:"; tail -15 "$LOG"; exit 2; }
  grep -qE 'link finish: logo$|\*\*\*\* boot message ' "$LOG" 2>/dev/null && { booted=1; break; }
  sleep 2
done
[ "$booted" = 1 ] && echo "  booted" || echo "  WARN: boot marker not seen (continuing)"
sleep 8

echo "== goalc (lt): connect + (build-game) to intern symbols + trigger NEW GAME intro-start =="
# (build-game) compiles the game in goalc ONLY (interns *game-info* etc. in the
# compiler); it does NOT reload the already-running target. Without it the
# (initialize! *game-info* ...) form fails to compile ("symbol not found").
{
  printf '(lt)\n'; sleep 8
  printf '(build-game)\n'; sleep 120
  printf '(set! *debug-segment* #f)\n'; sleep 1
  printf "(initialize! *game-info* 'game (the-as game-save #f) \"intro-start\")\n"
  sleep 140
  printf '(:exit)\n'
} | "$GOALC" --game jak1 --user-auto >> "$GLOG" 2>&1 &
GOALC_PID=$!

echo "== capture window ~280s (build-game ~120s + cinematic ~140s) =="
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt 285 ]; do
  kill -0 "$GK_PID" 2>/dev/null || { echo "  gk EXITED at $(( $(date +%s) - t0 ))s"; break; }
  sleep 4
done
kill $GOALC_PID 2>/dev/null || true

echo "== goalc bind check =="
grep -aiE 'connect|listen|reset target|run-time' "$GLOG" | head -8 || true

echo ""
echo "############ GECHO-DRAW distinct (tex,mode) with max tris ############"
grep -a 'GECHO-DRAW' "$LOG" \
 | sed -E 's/draw=[0-9]+ //; s/idx=[0-9]+ //' \
 | awk '{ key=$0; sub(/tris=[0-9]+/,"",key); tris=$NF; sub(/tris=/,"",tris);
          if (tris+0 > max[key]) max[key]=tris+0 }
        END { for (k in max) printf "%s tris_max=%d\n", k, max[k] }' \
 | sort | tee "$OUT/x86-cine-gecho-distinct.txt"
echo ""
echo "############ lines mentioning water / eco / misty / ripple / darkeco ############"
grep -aiE 'GECHO-DRAW.*(water|eco|misty|ripple|darkeco|liquid|mud)' "$LOG" | sort -u | head -40 | tee "$OUT/x86-cine-gecho-pool.txt"
echo ""
echo "== buckets that ever appeared in GECHO-GEN =="
grep -a 'GECHO-GEN' "$LOG" | sed -E 's/verts=.*//' | sort -u | head -40

kill -INT $GK_PID 2>/dev/null || true; sleep 2; kill -KILL $GK_PID 2>/dev/null || true; wait $GK_PID 2>/dev/null || true
trap - EXIT
echo "== done. full log: $LOG ; distinct: $OUT/x86-cine-gecho-distinct.txt =="
