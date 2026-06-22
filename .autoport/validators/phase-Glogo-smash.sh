#!/usr/bin/env bash
# Validator — Glogo-smash: the title logo-smash (logo-black breaking to reveal the logo) must MATCH
# the original on device, proven by deterministic smash-SEQUENCE state dumps (NEVER pixels). Any
# goal_src edit must be a REVERT toward pristine. See [[porting-1to1-fix-in-translation-layers]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Glogo FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Glogo ok] $*"; }

R=.autoport/reports/Glogo-smash/logo.txt
[ -f "$R" ] || fail "no logo.txt (logo-smash sequence state dumps for original-x86, our-x86, device)"
grep -qiE 'RESULT:[[:space:]]*LOGO[[:space:]]+SMASH[[:space:]]+MATCHES[[:space:]]+ORIGINAL' "$R" \
  || fail "logo.txt lacks RESULT: LOGO SMASH MATCHES ORIGINAL (device)"
grep -qiE 'original.?x86|gold' "$R" || fail "logo.txt must include the original-x86 baseline"
grep -qiE 'our.?x86|build.?x86' "$R" || fail "logo.txt must include the our-x86 dump"
grep -qiE 'device|eae4df44' "$R" || fail "logo.txt must include the device dump"
grep -qiE 'logo-black|smash|state|frame-?num|joint|trigger' "$R" || fail "logo.txt must dump the smash sequence state (state/anim/trigger)"
grep -qiE 'before|baseline|broken|reproduc' "$R" || fail "logo.txt must document the calibrated BEFORE (smash broken)"
grep -qiE 'after' "$R" || fail "logo.txt must document the AFTER (device smash matches original)"
grep -qiE 'regress|edit|hack|16x9|main-joint|reverted|pristine' "$R" || fail "logo.txt must name the regressing edit"
ok "logo-smash sequence dumps: calibrated BEFORE(broken)->AFTER(matches original); regressing edit named"

# === source edits only as a documented pristine revert ===
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then
  grep -qiE 'revert|pristine|restore.*original|toward.*original' "$R" || fail "goal_src edited but not documented as a pristine revert: $SRC"
  ok "goal_src edit documented as a pristine revert toward the original"
else
  ok "no goal_src edits (fix in translation layer)"
fi

# === fix-summary + golden pristine ===
S=.autoport/reports/Glogo-smash-fix-summary.md
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
echo "[Glogo PASS] device logo-smash matches the original (sequence-verified, no pixels); regressing edit reverted to pristine."
