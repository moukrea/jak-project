#!/usr/bin/env bash
# gpbrf_r23_glslcheck.sh — ROUND 23 GLSL gate for the whole PBR shader family.
#
# It runs the r22 compile gate (5 stages x {desktop 410 core, GLES 320 es}, after #include
# expansion) and REPLACES r22's STEP 0.
#
# WHY STEP 0 HAD TO CHANGE. r22's step 0 was a BYTE-IDENTITY proof: "expanding the newly-chunked
# tfrag3.frag reproduces the pre-extraction monolith exactly", i.e. the modularisation is a no-op.
# That proof is real but it is a ONE-SHOT: it was true at the extraction commit and can never be
# true again, because every later round deliberately changes the shader. Worse, the script's
# fallback reference is `git show HEAD:` — so once anything lands on top it reports FAIL for the
# healthiest possible reason (the round did its job), and a FAIL that fires on correct work trains
# you to ignore the gate. Re-pinning it to the pre-extraction blob does not help either: HEAD now
# legitimately differs from it by the whole of round 22.
#
# WHAT REPLACES IT — a gate that is meaningful going forward. For each of the four programs that
# consume the shared chunks, expand it now, expand it at HEAD, diff CODE lines only (comments
# stripped), and require every changed line to match this round's INTENDED-CHANGE allowlist. So:
#   * an unintended edit anywhere in 2000+ expanded lines fails the gate,
#   * the intended edits pass and are PRINTED, so the report quotes the delta instead of asserting it.
# Add a token here only together with the change it describes.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SRC=game/graphics/opengl_renderer/shaders
EXPAND=.autoport/gpbrf_r22_include_expand.py
PROGRAMS="tfrag3.frag shrub.frag tie_wind.frag etie_base.frag"

# ROUND 23 intended changes, one token per change:
#   pom_drive / POM_MAX_FEATURE_FRAC  = defect B, the last drive-independent amplitude rail
#                                       (pbr_fused.glsl + tfrag3.frag's standalone rt-OFF march)
#   has_vn / 134217728                = defect C, shrub keeps the consolidated mesh normal for the
#                                       displacement frame instead of a camera-forced one
#   u_pbr_uv_per_m                    = the continuation line of the re-wrapped pom_cap expression
#   tess_disp_w / tess_displaced /    = defect A, per-FRAGMENT tessellation coverage: the tess tier
#   TESS_COVER_MIN / u_pbr_tess_active  fades to zero past ~30 m and on welded seams, so the old
#                                       per-PROGRAM flag both suppressed the POM there and counted
#                                       those flat pixels as covered
# The allowlist must cover BOTH sides of the diff: a `<` (removed) line is as much part of an
# intended change as the `>` that replaces it, so the pre-image of each edit is listed too.
ALLOW='pom_drive|POM_MAX_FEATURE_FRAC|has_vn|134217728|max\(u_pbr_uv_per_m|dot\(N, Vv\)|dot\(v_normal, v_normal\)|tess_disp_w|tess_displaced|TESS_COVER_MIN|u_pbr_tess_active'

TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
mkdir -p "$TD/head"
for f in $(git ls-tree --name-only HEAD "$SRC/" | xargs -n1 basename); do
  git show "HEAD:$SRC/$f" > "$TD/head/$f" 2>/dev/null || true
done

echo "##### STEP 0 (r23): expansion code-delta vs HEAD, against the intended-change allowlist #####"
STEP0_FAIL=0
for p in $PROGRAMS; do
  python3 "$EXPAND" "$SRC/$p"      > "$TD/now.$p"  || { echo "  FAIL expand $p (now)";  STEP0_FAIL=1; continue; }
  python3 "$EXPAND" "$TD/head/$p"  > "$TD/head.$p" || { echo "  FAIL expand $p (HEAD)"; STEP0_FAIL=1; continue; }
  # Compare CODE only: a comment rewrite is not a behaviour change and must not fail the gate.
  changed=$(diff <(grep -vE '^[[:space:]]*//' "$TD/head.$p") \
                 <(grep -vE '^[[:space:]]*//' "$TD/now.$p") \
            | grep -E '^[<>]' || true)
  if [ -z "$changed" ]; then
    echo "  PASS $p — expansion code-identical to HEAD"
    continue
  fi
  # every changed code line must be explained by the allowlist
  unexplained=$(echo "$changed" | grep -vE "$ALLOW" || true)
  n_changed=$(echo "$changed" | grep -c . || true)
  if [ -n "$unexplained" ]; then
    echo "  FAIL $p — $n_changed changed code line(s), UNEXPLAINED by the r23 allowlist:"
    echo "$unexplained" | sed 's/^/        /'
    STEP0_FAIL=1
  else
    echo "  PASS $p — $n_changed changed code line(s), all intended:"
    echo "$changed" | sed 's/^/        /'
  fi
done
[ "$STEP0_FAIL" = 0 ] && echo "STEP0-R23: PASS" || echo "STEP0-R23: FAIL"

echo
echo "##### STEPS 1..N: the r22 compile gate (unchanged), byte-identity step neutralised #####"
# Neutralise r22's one-shot byte-identity step so it cannot mask a real compile failure below. It
# compares EXPAND(tfrag3.frag) against its reference, so the reference has to be the EXPANSION —
# pointing it at the raw source makes it tautologically FALSE (the raw source still holds #include
# lines), not tautologically true. The delta it used to guard is covered by STEP 0 above.
python3 "$EXPAND" "$SRC/tfrag3.frag" > "$TD/tfrag3.expanded.frag"
TFRAG3_ORIG="$TD/tfrag3.expanded.frag" bash .autoport/gpbrf_r22_glslcheck.sh
COMPILE_RC=$?

echo
if [ "$STEP0_FAIL" = 0 ] && [ "$COMPILE_RC" = 0 ]; then
  echo "GLSL-GATE-R23: PASS"; exit 0
fi
echo "GLSL-GATE-R23: FAIL (step0_fail=$STEP0_FAIL compile_rc=$COMPILE_RC)"; exit 1
