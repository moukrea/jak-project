#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gao FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-ambient-occlusion/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*AMBIENT OCCLUSION' "$R" || fail "no RESULT"
grep -qiE 'RESULT:.*(IN-PROGRESS|underway|not final)' "$R" && fail "RESULT is a living skeleton"
grep -qiE 'ssao|screen.?space|depth (buffer|fbo)' "$R" || fail "must be screen-space AO from the depth buffer"
grep -qiE 'alpha.*(exclud|transparent|cut|foliage|card)|transparent.*(exclud|depth)' "$R" || fail "must handle the alpha-transparent exclusion (owner #1 risk)"
grep -qiE 'no (boxy|square|halo).*(shadow|alpha)|alpha.*no.*(shadow|artifact)' "$R" || fail "must prove no boxy shadows on alpha foliage/grass cards"
grep -qiE 'off.*ssao.*hbao.*gtao|ssao.*hbao.*gtao' "$R" || fail "must offer the AO TYPE selector Off/SSAO/HBAO/GTAO"
grep -qiE 'ao quality|quality.*(low).*(medium).*(high)|low.*medium.*high' "$R" || fail "must add the separate AO Quality Low/Medium/High row"
grep -qiE 'hbao' "$R" || fail "HBAO must be implemented"
grep -qiE 'gtao|ground.?truth' "$R" || fail "GTAO must be implemented"
grep -qiE 'off.*(stock|identical|byte)|stock.*off' "$R" || fail "Off must == stock"
grep -qiE 'fps' "$R" || fail "must report device fps per algorithm x quality"
grep -qiE 'ssao.*fps|fps.*ssao|per.?(combo|algorithm)|cost curve' "$R" || fail "must report the fps cost curve across SSAO/HBAO/GTAO x Low/Med/High"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device jak1 evidence"
bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gao PASS]"
# Supervisor 2026-07-16: closing-round gate — the report must prove the owner's final tuning items
R=.autoport/reports/Grecharged-ambient-occlusion/report.txt
grep -qiE 'AO STRENGTH|ao-strength' "$R" || { echo "[Gao FAIL] CLOSING-ROUND: no AO STRENGTH row proof in report"; exit 1; }
grep -qiE 'Weaker' "$R" || { echo "[Gao FAIL] CLOSING-ROUND: no Weaker/Default/Stronger proof"; exit 1; }
grep -qiE 'variance|consisten' "$R" || { echo "[Gao FAIL] CLOSING-ROUND: no GTAO variance/consistency analysis"; exit 1; }
# Supervisor 2026-07-16: ROUND-F gate — SSAO low/med banding fix + HBAO/GTAO depth rework must be proven
R=.autoport/reports/Grecharged-ambient-occlusion/report.txt
grep -qiE 'horizontal band|banding.*(fix|free)|band-free' "$R" || { echo "[Gao FAIL] ROUND-F: no SSAO low/med horizontal-banding fix proof"; exit 1; }
grep -qiE 'depth A/B|broad.*(term|component|depth)|as deep as SSAO' "$R" || { echo "[Gao FAIL] ROUND-F: no HBAO/GTAO broad-depth rework proof"; exit 1; }
# fraîcheur: le rapport doit être plus récent que le mandat round-F (16:50)
[ "$(stat -c %Y "$R")" -gt "$(date -d '2026-07-16 16:50' +%s)" ] || { echo "[Gao FAIL] ROUND-F: stale report (predates the round-F mandate)"; exit 1; }
