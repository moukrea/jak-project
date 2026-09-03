#!/usr/bin/env bash
# Phase Gcine-crash2 validator — the LATER cinematic crash must be gone (full
# play-through). Forensics + DATA gated; deploy-verified; anti-grind.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
echo "== Phase Gcine-crash2 validator =="

[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 edited"
BIGV=$(find .autoport/reports -name '*.mp4' -size +20M 2>/dev/null | wc -l); [ "$BIGV" -eq 0 ] || fail "ANTI-GRIND: $BIGV large .mp4"
DFREE=$(df --output=avail -BG . 2>/dev/null | tail -1 | tr -dc '0-9'); [ "${DFREE:-99}" -ge 5 ] || fail "disk full (${DFREE}G)"
ok "no forbidden edits; no grind; disk ok (${DFREE}G)"

[ -f .autoport/reports/Gcine2/crash-logcat.log ] || fail "no Gcine2/crash-logcat.log (must reproduce the crash)"
SUM=.autoport/reports/Gcine2-crash-fix-summary.md
[ -f "$SUM" ] || fail "no Gcine2-crash-fix-summary.md"
[ "$(wc -l < "$SUM")" -ge 60 ] || fail "fix-summary too short"
grep -qiE 'sig|crash|fault|backtrace|scene|cinematic' "$SUM" || fail "summary doesn't name the crash/scene"
grep -qiE 'x86|oracle|arm64|hi32|high.32|mips2c|idiv|float|field|offset|regalloc|128' "$SUM" || fail "summary lacks arm64-mechanism oracle-diff"
[ "$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 'game/**' 2>/dev/null | wc -l)" -ge 1 ] || fail "no code fix landed"
ok "crash forensics + mechanism + fix present"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 smoke passes"

bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "deploy verified"

NEWLOG=$(ls -t .autoport/reports/Gcine2-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gcine2 routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal (11|6|4)|signal 4 \(SIGILL\)|signal 6 \(SIGABRT\)" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH still present: $CR signal events through the cinematic"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}; [ "$FM" -ge 9000 ] || fail "cinematic did not play past the prior crash point: frame=$FM (<9000)"
ok "no crash signature through the cinematic, frame=$FM"

echo ""
echo "PASS(data): Gcine-crash2 — later cinematic crash gone (frame=$FM, deploy-verified, x86 OK). OWNER eye-confirms the FULL cinematic plays through to gameplay."
