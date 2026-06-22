#!/usr/bin/env bash
# Validator — Gbirds-anim: title birds must ANIMATE on device (anim-frame advances), proven by
# per-frame anim-frame/joint-advance dumps (NEVER pixels), our-x86==original (1-to-1).
# See [[proxy-dumps-false-green]], [[porting-1to1-fix-in-translation-layers]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gbirds FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gbirds ok] $*"; }

R=.autoport/reports/Gbirds-anim/birds.txt
[ -f "$R" ] || fail "no birds.txt (per-frame bird anim-frame/joint advance, 3-way)"
grep -qiE 'RESULT:[[:space:]]*BIRDS[[:space:]]+ANIMATE[[:space:]]+MATCHING[[:space:]]+ORIGINAL' "$R" \
  || fail "birds.txt lacks RESULT: BIRDS ANIMATE MATCHING ORIGINAL (device, 1-to-1 source)"
grep -qiE 'original.?x86|gold' "$R" || fail "birds.txt must include the original-x86 baseline"
grep -qiE 'our.?x86|build.?x86' "$R" || fail "birds.txt must include the our-x86 dump"
grep -qiE 'device|eae4df44' "$R" || fail "birds.txt must include the device dump"
grep -qiE 'frame-?num|ja-|anim|joint|advance' "$R" || fail "birds.txt must dump the bird anim-frame/joint advance"
grep -qiE 'our.?x86 *(==|=|matches|identical).*orig|1-?to-?1|identical' "$R" || fail "birds.txt must show our-x86 == original-x86 (1-to-1)"
grep -qiE 'before|baseline|stuck|frozen|delta.?0|Δ.?0|reproduc' "$R" || fail "birds.txt must document the calibrated BEFORE (device anim-frame stuck)"
grep -qiE 'after' "$R" || fail "birds.txt must document the AFTER (device anim-frame advances)"
ok "bird anim-advance dumps: our-x86==original; device BEFORE(stuck)->AFTER(advances) matches"

# === 1-to-1 source: goal_src edits only as a documented pristine revert ===
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then
  grep -qiE 'revert|pristine|restore.*original|toward.*original' "$R" || fail "goal_src edited but not documented as a pristine revert: $SRC"
  ok "goal_src edit documented as a pristine revert"
else
  ok "no goal_src edits (fix in translation layer)"
fi

# === fix-summary + golden pristine ===
S=.autoport/reports/Gbirds-anim-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden .autoport/gold not pristine"
ok "fix-summary >=60 lines; golden pristine"

# === x86 unbroken + device runs fresh HEAD ===
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gbirds PASS] device title birds animate matching the original (anim-advance-verified, no pixels); our-x86==original."
