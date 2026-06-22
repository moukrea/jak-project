#!/usr/bin/env bash
# Validator — Gwater-lod: near-camera water must render the detailed surface on device (not flat-blue
# squares), proven by per-near-chunk LOD + detailed-draw counts (NEVER pixels), our-x86==original.
# See [[gwater-state]], [[proxy-dumps-false-green]], [[porting-1to1-fix-in-translation-layers]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gwater FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gwater ok] $*"; }

R=.autoport/reports/Gwater-lod/water.txt
[ -f "$R" ] || fail "no water.txt (per-near-chunk LOD + detailed-draw counts, 3-way)"
grep -qiE 'RESULT:[[:space:]]*NEAR-CAMERA[[:space:]]+WATER[[:space:]]+RENDERS[[:space:]]+MATCHING[[:space:]]+ORIGINAL' "$R" \
  || fail "water.txt lacks RESULT: NEAR-CAMERA WATER RENDERS MATCHING ORIGINAL (device, 1-to-1 source)"
grep -qiE 'original.?x86|gold' "$R" || fail "water.txt must include the original-x86 baseline"
grep -qiE 'our.?x86|build.?x86' "$R" || fail "water.txt must include the our-x86 dump"
grep -qiE 'device|eae4df44' "$R" || fail "water.txt must include the device dump"
grep -qiE 'lod|near|chunk|draw|vert|tri' "$R" || fail "water.txt must dump per-near-chunk LOD/draw counts"
grep -qiE 'our.?x86 *(==|=|matches|identical).*orig|1-?to-?1|identical' "$R" || fail "water.txt must show our-x86 == original-x86 (1-to-1)"
grep -qiE 'before|baseline|flat|blue|0 |reproduc' "$R" || fail "water.txt must document the calibrated BEFORE (device near-chunks flat/0 detailed)"
grep -qiE 'after' "$R" || fail "water.txt must document the AFTER (device near-chunks draw detailed surface)"
ok "near-chunk LOD/draw dumps: our-x86==original; device BEFORE(flat)->AFTER(detailed) matches"

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
S=.autoport/reports/Gwater-lod-fix-summary.md
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
echo "[Gwater PASS] device near-camera water renders the detailed surface matching the original (draw-verified, no pixels); our-x86==original."
