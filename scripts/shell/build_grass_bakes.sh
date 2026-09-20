#!/usr/bin/env bash
# build_grass_bakes.sh — Ggrass-density-presets (owner 2026-08-30) : CUIT LES CINQ PALIERS.
#
# « on devrait avoir des pre-calculs pour plusieurs densites alors, et en faire des valeurs
#   choisissables [...] donc on peut pre-calculer le tout et eviter le chemin lourd »
#
# POURQUOI CE SCRIPT EXISTE. Jusqu'a ce lot, AUCUN script du depot ne lancait `grass_bake` : les
# `.grassbake` livres avaient ete cuits a la main en session. Un artefact de livraison sans
# producteur automatise finit toujours par diverger de la source dont il derive — et ici la
# divergence a un cout mesure : un bake dont `fr3_size` ne correspond plus au `.fr3` livre est
# REFUSE par le moteur, qui basculait alors sur le placement EN DIRECT (1 207 Mo de pointe contre
# 735, et la population ou les plantages appareil ont ete reproduits).
#
# CE QU'IL GARANTIT :
#   * la liste des niveaux vient de `kGrassLevels` dans background_common.h — pas d'une copie ;
#   * la liste des paliers vient de `grass_density_presets.h` — pas d'une copie ;
#   * chaque bake est cuit contre le `.fr3` DE `out/jak1/fr3/`, c'est-a-dire exactement le fichier
#     que `android/build_custom_pack.sh` met dans le pack (il y pose un lien symbolique) ;
#   * les bakes SANS palier dans leur nom, et ceux des niveaux qui ne sont plus dans la liste, sont
#     retires : le moteur ne les resout plus, les laisser ne ferait qu'alourdir le pack ;
#   * chaque sortie est relue par `grassbake_header.py` et comparee au fr3 — echec dur sinon ;
#   * grass-bake-invalidation : une paire (niveau, palier) n'est RECUITE que si son CONTENU (ou la
#     recette de cuisson) a change depuis la derniere fois — `--only-stale` ne cuit que celles-la,
#     par defaut toutes les paires sont examinees puis recuites comme avant.
#
# Usage : scripts/shell/build_grass_bakes.sh [--fr3-dir DIR] [--tool PATH] [--keep-stale] [--only-stale]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
ROOT="$PWD"
FR3_DIR="$ROOT/out/jak1/fr3"
TOOL=""
KEEP_STALE=0
ONLY_STALE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fr3-dir) FR3_DIR="$2"; shift 2;;
    --tool)    TOOL="$2"; shift 2;;
    --keep-stale) KEEP_STALE=1; shift;;
    --only-stale) ONLY_STALE=1; shift;;
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    *) echo "argument inconnu : $1" >&2; exit 2;;
  esac
done

fail(){ echo "[grass-bakes] ECHEC: $*" >&2; exit 1; }

# --- le producteur ---
if [ -z "$TOOL" ]; then
  for c in "$ROOT/build/tools/grass_bake/grass_bake" "$ROOT/build-x86/tools/grass_bake/grass_bake"; do
    [ -x "$c" ] && { TOOL="$c"; break; }
  done
fi
[ -n "$TOOL" ] && [ -x "$TOOL" ] || fail "outil grass_bake introuvable — construis-le : .autoport/lib/build_x86.sh --target grass_bake"
[ -d "$FR3_DIR" ] || fail "repertoire fr3 absent : $FR3_DIR"

# --- LES NIVEAUX : lus dans le moteur, jamais recopies ---
HDR="$ROOT/game/graphics/opengl_renderer/background/background_common.h"
LEVELS=$(grep -oP 'kGrassLevels\[\]\s*=\s*\{\K[^}]*' "$HDR" | tr -d '" ' | tr ',' '\n' | sed '/^$/d')
[ -n "$LEVELS" ] || fail "kGrassLevels illisible dans $HDR"

# --- LES PALIERS : lus dans la table partagee, jamais recopies ---
PHDR="$ROOT/game/graphics/grass_density_presets.h"
SLUGS=$(grep -oP '^\s*\{"\K[a-z-]+(?=", ")' "$PHDR")
[ -n "$SLUGS" ] || fail "table des paliers illisible dans $PHDR"

# --- L'EMPREINTE DE LA RECETTE : les sources qui DÉCIDENT du contenu d'un bake. Un bake reste à
# recuire quand le CODE de cuisson change, pas seulement quand la donnée change (« et des tables
# qui en dépendent », contrat de l'item). La liste est ici et nulle part ailleurs.
RECIPE_SRC=(game/graphics/opengl_renderer/GrassBakeCore.cpp
            game/graphics/opengl_renderer/GrassBakeCore.h
            game/graphics/grass_density_presets.h
            game/graphics/grass_blade_variants.h
            tools/grass_bake/main.cpp)
for f in "${RECIPE_SRC[@]}"; do [ -f "$ROOT/$f" ] || fail "source de recette absente : $f"; done
RECIPE_FP=$(cat "${RECIPE_SRC[@]/#/$ROOT/}" | sha256sum | cut -c1-16)
echo "[grass-bakes] recette : $RECIPE_FP"

echo "[grass-bakes] outil   : $TOOL"
echo "[grass-bakes] fr3     : $FR3_DIR"
echo "[grass-bakes] niveaux : $(echo $LEVELS | tr '\n' ' ')"
echo "[grass-bakes] paliers : $(echo $SLUGS | tr '\n' ' ')"

# --- retrait des bakes que le moteur ne resout plus ---
if [ "$KEEP_STALE" = 0 ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base="$(basename "$f")"
    keep=0
    for lv in $LEVELS; do
      for sg in $SLUGS; do
        [ "$base" = "$lv.$sg.grassbake" ] && keep=1
      done
    done
    if [ "$keep" = 0 ]; then
      echo "[grass-bakes] retire (plus resolu par le moteur) : $base"
      rm -f "$f" "$f.fp"
    fi
  done < <(find "$FR3_DIR" -maxdepth 1 -type f -name '*.grassbake' | sort)
  # .fp orphelins : provenance sans son bake (bake deja retire par ailleurs, ou renomme).
  while IFS= read -r fpf; do
    [ -n "$fpf" ] || continue
    gb="${fpf%.fp}"
    if [ ! -f "$gb" ]; then
      echo "[grass-bakes] retire (provenance orpheline) : $(basename "$fpf")"
      rm -f "$fpf"
    fi
  done < <(find "$FR3_DIR" -maxdepth 1 -type f -name '*.grassbake.fp' | sort)
fi

# --- passage de DIAGNOSTIC : decide, paire par paire, la cause de peremption ---
declare -A CAUSE_OF
N_PAIRS=0
N_STALE=0
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
for lv in $LEVELS; do
  FR3="$FR3_DIR/$lv.fr3"
  [ -f "$FR3" ] || fail "fr3 absent pour le niveau '$lv' : $FR3"
  for sg in $SLUGS; do
    OUT="$FR3_DIR/$lv.$sg.grassbake"
    N_PAIRS=$((N_PAIRS + 1))
    CAUSE=""
    if [ ! -f "$OUT" ]; then
      CAUSE="absent"
    else
      "$TOOL" "$lv" --fr3-dir "$FR3_DIR" --preset "$sg" --freshness "$OUT" > "$tmp" \
        || fail "verdict de fraicheur illisible pour $lv/$sg"
      fresh_stale=$(sed -n 's/^freshness_stale=//p' "$tmp")
      fresh_reason=$(sed -n 's/^freshness_reason=//p' "$tmp")
      if [ "$fresh_stale" = "1" ]; then
        CAUSE="${fresh_reason%%:*}"
        [ -n "$CAUSE" ] || CAUSE="freshness"
      else
        recipe_read=$(sed -n 's/^recipe_fp=//p' "$OUT.fp" 2>/dev/null | head -1)
        if [ -z "$recipe_read" ] || [ "$recipe_read" != "$RECIPE_FP" ]; then
          CAUSE="recette"
        else
          CAUSE="-"
        fi
      fi
    fi
    key="$lv/$sg"
    CAUSE_OF["$key"]="$CAUSE"
    if [ "$CAUSE" = "-" ]; then
      P=0
    else
      P=1
      N_STALE=$((N_STALE + 1))
    fi
    echo "[grass-bakes] etat niveau=$lv palier=$sg perime=$P cause=$CAUSE"
  done
done

n_ok=0
N_BAKED=0
for lv in $LEVELS; do
  FR3="$FR3_DIR/$lv.fr3"
  FR3_SIZE=$(stat -c %s "$FR3")
  for sg in $SLUGS; do
    OUT="$FR3_DIR/$lv.$sg.grassbake"
    key="$lv/$sg"
    CAUSE="${CAUSE_OF[$key]}"
    if [ "$ONLY_STALE" = 1 ] && [ "$CAUSE" = "-" ]; then
      n_ok=$((n_ok + 1))
      continue
    fi
    echo "[grass-bakes] recuit niveau=$lv palier=$sg cause=$CAUSE"
    echo "[grass-bakes] cuisson $lv / $sg (fr3 $FR3_SIZE octets)"
    "$TOOL" "$lv" --fr3-dir "$FR3_DIR" --preset "$sg" --recipe-fp "$RECIPE_FP" >/dev/null \
      || fail "grass_bake a echoue pour $lv/$sg"
    [ -f "$OUT" ] || fail "sortie attendue absente : $OUT"
    # RELECTURE INDEPENDANTE : on ne croit pas l'outil sur parole, on relit le fichier ecrit.
    HDRLINE=$(python3 "$ROOT/scripts/shell/grassbake_header.py" "$OUT") || fail "en-tete illisible : $OUT"
    got_lv=$(sed -n 's/.* niveau=\([^ ]*\).*/\1/p' <<< "$HDRLINE")
    got_sz=$(sed -n 's/.* fr3_size=\([0-9]*\).*/\1/p' <<< "$HDRLINE")
    [ "$got_lv" = "$lv" ] || fail "$OUT : niveau '$got_lv' != '$lv'"
    [ "$got_sz" = "$FR3_SIZE" ] || fail "$OUT : fr3_size $got_sz != $FR3_SIZE — le bake serait REFUSE a l'arrivee"
    echo "  $HDRLINE"
    [ -s "$OUT.fp" ] || fail "provenance absente apres cuisson : $OUT.fp"
    "$TOOL" "$lv" --fr3-dir "$FR3_DIR" --preset "$sg" --freshness "$OUT" > "$tmp" \
      || fail "verdict de fraicheur illisible (post-cuisson) pour $lv/$sg"
    post_stale=$(sed -n 's/^freshness_stale=//p' "$tmp")
    [ "$post_stale" = "0" ] || fail "$OUT : le bake sort perime de sa propre cuisson"
    n_ok=$((n_ok + 1))
    N_BAKED=$((N_BAKED + 1))
  done
done
echo "[grass-bakes] $n_ok bake(s) cuits et verifies dans $FR3_DIR"
echo "[grass-bakes] paires_examinees=$N_PAIRS paires_perimees=$N_STALE paires_recuites=$N_BAKED"
