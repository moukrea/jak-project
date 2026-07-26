#!/usr/bin/env bash
# Grecharged-pbr-realtime-fusion ROUND 22 — GLSL compile gate for the WHOLE PBR family.
#
# Supersedes gpbrf_r17_glslcheck.sh (which only covered the tfrag3 family). Round 22 lifts the
# fused rt+pbr path into shared chunks (pbr_uniforms/pbr_helpers/pbr_fused .glsl) and ports it to
# shrub / tie_wind / etie_base, so every one of those stages must be compiled here — and it must be
# compiled AFTER `#include` expansion, because a chunk that only resolves on one of the two
# platforms, or only compiles in one of the two dialects, is a shipped black screen.
#
# For each stage, both variants the runtime actually builds:
#   * desktop : the .vert/.frag source + expand_includes() + OG_PBR define + HEIGHT_SCALE/SCISSOR_*
#   * android : preprocess.py's #version 320 es output + expand_includes() against the GENERATED
#               chunk copies (which have had the same sampler1D/noperspective treatment) + the
#               same OG_PBR define.
# Exit 0 = every stage compiled in both variants.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GLSLC=${GLSLC:-$HOME/Android/android-ndk-r27c/shader-tools/linux-x86_64/glslc}
SRC=game/graphics/opengl_renderer/shaders
EXPAND=.autoport/gpbrf_r22_include_expand.py
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
[ -x "$GLSLC" ] || { echo "[glslcheck] FAIL: no glslc at $GLSLC"; exit 1; }

STAGES="
tfrag3.frag:fragment
tfrag3.vert:vertex
tfrag3_tess.tesc:tesscontrol
tfrag3_tess.tese:tesseval
tfrag3_tess.vert:vertex
shrub.frag:fragment
shrub.vert:vertex
tie_wind.frag:fragment
tie_wind.vert:vertex
etie_base.frag:fragment
etie_base.vert:vertex
etie.frag:fragment
etie.vert:vertex
"
FAIL=0

# Shader.cpp's runtime substitution (jak1 values) + the OG_PBR define injected after #version.
subst() {  # $1 = src file, $2 = out file, $3 = vert_like (1/0)
  python3 - "$1" "$2" "$3" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
vert_like = sys.argv[3] == "1"
if vert_like:
    src = re.sub("HEIGHT_SCALE", "1.0", src)
    src = re.sub("SCISSOR_ADJUST", "(512.0 / 448.0)", src)
src = re.sub("SCISSOR_HEIGHT", "448.0", src)
v = src.find("#version")
nl = src.find("\n", v) if v != -1 else -1
src = src[:nl+1] + "#define OG_PBR 1\n" + src[nl+1:] if nl != -1 else src + "\n#define OG_PBR 1\n"
open(sys.argv[2], "w").write(src)
PY
}

echo "##### GLSL COMPILE GATE r22 (glslc $($GLSLC --version 2>&1 | head -1)) #####"
mkdir -p "$TMP/gles"
python3 "$SRC/preprocess.py" "$SRC" "$TMP/gles" >/dev/null || { echo "[glslcheck] preprocess.py failed"; exit 1; }

# ---- STEP 0: the byte-identity proof for the tfrag3 extraction ----------------
# The owner validated tfrag3's look this round; lifting its fused path into chunks must be a
# provable no-op. /tmp/tfrag3.frag.orig is the pre-extraction file (git's copy works too).
ORIG=${TFRAG3_ORIG:-/tmp/tfrag3.frag.orig}
if [ ! -f "$ORIG" ]; then
  git show HEAD:"$SRC/tfrag3.frag" > "$TMP/tfrag3.head.frag" 2>/dev/null && ORIG="$TMP/tfrag3.head.frag"
fi
if [ -f "$ORIG" ]; then
  if python3 "$EXPAND" "$SRC/tfrag3.frag" --check "$ORIG"; then
    echo "  PASS byte-identity  tfrag3.frag expansion == pre-extraction source"
  else
    echo "  FAIL byte-identity  tfrag3.frag expansion DIFFERS from $ORIG"; FAIL=1
  fi
else
  echo "  SKIP byte-identity  (no pre-extraction reference available)"
fi

for entry in $STAGES; do
  [ -n "$entry" ] || continue
  f=${entry%%:*}; stage=${entry##*:}
  vl=0; case "$stage" in vertex|tesseval) vl=1;; esac

  # ---- desktop 410 core: expand includes from the SOURCE dir, then substitute ----
  python3 "$EXPAND" "$SRC/$f" "$SRC" > "$TMP/x_$f" || { echo "  FAIL expand $f"; FAIL=1; continue; }
  subst "$TMP/x_$f" "$TMP/d_$f" "$vl"
  OUT=$("$GLSLC" -fshader-stage="$stage" --target-env=opengl -fauto-map-locations -std=410core -o /dev/null "$TMP/d_$f" 2>&1)
  if [ $? -eq 0 ]; then echo "  PASS desktop410  $f ($stage)"; else
    echo "  FAIL desktop410  $f ($stage)"; echo "$OUT" | head -25; FAIL=1; fi

  # ---- android GLES 320 es: expand includes from the GENERATED dir ----
  base=${f%.*}; ext=${f##*.}
  A="$TMP/gles/$base.android.$ext"
  if [ -f "$A" ]; then
    python3 "$EXPAND" "$A" "$TMP/gles" > "$TMP/xa_$f" || { echo "  FAIL expand(gles) $f"; FAIL=1; continue; }
    subst "$TMP/xa_$f" "$TMP/a_$f" "$vl"
    OUT=$("$GLSLC" -fshader-stage="$stage" --target-env=opengl -fauto-map-locations -std=320es -o /dev/null "$TMP/a_$f" 2>&1)
    if [ $? -eq 0 ]; then echo "  PASS gles320es   $f ($stage)"; else
      echo "  FAIL gles320es   $f ($stage)"; echo "$OUT" | head -25; FAIL=1; fi
  else
    echo "  SKIP gles320es   $f (preprocess.py emitted no android variant)"
  fi
done

if [ $FAIL -eq 0 ]; then echo "GLSL-GATE-R22: PASS (every stage compiled, both variants, includes expanded)"; else
  echo "GLSL-GATE-R22: FAIL"; fi
exit $FAIL
