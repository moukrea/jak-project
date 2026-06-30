#!/usr/bin/env bash
# Validator — Gres-picker: "Game Resolution" offers NATIVE + a per-aspect-ratio standard ladder.
# Objective markers + x86 smoke; device-consistency + owner play-test enforced by the close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gres FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gres ok] $*"; }

R=.autoport/reports/Gres-picker/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*RESOLUTION[[:space:]]+PICKER[[:space:]]+NATIVE[[:space:]]*\+?[[:space:]]*(AND[[:space:]]+)?LADDER' "$R" \
  || fail "report lacks RESULT: RESOLUTION PICKER NATIVE + LADDER"
grep -qiE 'native' "$R" || fail "must offer a NATIVE entry"
grep -qiE 'ladder|640.?x.?480|1280.?x.?720|1920.?x.?1080|resolution.*list' "$R" || fail "must show the standard ladder"
grep -qiE 'aspect.*(filter|re-?filter|per-aspect)|filter.*aspect' "$R" || fail "must filter the ladder per aspect ratio"
grep -qiE 'persist' "$R" || fail "must confirm the setting persists"
grep -qiE 'render.?scale|game_res|base.*scale|order' "$R" || fail "must document the RENDER SCALE interaction (base*scale order)"
grep -qiE 'sharp|crisp|softer|low.*native|native.*low' "$R" || fail "must show a low-vs-native sharpness comparison"
ok "report: NATIVE + per-aspect ladder, persistence, render-scale order, sharpness comparison"

# real change in pc/ menu + display_manager native path
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/jak1/pc/ game/system/hid/ game/kernel/ 2>/dev/null; git status --porcelain -- goal_src/jak1/pc/ game/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'pc/|hid/|kernel/' || fail "no resolution-picker code change in pc/ or display_manager"
# engine goal_src (non-pc) must stay untouched
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && fail "engine goal_src changed ($ENG) — keep menu edits in pc/ only (gold oracle)"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "pc/ + display_manager change; engine goal_src untouched; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken (link finish: logo)"

echo "[Gres PASS] resolution picker (NATIVE + ladder) markers present; x86 ok. (close-gate: deploy_verify + owner play-test next)"
