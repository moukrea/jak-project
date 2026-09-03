#!/usr/bin/env bash
# Validator — Ginput-replay-liverecord: a v2 LIVE record (real touch/gamepad, NOT scripted-drive) must
# CAPTURE the input (the owner's live re-record recorded all-neutral). Verified by injecting a known
# input + asserting non-neutral capture that byte-matches + replay==record. Host fix; goal_src 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Glive FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Glive ok] $*"; }

R=.autoport/reports/Ginput-replay-liverecord/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*V2[[:space:]]+LIVE[[:space:]]+RECORD[[:space:]]+CAPTURES[[:space:]]+INPUT' "$R" \
  || fail "report lacks RESULT: V2 LIVE RECORD CAPTURES INPUT"
# BEFORE: live record all-neutral reproduced; cause named
grep -qiE 'all-?neutral|0[[:space:]]*non-?neutral|0/[0-9]+' "$R" || fail "must reproduce the BEFORE (live record all-neutral)"
grep -qiE 'warp|drive|overwrit|merge|tap|cause|f1\.warp' "$R" || fail "must name the cause (live input lost at the tap)"
# AFTER: live record non-neutral + byte-matches injected + N/M
grep -qiE 'INPUT[[:space:]]*CAPTURED:[[:space:]]*[0-9]+[[:space:]]*/[[:space:]]*[0-9]+' "$R" || fail "must show 'INPUT CAPTURED: N/M' after the fix"
N=$(grep -oiE 'INPUT[[:space:]]*CAPTURED:[[:space:]]*[0-9]+' "$R" | grep -oE '[0-9]+' | head -1)
M=$(grep -oiE 'INPUT[[:space:]]*CAPTURED:[[:space:]]*[0-9]+[[:space:]]*/[[:space:]]*[0-9]+' "$R" | grep -oE '[0-9]+$' | head -1)
[ "${M:-0}" -ge 30 ] || fail "verification clip too short (M=${M:-0}, need >=30 frames)"
[ "${N:-0}" -ge $(( ${M:-0} / 2 )) ] || fail "too few non-neutral frames captured (N=${N:-0}/${M:-0})"
grep -qiE 'byte-?match|matches.*inject|inject.*match|identical.*inject' "$R" || fail "captured record must byte-match the injected sequence"
# determinism preserved: replay == record
grep -qiE 'replay[[:space:]]*==[[:space:]]*record|record[[:space:]]*==[[:space:]]*replay|bit-?identical|determinism.*(intact|preserved|0/)' "$R" || fail "must show replay==record still holds (determinism preserved)"
ok "live record captures input (CAPTURED ${N}/${M}, byte-matches injected); determinism preserved"

CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goalc/' || fail "no host/runtime code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Ginput-replay-liverecord-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "host fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Glive PASS] v2 LIVE record captures real input (byte-matches injected); determinism preserved. Owner can re-record for real."
