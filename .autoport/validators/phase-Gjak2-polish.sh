#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gj2polish FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gjak2-polish/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*JAK2 POLISH' "$R" || fail "no RESULT"
grep -qiE 'crouch|accroupi|L1' "$R" || fail "L1/R1 crouch mapping must be addressed"
grep -qiE 'cinemat.*aspect|aspect.*cinemat|cutscene.*aspect' "$R" || fail "cutscene aspect must follow the setting"
grep -qiE 'order|ordre' "$R" && grep -qiE 'advanced|ps2' "$R" || fail "menu order+label parity required"
grep -qiE 'fps.*(counter|compteur|option)' "$R" || fail "FPS counter option required"
grep -qiE 'rift|glow|portal' "$R" || fail "rift-gate glow tuning required"
grep -qiE 'mCurrentFocus.*jak2|focus.*jak2' "$R" || fail "jak2 foreground evidence"
V=$(find .autoport/reports/Gjak2-polish -type f \( -name '*.mp4' -o -name '*.png' \) 2>/dev/null | head -1)
[ -n "$V" ] || fail "no visual evidence"

# OWNER ROUND-3 (2026-07-09): PORT jak1 fixes, don't reinvent; no false-green self-cert.
# GAME-SPEED: the Gcamera-interp fix must be PORTED to jak2 (was jak1-only -> camera judder
# read as "variable speed"). Require the ported symbol to exist + be called in jak2 source.
grep -qiE 'cam-render-interp!|camera.?interp|pc-camera-interp-alpha' "$R" || fail "round3: must PORT jak1 cam-render-interp! to jak2 (game-speed/camera-judder)"
grep -qc 'cam-render-interp!' goal_src/jak2/engine/camera/cam-update.gc >/dev/null 2>&1 || fail "round3: cam-render-interp! not present in goal_src/jak2/engine/camera/cam-update.gc (port it, don't reinvent)"
# COLLISION: the crouch fix enabled nav-engine/collide methods hitting arm64 math divergence;
# the report must address collision-math COVERAGE for those methods (not a blind re-noop).
grep -qiE 'collision.?math|nav-engine|collide-cache|nan.?compare|fmin|fmax|vftoi|method 17' "$R" || fail "round3: must cover jak1 arm64 collision-math for the active jak2 nav/collide methods"
grep -qiE 'regress|prev.*build|previous build' "$R" || fail "round3: must address the speed/collision REGRESSION vs the previous build"
# HONESTY: subjective items (glow look, cutscene fill, speed/collision feel) must be handed to
# the OWNER, not self-certified. Reject any 'device-verified'/'confirmed' claim on those.
grep -qiE '(glow|cutscene|aspect|speed|collision).*(device-verified|confirmed working|verified fixed)' "$R" && fail "round3: do NOT self-certify subjective items — hand them to the owner's eye"
grep -qiE 'owner.*(playtest|eye|judge|calibrat)|awaiting owner' "$R" || fail "round3: subjective items must be handed to the owner's playtest"

git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gj2polish PASS]"
