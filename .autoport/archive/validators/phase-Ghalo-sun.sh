#!/usr/bin/env bash
# Validator — Ghalo-sun: the title sun-halo (a lighting/sun-state bug) must be GONE,
# verified by DETERMINISTIC sun-cycle STATE DUMPS compared x86-FIRST — not screenshots.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Ghalo-sun FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Ghalo-sun ok] $*"; }

# golden reference must stay pristine
[ -z "$(cd /home/emeric/code/jak-original-v033 2>/dev/null && git status --porcelain 2>/dev/null)" ] || fail "original golden (jak-original-v033) was modified — remove all temp dump instrumentation, keep it pristine"

# 1. x86-first sun/glow state dump: our-x86 == original across the sun cycle
X=.autoport/reports/Ghalo-sun/state-dump-x86.txt
[ -f "$X" ] || fail "no state-dump-x86.txt (dump+diff our-x86 sun/glow state vs original-x86 across the sun cycle FIRST)"
grep -qiE 'RESULT:[[:space:]]*X86[[:space:]]+MATCHES[[:space:]]+ORIGINAL' "$X" || fail "our-x86 sun/glow state does NOT match the original across the cycle"
grep -qiE 'sun|glow|intensit|elevation|corona|bloom|sunrise|phase' "$X" || fail "state-dump-x86.txt lacks the actual sun/glow numbers across the cycle"

# 2. device sun/glow state matches original (no spurious halo at sun-up, correct re-arm)
D=.autoport/reports/Ghalo-sun/state-dump-device.txt
[ -f "$D" ] || fail "no state-dump-device.txt (dump+diff DEVICE sun/glow state vs original across the cycle)"
grep -qiE 'RESULT:[[:space:]]*SUN[[:space:]]+STATE[[:space:]]+MATCHES[[:space:]]+ORIGINAL' "$D" || fail "device sun/glow state does NOT match the original across the cycle"
grep -qiE 'sun|glow|intensit|elevation|sunrise|phase' "$D" || fail "state-dump-device.txt lacks the device sun/glow numbers"
ok "sun/glow state matches the original across the cycle (x86 + device), deterministic dump"

# 3. fix-summary + real code change + dumps removed
S=.autoport/reports/Ghalo-sun-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "Ghalo-sun-fix-summary.md missing or <60 lines"
grep -qiE 'remov|deleted|reverted.*dump|dump.*removed|no leftover' "$S" || fail "fix-summary must confirm dump instrumentation REMOVED"
git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 'game/**' 2>/dev/null | grep -q . || git status --porcelain 2>/dev/null | grep -qE 'goal_src/|game/' || fail "no real code change under goal_src/** or game/**"

# 4. x86 boots + deploy landed + no crash regression
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
L=$(ls -t .autoport/reports/graphics-verify/routed-logcat.log 2>/dev/null | head -1)
if [ -n "$L" ]; then CR=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$L" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "crash regression: $CR sig"; fi
ok "x86 boots; device runs fresh HEAD; no crash"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Ghalo-sun PASS] title sun-halo OBJECTIVELY gone: sun/glow state matches the original across the day/night cycle (x86==original, device==original), no crash. Verified by deterministic dumps, not screenshots. Known-good restored."
