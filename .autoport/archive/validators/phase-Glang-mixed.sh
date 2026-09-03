#!/usr/bin/env bash
# Validator — Glang-mixed: interaction texts follow the TEXT language (audio EN + text FR case).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Glm FAIL] $*" >&2; exit 1; }
ok(){ echo "[Glm ok] $*"; }

R=.autoport/reports/Glang-mixed/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*TEXT[[:space:]]+FOLLOWS[[:space:]]+TEXT[[:space:]]+LANGUAGE' "$R" \
  || fail "report lacks RESULT: TEXT FOLLOWS TEXT LANGUAGE"
grep -qiE 'audio.*(en|english|anglais)' "$R" || fail "must cover the audio=EN case"
grep -qiE 'fran|french|fr\b' "$R" || fail "must cover text=FR"
grep -qiE 'interact|prompt|examine|talk|parler|objet|npc|personnage' "$R" || fail "must list the affected interaction strings"
grep -qiE 'oracle|golden|x86.*(side|vs|compar|verdict)' "$R" || fail "must give the x86 oracle verdict (divergence vs upstream)"
grep -qiE 'text.?bank|language.?id|lang.*(lost|key|fallback)|fallback' "$R" || fail "must name where the language id was lost"
grep -qiE 'both.?ways|back to en|en.*fr.*en|switch.*back' "$R" || fail "must check both-ways language switching"
grep -qiE 'screencap|screenshot|before.*after' "$R" || fail "must include before/after screencaps"
ok "report: affected list + oracle verdict + root + both-ways check"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
FIRST_PHASE=$(git log --format=%H --grep='\[autoport/Glang-mixed\]' | tail -1)
if [ -n "$FIRST_PHASE" ]; then
  PRE=$(git log --format=%H --grep='\[autoport/supervisor\]' "${FIRST_PHASE}^" 2>/dev/null | head -1)
  [ -n "$PRE" ] && SUP_ANCHOR=$PRE
fi
ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ game/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|game/|pc/' || fail "no translation-layer/pc fix"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
if [ -n "$ENG" ]; then grep -qiE 'revert|pristine|documented' "$R" || fail "engine goal_src changed ($ENG) undocumented"; fi
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "fix in pc/translation layer; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Glm PASS] language-follows-text markers present; x86 ok. (close-gate next)"
