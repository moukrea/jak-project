#!/usr/bin/env bash
# Validator — Gcollision-glitchcapture: capture the collision math AT a REAL owner-play glitch (glitch-
# triggered dump), feed the dumped operands to the x86 oracle, name + fix the divergent op. No replay/warp.
# Objective gate below; FINAL gate = owner play-test. goal_src 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gglitch FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gglitch ok] $*"; }

R=.autoport/reports/Gcollision-glitchcapture/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*REAL[[:space:]]+GLITCH[[:space:]]+COLLISION[[:space:]]+DIVERGENCE[[:space:]]+NAMED[[:space:]]*\+?[[:space:]]*(AND[[:space:]]+)?FIXED' "$R" \
  || fail "report lacks RESULT: REAL GLITCH COLLISION DIVERGENCE NAMED + FIXED"
# a REAL owner-play glitch was captured (dump + trigger signature)
grep -qiE 'owner|real.*(session|play|glitch)' "$R" || fail "must capture a REAL owner-play glitch (not headless/synthetic)"
grep -qiE 'dump|captur|trigger|signature|transv.*spike|jump|projection|under-?map|clip' "$R" || fail "must show the glitch-triggered dump + signature"
grep -qiE 'separation|normalize|fmin|fmax|normal|angle|transv|operand' "$R" || fail "must dump the collision-math operands at the glitch"
# x86 oracle on the dumped operands names the divergent op
grep -qiE 'x86' "$R" || fail "must run the x86 oracle on the dumped operands"
grep -qiE 'first.*diverg|diverg.*op|the op|root|arm64.*(!=|differ|vs).*x86|x86.*(finite|correct).*arm64' "$R" || fail "must name the FIRST op that diverges (arm64 vs x86 on the dumped operands)"
grep -qiE 'before' "$R" || fail "must show BEFORE (arm64 wrong vs x86 on the glitch operands)"
grep -qiE 'after' "$R" || fail "must show AFTER (arm64 == x86 on the dumped operands)"
grep -qiE 'arm64.*(==|=|match).*x86|identical|0[[:space:]]*diff' "$R" || fail "must show arm64 == x86 after the fix on the captured operands"
grep -qiE 'owner.*(play|test|eye|verif)|final gate' "$R" || fail "must note the owner play-test is the final gate"
ok "real glitch dump captured; x86-oracle diff named the divergent op; BEFORE->AFTER(==x86); owner-gate noted"

CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goalc/' || fail "no translation-layer code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Gcollision-glitchcapture-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "translation-layer fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gglitch PASS] real-glitch collision divergence named + fixed (arm64==x86 on the captured operands). AWAITING OWNER PLAY-TEST."
