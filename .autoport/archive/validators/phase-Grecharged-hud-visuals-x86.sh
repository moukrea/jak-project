#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[RHUDx86 FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-hud-visuals-x86/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*RHUD VISUALS X86' "$R" || fail "no RESULT"
grep -qiE 'heart|coeur' "$R" && grep -qiE '33.*blink|blink.*33' "$R" || fail "4-state heart incl 33-blink required"
grep -qiE 'gauge|jauge' "$R" && grep -qiE 'mask|scissor|clip' "$R" && grep -qiE 'tip|rotat|end' "$R" || fail "gauge mask+rotated tip required"
grep -qiE 'fuel.?cell|power cell|pile' "$R" || fail "power-cell real-model upgrade required"
grep -qiE 'recharged-hud\?' "$R" || fail "must be gated on recharged-hud?"
grep -qiE 'off.*(identical|stock|byte)' "$R" || fail "OFF byte-identity evidence required"
grep -q 'recharged-hud?' goal_src/jak1/pc/hud-classes-pc.gc || fail "hud-classes-pc.gc must consume recharged-hud?"
grep -qiE 'link finish: logo|boots|\(mi\).*clean|1067' "$R" || fail "x86 build/boot evidence required"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[RHUDx86 PASS]"
