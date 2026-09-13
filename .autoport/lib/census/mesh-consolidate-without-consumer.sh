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
# LE MARQUEUR N'EST PAS DANS L'EXECUTABLE. `format_mesh_audit()` vit dans `libcommon.so`, que les
# trois outils lient DYNAMIQUEMENT : `strings` sur l'executable seul rend 0 sur un arbre ou les
# outils portent pourtant le changement (mesure du 13/09 : mesh_audit=0, libcommon.so=1). Un zero
# d'instrument se serait lu « les outils sont vieux ». On interroge donc l'executable ET chacun des
# objets partages QUE LE CHARGEUR LUI RESOUT, par `ldd` — pas une liste de noms ecrite a la main.
# `mesh_tools_objects_scanned` publie le denominateur : a zero, aucune des deux lignes au-dessus ne
# veut dire quoi que ce soit.
outils_presents=0
outils_marques=0
objets_lus=0
for t in build/tools/mesh_audit/mesh_audit build/tools/tess_audit/tess_audit \
         build/tools/tess_sign/tess_sign; do
  [ -x "$t" ] || continue
  outils_presents=$((outils_presents + 1))
  porte=0
  for o in "$t" $(ldd "$t" 2>/dev/null | sed -n 's/.*=> \(\/[^ ]*\) (0x.*/\1/p'); do
    [ -r "$o" ] || continue
    objets_lus=$((objets_lus + 1))
    # `grep -q` SORT DES LA PREMIERE OCCURRENCE et tue `strings` par SIGPIPE : sous `pipefail`,
    # le pipeline rend 141 et la condition est FAUSSE sur un objet qui PORTE le marqueur (mesure du
    # 13/09 : libcommon.so, 91 Mio, rc=141 avec -q, compte=1 avec -c). C'etait la moitie du zero.
    # On lit donc jusqu'au bout et on compte.
    n_occ=$(strings -a "$o" 2>/dev/null | grep -cF "$MARQUEUR" || true)
    if [ "${n_occ:-0}" -gt 0 ] 2>/dev/null; then
      porte=1
    fi
  done
  outils_marques=$((outils_marques + porte))
done
echo "mesh_tools_built=$outils_presents"
echo "mesh_tools_carrying_change=$outils_marques"
echo "mesh_tools_objects_scanned=$objets_lus"

# ---------------------------------------------------------------------------------------------
# 1 bis. LES DEUX GARDIENS HORS LIGNE DE L'INVARIANT TOURNENT ENCORE (livrable 3, deuxieme moitie).
#    `tess_audit` et `tess_sign` ne produisent AUCUN artefact livre : leur seule sortie est un
#    rapport. On les lance sur `intro` et on publie leur code de retour et l'empreinte de leur
#    rapport, HORODATAGES RETIRES. Ce que ca prouve : ils compilent, ils traversent la meme
#    consolidation et ils vont au bout. Ce que ca ne prouve PAS : l'egalite avec un rapport
#    d'AVANT — aucun binaire d'avant n'existe sur ce disque. C'est dit dans le rapport.
# ---------------------------------------------------------------------------------------------
FR3_INTRO="out/jak1/fr3/intro.fr3"
for paire in "tess_audit:build/tools/tess_audit/tess_audit:" \
             "tess_sign:build/tools/tess_sign/tess_sign:--summary-only"; do
  nom=${paire%%:*}; reste=${paire#*:}; exe=${reste%%:*}; opt=${reste#*:}
  if [ -x "$exe" ] && [ -s "$FR3_INTRO" ]; then
    RAP=$(mktemp "${TMPDIR:-/tmp}/mcwc-$nom.XXXXXX")
    # shellcheck disable=SC2086
    if timeout 900 "$exe" --fr3 "$FR3_INTRO" $opt --out "$RAP" > "$RAP.log" 2>&1; then rc=0; else rc=$?; fi
    echo "mesh_tool_${nom}_rc=$rc"
    echo "mesh_tool_${nom}_report_bytes=$(stat -c %s "$RAP" 2>/dev/null || echo 0)"
    echo "mesh_tool_${nom}_report_lines=$(wc -l < "$RAP" 2>/dev/null | tr -d ' ' || echo 0)"
    # Les horodatages et les durees varient d'une course a l'autre : les retirer, sinon l'empreinte
    # ne dit rien d'autre que « ce n'est pas la meme seconde ».
    emp=$(sed -E 's/[0-9]+\.[0-9]+ ?(ms|s)//g; s/[0-9]{2}:[0-9]{2}:[0-9]{2}//g' "$RAP" 2>/dev/null \
          | md5sum | cut -c1-16)
    echo "mesh_tool_${nom}_report_sha=${emp:--}"
    # ANTI-VACUITE : un rapport peut sortir en rc=0 sans avoir touche un seul sommet. On publie la
    # POPULATION que chaque outil a effectivement traversee, tiree de son propre rapport.
    case "$nom" in
      tess_audit)
        echo "mesh_tool_tess_audit_patches=$(sed -n 's/^patches (tris) *: *\([0-9]*\).*/\1/p' "$RAP" | head -1 | tr -d ' ')"
        echo "mesh_tool_tess_audit_verts=$(sed -n 's/^vertices *: *\([0-9]*\).*/\1/p' "$RAP" | head -1 | tr -d ' ')" ;;
      tess_sign)
        echo "mesh_tool_tess_sign_global_verts=$(sed -n 's/.*of \([0-9]*\) global vertices.*/\1/p' "$RAP" | head -1)"
        echo "mesh_tool_tess_sign_rayf_voted=$(sed -n 's/.*rayf_vs_vol.*voted=\([0-9]*\).*/\1/p' "$RAP" | head -1)" ;;
    esac
    rm -f "$RAP" "$RAP.log"
  else
    echo "mesh_tool_${nom}_rc=-1"
    echo "mesh_tool_${nom}_report_bytes=0"
    echo "mesh_tool_${nom}_report_lines=0"
    echo "mesh_tool_${nom}_report_sha=-"
  fi
done

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
  # LIVRABLE 4, SUR LES 26 ET PAS SUR UN SEUL. `notes/sidecars-avant.md5` est la liste des
  # empreintes des sidecars LIVRES relevee AVANT la re-cuisson (essai 2, 13/09 18:57). On compare
  # fichier par fichier et on publie le nombre de LIGNES COMPAREES : a zero, `mesh_sidecars_changed`
  # ne veut rien dire, et le rapport doit le dire au lieu de lire un zero comme « rien n'a bouge ».
  REF="$D/notes/sidecars-avant.md5"
  if [ -s "$REF" ]; then
    # L'ORDRE DE `sort` DEPEND DE LA LOCALE : `GAME.meshweld` se range avant `beach` en C et apres
    # en fr_FR.UTF-8. Une liste de reference triee sous une autre locale faisait rendre 3 a `diff`
    # sur 26 fichiers tous identiques. On trie les DEUX cotes ici, sous LC_ALL=C, pose en tete.
    MAINT=$(mktemp "${TMPDIR:-/tmp}/mcwc-now.XXXXXX")
    REFT=$(mktemp "${TMPDIR:-/tmp}/mcwc-ref.XXXXXX")
    ( cd out/jak1/fr3 && md5sum *.meshweld 2>/dev/null ) | sort -k2 > "$MAINT"
    sort -k2 "$REF" > "$REFT"
    echo "mesh_sidecars_compared=$(wc -l < "$REF" | tr -d ' ')"
    echo "mesh_sidecars_now_listed=$(wc -l < "$MAINT" | tr -d ' ')"
    echo "mesh_sidecars_changed=$(diff "$REFT" "$MAINT" 2>/dev/null | grep -c '^<' || true)"
    rm -f "$MAINT" "$REFT"
  else
    echo "mesh_sidecars_compared=0"
    echo "mesh_sidecars_now_listed=0"
    echo "mesh_sidecars_changed=-1"
  fi
else
  echo "mesh_delivered_sidecars=0"
  echo "mesh_delivered_sidecars_sha=-"
  echo "mesh_sidecars_compared=0"
  echo "mesh_sidecars_now_listed=0"
  echo "mesh_sidecars_changed=-1"
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
