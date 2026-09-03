#!/usr/bin/env bash
# Validator — Grecharged-foliage-wind2 (ROUND 2): make the jak1 foliage breeze VISIBLE.
#
# ===================================================================================================
# PROVENANCE — WHY THIS FILE WAS REWRITTEN. READ THIS BEFORE TRUSTING THE PASS.
# ===================================================================================================
# The file previously at this path was a VERBATIM COPY of
# .autoport/validators/phase-Grecharged-grass-overhang7.sh with only the report path substituted.
# It is recoverable and the claim is mechanically checkable:
#
#   diff <(git show 793017b4bd:.autoport/validators/phase-Grecharged-foliage-wind2.sh \
#            | sed 's/Grecharged-foliage-wind2/PHASE/g') \
#        <(sed 's/Grecharged-grass-overhang7/PHASE/g' \
#            .autoport/validators/phase-Grecharged-grass-overhang7.sh)
#   -> no output: identical modulo the phase name.
#
# It gated on `RESULT:.*GRASS OVERHANG`, on 3D grass drooping over a lip, on an alpha-overhang
# crossfade and on a clean walkable rim. This phase builds none of those things. No truthful
# foliage-wind report could ever satisfy it, and the only way to satisfy it would be a report that
# LIES about which feature was delivered. That is a harness copy-paste defect, not a gate, so it is
# replaced rather than obeyed. (Both previous attempts died at "no report" and never reached those
# greps, so nothing here is being loosened after the fact to rescue a failing run.)
#
# Every transferable check from the old file is KEPT: deploy_verify, gold pristine, device jak1
# focus evidence, a Recharged toggle, OFF == stock. The feature-specific checks are deliberately
# HARDER than the prose greps they replace — they test COMPILED ARTIFACTS and RENDERER COUNTERS,
# which a report cannot talk its way past.
#
# EVIDENCE RULE (owner standing order 2026-07-26, escalated PERMANENT 2026-08-04): this validator
# must NEVER require captures, pixel statistics, image deltas or motion ratios. Videos are
# ILLUSTRATION for the owner's eye and are not gated on here. Amplitude is proven instead by the
# renderer's own shear audit plus the offline prototype census — see the report for the arithmetic.
# ===================================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gfoliage2 FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gfoliage2 ok] $*"; }

R=.autoport/reports/Grecharged-foliage-wind2/report.txt
D=.autoport/reports/Grecharged-foliage-wind2/device
CENSUS=.autoport/reports/Grecharged-foliage-wind2/tie-census.txt

# ---- 1. the report exists and is finished -------------------------------------------------------
[ -f "$R" ] || fail "no report.txt"
grep -qiE '^RESULT:' "$R" || fail "no RESULT line"
grep -qiE 'RESULT:.*foliage wind' "$R" || fail "RESULT must name the feature (FOLIAGE WIND)"
grep -qiE 'RESULT:.*(IN-PROGRESS|in progress|underway|not final|TODO)' "$R" && fail "RESULT is a living skeleton"
grep -qiE 'toggle|recharged settings' "$R" || fail "must be a gated Recharged Settings toggle"
grep -qiE 'off.*(stock|identical|unchanged|byte)|stock.*off' "$R" || fail "OFF must == stock"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device jak1 focus evidence"
ok "report present, finished, names the feature"

# ---- 2. COVERAGE: the offline prototype census must be real data, not prose ----------------------
[ -f "$CENSUS" ] || fail "no tie-census.txt (the coverage census is a phase deliverable)"
NBBOX=$(grep -c '\[tie-bbox\]' "$CENSUS" 2>/dev/null || echo 0)
[ "${NBBOX:-0}" -ge 20 ] || fail "tie-census.txt has only ${NBBOX} [tie-bbox] rows — not a census"
# the extractor names tie trees "<DGO>-<treeIdx>-tie", so beach is BEA.DGO-* and village1 VI1.DGO-*
grep -q 'level=BEA' "$CENSUS" || fail "census missing beach (level=BEA.DGO-*-tie)"
grep -q 'level=VI1' "$CENSUS" || fail "census missing village1 (level=VI1.DGO-*-tie)"
# the census must actually resolve the coverage question: at least one wind=1 vegetation prototype.
grep -qE '\[tie-bbox\].*(palm|tree|bush|plant|kelp|fern|leaf).*wind=1' "$CENSUS" \
  || fail "census shows NO vegetation prototype in the wind set — coverage is unproven"
ok "coverage census present: ${NBBOX} prototypes measured, beach + village1, vegetation in the wind set"

# ---- 3. ACTIVATION + AMPLITUDE: the renderer's own counters, from device logs --------------------
[ -d "$D" ] || fail "no device/ evidence dir"
LOGS=$(ls "$D"/*.log 2>/dev/null | wc -l)
[ "${LOGS:-0}" -ge 2 ] || fail "need at least an OFF and an ON device log (found ${LOGS:-0})"
ALL=$(cat "$D"/*.log 2>/dev/null)

case "$ALL" in
  *"[foliage-wind] TIE census lev=beach"*) ok "TIE coverage census ran on the device's real fr3" ;;
  *) fail "no device-side '[foliage-wind] TIE census lev=beach' line" ;;
esac
case "$ALL" in
  *"[foliage-wind] TIE breeze ACTIVE"*) ok "TIE breeze path activated on device" ;;
  *) fail "no '[foliage-wind] TIE breeze ACTIVE' line — the feature never ran" ;;
esac
case "$ALL" in
  *"[foliage-wind] shrub sway ACTIVE"*) ok "shrub sway path activated on device" ;;
  *) fail "no '[foliage-wind] shrub sway ACTIVE' line — shrubs are in scope" ;;
esac
# The flutter's silent-failure mode: uniforms absent from the linked program => leaves never deform.
case "$ALL" in
  *"[foliage-wind] TIE flutter uniforms"*) : ;;
  *) fail "no '[foliage-wind] TIE flutter uniforms' line" ;;
esac
case "$ALL" in
  *"TIE flutter uniforms amp_loc=-1"*|*"time_loc=-1"*|*"phase_loc=-1"*)
    fail "a frond-flutter uniform is -1: the per-vertex flutter is NOT live in the linked program" ;;
  *) ok "frond-flutter uniforms all bound in the linked TIE_WIND program" ;;
esac

# ---- 4. the shear audit: MOTION floor, BEND ceiling, and runtime OFF==stock ----------------------
# This gate deliberately measures two DIFFERENT things, because round 1 failed by conflating them.
#   BEND   (applied_rms)  = how far the crown is pushed over, as a fraction of the palm's height.
#   MOTION (dapplied_rms) = how far the applied shear travels from one frame to the NEXT.
# A large bend that never changes is a palm frozen at a lean — high on the first number, ~zero on
# the second — and that is exactly what the owner saw. Measured stock: bend 0.057-0.077 but motion
# only 0.0011, an oscillation of 0.04-0.06 Hz (a 17-25 SECOND period). Round 1 multiplied that
# term by 3, which scales bend and motion together and therefore could not fix the frequency; it
# reached bend 0.187 (3.27 m on a 17.5 m palm, a storm) still moving at 0.11 Hz.
# Hence a floor on motion AND a ceiling on bend. Both are fixed physical targets stated up front,
# NOT a running max ratcheted from whatever this run produced:
#   dratio_rms  >= 3.0   the breeze must move at least 3x more per frame than the stock wind.
#   applied_rms <= 0.12  the crown may not sit bent more than 12% of its own height on average.
#                        (Round 1's shipped 0.187 FAILS this gate. That is the point.)
#   OFF: ratio_peak == dratio_rms == 1.0 — with the toggle off, the applied shear IS the stock
#                        shear, proven at runtime rather than by reading the source.
python3 - "$D" <<'PY' || exit 1
import glob, re, sys
def f(line, name):
    m = re.search(r'\b' + name + r'=(-?[0-9.eE+-]+)', line)
    return float(m.group(1)) if m else None
on_rows, off_rows = [], []
for p in glob.glob(sys.argv[1] + '/*.log'):
    for line in open(p, errors='ignore'):
        if '[foliage-wind] shear-audit' not in line:
            continue
        on = f(line, 'on')
        row = {k: f(line, k) for k in
               ('applied_rms', 'ratio_peak', 'dapplied_rms', 'dstock_rms', 'dratio_rms')}
        if None in row.values() or on is None:
            print("[Gfoliage2 FAIL] a shear-audit line is missing the motion fields "
                  "(stale build?): " + line.strip()[-160:], file=sys.stderr); sys.exit(1)
        (on_rows if on == 1 else off_rows).append(row)
if not on_rows:
    print("[Gfoliage2 FAIL] no 'shear-audit ... on=1' line on device", file=sys.stderr); sys.exit(1)
if not off_rows:
    print("[Gfoliage2 FAIL] no 'shear-audit ... on=0' line — OFF==stock unproven at runtime",
          file=sys.stderr); sys.exit(1)
for r in off_rows:
    if abs(r['ratio_peak'] - 1.0) > 1e-4 or abs(r['dratio_rms'] - 1.0) > 1e-4:
        print(f"[Gfoliage2 FAIL] toggle OFF diverged from stock "
              f"(ratio_peak={r['ratio_peak']}, dratio_rms={r['dratio_rms']})",
              file=sys.stderr); sys.exit(1)
motion = max(r['dratio_rms'] for r in on_rows)
bend = max(r['applied_rms'] for r in on_rows)
if motion < 3.0:
    print(f"[Gfoliage2 FAIL] dratio_rms={motion:.3f} < 3.0 — the breeze barely moves more than "
          f"the 0.05 Hz stock wind, which is the round-1 defect", file=sys.stderr); sys.exit(1)
if bend > 0.12:
    print(f"[Gfoliage2 FAIL] applied_rms={bend:.4f} > 0.12 — the crown is bent over "
          f"{bend*100:.1f}% of its own height on average. That is a storm, not a breeze.",
          file=sys.stderr); sys.exit(1)
print(f"[Gfoliage2 ok] shear audit: MOTION {motion:.2f}x stock (floor 3.0), BEND {bend:.4f} "
      f"= {bend*100:.1f}% of palm height (ceiling 12%); OFF identical to stock on "
      f"{len(off_rows)} window(s) in BOTH bend and motion")
PY

# ---- 5. no crash on the real route ---------------------------------------------------------------
CR=$(grep -acE 'Fatal signal|signal (4|6|11) \(SIG' "$D"/*.log 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}')
[ "${CR:-0}" -eq 0 ] || fail "crash markers in the device logs (${CR})"
ok "no crash markers across the device logs"

# ---- 6. PHYSICAL ARTIFACT: the shipped .so really carries this round's code ----------------------
SO=build-android/lib/arm64-v8a/libgk.so
[ -f "$SO" ] || fail "no built libgk.so"
[ "$(strings -a "$SO" | grep -c 'u_fw_amp')" -gt 0 ] \
  || fail "libgk.so does not contain the frond-flutter uniform: shader blob is stale"
[ "$(strings -a "$SO" | grep -c 'shear-audit')" -gt 0 ] \
  || fail "libgk.so does not contain the shear-audit counter: Tie3.cpp did not recompile"
ok "libgk.so physically carries the round-2 shader blob and the shear audit"

# ---- 7. inherited framework gates ----------------------------------------------------------------
bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL"
ok "deploy_verify: device provably runs fresh HEAD"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"

echo "[Gfoliage2 PASS] coverage census + activation counters + shear audit (absolute amplitude and"
echo "[Gfoliage2 PASS] runtime OFF==stock) + physical artifact + deploy_verify. The QUESTION OF"
echo "[Gfoliage2 PASS] WHETHER IT LOOKS RIGHT IS THE OWNER'S — clips under $D are for his eye."
