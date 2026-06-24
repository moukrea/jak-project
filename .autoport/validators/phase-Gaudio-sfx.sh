#!/usr/bin/env bash
# Validator — Gaudio-sfx: in-game SFX + voice must reach the AAudio output on device (not just music),
# proven by a non-silent SFX/voice RMS measurement (calibrated BEFORE silent -> AFTER audible).
# See [[proxy-dumps-false-green]] (no "the function ran" proxy), [[gate-visual-quality-not-liveness]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gaudio FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gaudio ok] $*"; }

R=.autoport/reports/Gaudio-sfx/audio.txt
[ -f "$R" ] || fail "no audio.txt (device SFX/voice RMS measurement)"
grep -qiE 'RESULT:[[:space:]]*SFX[[:space:]]*\+?[[:space:]]*VOICE[[:space:]]+AUDIBLE[[:space:]]+ON[[:space:]]+DEVICE' "$R" \
  || fail "audio.txt lacks RESULT: SFX + VOICE AUDIBLE ON DEVICE (samples reach AAudio)"
# must be a sample/RMS measurement at the output — not a "snd-play was called" proxy
grep -qiE 'rms|non-?silent|amplitude|sample|aaudio|peak|dbfs' "$R" || fail "audio.txt must measure actual output samples (RMS/amplitude), not a call-count proxy"
# SFX covered
grep -qiE 'sfx|crate|orb|snd-?play|sound.?effect' "$R" || fail "audio.txt must cover SFX (crate/orb/snd-play)"
# voice covered
grep -qiE 'voice|dialog|sage|speech|vag.*voice' "$R" || fail "audio.txt must cover VOICE/dialog"
# calibrated BEFORE silent -> AFTER audible
grep -qiE 'before|baseline|silent|≈ ?0|= ?0|rms.?0' "$R" || fail "audio.txt must document the BEFORE (SFX/voice RMS ~0 while music > 0)"
grep -qiE 'after' "$R" || fail "audio.txt must document the AFTER (SFX/voice RMS > 0)"
grep -qiE 'music.*(>|non-?zero|>0)|music.*rms' "$R" || fail "audio.txt should show music RMS>0 (the working reference) for contrast"
ok "deterministic SFX+voice RMS: BEFORE ~0 -> AFTER >0 (music>0 reference); gap named"

# real fix + goal_src 1-to-1 + summary
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/' || fail "no real audio code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited (must stay 1-to-1): $SRC"
S=.autoport/reports/Gaudio-sfx-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "real fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
grep -qiE 'gameplay|frame[= ]*1[0-9]{4}|crash-?free|boot' "$R" || fail "audio.txt must show the build boots to gameplay"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gaudio PASS] in-game SFX + voice reach the AAudio output on device (RMS>0, calibrated vs the silent before). Owner ear = final."
