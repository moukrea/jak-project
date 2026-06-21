#!/usr/bin/env bash
# Validator — Gmenu-placement: main-menu UI elements must be PLACED CORRECTLY on device (not
# bunched to center), proven by deterministic per-element X/Y POSITION dumps (NEVER pixels — the
# menu is a transparent overlay over a moving island), our-x86==original (1-to-1).
# See [[proxy-dumps-false-green]], [[porting-1to1-fix-in-translation-layers]], [[android-aspect-ratio-4x3-default]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gmenu FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gmenu ok] $*"; }

R=.autoport/reports/Gmenu-placement/menu.txt
[ -f "$R" ] || fail "no menu.txt (per-element X/Y position dumps for original-x86, our-x86, device @2400x1080)"
grep -qiE 'RESULT:[[:space:]]*MENU[[:space:]]+ELEMENTS[[:space:]]+PLACED[[:space:]]+CORRECTLY' "$R" \
  || fail "menu.txt lacks RESULT: MENU ELEMENTS PLACED CORRECTLY (device, positions match intended)"
grep -qiE 'original.?x86|gold' "$R" || fail "menu.txt must include the original-x86 baseline"
grep -qiE 'our.?x86|build.?x86' "$R" || fail "menu.txt must include the our-x86 dump"
grep -qiE 'device|eae4df44' "$R" || fail "menu.txt must include the device dump"
grep -qiE '2400|1080|ultrawide|aspect' "$R" || fail "menu.txt must record the decisive x86-at-2400x1080 finding"
grep -qiE 'x.*y|pos|coord|placement|x=|y=' "$R" || fail "menu.txt must dump per-element X/Y positions (not a scale proxy)"
grep -qiE 'our.?x86 *(==|=|matches|identical).*orig|1-?to-?1|identical' "$R" || fail "menu.txt must show our-x86 == original-x86 (1-to-1)"
grep -qiE 'before|baseline|bunch|cluster|center|reproduc' "$R" || fail "menu.txt must document the calibrated BEFORE (device elements bunched to center)"
grep -qiE 'after' "$R" || fail "menu.txt must document the AFTER (device positions match intended spread)"
ok "per-element X/Y dumps: our-x86==original; device calibrated BEFORE(bunched)->AFTER(spread)"

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
S=.autoport/reports/Gmenu-placement-fix-summary.md
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
echo "[Gmenu PASS] device menu elements placed correctly (position-verified, no pixels); our-x86==original. Known-good restored."
