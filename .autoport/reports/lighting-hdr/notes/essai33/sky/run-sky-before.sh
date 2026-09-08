#!/usr/bin/env bash
set -uo pipefail
cd /home/emeric/code/jak-project
test ! -e .autoport/.deploy-in-progress || exit 3
sha256sum -c .autoport/reports/lighting-hdr/notes/essai33/sky/source-sha256.txt || exit 3
AUTOPORT_BACKEND=codex ANDROID_SERIAL=eae4df44 bash .autoport/lib/proof_run.sh lighting-hdr device --timeout 220 --hdr-campaign essai33-sky --hdr-vantages beach-start --hdr-hours 9,12,18 --hdr-prop debug.opengoal.refset.cambyhour=0:0:0:0,0:0:0:0,0:0:0:0,7:-35:0:30,7:-35:0:5000,0:0:0:0,7:-35:0:5000 --hdr-prop debug.opengoal.refset.temporal=6 --hdr-prop debug.opengoal.level.warp=beach-start --hdr-prop debug.opengoal.refset.loadsettle=240 --hdr-prop debug.opengoal.refset.orderhour=1 --hdr-prop debug.opengoal.refset.settle=12 --hdr-prop debug.opengoal.refset.warpat=900 --hdr-prop debug.opengoal.want.display=beach,display --hdr-prop debug.opengoal.want.levels=beach,village1 > .autoport/reports/lighting-hdr/notes/essai33/sky/run-sky-before.log 2>&1
rc=$?
printf '%s\n' "$rc" > .autoport/reports/lighting-hdr/notes/essai33/sky/exit-sky-before.txt
cp .autoport/reports/lighting-hdr/proof.txt .autoport/reports/lighting-hdr/notes/essai33/sky/proof-sky-before.txt
exit "$rc"
