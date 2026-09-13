#!/usr/bin/env bash
# lib/census/mesh-consolidate-without-consumer.sh — LES TROIS TEMOINS QUE LE MOTEUR NE PEUT PAS
# PRODUIRE.
#
# Le verdict de cet item — `mesh_consolidate_waste_ms_x100` — sort du MOTEUR, sur l'appareil.
# Trois des quatre livrables ne vivent pas dans une image et n'ont donc aucun chemin vers le
# moteur :
#
#   3. « les outils hors ligne gardent leur chemin » — ils COMPILENT et rendent le MEME resultat.
#   4. « aucun maillage livre ne change » — l'empreinte des sidecars produits est IDENTIQUE.
#   1. « le cout AVANT » — mesure par une course de preuve ANTERIEURE, sur le meme binaire, sous
#      le bit A/B `kMeshBitKeepUnconsumed` (65536), et archivee dans `notes/`.
#
# LA MESURE QUI REPOND AUX DEUX PREMIERS EST LA MEME : on REFAIT le bake d'un niveau avec l'outil
# hors ligne, dans un bac a sable, et on compare ses octets a ceux du sidecar LIVRE. Identique =>
# l'outil produit encore le meme resultat ET rien de ce que le jeu charge n'a bouge. Ce n'est pas
# un `diff` de code : c'est l'artefact.
#
# PAS UNE SEULE LECTURE D'HORODATAGE (harness-subsecond-freshness-is-blind). « L'outil a-t-il ete
# rebati avec le changement ? » se lit dans son CONTENU : `strings` y cherche le litteral que
# `format_mesh_audit()` emet. Une date dirait « plus recent que », jamais « porte ce code ».
#
# POLARITE. Un temoin qui ne peut pas etre produit ne publie PAS un zero rassurant : il publie
# l'etat qui le rend illisible (`*_present=0`), et le rapport doit le dire. Un zero de defaut et
# un zero d'absence ne se lisent jamais pareil.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
export LC_ALL=C

ID="${AUTOPORT_CENSUS_ID:-mesh-consolidate-without-consumer}"
D="${AUTOPORT_CENSUS_DIR:-.autoport/reports/$ID}"

# Le litteral que `format_mesh_audit()` emet depuis cet item. Un binaire d'outil qui ne le porte
# pas a ete bati AVANT le changement : sa reproduction du bake ne prouverait rien.
MARQUEUR="MCWC-unconsumed-2026-09-13"

# ---------------------------------------------------------------------------------------------
# 1. LES OUTILS HORS LIGNE : presents, et batis AVEC le changement.
# ---------------------------------------------------------------------------------------------
outils_presents=0
outils_marques=0
for t in build/tools/mesh_audit/mesh_audit build/tools/tess_audit/tess_audit \
         build/tools/tess_sign/tess_sign; do
  [ -x "$t" ] || continue
  outils_presents=$((outils_presents + 1))
  if strings -a "$t" 2>/dev/null | grep -qF "$MARQUEUR"; then
    outils_marques=$((outils_marques + 1))
  fi
done
echo "mesh_tools_built=$outils_presents"
echo "mesh_tools_carrying_change=$outils_marques"

# ---------------------------------------------------------------------------------------------
# 2. LE BAKE REPRODUIT, OCTET POUR OCTET (livrables 3 et 4, une seule mesure).
#    `intro` : 1,1 Mio de fr3, 219 Kio de sidecar, ~30 s de bake. Assez gros pour traverser tout
#    l'appareil de soudage, assez petit pour tenir dans un recensement.
# ---------------------------------------------------------------------------------------------
NIV=intro
OUTIL=build/tools/mesh_audit/mesh_audit
FR3="out/jak1/fr3/$NIV.fr3"
LIVRE="out/jak1/fr3/$NIV.meshweld"

# `out/` est HORS DE GIT : dans un arbre detache, ces entrees n'existent pas et le temoin est
# muet, pas vert (feedback_test_reading_a_gitignored_file_is_unfailable_outside_the_main_tree).
if [ -x "$OUTIL" ] && [ -s "$FR3" ] && [ -s "$LIVRE" ]; then
  echo "mesh_bake_inputs_present=1"
  BAC=$(mktemp -d "${TMPDIR:-/tmp}/mcwc-bake.XXXXXX") || BAC=""
  if [ -n "$BAC" ]; then
    trap 'rm -rf "$BAC"' EXIT
    cp "$FR3" "$BAC/" 2>/dev/null
    if timeout 600 "$OUTIL" --level "$NIV" --fr3-dir "$BAC" --bake \
         --out "$BAC/report.txt" --csv "$BAC/report.csv" > "$BAC/stdout.log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
    echo "mesh_bake_rc=$rc"
    md_livre=$(md5sum "$LIVRE" 2>/dev/null | cut -d' ' -f1)
    md_refait=$(md5sum "$BAC/$NIV.meshweld" 2>/dev/null | cut -d' ' -f1)
    echo "mesh_bake_md5_delivered=${md_livre:--}"
    echo "mesh_bake_md5_rebaked=${md_refait:--}"
    echo "mesh_bake_bytes_delivered=$(stat -c %s "$LIVRE" 2>/dev/null || echo 0)"
    echo "mesh_bake_bytes_rebaked=$(stat -c %s "$BAC/$NIV.meshweld" 2>/dev/null || echo 0)"
    if [ -n "$md_livre" ] && [ "$md_livre" = "$md_refait" ]; then
      echo "mesh_bake_identical=1"
    else
      echo "mesh_bake_identical=0"
    fi
  else
    echo "mesh_bake_rc=-2"
    echo "mesh_bake_identical=0"
  fi
else
  # Ni vert ni rouge : ILLISIBLE. Le rapport doit le dire.
  echo "mesh_bake_inputs_present=0"
  echo "mesh_bake_rc=-1"
  echo "mesh_bake_identical=0"
  echo "mesh_bake_md5_delivered=-"
  echo "mesh_bake_md5_rebaked=-"
fi

# ---------------------------------------------------------------------------------------------
# 3. LES SIDECARS LIVRES, RECENSES. Le jeu en charge 26 ; aucun ne doit avoir bouge. On publie
#    leur nombre et l'empreinte de l'ENSEMBLE, pour qu'une comparaison d'une course a l'autre soit
#    possible sans relire 26 fichiers.
# ---------------------------------------------------------------------------------------------
if [ -d out/jak1/fr3 ]; then
  n_sc=$(find out/jak1/fr3 -maxdepth 1 -name '*.meshweld' | wc -l | tr -d ' ')
  sha_sc=$(find out/jak1/fr3 -maxdepth 1 -name '*.meshweld' -print0 2>/dev/null \
           | sort -z | xargs -0 md5sum 2>/dev/null | md5sum | cut -c1-16)
  echo "mesh_delivered_sidecars=$n_sc"
  echo "mesh_delivered_sidecars_sha=${sha_sc:--}"
else
  echo "mesh_delivered_sidecars=0"
  echo "mesh_delivered_sidecars_sha=-"
fi

# ---------------------------------------------------------------------------------------------
# 4. LE COUT « AVANT », RELU D'UNE PREUVE MACHINE. On ne recopie pas un chiffre a la main : on lit
#    le `proof.txt` qu'une course ANTERIEURE de `lib/proof_run.sh` a ecrit sous le bit A/B, et on
#    republie AVEC son identite de course et l'empreinte du binaire qui l'a produit. Sans elles,
#    « 4200 » ne dirait pas de quel binaire il parle.
# ---------------------------------------------------------------------------------------------
AV="$D/notes/avant-proof.txt"
if [ -s "$AV" ]; then
  lire(){ sed -n "s/^$1=//p" "$AV" 2>/dev/null | tail -1; }
  echo "mesh_waste_before_present=1"
  echo "mesh_waste_before_ms_x100=$(lire mesh_consolidate_waste_ms_x100)"
  echo "mesh_waste_before_loads=$(lire mesh_consolidate_loads)"
  echo "mesh_waste_before_total_ms_x100=$(lire mesh_consolidate_total_ms_x100)"
  echo "mesh_waste_before_sha=$(lire sha)"
  echo "mesh_waste_before_run_id=$(lire proof_run_id)"
  echo "mesh_waste_before_source=$(lire source)"
  echo "mesh_waste_before_device=$(lire device_serial)"
else
  echo "mesh_waste_before_present=0"
fi

exit 0
