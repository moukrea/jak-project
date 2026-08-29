#!/usr/bin/env bash
# Dump every game texture to extracted_textures/<game>/<tpage>/<texture>.png.
#
# This is the decompiler's own texture unpacker, with everything else switched
# off.  In particular levels_extract is forced off: it writes out/<game>/fr3,
# which is what a running gk reads, and rebuilding those is not something a
# texture dump should do behind your back.
#
#   tools/texture_seamless/extract_textures.sh [jak1|jak2|jak3] [decompiler-binary]
set -euo pipefail

GAME="${1:-jak1}"
DECOMP="${2:-}"
cd "$(dirname "$0")/../.."

if [[ -z "$DECOMP" ]]; then
  for c in build/decompiler/decompiler build-x86/decompiler/decompiler; do
    [[ -x "$c" ]] && DECOMP="$c" && break
  done
fi
[[ -x "${DECOMP:-}" ]] || { echo "no decompiler binary; build the 'decompiler' target first" >&2; exit 1; }
[[ -d "iso_data/$GAME" ]] || { echo "iso_data/$GAME missing; extract the ISO first" >&2; exit 1; }

TMP=".texdump_tmp"
rm -rf "$TMP"
"$DECOMP" "./decompiler/config/$GAME/${GAME}_config.jsonc" ./iso_data "./$TMP" --disable-ansi \
  --config-override '{
    "save_texture_pngs": true, "process_tpages": true,
    "levels_extract": false, "extract_collision": false, "dump_objs": false,
    "process_game_text": false, "process_game_count": false,
    "process_part_group_table": false, "generate_symbol_definition_map": false,
    "rip_streamed_audio": false
  }'

mkdir -p extracted_textures
rm -rf "extracted_textures/$GAME"
mv "$TMP/$GAME/textures" "extracted_textures/$GAME"
rm -rf "$TMP"
echo "extracted_textures/$GAME: $(find "extracted_textures/$GAME" -name "*.png" | wc -l) textures in $(find "extracted_textures/$GAME" -mindepth 1 -maxdepth 1 -type d | wc -l) tpages"
