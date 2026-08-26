#!/usr/bin/env bash
# gmam_fr3_determinism.sh — MESURER si la construction d'un niveau custom est reproductible.
#
# La question n'est pas « le fichier est-il correct » mais « deux constructions successives,
# a sources INCHANGEES, rendent-elles le MEME fichier ». Si non, la version du pack custom
# (md5 du contenu des membres) change a chaque build, et `deploy_verify` declare l'appareil
# perime alors que rien n'a bouge. C'est ce qui a fait echouer la gate de cloture au cycle 4.
#
# NATURE de la mesure : identite binaire (md5) d'un ARTEFACT DERIVE, pas une grandeur physique.
# REPERE : le fichier livre `out/jak1/fr3/test-zone.fr3`, celui-la meme qu'empaquette
#          android/build_custom_pack.sh.
# LIGNE DE BASE : avant correctif, N constructions rendaient N md5 distincts.
#
# Usage : gmam_fr3_determinism.sh [N]   (defaut 2). Sortie 0 = reproductible.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
N=${1:-2}
LVL=custom_assets/jak1/levels/test-zone/test-zone.jsonc
FR3=out/jak1/fr3/test-zone.fr3
HASHES=()
for i in $(seq 1 "$N"); do
  touch "$LVL"                       # seule variable touchee : la mtime, jamais le contenu
  timeout 900 ./build/goalc/goalc --user-auto --game jak1 --disable-ansi \
      -c '(make-group "iso")' > ".autoport/tmp/mi-det-$i.log" 2>&1 \
    || { echo "FAIL: goalc run $i"; tail -20 ".autoport/tmp/mi-det-$i.log"; exit 2; }
  h=$(md5sum "$FR3" | cut -d' ' -f1)
  HASHES+=("$h")
  echo "run $i : $h  ($(grep -oE 'Successfully built all [0-9]+ targets in [0-9.]+s' ".autoport/tmp/mi-det-$i.log" | head -1))"
done
u=$(printf '%s\n' "${HASHES[@]}" | sort -u | wc -l)
if [ "$u" -eq 1 ]; then
  echo "REPRODUCTIBLE : $N constructions, 1 seul md5 (${HASHES[0]})"
  exit 0
fi
echo "NON REPRODUCTIBLE : $N constructions, $u md5 distincts"
exit 1
