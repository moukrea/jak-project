#!/usr/bin/env bash
# acquis/flipped-faces.sh — LES FACES A L'ENVERS RESTENT CORRIGEES DANS L'ASSET, JAMAIS DANS LE RENDU.
#
# Owner 25/09 : « Pourquoi le moteur devrait porter le truc des flipped faces defects si c'est un
# truc qu'on fait sur les assets du jeu directement ? ». La correction vit dans les compagnons
# <niveau>.meshweld du pack RECHARGE ; aucun shader ne retourne plus la normale stockee.
#
# CE QU'ON GARDE, HORS LIGNE (aucune course du jeu) : le recensement
# `lib/census/lighting-flipped-faces-everywhere.sh` relit le pack livre avec
# `tools/mesh_audit --check-orient` et le texte des shaders. Defaut = triangle du decor a l'envers
# apres compagnon, niveau a decor sans compagnon ou compagnon refuse, retournement de normale
# d'asset dans un shader, compagnon refuse par la regle d'appartenance du pack.
#
# CE QU'ON NE GARDE PAS : le rendu des surfaces minces vues de dos (decision owner en attente).
#
# L'ANCIEN acquis (acquis-retired/flipped-faces.sh) jugeait le RENDU par l'instrumentation moteur
# `flip_census`, retiree du moteur avec cet item.
#
# Cache : empreinte du CONTENU (outil, pack, niveaux .fr3, shaders, recensement, surcharges) ; les
# surcharges FLIP_PACK / FLIP_SHADERS / FLIP_LEVEL servent aux controles de l'item.
ACQ_NAME=flipped-faces
. "$(dirname "$0")/_lib.sh"

CENSUS=.autoport/lib/census/lighting-flipped-faces-everywhere.sh
[ -f "$CENSUS" ] || acq_unprovable "$CENSUS absent"
bash .autoport/lib/build_x86.sh --target mesh_audit >/dev/null 2>&1 \
  || acq_unprovable "build_x86.sh --target mesh_audit a echoue"
BIN=build/tools/mesh_audit/mesh_audit
PACK="${FLIP_PACK:-android/app/src/jak1/assets-slim/bundle/jak1_custom.zip}"
SHADERS="${FLIP_SHADERS:-game/graphics/opengl_renderer/shaders}"
[ -x "$BIN" ] && [ -f "$PACK" ] && [ -d out/jak1/fr3 ] && [ -d "$SHADERS" ] \
  || acq_unprovable "outil, pack, niveaux ou shaders absents"

fp=$( { sha256sum "$BIN" "$PACK" "$CENSUS" .autoport/lib/census/flipped_faces_shader_scan.py
        find out/jak1/fr3 -maxdepth 1 -name '*.fr3' -print0 | xargs -0 -r -n 8 -P 8 sha256sum | LC_ALL=C sort -k2
        find "$SHADERS" -type f -print0 | xargs -0 -r sha256sum | sed 's#  .*/#  #' | LC_ALL=C sort -k2
        printf 'level=%s\n' "${FLIP_LEVEL:-}"; } | sha256sum | cut -c1-16)
mkdir -p "$ACQ_CACHE" || acq_unprovable "cache $ACQ_CACHE"
OUT="$ACQ_CACHE/flipfaces-offline.$fp.out"
if [ ! -s "$OUT" ]; then
  FLIP_PACK="$PACK" FLIP_SHADERS="$SHADERS" bash "$CENSUS" > "$OUT.tmp" 2> "$OUT.err" \
    || { rm -f "$OUT.tmp"; acq_unprovable "le recensement hors ligne a rendu une erreur : $(tail -1 "$OUT.err")"; }
  mv "$OUT.tmp" "$OUT"
fi
val(){ sed -n "s/^$1=//p" "$OUT" | tail -1; }
DEF=$(val flipped_asset_defects); REV=$(val flipped_asset_reversed); MISS=$(val flipped_asset_levels_missing)
REFU=$(val flipped_asset_levels_refused); SFL=$(val flipped_shader_flips); PREF=$(val flipped_pack_refused)
LEV=$(val flipped_asset_levels_checked); REVB=$(val flipped_asset_reversed_before)
[ -n "$DEF" ] && [ "${LEV:-0}" -gt 0 ] || acq_unprovable "recensement sans verdict ($OUT)"
RES="niveaux=$LEV reversed=$REV missing=$MISS refused=$REFU shader_flips=$SFL pack_refused=$PREF temoin_origine=$REVB cache=$fp"
[ "$DEF" = 0 ] || acq_broken "defauts=$DEF : $RES shaders=$(val flipped_shader_flip_list) niveaux_en_defaut=$(val flipped_asset_bad_levels)"
acq_ok "defauts=0 hors ligne : $RES"
