#!/usr/bin/env bash
# Phase Gref-en validator — capture the English pristine intro reference frames
# + pixel-diff the phone against them. Reference/audit phase: NO engine edits.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
ANCHOR=${SUP_ANCHOR:-HEAD}
GREF_CLOSE=$(git log --format=%H --all --grep='autoport/Gref-pristine' | head -1); GREF_CLOSE=${GREF_CLOSE:-$ANCHOR}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase Gref-en validator (English pristine reference frames + phone audit) =="

# 1. Reference-only — must NOT modify engine/compiler/game.
for area in 'goalc/' 'game/' 'goal_src/' 'android/'; do
  n=$(git diff "$ANCHOR" HEAD -- "$area" 2>/dev/null | wc -l)
  [ "$n" -eq 0 ] || fail "$area modified — Gref-en is reference/audit only, no engine edits"
done
n=$(git diff HEAD -- 'goalc/' 'game/' 'goal_src/' 'android/' 2>/dev/null | wc -l)
[ "$n" -eq 0 ] || fail "engine modified (unstaged) — reference-only phase"
# Existing gold core read-only; adding pristine-en/ allowed.
GOLD_CORE=$(git diff --name-only "$GREF_CLOSE" HEAD -- '.autoport/gold/' 2>/dev/null | grep -vE '^\.autoport/gold/pristine-en/' || true)
[ -z "$GOLD_CORE" ] || fail "existing gold reference modified (read-only): $GOLD_CORE"
ok "reference-only (no engine/compiler/game edits)"

# 2. Required summary + divergence doc
[ -f .autoport/reports/Grefen-fix-summary.md ] || fail "no Grefen-fix-summary.md"
LINES=$(wc -l < .autoport/reports/Grefen-fix-summary.md); [ "$LINES" -ge 80 ] || fail "Grefen-fix-summary.md too short ($LINES)"
grep -qiE 'pristine|divergen|beat|phone.*gold|gold.*phone' .autoport/reports/Grefen-fix-summary.md || fail "summary lacks the pristine-vs-phone divergence analysis"
[ -f .autoport/reports/Grefen-divergences.md ] || fail "no .autoport/reports/Grefen-divergences.md (the per-beat divergence list)"
ok "summary + divergence doc present ($LINES lines)"

# 3. English pristine reference frames captured (>=3 beats)
PEN=$(ls .autoport/gold/pristine-en/*.png 2>/dev/null | wc -l)
[ "$PEN" -ge 3 ] || fail "only $PEN pristine-en frames (need >=3 beats: ndi/logo/title/menu) in .autoport/gold/pristine-en/"
# Frames must be real (non-trivial size, not all identical/black).
BIG=$(find .autoport/gold/pristine-en -name '*.png' -size +20k 2>/dev/null | wc -l)
[ "$BIG" -ge 2 ] || fail "pristine-en frames look empty/trivial (need >=2 non-trivial) — capture likely failed"
ok "English pristine reference captured ($PEN frames, $BIG non-trivial)"

# 4. Phone capture present
SHOT=$(ls .autoport/reports/Grefen-device-*.png 2>/dev/null | head -1); [ -n "$SHOT" ] || fail "no Grefen-device-*.png phone capture"
[ "$(stat -c %s "$SHOT" 2>/dev/null||echo 0)" -gt 1000 ] || fail "phone screencap empty"
ok "phone capture present: $(basename "$SHOT")"

# 5. Our x86 still boots (sanity)
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "our x86 smoke regressed"; }
ok "our x86 smoke still passes"

echo ""
echo "PASS: Phase Gref-en — English pristine reference frames captured ($PEN) + phone divergence audit. Supervisor reviews the diff to drive one-at-a-time fixes."
