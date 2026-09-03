#!/usr/bin/env bash
# Validator — Gndskip: START at the ND logo skips TO the J&D logo (no black hole).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gns FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gns ok] $*"; }

R=.autoport/reports/Gndskip/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*ND[[:space:]]+SKIP[[:space:]]+LANDS[[:space:]]+ON[[:space:]]+JAK[[:space:]]+LOGO' "$R" \
  || fail "report lacks RESULT: ND SKIP LANDS ON JAK LOGO"
grep -qiE 'black|noir|gap' "$R" || fail "must measure the before black-gap"
grep -qiE 'oracle|golden|x86.*(skip|verdict|same|instant)' "$R" || fail "must give the x86 oracle verdict"
grep -qiE 'ndi|naughty|sequence.*clock|spool|process.*kill|skip.*path' "$R" || fail "must name the skip path + fix"
grep -qiE '(within|~|<).*(1 ?s|1s|second)|instant' "$R" || fail "must show the after timing (~1s to the J&D logo)"
grep -qiE 'no.?skip|full sequence|not press|sans.*start' "$R" || fail "must verify the no-skip path still plays fully"
grep -qiE 'title.*(intact|unregress)|attract|logo.*(placement|unregress)|halo' "$R" || fail "must confirm title/attract unregressed"
grep -qiE 'audio.*(consistent|no orphan|coup|stop)' "$R" || fail "must confirm audio consistent after skip"
ok "report: gap + oracle + skip path + timing + no-skip + title intact"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
FIRST_PHASE=$(git log --format=%H --grep='\[autoport/Gndskip\]' | tail -1)
if [ -n "$FIRST_PHASE" ]; then
  PRE=$(git log --format=%H --grep='\[autoport/supervisor\]' "${FIRST_PHASE}^" 2>/dev/null | head -1)
  [ -n "$PRE" ] && SUP_ANCHOR=$PRE
fi
ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ game/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|game/|pc/' || fail "no translation-layer/pc fix"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
if [ -n "$ENG" ]; then grep -qiE 'revert|pristine|documented|TIT\.DGO' "$R" || fail "engine goal_src changed ($ENG) undocumented"; fi
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "fix in pc/translation layer; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gns PASS] ND-skip markers present; x86 ok. (close-gate next)"
