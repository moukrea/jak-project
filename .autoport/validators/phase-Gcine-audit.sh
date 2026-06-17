#!/usr/bin/env bash
# Phase Gcine-audit validator — DIAGNOSTIC. Objective new-game cinematic divergence
# map vs the x86 oracle (camera/scene DATA diff + bounded matched-beat pixel diff).
# No device fix. Anti-fiction: real x86 + arm64 capture artifacts must exist.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
echo "== Phase Gcine-audit validator =="

# 1. Forbidden edits + anti-grind + disk.
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 edited"
BIGV=$(find .autoport/reports -name '*.mp4' -size +20M 2>/dev/null | wc -l); [ "$BIGV" -eq 0 ] || fail "ANTI-GRIND: $BIGV large .mp4"
DFREE=$(df --output=avail -BG . 2>/dev/null | tail -1 | tr -dc '0-9'); [ "${DFREE:-99}" -ge 5 ] || fail "disk full (${DFREE}G)"
ok "no forbidden edits; no grind; disk ok (${DFREE}G)"

# 2. The divergence map exists, is substantive, has a method + ranked findings.
MAP=.autoport/reports/Gcine-audit/divergences.md
[ -f "$MAP" ] || fail "no Gcine-audit/divergences.md"
[ "$(wc -l < "$MAP")" -ge 50 ] || fail "divergence map too short (<50 lines)"
grep -qiE 'method|aligned|frame counter|tolerance|metric' "$MAP" || fail "map lacks a method/tolerance section"
grep -qiE 'camera|cadence|transition|water|green|glow|lighting|render' "$MAP" || fail "map doesn't address the cinematic issue categories"
grep -qiE 'frame|beat' "$MAP" || fail "divergence entries must cite a frame/beat"
grep -qiE 'fix order|recommend|priority|rank' "$MAP" || fail "map lacks a recommended fix order/ranking"
ok "divergence map present, substantive, ranked"

# 3. Anti-fiction: REAL capture artifacts (x86 + arm64) must exist, non-trivial size.
AUD=.autoport/reports/Gcine-audit
X86=$(find "$AUD" -type f \( -iname '*x86*' -o -iname '*oracle*' \) -size +2k 2>/dev/null | head -1)
ARM=$(find "$AUD" -type f \( -iname '*arm*' -o -iname '*device*' -o -iname '*eae4df44*' \) -size +2k 2>/dev/null | head -1)
[ -n "$X86" ] || fail "no x86/oracle capture artifact (>2k) under $AUD — divergence claims unbacked"
[ -n "$ARM" ] || fail "no arm64/device capture artifact (>2k) under $AUD — divergence claims unbacked"
ok "real capture artifacts present: x86=$(basename "$X86") arm64=$(basename "$ARM")"

# 4. x86 oracle still boots (instrumentation didn't break it).
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 smoke passes"

echo ""
echo "PASS(diag): Gcine-audit — objective cinematic divergence map produced (x86-vs-arm64, evidence-backed). Supervisor triages into single-defect fix phases."
