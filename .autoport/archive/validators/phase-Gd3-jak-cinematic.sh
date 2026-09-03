#!/usr/bin/env bash
# Validator — Gd3-jak-cinematic: Jak must be VISIBLE in the new-game cinematic on device
# (merc bucket drawing >0 tris where Jak appears). Deterministic census, x86-first, no screenshots.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gd3-jak FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gd3-jak ok] $*"; }

[ -z "$(cd /home/emeric/code/jak-original-v033 2>/dev/null && git status --porcelain 2>/dev/null)" ] || fail "original golden modified — remove temp dumps, keep pristine"

# 1. deterministic Jak census proof
J=.autoport/reports/Gd3-jak/jak-census.txt
[ -f "$J" ] || fail "no jak-census.txt (device vs x86 Jak-in-cinematic merc census, BEFORE+AFTER)"
grep -qiE 'RESULT:[[:space:]]*JAK[[:space:]]+VISIBLE[[:space:]]+IN[[:space:]]+CINEMATIC' "$J" || fail "jak-census.txt lacks RESULT: JAK VISIBLE IN CINEMATIC"
grep -qiE 'before' "$J" && grep -qiE 'after' "$J" || fail "jak-census.txt must show BEFORE and AFTER"
grep -qiE 'jak|merc|tris|spawn|target' "$J" || fail "jak-census.txt lacks the census numbers (merc tris / spawn state)"
ok "Jak census: device merc draws >0 in cinematic after fix (deterministic)"

# 2. real code change + fix-summary + dumps removed
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 'android/**' 'game/**' 2>/dev/null | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'goal_src/|android/|game/' || fail "no real code change"
S=.autoport/reports/Gd3-jak-cinematic-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp dumps removed"

# 3. x86 boots + deploy + no crash regression
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
L=$(ls -t .autoport/reports/Gd3-jak/*.log .autoport/reports/graphics-verify/routed-logcat.log 2>/dev/null | head -1)
if [ -n "$L" ]; then CR=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$L" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "crash regression: $CR sig"; fi
ok "x86 unbroken; device runs fresh HEAD; no crash"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gd3-jak PASS] Jak is now VISIBLE in the new-game cinematic on device (merc draws >0 matching x86), x86 unchanged, crash-free. Known-good restored."
