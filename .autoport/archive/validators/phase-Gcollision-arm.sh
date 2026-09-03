#!/usr/bin/env bash
# Validator — Gcollision-arm: arm64 collision must match x86 (no wall clip-through, no stuck-crouch),
# proven by an x86-first collision-state diff with the named arm64 divergence fixed in translation.
# See [[porting-1to1-fix-in-translation-layers]], [[proxy-dumps-false-green]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gcollide FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gcollide ok] $*"; }

R=.autoport/reports/Gcollision-arm/collide.txt
[ -f "$R" ] || fail "no collide.txt (x86-first collision-state diff)"
grep -qiE 'RESULT:[[:space:]]*ARM[[:space:]]+COLLISION[[:space:]]+MATCHES[[:space:]]+X86' "$R" \
  || fail "collide.txt lacks RESULT: ARM COLLISION MATCHES X86 (no wall clip-through, no stuck-crouch)"
grep -qiE 'original.?x86|gold|x86' "$R" || fail "collide.txt must include the x86 baseline"
grep -qiE 'device|eae4df44|arm64' "$R" || fail "collide.txt must include the device dump"
grep -qiE 'clip|through|fall.*map|wall' "$R" || fail "collide.txt must cover the wall clip-through"
grep -qiE 'crouch|accroup' "$R" || fail "collide.txt must cover the stuck-crouch"
grep -qiE 'collide|normal|penetrat|prim|plane|float|dot|det' "$R" || fail "collide.txt must dump the collision-state floats/values"
# named arm64 divergence
grep -qiE 'diverg|float|nan|denorm|ftz|#f|modulo|ldp|compare|round|sign|codegen|mips2c' "$R" || fail "collide.txt must name the arm64 divergence (the value that differs from x86)"
grep -qiE 'before|baseline' "$R" || fail "collide.txt must document the calibrated BEFORE (device diverges, clips/crouches)"
grep -qiE 'after' "$R" || fail "collide.txt must document the AFTER (device == x86, no clip/crouch)"
grep -qiE 'device.*(==|=|match).*x86|1-?to-?1|identical' "$R" || fail "collide.txt must show device collision-state == x86 after the fix"
ok "x86-first collision diff: named arm64 divergence; device BEFORE(clip/crouch)->AFTER(==x86)"

# translation-layer fix; goal_src 1-to-1 (or documented pristine revert)
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goalc/' || fail "no translation-layer code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Gcollision-arm-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "translation-layer fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gcollide PASS] arm64 collision matches x86 (no wall clip-through, no stuck-crouch); divergence fixed in translation; goal_src 1-to-1."
