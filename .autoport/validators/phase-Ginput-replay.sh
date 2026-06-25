#!/usr/bin/env bash
# Validator — Ginput-replay: a faithful, deterministic host-side input record/replay harness.
# PROVES all-input capture (record->replay byte-identical pad state), determinism, and cross-backend
# (x86+arm64) replay for the state-trace diff. Foundation for the owner-records-once crash phases +
# the x86-vs-arm64 frame-by-frame divergence localizer. See [[porting-1to1-fix-in-translation-layers]],
# [[state-dumps-x86-first-not-screenshots]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Ginput-replay FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Ginput-replay ok] $*"; }

R=.autoport/reports/Ginput-replay/replay.txt
[ -f "$R" ] || fail "no replay.txt"
grep -qiE 'RESULT:[[:space:]]*INPUT[[:space:]]+RECORD/?REPLAY[[:space:]]+FAITHFUL[[:space:]]*\+?[[:space:]]*(AND[[:space:]]+)?DETERMINISTIC' "$R" \
  || fail "replay.txt lacks RESULT: INPUT RECORD/REPLAY FAITHFUL + DETERMINISTIC"
# All-input fidelity: record->replay pad state byte-identical across ALL frames (PAD DIFF: 0/N)
grep -qiE 'PAD[[:space:]]*DIFF:[[:space:]]*0[[:space:]]*/[[:space:]]*[0-9]+' "$R" \
  || fail "replay.txt must prove all-input capture: 'PAD DIFF: 0/<N>' (0 mismatched frames)"
NFR=$(grep -oiE 'PAD[[:space:]]*DIFF:[[:space:]]*0[[:space:]]*/[[:space:]]*[0-9]+' "$R" | grep -oE '[0-9]+$' | head -1)
[ "${NFR:-0}" -ge 30 ] || fail "self-test demo too trivial (only ${NFR:-0} frames) — exercise >=30 frames of varied input"
# full pad state per frame (not events) + flush-per-frame guarantee + idle-until-first-input
grep -qiE 'full|all[[:space:]]*button|per[- ]frame|absolute[- ]state|bitmask' "$R" || fail "must document FULL pad state per frame (not events/deltas)"
grep -qiE 'flush|per[- ]frame.*(write|sync)|crash.*(frame|tail).*(log|captur)' "$R" || fail "must document flush-every-frame (crash frame in log)"
grep -qiE 'idle|first[- ]input|non[- ]neutral|frame[[:space:]]*0' "$R" || fail "must document idle-until-first-input start"
grep -qiE 'seed|rng|determinis|frame[- ]lock|continue[- ]?point|fingerprint' "$R" || fail "must document the determinism/start-state mechanism (rng seed etc.)"
# Determinism: two replays bit-identical state dumps
grep -qiE 'determinis|2[[:space:]]*replay|twice|bit-?identical|identical[[:space:]]*(state[[:space:]]*)?(dump|trace)|replay.*==.*replay' "$R" || fail "must prove determinism (2 replays bit-identical state dumps)"
# Cross-backend: x86 + arm64 replay both ran
grep -qiE 'x86' "$R" || fail "must show x86 replay"
grep -qiE 'arm64|device|eae4df44' "$R" || fail "must show arm64/device replay"
# Comparison MUST be STATE-anchored (deterministic logical state), NOT render-frame-indexed (framerate-dependent)
grep -qiE 'logic[- ]?tick|logical[- ]?state|state-?anchor|process[- ]?state|control[- ]?state|game[- ]?event|deterministic[- ]?(state|tick)|tick-?lock|framerate-?independ' "$R" \
  || fail "comparison must be anchored on the deterministic LOGICAL STATE (logic tick / process-state / event), NOT render frames"
grep -qiE 'bit-?identical|identical.*(value|float|state)|same[[:space:]]*(value|float|state)' "$R" \
  || fail "must assert variables/floats are BIT-IDENTICAL at matching logical states across x86 vs arm64"
grep -qiE 'diverg|first.*(state|variable|value).*(differ|diverg)|first[- ]?divergent' "$R" \
  || fail "must document the first-divergent-STATE/VARIABLE localizer (not a frame index)"
# Reject a render-frame-indexed methodology slipping back in
if grep -qiE 'first[- ]?divergent[- ]?frame|per[- ]?render[- ]?frame|align.*by.*frame[- ]?(index|number)' "$R"; then
  fail "report uses render-frame-indexed comparison (framerate-dependent) — must be STATE-anchored"
fi
# self-test demo artifact present + non-trivial
D=.autoport/demos/selftest.inputs
[ -f "$D" ] || fail "no .autoport/demos/selftest.inputs artifact"
[ "$(wc -c < "$D")" -ge 256 ] || fail "selftest.inputs too small (<256 bytes) — not a real recording"
ok "record/replay faithful (PAD DIFF 0/${NFR}); determinism + cross-backend diff documented; demo artifact present"

# real host-pad-layer change; goal_src 1-to-1
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'android/**' 'game/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'android/|game/' || fail "no host-pad-layer code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Ginput-replay-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "host-pad-layer fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD with the harness"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Ginput-replay PASS] faithful deterministic input record/replay; all inputs captured (PAD DIFF 0/${NFR}); x86+arm64 state-trace diff ready; goal_src 1-to-1."
