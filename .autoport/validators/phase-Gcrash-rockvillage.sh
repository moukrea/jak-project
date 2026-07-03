#!/usr/bin/env bash
# Validator — Gcrash-rockvillage: village2 past-pontoons crash reproduced, forensically named,
# fixed 1-to-1, crash-free past the old crash point. Objective markers + x86 smoke; device+owner
# via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Grv FAIL] $*" >&2; exit 1; }
ok(){ echo "[Grv ok] $*"; }

R=.autoport/reports/Gcrash-rockvillage/report.txt
[ -f "$R" ] || fail "no report.txt"
if grep -qiE 'RESULT:[[:space:]]*ROCK[[:space:]]+VILLAGE[[:space:]]+CRASH[[:space:]]+ROOT[[:space:]]+NAMED' "$R"; then
  grep -qiE 'pc=|faulting|signal|sig ?1?[146]' "$R" || fail "ROOT NAMED must include the forensic fn/PC/signal"
  grep -qiE 'ruled out|not.*(cause|the)|classif' "$R" || fail "ROOT NAMED must state what was ruled out"
  echo "[Grv PASS] honest root-named outcome"; exit 0
fi
grep -qiE 'RESULT:[[:space:]]*ROCK[[:space:]]+VILLAGE[[:space:]]+PONTOON[[:space:]]+CRASH[[:space:]]+FIXED' "$R" \
  || fail "report lacks RESULT: ROCK VILLAGE PONTOON CRASH FIXED (or ROOT NAMED)"
grep -qiE 'village2|rock ?village' "$R" || fail "must be about Rock Village (village2)"
grep -qiE 'pontoon|passerelle|90.?orb|warrior|soldat|buzzer|crate|fly' "$R" || fail "must cover the owner route (pontoons/90 orbs/buzzer crate)"
grep -qiE 'reproduc|trigger|warp|continue.?point|save.*flag|progress.*flag' "$R" || fail "must reproduce on device (how the 90-orb gate was crossed)"
grep -qiE 'sig(nal)? ?(11|6|4)|SIGSEGV|SIGILL|SIGABRT' "$R" || fail "must capture the crash signal"
grep -qiE 'faulting|pc=|fp-?walk|lr |byte.?match' "$R" || fail "must name the faulting function/PC (forensics)"
grep -qiE 'classif|codegen|mips2c|stack|dgo|stream|sparticle|renderer|stomp' "$R" || fail "must classify the crash"
grep -qiE 'after.*(crash-?free|no crash|0 sig)|crash-?free.*after|sustained' "$R" || fail "must show a crash-free AFTER run past the old crash point"
grep -qiE 'collision|jungle|blue.?eco|speed|camera|orb' "$R" || fail "must confirm prior fixes intact"
grep -qiE 'x86.*(link finish|ok|unbroken)|link finish: logo' "$R" || fail "must confirm x86 unaffected"
ok "report: repro + forensics + classification + fix + crash-free after + fixes intact"

# Phase-aware anchor (mid-phase supervisor journal commits must not advance it).
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
FIRST_PHASE=$(git log --format=%H --grep='\[autoport/Gcrash-rockvillage\]' | tail -1)
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

echo "[Grv PASS] rock-village crash fix markers present; x86 ok. (close-gate next)"
