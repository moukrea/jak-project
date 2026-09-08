#!/usr/bin/env bash
set -uo pipefail
cd /home/emeric/code/jak-project
test ! -e .autoport/.deploy-in-progress || exit 3
sha256sum -c .autoport/reports/lighting-hdr/notes/essai33/hut-portal/source-sha256.txt || exit 3
AUTOPORT_BACKEND=codex ANDROID_SERIAL=eae4df44 bash .autoport/lib/proof_run.sh lighting-hdr device --timeout 220 --hdr-campaign essai33-hut-portal --hdr-vantages village1-out --hdr-hours 12,18 --hdr-prop debug.opengoal.refset.cam=village1-out:-10:-108:152:33 --hdr-prop debug.opengoal.refset.temporal=6 --hdr-prop debug.opengoal.level.warp=village1-hut --hdr-prop debug.opengoal.refset.loadsettle=240 --hdr-prop debug.opengoal.refset.orderhour=1 --hdr-prop debug.opengoal.refset.settle=12 --hdr-prop debug.opengoal.refset.warpat=900 --hdr-prop debug.opengoal.want.display=village1,display --hdr-prop debug.opengoal.want.levels=beach,village1 > .autoport/reports/lighting-hdr/notes/essai33/hut-portal/run-hut-portal.log 2>&1
rc=$?
printf '%s\n' "$rc" > .autoport/reports/lighting-hdr/notes/essai33/hut-portal/exit-hut-portal.txt
cp .autoport/reports/lighting-hdr/proof.txt .autoport/reports/lighting-hdr/notes/essai33/hut-portal/proof-hut-portal.txt
exit "$rc"
