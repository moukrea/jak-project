#!/usr/bin/env bash
# Validator — Gtouch-menus: in-game menus fully touch-browsable (tap enters submenu / selects option),
# verified with REAL adb input tap; D-pad still works. Objective markers + x86 smoke; device+owner via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gtm FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gtm ok] $*"; }

R=.autoport/reports/Gtouch-menus/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*MENUS[[:space:]]+TOUCH-?BROWSABLE' "$R" || fail "report lacks RESULT: MENUS TOUCH-BROWSABLE"
grep -qiE 'tap' "$R" || fail "must describe tap-driven navigation"
grep -qiE 'submenu|sub-?option|enter|select|carousel|row' "$R" || fail "must show tap enters submenu / selects sub-option"
grep -qiE 'hit.?test|x,?y|rect|layout|position' "$R" || fail "must describe touch hit-testing to menu rows"
grep -qiE 'adb (shell )?input tap|input tap' "$R" || fail "verification MUST use real 'adb input tap' events"
grep -qiE 'without.*d-?pad|no d-?pad|no dpad|touch.*only' "$R" || fail "must confirm navigation works WITHOUT the D-pad"
grep -qiE 'd-?pad.*(still|work|intact)|gamepad.*(still|work|intact)' "$R" || fail "must confirm D-pad/gamepad still work (touch is additive)"
ok "report: tap-nav + hit-test + adb-input-tap verified (no D-pad) + D-pad still works"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ goal_src/jak1/pc/ game/ 2>/dev/null; git status --porcelain -- android/ goal_src/jak1/pc/ game/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|pc/|game/' || fail "no touch-menu code change"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && fail "engine goal_src changed ($ENG) — keep it in pc/ + android glue"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "code change present; engine goal_src untouched; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken (link finish: logo)"

echo "[Gtm PASS] touch-browsable menu markers present; x86 ok. (close-gate: deploy_verify + boot + owner next)"
