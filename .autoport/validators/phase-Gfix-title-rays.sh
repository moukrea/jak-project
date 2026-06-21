#!/usr/bin/env bash
# Validator — Gfix-title-rays: the title-logo light rays must VANISH after the smash on the
# SAME frame as the untouched original (.autoport/gold), proven by deterministic per-frame
# alpha/active DUMPS (NEVER pixels). Calibrated: a BEFORE must show ours lingering vs original.
# See [[proxy-dumps-false-green]], [[state-dumps-x86-first-not-screenshots]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gfix-title-rays FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gfix-title-rays ok] $*"; }

R=.autoport/reports/Gfix-title-rays/rays.txt
[ -f "$R" ] || fail "no rays.txt (per-frame ray alpha/active dumps for original-x86, our-x86, device)"
# the RESULT verdict
grep -qiE 'RESULT:[[:space:]]*TITLE[[:space:]]+RAYS[[:space:]]+VANISH[[:space:]]+MATCHING[[:space:]]+ORIGINAL' "$R" \
  || fail "rays.txt lacks RESULT: TITLE RAYS VANISH MATCHING ORIGINAL"
# all three sources dumped (x86-first mandate)
grep -qiE 'original.?x86|gold' "$R" || fail "rays.txt must include the original-x86 (.autoport/gold) baseline dump"
grep -qiE 'our.?x86|build.?x86' "$R" || fail "rays.txt must include the our-x86 dump (x86-first comparison)"
grep -qiE 'device|eae4df44' "$R" || fail "rays.txt must include the device dump"
# calibration: a BEFORE that reproduced the lingering
grep -qiE 'before|baseline|ling/?er|reproduc' "$R" || fail "rays.txt must document the BEFORE that reproduced the lingering rays (calibration)"
grep -qiE 'after' "$R" || fail "rays.txt must document the AFTER (rays now vanish matching original)"
ok "ray alpha/active dumps present for original-x86 + our-x86 + device; calibrated BEFORE/AFTER"

# real code change + fix-summary + dumps removed + golden pristine
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 'game/**' 'android/**' 2>/dev/null | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'goal_src/|game/|android/' || fail "no real code change"
S=.autoport/reports/Gfix-title-rays-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden .autoport/gold not pristine (must be byte-clean)"
ok "real code change; fix-summary >=60 lines; golden pristine"

# x86 unbroken + deploy landed
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gfix-title-rays PASS] title-logo light rays vanish matching the original (dump-verified, no pixels), x86 unchanged. Known-good restored."
