#!/usr/bin/env bash
# Validator — Gcollision-replay-diff: diagnose+fix the REAL arm64 collision divergence using the OWNER's
# recorded glitch demo replayed on x86 vs arm64 with per-logic-tick collision dumps. Demo-driven (NOT
# synthetic scenarios / unit-sweep-only — that false-greened). Translation-layer; goal_src 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gcoll-rd FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gcoll-rd ok] $*"; }

# the owner demo must exist + be the real ~8min playthrough
D=.autoport/demos/collision-glitch.inputs
[ -f "$D" ] || fail "owner demo .autoport/demos/collision-glitch.inputs missing"
[ "$(wc -c < "$D")" -ge 100000 ] || fail "owner demo too small — not the real glitch playthrough"

R=.autoport/reports/Gcollision-replay-diff/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*ARM[[:space:]]+COLLISION[[:space:]]+MATCHES[[:space:]]+X86[[:space:]]+ON[[:space:]]+OWNER[[:space:]]+DEMO' "$R" \
  || fail "report lacks RESULT: ARM COLLISION MATCHES X86 ON OWNER DEMO"
# must be DEMO-DRIVEN: the owner demo replayed on BOTH backends
grep -qiE 'collision-glitch\.inputs|owner.?demo|recorded.*playthrough' "$R" || fail "must use the owner demo collision-glitch.inputs"
grep -qiE 'x86' "$R" || fail "must replay on x86 oracle"
grep -qiE 'arm64|device|eae4df44' "$R" || fail "must replay on arm64 device"
grep -qiE 'replay|OG_PAD_REPLAY_REPLAY|pad_replay' "$R" || fail "must use the Ginput-replay harness replay"
# per-logic-tick collision dump + first-divergence tick named BEFORE
grep -qiE 'logic[- ]?tick|per[- ]tick|tick=' "$R" || fail "collision dump must be keyed by LOGIC TICK (not render frame)"
grep -qiE 'normal|penetrat|veloc|position|quant|bbox|hash|collide' "$R" || fail "must dump real collision-state fields"
grep -qiE 'first[- ]?diverg|diverg.*tick|tick.*diverg|onset' "$R" || fail "must name the FIRST divergent logic tick (glitch onset)"
grep -qiE 'root|cause|the op|culprit|smoking gun' "$R" || fail "must name the real root op"
# BEFORE diverges -> AFTER matches (first-divergence pushed out / none)
grep -qiE 'before' "$R" || fail "must document BEFORE (arm64 diverges from x86 at tick T)"
grep -qiE 'after' "$R" || fail "must document AFTER (arm64 trace matches x86 oracle)"
grep -qiE 'match|==|identical|no.*diverg|0[[:space:]]*diverg' "$R" || fail "must show AFTER arm64 collision == x86 on the demo"
grep -qiE 'regress' "$R" || fail "must document the regression-check of the FCVTZS + per-site fixes"
ok "demo-driven x86-vs-arm64 collision diff: first-divergence + root named; BEFORE->AFTER(==x86)"

CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goalc/' || fail "no translation-layer code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Gcollision-replay-diff-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm the temp dump hook removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "translation-layer fix; goal_src 1-to-1; fix-summary >=60 lines; dump hook removed; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gcoll-rd PASS] owner-demo replay diff: arm64 collision == x86; real root fixed. AWAITING OWNER RE-PLAY (final ground truth)."
