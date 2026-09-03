#!/usr/bin/env bash
# gpbrf_r24_sweep.sh — drive gpbrf_r24_cells.sh over the round-24 vantage set and both tiers,
# then run the EFFECT metric on every (vantage, tier) pair and print the WORST one.
#
# The mandate: "PLUSIEURS VANTAGES, PAS UN ... Rapporte le PIRE vantage, pas la moyenne — c'est le
# pire que l'owner voit." One boot per (vantage, tier) because the warp is a boot one-shot
# (kboot.cpp:176) and the tfrag program + mesh pre-subdivision come from the SETTING at boot.
#
#   VSET="va vb vc vd ve"  TIERS="2 1"  TP=1  R24OUT=r24  bash .autoport/gpbrf_r24_sweep.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/${R24OUT:-r24}; mkdir -p "$OUT"
LOGD=.autoport/reports/Grecharged-pbr-realtime-fusion; mkdir -p "$LOGD"
TP="${TP:-1}"

# label -> "x y z" (metres). Derived from decompiler_out/jak1/entities/village1-actors.json: every
# one sits within a few metres of a real actor, i.e. on authored walkable ground.
pos_of(){ case "$1" in
  va) echo "-111.98 41.96 204.99";;   # the OWNER's vantage: sage hut terrace, stone wall + ground
  vb) echo "-134.5 40.2 202.4";;      # hut base / stilts, looking up the wall (near field)
  vc) echo "-126.0 52.2 217.0";;      # upper warp-gate terrace, looks DOWN onto the hut roofs
  vd) echo "-156.0 34.0 188.0";;      # the stock village1-hut continue: plateau, cliff, long view
  ve) echo "-89.4 15.5 22.4";;        # village core grass, 184 m from va: the far/mid-LOD case
  *) echo "";; esac; }

VSET="${VSET:-va vb vc vd ve}"
TIERS="${TIERS:-2 1}"

for V in $VSET; do
  P=$(pos_of "$V"); [ -n "$P" ] || { echo "unknown vantage $V"; exit 1; }
  for T in $TIERS; do
    TAG="${V}_t${T}"
    if [ -f "$OUT/${TAG}_diag.png" ] && [ "${FORCE:-0}" = "0" ]; then
      echo "== skip $TAG (already captured)"; continue
    fi
    echo "== CAPTURE $TAG  pos='$P'  tp=$TP"
    VLABEL="$V" VPOS="$P" TIER="$T" TP="$TP" R24OUT="${R24OUT:-r24}" SATAB=1 RELIEF="${RELIEF:-2.0}" \
      timeout 1800 bash .autoport/gpbrf_r24_cells.sh > "$LOGD/r24-cells-${TAG}${R24SUF:-}.log" 2>&1
    rc=$?
    echo "   exit=$rc  (log $LOGD/r24-cells-${TAG}${R24SUF:-}.log)"
    [ $rc -eq 0 ] || tail -12 "$LOGD/r24-cells-${TAG}${R24SUF:-}.log"
  done
done

echo
echo "################ ROUND 24 EFFECT METRIC — all captured pairs ################"
: > "$OUT/moved_summary.txt"
for V in $VSET; do
  for T in $TIERS; do
    TAG="${V}_t${T}"
    [ -f "$OUT/${TAG}_diag.png" ] || continue
    TIERNAME=tessellation; [ "$T" = "1" ] && TIERNAME=parallax
    python3 .autoport/gpbrf_r24_moved.py --label "$V" --tier "$TIERNAME" \
      --on "$OUT/${TAG}_on.png" --off1 "$OUT/${TAG}_off1.png" --off2 "$OUT/${TAG}_off2.png" \
      --mask "$OUT/${TAG}_mask.png" --prog "$OUT/${TAG}_prog.png" --diag "$OUT/${TAG}_diag.png" \
      --sham "$OUT/${TAG}_sham.png" --diag2 "$OUT/${TAG}_diag2.png" --sat "$OUT/${TAG}_onMAX.png" \
      --json "$OUT/${TAG}_moved.json" | tee "$OUT/${TAG}_moved.txt"
    grep -a '^HEADLINE' "$OUT/${TAG}_moved.txt" >> "$OUT/moved_summary.txt"
    echo
  done
done
echo "################ WORST VANTAGE ################"
sort -t: -k2 -g "$OUT/moved_summary.txt" 2>/dev/null | head -40
python3 - "$OUT" <<'PY'
import glob, json, sys
o = sys.argv[1]
rows = [json.load(open(f)) for f in sorted(glob.glob(o + "/*_moved.json"))]
for t in ("tessellation", "parallax"):
    r = [x for x in rows if x["tier"] == t]
    if not r:
        continue
    w = min(r, key=lambda x: x["moved_pct"])
    print(f"{t:<14} WORST vantage = {w['label']}: {w['moved_pct']:.2f}% of maps-bearing pixels moved "
          f"({w['moved_px']}/{w['maps_px']}), floor {w['threshold']:.2f}/255   "
          f"[all: " + ", ".join(f"{x['label']} {x['moved_pct']:.2f}%" for x in r) + "]")
PY
