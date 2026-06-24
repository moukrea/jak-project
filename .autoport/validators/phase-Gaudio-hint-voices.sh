#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${ANCHOR:-HEAD}
fail(){ echo "[Ghintvox FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
R=.autoport/reports/Gaudio-hint-voices/voices.txt
[ -f "$R" ] || fail "no voices.txt"
grep -qiE 'RESULT:[[:space:]]*IN-GAME[[:space:]]+HINT[[:space:]]+VOICES.*AUDIBLE' "$R" || fail "voices.txt lacks RESULT: IN-GAME HINT VOICES + ACTION SFX AUDIBLE (device)"
grep -qiE 'hint|talker|tutorial|sage|ambient|dialog' "$R" || fail "must cover the in-game hint/tutorial dialog voice"
grep -qiE 'rms|non-?silent|sample|0.*>|before|after' "$R" || fail "must show per-source RMS BEFORE 0 -> AFTER >0"
grep -qiE 'action|sfx|snd-?play' "$R" || fail "must cover the missing action sounds"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited: $SRC"
S=.autoport/reports/Gaudio-hint-voices-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary <60 lines"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified"
bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Ghintvox PASS] in-game hint/tutorial voices + action SFX audible on device; goal_src 1-to-1. Owner ear final."
