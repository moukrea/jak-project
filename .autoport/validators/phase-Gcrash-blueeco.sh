#!/usr/bin/env bash
# Validator — Gcrash-blueeco: jungle blue-eco vent crash reproduced, forensically named, fixed 1-to-1,
# crash-free past the trigger. Objective markers + x86 smoke; device+owner via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gbe FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gbe ok] $*"; }

R=.autoport/reports/Gcrash-blueeco/report.txt
[ -f "$R" ] || fail "no report.txt"
if grep -qiE 'RESULT:[[:space:]]*BLUE[[:space:]]+ECO[[:space:]]+CRASH[[:space:]]+ROOT[[:space:]]+NAMED' "$R"; then
  grep -qiE 'pc=|faulting|signal|sig ?1?[146]' "$R" || fail "ROOT NAMED must include the forensic fn/PC/signal"
  grep -qiE 'ruled out|not.*(cause|the)|classif' "$R" || fail "ROOT NAMED must state what was ruled out"
  echo "[Gbe PASS] honest root-named outcome"; exit 0
fi
grep -qiE 'RESULT:[[:space:]]*BLUE[[:space:]]+ECO[[:space:]]+VENT[[:space:]]+CRASH[[:space:]]+FIXED' "$R" \
  || fail "report lacks RESULT: BLUE ECO VENT CRASH FIXED (or ROOT NAMED)"
grep -qiE 'vent|fountain|fontaine|blue.?eco' "$R" || fail "must be about the blue-eco vent"
grep -qiE 'reproduc|trigger|warp.*jungle|jungle-start' "$R" || fail "must reproduce on device (warp+trigger)"
grep -qiE 'sig(nal)? ?(11|6|4)|SIGSEGV|SIGILL|SIGABRT' "$R" || fail "must capture the crash signal"
grep -qiE 'faulting|pc=|fp-?walk|lr |byte.?match' "$R" || fail "must name the faulting function/PC (forensics)"
grep -qiE 'classif|codegen|mips2c|stack|sparticle|renderer' "$R" || fail "must classify the crash"
grep -qiE 'after.*(crash-?free|no crash|0 sig)|crash-?free.*after|sustained' "$R" || fail "must show a crash-free AFTER run past the trigger"
grep -qiE 'collision|jungle|speed|camera' "$R" || fail "must confirm prior fixes intact"
ok "report: repro + forensics + classification + fix + crash-free after + fixes intact"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/ goalc/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ game/ goalc/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -v 'IGenX86_64' | grep -qE 'android/|game/|goalc/|pc/' || fail "no translation-layer fix"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
if [ -n "$ENG" ]; then grep -qiE 'revert|pristine|documented' "$R" || fail "engine goal_src changed ($ENG) undocumented"; fi
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "translation-layer fix; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"

echo "[Gbe PASS] blue-eco crash fix markers present; x86 ok. (close-gate next)"
