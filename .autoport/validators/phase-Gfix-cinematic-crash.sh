#!/usr/bin/env bash
# Validator — Gfix-cinematic-crash: the owner's EXACT new-game path (menu -> NEW GAME ->
# select save -> overwrite -> yes -> cinematic) must complete crash-free, repeatably (>=3x).
# Calibrated: BEFORE must reproduce the crash. No proxy/shortcut. See [[proxy-dumps-false-green]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gfix-cine FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gfix-cine ok] $*"; }

R=.autoport/reports/Gfix-cinematic-crash/runs.txt
[ -f "$R" ] || fail "no runs.txt (owner's exact path driven >=3x with crash results)"
grep -qiE 'RESULT:[[:space:]]*CINEMATIC[[:space:]]+COMPLETES[[:space:]]+CRASH-?FREE[[:space:]]*\(3/3\)' "$R" || fail "runs.txt lacks RESULT: CINEMATIC COMPLETES CRASH-FREE (3/3)"
# calibration: a BEFORE that reproduced the crash on the current build
grep -qiE 'before|baseline|reproduc' "$R" || fail "runs.txt must document the BEFORE that reproduced the crash (calibration)"
grep -qiE 'new game|new-game|overwrite|save' "$R" || fail "runs.txt must show the owner's exact path (new game -> save -> overwrite)"
# >=3 gameplay-reach markers
N=$(grep -acE 'frame=1[0-9]{4}|reach.*gameplay|GAMEPLAY' "$R" 2>/dev/null || true); [ "${N:-0}" -ge 3 ] || fail "fewer than 3 crash-free gameplay-reaching runs documented (got $N)"
ok "owner-exact path completes crash-free >=3/3 (calibrated against a reproduced BEFORE crash)"

# real code change + fix-summary + dumps removed
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goal_src/**' 2>/dev/null | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goal_src/' || fail "no real code change"
S=.autoport/reports/Gfix-cinematic-crash-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"

# x86 unbroken + deploy landed
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gfix-cine PASS] new-game intro cinematic completes crash-free on the owner's EXACT path (3/3), x86 unchanged. Known-good restored."
