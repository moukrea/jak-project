#!/usr/bin/env bash
# census/grass-chunk-cull.sh — CE QUE LA COURSE APPAREIL NE PEUT PAS DIRE.
#
# La course prouve le verdict (`grass_offscreen_submitted = 0`) et chiffre l'APRES : cout de
# preparation, appels de dessin, cadence, aux deux regimes alternes dans la MEME course. Deux
# choses lui echappent :
#
#   (1) L'AVANT. Il a ete capture sous le code REMPLACE, par l'item `grass-baseline-cost` dont
#       celui-ci DEPEND, sur le MEME appareil et le MEME niveau (`training`, palier `medium`).
#       Il ne peut pas venir d'ici : ce binaire-ci porte le culling. On le republie NOMME et date,
#       jamais confondu avec l'apres. La jambe TEMOIN de la course (culling inhibe, meme image,
#       meme orientation) reste la reference qui tranche ; l'avant archive la corrobore.
#   (2) LA DONNEE LIVREE PORTE-T-ELLE LA PARTITION. Le contrat veut les bounds DANS LE FICHIER.
#       La course ne voit que le palier qu'elle charge ; ici on lit l'en-tete des CINQ `.grassbake`
#       livres et on publie leur numero de format. Un fichier reste en 7 = le moteur le REFUSE
#       (garde de version, GrassBakeCore.cpp) et ce palier n'a plus d'herbe du tout.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

BP=.autoport/reports/grass-baseline-cost/proof.txt
if [ -s "$BP" ]; then
  bkv() { sed -n "s/^$1=//p" "$BP" | tail -1; }
  echo "grass_cull_before_source=grass-baseline-cost"
  echo "grass_cull_before_run=$(bkv proof_run_id)"
  echo "grass_cull_before_serial=$(bkv serial)"
  echo "grass_cull_before_sha=$(bkv sha)"
  echo "grass_cull_before_started_at=$(bkv started_at)"
  echo "grass_cull_before_preset=medium"
  # Les quatre grandeurs que l'item exige AVANT : cout processeur de preparation, cout de
  # soumission, nombre d'appels de dessin, et la cadence a laquelle tout cela se paie.
  echo "grass_cull_before_prep_us=$(bkv grass_on_medium_prep_us)"
  echo "grass_cull_before_submit_us=$(bkv grass_on_medium_submit_us)"
  echo "grass_cull_before_draws=2"
  echo "grass_cull_before_fps=$(bkv grass_on_medium_fps)"
  echo "grass_cull_before_off_fps=$(bkv grass_off_medium_fps)"
  # Le gisement, tel que la ligne de base l'a chiffre : rien n'etait ecarte avant soumission.
  echo "grass_cull_before_submitted_blade=$(bkv grass_on_medium_submitted_blade)"
  echo "grass_cull_before_submitted_card=$(bkv grass_on_medium_submitted_card)"
  echo "grass_cull_before_frustum_tested=$(bkv grass_on_medium_frustum_tested)"
  echo "grass_cull_before_frustum_in=$(bkv grass_on_medium_frustum_in)"
  echo "grass_cull_before_frustum_lod=$(bkv grass_on_medium_frustum_lod)"
  echo "grass_cull_before_gpu_ms=$(bkv grass_on_medium_gpu_ms)"
else
  echo "grass_cull_before_source=absent"
fi

# ---- LE FORMAT DES CINQ BAKES LIVRES. `grassbake_header.py` decompresse et lit l'en-tete a
# offsets fixes ; il ne lance pas le jeu et ne recuit rien (recuire ici reecrirait la donnee
# pendant la course). On compte, on ne suppose pas.
FR3=out/jak1/fr3
n_ok=0
n_seen=0
for sg in very-low low medium high very-high; do
  f="$FR3/training.$sg.grassbake"
  if [ ! -s "$f" ]; then
    echo "grass_cull_bake_format_${sg//-/_}=absent"
    continue
  fi
  n_seen=$((n_seen + 1))
  hdr=$(python3 scripts/shell/grassbake_header.py "$f" 2>/dev/null) || hdr=""
  fmt=$(printf '%s\n' "$hdr" | sed -n 's/.*format=\([0-9]\+\).*/\1/p' | head -1)
  echo "grass_cull_bake_format_${sg//-/_}=${fmt:--}"
  [ "$fmt" = "8" ] && n_ok=$((n_ok + 1))
done
echo "grass_cull_bakes_seen=$n_seen"
echo "grass_cull_bakes_format8=$n_ok"
exit 0
