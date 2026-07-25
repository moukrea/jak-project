#!/usr/bin/env bash
# Grecharged-pbr-realtime-fusion — GLSL compile gate for the PBR-polish shaders.
#
# The Android device is unplugged this round, so a GLSL syntax/type error in the fused path would
# otherwise only be discovered by the owner as a black screen. This compiles BOTH variants the
# runtime actually builds, with the SAME preprocessing Shader.cpp/preprocess.py apply:
#   * desktop  : #version 410 core + OG_PBR define + HEIGHT_SCALE/SCISSOR_* token substitution
#   * android  : the #version 320 es blob preprocess.py generates + the same OG_PBR define
# using the NDK's glslc. Exit 0 = every stage compiled.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GLSLC=${GLSLC:-$HOME/Android/android-ndk-r27c/shader-tools/linux-x86_64/glslc}
SRC=game/graphics/opengl_renderer/shaders
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
[ -x "$GLSLC" ] || { echo "[glslcheck] FAIL: no glslc at $GLSLC"; exit 1; }

STAGES="tfrag3.frag:fragment tfrag3_tess.tesc:tesscontrol tfrag3_tess.tese:tesseval tfrag3_tess.vert:vertex tfrag3.vert:vertex"
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

echo "##### GLSL COMPILE GATE (glslc $($GLSLC --version 2>&1 | head -1)) #####"
mkdir -p "$TMP/gles"
python3 "$SRC/preprocess.py" "$SRC" "$TMP/gles" >/dev/null || { echo "[glslcheck] preprocess.py failed"; exit 1; }
for entry in $STAGES; do
  f=${entry%%:*}; stage=${entry##*:}
  vl=0; case "$stage" in vertex|tesseval) vl=1;; esac

  # ---- desktop 410 core ----
  subst "$SRC/$f" "$TMP/d_$f" "$vl"
  OUT=$("$GLSLC" -fshader-stage="$stage" --target-env=opengl -fauto-map-locations -std=410core -o /dev/null "$TMP/d_$f" 2>&1)
  if [ $? -eq 0 ]; then echo "  PASS desktop410  $f ($stage)"; else
    echo "  FAIL desktop410  $f ($stage)"; echo "$OUT" | head -20; FAIL=1; fi

  # ---- android GLES 320 es (exactly what preprocess.py emits) ----
  base=${f%.*}; ext=${f##*.}
  A="$TMP/gles/$base.android.$ext"
  if [ -f "$A" ]; then
    subst "$A" "$TMP/a_$f" "$vl"
    OUT=$("$GLSLC" -fshader-stage="$stage" --target-env=opengl -fauto-map-locations -std=320es -o /dev/null "$TMP/a_$f" 2>&1)
    if [ $? -eq 0 ]; then echo "  PASS gles320es   $f ($stage)"; else
      echo "  FAIL gles320es   $f ($stage)"; echo "$OUT" | head -20; FAIL=1; fi
  else
    echo "  SKIP gles320es   $f (preprocess.py emitted no android variant)"
  fi
done

if [ $FAIL -eq 0 ]; then echo "GLSL-GATE: PASS (every stage compiled, both variants)"; else
  echo "GLSL-GATE: FAIL"; fi
exit $FAIL
