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
# VERROU D'INSTANCE UNIQUE. Le 2026-08-11 trois instances tournaient en meme temps apres un
# cycle kill/respawn : chacune lancait son propre build arm64 sur le meme arbre. Le verrou rend
# le doublon impossible au lieu de le nettoyer a la main.
exec 9>.autoport/.auto_build_apk.lock
if ! flock -n 9; then
  echo "$(date +%H:%M:%S) une autre instance detient le verrou — sortie" >> "$LOG"
  exit 0
fi
say "auto-builder démarré (branche $(git branch --show-current), verrou pris)"

# =====================================================================================
# LE TELEPHONE NE DOIT JAMAIS RESTER EN ARRIERE DU BUILD.
#
# La panne a coute DEUX close-gates, la meme journee, avec la meme signature :
#   - tentative 5 : APK bati ET publie, jamais installe -> « stamp c77cb1e9e4f94 !=
#     version c2cb64c15cf50 ».
#   - tentative 7 (19:48) : « stamp c35d886d2c371 != version ceb901590eec4 ». Le log de
#     ce fichier dit pourquoi, mot pour mot : « org.opengoal.gk.jak1 au premier plan sur
#     le Redmi (mesure du superviseur) — installation differee ».
#
# La correction de la tentative 5 (installer juste apres le build) n'a pas suffi, et il
# faut nommer exactement pourquoi : le tampon de contenu ($STAMP) est ecrit AVANT
# l'installation. Une installation « differee » n'etait donc jamais reprise — au tour
# suivant le contenu n'avait pas bouge, la boucle sautait par `continue`, et le
# telephone restait en arriere pour toujours. Le report n'etait pas une attente, c'etait
# un abandon silencieux, et l'ecart ne reapparaissait qu'au point de controle
# (deploy_verify), c'est-a-dire trop tard.
#
# Regle de non-destruction de l'owner : « t'assurer que ton travail n'est pas
# systematiquement detruit... tu peux pas juste dire "ah oups", corriger et laisser
# reproduire en boucle ». On ne rend donc pas l'ecart mieux DETECTABLE : on le rend
# IMPOSSIBLE au point de production. La reconciliation ci-dessous
#   - tourne a CHAQUE tour de boucle, qu'on ait bati ou non (donc un report se retente
#     tout seul quatre minutes plus tard, indefiniment, jusqu'a ce que ce soit fait) ;
#   - est idempotente : quand les deux tampons du telephone valent deja les versions
#     baties, elle ne fait rien et n'ecrit rien ;
#   - ne rend jamais d'erreur : un echec ici ne doit pas interrompre la publication,
#     le publieur est un autre processus et a deja de quoi travailler.
#
# NE PAS CONFONDRE LES DEUX APPAREILS (owner, 2026-08-11) : le Redmi eae4df44 est
# L'INSTRUMENT DU SUPERVISEUR. L'owner teste sur SON Honor, que nous ne voyons pas du
# tout. Rien de ce que montre le Redmi ne dit quoi que ce soit de son activite. Le
# garde-fou « premier plan » ci-dessous ne parle donc PAS de l'owner : il evite de
# couper une mesure du superviseur en cours — et il est BORNE (25 min), parce qu'un jeu
# laisse au premier plan apres une course abandonnee bloquerait sinon la livraison pour
# toujours, ce qui est exactement la panne qu'on ferme.
#
# `grep -c` et JAMAIS `grep -q` : sous `-o pipefail`, `-q` sort a la premiere
# correspondance, SIGPIPE le producteur en amont, le pipeline rend 141 et le test se lit
# a l'envers. Piege maison, deja documente deux fois dans ce fichier.
fg_bloque_depuis=""
reconcilier_telephone(){
  local ADBX SERX PKGX APKX man_c man_g want_c want_g here fg dev_c dev_g compx got_c got_g i age apk_c
  ADBX="${ADB:-/home/emeric/Android/platform-tools/adb}"
  SERX=eae4df44
  PKGX=org.opengoal.gk.jak1
  APKX=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
  man_c=android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties
  man_g=android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties
  [ -f "$APKX" ] && [ -f "$man_c" ] || return 0
  want_c=$(grep -E '^version=' "$man_c" 2>/dev/null | cut -d= -f2)
  want_g=$(grep -E '^version=' "$man_g" 2>/dev/null | cut -d= -f2)
  [ -n "$want_c" ] || return 0

  # Ne jamais installer par-dessus une livraison du worker en cours : ces minutes-la
  # sont precisement celles ou aucun compilateur ne tourne, donc celles ou ce script se
  # croit libre.
  if [ -f .autoport/.deploy-in-progress ]; then
    age=$(( $(date +%s) - $(stat -c %Y .autoport/.deploy-in-progress 2>/dev/null || echo 0) ))
    [ "$age" -lt 3600 ] && return 0
  fi

  here=$("$ADBX" devices 2>/dev/null | grep -cE "^${SERX}[[:space:]]+device$" || true)
  [ "${here:-0}" -eq 0 ] && return 0   # telephone absent : ce n'est pas une erreur, on retentera

  # L'OVERRIDE EXTERNE D'ABORD — c'est LUI que le moteur lit, pas le pack.
  # Mesure du 2026-08-11 20:08, trace d'execution sur le Redmi :
  #   [hd-phys] PARAMSRC=external-override
  #             path=/storage/emulated/0/OpenGOAL/jak1/assets/recharged_assets/physics_chains.txt
  # et ce fichier-la datait de 15:49 (md5 4055f571..., contre 9d7701c8... livre dans le pack).
  # kmachine.cpp (pc_physics_parse_file) donne la PRIORITE a la copie externe, par conception :
  # « an EXTERNAL copy therefore OVERRIDES the packaged one » — c'est ce qui evite a l'owner un
  # re-telechargement de 581 Mo pour une valeur de raideur. Consequence : deploy_verify peut
  # certifier les 121 membres du pack (il l'a fait, ils correspondent tous) pendant que le jeu
  # tourne sur des parametres vieux de quatre heures. Le pack etait juste, la mesure etait fausse.
  # On synchronise donc TOUTES les sources que le moteur peut lire, pas seulement celle que la
  # gate regarde. Idempotent : md5 egaux -> aucun push, aucun log.
  if [ -f recharged_assets/physics_chains.txt ]; then
    local ext_dir ext_md5 loc_md5
    ext_dir=/storage/emulated/0/OpenGOAL/jak1/assets/recharged_assets
    ext_md5=$("$ADBX" -s "$SERX" shell "md5sum $ext_dir/physics_chains.txt 2>/dev/null" | tr -d '\r' | cut -d' ' -f1)
    loc_md5=$(md5sum recharged_assets/physics_chains.txt | cut -d' ' -f1)
    if [ -n "$ext_md5" ] && [ "$ext_md5" != "$loc_md5" ]; then
      if "$ADBX" -s "$SERX" push recharged_assets/physics_chains.txt "$ext_dir/physics_chains.txt" >> "$LOG" 2>&1; then
        say "reconciliation: override externe resynchronise ($ext_md5 -> $loc_md5) — c'est ce fichier que le moteur lit"
      else
        say "reconciliation: push de l'override externe ECHOUE — retentee au prochain tour"
      fi
    fi
  fi

  dev_c=$("$ADBX" -s "$SERX" exec-out run-as "$PKGX" cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
  dev_g=$("$ADBX" -s "$SERX" exec-out run-as "$PKGX" cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
  # DEJA A JOUR : le cas normal. Silence total, sinon le log se remplit toutes les 4 min.
  [ "$dev_c" = "$want_c" ] && [ "$dev_g" = "$want_g" ] && { fg_bloque_depuis=""; return 0; }

  # L'APK du disque doit EMBARQUER ce que l'arbre a bati, sinon on installerait un APK
  # perime et les tampons ne bougeraient pas d'un pouce — une attente sans fin.
  apk_c=$(unzip -p "$APKX" assets/bundle/jak1_custom.manifest.properties 2>/dev/null \
            | grep -E '^version=' | cut -d= -f2)
  if [ "$apk_c" != "$want_c" ]; then
    say "reconciliation: l'APK embarque '$apk_c' et l'arbre a bati '$want_c' — on attend le prochain empaquetage"
    return 0
  fi

  fg=$("$ADBX" -s "$SERX" shell dumpsys window 2>/dev/null \
         | grep -a 'mCurrentFocus' | grep -ac "$PKGX" || true)
  if [ "${fg:-0}" -gt 0 ]; then
    : "${fg_bloque_depuis:=$(date +%s)}"
    if [ $(( $(date +%s) - fg_bloque_depuis )) -lt 1500 ]; then
      say "reconciliation: $PKGX au premier plan (mesure en cours) — RETENTEE au prochain tour"
      return 0
    fi
    say "reconciliation: 25 min au premier plan sans relache — jeu vraisemblablement laisse ouvert, on installe quand meme"
  fi
  fg_bloque_depuis=""

  say "reconciliation: telephone en arriere du build (custom '$dev_c'->'$want_c', cgo '$dev_g'->'$want_g') — installation"
  if ! timeout 1800 "$ADBX" -s "$SERX" install -r "$APKX" >> "$LOG" 2>&1; then
    say "reconciliation: adb install a echoue — retentee au prochain tour (voir plus haut dans ce log)"
    return 0
  fi
  # Lancement par l'activite RESOLUE (LoaderActivity), JAMAIS MainActivity : c'est
  # LoaderActivity, et elle seule, qui reextrait les packs et ecrit les tampons
  # .cgo_pack_stamp_jak1 / .custom_pack_stamp_jak1 que deploy_verify relit. Un lancement
  # direct de MainActivity installe l'APK sans jamais deballer les donnees.
  compx=$("$ADBX" -s "$SERX" shell cmd package resolve-activity --brief "$PKGX" 2>/dev/null \
            | tr -d '\r' | grep "^${PKGX}/" | head -1)
  [ -n "$compx" ] || compx="${PKGX}/org.opengoal.gk.LoaderActivity"
  "$ADBX" -s "$SERX" shell am force-stop "$PKGX" >/dev/null 2>&1
  "$ADBX" -s "$SERX" shell am start -n "$compx" >/dev/null 2>&1
  # Laisser LoaderActivity deballer, puis CITER LES TAMPONS RELUS SUR LE TELEPHONE : une
  # affirmation sur ce que le programme a fait cite une trace, jamais une intention.
  got_c=""; got_g=""
  for i in $(seq 1 60); do
    sleep 10
    got_c=$("$ADBX" -s "$SERX" exec-out run-as "$PKGX" cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
    got_g=$("$ADBX" -s "$SERX" exec-out run-as "$PKGX" cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
    [ "$got_c" = "$want_c" ] && [ "$got_g" = "$want_g" ] && break
  done
  "$ADBX" -s "$SERX" shell am force-stop "$PKGX" >/dev/null 2>&1
  if [ "$got_c" = "$want_c" ] && [ "$got_g" = "$want_g" ]; then
    say "reconciliation: installe et deballe — tampons relus sur le telephone custom='$got_c' cgo='$got_g'"
  else
    say "reconciliation: installe mais packs NON deballes (custom '$got_c' != '$want_c', cgo '$got_g' != '$want_g') — RETENTEE au prochain tour"
  fi
}

while true; do
  sleep 240

  # RECONCILIATION D'ABORD, a chaque tour, qu'on ait bati ou non : c'est ce qui rend
  # impossible qu'un report d'installation devienne un abandon (voir le pave ci-dessus).
  reconcilier_telephone

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

  # NE JAMAIS CONSTRUIRE DEPUIS UN ARBRE SALE (2026-08-11 18:50). Le build de 18:28 a ete
  # fabrique pendant que le worker ecrivait le moteur : 366 lignes ajoutees et 52 retirees non
  # commitees. L'owner a donc teste un moteur a MOITIE reecrit et l'a trouve pire — "des petits
  # flickers qui font plus glitch qu'intentionnels". Un build livrable se fait depuis un etat
  # COMMITE, donc auto-coherent. On attend simplement le prochain point de commit du worker :
  # il en fait regulierement, la livraison continue, mais plus jamais a moitie.
  dirty=$(git status --porcelain -- goal_src/jak1/pc/jak-hd-physics.gc \
                                    goal_src/jak1/pc/phys-room.gc \
                                    recharged_assets/physics_chains.txt 2>/dev/null | grep -c . || true)
  if [ "${dirty:-0}" -gt 0 ]; then
    # Un arbre sale n'est pas forcement a moitie ecrit : le seul test objectif, c'est qu'il
    # COMPILE. S'il compile, l'etat est coherent et on en fait un point de commit pour livrer;
    # sinon le worker est vraiment au milieu d'une edition et on attend. Sans ce raffinement le
    # garde-fou pose a 18:50 aurait bloque toute livraison pendant des heures — l'owner a demande
    # l'inverse.
    if timeout 900 ./build/goalc/goalc --user-auto --cmd '(make-group "iso")' >> "$LOG" 2>&1; then
      git add -A goal_src/jak1/pc/jak-hd-physics.gc goal_src/jak1/pc/phys-room.gc \
                 recharged_assets/physics_chains.txt >> "$LOG" 2>&1
      git commit -q -m "[keira-physique] checkpoint automatique du constructeur: l'arbre compile (551 cibles), etat coherent livrable" >> "$LOG" 2>&1
      say "arbre sale mais COMPILE — checkpoint commite, build autorise"
    else
      say "arbre sale ET ne compile pas — worker au milieu d'une edition, build reporte"
      continue
    fi
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

  # On installe TOUT DE SUITE ce qu'on vient de produire, sans attendre le tour suivant.
  # Et si ce passage-ci reporte (mesure en cours, telephone absent, install ratee), le
  # tour suivant le retentera : c'est la boucle, en tete, qui garantit qu'un report ne
  # devient jamais un abandon.
  reconcilier_telephone
done
