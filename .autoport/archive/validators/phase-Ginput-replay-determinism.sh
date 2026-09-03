#!/usr/bin/env bash
# Validator — Ginput-replay-determinism: replaying a REAL-gameplay recording must reproduce it
# faithfully (record-trace == replay-trace, same backend, bit-identical, over a real clip). The scripted
# self-test passed but real gameplay diverged (owner: "moves at the wrong place from the first seconds").
# Host/runtime fix; goal_src 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gdet FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gdet ok] $*"; }

R=.autoport/reports/Ginput-replay-determinism/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*REPLAY[[:space:]]+REPRODUCES[[:space:]]+REAL[[:space:]]+GAMEPLAY[[:space:]]*\(RECORD[[:space:]]*==[[:space:]]*REPLAY\)' "$R" \
  || fail "report lacks RESULT: REPLAY REPRODUCES REAL GAMEPLAY (RECORD==REPLAY)"
# must be REAL gameplay, NOT the scripted self-test
grep -qiE 'real[- ]?gameplay|in-?game|new[- ]?game|playthrough' "$R" || fail "must use a REAL gameplay clip (not the scripted self-test)"
grep -qiE 'record-?trace|replay-?trace|record.*vs.*replay|same[- ]backend' "$R" || fail "must compare record-trace vs same-backend replay-trace"
# state keyed by game-LOGIC frame, real game-state fields
grep -qiE 'logic[- ]?frame|game[- ]?frame|per[- ]frame|frame=' "$R" || fail "trace must be keyed by the deterministic game-logic frame"
grep -qiE 'position|pos|orient|camera|velocity|jak' "$R" || fail "trace must dump real game-state (Jak pos/orientation/camera)"
# bit-identical record==replay, both a short and a longer clip
grep -qiE 'bit-?identical|identical|0[[:space:]]*diverg|0[[:space:]]*/[[:space:]]*[0-9]+|record[[:space:]]*==[[:space:]]*replay|match' "$R" || fail "must show record==replay bit-identical over the clip"
grep -qiE '3[[:space:]]*min|[0-9]+[[:space:]]*min|longer|long.*clip|[0-9]{4,}[[:space:]]*(frame|tick)' "$R" || fail "must verify a LONGER (>=3 min) real-gameplay clip too"
# the non-determinism source(s) named + the BEFORE divergence
grep -qiE 'tick[- ]?index|controller-?read|rng|rand-?vu|seed|camera|spawn|non-?determin|diverg' "$R" || fail "must name the non-determinism source(s) found"
grep -qiE 'before' "$R" || fail "must document the BEFORE (replay diverged from record)"
ok "real-gameplay record==replay bit-identical (short+long); non-determinism source(s) named+fixed"

CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goalc/' || fail "no host/runtime code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Ginput-replay-determinism-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp dump removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "host/runtime fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gdet PASS] replay faithfully reproduces real gameplay (record==replay); non-determinism captured/restored. Collision diff unblocked."
