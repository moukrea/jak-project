#!/usr/bin/env bash
# Validator — Goptions-reorder: exact menu order + PS2→Advanced rename + hide Min-Target-FPS when
# Dynamic off. Menu/UX only (pc/). Objective markers + x86 smoke; device+owner via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gord FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gord ok] $*"; }

R=.autoport/reports/Goptions-reorder/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*GRAPHICS[[:space:]]+OPTIONS[[:space:]]+REORDERED' "$R" \
  || fail "report lacks RESULT: GRAPHICS OPTIONS REORDERED"
grep -qiE 'aspect ratio' "$R" || fail "must list Aspect Ratio"
grep -qiE 'game resolution' "$R" || fail "must list Game Resolution"
grep -qiE 'dynamic render scale' "$R" || fail "must list Dynamic Render Scale"
grep -qiE 'render scale|min render scale' "$R" || fail "must list Render Scale / Min Render Scale"
grep -qiE 'min target fps|minimum target' "$R" || fail "must list Min Target FPS"
grep -qiE 'fps counter' "$R" || fail "must list FPS Counter"
grep -qiE 'v-?sync' "$R" || fail "must list V-Sync"
grep -qiE 'msaa' "$R" || fail "must list MSAA"
grep -qiE 'advanced settings' "$R" || fail "must rename PS2 Options -> Advanced settings"
grep -qiE 'order|reorder|sequence|1\..*aspect|top.*aspect' "$R" || fail "must confirm the exact order applied"
grep -qiE 'hidden|hide.*min target|dynamic.*off.*hidden|off.*hide' "$R" || fail "must hide Min Target FPS when Dynamic Render Scale is OFF"
grep -qiE 'ps2 options.*(gone|removed|renamed|no longer)|no.*ps2 options' "$R" || fail "must confirm 'PS2 Options' no longer appears (renamed)"
grep -qiE 'android.*(hide|intact|display-mode)|display-mode.*(hidden|intact)' "$R" || fail "must confirm the Android hides (Display-mode/Display/Frame-rate) stay intact"
ok "report: exact order + Advanced rename + Min-Target-FPS hidden-when-off + Android hides intact"
# owner defaults + persistence of all graphics settings
grep -qiE 'default.*(dynamic|on)|dynamic.*on.*default|on by default' "$R" || fail "must set Dynamic Render Scale = ON by default"
grep -qiE 'default.*40|40.*default|minimum.*40' "$R" || fail "must set Minimum Render Scale = 40% default"
grep -qiE 'default.*60|60.*default|target.*60' "$R" || fail "must set Minimum Target FPS = 60 default"
grep -qiE 'persist.*(restart|relaunch|reboot|across)|restart.*persist|retain.*restart|commit-to-file' "$R" || fail "must VERIFY all graphics settings persist across an app restart (owner explicitly unsure re: the dynamic-scale trio)"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'pc/' || fail "no pc/ menu change"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && fail "engine goal_src changed ($ENG) — menu reorder must be pc/ only"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "pc/ menu change; engine goal_src untouched; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken (link finish: logo)"

echo "[Gord PASS] menu reorder + rename + hide-when-off markers present; x86 ok. (close-gate: deploy_verify + boot + owner next)"
