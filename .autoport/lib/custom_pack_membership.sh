#!/usr/bin/env bash
# custom_pack_membership.sh — LA regle d'appartenance du pack d'assets RECHARGES, en un seul endroit.
#
# Sourcee par release_verify.sh (qui refuse un pack a membre hors-regle) ET executable seule :
#   custom_pack_membership.sh --check <F_HUD 0|1> <F_HDMODELS 0|1> <membre>...
# ecrit une ligne `refus <membre> : <raison>` par membre refuse, puis `refused=<n>`, et rend 0.
# lighting-flipped-faces-everywhere : le moteur en demande le verdict pour les compagnons
# <niveau>.meshweld qu'il vient de charger (terme « refus de release_verify » de sa porte), au lieu
# de recopier la regle et de diverger d'elle.

# custom_pack_member_ok <membre> <F_HUD> <F_HDMODELS> : rend 0 si le membre est permis, sinon
# ecrit la raison sur stdout et rend 1.
custom_pack_member_ok(){
  local m="$1" hud="${2:-0}" hd="${3:-0}"
  case "$m" in
    recharged_assets/*.png) [ "$hud" -eq 1 ] || { echo "contient $m mais recharged-hud est OFF"; return 1; };;
    fr3/enhanced/*.fr3)     [ "$hd" -eq 1 ] || { echo "contient $m mais hd-models est OFF"; return 1; };;
    fr3/*.grassbake)        ;;
    # la provenance du bake : sans elle le moteur refuse le bake et le niveau perd son herbe
    fr3/*.grassbake.fp)     ;;
    # le profil de biome de l'herbe : donnee source, pas derivee (voir game/assets/grass/biomes/)
    fr3/*.grassbiome)       ;;
    # les normales du decor orientees vers la face vue, corrigees UNE FOIS dans l'asset (owner 25/09 :
    # « pas de repli, l'asset est la ou pas la ») : derive, non flag-gate, comme le .grassbake
    fr3/*.meshweld)         ;;
    # physics: la definition des chaines voyage avec recharged_assets (non flag-gate,
    # comme les PNG du HUD cote livraison) -> accepte inconditionnellement.
    recharged_assets/physics_chains.txt) ;;
    *) echo "membre hors-règle: $m"; return 1;;
  esac
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  [ "${1:-}" = "--check" ] || { echo "usage: $0 --check <F_HUD> <F_HDMODELS> <membre>..." >&2; exit 2; }
  hud="${2:-0}"; hd="${3:-0}"; shift 3 || exit 2
  n=0
  for m in "$@"; do
    why=$(custom_pack_member_ok "$m" "$hud" "$hd") || { echo "refus $m : $why"; n=$((n + 1)); }
  done
  echo "refused=$n"
  exit 0
fi
