#!/usr/bin/env bash
# Validator — Gcollision-systemic: the pervasive arm64 collision divergence (clip-through, eject,
# under-map, invisible walls, stuck-crouch) fixed at the ROOT (a systemic arm64 conversion/codegen op),
# proven by a x86-vs-arm64 collision-math sweep (many->0 diffs) + state-anchored in-game confirm on
# multiple scenarios. Translation-layer only; goal_src 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gcollsys FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gcollsys ok] $*"; }

R=.autoport/reports/Gcollision-systemic/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*ARM[[:space:]]+COLLISION[[:space:]]+MATCHES[[:space:]]+X86[[:space:]]*\(SYSTEMIC\)' "$R" \
  || fail "report lacks RESULT: ARM COLLISION MATCHES X86 (SYSTEMIC)"
# the unit-diff sweep: BEFORE many diffs -> AFTER 0 diffs, with counts (the Gcollision-arm model)
grep -qiE '[0-9]+[[:space:]]*/[[:space:]]*[0-9]{3,}' "$R" || fail "must show the collision-math sweep counts (e.g. N/60000)"
grep -qiE '0[[:space:]]*/[[:space:]]*[0-9]{3,}' "$R" || fail "must show AFTER = 0/<N> diffs (collision math bit-identical to x86)"
grep -qiE 'before|baseline' "$R" || fail "must show the BEFORE sweep (many diffs)"
# named systemic root op
grep -qiE 'vftoi|vitof|ftoi|itof|convert|truncat|round|fixed-?point|scale|fma|denorm|ftz|codegen|mips2c' "$R" \
  || fail "must NAME the systemic arm64 conversion/codegen root op that diverges"
grep -qiE 'systemic|pervasive|root|everywhere|broad' "$R" || fail "must frame the fix as the systemic ROOT, not a per-site patch"
# >=3 distinct in-game symptom scenarios, state-anchored, before->after
grep -qiE 'clip|through|under.?map|wall' "$R" || fail "must cover clip-through / under-map / wall scenario"
grep -qiE 'eject|launch|project|off.*cliff|far' "$R" || fail "must cover the eject/launch scenario"
grep -qiE 'invisible|flat|stuck|crouch|edge|blue-?eco' "$R" || fail "must cover a third scenario (invisible-wall/stuck/edge)"
NS=$(grep -aciE 'scenario|spot|case [0-9]|before.*after' "$R" 2>/dev/null || true); [ "${NS:-0}" -ge 3 ] || fail "fewer than 3 documented before/after scenarios (got $NS)"
grep -qiE 'state-?anchor|logical|control[- ]state|normal|penetrat|veloc|position' "$R" || fail "in-game confirm must dump state-anchored collision values (not render frames)"
grep -qiE 'device.*(==|=|match).*x86|1-?to-?1|identical|== *x86' "$R" || fail "must show device collision == x86 after the fix"
grep -qiE 'regress' "$R" || fail "must document the regression-check of the recent collision fixes"
ok "systemic root named; sweep many->0; >=3 scenarios BEFORE->AFTER(==x86); regression-checked"

CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goalc/' || fail "no translation-layer code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Gcollision-systemic-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "translation-layer fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gcollsys PASS] systemic arm64 collision divergence fixed at root; math sweep 0 diffs; >=3 scenarios == x86; goal_src 1-to-1."
