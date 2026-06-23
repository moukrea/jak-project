#!/usr/bin/env bash
# Validator — Gtouch-rightstick: the right camera must be a FLOATING anchor+deflection virtual stick
# (sustained RIGHTX/RIGHTY from offset-to-anchor), NOT a frame-delta mouse-drag. android-only; 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Grstick FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Grstick ok] $*"; }

R=.autoport/reports/Gtouch-rightstick/cam.txt
[ -f "$R" ] || fail "no cam.txt"
grep -qiE 'RESULT:[[:space:]]*RIGHT[[:space:]]+CAMERA[[:space:]]+IS[[:space:]]+A[[:space:]]+FLOATING[[:space:]]+DEFLECTION[[:space:]]+STICK' "$R" \
  || fail "cam.txt lacks RESULT: RIGHT CAMERA IS A FLOATING DEFLECTION STICK (sustained, not delta)"
grep -qiE 'anchor|deflect|offset.*(anchor|down)|cur ?- ?anchor|floating' "$R" || fail "cam.txt must show the anchor+deflection model"
grep -qiE 'sustain|held|continuous|does not decay|not.*delta' "$R" || fail "cam.txt must show a HELD offset gives SUSTAINED RIGHTX/RIGHTY (not a decaying delta)"
grep -qiE 'rightx|righty' "$R" || fail "cam.txt must show RIGHTX/RIGHTY actuation"
grep -qiE 'release.*(0|zero)|0.*release' "$R" || fail "cam.txt must show release -> RIGHTX/RIGHTY = 0"

# the camera axis must NOT come from a frame-delta anymore (grep the source)
TV=android/app/src/main/java/org/opengoal/gk/TouchOverlayView.java
[ -f "$TV" ] || fail "TouchOverlayView.java missing"
# the camera computation should reference an anchor, not lastX/lastY-delta for the axis
grep -qiE 'anchor|down[XY]|origin[XY]|startX|startY' "$TV" || fail "TouchOverlayView has no anchor-point for the camera (still delta-based?)"
ok "right camera is anchor+deflection (sustained), release zeroes; not frame-delta"

# android-only; goal_src 1-to-1
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'android/**' 2>/dev/null | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'android/' || fail "no android/** change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited (must stay 1-to-1): $SRC"
S=.autoport/reports/Gtouch-rightstick-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "android-only; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

echo "[Grstick PASS] right camera is now a floating invisible deflection stick; android-only; goal_src 1-to-1. Owner eye = final on feel."
