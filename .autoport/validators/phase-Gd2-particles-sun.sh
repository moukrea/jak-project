#!/usr/bin/env bash
# Validator — Gd2-particles-sun: re-enable sp-process-block-3d on arm64 so 3D particles/
# stars/sun-corona render (the "halo" becomes a real sun). Deterministic bucket census, no screenshots.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gd2 FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gd2 ok] $*"; }

[ -z "$(cd /home/emeric/code/jak-original-v033 2>/dev/null && git status --porcelain 2>/dev/null)" ] || fail "original golden modified — remove temp dumps, keep pristine"

# 1. deterministic bucket census: 3D-particle/sun-corona buckets now >0 on device
C=.autoport/reports/Gd2-particles-sun/bucket-census.txt
[ -f "$C" ] || fail "no bucket-census.txt (device vs x86 3D-particle/sun-corona tris, BEFORE+AFTER)"
grep -qiE 'RESULT:[[:space:]]*3D[[:space:]]+PARTICLES[[:space:]]*\+?[[:space:]]*SUN[[:space:]]+RENDER' "$C" || fail "bucket-census.txt lacks RESULT: 3D PARTICLES + SUN RENDER"
grep -qiE 'before' "$C" && grep -qiE 'after' "$C" || fail "bucket-census.txt must show BEFORE and AFTER"
grep -qiE 'particle|sparticle|sun|corona|group-sun|tris|bucket' "$C" || fail "bucket-census.txt lacks the per-bucket tri numbers"
ok "3D particles + sun corona render on device after fix (deterministic census)"

# 2. real code change (un-noop in mips2c) + fix-summary + dumps removed
grep -qiE 'sp-process-block-3d' game/mips2c/mips2c_table_jak1_arm64.cpp 2>/dev/null || fail "sp-process-block-3d not referenced in the arm64 mips2c table (expected the un-noop)"
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'goal_src/**' 2>/dev/null | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|goal_src/' || fail "no real code change"
S=.autoport/reports/Gd2-particles-sun-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp dumps removed"

# 3. x86 boots + deploy + NO crash at frame ~190+ (the reason it was noop'd)
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
L=$(ls -t .autoport/reports/Gd2-particles-sun/*.log .autoport/reports/graphics-verify/routed-logcat.log 2>/dev/null | head -1)
if [ -n "$L" ]; then
  CR=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$L" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "crash regression (the frame-190 SIGSEGV?): $CR sig"
  FM=$(grep -aoE 'frame=[0-9]+' "$L" | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}; [ "$FM" -ge 600 ] || fail "did not sustain past frame 190 (frame=$FM)"
fi
ok "x86 unbroken; device runs fresh HEAD; no frame-190 crash; sustains"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gd2 PASS] 3D particles/stars + the real sun corona now RENDER on device (sp-process-block-3d re-enabled, frame-190 crash fixed), x86 unchanged, crash-free. Known-good restored."
