#!/usr/bin/env bash
# Validator — Gperf-particles2: perf re-earned CORRECTLY under real moving gameplay. Image must be
# clean (no geometry pop, no TOD flicker) with natural TOD — the pose-held/TOD-pinned proof that
# hid the v5 regression is FORBIDDEN as correctness evidence. Objective markers + x86 smoke.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gp2 FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gp2 ok] $*"; }

R=.autoport/reports/Gperf-particles2/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*PERF[[:space:]]+CLEAN' "$R" || fail "report lacks RESULT: PERF CLEAN <before>-><after> FPS"
# Correctness-first evidence:
grep -qiE 'moving|camera pan|traversal|in.?play|gameplay.*(video|record)|screenrecord' "$R" || fail "must validate under REAL MOVING gameplay (not a static pose)"
grep -qiE 'natural.*tod|tod.*advanc|day.?(to|->|→).?night|clock (runs|advanc)' "$R" || fail "TOD must ADVANCE naturally (pinned-TOD proof is forbidden — it hid the v5 bug)"
grep -qiE 'geometry pop|pop(-| )?in|disappear|present.*absent|no pop' "$R" || fail "must inspect for GEOMETRY POP (v5 symptom)"
grep -qiE 'flicker|palette|tod.*(cycle|flicker)|day/night/sunrise|no.*tod.*flicker' "$R" || fail "must inspect for TOD/palette FLICKER (v5 symptom)"
grep -qiE 'known.?bad|control.*(bad|re-?enabl)|detect.*(pop|flicker|bug)|check.*works' "$R" || fail "must record a KNOWN-BAD control proving the inspection actually detects the pop/flicker"
grep -qiE 'per.?feature|one at a time|kept|dropped|left off' "$R" || fail "must re-earn each optimization individually (kept/dropped + why)"
grep -qiE 'byte-?identical|matches v4|== ?v4|parity.*v4|v4.?render' "$R" || fail "kept features must render identical to the v4 renderer path"
grep -qiE 'eco.*(burst|intact)|orb.*(hud|intact)' "$R" || fail "must re-verify eco bursts + orb HUD"
grep -qiE 'fps' "$R" || fail "must report the fps of the kept set"
ok "report: real-moving-gameplay correctness + known-bad control + per-feature verdict"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
FIRST_PHASE=$(git log --format=%H --grep='\[autoport/Gperf-particles2\]' | tail -1)
if [ -n "$FIRST_PHASE" ]; then
  PRE=$(git log --format=%H --grep='\[autoport/supervisor\]' "${FIRST_PHASE}^" 2>/dev/null | head -1)
  [ -n "$PRE" ] && SUP_ANCHOR=$PRE
fi
ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/ 2>/dev/null; git status --porcelain -- android/ game/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|game/' || fail "no renderer/runtime change"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && { grep -qiE 'revert|pristine|documented|prior.?phase' "$R" || fail "engine goal_src changed ($ENG) undocumented"; }
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "renderer/runtime; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gp2 PASS] correctness-first perf markers present; x86 ok. (close-gate next)"
