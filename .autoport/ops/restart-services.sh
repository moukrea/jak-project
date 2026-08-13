#!/usr/bin/env bash
# Remet en route ce que j'ai arrêté le 2026-08-13 vers 15h pour rendre de la RAM au portage.
# Rien n'a été supprimé : seulement `docker stop`, les volumes et les données sont intacts.
# Usage : bash .autoport/ops/restart-services.sh
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
LIST=.autoport/ops/services-stopped.txt
POL=.autoport/ops/authentik-postgres.restartpolicy

[ -f "$LIST" ] || { echo "rien à remettre en route (liste absente)"; exit 0; }

# authentik-postgres avait sa politique de redémarrage désarmée pour sortir de sa boucle : on la rend
if [ -f "$POL" ]; then
  p=$(cat "$POL")
  [ -n "$p" ] && [ "$p" != "no" ] && docker update --restart="$p" authentik-postgres >/dev/null 2>&1 \
    && echo "politique de redémarrage rendue à authentik-postgres : $p"
fi

# les bases d'abord, les applis ensuite — sinon les applis démarrent sur une base absente
for c in authentik-postgres authentik-redis immich-postgres immich-redis; do
  grep -qx "$c" "$LIST" && docker start "$c" >/dev/null 2>&1 && echo "démarré: $c"
done
sleep 5
while read -r c; do
  case "$c" in authentik-postgres|authentik-redis|immich-postgres|immich-redis) continue;; esac
  docker start "$c" >/dev/null 2>&1 && echo "démarré: $c" || echo "ÉCHEC: $c"
done < "$LIST"

echo
docker ps --format '  {{.Names}}  {{.Status}}'
echo
echo "NOTE authentik-postgres : il bouclait depuis le 2026-06-29 sur"
echo "  PANIC: could not write file \"pg_control\": No space left on device"
echo "Le disque était plein ce jour-là ; il y a maintenant ~20 Go libres, donc il devrait repartir."
echo "Si ce n'est pas le cas, c'est une corruption à réparer, pas un manque de place."
