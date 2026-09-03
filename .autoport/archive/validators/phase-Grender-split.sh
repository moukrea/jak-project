#!/usr/bin/env bash
# Validator — Grender-split: 3D scaled + UI native, renderer-side (both builds). Accepts an HONEST
# "blocked" outcome (the engine renderer is historically locked). Objective markers + x86 smoke;
# device-consistency + owner play-test enforced by the close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gsplit FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gsplit ok] $*"; }

R=.autoport/reports/Grender-split/report.txt
[ -f "$R" ] || fail "no report.txt"
# Two acceptable RESULTs: a real split, OR an honest documented blocker (no false-green either way).
if grep -qiE 'RESULT:[[:space:]]*RENDER[[:space:]]+SPLIT[[:space:]]+BLOCKED' "$R"; then
  grep -qiE 'block|cannot|breaks|lbox|letterbox|depth|sprite|pcrtc|locked' "$R" || fail "BLOCKED claimed but no concrete blocker named"
  grep -qiE 'safe.*partial|next|would need|recommend' "$R" || fail "BLOCKED must state what a safe partial / next step is"
  echo "[Gsplit PASS] honest BLOCKED outcome with a named blocker (no false-green; owner decides next)"
  exit 0
fi
grep -qiE 'RESULT:[[:space:]]*RENDER[[:space:]]+SPLIT[[:space:]]+UI-?NATIVE[[:space:]]+3D-?SCALED' "$R" \
  || fail "report lacks RESULT: RENDER SPLIT UI-NATIVE 3D-SCALED (or RENDER SPLIT BLOCKED)"
grep -qiE 'crisp.*UI|UI.*crisp|HUD.*native|text.*native|native.*text' "$R" || fail "must show UI/HUD/text stays NATIVE-crisp"
grep -qiE '3d.*scal|scal.*3d|soft.*3d' "$R" || fail "must show the 3D is scaled/softer"
grep -qiE 'both.*build|x86.*android|android.*x86|renderer-side' "$R" || fail "must confirm renderer-side on BOTH builds (not Android-only)"
grep -qiE 'depth|sprite|letterbox|lbox|effect.*(ok|intact|correct)|no.*broken' "$R" || fail "must confirm no broken resolution-dependent effects"
grep -qiE 'flicker|0/|no black' "$R" || fail "must confirm 0 flicker"
ok "report: UI-native + 3D-scaled, both builds, no broken effects, 0 flicker"

# real renderer change (game/graphics or android/), engine goal_src untouched
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- game/graphics/ android/ 2>/dev/null; git status --porcelain -- game/graphics/ android/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'graphics/|android/' || fail "no renderer change in game/graphics or android/"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && fail "engine goal_src changed ($ENG) — render split must be renderer-side"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "renderer-side change; engine goal_src untouched; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken (link finish: logo)"

echo "[Gsplit PASS] render-split markers present; x86 ok. (close-gate: deploy_verify + owner play-test next)"
