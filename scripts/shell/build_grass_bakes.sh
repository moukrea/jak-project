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
#   * chaque sortie est relue par `grassbake_header.py` et comparee au fr3 — echec dur sinon.
#
# Usage : scripts/shell/build_grass_bakes.sh [--fr3-dir DIR] [--tool PATH] [--keep-stale]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
ROOT="$PWD"
FR3_DIR="$ROOT/out/jak1/fr3"
TOOL=""
KEEP_STALE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fr3-dir) FR3_DIR="$2"; shift 2;;
    --tool)    TOOL="$2"; shift 2;;
    --keep-stale) KEEP_STALE=1; shift;;
    -h|--help) sed -n '2,26p' "$0"; exit 0;;
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
[ -n "$TOOL" ] && [ -x "$TOOL" ] || fail "outil grass_bake introuvable — construis-le : cmake --build build --target grass_bake"
[ -d "$FR3_DIR" ] || fail "repertoire fr3 absent : $FR3_DIR"

# --- LES NIVEAUX : lus dans le moteur, jamais recopies ---
HDR="$ROOT/game/graphics/opengl_renderer/background/background_common.h"
LEVELS=$(grep -oP 'kGrassLevels\[\]\s*=\s*\{\K[^}]*' "$HDR" | tr -d '" ' | tr ',' '\n' | sed '/^$/d')
[ -n "$LEVELS" ] || fail "kGrassLevels illisible dans $HDR"

# --- LES PALIERS : lus dans la table partagee, jamais recopies ---
PHDR="$ROOT/game/graphics/grass_density_presets.h"
SLUGS=$(grep -oP '^\s*\{"\K[a-z-]+(?=", ")' "$PHDR")
[ -n "$SLUGS" ] || fail "table des paliers illisible dans $PHDR"

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
      rm -f "$f"
    fi
  done < <(find "$FR3_DIR" -maxdepth 1 -type f -name '*.grassbake' | sort)
fi

n_ok=0
for lv in $LEVELS; do
  FR3="$FR3_DIR/$lv.fr3"
  [ -f "$FR3" ] || fail "fr3 absent pour le niveau '$lv' : $FR3"
  FR3_SIZE=$(stat -c %s "$FR3")
  for sg in $SLUGS; do
    OUT="$FR3_DIR/$lv.$sg.grassbake"
    echo "[grass-bakes] cuisson $lv / $sg (fr3 $FR3_SIZE octets)"
    "$TOOL" "$lv" --fr3-dir "$FR3_DIR" --preset "$sg" >/dev/null \
      || fail "grass_bake a echoue pour $lv/$sg"
    [ -f "$OUT" ] || fail "sortie attendue absente : $OUT"
    # RELECTURE INDEPENDANTE : on ne croit pas l'outil sur parole, on relit le fichier ecrit.
    HDRLINE=$(python3 "$ROOT/scripts/shell/grassbake_header.py" "$OUT") || fail "en-tete illisible : $OUT"
    got_lv=$(sed -n 's/.* niveau=\([^ ]*\).*/\1/p' <<< "$HDRLINE")
    got_sz=$(sed -n 's/.* fr3_size=\([0-9]*\).*/\1/p' <<< "$HDRLINE")
    [ "$got_lv" = "$lv" ] || fail "$OUT : niveau '$got_lv' != '$lv'"
    [ "$got_sz" = "$FR3_SIZE" ] || fail "$OUT : fr3_size $got_sz != $FR3_SIZE — le bake serait REFUSE a l'arrivee"
    echo "  $HDRLINE"
    n_ok=$((n_ok + 1))
  done
done
echo "[grass-bakes] $n_ok bake(s) cuits et verifies dans $FR3_DIR"
