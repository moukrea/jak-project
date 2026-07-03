#!/usr/bin/env bash
# Validator — Gtitle-tap: "PRESS START OR TAP SCREEN" + tap opens the start menu (Android only).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gtt FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gtt ok] $*"; }

R=.autoport/reports/Gtitle-tap/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*TITLE[[:space:]]+TAP[[:space:]]+OPENS[[:space:]]+START[[:space:]]+MENU' "$R" \
  || fail "report lacks RESULT: TITLE TAP OPENS START MENU"
grep -qiE 'tap screen|tap.*start|onMenuTap|touch' "$R" || fail "must show the tap->START wiring"
grep -qiE 'or tap|ou touchez' "$R" || fail "must show the new prompt wording"
grep -qiE 'fran|touchez|fr\b' "$R" || fail "prompt must be localized (FR at minimum)"
grep -qiE 'input tap.*(menu|start)|tap.*(opens|menu)' "$R" || fail "must prove a real adb tap opens the start menu"
grep -qiE 'gamepad|manette|start.*(still|works)' "$R" || fail "must confirm gamepad START still works"
grep -qiE 'in.?game.*(unchanged|unaffected|virtual)|scope' "$R" || fail "must prove in-game taps are unaffected (scoping)"
grep -qiE 'layout|placement|center|4.?3|16.?9|unregress' "$R" || fail "must check the title layout at both aspects"
grep -qiE 'x86.*(untouched|its prompt|link finish)' "$R" || fail "x86 prompt must be untouched"
ok "report: wiring + localized prompt + tap proof + scoping + layout"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
FIRST_PHASE=$(git log --format=%H --grep='\[autoport/Gtitle-tap\]' | tail -1)
if [ -n "$FIRST_PHASE" ]; then
  PRE=$(git log --format=%H --grep='\[autoport/supervisor\]' "${FIRST_PHASE}^" 2>/dev/null | head -1)
  [ -n "$PRE" ] && SUP_ANCHOR=$PRE
fi
ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ game/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|game/|pc/' || fail "no translation-layer/pc change"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
if [ -n "$ENG" ]; then grep -qiE 'revert|pristine|documented|TIT\.DGO' "$R" || fail "engine goal_src changed ($ENG) undocumented"; fi
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "change in pc/translation layer; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gtt PASS] title-tap markers present; x86 ok. (close-gate next)"
