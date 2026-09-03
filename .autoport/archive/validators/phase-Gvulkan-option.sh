#!/usr/bin/env bash
# Validator — Gvulkan-option: Vulkan renderer selectable via a Graphics Options entry, renders
# correctly on the delivered build(s), GL/GLES default unchanged. Honest partial delivery allowed.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gvk FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gvk ok] $*"; }

R=.autoport/reports/Gvulkan-option/report.txt
[ -f "$R" ] || fail "no report.txt"
if grep -qiE 'RESULT:[[:space:]]*VULKAN[[:space:]]+RENDERER[[:space:]]+OPTION[[:space:]]+BLOCKED' "$R"; then
  grep -qiE 'blocker|surface|vksurface|missing|unavailable|deferred' "$R" || fail "BLOCKED must name the exact blocker"
  echo "[Gvk PASS] honest blocked outcome"; exit 0
fi
grep -qiE 'RESULT:[[:space:]]*VULKAN[[:space:]]+RENDERER[[:space:]]+OPTION' "$R" || fail "report lacks RESULT: VULKAN RENDERER OPTION (or BLOCKED)"
grep -qiE 'vulkan' "$R" || fail "must be about Vulkan"
grep -qiE 'menu|graphics option|renderer.*option|graphics api' "$R" || fail "must add a Graphics Options renderer entry"
grep -qiE 'persist' "$R" || fail "must persist the setting"
grep -qiE 'gl/?gles|opengl|default.*(gl|gles|unchanged)|gles.*default' "$R" || fail "must keep GL/GLES the unchanged default"
grep -qiE 'oracle|side-?by-?side|match|compar.*gl|correct' "$R" || fail "must show Vulkan renders correctly (oracle-diff vs GL/GLES)"
grep -qiE 'fps|cost|perf' "$R" || fail "must note the fps delta"
grep -qiE 'x86 vulkan|desktop vulkan|android vulkan|which build|deferred|both build' "$R" || fail "must state which build(s) got Vulkan + what's deferred"
grep -qiE 'screencap|screenshot' "$R" || fail "must include screencaps"
ok "report: vulkan option + menu + persistence + correctness + default-unchanged"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
FIRST_PHASE=$(git log --format=%H --grep='\[autoport/Gvulkan-option\]' | tail -1)
if [ -n "$FIRST_PHASE" ]; then
  PRE=$(git log --format=%H --grep='\[autoport/supervisor\]' "${FIRST_PHASE}^" 2>/dev/null | head -1)
  [ -n "$PRE" ] && SUP_ANCHOR=$PRE
fi
ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/graphics/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ game/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|graphics/|pc/' || fail "no renderer-backend/menu change"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && { grep -qiE 'revert|pristine|documented|prior.?phase' "$R" || fail "engine goal_src changed ($ENG) undocumented"; }
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "renderer/pc change; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gvk PASS] vulkan-option markers present; x86 ok. (close-gate next)"
