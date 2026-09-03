#!/usr/bin/env bash
# Validator — Grender-audit: a DIAGNOSTIC phase. Gates on a deterministic, x86-first
# ranked divergence map (game-clock/half-speed, missing buckets, merc/Jak, sun) —
# NOT a code fix. No screenshot/video grind.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Grender-audit FAIL] $*" >&2; exit 1; }
ok(){ echo "  ok: $*"; }
echo "== Phase Grender-audit validator (deterministic render-divergence map) =="

# anti-grind + golden pristine
BIGV=$(find .autoport/reports -name '*.mp4' -size +20M 2>/dev/null | wc -l); [ "$BIGV" -eq 0 ] || fail "ANTI-GRIND: large .mp4 present"
[ -z "$(cd /home/emeric/code/jak-original-v033 2>/dev/null && git status --porcelain 2>/dev/null)" ] || fail "original golden (jak-original-v033) modified — remove temp dump instrumentation, keep pristine"

M=.autoport/reports/Grender-audit/divergences.md
[ -f "$M" ] || fail "no divergences.md (the ranked render-divergence map is the deliverable)"
[ "$(wc -l < "$M")" -ge 40 ] || fail "divergences.md too thin (<40 lines)"

# D1: game-clock rate measured for BOTH device and x86 (the half-speed factor)
grep -qiE 'half|game.?clock|frames?.?per|fps|base-frame|vsync|tick|delta.?time|rate' "$M" || fail "D1 missing: no game-clock/half-speed measurement"
grep -qiE 'device' "$M" && grep -qiE 'x86|original' "$M" || fail "D1 must give the rate for BOTH device and x86 (the half-speed comparison)"

# D2: per-bucket census naming a missing/empty bucket + cause
grep -qiE 'bucket|sparticle|particle|merc|sun|sky|noop|allowlist|excluded|mips2c' "$M" || fail "D2 missing: no per-bucket census / missing-bucket cause"

# D3: merc/Jak verdict
grep -qiE 'jak|merc' "$M" || fail "D3 missing: no Jak-invisible / merc verdict"

# ranked fix order + raw artifacts
grep -qiE 'fix order|priorit|rank|recommend|D1|D2|D3' "$M" || fail "no ranked fix order"
RAW=$(ls .autoport/reports/Grender-audit/ 2>/dev/null | grep -vc 'divergences.md'); [ "${RAW:-0}" -ge 1 ] || fail "no raw dump artifacts under .autoport/reports/Grender-audit/"
ok "divergences.md: D1 half-speed (device vs x86) + D2 missing-bucket census + D3 merc/Jak + ranked fix order + raw dumps"

echo ""
echo "[Grender-audit PASS] deterministic, x86-first render-divergence map produced (half-speed clock rate, missing buckets, merc/Jak, sun). Supervisor triages into single-defect fix phases."
