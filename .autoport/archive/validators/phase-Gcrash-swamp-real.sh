#!/usr/bin/env bash
# Validator — Gcrash-swamp-real: the REAL Rock Village->Swamp route crash reproduced by WALKING it,
# forensically named at swamp-load, fixed 1-to-1, crash-free on the SAME real route (not synthetic
# replay). Objective markers + x86 smoke; device+owner via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gsr FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gsr ok] $*"; }

R=.autoport/reports/Gcrash-swamp-real/report.txt
[ -f "$R" ] || fail "no report.txt"
if grep -qiE 'RESULT:[[:space:]]*SWAMP[[:space:]]+CRASH[[:space:]]+ROOT[[:space:]]+NAMED' "$R"; then
  grep -qiE 'pc=|faulting|signal|sig ?1?[146]' "$R" || fail "ROOT NAMED must include the forensic fn/PC/signal"
  grep -qiE 'ruled out|not.*(cause|the)|classif' "$R" || fail "ROOT NAMED must state what was ruled out"
  echo "[Gsr PASS] honest root-named outcome"; exit 0
fi
grep -qiE 'RESULT:[[:space:]]*SWAMP[[:space:]]+CRASH[[:space:]]+FIXED[[:space:]]*\(REAL[[:space:]]+INPUT\)' "$R" \
  || fail "report lacks RESULT: SWAMP CRASH FIXED (REAL INPUT) (or ROOT NAMED)"
grep -qiE 'swamp|boggy|pontoon|passerelle' "$R" || fail "must be about the Rock Village->Swamp route"
# REAL-route repro, NOT synthetic-only:
grep -qiE 'real.?input|pad|stick|cpad|hid|owner.*(walk|save|captur)|input.?inject' "$R" || fail "must reproduce with REAL controller INPUT or the owner capture (target.drive is BANNED)"
grep -qiE 'target.?drive|position.?drive' "$R" && grep -qiE 'ban|not.*proof|forbidden|differ' "$R" || grep -qvE 'target.?drive.*(after|proof|verif)' "$R" || fail "target.drive must NOT be the AFTER proof"
grep -qiE 'sig(nal)? ?(11|6|4)|SIGSEGV|SIGILL|SIGABRT' "$R" || fail "must capture the crash signal"
grep -qiE 'faulting|pc=|fp-?walk|lr |byte.?match' "$R" || fail "must name the faulting function/PC (forensics)"
grep -qiE 'swamp.?load|dgo|link|klink|stream|load.*boundary' "$R" || fail "must tie the crash to the swamp load path"
grep -qiE 'classif|codegen|mips2c|stack|dgo|stream|sparticle|merc|stomp' "$R" || fail "must classify the crash"
grep -qiE 'rockvillage|58ee45b15|previous.*(fix|phase|repair)|repair-and-resume|missed|false' "$R" || fail "must explain why Gcrash-rockvillage's fix missed the real crash"
grep -qiE 'after.*(crash-?free|no crash|0 sig)|crash-?free.*after|sustained|stood.*swamp|loaded.*swamp' "$R" || fail "must show a crash-free AFTER run on the REAL route past the boundary"
grep -qiE 'collision|jungle|blue.?eco|orb|eco|speed|camera' "$R" || fail "must confirm prior fixes intact"
grep -qiE 'x86.*(link finish|ok|unbroken)|link finish: logo' "$R" || fail "must confirm x86 unaffected"
ok "report: REAL-route repro + forensics + classification + fix + real AFTER + fixes intact"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
FIRST_PHASE=$(git log --format=%H --grep='\[autoport/Gcrash-swamp-real\]' | tail -1)
if [ -n "$FIRST_PHASE" ]; then
  PRE=$(git log --format=%H --grep='\[autoport/supervisor\]' "${FIRST_PHASE}^" 2>/dev/null | head -1)
  [ -n "$PRE" ] && SUP_ANCHOR=$PRE
fi
ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/ goalc/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ game/ goalc/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -v 'IGenX86_64' | grep -qE 'android/|game/|goalc/|pc/' || fail "no translation-layer fix"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
if [ -n "$ENG" ]; then grep -qiE 'revert|pristine|documented' "$R" || fail "engine goal_src changed ($ENG) undocumented"; fi
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "translation-layer fix; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gsr PASS] swamp-load crash fix markers present; x86 ok. (close-gate next)"
