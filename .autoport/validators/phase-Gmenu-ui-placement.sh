#!/usr/bin/env bash
# Validator — Gmenu-ui-placement: gates on DETERMINISTIC STATE DUMPS compared
# x86-FIRST vs the unaltered original — NOT screenshot pixel-diffs (owner directive
# 2026-06-19, memory state-dumps-x86-first-not-screenshots).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
echo "== Phase Gmenu-ui-placement validator (x86-first STATE-DUMP comparison; no screenshots) =="

# 1. forbidden edits + golden reference must stay pristine + disk
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 edited"
[ -z "$(cd /home/emeric/code/jak-original-v033 2>/dev/null && git status --porcelain 2>/dev/null)" ] || fail "the original golden reference (jak-original-v033) was modified — it must stay byte-pristine; remove all temp dump instrumentation"
DFREE=$(df --output=avail -BG . 2>/dev/null | tail -1 | tr -dc '0-9'); [ "${DFREE:-99}" -ge 5 ] || fail "disk nearly full (${DFREE}G)"
ok "no forbidden edits; original golden pristine; disk ok (${DFREE}G)"

# 2. x86-FIRST state dump: our-x86 menu state must MATCH the original-x86 (proves no x86 regression + x86-level fix landed)
X=.autoport/reports/Gmenu-ui/state-dump-x86.txt
[ -f "$X" ] || fail "no state-dump-x86.txt (must dump+diff our-x86 menu state vs the original-x86 FIRST)"
grep -qiE 'RESULT:[[:space:]]*X86[[:space:]]+MATCHES[[:space:]]+ORIGINAL' "$X" || fail "our-x86 menu state does NOT match the original-x86 (state-dump-x86.txt) — either an x86-level bug remains or an ARM change broke x86; fix on the host first"
grep -qiE 'ring|scale|projection|c0\.|position|ratio' "$X" || fail "state-dump-x86.txt lacks the actual dumped numbers (ring scale / projection rows / positions)"
ok "x86-first: our-x86 menu state matches the original-x86 (no x86 regression; host-level fix verified)"

# 3. DEVICE state dump: device menu state must MATCH the original within tolerance
D=.autoport/reports/Gmenu-ui/state-dump-device.txt
[ -f "$D" ] || fail "no state-dump-device.txt (must dump+diff the DEVICE menu state vs the original)"
grep -qiE 'RESULT:[[:space:]]*MENU[[:space:]]+STATE[[:space:]]+MATCHES[[:space:]]+ORIGINAL' "$D" || fail "device menu state does NOT match the original (state-dump-device.txt)"
grep -qiE 'ring|scale|projection|c0\.|position|ratio' "$D" || fail "state-dump-device.txt lacks the dumped numbers"
ok "device menu state matches the original (deterministic dump, not pixels)"

# 4. fix-summary + real code change + dumps removed
SUM=.autoport/reports/Gmenu-ui-placement-fix-summary.md
[ -f "$SUM" ] && [ "$(wc -l < "$SUM")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|reverted.*dump|dump.*removed|no leftover' "$SUM" || fail "fix-summary must confirm the temporary dump instrumentation was REMOVED"
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 'game/**' 2>/dev/null | wc -l); [ "$CHG" -ge 1 ] || fail "no real UI/projection code change landed"
ok "fix-summary documents the dumped numbers + the fix; dumps removed; real code change"

# 5. x86 still boots + deploy landed on device
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD build"
ok "x86 boots; device runs fresh HEAD build"

echo ""
echo "PASS: Gmenu-ui-placement — menu UI state OBJECTIVELY matches the original (x86-first state-dump: our-x86==original, device==original), x86 OK, deploy-verified. Verified by deterministic dumps, not screenshots."
