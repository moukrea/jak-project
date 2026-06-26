#!/usr/bin/env bash
# Gecho-pool capture, take 2: device ALREADY runs current-HEAD instrumented libgk
# (verified by run100). The ONLY change: CLEAR the lingering debug.opengoal.f1.warp
# (left =1 by prior Gsfx/Gaudio F1 runs) which warps past the intro cinematic to
# Geyser Rock. With warp OFF the NEW-GAME intro cinematic plays -> misty -> the
# dark-eco pool. Arms both gecho census props, drives new-game, harvests pool draws.
#   Usage: bash .autoport/Gecho_capture2.sh <run#>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44
RUN="${1:-101}"
say(){ echo; echo "######## $* ########"; }

say "0. confirm device runs fresh HEAD libgk (quick chain check)"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -2 || { echo "[WARN] deploy_verify failed — device may be stale; continuing anyway for diagnosis"; }

say "1. props: CLEAR f1.warp + f1.census (let the intro cinematic PLAY), arm gecho gen+merc"
$ADB -s $S shell setprop debug.opengoal.f1.warp 0
$ADB -s $S shell setprop debug.opengoal.f1.census 0
$ADB -s $S shell setprop debug.opengoal.gecho.gen 1
$ADB -s $S shell setprop debug.opengoal.gecho.merc 1
for p in debug.opengoal.f1.warp debug.opengoal.f1.census debug.opengoal.gecho.gen debug.opengoal.gecho.merc; do
  echo "  $p = $($ADB -s $S shell getprop $p | tr -d '\r')"
done

say "2. drive NEW-GAME -> intro cinematic (no warp); skip reinstall"
FLOW=newgame bash .autoport/f1d_run.sh "$RUN" skip || echo "  (f1d returned $?)"

L=".autoport/reports/F1d-routed-logcat-run${RUN}.log"
say "3. HARVEST  (log: $L, $(wc -l <"$L" 2>/dev/null || echo 0) lines)"
echo "--- F1-WARP (should be 0 now) ---"; grep -ac 'F1-WARP' "$L"
echo "--- level display sequence ---"; grep -aoE 'Displaying level [a-z0-9]+ ?\[[a-z-]+\]' "$L" | uniq -c
MISTY=$(grep -an 'Displaying level misty' "$L" | head -1 | cut -d: -f1); MISTY=${MISTY:-1}
echo "--- misty displayed at line: $MISTY of $(wc -l <"$L") ---"
echo "--- crash signature (if any) ---"; grep -aE 'GK-DIAG sig=|A38-TRIPWIRE (pc|lr) nearest-fn' "$L" | head -6
echo "--- did pool MODEL ever render (Merc2 or Generic)? ---"; grep -ac 'water-anim-misty-dark-eco-pool' "$L"
echo "--- GECHO-MERC poolish models DURING misty ---"
tail -n +"$MISTY" "$L" | grep -aE 'GECHO-MERC.*poolish=1' | sed -E 's/.*GECHO-MERC //' | sort | uniq -c | head
echo "--- misty cinematic models in Merc2 DURING misty (crate-darkeco/darkecocan/sidekick-human/babak/bonelurker) ---"
tail -n +"$MISTY" "$L" | grep -aoE 'GECHO-MERC model=[^ ]+' | sort | uniq -c | sort -rn | head -25
echo "--- GECHO-GEN buckets DURING misty ---"
tail -n +"$MISTY" "$L" | grep -a 'GECHO-GEN' | sed -E 's/.*GECHO-GEN //; s/ verts=.*//' | sort | uniq -c | head
echo "--- GECHO-DRAW darkeco/eco/water textures DURING misty (THE KEY SIGNAL) ---"
tail -n +"$MISTY" "$L" | grep -aiE 'GECHO-DRAW.*(darkeco|environment-darkeco|darkecowater|eco|water)' | sed -E 's/.*GECHO-DRAW //; s/ idx=[0-9]+//; s/ tris=[0-9]+//' | sort | uniq -c | head -20
echo "--- ALL distinct GECHO-DRAW buckets DURING misty ---"
tail -n +"$MISTY" "$L" | grep -aoE 'GECHO-DRAW bucket=[^ ]+ id=[0-9]+' | sort | uniq -c | sort -rn | head
echo "--- A37 ripple fallback ---"; grep -aoE 'A37-MIPS2C-FALLBACK ripple[^ ]*' "$L" | sort -u
say "Gecho-capture2 DONE (run $RUN)"
