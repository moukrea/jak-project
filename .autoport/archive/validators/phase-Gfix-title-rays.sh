#!/usr/bin/env bash
# Validator — Gfix-title-rays (v2, 1-to-1 source): the device title-logo additive light rays must
# MATCH the untouched original's fade, with the fix in a TRANSLATION layer (goalc/game-graphics/
# android) and ZERO game-source edits. our-x86 must stay == original-x86.
# See [[porting-1to1-fix-in-translation-layers]], [[proxy-dumps-false-green]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gfix-title-rays FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gfix-title-rays ok] $*"; }

# === 1-to-1 SOURCE GATE: the phase must make ZERO goal_src game-logic edits ===
SRC_TOUCHED=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC_TOUCHED=$(echo "$SRC_TOUCHED" | grep -vE '^\s*$' || true)
[ -z "$SRC_TOUCHED" ] || fail "FORBIDDEN game-source edit(s) — the fix must be in a translation layer (goalc/game-graphics/android), not goal_src:
$SRC_TOUCHED"
ok "no goal_src game-logic edits (1-to-1 source preserved)"

R=.autoport/reports/Gfix-title-rays/rays.txt
[ -f "$R" ] || fail "no rays.txt (per-frame ray INTENSITY dumps for original-x86, our-x86, device)"
grep -qiE 'RESULT:[[:space:]]*TITLE[[:space:]]+RAYS[[:space:]]+MATCH[[:space:]]+ORIGINAL' "$R" \
  || fail "rays.txt lacks RESULT: TITLE RAYS MATCH ORIGINAL (device, 1-to-1 source)"
grep -qiE 'original.?x86|gold' "$R" || fail "rays.txt must include the original-x86 (.autoport/gold) baseline"
grep -qiE 'our.?x86|build.?x86' "$R" || fail "rays.txt must include the our-x86 dump"
grep -qiE 'device|eae4df44' "$R" || fail "rays.txt must include the device dump"
# our-x86 must equal original-x86 (1-to-1), explicitly asserted
grep -qiE 'our.?x86 *(==|=|matches|identical).*orig|orig.*(==|=|matches|identical).*our.?x86|1-?to-?1|identical' "$R" \
  || fail "rays.txt must explicitly show our-x86 == original-x86 ray intensity (1-to-1 preserved)"
grep -qiE 'before|baseline|reproduc|linger' "$R" || fail "rays.txt must document the calibrated BEFORE (device diverged)"
grep -qiE 'after' "$R" || fail "rays.txt must document the AFTER (device now matches original)"
ok "ray-intensity dumps: our-x86==original-x86; device calibrated BEFORE->AFTER matches original"

# === translation-layer change actually exists ===
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'goalc/**' 'game/**' 'android/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'goalc/|game/|android/' || fail "no translation-layer code change (goalc/game/android)"
S=.autoport/reports/Gfix-title-rays-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden .autoport/gold not pristine"
ok "translation-layer fix present; fix-summary >=60 lines; golden pristine"

# === x86 unbroken + device runs fresh HEAD ===
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gfix-title-rays PASS] device title rays match the original via a TRANSLATION-layer fix (no game-source edits, our-x86==original). Known-good restored."
