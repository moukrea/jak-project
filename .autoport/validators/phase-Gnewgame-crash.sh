#!/usr/bin/env bash
# Phase Gnewgame-crash validator — the new-game→cinematic crash must be gone.
# Forensics + DATA gated (crash signature absent, deploy verified). The cinematic
# "actually plays" is owner-verified. Hard anti-grind. deploy_verify enforces landing.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
echo "== Phase Gnewgame-crash validator =="

# 1. Forbidden edits + anti-grind + disk.
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 edited"
BIGV=$(find .autoport/reports -name '*.mp4' -size +20M 2>/dev/null | wc -l); [ "$BIGV" -eq 0 ] || fail "ANTI-GRIND: $BIGV large .mp4 present"
DFREE=$(df --output=avail -BG . 2>/dev/null | tail -1 | tr -dc '0-9'); [ "${DFREE:-99}" -ge 5 ] || fail "disk nearly full (${DFREE}G)"
ok "no forbidden edits; no grind; disk ok (${DFREE}G)"

# 2. Crash forensics + fix-summary naming the mechanism.
[ -f .autoport/reports/Gnewgame/crash-logcat.log ] || fail "no crash-logcat.log (must reproduce + capture the crash)"
SUM=.autoport/reports/Gnewgame-crash-fix-summary.md
[ -f "$SUM" ] || fail "no Gnewgame-crash-fix-summary.md"
[ "$(wc -l < "$SUM")" -ge 60 ] || fail "fix-summary too short"
grep -qiE 'sig|crash|fault|backtrace|function|new.?game|cinematic' "$SUM" || fail "summary doesn't name the crash"
grep -qiE 'x86|oracle|arm64|idiv|mod|float|field|offset|regalloc|mips2c|128' "$SUM" || fail "summary lacks the arm64-mechanism oracle-diff"
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 'game/**' 2>/dev/null | wc -l); [ "$CHG" -ge 1 ] || fail "no code fix landed"
ok "crash forensics + mechanism + fix present"

# 3. x86 unbroken.
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 smoke passes"

# 4. DEPLOY LANDS (device provably runs fresh HEAD).
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running the fresh HEAD build"
ok "deploy verified (fresh HEAD on device)"

# 5. The crash is GONE on a fresh device run (no sig=11 at/after new-game), boot sustained.
NEWLOG=$(ls -t .autoport/reports/Gnewgame-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gnewgame routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11|signal 4 \(SIGILL\)" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH still present: $CR signal events"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}; [ "$FM" -ge 300 ] || fail "boot not sustained: frame=$FM"
ok "no crash signature, boot sustained (frame=$FM)"

echo ""
echo "PASS(data): Gnewgame-crash — crash signature gone, deploy verified, x86 OK. OWNER eye-confirms the intro cinematic actually plays on NEW GAME."
