#!/usr/bin/env bash
# Validator — Gframerate-variable: free-fluctuating fps + constant game speed; the 30/60 vblank LOCK
# removed, target-fps fed the real device refresh, flicker fix kept. Objective markers + x86 smoke;
# device-consistency + owner play-test are enforced by the orchestrator close-gate (device/owner_verify).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gfps FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gfps ok] $*"; }

R=.autoport/reports/Gframerate-variable/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*VARIABLE[[:space:]]+FPS[[:space:]]*\+?[[:space:]]*(AND[[:space:]]+)?CONSTANT[[:space:]]+SPEED' "$R" \
  || fail "report lacks RESULT: VARIABLE FPS + CONSTANT SPEED"
# state-anchored: constant game-time across >=3 fps regimes (the owner's rule, not frame-indexed)
grep -qiE 'game.?units|units/real|game-time|per[ -]real-?sec|state-?anchored' "$R" || fail "must show state-anchored game-time per real second"
grep -qiE '30|45|50|60' "$R" || fail "must report multiple fps regimes"
grep -qiE 'constant|==|equal|same.*speed|flat' "$R" || fail "must show speed is CONSTANT across fps regimes"
grep -qiE 'flicker|black.*frame|0/|no black' "$R" || fail "must confirm zero black flicker (regression guard on 8b330f996)"
grep -qiE 'target-?fps|set-frame-rate|refresh' "$R" || fail "must show target-fps wired to the real refresh"
grep -qiE 'cutscene|slow-?mo|iop|pacer' "$R" || fail "must confirm cutscene speed (IOP pacer unpinned)"
ok "report: variable-fps + constant speed, state-anchored, flicker 0, target-fps wired, cutscene ok"

# the vblank cadence-LOCK must be GONE (the fake stable-grid clock that capped 30/60)
if grep -rnE 'g_gspeed_clock_active' android/gk_android_main.cpp 2>/dev/null | grep -qvE '//|/\*'; then
  fail "g_gspeed_clock_active still consumed in a35_read_ee_timer — the 30/60 lock clock was not removed"
fi
# the anti-flicker hold MUST remain (don't reintroduce the black flash)
grep -qiE 'present_this_cycle|undrawn|hold.*last|last good' android/android_renderer.cpp || fail "the flicker fix (never-present-undrawn / hold-last-frame) appears removed — regression"
ok "30/60 cadence lock removed; flicker hold-last-frame retained"

# real translation-layer change present (close-gate GATE 1 also checks this)
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|pc/' || fail "no android/pc runtime change"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "runtime change present; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken (link finish: logo)"

echo "[Gfps PASS] variable-fps + constant-speed markers present; lock removed; flicker kept; x86 ok. (close-gate: deploy_verify + owner play-test next)"
