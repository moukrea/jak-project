#!/usr/bin/env bash
# Validator — Ginput-replay-realinput: the owner's REAL input path (touch overlay / gamepad merge) must be
# CAPTURED under the warp anchor, verified with REAL Android `adb input` events (NOT the headless
# cpad_inject, which already worked and false-greened Ginput-replay-liverecord). Host fix; goal_src 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Greal FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Greal ok] $*"; }

R=.autoport/reports/Ginput-replay-realinput/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*REAL[[:space:]]+INPUT[[:space:]]+CAPTURED[[:space:]]+UNDER[[:space:]]+ANCHOR' "$R" \
  || fail "report lacks RESULT: REAL INPUT CAPTURED UNDER ANCHOR"
# BEFORE: real touch all-neutral reproduced + drop point named
grep -qiE 'all-?neutral|0[[:space:]]*non-?neutral|0%|0/[0-9]+' "$R" || fail "must reproduce the BEFORE (real touch all-neutral under warp)"
grep -qiE 'warp|drive|merge|get_cpad_state|overwrit|tap|drop' "$R" || fail "must name where the real merge is dropped"
# VERIFICATION MUST use real adb input (NOT cpad_inject)
grep -qiE 'adb (shell )?input|input swipe|input tap' "$R" || fail "verification MUST use real 'adb input' touch events"
if ! grep -qiE 'not.*cpad_?inject|NOT.*injector|real.*(touch|input).*not.*inject|adb input.*not' "$R"; then
  grep -qiE 'cpad_?inject' "$R" && fail "report still leans on cpad_inject — verification must be REAL adb-input touch, explicitly not the injector"
fi
# AFTER: real-input record non-neutral + N/M + replay==record
grep -qiE 'REAL[[:space:]]+INPUT[[:space:]]+CAPTURED:[[:space:]]*[0-9]+[[:space:]]*/[[:space:]]*[0-9]+' "$R" || fail "must show 'REAL INPUT CAPTURED: N/M' from adb-input"
N=$(grep -oiE 'REAL[[:space:]]+INPUT[[:space:]]+CAPTURED:[[:space:]]*[0-9]+' "$R" | grep -oE '[0-9]+' | head -1)
M=$(grep -oiE 'REAL[[:space:]]+INPUT[[:space:]]+CAPTURED:[[:space:]]*[0-9]+[[:space:]]*/[[:space:]]*[0-9]+' "$R" | grep -oE '[0-9]+$' | head -1)
[ "${M:-0}" -ge 60 ] || fail "real-input clip too short (M=${M:-0}, need >=60 frames)"
[ "${N:-0}" -ge $(( ${M:-0} / 3 )) ] || fail "too few non-neutral frames from real input (N=${N:-0}/${M:-0})"
grep -qiE 'replay[[:space:]]*==[[:space:]]*record|record[[:space:]]*==[[:space:]]*replay|bit-?identical|determinism.*(intact|preserved|0/)' "$R" || fail "must show replay==record (determinism preserved)"
ok "real adb-input touch captured under warp (REAL ${N}/${M}); determinism preserved; not the injector"

CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goalc/' || fail "no host/runtime code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Ginput-replay-realinput-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "host fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Greal PASS] owner's REAL input (adb-input touch) captured under the anchor; determinism preserved. Owner re-record will work."
