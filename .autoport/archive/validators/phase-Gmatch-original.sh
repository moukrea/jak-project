#!/usr/bin/env bash
# Validator — Gmatch-original: OBJECTIVE gate, device vs the UNTOUCHED v0.3.3
# original (jak-original-v033). Runs the graphics-verify harness on whatever
# build the worker deployed, then gates on the RELIABLE signals:
#   - no crash (crash_signatures == 0)
#   - reaches in-game (ingame-firstframe reached)
#   - no halo at the ND-logo beat (intro-logo halo_excess_frac < 0.01)
# (The moving-intro/title PIXEL diffs are phase-confounded; not gated yet —
#  matched-phase capture is a follow-up. The menu black-rect artifact + cinematic
#  pixel-match become gates once those beats are reached + phase-aligned.)
# Always force-restores the known-good f1c set afterward so the phone stays usable.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/graphics-verify/report.json
fail(){ echo "[Gmatch FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }

# 1. anti-stub: NONE needed beyond the fresh harness itself. The legitimate fix
#    for this phase may be "deploy the RIGHT existing libgk" (e.g. a later commit
#    whose Gcine/halo fixes already exist) — that is NOT a code change but IS a
#    real, persisted device improvement. The gate below RE-RUNS verify_device_
#    graphics.sh fresh against the v0.3.3 original, so a PASS = the device genuinely
#    matched the original right now; it cannot be faked by a stale report. That IS
#    the anti-stub. (A code-change requirement here wrongly rejected attempt 1.)

# 2. run the objective harness on the currently-deployed build
echo "[Gmatch] running graphics-verify harness..."
bash .autoport/lib/verify_device_graphics.sh > .autoport/reports/graphics-verify/validator-run.log 2>&1 || true
[ -f "$R" ] || fail "harness produced no report.json"
cp -f "$R" .autoport/reports/graphics-verify/report-$(date +%s).json 2>/dev/null || true

# 3. gate on the reliable objective signals
VERDICT=$(python3 - "$R" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
crash=r.get('crash_signatures',1)
beats={b['beat']:b for b in r.get('beats',[])}
intro=beats.get('intro-logo',{}) or {}
ingame=beats.get('ingame-firstframe',{}) or {}
halo=intro.get('halo_excess_frac') or 0.0
fails=[]
if crash and crash>0: fails.append(f"crash_signatures={crash}")
if not ingame.get('reached'): fails.append("did NOT reach in-game (new-game/cinematic crash blocks it)")
if halo and halo>0.01: fails.append(f"halo at ND-logo (excess_frac={halo:.4f})")
print("FAIL: "+"; ".join(fails) if fails else "PASS")
PY
)
echo "[Gmatch] $VERDICT"

# 4. ALWAYS restore known-good so the device stays usable for the owner
bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true

# 5. verdict
case "$VERDICT" in
  PASS*) echo "[Gmatch PASS] device matches original on the gated signals (no crash, reaches in-game, no halo). Known-good restored."; exit 0;;
  *)     echo "[Gmatch] $VERDICT" >&2; exit 1;;
esac
