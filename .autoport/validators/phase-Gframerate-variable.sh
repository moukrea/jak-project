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
# NUMERIC anti-false-green (owner 2026-06-30): don't pass on the WORD "flat" — require the
# per-regime game_units_per_real_sec NUMBERS to actually be (a) constant across fps regimes
# and (b) spike-free. The 'min/avg/max=A/B/C' triples must show cross-regime avg consistency
# and bounded transient spikes (the owner's slow-mo↔hyper-accel symptom = exactly these spikes).
python3 - "$R" <<'PY' || fail "speed numbers not constant/spike-free across regimes (see message)"
import re,sys
t=open(sys.argv[1],errors='replace').read()
trip=re.findall(r'game.?units[^=\n]*=\s*([\d.]+)\s*/\s*([\d.]+)\s*/\s*([\d.]+)', t, re.I)
if len(trip)<3:
    print("FAIL: need >=3 per-regime 'game_units_per_real_sec [min/avg/max]=A/B/C' triples in the report",file=sys.stderr); sys.exit(1)
mins=[float(a) for a,b,c in trip]; avgs=[float(b) for a,b,c in trip]; maxs=[float(c) for a,b,c in trip]
# (a) constant speed regardless of fps: regime averages must agree within 15%
if min(avgs)<=0 or max(avgs)/min(avgs) > 1.15:
    print(f"FAIL: game-speed NOT constant across fps regimes — regime avgs {avgs} spread {max(avgs)/max(min(avgs),1e-9):.2f}x (need <=1.15x). The fix must make speed fps-INDEPENDENT.",file=sys.stderr); sys.exit(1)
# (b) no transient spikes (the owner's momentary hyper-acceleration): per regime max<=1.6*avg, min>=0.6*avg
for a,b,c in trip:
    a,b,c=float(a),float(b),float(c)
    if c > 1.6*b or a < 0.6*b:
        print(f"FAIL: speed SPIKES within a regime (min/avg/max={a}/{b}/{c}) — momentary slow-mo/hyper-accel still present (need max<=1.6*avg, min>=0.6*avg). Exclude warm-up frames OR fix the real spike.",file=sys.stderr); sys.exit(1)
print(f"OK: speed constant across regimes (avgs {avgs}) and spike-free")
PY
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
