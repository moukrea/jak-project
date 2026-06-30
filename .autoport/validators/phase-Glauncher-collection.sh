#!/usr/bin/env bash
# Validator — Glauncher-collection: multi-game launcher (asset-gated), or an honest documented STEP-1
# minimal increment. Objective markers + jak1-still-builds; device + owner play-test via the close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Glauncher FAIL] $*" >&2; exit 1; }
ok(){ echo "[Glauncher ok] $*"; }

R=.autoport/reports/Glauncher-collection/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*(MULTI-?GAME[[:space:]]+LAUNCHER|LAUNCHER[[:space:]]+STEP-?1)' "$R" \
  || fail "report lacks RESULT: MULTI-GAME LAUNCHER (or LAUNCHER STEP-1)"
grep -qiE 'launcher|game.*list|pick.*game|select.*game' "$R" || fail "must describe the launcher UI"
grep -qiE 'gamepad' "$R" && grep -qiE 'touch' "$R" || fail "must support gamepad AND touch selection"
grep -qiE 'asset.*(gat|driven|present|bundle)|gat.*asset|built-in.*asset' "$R" || fail "must show asset-driven game gating"
grep -qiE 'jak1.*(launch|play|boot|render)|launch.*jak1' "$R" || fail "must confirm jak1 launches + plays through the launcher"
# STEP-1 increments must honestly say what remains
if grep -qiE 'STEP-?1' "$R"; then
  grep -qiE 'remain|follow-?up|next|todo|future|jak ?2' "$R" || fail "STEP-1 must state what remains for full multi-game"
fi
ok "report: launcher UI, gamepad+touch, asset-gating, jak1 plays"

# real change (android packaging / runtime / launcher code or pc/)
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ game/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|game/|pc/' || fail "no launcher/packaging code change"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "launcher/packaging change present; golden pristine"

# jak1 must still build x86 (the existing game stays playable)
SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 jak1 smoke regressed — launcher broke the game path"; }; rm -f "$SMOKE"
ok "jak1 x86 still boots (link finish: logo)"

echo "[Glauncher PASS] launcher markers present; jak1 path intact. (close-gate: deploy_verify + owner play-test next)"
