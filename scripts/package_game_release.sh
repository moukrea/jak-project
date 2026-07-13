#!/usr/bin/env bash
# scripts/package_game_release.sh <jak1|jak2|jak3>
#
# The DESKTOP x86 counterpart of the asset split: packages the game BINARY plus
# the per-arch compiled code (the x86 *.CGO/*.DGO) plus the runtime data the gk
# needs that is NOT in the arch-independent asset archive (shaders + game assets).
# The big extracted originals (audio/text/vis/str/fr3) ship separately via
# scripts/package_game_assets.sh.
#
# Output: out/artifacts/<game>_binary_x86.tar.gz
#   gk                                                  (desktop x86 build)
#   data/out/<game>/iso/*.CGO,*.DGO                     (x86 compiled code set)
#   data/game/graphics/opengl_renderer/shaders/**       (renderer shaders)
#   data/game/assets/**                                 (fonts/controller-db/...)
#   README.txt                                          (how to run)
set -euo pipefail

usage(){ echo "usage: $0 <jak1|jak2|jak3>" >&2; exit 2; }

GAME="${1:-}"
[ -n "$GAME" ] || usage
case "$GAME" in jak1|jak2|jak3) ;; *) echo "[release] FATAL: unknown game '$GAME'" >&2; usage;; esac

fail(){ echo "[release] FATAL: $*" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"
ROOT="$(pwd)"

OUT_DIR="out/artifacts"
mkdir -p "$OUT_DIR"

# --- locate the desktop gk binary (newest of the known build layouts) ----------
echo "[release] desktop gk candidates:"
ls -la build*/game/gk 2>/dev/null || true
GK=""
GK_MT=0
for cand in build*/game/gk; do
  [ -f "$cand" ] || continue
  mt=$(stat -c %Y "$cand")
  if [ "$mt" -ge "$GK_MT" ]; then GK_MT=$mt; GK="$cand"; fi
done
[ -n "$GK" ] || fail "no desktop gk found (looked for build*/game/gk) — build the desktop target first"
echo "[release] using gk: $GK"

ISO_DIR="out/${GAME}/iso"
[ -d "$ISO_DIR" ] || fail "no $ISO_DIR — run the PC extract/build first"
mapfile -t CODE_FILES < <(find "$ISO_DIR" -maxdepth 1 -type f \( -name '*.CGO' -o -name '*.DGO' \) -printf '%f\n' | sort)
[ "${#CODE_FILES[@]}" -gt 0 ] || fail "no *.CGO/*.DGO in $ISO_DIR"
echo "[release] x86 code files: ${#CODE_FILES[@]}"

SHADERS="game/graphics/opengl_renderer/shaders"
ASSETS="game/assets"
[ -d "$SHADERS" ] || fail "no $SHADERS"
[ -d "$ASSETS" ]  || fail "no $ASSETS"

# --- stage a symlink farm so tar packs the "data/" layout without a giant copy --
STAGE="out/${GAME}-release-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/data/out/${GAME}/iso" \
         "$STAGE/data/game/graphics/opengl_renderer" \
         "$STAGE/data/game"

ln -s "$ROOT/$GK" "$STAGE/gk"
for f in "${CODE_FILES[@]}"; do
  ln -s "$ROOT/$ISO_DIR/$f" "$STAGE/data/out/${GAME}/iso/$f"
done
ln -s "$ROOT/$SHADERS" "$STAGE/data/game/graphics/opengl_renderer/shaders"
ln -s "$ROOT/$ASSETS"  "$STAGE/data/game/assets"
# gk's -debug-mem boot scans <data>/goal_src/user at startup and aborts if the
# directory is absent (proven in the Grecharged-external-assets x86 binpack
# test) — ship it empty.
mkdir -p "$STAGE/data/goal_src/user"

cat > "$STAGE/README.txt" <<EOF
${GAME} — desktop (x86) binary release
======================================

This tarball ships the OpenGOAL game binary (gk), the x86 compiled code
(*.CGO/*.DGO), the renderer shaders and the game assets. It does NOT include the
large extracted original assets (audio / text / vis / str / fr3 textures) — those
live in the separate archive produced by scripts/package_game_assets.sh
(${GAME}_assets.zip). Extract that archive so its iso/ and fr3/ contents land under
data/out/${GAME}/ next to the CGO/DGO here.

Layout after extraction:
  gk                                  the game binary
  data/out/${GAME}/iso/*.CGO,*.DGO    x86 compiled code (this release)
  data/out/${GAME}/iso/<data files>   <- from ${GAME}_assets.zip (iso/*)
  data/out/${GAME}/fr3/*.fr3          <- from ${GAME}_assets.zip (fr3/*)
  data/game/graphics/.../shaders/**   renderer shaders
  data/game/assets/**                 fonts, controller db, per-game assets

Running:
  1. Extract this tarball, then extract ${GAME}_assets.zip so its iso/ and fr3/
     entries land under data/out/${GAME}/ (merge into the existing iso/ dir).
  2. From the extracted root (where gk and data/ sit side by side):

        ./gk --game ${GAME}

     gk resolves its data relative to this data/ directory. If you keep the
     assets elsewhere, point gk at that tree explicitly:

        ./gk --game ${GAME} --proj-path <chosen>

     where <chosen> is the directory that CONTAINS the data/ folder (or the
     jak_N game root you extracted the assets into).
  3. On first boot, if prompted, point the game at your assets folder.
EOF

# --- pack (tar dereferences symlinks: -h) --------------------------------------
TAR_ABS="$ROOT/$OUT_DIR/${GAME}_binary_x86.tar.gz"
rm -f "$TAR_ABS"
echo "[release] packing → $OUT_DIR/${GAME}_binary_x86.tar.gz …"
nice tar -czhf "$TAR_ABS" -C "$STAGE" .

rm -rf "$STAGE"

TAR_BYTES=$(stat -c %s "$TAR_ABS")
echo "[release] done: $TAR_ABS ($TAR_BYTES bytes)"
echo "RELEASE $TAR_ABS $TAR_BYTES gk=$GK code=${#CODE_FILES[@]}"
