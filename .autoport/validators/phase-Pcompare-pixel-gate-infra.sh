#!/usr/bin/env bash
# Phase Pcompare validator — the objective pixel-compare gate must EXIST and WORK.
# Self-tests the diff tool itself (identical->match, different->mismatch), checks
# goldens were captured, and that the oracle repo was left pristine.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase Pcompare validator (objective pixel-compare gate) =="

# 1. The compare tool exists. Resolve how to invoke it.
TOOL=""; RUN=()
if [ -f .autoport/lib/frame_compare.py ]; then TOOL=.autoport/lib/frame_compare.py; RUN=(python3 "$TOOL")
elif [ -f .autoport/lib/frame_compare.sh ]; then TOOL=.autoport/lib/frame_compare.sh; RUN=(bash "$TOOL")
else fail "no .autoport/lib/frame_compare.{py,sh}"; fi
ok "compare tool present: $TOOL"

# 2. Goldens captured (>=3 non-trivial PNGs).
GDIR=.autoport/gold/pristine-frames
NG=$(ls "$GDIR"/*.png 2>/dev/null | wc -l); [ "$NG" -ge 3 ] || fail "only $NG goldens in $GDIR (need >=3)"
BIG=$(find "$GDIR" -name '*.png' -size +20k 2>/dev/null | wc -l); [ "$BIG" -ge 3 ] || fail "goldens look empty/trivial ($BIG non-trivial)"
GOLD=$(ls "$GDIR"/*.png | head -1)
ok "goldens present ($NG, $BIG non-trivial)"

# 3. SELF-TEST the tool ourselves (don't trust the worker's selftest.txt alone).
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
cp "$GOLD" "$TMP/a.png"; cp "$GOLD" "$TMP/b.png"
# identical -> MATCH (exit 0)
if "${RUN[@]}" "$TMP/a.png" "$TMP/b.png" >/dev/null 2>&1; then ok "identical pair -> MATCH (exit 0)"; else fail "tool reports MISMATCH on identical images — broken gate"; fi
# black frame, same dims -> MISMATCH (nonzero). Need ImageMagick.
DIMS=$(identify -format '%wx%h' "$GOLD" 2>/dev/null || echo "")
[ -n "$DIMS" ] || fail "imagemagick 'identify' unavailable — cannot self-test"
convert -size "$DIMS" xc:black "$TMP/black.png" 2>/dev/null || fail "could not synthesize black frame"
if "${RUN[@]}" "$GOLD" "$TMP/black.png" >/dev/null 2>&1; then fail "tool reports MATCH golden-vs-black — gate not sensitive"; else ok "golden-vs-black -> MISMATCH (nonzero)"; fi

# 4. Self-test evidence + summary present.
[ -f .autoport/reports/Pcompare/selftest.txt ] || fail "no .autoport/reports/Pcompare/selftest.txt"
[ -f .autoport/reports/Pcompare-fix-summary.md ] || fail "no Pcompare-fix-summary.md"
grep -qiE 'anchor|frame|golden|toleran|metric|diff' .autoport/reports/Pcompare-fix-summary.md || fail "summary lacks capture-anchor/metric detail"
ok "self-test evidence + summary present"

# 5. Oracle repo left PRISTINE (temp dump-hook reverted).
ORACLE=/home/emeric/code/jak-original-v033
if [ -d "$ORACLE/.git" ]; then
  DIRTY=$(git -C "$ORACLE" status --porcelain 2>/dev/null | head -5)
  [ -z "$DIRTY" ] || fail "oracle repo left MODIFIED (temp hook not reverted): $DIRTY"
  HEAD=$(git -C "$ORACLE" rev-parse --short HEAD 2>/dev/null)
  [ "$HEAD" = "c4bc4d3ff" ] || echo "  warn: oracle HEAD=$HEAD (expected c4bc4d3ff)"
  ok "oracle repo pristine (clean tree)"
fi

# 6. Our repo: no game/compiler fix slipped in (tooling-only phase).
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
NF=$(git diff "$ANCHOR" HEAD -- goalc/ goal_src/ game/ android/ 2>/dev/null | wc -l)
[ "$NF" -eq 0 ] || fail "Pcompare is tooling-only but goalc/goal_src/game/android changed ($NF lines)"
ok "tooling-only (no game/compiler fix)"

echo ""
echo "PASS: Phase Pcompare — objective pixel-compare gate built + self-tested; $NG goldens captured; oracle pristine. Intro/title phases can now gate on device-vs-golden."
