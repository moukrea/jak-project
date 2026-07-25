#!/usr/bin/env bash
# Grecharged-buildsys-packaging (autoport 2026-07-17): build the PORT-CUSTOM asset
# pack the slim APK ships alongside the CGO pack.
#
# Owner rule: the game PACKAGE carries ALL port-custom artifacts. The CGO pack
# (build_cgo_pack.sh) carries the arm64 code; THIS pack carries the port-custom
# DATA gated by the build's feature flags:
#   recharged_assets/<name>.png   (flag recharged-hud ON, jak1 only)
#   fr3/<name>.grassbake          (ALWAYS — validated feature)
#   fr3/enhanced/<name>.fr3       (flag hd-models ON)
#   recharged_textures/<tpage>/<tex>/<tex>[ _height|_normal|_roughness].png  (ALWAYS — first-party set)
#
# The flag SET is recovered from the compiled arm64 GAME.CGO marker
# ("ogflags:<hash>:<target>"): the 12-char hash is inverted by enumerating the 32
# subsets of {grass-overhang, hd-models, pbr, recharged-hud, vulkan-support}, hashing
# each alphabetical comma-join, and matching. (Same canonical scheme as build.sh.)
#
# Output:
#   android/app/src/<game>/assets-slim/bundle/<game>_custom.zip           (paths preserved)
#   android/app/src/<game>/assets-slim/bundle/<game>_custom.manifest.properties
set -euo pipefail

GAME="${1:-jak1}"

cd "$(git rev-parse --show-toplevel)"
ROOT="$(pwd)"

fail(){ echo "[custom-pack] FATAL: $*" >&2; exit 1; }

ARM64_CODE="out/${GAME}-arm64-full/iso"
FR3_DIR="out/${GAME}/fr3"
OUT_DIR="android/app/src/${GAME}/assets-slim/bundle"
STAGE="out/${GAME}-custom-pack-stage"
ZIP_REL="${OUT_DIR}/${GAME}_custom.zip"
MANIFEST="${OUT_DIR}/${GAME}_custom.manifest.properties"
ZIP_ABS="${ROOT}/${ZIP_REL}"

GAME_CGO="${ARM64_CODE}/GAME.CGO"
[ -f "$GAME_CGO" ] || fail "no $GAME_CGO — rebuild via ./build.sh android-arm64"

# --- recover the flag marker + invert the hash to the flag SET ---
# || true: grep -o | head -1 close the pipe early -> SIGPIPE(141) would abort under
# set -euo pipefail even on a successful match.
MARKER=$(grep -a -o 'ogflags:[a-zA-Z0-9:_.-]*' "$GAME_CGO" | head -1 || true)
[ -n "$MARKER" ] || fail "pre-flag-era CGO set — rebuild via ./build.sh android-arm64"
# marker = ogflags:<hash>:<target>
HASH="${MARKER#ogflags:}"; HASH="${HASH%%:*}"
[ -n "$HASH" ] || fail "malformed marker '$MARKER'"

# Enumerate 32 subsets of the 5 flags (alphabetical universe), hash each canonical
# (alphabetical comma-join) string, match against HASH.
ALL_FLAGS=(grass-overhang hd-models pbr recharged-hud vulkan-support)
F_OVERHANG=0; F_HDMODELS=0; F_PBR=0; F_HUD=0; F_VULKAN=0
FOUND=0; MATCHED_STR=""
for mask in $(seq 0 31); do
  set_list=()
  for bit in 0 1 2 3 4; do
    if (( (mask >> bit) & 1 )); then set_list+=("${ALL_FLAGS[$bit]}"); fi
  done
  cand=$(IFS=,; echo "${set_list[*]-}")
  h=$(printf '%s' "$cand" | sha256sum | cut -c1-12)
  if [ "$h" = "$HASH" ]; then
    FOUND=1; MATCHED_STR="$cand"
    for fl in "${set_list[@]-}"; do
      case "$fl" in
        grass-overhang) F_OVERHANG=1;;
        hd-models)      F_HDMODELS=1;;
        pbr)            F_PBR=1;;
        recharged-hud)  F_HUD=1;;
        vulkan-support) F_VULKAN=1;;
      esac
    done
    break
  fi
done
[ "$FOUND" -eq 1 ] || fail "pre-flag-era CGO set — rebuild via ./build.sh android-arm64"
echo "[custom-pack] marker=$MARKER  flags='${MATCHED_STR:-<none>}' (hud=$F_HUD overhang=$F_OVERHANG hd-models=$F_HDMODELS pbr=$F_PBR vulkan=$F_VULKAN)"

mkdir -p "$OUT_DIR"
rm -rf "$STAGE"
mkdir -p "$STAGE"

MEMBERS=()   # zip-relative paths staged (for count + version)

# 1. recharged HUD PNGs — ONLY when recharged-hud ON and game == jak1.
if [ "$F_HUD" -eq 1 ] && [ "$GAME" = "jak1" ]; then
  mkdir -p "$STAGE/recharged_assets"
  n_png=0
  while IFS= read -r png; do
    [ -n "$png" ] || continue
    base="$(basename "$png")"
    ln -s "$png" "$STAGE/recharged_assets/$base"
    MEMBERS+=("recharged_assets/$base")
    n_png=$((n_png + 1))
  done < <(find "$ROOT/recharged_assets" -maxdepth 1 -type f -name '*.png' 2>/dev/null | sort)
  [ "$n_png" -gt 0 ] || fail "flag recharged-hud ON but no recharged_assets/*.png found"
  echo "[custom-pack] recharged HUD PNGs: $n_png"
fi

# 2. grassbake precompute tables — ALWAYS (validated feature; 0 is OK).
if [ -d "$FR3_DIR" ]; then
  mkdir -p "$STAGE/fr3"
  n_bake=0
  while IFS= read -r gb; do
    [ -n "$gb" ] || continue
    base="$(basename "$gb")"
    ln -s "$ROOT/$gb" "$STAGE/fr3/$base"
    MEMBERS+=("fr3/$base")
    n_bake=$((n_bake + 1))
  done < <(find "$FR3_DIR" -maxdepth 1 -type f -name '*.grassbake' 2>/dev/null | sort)
  echo "[custom-pack] grassbake tables: $n_bake"

  # 2b. Grecharged-mesh-consolidation sidecars — ALWAYS (0 is OK: a level without one just runs the
  #     live pass). These carry the consolidated weld: shared normals, snapped positions, blended
  #     baked-colour indices and seam weights. Measured on the Redmi they cut village1's load from
  #     67.0 s to 22.1 s, so shipping them is not an optimisation, it is the difference between a
  #     playable load and a minute of black screen. Built by: tools/mesh_audit --game <g> --bake.
  n_mesh=0
  while IFS= read -r mw; do
    [ -n "$mw" ] || continue
    base="$(basename "$mw")"
    ln -s "$ROOT/$mw" "$STAGE/fr3/$base"
    MEMBERS+=("fr3/$base")
    n_mesh=$((n_mesh + 1))
  done < <(find "$FR3_DIR" -maxdepth 1 -type f -name '*.meshweld' 2>/dev/null | sort)
  echo "[custom-pack] mesh-consolidation sidecars: $n_mesh"
fi

# 2c. FIRST-PARTY recharged replacement textures — ALWAYS (committed owner-made set at
#     custom_assets/<game>/recharged_textures/<tpage>/<texname>/{<texname>.png + _height/
#     _normal/_roughness}; the base swap needs no build flag, the PBR maps feed the PBR
#     pipeline when compiled in). Extracted by LoaderActivity to <custom root>/
#     recharged_textures/** (zip paths preserved); runtime scans
#     get_bundled_recharged_textures_dir(). 0 is OK (set absent).
RTEX_SRC="custom_assets/${GAME}/recharged_textures"
if [ -d "$ROOT/$RTEX_SRC" ]; then
  n_rtex=0
  while IFS= read -r tf; do
    [ -n "$tf" ] || continue
    rel="${tf#"$ROOT/$RTEX_SRC/"}"
    mkdir -p "$STAGE/recharged_textures/$(dirname "$rel")"
    ln -s "$tf" "$STAGE/recharged_textures/$rel"
    MEMBERS+=("recharged_textures/$rel")
    n_rtex=$((n_rtex + 1))
  done < <(find "$ROOT/$RTEX_SRC" -type f -name '*.png' 2>/dev/null | sort)
  echo "[custom-pack] recharged textures: $n_rtex"
fi

# 3. enhanced HD fr3 — ONLY when hd-models ON.
if [ "$F_HDMODELS" -eq 1 ]; then
  ENH="$FR3_DIR/enhanced"
  n_enh=0
  if [ -d "$ENH" ]; then
    mkdir -p "$STAGE/fr3/enhanced"
    while IFS= read -r ef; do
      [ -n "$ef" ] || continue
      base="$(basename "$ef")"
      ln -s "$ROOT/$ef" "$STAGE/fr3/enhanced/$base"
      MEMBERS+=("fr3/enhanced/$base")
      n_enh=$((n_enh + 1))
    done < <(find "$ENH" -maxdepth 1 -type f -name '*.fr3' 2>/dev/null | sort)
  fi
  [ "$n_enh" -gt 0 ] || fail "flag hd-models ON but $ENH missing/empty — run android/build_enhanced_models.sh"
  echo "[custom-pack] enhanced HD fr3: $n_enh"
fi

FILE_COUNT=${#MEMBERS[@]}

# content-derived version: md5 of member contents (empty-content md5 for 0 members),
# same c<hash> scheme as build_cgo_pack.sh.
if [ "$FILE_COUNT" -eq 0 ]; then
  VERSION="c$(printf '' | md5sum | cut -c1-12)"
  RAW_BYTES=0
else
  VERSION="c$( for m in "${MEMBERS[@]}"; do printf '%s\0' "$STAGE/$m"; done \
      | sort -z | xargs -0 md5sum | md5sum | cut -c1-12 )"
  RAW_BYTES=$(find -L "$STAGE" -type f -printf '%s\n' | awk '{s+=$1} END{print s+0}')
fi

# --- idempotent skip (version + file_count + mtime) ---
if [ -f "$ZIP_REL" ] && [ -f "$MANIFEST" ]; then
  cv=$(grep -E '^version=' "$MANIFEST" | cut -d= -f2 || echo "")
  cfc=$(grep -E '^file_count=' "$MANIFEST" | cut -d= -f2 || echo "")
  SRC_DIRS=("$FR3_DIR")
  [ -d "$ROOT/custom_assets/${GAME}/recharged_textures" ] && SRC_DIRS+=("$ROOT/custom_assets/${GAME}/recharged_textures")
  [ "$F_HUD" -eq 1 ] && [ "$GAME" = "jak1" ] && [ -d "$ROOT/recharged_assets" ] && SRC_DIRS+=("$ROOT/recharged_assets")
  newest=$(find "${SRC_DIRS[@]}" -type f -printf '%T@\n' 2>/dev/null | awk 'BEGIN{m=0}{t=int($1); if(t>m)m=t} END{print m}')
  zmt=$(stat -c %Y "$ZIP_REL")
  if [ "$cv" = "$VERSION" ] && [ "$cfc" = "$FILE_COUNT" ] && { [ -z "$newest" ] || [ "$zmt" -ge "$newest" ]; }; then
    echo "[custom-pack] up to date: $ZIP_REL (version=$VERSION file_count=$cfc)"
    rm -rf "$STAGE"
    exit 0
  fi
fi

echo "[custom-pack] packing $FILE_COUNT members → $ZIP_REL…"
rm -f "$ZIP_ABS"
if [ "$FILE_COUNT" -eq 0 ]; then
  # `zip -r stage/*` fails on an empty stage; create an empty (but valid) zip.
  python3 -c "import zipfile; zipfile.ZipFile('$ZIP_ABS','w').close()"
else
  (
    cd "$STAGE"
    # preserve zip paths (recharged_assets/, fr3/, fr3/enhanced/).
    zip -r -6 -X -q "$ZIP_ABS" .
  )
fi
ZIP_BYTES=$(stat -c %s "$ZIP_ABS")

cat > "$MANIFEST" <<EOF
# Generated by android/build_custom_pack.sh — do not edit.
version=${VERSION}
game=${GAME}
file_count=${FILE_COUNT}
raw_bytes=${RAW_BYTES}
flags=${MARKER}
EOF

rm -rf "$STAGE"

echo "[custom-pack] done: $ZIP_REL"
echo "[custom-pack]   files=$FILE_COUNT  raw=${RAW_BYTES}B  zip=${ZIP_BYTES}B  version=$VERSION  flags=$MARKER"
