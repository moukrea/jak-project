#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gj2polish FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gjak2-polish/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*JAK2 POLISH' "$R" || fail "no RESULT"
grep -qiE 'crouch|accroupi|L1' "$R" || fail "L1/R1 crouch mapping must be addressed"
grep -qiE 'cinemat.*aspect|aspect.*cinemat|cutscene.*aspect' "$R" || fail "cutscene aspect must follow the setting"
grep -qiE 'order|ordre' "$R" && grep -qiE 'advanced|ps2' "$R" || fail "menu order+label parity required"
grep -qiE 'fps.*(counter|compteur|option)' "$R" || fail "FPS counter option required"
grep -qiE 'rift|glow|portal' "$R" || fail "rift-gate glow tuning required"
grep -qiE 'mCurrentFocus.*jak2|focus.*jak2' "$R" || fail "jak2 foreground evidence"
V=$(find .autoport/reports/Gjak2-polish -type f \( -name '*.mp4' -o -name '*.png' \) 2>/dev/null | head -1)
[ -n "$V" ] || fail "no visual evidence"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gj2polish PASS]"
