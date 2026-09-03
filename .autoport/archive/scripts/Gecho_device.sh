#!/usr/bin/env bash
# Gecho-pool DEVICE capture. Arms the Generic2 census prop, drives the proven
# f1d new-game -> intro-cinematic navigation, then greps the routed logcat for
# the dark-eco pool's generic draws (textures mis-darkecowater / environment-
# darkeco, bucket l*-tfrag-generic) to see if they render on arm64.
#   Usage: bash .autoport/Gecho_device.sh <run#> [skip]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
RUN="${1:-90}"; SKIP="${2:-}"
SER=eae4df44
echo "== arm Generic2 census prop on device =="
adb -s "$SER" shell setprop debug.opengoal.gecho.gen 1
echo "  debug.opengoal.gecho.gen=$(adb -s "$SER" shell getprop debug.opengoal.gecho.gen | tr -d '\r')"

echo "== run f1d new-game -> cinematic navigation (RUN=$RUN) =="
FLOW=newgame bash .autoport/f1d_run.sh "$RUN" "$SKIP" || echo "  (f1d returned $?)"

LOG=".autoport/reports/F1d-routed-logcat-run${RUN}.log"
echo ""
echo "############ DEVICE pool draws (mis-darkecowater / environment-darkeco) ############"
grep -aE 'GECHO-DRAW.*(darkecowater|environment-darkeco)' "$LOG" | sort -u | head -30
echo ""
echo "############ any pool-ish texture in ANY generic draw (count) ############"
grep -aoE 'tex=[^ ]*(darkeco|darkecowater|environment-darkeco|misty)[^ ]*' "$LOG" 2>/dev/null | sort | uniq -c | sort -rn | head -20
echo ""
echo "############ tfrag-generic buckets active on device (GECHO-GEN) ############"
grep -aE 'GECHO-GEN.*tfrag-generic' "$LOG" 2>/dev/null | sed -E 's/ verts=.*//' | sort | uniq -c | head
echo ""
echo "############ ALL distinct GECHO-GEN buckets seen on device ############"
grep -a 'GECHO-GEN' "$LOG" 2>/dev/null | sed -E 's/ verts=.*//' | sort -u
echo ""
echo "############ totals ############"
echo "GECHO-DRAW lines: $(grep -aca 'GECHO-DRAW' "$LOG" 2>/dev/null)"
echo "GECHO-GEN  lines: $(grep -aca 'GECHO-GEN' "$LOG" 2>/dev/null)"
echo "misty loaded?    : $(grep -aca 'Displaying level misty\|link finish: dark-eco-pool' "$LOG" 2>/dev/null)"
echo "== Gecho_device done (RUN=$RUN); routed logcat: $LOG =="
