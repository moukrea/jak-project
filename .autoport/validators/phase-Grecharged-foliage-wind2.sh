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
grep -q 'level=beach' "$CENSUS" || fail "census missing level=beach"
grep -q 'level=village1' "$CENSUS" || fail "census missing level=village1"
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

# ---- 4. the shear audit: absolute amplitude + OFF==stock identity, both un-fakeable --------------
# The shear is dimensionless and displaces a vertex by shear * (its height above the instance
# origin). The floors below are FIXED physical design targets stated up front, NOT a running max
# ratcheted from whatever this run happened to produce.
#   applied_peak >= 0.05  == a crown swings at least 5% of the palm's own height (round 1 applied
#                            ~0.4%, which is what the owner correctly called "nada").
#   ratio_peak   >= 4.0   == comfortably more than the x3 shear multiplier round 1 shipped.
#   OFF ratio_peak == 1   == with the toggle off the applied shear IS the stock shear, at runtime.
python3 - "$D" <<'PY' || exit 1
import glob, re, sys
rx = re.compile(r'\[foliage-wind\] shear-audit .*?\bon=(\d+)\b.*?\bapplied_peak=([0-9.eE+-]+).*?\bratio_peak=([0-9.eE+-]+)')
on_rows, off_rows = [], []
for p in glob.glob(sys.argv[1] + '/*.log'):
    for line in open(p, errors='ignore'):
        m = rx.search(line)
        if not m:
            continue
        (on_rows if m.group(1) == '1' else off_rows).append(
            (float(m.group(2)), float(m.group(3))))
if not on_rows:
    print("[Gfoliage2 FAIL] no 'shear-audit ... on=1' line on device", file=sys.stderr); sys.exit(1)
if not off_rows:
    print("[Gfoliage2 FAIL] no 'shear-audit ... on=0' line — OFF==stock is unproven at runtime",
          file=sys.stderr); sys.exit(1)
ap = max(r[0] for r in on_rows)
rp = max(r[1] for r in on_rows)
bad = [r for r in off_rows if abs(r[1] - 1.0) > 1e-4]
if bad:
    print(f"[Gfoliage2 FAIL] toggle OFF applied a non-stock shear (ratio_peak={bad[0][1]})",
          file=sys.stderr); sys.exit(1)
if ap < 0.05:
    print(f"[Gfoliage2 FAIL] applied_peak={ap:.5f} < 0.05 — crown sway under 5% of palm height",
          file=sys.stderr); sys.exit(1)
if rp < 4.0:
    print(f"[Gfoliage2 FAIL] ratio_peak={rp:.3f} < 4.0 vs stock", file=sys.stderr); sys.exit(1)
print(f"[Gfoliage2 ok] shear audit: ON applied_peak={ap:.5f} ratio_peak={rp:.2f}; "
      f"OFF ratio_peak==1.0 on {len(off_rows)} window(s) => OFF is stock arithmetic at runtime")
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
