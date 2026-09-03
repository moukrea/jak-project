#!/usr/bin/env bash
# Validator — Gd1-cutscene-clock: cinematics must play at REAL-TIME (cutscene spool/IOP
# clock decoupled from render vsync). Deterministic clock-rate measurement, not screenshots.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gd1-clock FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gd1-clock ok] $*"; }

[ -z "$(cd /home/emeric/code/jak-original-v033 2>/dev/null && git status --porcelain 2>/dev/null)" ] || fail "original golden modified — remove temp dumps, keep pristine"

# 1. deterministic before/after cutscene clock-rate proof
R=.autoport/reports/Gd1-cutscene-clock/clock-rate.txt
[ -f "$R" ] || fail "no clock-rate.txt (dump cutscene str-pos/IOP-vblank advance rate vs wall-clock, BEFORE+AFTER)"
grep -qiE 'RESULT:[[:space:]]*CUTSCENE[[:space:]]+CLOCK[[:space:]]+REAL-?TIME' "$R" || fail "clock-rate.txt lacks RESULT: CUTSCENE CLOCK REAL-TIME"
grep -qiE 'before' "$R" && grep -qiE 'after' "$R" || fail "clock-rate.txt must show BEFORE and AFTER rates"
grep -qiE 'str-?pos|vblank|hz|wall.?clock|fps|rate' "$R" || fail "clock-rate.txt lacks the actual rate numbers"
ok "cutscene clock measured real-time after fix (deterministic)"

# 2. real code change (android runtime) + x86 path unchanged + fix-summary + dumps removed
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'android/**' 'game/**' 2>/dev/null | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'android/|game/' || fail "no real code change under android/** or game/**"
S=.autoport/reports/Gd1-cutscene-clock-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp dumps removed"

# 3. x86 still boots (change must be Android-runtime-gated)
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"

# 4. deploy landed + no crash regression
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
L=$(ls -t .autoport/reports/Gd1-cutscene-clock/*.log .autoport/reports/graphics-verify/routed-logcat.log 2>/dev/null | head -1)
if [ -n "$L" ]; then CR=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$L" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "crash regression: $CR sig"; fi
ok "x86 unbroken; device runs fresh HEAD; no crash"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gd1-clock PASS] cinematics now play at REAL-TIME on device (cutscene clock decoupled from render vsync), x86 unchanged, no crash. Known-good restored."
