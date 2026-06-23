#!/usr/bin/env bash
# Validator — Gtouch-controls: the Android on-screen overlay must expose the FULL control set with
# correct SDL mapping, per-control actuation, and show-on-touch + 10s-fade. android-only; goal_src 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gtouch FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gtouch ok] $*"; }

R=.autoport/reports/Gtouch-controls/controls.txt
[ -f "$R" ] || fail "no controls.txt (overlay-map + actuation + visibility tests)"
grep -qiE 'RESULT:[[:space:]]*TOUCH[[:space:]]+CONTROLS[[:space:]]+COMPLETE' "$R" || fail "controls.txt lacks RESULT: TOUCH CONTROLS COMPLETE (...)"
# full control set enumerated (every control must appear)
for c in south east west north dpad_up dpad_down dpad_left dpad_right start 'select|back' 'l1|left_shoulder' 'r1|right_shoulder' 'l2|left_trigger' 'r2|right_trigger' 'l3|left_stick' 'r3|right_stick' 'left.?stick|leftx|lefty' 'right.?stick|rightx|righty'; do
  grep -qiE "$c" "$R" || fail "controls.txt overlay-map missing control: $c"
done
ok "full control set enumerated (face/dpad/start/select/L1R1L2R2/L3R3/both sticks)"
# per-control actuation reaching native
grep -qiE 'onPadButton|onPadAxis' "$R" || fail "controls.txt must show per-control actuation (onPadButton/onPadAxis reaching native)"
grep -qiE 'actuat|tap.*->|inject.*button|axis.*value' "$R" || fail "controls.txt must document the actuation test (touch coords -> correct SDL button/axis)"
# visibility: show-on-touch + 10s fade
grep -qiE 'hidden|invisible|alpha.?0|fade' "$R" || fail "controls.txt must show the fade/hidden state"
grep -qiE 'touch.*(show|visible|wake)|show.*touch' "$R" || fail "controls.txt must show the show-on-touch behavior"
grep -qiE '10 ?s|10000|ten second|10-?sec' "$R" || fail "controls.txt must show the 10-second idle fade timer"
ok "actuation + show-on-touch + 10s-fade verified"

# android-only change; goal_src 1-to-1
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'android/**' 2>/dev/null | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'android/' || fail "no android/** code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited (must stay 1-to-1): $SRC"
S=.autoport/reports/Gtouch-controls-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden .autoport/gold not pristine"
ok "android-only change; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

# x86 unaffected + device runs fresh HEAD + reached gameplay
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
grep -qiE 'gameplay|frame[= ]*1[0-9]{4}|crash-?free|0 sig' "$R" || fail "controls.txt must show the build boots to gameplay crash-free"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unaffected; device runs fresh HEAD; boots to gameplay"

echo "[Gtouch PASS] full touch-control overlay (all buttons+sticks, PS icons, show-on-touch+10s-fade) wired to the game; android-only; goal_src 1-to-1. Owner eye = final on icon look/feel."
