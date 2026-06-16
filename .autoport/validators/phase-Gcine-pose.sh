#!/usr/bin/env bash
# Phase Gcine-pose validator — cinematic character "pose blink" glitch must be GONE,
# proven by an OBJECTIVE joint-sanity tripwire (before>0 -> after=0), not eyeballing.
# DATA/oracle-diff gated; deploy-verified; anti-grind. Final smoothness = owner-eye.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
echo "== Phase Gcine-pose validator =="

# 1. Forbidden edits + anti-grind + disk.
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 edited"
BIGV=$(find .autoport/reports -name '*.mp4' -size +20M 2>/dev/null | wc -l); [ "$BIGV" -eq 0 ] || fail "ANTI-GRIND: $BIGV large .mp4"
DFREE=$(df --output=avail -BG . 2>/dev/null | tail -1 | tr -dc '0-9'); [ "${DFREE:-99}" -ge 5 ] || fail "disk full (${DFREE}G)"
ok "no forbidden edits; no grind; disk ok (${DFREE}G)"

# 2. Objective joint-sanity tripwire: before>0 (reproduced) -> after=0 (fixed).
JS=.autoport/reports/Gpose/joint-sanity.txt
[ -f "$JS" ] || fail "no Gpose/joint-sanity.txt (must objectively measure the pose-glitch)"
BEFORE=$(grep -aoiE 'before[^0-9]*[0-9]+' "$JS" | grep -oE '[0-9]+' | head -1)
AFTER=$(grep -aoiE 'after[^0-9]*[0-9]+'  "$JS" | grep -oE '[0-9]+' | head -1)
[ -n "${BEFORE:-}" ] && [ -n "${AFTER:-}" ] || fail "joint-sanity.txt must report 'before N' and 'after N' glitch-frame counts"
[ "$BEFORE" -gt 0 ] || fail "glitch not reproduced (before=$BEFORE, must be >0)"
[ "$AFTER" -eq 0 ] || fail "pose-glitch still present (after=$AFTER glitch frames, must be 0)"
ok "joint-sanity tripwire: before=$BEFORE -> after=$AFTER (glitch eliminated)"

# 3. Forensic summary naming the function + scene + arm64 mechanism + oracle-diff.
SUM=.autoport/reports/Gpose-fix-summary.md
[ -f "$SUM" ] || fail "no Gpose-fix-summary.md"
[ "$(wc -l < "$SUM")" -ge 60 ] || fail "fix-summary too short"
grep -qiE 'joint|merc|skeleton|pose|anim|blend' "$SUM" || fail "summary doesn't name the joint/merc/pose path"
grep -qiE 'x86|oracle|arm64|hi32|high.32|mips2c|noop|idiv|float|field|offset|regalloc|128' "$SUM" || fail "summary lacks arm64-mechanism oracle-diff"
grep -qiE 'before|after|tripwire|sanity|glitch.?frame' "$SUM" || fail "summary doesn't document the objective metric"
[ "$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 'game/**' 2>/dev/null | wc -l)" -ge 1 ] || fail "no code fix landed"
ok "forensics + mechanism + metric + fix present"

# 4. x86 unbroken.
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 smoke passes"

# 5. Deploy lands.
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "deploy verified"

# 6. Cinematic still plays fully through, crash-free (no regression of Gcine-crash2).
NEWLOG=$(ls -t .autoport/reports/Gpose-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gpose routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal (11|6|4)|signal 4 \(SIGILL\)|signal 6 \(SIGABRT\)" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH regressed: $CR signal events"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}; [ "$FM" -ge 9000 ] || fail "cinematic regressed: frame=$FM (<9000)"
ok "cinematic still plays through crash-free, frame=$FM"

echo ""
echo "PASS(data): Gcine-pose — pose-glitch eliminated (joint-sanity $BEFORE->0), cinematic plays through (frame=$FM), deploy-verified, x86 OK. OWNER eye-confirms smooth poses (no blinks)."
