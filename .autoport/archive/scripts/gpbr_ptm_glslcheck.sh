#!/usr/bin/env bash
# gpbr_ptm_glslcheck.sh — GLSL gate for phase Gpbr-per-texture-materials.
#
# Same shape as .autoport/gpbrf_r23_glslcheck.sh, with THIS phase's intended-change allowlist.
# It exists for the reason r23 states in its own header: r22's STEP 0 is a one-shot byte-identity
# proof against the PRE-EXTRACTION tfrag3.frag, so it reports FAIL for the healthiest possible
# reason — the round did its job — and a gate that fires on correct work trains you to ignore it.
#
# STEP 0 here: expand each PBR program now and at HEAD, diff CODE lines only (comments stripped),
# and require every changed line to be explained by the allowlist below. An unintended edit
# anywhere in 2000+ expanded lines fails; the intended edits pass AND ARE PRINTED, so the report
# quotes the delta instead of asserting it.
# STEP 1..N: the r22 COMPILE gate, unchanged — 5 stages x {desktop 410 core, GLES 320 es}, on
# freshly generated (preprocess.py) android variants, so no stale generated shader can hide behind
# a PASS.
#
# INTENDED CHANGES OF THIS PHASE — one token group per change. Add a token here only together with
# the change it describes.
#
#   HALF 1 — THE TANGENT FRAME IS TAKEN PER FACE, NOT PER VERTEX.
#     fdPx fdPy fdUx fdUy fdetJ fdPdv fhs fhw fBuv Bn      the fragment sites (pbr_fused.glsl and
#                                                          tfrag3.frag's standalone rt-OFF path)
#     pe1 pe2 pd1 pd2 pdet pdPdu pdPdv phs hax_u hax_v      the tess-eval site (the patch IS the
#                                                          original triangle, so no derivative is
#                                                          needed there)
#     u_pbr_bisect2                                        bisect BANK 2 — bank 1's 31 bits are all
#                                                          taken, so the A/B killswitch opens a new
#                                                          bank instead of overloading a used bit
#   HALF 2 — MATERIAL KNOBS BECOME PER TEXTURE.
#     u_pbr_mat u_pbr_mat2                                 the authored per-material vec4/vec2 the
#                                                          binder pushes per draw
#     rough metal F0 nraw                                  their four consumption sites (roughness,
#                                                          metallic, dielectric F0, normal-map
#                                                          green sign)
#
# The allowlist must cover BOTH sides of the diff: a removed `<` line is as much part of an
# intended change as the `>` that replaces it, so each edit's pre-image is covered too.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SRC=game/graphics/opengl_renderer/shaders
EXPAND=.autoport/gpbrf_r22_include_expand.py
PROGRAMS="tfrag3.frag shrub.frag tie_wind.frag etie_base.frag tfrag3_tess.tese"

ALLOW='fdPx|fdPy|fdUx|fdUy|fdetJ|fdPdu|fdPdv|fhs|fhw|fBuv|Bn = cross|fTuv = -fTuv|Tn = -Tn|pe1|pe2|pd1|pd2|pdet|pdPdu|pdPdv|phs|hax_u|hax_v|u_pbr_bisect2|u_pbr_mat|u_pbr_mat2|float rough =|float metal =|F0 = mix|nraw|w < 0\.0 \? -1\.0 : 1\.0|^[<>][[:space:]]*\}+[[:space:]]*$'
# The trailing token is the LEGACY FALLBACK expression itself — `(v_tangent.w < 0.0 ? -1.0 : 1.0)`
# and its tess-eval twin `(tc_tangent[0].w < 0.0 ? -1.0 : 1.0)`. It is the pre-image of the
# handedness edit AND survives inside it as the fallback arm (a degenerate UV Jacobian, or a 2x2
# quad straddling an edge, has no face sign to read), so it appears on both sides of the diff.
# Listed explicitly rather than left unexplained: an allowlist is only worth what it names.
# The last alternative allows a diff line that is NOTHING BUT a closing brace. Adding a guarded `if`
# adds one, and a brace on its own carries no semantics: any real change also shows a line with a
# token in it, which this allowlist still has to explain. Without it the gate reports FAIL on the
# punctuation of its own intended change -- the same "fires on correct work" failure that made r22's
# STEP 0 unusable.

TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
mkdir -p "$TD/head"
for f in $(git ls-tree --name-only HEAD "$SRC/" | xargs -n1 basename); do
  git show "HEAD:$SRC/$f" > "$TD/head/$f" 2>/dev/null || true
done

echo "##### STEP 0: expansion code-delta vs HEAD, against this phase's intended-change allowlist #####"
STEP0_FAIL=0
for p in $PROGRAMS; do
  python3 "$EXPAND" "$SRC/$p"     > "$TD/now.$p"  || { echo "  FAIL expand $p (now)";  STEP0_FAIL=1; continue; }
  python3 "$EXPAND" "$TD/head/$p" > "$TD/head.$p" || { echo "  FAIL expand $p (HEAD)"; STEP0_FAIL=1; continue; }
  changed=$(diff <(grep -vE '^[[:space:]]*//' "$TD/head.$p") \
                 <(grep -vE '^[[:space:]]*//' "$TD/now.$p") \
            | grep -E '^[<>]' || true)
  if [ -z "$changed" ]; then
    echo "  PASS $p — expansion code-identical to HEAD"
    continue
  fi
  unexplained=$(echo "$changed" | grep -vE "$ALLOW" || true)
  n_changed=$(echo "$changed" | grep -c . || true)
  if [ -n "$unexplained" ]; then
    echo "  FAIL $p — $n_changed changed code line(s), UNEXPLAINED by this phase's allowlist:"
    echo "$unexplained" | sed 's/^/        /'
    STEP0_FAIL=1
  else
    echo "  PASS $p — $n_changed changed code line(s), all intended:"
    echo "$changed" | sed 's/^/        /'
  fi
done
[ "$STEP0_FAIL" = 0 ] && echo "STEP0-GPM: PASS" || echo "STEP0-GPM: FAIL"

echo
echo "##### STEPS 1..N: the r22 COMPILE gate (both profiles); its one-shot byte-identity step is #####"
echo "##### neutralised the same way r23 neutralises it, and is NOT counted below.             #####"
python3 "$EXPAND" "$SRC/tfrag3.frag" > "$TD/tfrag3.expanded.frag"
CGATE="$TD/compile.log"
TFRAG3_ORIG="$TD/tfrag3.expanded.frag" bash .autoport/gpbrf_r22_glslcheck.sh > "$CGATE" 2>&1
grep -E '^  (PASS|FAIL|SKIP) ' "$CGATE" | grep -v 'byte-identity'
NCOMP_FAIL=$(grep -cE '^  FAIL (desktop410|gles320es|expand)' "$CGATE" || true)
NCOMP_PASS=$(grep -cE '^  PASS (desktop410|gles320es)' "$CGATE" || true)
echo "COMPILE: pass=$NCOMP_PASS fail=$NCOMP_FAIL (byte-identity excluded, see header)"

echo
if [ "$STEP0_FAIL" = 0 ] && [ "$NCOMP_FAIL" = 0 ] && [ "$NCOMP_PASS" -gt 0 ]; then
  echo "GLSL-GATE-GPM: PASS"; exit 0
fi
echo "GLSL-GATE-GPM: FAIL (step0_fail=$STEP0_FAIL compile_fail=$NCOMP_FAIL compile_pass=$NCOMP_PASS)"; exit 1
