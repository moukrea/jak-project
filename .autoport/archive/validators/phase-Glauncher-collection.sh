#!/usr/bin/env bash
# Validator — Glauncher-collection (REVISED): 1 game = direct boot + per-game name/icon; >1 game =
# collection mode ("Jak and Daxter: The Recharged Jak-pot") + selection menu. jak1-only build must
# boot straight into "Jak & Daxter". Objective markers + jak1-still-builds; device + owner via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Glauncher FAIL] $*" >&2; exit 1; }
ok(){ echo "[Glauncher ok] $*"; }

R=.autoport/reports/Glauncher-collection/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*(PER-?GAME[[:space:]]+OR[[:space:]]+COLLECTION[[:space:]]+BY[[:space:]]+BUILD[[:space:]]+ASSETS|LAUNCHER[[:space:]]+STEP-?1)' "$R" \
  || fail "report lacks RESULT: PER-GAME OR COLLECTION BY BUILD ASSETS (or LAUNCHER STEP-1)"
# single-game = direct boot, per-game name/icon
grep -qiE 'single|one game|direct.?boot|straight.*(game|in-game)|no.*launcher' "$R" || fail "must show single-game = direct boot (no launcher)"
grep -qiE 'Jak ?& ?Daxter|Jak and Daxter' "$R" || fail "must set jak1-only label 'Jak & Daxter'"
grep -qiE 'icon' "$R" || fail "must set the per-game launcher icon"
# >1 game = collection mode + selection menu + name
grep -qiE 'collection|more than one|>1|multi' "$R" || fail "must describe collection mode for >1 game"
grep -qiE 'Recharged Jak-?pot' "$R" || fail "collection label must be 'Jak and Daxter: The Recharged Jak-pot'"
grep -qiE 'select|menu|pick|choose' "$R" || fail "collection must have a game-selection menu"
grep -qiE 'touch' "$R" && grep -qiE 'gamepad|controller' "$R" || fail "selection must work by touch AND gamepad"
# asset-driven detection
grep -qiE 'asset.*(driven|detect|present|bundle|build-?time)|detect.*game|manifest|dry-?run' "$R" || fail "must show the asset-driven 1-vs-collection detection"
# jak1 plays
grep -qiE 'jak1.*(boot|play|render|game)|boots.*jak' "$R" || fail "must confirm jak1 boots + plays (all fixes intact)"
if grep -qiE 'STEP-?1' "$R"; then
  grep -qiE 'remain|follow-?up|next|future|coexist' "$R" || fail "STEP-1 must state what remains for full multi-game coexistence"
fi
ok "report: single=direct+name/icon; collection=Recharged Jak-pot+menu(touch+gamepad); asset-detect; jak1 plays"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ game/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|game/|pc/' || fail "no launcher/packaging code change"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "launcher/packaging change present; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 jak1 smoke regressed — launcher broke the game path"; }; rm -f "$SMOKE"
ok "jak1 x86 still boots (link finish: logo)"

echo "[Glauncher PASS] per-game/collection markers present; jak1 path intact. (close-gate: deploy_verify + owner play-test next)"
