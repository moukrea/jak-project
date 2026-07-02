#!/usr/bin/env bash
# Validator — Gtouch-fix: ALL menu option types tappable (toggles, sliders, save rows, carousels),
# verified per-type with real adb input tap. Objective markers + x86 smoke; device+owner via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gtf FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gtf ok] $*"; }

R=.autoport/reports/Gtouch-fix/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*ALL[[:space:]]+MENU[[:space:]]+ELEMENTS[[:space:]]+TAPPABLE' "$R" \
  || fail "report lacks RESULT: ALL MENU ELEMENTS TAPPABLE"
grep -qiE 'toggle|on/?off' "$R" || fail "must fix ON/OFF toggles"
grep -qiE 'slider|percent|render scale.*(tap|step)|step.*(up|down)' "$R" || fail "must fix sliders/percent carousels"
grep -qiE 'save.?file|continue without|activat' "$R" || fail "must fix save-file row tap-activation"
grep -qiE 'carousel|aspect|resolution' "$R" || fail "must cover carousels (aspect/resolution)"
grep -qiE 'adb (shell )?input tap|input tap' "$R" || fail "verification MUST use real adb input tap"
grep -qiE 'on.*off.*on|off.*on.*off|toggled.*(tap|twice)' "$R" || fail "must show a toggle flipped by tap alone (round trip)"
grep -qiE 'value.*(chang|step)|stepped|40.*50|down.*up' "$R" || fail "must show a slider value changed by tap alone"
grep -qiE 'no d-?pad|without.*d-?pad|touch.*only' "$R" || fail "must confirm the whole sequence used NO D-pad"
grep -qiE 'd-?pad.*(still|work|intact)|gamepad.*(still|work)' "$R" || fail "D-pad/gamepad must still work"
ok "report: all types tappable, per-type adb-tap proof, no D-pad, D-pad intact"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ goal_src/jak1/pc/ game/ 2>/dev/null; git status --porcelain -- android/ goal_src/jak1/pc/ game/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|pc/|game/' || fail "no touch-fix code change"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && fail "engine goal_src changed ($ENG) — keep it in pc/ + android glue"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "code change present; engine goal_src untouched; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"

echo "[Gtf PASS] all-elements-tappable markers present; x86 ok. (close-gate next)"
