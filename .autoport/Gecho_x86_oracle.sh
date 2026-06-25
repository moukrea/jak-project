#!/usr/bin/env bash
# Gecho-pool x86 ORACLE. Durable progress log (survives buffering/kills). gk via
# nohup (gets GL under run_in_background). goalc heredoc: (lt) -> (build-game) to
# intern *game-info* -> trigger NEW-GAME intro. Harvest GECHO-DRAW for the pool.
set -o pipefail
cd "$(git rev-parse --show-toplevel)"
ROOT="$(pwd)"
OUT="$ROOT/.autoport/reports/Gecho-pool"; mkdir -p "$OUT"
P="$OUT/x86-oracle-progress.log"; L="$OUT/x86-oracle.log"; GL="$OUT/x86-oracle-goalc.log"
: > "$L"; : > "$GL"
GK="$ROOT/build-x86/game/gk"; GOALC="$ROOT/build-x86/goalc/goalc"
export DISPLAY="${DISPLAY:-:0}" SDL_VIDEODRIVER=x11
[ -n "${XAUTHORITY:-}" ] || for x in /run/user/1000/.mutter-Xwaylandauth.* "$HOME/.Xauthority"; do [ -e "$x" ] && { export XAUTHORITY="$x"; break; }; done
echo "[oracle] start DISPLAY=$DISPLAY XAUTH=${XAUTHORITY:-none}"

echo "[oracle] launch gk (OG_GECHO_GEN=1)"
OG_GECHO_GEN=1 nohup "$GK" --game jak1 --portable --disable-ansi -iso-data "$ROOT/out/jak1/iso" -- -boot -debug >> "$L" 2>&1 &
GK_PID=$!
echo "[oracle] gk pid=$GK_PID"

booted=0
for i in $(seq 1 90); do
  if grep -qaE 'kernel: machine started' "$L"; then echo "[oracle] BOOTED (poll $i)"; booted=1; break; fi
  kill -0 "$GK_PID" 2>/dev/null || { echo "[oracle] gk DIED in boot"; tail -8 "$L"; break; }
  sleep 2
done
[ "$booted" = 1 ] || { echo "[oracle] no boot marker; aborting"; kill -KILL "$GK_PID" 2>/dev/null; exit 2; }
sleep 4

echo "[oracle] drive goalc: (lt) -> (build-game) -> intro-start"
{
  echo '(lt)'; sleep 8
  echo '(build-game)'; sleep 170
  echo '(set! *debug-segment* #f)'; sleep 1
  echo "(initialize! *game-info* 'game (the-as game-save #f) \"intro-start\")"; sleep 90
  for k in 1 2 3 4 5 6; do
    echo "(format 0 \"GDUMP-OFF level0_off=~D name_off=~D index_off=~D stride=~D~%\" (- (the-as int (-> *level* data 0)) (the-as int *level*)) (- (the-as int (&-> (-> *level* data 0) name)) (the-as int (-> *level* data 0))) (- (the-as int (&-> (-> *level* data 0) index)) (the-as int (-> *level* data 0))) (- (the-as int (-> *level* data 1)) (the-as int (-> *level* data 0))))"
    sleep 1
    echo "(format 0 \"GDUMP-SYM misty=~D village1=~D intro=~D default=~D~%\" (the-as int 'misty) (the-as int 'village1) (the-as int 'intro) (the-as int 'default))"
    sleep 1
    echo "(format 0 \"GDUMP-LVLADDR levelglobal=~D~%\" (the-as int *level*))"
    sleep 10
  done
  echo '(:exit)'
} | nohup "$GOALC" --game jak1 --user-auto >> "$GL" 2>&1 &
GOALC_PID=$!

echo "[oracle] capture window; polling GECHO-DRAW"
for i in $(seq 1 260); do
  kill -0 "$GK_PID" 2>/dev/null || { echo "[oracle] gk DIED at poll $i"; break; }
  n=$(grep -aca 'GECHO-DRAW' "$L" 2>/dev/null); n=${n:-0}
  if [ $((i % 10)) -eq 0 ]; then
    echo "[oracle] poll $i: GECHO-DRAW=$n  (goalc ${GL##*/}=$(wc -c < "$GL")B)"
  fi
  kill -0 "$GOALC_PID" 2>/dev/null || { echo "[oracle] goalc exited (poll $i); n=$n"; [ "$n" -gt 0 ] && break; }
  sleep 2
done

kill "$GOALC_PID" 2>/dev/null
echo ""
echo "############ goalc tail (build-game / trigger result) ############"
grep -aiE 'connect to target|reset target|build-game|Compil|Error|game-info|Total|warning' "$GL" | tail -20
echo ""
echo "############ GECHO-DRAW distinct tex/mode (max tris) ############"
grep -a 'GECHO-DRAW' "$L" \
 | sed -E 's/ draw=[0-9]+//; s/ idx=[0-9]+//; s/ tbp=0x[0-9a-f]+//' \
 | awk '{tr=$NF; sub(/tris=/,"",tr); k=$0; sub(/ tris=[0-9]+/,"",k); if (tr+0>m[k]) m[k]=tr+0}
        END{for(k in m) printf "%s tris_max=%d\n",k,m[k]}' \
 | sort > "$OUT/x86-oracle-distinct.txt"
cat "$OUT/x86-oracle-distinct.txt"
echo ""
echo "############ pool-ish draws (water/eco/misty/ripple/mud) ############"
grep -aiE 'GECHO-DRAW.*(water|eco|misty|ripple|darkeco|mud|liquid)' "$L" | sort -u | head -40 | tee "$OUT/x86-oracle-pool.txt"
echo ""
echo "[oracle] totals: GECHO-DRAW=$(grep -aca GECHO-DRAW "$L")  distinct-buckets(GECHO-GEN)=$(grep -a GECHO-GEN "$L" | sed -E 's/ verts=.*//' | sort -u | wc -l)"
echo "[oracle] cinematic markers:"; grep -aE 'link finish: dark-eco-pool|Displaying level' "$L" | sort -u | tail -8
kill -INT "$GK_PID" 2>/dev/null; sleep 2; kill -KILL "$GK_PID" 2>/dev/null
echo "[oracle] DONE"
