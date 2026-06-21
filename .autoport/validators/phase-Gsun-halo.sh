#!/usr/bin/env bash
# Validator — Gsun-halo: the device title sun CORONA size must match the untouched original (small
# disc, not a ~20% glow), proven by deterministic per-frame SIZE dumps (NEVER pixels), with
# our-x86 == original-x86 (1-to-1). Source edits allowed ONLY as a revert toward pristine.
# See [[porting-1to1-fix-in-translation-layers]], [[proxy-dumps-false-green]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gsun-halo FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gsun-halo ok] $*"; }

R=.autoport/reports/Gsun-halo/sun.txt
[ -f "$R" ] || fail "no sun.txt (per-frame sun disc + corona size dumps for original-x86, our-x86, device)"
grep -qiE 'RESULT:[[:space:]]*SUN[[:space:]]+CORONA[[:space:]]+SIZE[[:space:]]+MATCHES[[:space:]]+ORIGINAL' "$R" \
  || fail "sun.txt lacks RESULT: SUN CORONA SIZE MATCHES ORIGINAL (device, 1-to-1 source)"
grep -qiE 'original.?x86|gold' "$R" || fail "sun.txt must include the original-x86 (.autoport/gold) baseline"
grep -qiE 'our.?x86|build.?x86' "$R" || fail "sun.txt must include the our-x86 dump"
grep -qiE 'device|eae4df44' "$R" || fail "sun.txt must include the device dump"
grep -qiE 'corona|glow|sprite|scale|size' "$R" || fail "sun.txt must dump the corona/glow size metric"
grep -qiE 'our.?x86 *(==|=|matches|identical).*orig|1-?to-?1|identical' "$R" || fail "sun.txt must show our-x86 == original-x86 (1-to-1)"
grep -qiE 'before|baseline|oversize|reproduc' "$R" || fail "sun.txt must document the calibrated BEFORE (device corona oversized)"
grep -qiE 'after' "$R" || fail "sun.txt must document the AFTER (device corona matches original)"
ok "sun size dumps: our-x86==original-x86; device calibrated BEFORE->AFTER matches original"

# === 1-to-1 source: any goal_src change must be a REVERT toward pristine (our-x86 ends == original) ===
# We can't diff against upstream here, but the sun.txt our-x86==original assertion above covers the
# x86 behavior. Additionally forbid NEW source files; allow edits only to known title/sun sources.
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then
  BAD=$(echo "$SRC" | grep -vE 'title/title-obs\.gc|weather-part\.gc' || true)
  [ -z "$BAD" ] || fail "goal_src edits outside title/sun sources (must be a pristine revert, not a new hack): $BAD"
  grep -qiE 'revert|pristine|restore.*original|toward.*original' "$R" || fail "goal_src was edited but sun.txt does not document it as a REVERT toward the pristine original"
  ok "goal_src edit limited to title/sun sources and documented as a pristine revert"
else
  ok "no goal_src edits (fix is in the translation layer)"
fi

# === fix-summary + golden pristine ===
S=.autoport/reports/Gsun-halo-fix-summary.md
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
echo "[Gsun-halo PASS] device sun corona size matches the original (small disc, dump-verified, no pixels); our-x86==original. Known-good restored."
