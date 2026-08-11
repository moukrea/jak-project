#!/usr/bin/env bash
# auto_build_apk.sh — produire un APK testable EN CONTINU, vert ou pas.
#
# Owner 2026-08-11 : « faudrait que, même si pas vert, quand un build existe tu le pousses
# automatiquement sur jak-builds avec les assets qui vont bien s'ils ont été changés, comme ça même
# si pour toi c'est pas vert, moi je peux quand même tester et te faire des feedbacks. »
#
# Le publieur (auto_push_builds.sh) n'a JAMAIS été conditionné au validateur : il pousse dès que
# l'APK change. Le vrai manque était en amont — le worker itère sur x86 et personne ne fabriquait
# d'APK, donc le publieur n'avait rien à publier. Ce script est la pièce manquante.
#
# Il surveille les sources qui changent le comportement in-game ; quand elles bougent et qu'aucun
# build n'est en cours, il refait un jeu arm64 COHÉRENT (28 CGO/DGO d'un seul jet) puis l'APK.
# La cohérence est la leçon du « full random » : un APK et un pack de données de commits différents
# donnent des paramètres lus dans les mauvais champs. Les deux portent donc le même commit, écrit
# dans un fichier livré avec eux.

set +e -o pipefail
cd "$(dirname "$0")/.." || exit 1
LOG=.autoport/logs/auto_build_apk.txt
STAMP=.autoport/.last_apk_build_sha
WATCH=(goal_src/jak1/pc/jak-hd-physics.gc
       goal_src/jak1/pc/phys-room.gc
       goal_src/jak1/pc/jak-hd.gc
       recharged_assets/physics_chains.txt)

say(){ echo "$(date +%H:%M:%S) $*" >> "$LOG"; }
say "auto-builder démarré (branche $(git branch --show-current))"

while true; do
  sleep 240

  # empreinte du contenu surveillé : on rebâtit sur le CONTENU, pas sur la mtime
  h=$(cat "${WATCH[@]}" 2>/dev/null | md5sum | cut -d' ' -f1)
  [ "$h" = "$(cat "$STAMP" 2>/dev/null)" ] && continue

  # ne jamais démarrer par-dessus un build en cours (goalc, cmake, gradle) ni pendant qu'un
  # gk tourne : le worker mesure peut-être en ce moment.
  if ps -eo comm,args | grep -vE '^claude ' \
       | grep -qE '^(cmake|ninja|cc1plus|java|goalc|gk)([^n]|$)'; then continue; fi

  say "sources changées ($h) → build arm64 cohérent"
  if ! timeout 3600 bash .autoport/build_arm64_full_consistent.sh >> "$LOG" 2>&1; then
    say "build arm64 ÉCHOUÉ — rien à publier, on retentera au prochain changement"
    echo "$h" > "$STAMP"   # ne pas boucler sur un état cassé
    continue
  fi

  say "APK gradle"
  if ! ( cd android && timeout 2400 ./gradlew assembleJak1Debug >> "../$LOG" 2>&1 ); then
    say "gradle ÉCHOUÉ"
    echo "$h" > "$STAMP"
    continue
  fi

  # la paire doit être traçable : même commit pour l'APK et pour le pack
  sha=$(git rev-parse --short HEAD)
  mkdir -p out/artifacts
  {
    echo "commit: $sha"
    echo "branche: $(git branch --show-current)"
    echo "date: $(date -Is)"
    echo "état: build intermédiaire, PAS validé — publié pour que l'owner puisse tester (consigne 2026-08-11)"
    [ -f .autoport/OWNER-VERIFY-QUEUE.md ] && sed -n '1,40p' .autoport/OWNER-VERIFY-QUEUE.md
  } > out/artifacts/BUILD-INFO.txt

  echo "$h" > "$STAMP"
  say "APK prêt pour le commit $sha — le publieur prendra le relais"
done
