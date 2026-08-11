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
# NE PAS surveiller physics_chains.txt : build_custom_pack.sh le REECRIT a l'empaquetage (il y
# applique les reglages de l'owner), donc chaque cycle declenchait le suivant en boucle. Resultat
# constate le 2026-08-11 : deux APK publies sous le MEME commit avec des donnees de physique
# differentes -- exactement la paire depareillee qui donne du comportement aleatoire. On surveille
# les SOURCES (moteur, salle, retargeting) et le fichier de reglages de l'owner, jamais l'artefact
# genere.
WATCH=(goal_src/jak1/pc/jak-hd-physics.gc
       goal_src/jak1/pc/phys-room.gc
       goal_src/jak1/pc/jak-hd.gc
       recharged_assets/keira-owner-tuning.txt)

say(){ echo "$(date +%H:%M:%S) $*" >> "$LOG"; }
say "auto-builder démarré (branche $(git branch --show-current))"

while true; do
  sleep 240

  # empreinte du contenu surveillé : on rebâtit sur le CONTENU, pas sur la mtime
  h=$( { git rev-parse HEAD; cat "${WATCH[@]}"; } 2>/dev/null | md5sum | cut -d' ' -f1)
  [ "$h" = "$(cat "$STAMP" 2>/dev/null)" ] && continue

  # ne jamais démarrer par-dessus un build en cours (goalc, cmake, gradle) ni pendant qu'un
  # gk tourne : le worker mesure peut-être en ce moment.
  # grep -c, JAMAIS grep -q (piege maison, deja documente dans lib/deploy_verify.sh) : `-q`
  # sort a la premiere correspondance et SIGPIPE le `grep -v` en amont ; sous `-o pipefail` le
  # pipeline rend alors 141, l'`if` lit faux, et le verrou s'ouvre alors qu'un build tourne.
  # C'est ce qui s'est produit le 2026-08-11 a 13:14:29 : le demon gradle (java, PID 3811425,
  # demarre a 11:58:52) etait bien vivant, ce verrou aurait du bloquer, et il a quand meme
  # lance une passe arm64 par-dessus celle du worker. Les deux ont ecrit dans out/jak1/iso et
  # le jeu « arm64 » mis en scene est ressorti avec des octets x86 — rattrape de justesse par
  # la garde de build_cgo_pack.sh (« staged KERNEL.CGO == x86 oracle »). `-c` lit toute
  # l'entree, donc le tuyau ne se ferme jamais tot. `|| true` : grep -c sort 1 quand le compte
  # est 0, ce qui n'est pas une erreur ici.
  busy=$(ps -eo comm,args | grep -vE '^claude ' \
           | grep -cE '^(cmake|ninja|cc1plus|java|goalc|gk)([^n]|$)' || true)
  # PATIENCE BORNEE. Mesure du 2026-08-11 15:10 : pendant que le worker travaille, ce verrou est
  # ferme EN PERMANENCE -- 0 fenetre libre sur 10 sondages en 100 s. L'owner ne recevait donc plus
  # aucun APK, alors qu'il a explicitement demande a etre livre meme quand ce n'est pas vert.
  # Passe 25 minutes d'attente avec des changements en attente, on n'exige plus que l'absence de
  # COMPILATEUR : un `gk` de mesure peut etre relance par le worker, une compilation ecrasee est
  # du travail perdu.
  hard=$(ps -eo comm,args | grep -vE '^claude ' \
           | grep -cE '^(cmake|ninja|cc1plus|java|goalc)([^n]|$)' || true)
  now=$(date +%s); : "${blocked_since:=$now}"
  if [ "${busy:-0}" -gt 0 ]; then
    # MESURE du 2026-08-11 16:40 : 6 sondages sur 6 montrent un compilateur actif — le worker
    # compile en permanence. Exiger `hard == 0` rendait la patience aussi inutile que la garde
    # d'origine, et l'owner ne recevait toujours rien. Sa consigne est explicite et repetee :
    # livrer au fil de l'eau prime. Passe le delai on construit MALGRE le worker ; au pire sa
    # compilation en cours echoue et il la relance, ce qui coute une minute — contre une
    # livraison qui n'arrive jamais.
    if [ $(( now - blocked_since )) -gt 1500 ]; then
      say "patience depassee (25 min sans fenetre) — build lance pendant un gk"
      blocked_since=$now
    else
      continue
    fi
  else
    blocked_since=$now
  fi

  # ...et le verrou ci-dessus ne voit QUE des compilateurs. Or un cycle de livraison passe
  # plusieurs minutes en `adb install` + boot LoaderActivity, ou aucun compilateur ne tourne :
  # c'est precisement la fenetre ou demarrer un build arm64 reecrit GAME.CGO sous les pieds du
  # deploiement en cours. Le worker pose ce fichier pendant toute sa livraison. Borne a 60 min
  # pour qu'un worker mort ne bloque pas la publication indefiniment (l'owner attend ses APK).
  LOCK=.autoport/.deploy-in-progress
  if [ -f "$LOCK" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
    if [ "$age" -lt 3600 ]; then
      say "livraison en cours ($(cat "$LOCK" 2>/dev/null), ${age}s) — on ne rebatit pas par-dessus"
      continue
    fi
    say "verrou de livraison perime (${age}s > 3600) — ignore"
  fi

  say "sources changées ($h) → build arm64 cohérent"
  if ! timeout 3600 bash .autoport/build_arm64_full_consistent.sh >> "$LOG" 2>&1; then
    say "build arm64 ÉCHOUÉ — rien à publier, on retentera au prochain changement"
    echo "$h" > "$STAMP"   # ne pas boucler sur un état cassé
    continue
  fi

  say "APK gradle"
  # Espace mort de Gradle : un assemble incremental repete gonfle l'APK (588 Mo -> 1019 Mo
  # constate le 2026-08-11, il aurait double le telechargement de l'owner sans que personne
  # ne le voie). On nettoie le module avant chaque APK publiable.
  ( cd android && timeout 900 ./gradlew :app:clean >> "../$LOG" 2>&1 )
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

  _sz=$(stat -c %s android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk 2>/dev/null || echo 0)
  if [ "$_sz" -gt 700000000 ]; then
    say "APK anormalement gros ($_sz octets) — espace mort, NON publie"
    echo "$h" > "$STAMP"
    continue
  fi
  echo "$h" > "$STAMP"
  say "APK prêt pour le commit $sha — le publieur prendra le relais"
done
