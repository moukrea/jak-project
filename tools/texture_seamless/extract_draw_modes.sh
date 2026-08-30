#!/usr/bin/env bash
# Dump, for every draw in every level, the texture it binds and the GS wrap
# settings + UV range it binds it with.  clamp = 0 on an axis is the game
# declaring that it repeats that texture on that axis: ground truth for
# "is this texture meant to repeat", which no image statistic can supply.
#
# Level extraction writes out/<game>/fr3, which is what a running gk reads.  So
# it runs against a SHADOW project directory: a tree of symlinks to this repo
# with its own out/, found by dropping a `data` directory next to a copy of the
# binary (file_util::try_get_data_dir).  The real out/<game>/fr3 is never opened.
#
#   tools/texture_seamless/extract_draw_modes.sh [jak1|jak2|jak3]
set -euo pipefail

GAME="${1:-jak1}"
cd "$(dirname "$0")/../.."
REPO="$PWD"
SHADOW="$REPO/.texdump_shadow"
OUT="$REPO/extracted_textures/$GAME-draw-modes"

for c in build/decompiler/decompiler build-x86/decompiler/decompiler; do
  [[ -x "$c" ]] && DECOMP="$c" && break
done
[[ -x "${DECOMP:-}" ]] || { echo "no decompiler binary; build the 'decompiler' target first" >&2; exit 1; }

rm -rf "$SHADOW"
mkdir -p "$SHADOW/root/data" "$SHADOW/out" "$SHADOW/dcout"
for e in "$REPO"/*; do
  b="$(basename "$e")"
  [[ "$b" == out || "$b" == .texdump_shadow ]] && continue
  ln -s "$e" "$SHADOW/root/data/$b"
done
ln -s "$SHADOW/out" "$SHADOW/root/data/out"
ln -s "$SHADOW/dcout" "$SHADOW/root/data/dcout"
# a copy, not a symlink: get_current_executable_path() resolves /proc/self/exe,
# so a symlink would find the real build tree and with it the real out/
cp "$DECOMP" "$SHADOW/root/decompiler"

( cd "$SHADOW/root/data" && TIE_PROTO_NAMES=1 "$SHADOW/root/decompiler" \
    "./decompiler/config/$GAME/${GAME}_config.jsonc" ./iso_data ./dcout --disable-ansi \
    --config-override '{
      "levels_extract": true, "dump_draw_modes": true,
      "process_tpages": false, "save_texture_pngs": false,
      "extract_collision": false, "rip_levels": false, "dump_objs": false,
      "process_game_text": false, "process_game_count": false,
      "process_part_group_table": false, "generate_symbol_definition_map": false,
      "rip_streamed_audio": false
    }' ) | grep -E '\[draw-modes\]|finished'

mkdir -p "$OUT"
rm -f "$OUT"/*.csv
cp "$SHADOW/out/$GAME/fr3"/*-draw-modes.csv "$OUT/"
rm -rf "$SHADOW"
echo "$OUT: $(ls "$OUT"/*.csv | wc -l) levels, $(cat "$OUT"/*.csv | grep -cv '^level,') draws"
