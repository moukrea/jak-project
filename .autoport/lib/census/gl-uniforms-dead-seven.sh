#!/usr/bin/env bash
# census/gl-uniforms-dead-seven.sh — LE TEMOIN « AVANT », ET RIEN D'AUTRE.
#
# La porte (`dead_uniform_pushes == 0`) est produite par le MOTEUR : `glu::census_frame`
# interroge le pilote programme par programme. Ce crochet ne la touche pas — il ne peut pas :
# proof_run.sh moissonne les deux sorties dans le meme journal et ce script ne publie que des
# cles en `_before`/`_at_commit`.
#
# POURQUOI IL EXISTE. Apres la correction, la population que l'on comptait est VIDE : un zero
# seul ne distingue pas « plus rien a retirer » de « on n'a jamais rien compte ». Le temoin
# AVANT doit donc voyager jusque dans le proof FINAL. Deux ancrages, aucun des deux lu a `HEAD:`
# (un temoin lu a HEAD s'accuse lui-meme des que le correctif est commite) :
#
#   1. La COURSE d'avant. `notes/avant-proof.txt` est un proof.txt produit par proof_run.sh sur
#      le binaire NON corrige. On en recopie les chiffres et le sha du binaire qui les a dits.
#   2. Le COMMIT temoin, fige ici par son empreinte : on compte, dans son contenu, les sites
#      de poussee des sept. Ce nombre ne bouge plus jamais.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
D="${AUTOPORT_CENSUS_DIR:?}"

# ---- 1. la course d'avant -------------------------------------------------------------------
A="$D/notes/avant-proof.txt"
if [ -s "$A" ]; then
  kv(){ sed -n "s/^$1=//p" "$A" | tail -1; }
  for k in dead_uniform_pushes dead_uniform_names uniform_pushes_total uniform_names_seen \
           uniform_programs_linked dead7_pushes; do
    v=$(kv "$k"); [ -n "$v" ] && echo "${k}_before=$v"
  done
  echo "dead_uniform_list_before=$(kv dead_uniform_list)"
  echo "avant_binary_sha=$(kv sha)"
  echo "avant_started_at=$(kv started_at)"
  echo "avant_frames=$(kv frames)"
else
  echo "avant_binary_sha=absent"
fi

# ---- 2. le commit temoin --------------------------------------------------------------------
# Fige : le dernier commit AVANT que cet item ne touche a quoi que ce soit.
WITNESS=a06fb3868e
SEVEN='u_pbr_sun_dir|u_pbr_sun_color|u_rt_ambient_key|u_rt_ambient_contrast|u_rt_shadow_mul|u_rt_tint_shadow|u_pbr_uv_tile'
n=0
for f in game/graphics/opengl_renderer/background/background_common.cpp \
         game/graphics/opengl_renderer/background/Tie3.cpp \
         game/graphics/opengl_renderer/background/TFragment.cpp \
         game/graphics/opengl_renderer/background/Shrub.cpp \
         game/graphics/opengl_renderer/PrePass.cpp; do
  c=$(git show "$WITNESS:$f" 2>/dev/null | grep -cE "(lgt_[0-9a-z]+|glu::loc)\([^,]+, *\"($SEVEN)\"" ) || c=0
  n=$((n + c))
done
echo "dead7_sites_at_commit=$n"
echo "dead7_witness_commit=$WITNESS"
exit 0
