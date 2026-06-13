#!/usr/bin/env bash
# Phase Gref validator — pristine upstream x86 gold standard + 3-tier harness.
# This is a REFERENCE-build phase, not an engine fix: it must NOT modify our
# compiler/engine, and it must produce a real pristine build + Tier-A diff +
# pristine boot-sequence reference + comparison harness.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase Gref validator (pristine x86 gold standard) =="

# 1. Must NOT modify our engine/compiler/source (this phase only adds .autoport/gold/).
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
ANCHOR=${SUP_ANCHOR:-HEAD}
for area in 'goalc/' 'game/' 'goal_src/' 'android/'; do
  n=$(git diff "$ANCHOR" HEAD -- "$area" 2>/dev/null | wc -l)
  [ "$n" -eq 0 ] || fail "$area was modified — Gref is a reference build, it must not touch our engine/compiler"
done
n=$(git diff HEAD -- 'goalc/' 'game/' 'goal_src/' 'android/' 2>/dev/null | wc -l)
[ "$n" -eq 0 ] || fail "engine/compiler modified (unstaged) — Gref must only add .autoport/gold/"
ok "no engine/compiler edits (reference-only)"

# 2. Required summary with a Tier-A verdict
[ -f .autoport/reports/Gref-summary.md ] || fail "no Gref-summary.md"
LINES=$(wc -l < .autoport/reports/Gref-summary.md)
[ "$LINES" -ge 80 ] || fail "Gref-summary.md too short ($LINES lines, need >=80)"
grep -qiE 'tier.?a|pristine|gold|704972dd6' .autoport/reports/Gref-summary.md || fail "summary doesn't engage the gold-standard / Tier-A comparison"
ok "Gref-summary.md present ($LINES lines)"

# 3. Pristine gk ELF under .autoport/gold/, distinct from our build
GOLD_GK=$(find .autoport/gold -name 'gk' -type f 2>/dev/null | head -1)
[ -n "$GOLD_GK" ] || fail "no pristine gk under .autoport/gold/ (the gold build must be produced)"
file "$GOLD_GK" 2>/dev/null | grep -qiE 'ELF|executable' || fail "$GOLD_GK is not a real ELF executable"
SZ=$(stat -c %s "$GOLD_GK" 2>/dev/null || echo 0)
[ "$SZ" -gt 1000000 ] || fail "pristine gk looks too small ($SZ bytes) — not a real build"
# Must be genuinely built from the pristine commit, not a copy of our gk.
OUR_GK=$(find build-x86 -name 'gk' -type f 2>/dev/null | head -1)
if [ -n "$OUR_GK" ]; then
  cmp -s "$GOLD_GK" "$OUR_GK" && fail "pristine gk is byte-identical to OUR gk — likely a copy, not a pristine build from 704972dd6"
fi
ok "pristine gk present and distinct from our build ($SZ bytes)"

# 4. Tier-A CGO diff report with a verdict
[ -f .autoport/gold/tierA-cgo-diff.md ] || fail "no .autoport/gold/tierA-cgo-diff.md (gold vs our-x86 CGO comparison required)"
grep -qiE 'identical|diverge|divergent' .autoport/gold/tierA-cgo-diff.md || fail "tierA-cgo-diff.md has no per-object verdict (identical/divergent)"
ok "Tier-A CGO diff present"

# 5. Pristine boot-sequence reference, non-trivial, with intro/title markers
SEQ=.autoport/gold/pristine-boot-sequence.log
[ -f "$SEQ" ] || fail "no .autoport/gold/pristine-boot-sequence.log (the chronological reference)"
[ "$(wc -l < "$SEQ")" -ge 50 ] || fail "pristine-boot-sequence.log too short to be a real capture"
grep -qiE 'enter-state|set-master-mode|title|intro|logo|link finish' "$SEQ" || fail "pristine sequence has no recognizable boot/intro/title markers"
ok "pristine boot-sequence reference captured"

# 6. Comparison harness present + executable
H=.autoport/gold/compare-3tier.sh
[ -f "$H" ] || fail "no .autoport/gold/compare-3tier.sh harness"
[ -x "$H" ] || fail "compare-3tier.sh not executable"
ok "3-tier comparison harness present"

# 7. Our x86 still boots (sanity — Gref must not have disturbed it)
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "our x86 smoke regressed"; }
ok "our x86 smoke still passes (link finish: logo)"

echo ""
echo "PASS: Phase Gref — pristine gold standard built; Tier-A verdict recorded; chronological reference + 3-tier harness ready."
