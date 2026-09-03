#!/usr/bin/env bash
# Gfont-urbanist — chaine complete et reproductible.
#   1. atlas Urbanist sur la grille du moteur (composite depuis GAME.fr3, non commite)
#   2. avances rebranchees dans font.gc
#   3. compositions d'accents minuscules dans font_db_jak1.cpp
#   4. conversion de casse (texte + sous-titres)
#   5. C++ incremental (goalc + gk : common/util/font a change) puis donnees
#   6. fumee x86 avec la PREUVE d'activation du remplacement de police
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
LOCK=.autoport/.deploy-in-progress
printf 'gfont_build pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

echo "== 1/6 atlas =="       ; python3 recharged_assets/font/gen_game_atlas.py   || exit 1
echo "== 2/6 avances =="     ; python3 recharged_assets/font/patch_font_tables.py || exit 1
echo "== 3/6 accents =="     ; python3 recharged_assets/font/gen_accent_table.py  || exit 1
echo "== 4/6 casse =="       ; python3 recharged_assets/font/gen_mixed_case.py    || exit 1
echo "== 5/6 goalc + gk =="
cmake --build build --target goalc -j"$(nproc)" 2>&1 | tail -5 || exit 1
cmake --build build --target gk    -j"$(nproc)" 2>&1 | tail -5 || exit 1
build/goalc/goalc --user-auto --game jak1 --disable-ansi -c '(make-group "iso")' 2>&1 | tail -3
echo "== 6/6 fumee x86 =="
timeout 200 build/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -iso-data out/jak1/iso -- -boot -debug-mem > /tmp/gfont_smoke.log 2>&1
echo "PREUVE D'ACTIVATION :"
grep -i "custom texture replacement" /tmp/gfont_smoke.log | grep -i gamefont
echo "link finish: logo x$(grep -c 'link finish: logo' /tmp/gfont_smoke.log)"
