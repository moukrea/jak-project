#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gmesh FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-mesh-consolidation/report.txt
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS"
grep -qiE '^RESULT: WIP' "$R" && fail "report is WIP"
grep -qiE 'READY FOR OWNER VISUAL CHECK' "$R" || fail "no READY marker"
# the coverage metric (the point of the phase)
grep -qiE 'coincident.?but.?unshared|unshared edge|open edge.*(twin|pair|coincident)|forgotten weld.*count' "$R" || fail "no coincident-but-unshared-edge audit metric (the 'no omissions' proof)"
grep -qiE '(unshared|open).*edge.*(0|zero|~0|remaining [0-9])' "$R" || fail "no remaining-unshared-edge count reported"
grep -qiE 'per.?level|every level|all level' "$R" || fail "no per-level whole-game coverage evidence"
grep -qiE 'normal.*(discontinuity|delta).*(histogram|max|~?0)|normal delta.*report' "$R" || fail "no normal-discontinuity metric"
grep -qiE 'baked.?colou?r.*(delta|discontinuity|blend|average)' "$R" || fail "no baked-colour-discontinuity metric/fix (the couture suspect)"
grep -qiE 'seam.*(consistent|identical).*(displac|height)|displac.*(identical|same).*(seam|coincident)' "$R" || fail "no seam-consistent displacement (tessellation slits)"
grep -qiE 'orientation|inward.*(flip|fixed)|collision.*(authority|outward)' "$R" || fail "no normal-orientation pass evidence"
grep -qiE 'tie|shrub' "$R" || fail "no evidence tie/shrub systems covered (not only tfrag ground)"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1|boots' "$R" || fail "no device boot proof"
echo "[Gmesh PASS]"
