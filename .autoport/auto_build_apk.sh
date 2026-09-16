#!/usr/bin/env bash
# --- GARDE SHIELD (owner 2026-08-26) : ce demon fait son travail normalement,
# mais il ne doit JAMAIS parler a la NVIDIA Shield. Elle s'etait reconnectee
# toute seule au serveur adb et l'owner a exige l'arret total :
#   « TU TOUCHES PLUS A LA SHIELD TANT QUE JE TE LE DIT PAS »
# On la sort du serveur adb a chaque tour, sans rien changer au reste.
SHIELD_ADDR="192.168.1.32:5555"   # Shield INTERDITE — adresse gardee UNIQUEMENT pour la deconnecter
shield_keep_out() {
  # INTERDICTION OWNER 2026-08-30 : « Interdit de toucher a la SHIELD a nouveau. »
  # Appelee a CHAQUE tour de boucle, plus seulement au demarrage : une reconnexion
  # faite par un tiers ne doit jamais laisser la Shield visible d'un tour a l'autre.
  "${ADB:-adb}" disconnect "$SHIELD_ADDR" >/dev/null 2>&1 || true
}
shield_keep_out



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

# ------------------------------------------------------------------------------------------------
# `/tmp` EST UN TMPFS A QUOTA PAR UTILISATEUR, ET IL A TUE LA LIVRAISON DEUX CYCLES DE SUITE.
# Mesure du 2026-08-13 00:46 : `quota -s` donne 6311M sur une limite de 6311M — SATURE. Toute
# ecriture y rend un fichier de 0 octet ou un EDQUOT, et `df` ment (il annonce 1,6 G libres :
# la limite est un quota utilisateur, pas le remplissage du tmpfs).
#   - cycle du 12 aout : `mktemp -d` du bake -> `hd_merc_swap stamp` annonce « STAMPED 24 prims »
#     avec rc=0 en ecrivant 0 octet, et le bake meurt trois etapes plus loin ;
#   - cycle du 13 aout 00:44 : `:app:packageJak1Debug` meurt sur
#     « java.io.IOException: Débordement du quota d'espace disque ». AUCUN APK produit, donc
#     AUCUN build pousse — le correctif PRIORITE 1 des cheveux, bake a 23:53, n'a jamais atteint
#     l'owner. La livraison au fil de l'eau etait rompue sans que rien ne le signale.
#
# La regle de l'owner (« quand une perte se repete, on la rend impossible au POINT DE PRODUCTION,
# pas detectable au point de controle ») s'applique : on ne retente pas, on retire la dependance.
#
# LES DEUX VARIABLES SONT NECESSAIRES, ET C'EST LE PIEGE. `TMPDIR` couvre `mktemp` et les outils
# POSIX (le bake, package_hd_assets.sh:76), mais la JVM lit `java.io.tmpdir`, dont le defaut est
# `/tmp` INDEPENDAMMENT de `TMPDIR` : poser `TMPDIR` seul aurait laisse gradle mourir exactement
# au meme endroit, en donnant l'impression que le correctif ne marche pas.
export TMPDIR=${TMPDIR:-/home/emeric/.autoport-tmp}
mkdir -p "$TMPDIR"
export GRADLE_OPTS="${GRADLE_OPTS:+$GRADLE_OPTS }-Djava.io.tmpdir=$TMPDIR"
# ------------------------------------------------------------------------------------------------

# PID FILE — le superviseur teste l'EXISTENCE du processus, jamais une correspondance de
# motif : `ps | grep motif` compte le grep lui-meme, piege tombe quatre fois en 24h et qui a
# fait tuer la chaine de livraison toute la nuit du 2026-08-11.
PIDFILE=".autoport/.auto_build_apk.pid"
# LE FICHIER PID N'EST ECRIT QU'APRES LA PRISE DU VERROU (2026-09-03). Ecrit ici, un DOUBLON
# lance par erreur ecrasait le pid de l'instance vivante, puis son `trap EXIT` EFFACAIT ce
# fichier en sortant — refuse par le verrou, il emportait donc l'identite du builder qui
# tournait vraiment. Constate en direct pendant la passe de verification : le verrou a bien
# refuse le doublon, et le fichier pid s'est retrouve vide alors qu'un builder tournait.
# Le trap est pose au meme endroit, pour que seul le detenteur puisse retirer son propre pid.
LOG=.autoport/logs/auto_build_apk.txt
STAMP=.autoport/.last_apk_build_sha
# DECLENCHEMENT (remis d'equerre 2026-09-03). Avant : l'empreinte incluait `git rev-parse HEAD`,
# donc CHAQUE commit WIP d'un essai rate lancait un build arm64 complet + `gradle clean`. Mesure
# de la revue : 454 builds, 672 lancements « pendant un gk », et l'ISO reecrite en ARM64 sous les
# pieds du `gk` x86 de l'essai suivant — un faux rouge, un nouveau WIP, un nouveau build. C'est la
# boucle d'auto-sabotage que l'owner decrit par « la moitie du temps gaspillee en builds ».
# Desormais on ne batit QUE sur une intention explicite :
#   - `.autoport/.build-request` : pose par le worker quand SON CODE EST FINAL (contenu libre) ;
#   - un commit dont le sujet n'est PAS un checkpoint WIP (donc un passage de porte, une
#     livraison, un correctif du superviseur).
# La liste WATCH de fichiers Keira a disparu avec le perimetre qu'elle servait.
REQ=".autoport/.build-request"
head_is_wip(){ git log -1 --format=%s 2>/dev/null | grep -qiE 'WIP checkpoint|checkpoint automatique|^\[[^]]*\] *WIP |validateur .CHOU|PAS une r.ussite'; }

# 2026-09-11 — PORTE DE CONTENU. Un commit qui ne touche que `.autoport/` (backlog, consignes,
# rapports) ne peut PAS changer une image a l'ecran : le batir et publier 641 Mo est du pur
# gaspillage. Mesure du 11/09 : 14 des 25 derniers builds venaient de tels commits, 13 etaient
# ceux du superviseur. On compare le DERNIER COMMIT BATI a HEAD — pas HEAD tout seul, sinon un
# commit superviseur pose juste apres un commit worker ferait sauter le build du worker.
# Sans repere (premiere course, repere efface), on BATIT : un build de trop est benin, un build
# manquant ferait tester une version qui n'existe pas.
COMMIT_STAMP=.autoport/.last_apk_build_commit
range_touches_game(){
  local base cur
  cur=$(git rev-parse HEAD 2>/dev/null) || return 0
  base=$(cat "$COMMIT_STAMP" 2>/dev/null) || return 0
  [ -n "$base" ] || return 0
  git cat-file -e "$base^{commit}" 2>/dev/null || return 0      # repere perime : on batit
  [ "$base" = "$cur" ] && return 1                               # rien de neuf
  git diff --name-only "$base" "$cur" -- . ':(exclude).autoport/**' 2>/dev/null | grep -q . 
}
mark_built(){
  printf '%s\n' "$1" > "$STAMP.tmp.$$" && mv -f "$STAMP.tmp.$$" "$STAMP" &&
    printf '%s\n' "$build_commit" > "$COMMIT_STAMP.tmp.$$" &&
    mv -f "$COMMIT_STAMP.tmp.$$" "$COMMIT_STAMP"
}

# >>> BUILDER-GUARD-BEGIN — tranche lue telle quelle par lib/builder_guard_selftest.sh.
# NE PAS SCINDER : le banc a deux bras extrait ce bloc du FICHIER et l'execute. S'il disparait,
# perd son indirection `builder_pid_list` ou son etranglement, le banc sort en 2 et le
# recensement de l'item rougit.
say(){ echo "$(date +%H:%M:%S) $*" >> "$LOG"; }

#
# SEPT HEURES SANS UN MOT, LE 16/09 (17:41 -> 00:40), et rien dans le journal pour le dire.
# La garde d'origine comptait `java` dans `busy` ET dans `hard` :
#     busy=$(ps -eo comm,args | grep -vE '^(claude|codex) ' \
#              | grep -cE '^(cmake|ninja|cc1plus|java|goalc|gk)([^n]|$)' || true)
# Un demon Gradle INACTIF — lance par le gradle d'une course de preuve appareil, et vivant trois
# heures par son `idleTimeout=10800000` — est un `java`. Il faisait donc `continue` SANS UN MOT,
# et comme il comptait aussi dans `hard`, la patience de 20 minutes ne s'appliquait JAMAIS
# (`hard > 0`). Deux commits livrables (herbe, ocean) ont attendu la nuit entiere.
#
# CE QUI SEPARE UN DEMON QUI DORT D'UN GRADLE QUI BATIT :
#   1. la LIGNE DE COMMANDE. Le client et les workers portent GradleWrapperMain / GradleMain /
#      GradleWorkerMain / gradle-wrapper.jar ; le demon porte GradleDaemon et rien de tout ca.
#      C'est un RELEVE, pas une supposition : lib/fixtures/gradle-cmdlines.tsv les a lus dans
#      /proc pendant un vrai `./gradlew help`. Meme litteral que lib/proof_run.sh::busy_reason
#      (item frere harness-busy-guard-matches-gradle-daemon, 14/09) — la copie VIVANTE etait ici.
#   2. le TRAVAIL REEL, quand la ligne de commande ne trahit rien : un demon qui compile brule du
#      CPU et fork des workers. On echantillonne utime+stime sur 10 s et on regarde ses enfants.
#      Zero des deux = il dort ; il ne compte alors NI dans busy NI dans hard.
# On ne TUE aucun demon (ce serait le travail d'un autre) : on cesse de le prendre pour un build.

BUILDER_REG=.autoport/logs/builder-ticks.tsv
BUILDER_REG_MAX=${BUILDER_REG_MAX:-20000}
BUILDER_SAY_THROTTLE=${BUILDER_SAY_THROTTLE:-1200}
# Le MEME litteral que lib/proof_run.sh::busy_reason. Deux copies divergeraient en silence ;
# lib/builder_guard_selftest.sh compare les deux et rougit si elles s'ecartent.
BUILDER_GRADLE_TRAVAIL='GradleWrapperMain|org\.gradle\.launcher\.GradleMain|GradleWorkerMain|gradle-wrapper\.jar'
BUILDER_CPU_FENETRE=${BUILDER_CPU_FENETRE:-10}      # secondes d'observation
BUILDER_CPU_TICKS_MIN=${BUILDER_CPU_TICKS_MIN:-25}  # 0,25 s de CPU en 10 s = 2,5 % d'un coeur
declare -A _builder_cause_vue

# L'INDIRECTION, ET C'EST LA SEULE PORTE DE CETTE GARDE VERS LE SYSTEME. Le banc la remplace pour
# n'exposer que SES processus ; tout le reste (comm, ligne de commande, CPU, enfants) reste lu
# dans le VRAI /proc, sur de VRAIS processus. Un banc qui simulerait aussi /proc ne mesurerait
# que son propre decor.
builder_pid_list(){ ls -1 /proc 2>/dev/null | grep -xE '[0-9]+'; }

builder_cpu_ticks(){ awk '{print $14+$15}' "/proc/$1/stat" 2>/dev/null; }

# Un demon qui BATIT fork des workers ; un demon qui dort n'a pas d'enfant. Si le noyau ne rend
# pas `children`, le compte est 0 et c'est le CPU qui tranche seul — l'etat est publie.
BUILDER_CHILDREN_LISIBLE=$([ -r "/proc/$$/task/$$/children" ] && echo 1 || echo 0)
builder_enfants_compilateurs(){          # $1 = pid parent
  local k c n=0
  for k in /proc/"$1"/task/*/children; do
    [ -r "$k" ] || continue
    for c in $(cat "$k" 2>/dev/null); do
      case "$(cat "/proc/$c/comm" 2>/dev/null)" in
        java|javac|kotlin*|cc1plus|cc1|clang*|d8|r8|aapt2|ld|as|ninja|cmake) n=$((n+1)) ;;
      esac
    done
  done
  printf '%s' "$n"
}

# Rend UNE ligne : "<busy> <hard> <demons-inactifs-ecartes> <pourquoi>". `hard` ne compte que les
# COMPILATEURS (c'est lui qui debloque la patience de 20 min) ; `busy` y ajoute un `gk` de mesure.
builder_busy_counts(){
  local pid comm cmd busy=0 hard=0 idle=0 pourquoi="" a b enf
  local cand=() ; local -A t0=()
  for pid in $(builder_pid_list); do
    comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
    [ -n "$comm" ] || continue
    case "$comm" in
      claude|codex) continue ;;
      cmake|ninja|cc1plus|cc1|goalc)
        busy=$((busy+1)); hard=$((hard+1)); pourquoi="${pourquoi:+$pourquoi,}$comm:$pid" ;;
      gk)
        busy=$((busy+1)); pourquoi="${pourquoi:+$pourquoi,}gk:$pid" ;;
      java)
        cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
        # `[[ =~ ]]` ET PAS `printf | grep -q` : sous `-o pipefail`, `grep -q` sort a la premiere
        # correspondance, SIGPIPE le `printf` en amont, et le pipeline rend 141 — donc FAUX sur
        # une ligne de commande qui PORTE le motif. Un vrai client Gradle serait alors range
        # parmi les candidats inactifs, c'est-a-dire l'inverse exact de ce qu'on repare.
        if [[ "$cmd" =~ $BUILDER_GRADLE_TRAVAIL ]]; then
          busy=$((busy+1)); hard=$((hard+1)); pourquoi="${pourquoi:+$pourquoi,}gradle-travail:$pid"
        else
          cand+=("$pid"); t0[$pid]=$(builder_cpu_ticks "$pid")
        fi ;;
    esac
  done
  # LE SEUL COUT DE LA MESURE, ET IL N'EST PAYE QUE S'IL Y A UN CANDIDAT : 10 s par tour de 240 s.
  if [ "${#cand[@]}" -gt 0 ]; then
    sleep "$BUILDER_CPU_FENETRE"
    for pid in "${cand[@]}"; do
      [ -d "/proc/$pid" ] || { pourquoi="${pourquoi:+$pourquoi,}java-disparu:$pid"; continue; }
      a=${t0[$pid]}; b=$(builder_cpu_ticks "$pid")
      if [ -z "$a" ] || [ -z "$b" ]; then
        # ILLISIBLE N'EST PAS INACTIF. On ne fabrique pas un vert avec une lecture ratee.
        busy=$((busy+1)); hard=$((hard+1)); pourquoi="${pourquoi:+$pourquoi,}java-illisible:$pid"; continue
      fi
      enf=$(builder_enfants_compilateurs "$pid")
      if [ $(( b - a )) -ge "$BUILDER_CPU_TICKS_MIN" ] || [ "$enf" -gt 0 ]; then
        busy=$((busy+1)); hard=$((hard+1))
        pourquoi="${pourquoi:+$pourquoi,}java-actif:$pid:cpu$((b-a)):enf$enf"
      else
        idle=$((idle+1))
        pourquoi="${pourquoi:+$pourquoi,}java-inactif-ecarte:$pid:cpu$((b-a)):enf$enf"
      fi
    done
  fi
  printf '%s %s %s %s\n' "$busy" "$hard" "$idle" "${pourquoi:--}"
}

# LE REGISTRE N'EST JAMAIS ETRANGLE — c'est LUI qui rend un tour muet impossible. Le journal
# lisible par un humain, lui, ne recoit qu'UNE ligne par cause et par 20 min : la consigne est
# « aucun tick muet », pas « noyer le journal ». Les deux sorties ont donc des regimes distincts,
# et c'est le registre que le recensement lit.
builder_tick_record(){                   # $1=cause  $2..=texte
  local c=$1; shift
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date +%s)" "$$" "$c" "${busy:--}" "${hard:--}" "${idle_daemons:--}" \
    "$(git rev-parse --short HEAD 2>/dev/null || echo -)" \
    "$(printf '%s' "${*:-}" | tr '\t\n' '  ')" >> "$BUILDER_REG" 2>/dev/null || true
  # Rotation bornee : un registre qui grossit sans fin finirait par couter plus cher que le
  # defaut qu'il surveille.
  local n
  n=$(wc -l < "$BUILDER_REG" 2>/dev/null || echo 0); n=${n// /}
  if [ "${n:-0}" -gt "$BUILDER_REG_MAX" ]; then
    tail -n $(( BUILDER_REG_MAX / 2 )) "$BUILDER_REG" > "$BUILDER_REG.tmp.$$" 2>/dev/null &&
      mv -f "$BUILDER_REG.tmp.$$" "$BUILDER_REG" 2>/dev/null || rm -f "$BUILDER_REG.tmp.$$"
  fi
}

# AUCUN `continue` DE LA BOUCLE SANS ELLE. lib/builder_mute_census.py le verifie sur le FICHIER
# et publie la liste des fautifs : la perte est rendue impossible au point de PRODUCTION, pas
# detectable au point de controle.
say_cause(){                             # $1=cause  $2..=texte
  local c=$1; shift
  builder_tick_record "$c" "$*"
  local now last
  now=$(date +%s); last=${_builder_cause_vue[$c]:-0}
  if [ $(( now - last )) -ge "$BUILDER_SAY_THROTTLE" ]; then
    _builder_cause_vue[$c]=$now
    say "$*"
  fi
}
# <<< BUILDER-GUARD-END

# L'INSTANTANE QUI A REMPLACE LE CHECKPOINT. `checkpoint_snapshot` enregistre un arbre sale sans
# commiter, sans toucher l'index ni l'arbre de travail du worker : voir l'en-tete de la librairie
# pour l'accident qu'elle rend impossible. Sourcee ici, avant la boucle, pour qu'une librairie
# absente se voie au demarrage et non au milieu d'une passe.
# shellcheck source=lib/checkpoint_snapshot.sh
. .autoport/lib/checkpoint_snapshot.sh || { echo "lib/checkpoint_snapshot.sh introuvable" >> "$LOG"; exit 1; }
# VERROU D'INSTANCE UNIQUE. Le 2026-08-11 trois instances tournaient en meme temps apres un
# cycle kill/respawn : chacune lancait son propre build arm64 sur le meme arbre. Le verrou rend
# le doublon impossible au lieu de le nettoyer a la main.
exec 9>.autoport/.auto_build_apk.lock
if ! flock -n 9; then
  echo "$(date +%H:%M:%S) une autre instance detient le verrou — sortie" >> "$LOG"
  exit 0
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT
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
# ------------------------------------------------------------------------------------------------
# UNE INSTALLATION EFFACE L'APP-OP QUI DONNE LA SURFACE — ET CA A COUTE UN ESSAI ENTIER.
# Mesure du 2026-09-11 (recharged-gating-real, essai 3), deux fois de suite sur eae4df44 :
#   05:17  lib/proof_run.sh pose MIUIOP(10020) (« afficher sur l'ecran verrouille ») : ignore -> allow
#   05:22  la course rend frames=6960, crash=0
#   05:25:54 et 05:31:50  CE script reinstalle l'APK
#   05:30 et 05:33:15  `appops get` rend « MIUIOP(10020): ignore ; rejectTime=+1m1s » — le systeme
#          a REFUSE la surface a notre paquet dans la minute qui suit l'installation.
# Entre les deux lectures, un `am start` a 05:31:00 avait rendu `A35-RENDER frame=1` : le binaire
# dessine. La porte de fermeture de l'essai 2, elle, a lance l'appli APRES l'installation de
# 05:25:54 et n'a jamais vu de rendu — verdict « the deployed build does not boot on device » sur
# un moteur qui venait de dessiner 6960 images, et un essai brule.
# Correctif au POINT DE PRODUCTION : celui qui installe repose l'app-op tout de suite, et le dit.
# Aussi appelee a chaque tour, pour rattraper un effacement venu d'ailleurs (l'owner qui installe
# un build de jak-builds efface le meme app-op). On ne touche QUE l'app-op de NOTRE paquet, jamais
# un reglage systeme de l'owner ; un echec n'interrompt rien.
appop_surface_verrouillee(){          # $1 = raison, journalisee
  local A S P avant apres
  A="${ADB:-/home/emeric/Android/platform-tools/adb}"; S=eae4df44; P=org.opengoal.gk.jak1
  avant=$(timeout 15 "$A" -s "$S" shell appops get "$P" 2>/dev/null \
            | tr -d '\r' | sed -n 's/^MIUIOP(10020): \([a-z]*\).*/\1/p' | head -1)
  [ -n "$avant" ] || return 0         # pas un MIUI, ou app-op absent : rien a faire, rien a dire
  [ "$avant" = allow ] && return 0    # deja pose : silence, sinon le journal se remplit
  timeout 15 "$A" -s "$S" shell appops set "$P" 10020 allow >/dev/null 2>&1
  apres=$(timeout 15 "$A" -s "$S" shell appops get "$P" 2>/dev/null \
            | tr -d '\r' | sed -n 's/^MIUIOP(10020): \([a-z]*\).*/\1/p' | head -1)
  say "reconciliation: app-op MIUI 10020 (surface sur ecran verrouille) $avant -> ${apres:-inconnu} — $1"
}

fg_bloque_depuis=""
reconcilier_telephone(){
  python3 .autoport/delivery_artifact.py check >/dev/null 2>&1 || return 0
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

  # 2026-09-11 — NI PAR-DESSUS UNE PREUVE EN COURS. Le verrou ci-dessus couvre les LIVRAISONS
  # du worker, pas ses COURSES DE MESURE. Signalement du worker lighting-legacy-purge, mesure
  # directe du 11/09 a 03:54:49 : ce reconciliateur a reinstalle l'APK pendant une course, le
  # process du jeu est passe de 12642 a 13021 et le chemin /data/app/ a change sous elle. La
  # course est sortie en frames=0 et se lisait comme une regression du moteur. Trois essais ont
  # ete brules sur des diagnostics de ce faux rouge.
  # Plafond d'age : une course figee ne doit pas bloquer les installations pour toujours.
  pr_age=0
  for pr in $(ps -eo pid= -o etimes= -o args= 2>/dev/null \
                | awk '/[p]roof_run\.sh/ {print $2}'); do
    [ "$pr" -gt "$pr_age" ] 2>/dev/null && pr_age=$pr
  done
  if [ "$pr_age" -gt 0 ] && [ "$pr_age" -lt 2400 ]; then
    say "reconciliation: une course de preuve tourne depuis ${pr_age}s — RETENTEE au prochain tour"
    return 0
  fi

  here=$("$ADBX" devices 2>/dev/null | grep -cE "^${SERX}[[:space:]]+device$" || true)
  [ "${here:-0}" -eq 0 ] && return 0   # telephone absent : ce n'est pas une erreur, on retentera

  # Le telephone est la : on s'assure que notre paquet peut obtenir une surface, meme ecran
  # verrouille ou face contre table. Silencieux quand c'est deja le cas.
  appop_surface_verrouillee "tour de reconciliation"

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
  # LE BINAIRE AUSSI, PAS SEULEMENT LES PACKS (2026-09-02 17:08). Un changement C++ seul
  # (Merc2.cpp, commit 7f69ed7579) laisse les DEUX tampons de pack identiques : le telephone
  # etait declare « deja a jour » avec le libgk.so de 16:16 pendant que l'APK de 16:59 attendait
  # sur le disque — et l'owner aurait eu, lui, le nouveau binaire par jak-builds. L'identite de
  # l'APK INSTALLE par ce script est memorisee (taille-mtime, .autoport/.redmi_installed_apk) ;
  # une identite differente vaut « telephone en arriere », comme un tampon de pack different.
  apk_id=$(stat -c '%s-%Y' "$APKX" 2>/dev/null)
  inst_id=$(cat .autoport/.redmi_installed_apk 2>/dev/null)
  # DEJA A JOUR : le cas normal. Silence total, sinon le log se remplit toutes les 4 min.
  [ "$dev_c" = "$want_c" ] && [ "$dev_g" = "$want_g" ] && [ "$apk_id" = "$inst_id" ] && { fg_bloque_depuis=""; return 0; }

  # L'APK du disque doit EMBARQUER ce que l'arbre a bati, sinon on installerait un APK
  # perime et les tampons ne bougeraient pas d'un pouce — une attente sans fin.
  apk_c=$(unzip -p "$APKX" assets/bundle/jak1_custom.manifest.properties 2>/dev/null \
            | grep -E '^version=' | cut -d= -f2)
  if [ "$apk_c" != "$want_c" ]; then
    say "reconciliation: l'APK embarque '$apk_c' et l'arbre a bati '$want_c' — on attend le prochain empaquetage"
    return 0
  fi

  # `mCurrentFocus` NE SUFFIT PAS, et c'est ce qui a laisse passer les deux installations de
  # 05:24:56 et 05:31:50 (2026-09-11) pendant qu'une mesure tournait : sur ce MIUI, la fenetre
  # `ScreenOnProximitySensorGuide` prend le focus des que le capteur de proximite est couvert
  # (telephone pose face contre table — sa position normale ici), et `mCurrentFocus` ne nomme
  # alors plus notre paquet. `mFocusedApp`, lui, le nommait toujours :
  #   mCurrentFocus=Window{ae01a0 u0 ScreenOnProximitySensorGuide}
  #   mFocusedApp=ActivityRecord{a04eeaa u0 org.opengoal.gk.jak1/org.opengoal.gk.MainActivity}
  # On lit les DEUX lignes : une seule qui nomme le paquet suffit a differer l'installation. La
  # borne de 25 min ci-dessous est inchangee, donc un jeu laisse ouvert ne bloque toujours rien.
  fg=$("$ADBX" -s "$SERX" shell dumpsys window 2>/dev/null \
         | grep -aE 'mCurrentFocus|mFocusedApp' | grep -ac "$PKGX" || true)
  if [ "${fg:-0}" -gt 0 ]; then
    : "${fg_bloque_depuis:=$(date +%s)}"
    if [ $(( $(date +%s) - fg_bloque_depuis )) -lt 1500 ]; then
      say "reconciliation: $PKGX au premier plan (mesure en cours) — RETENTEE au prochain tour"
      return 0
    fi
    say "reconciliation: 25 min au premier plan sans relache — jeu vraisemblablement laisse ouvert, on installe quand meme"
  fi
  fg_bloque_depuis=""

  say "reconciliation: telephone en arriere du build (custom '$dev_c'->'$want_c', cgo '$dev_g'->'$want_g', apk '$inst_id'->'$apk_id') — installation"
  if ! timeout 1800 "$ADBX" -s "$SERX" install -r "$APKX" >> "$LOG" 2>&1; then
    say "reconciliation: adb install a echoue — retentee au prochain tour (voir plus haut dans ce log)"
    return 0
  fi
  echo "$apk_id" > .autoport/.redmi_installed_apk
  # L'installation VIENT d'effacer l'app-op : on le repose avant meme de relancer LoaderActivity,
  # sinon le lancement ci-dessous est deja celui qui se voit refuser la surface.
  appop_surface_verrouillee "juste apres l'installation"
  # 2026-09-11 — CHAINE D'INSTALLATION MEMORISEE. deploy_verify tirait l'APK ENTIER (671 Mo)
  # du telephone a chaque fermeture pour lire l'empreinte d'UN fichier qu'il contient. Celui qui
  # installe la connait deja : on l'ecrit ici, avec de quoi prouver que le fichier sur le
  # telephone est bien celui-la (chemin + taille + date, releves APRES l'installation). Un APK
  # pose par quelqu'un d'autre — l'owner qui installe un build de jak-builds — change taille et
  # date, et deploy_verify retombe alors sur le tirage complet.
  {
    so_sha=$(unzip -p "$APKX" lib/arm64-v8a/libgk.so 2>/dev/null | sha256sum | cut -d" " -f1)
    dpath=$("$ADBX" -s "$SERX" shell pm path "$PKGX" 2>/dev/null | sed "s/package://" | tr -d "\r" | head -1)
    dstat=$("$ADBX" -s "$SERX" shell stat -c "%s:%Y" "$dpath" 2>/dev/null | tr -d "\r")
    [ -n "$so_sha" ] && [ -n "$dpath" ] && [ -n "$dstat" ] && \
      printf "%s|%s|%s|%s|%s\n" "$SERX" "$PKGX" "$dpath" "$dstat" "$so_sha" \
        > .autoport/.installed_chain
  } 2>/dev/null || true
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
  # MENAGE DISQUE (2026-08-31) : le disque plein a TUE LE SHELL cette nuit, en pleine
  # analyse. Le ménage ne se declenche que sous son plancher d'espace libre et ne touche
  # qu'aux journaux bruts des phases que l'owner a FERMEES. Appele ici parce que c'est la
  # seule boucle qui tourne en permanence.
  bash .autoport/disk_reclaim.sh 50 15 >> .autoport/logs/disk_reclaim.txt 2>&1 || true
  shield_keep_out   # owner 2026-08-30 : la Shield ne doit jamais etre visible d'un tour a l'autre
  sleep 240

  # RECONCILIATION D'ABORD, a chaque tour, qu'on ait bati ou non : c'est ce qui rend
  # impossible qu'un report d'installation devienne un abandon (voir le pave ci-dessus).
  reconcilier_telephone

  # Une demande explicite prime sur tout ; sinon on regarde HEAD, mais jamais un WIP.
  if [ -f "$REQ" ]; then
    h=$( { git rev-parse HEAD; cat "$REQ"; } 2>/dev/null | md5sum | cut -d' ' -f1)
    reason="demande explicite ($(head -c 120 "$REQ" 2>/dev/null | tr '\n' ' '))"
  elif head_is_wip; then
    say_cause wip "aucun build — HEAD est un checkpoint WIP ($(git log -1 --format=%h 2>/dev/null))"; continue
  else
    h=$(git rev-parse HEAD 2>/dev/null | md5sum | cut -d' ' -f1)
    reason="commit livrable $(git log -1 --format=%h 2>/dev/null)"
  fi
  # Les anciens reperes memorisaient aussi les echecs. Sans recu verifie,
  # ils ne peuvent plus supprimer la tentative de reprise.
  ready=0
  python3 .autoport/delivery_artifact.py check >/dev/null 2>&1 && ready=1
  if [ "$ready" = 1 ] && [ "$h" = "$(cat "$STAMP" 2>/dev/null)" ]; then
    say_cause deja-bati "aucun build — $reason : deja bati, artefacts prets"; continue
  fi

  # PORTE DE CONTENU : rien hors `.autoport/` depuis le dernier build ⇒ ni build ni publication.
  # Une demande explicite du worker passe outre : lui sait que son code est final.
  if [ "$ready" = 1 ] && [ ! -f "$REQ" ] && ! range_touches_game; then
    say_cause sans-fichier-de-jeu "build IGNORE — aucun fichier de jeu depuis le dernier build ($(git log -1 --format=%h))"; continue
  fi

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
  # LA GARDE, MESUREE (bloc BUILDER-GUARD ci-dessus) : un demon Gradle INACTIF n'entre ni dans
  # `busy` ni dans `hard`. `read` sur une chaine-ici s'execute dans CE shell, pas dans un tuyau :
  # les quatre valeurs survivent a la ligne.
  busy=-; hard=-; idle_daemons=-; busy_why=-
  read -r busy hard idle_daemons busy_why <<< "$(builder_busy_counts)"
  now=$(date +%s); : "${blocked_since:=$now}"
  if [ "${busy:-0}" -gt 0 ]; then
    # MESURE du 2026-08-11 16:40 : 6 sondages sur 6 montrent un compilateur actif — le worker
    # compile en permanence. Exiger `hard == 0` rendait la patience aussi inutile que la garde
    # d'origine, et l'owner ne recevait toujours rien. Sa consigne est explicite et repetee :
    # livrer au fil de l'eau prime. Passe le delai on construit MALGRE le worker ; au pire sa
    # compilation en cours echoue et il la relance, ce qui coute une minute — contre une
    # livraison qui n'arrive jamais.
    # 2026-09-03 : on ne bâtit PLUS par-dessus un `gk` en cours. La raison d'origine (« l'owner
    # ne recevait plus aucun APK ») tombe : les builds ne sont plus declenches par les WIP, donc
    # ils sont rares et intentionnels, et attendre une fenetre libre ne retarde plus la livraison.
    # Ecraser l'ISO sous un `gk` de mesure produisait un faux rouge ET un APK depareille.
    # On n'exige plus que l'absence de COMPILATEUR passe 20 min, jamais l'absence de gk seule.
    if [ $(( now - blocked_since )) -gt 1200 ] && [ "${hard:-0}" -eq 0 ]; then
      say "patience depassee (20 min) mais aucun compilateur actif — build lance (busy=$busy why=$busy_why)"
      blocked_since=$now
    else
      say_cause build-en-cours "aucun build — un build tourne (busy=$busy hard=$hard demons-inactifs-ecartes=$idle_daemons : $busy_why)"; continue
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
    # LE DETENTEUR DOIT ETRE VIVANT (2026-08-31 01:05). Mesure : le marqueur nommait
    # pid=934793, mort depuis longtemps, et 57 tentatives de build ont ete ecartees en une
    # heure par une garde qui gardait le vide — pendant que l'owner attendait le correctif
    # du plantage d'herbe. La borne de 60 min ne suffit pas : elle fait attendre une heure
    # pour rien. On LIT le pid inscrit dans le marqueur et on teste sa vie.
    # On NE SUPPRIME PAS le fichier : effacer un verrou a la main a deja relache le
    # constructeur en pleine course et detruit des art-groups (voir PITFALLS). On l'ignore,
    # c'est tout — le poseur reste seul proprietaire de son fichier.
    HOLDER=$(sed -n 's/.*pid=\([0-9]\+\).*/\1/p' "$LOCK" 2>/dev/null | head -1)
    if [ -n "$HOLDER" ] && ! kill -0 "$HOLDER" 2>/dev/null; then
      say "verrou de livraison ORPHELIN (detenteur pid=$HOLDER mort, ${age}s) — ignore, on construit"
    elif [ "$age" -lt 3600 ]; then
      say_cause livraison-en-cours "livraison en cours ($(cat "$LOCK" 2>/dev/null | tr '\n' ' '), ${age}s, detenteur pid=$HOLDER vivant) — on ne rebatit pas par-dessus"; continue
    else
      say "verrou de livraison perime (${age}s > 3600) — ignore"
    fi
  fi

  # Exclusion avec le publieur ; verrou PID tenu aussi pendant les preparatifs.
  exec 8>.autoport/.delivery-artifacts.lock
  if ! flock -n -x 8; then exec 8>&-; say_cause verrou-publieur "aucun build — .delivery-artifacts.lock est tenu (le publieur travaille)"; continue; fi
  printf '%s pid=%s\n' "$0" "$$" > .autoport/.deploy-in-progress
  trap 'rm -f "$PIDFILE" .autoport/.deploy-in-progress' EXIT
  fin_de_passe(){ rm -f .autoport/.deploy-in-progress; flock -u 8; exec 8>&-; }
  build_commit=$(git rev-parse HEAD) || { say_cause git-muet "aucun build — git rev-parse HEAD a echoue"; fin_de_passe; continue; }
  build_sources=$(python3 .autoport/delivery_artifact.py sources) || { say_cause sources-illisibles "aucun build — delivery_artifact.py sources a echoue"; fin_de_passe; continue; }
  request_hash=$(sha256sum "$REQ" 2>/dev/null | cut -d' ' -f1)
  rm -f .autoport/.delivery-ready.json
  # Les deux compilateurs consomment les headers serialises, eux aussi.
  if ! bash .autoport/lib/build_x86.sh --target goalc >> "$LOG" 2>&1 ||
     ! cmake --build build-arm64 --target goalc -j "$(nproc)" >> "$LOG" 2>&1 ||
     ! bash .autoport/prepare_delivery_bakes.sh >> "$LOG" 2>&1; then
    say_cause preparation-echouee "preparation/cuisson ECHOUEE — demande conservee, prochain tour retente"
    fin_de_passe
    continue
  fi

  # NE JAMAIS CONSTRUIRE DEPUIS UN ARBRE SALE (2026-08-11 18:50). Le build de 18:28 a ete
  # fabrique pendant que le worker ecrivait le moteur : 366 lignes ajoutees et 52 retirees non
  # commitees. L'owner a donc teste un moteur a MOITIE reecrit et l'a trouve pire — "des petits
  # flickers qui font plus glitch qu'intentionnels". Un build livrable se fait depuis un etat
  # COHERENT : ce que le compilateur accepte, et dont on garde une trace exacte. Ce fut un commit
  # jusqu'au 2026-09-11 ; c'est desormais un instantane, parce qu'un commit prenait la propriete
  # d'un travail que le constructeur n'avait pas fait.
  SNAP=""   # une passe sur arbre propre ne doit pas reprendre l'instantane de la passe d'avant
  dirty=$(git status --porcelain -- goal_src/ game/ android/ common/ goalc/ 2>/dev/null | grep -c . || true)
  if [ "${dirty:-0}" -gt 0 ]; then
    # Un arbre sale n'est pas forcement a moitie ecrit : le seul test objectif, c'est qu'il
    # COMPILE. S'il compile, l'etat est coherent et on en fait un point de commit pour livrer;
    # sinon le worker est vraiment au milieu d'une edition et on attend. Sans ce raffinement le
    # garde-fou pose a 18:50 aurait bloque toute livraison pendant des heures — l'owner a demande
    # l'inverse.
    if timeout 900 ./build/goalc/goalc --user-auto --cmd '(make-group "iso")' >> "$LOG" 2>&1; then
      # LE CONSTRUCTEUR NE COMMITE PLUS RIEN (2026-09-11, item builder-checkpoint-steals-work).
      # Ces deux lignes etaient `git add -- goal_src/ game/ android/ common/ goalc/` suivi d'un
      # `git commit`. Le constructeur ne PRODUIT rien sous ces cinq dossiers : tout ce qu'elles
      # ramassaient appartenait a un chantier en cours. La purge d'eclairage commandee par
      # l'owner est partie entiere dans 2605a2f595 et a2dcd34b3f, sous un sujet qui ne nomme
      # aucun chantier. Un instantane conserve l'etat bati sans se l'approprier : HEAD ne bouge
      # pas, l'index du worker n'est pas valide, l'arbre n'est pas touche.
      SNAP=$(checkpoint_snapshot "arbre sale mais compile — build $(date -Is)")
      if [ -n "$SNAP" ]; then
        checkpoint_snapshot_prune 100
        say "arbre sale mais COMPILE — instantane $SNAP (aucun commit, aucun fichier de chantier emporte), build autorise"
      else
        say "arbre sale mais COMPILE — instantane IMPOSSIBLE (git a refuse) ; build autorise, toujours aucun commit"
      fi
    else
      say_cause arbre-ne-compile-pas "arbre sale ET ne compile pas — worker au milieu d'une edition, build reporte"
      fin_de_passe
      continue
    fi
  fi
  # LE CONSTRUCTEUR POSE LE VERROU QU'IL FAISAIT LIRE AUX AUTRES (2026-09-03). Il consultait
  # `.deploy-in-progress` sans jamais l'ecrire : rien n'empechait un `gk` de demarrer pendant que
  # lui reecrivait `out/jak1/iso` en ARM64. `lib/proof_run.sh` attend ce verrou ; il faut donc
  # qu'il existe pendant toute la passe. PID vivant inscrit dedans, retire par trap.
  echo "pid=$$ started=$(date -Is) what=build-arm64-apk" > .autoport/.deploy-in-progress
  trap 'rm -f "$PIDFILE" .autoport/.deploy-in-progress' EXIT
  # LE VERROU SE REND A LA FIN DE LA PASSE, PAS A LA MORT DU DEMON (2026-09-03 14:00).
  # Le `trap ... EXIT` ci-dessus ne tire que quand ce script s'arrete. Or ce script est une
  # boucle sans fin : apres son PREMIER build, le marqueur restait sur le disque avec un PID
  # BIEN VIVANT, pendant les 240 s de sommeil et pendant toutes les passes ou rien n'est bati.
  # `lib/proof_run.sh::busy_reason` lit exactement ca — « deploy-in-progress pid=N vivant » — et
  # attend 1800 s avant de rendre 3 SANS ecrire de preuve. Mesure : marqueur pose a 12:12, build
  # fini a 12:18, encore la a 14:00. Aucune preuve appareil n'etait possible entre les deux.
  # On le rend donc a chaque sortie de passe. Le trap EXIT reste, comme filet.
  # shellcheck disable=SC2317
  say "build declenche — $reason"
  if ! timeout 3600 bash .autoport/build_arm64_full_consistent.sh >> "$LOG" 2>&1; then
    say_cause build-arm64-echoue "build arm64 ÉCHOUÉ — rien à publier, prochain tour retente"
    fin_de_passe
    continue
  fi

  say "APK gradle"
  # Espace mort de Gradle : un assemble incremental repete gonfle l'APK (588 Mo -> 1019 Mo
  # constate le 2026-08-11, il aurait double le telechargement de l'owner sans que personne
  # ne le voie). On nettoie le module avant chaque APK publiable.
  # `:app:clean` avant CHAQUE APK coutait plusieurs minutes par build. Il servait a un vrai
  # defaut (l'espace mort d'un assemble incremental repete : 588 Mo -> 1019 Mo le 2026-08-11).
  # On ne nettoie donc que lorsque le defaut se manifeste : au-dela de 700 Mo, ou tous les
  # 10 builds, ou sur demande explicite (`full` dans .build-request).
  APKF=$(ls -t android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk 2>/dev/null | head -1)
  SZ=$(stat -c %s "$APKF" 2>/dev/null || echo 0)
  NB=$(( $(cat .autoport/.build-count 2>/dev/null || echo 0) + 1 )); echo "$NB" > .autoport/.build-count
  if [ "$SZ" -gt 734003200 ] || [ $(( NB % 10 )) -eq 0 ] || echo "${reason:-}" | grep -q full; then
    say "gradle clean (taille=${SZ}o build#${NB})"
    ( cd android && timeout 900 ./gradlew :app:clean >> "../$LOG" 2>&1 )
  fi
  # Une sortie de la passe precedente ne prouve pas que cette passe a produit
  # un APK. Gradle re-empaquette seulement la sortie manquante, sans clean.
  rm -f android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
  if ! ( cd android && timeout 2400 ./gradlew assembleJak1Debug >> "../$LOG" 2>&1 ); then
    ( cd android && timeout 120 ./gradlew --stop >/dev/null 2>&1 )
    say_cause gradle-echoue "gradle ÉCHOUÉ"
    fin_de_passe
    continue
  fi
  # LE DEMON GRADLE SURVIT A SON BUILD, ET IL A COUTE 30 MINUTES DEUX FOIS (2026-09-03 17:26).
  # `lib/proof_run.sh::busy_reason` teste `pgrep -f '[g]radle'` : un demon INACTIF y ressemble
  # exactement a un build en cours, et proof_run attend jusqu'a `AUTOPORT_PROOF_WAIT_MAX` (1800 s)
  # sans mesurer quoi que ce soit. La perte s'est repetee ; on la rend impossible au POINT DE
  # PRODUCTION plutot que d'assouplir la garde du preuveur — un `busy_reason` plus permissif
  # laisserait un `gk` demarrer pendant que `out/jak1/iso` se reecrit, ce qu'elle existe pour
  # empecher. Le demon rendu ici coute ~10 s au prochain build.
  ( cd android && timeout 120 ./gradlew --stop >/dev/null 2>&1 )

  # ----------------------------------------------------------------------------------------------
  # LE PACK HD EXTERNE — LE SEUL VEHICULE DU MESH, ET AUCUNE ETAPE NE LE REFABRIQUAIT.
  # Mesure du 2026-08-13 00:47 : le bake avait reecrit `out/jak1/fr3/enhanced/GAME.fr3` a 23:53
  # (correctif PRIORITE 1 des cheveux, aretes dechirees 82/19/10/10/26/24 -> 0), le publieur
  # surveillait bien `out/artifacts/jak1_hd_assets.zip`... que PERSONNE ne reconstruisait. Le
  # correctif est donc reste sur le disque, invisible pour l'owner, sans qu'aucune gate ne le voie.
  #
  # Les poids de peau HD ne voyagent JAMAIS dans l'APK (IP Naughty Dog) : ce zip est leur unique
  # chemin. Un APK frais a cote d'un pack perime, c'est precisement la paire depareillee que ce
  # script existe pour empecher. On le refabrique donc a CHAQUE build publiable, sans condition :
  # sa version est derivee du contenu, donc si rien n'a change le zip est identique et le publieur
  # (qui compare des md5) ne le renvoie pas. Ca ne coute rien et ca ne peut plus etre oublie.
  rm -f out/artifacts/jak1_hd_assets.zip
  if ! timeout 900 bash scripts/package_hd_assets.sh jak1 >> "$LOG" 2>&1; then
    say_cause pack-hd-echoue "pack HD ÉCHOUÉ — l'APK partirait avec un mesh perime, on ne publie pas"
    fin_de_passe
    continue
  fi
  # ----------------------------------------------------------------------------------------------

  # la paire doit être traçable : même commit pour l'APK et pour le pack
  sha=${build_commit:0:12}
  mkdir -p out/artifacts
  {
    echo "commit: $sha"
    echo "branche: $(git branch --show-current)"
    echo "date: $(date -Is)"
    echo "état: build intermédiaire, PAS validé — publié pour que l'owner puisse tester (consigne 2026-08-11)"
    [ -f .autoport/OWNER-VERIFY-QUEUE.md ] && sed -n '1,40p' .autoport/OWNER-VERIFY-QUEUE.md
  } > out/artifacts/BUILD-INFO.txt

  # ESPACE MORT DE GRADLE : un assemble incremental repete gonfle l'APK. Le 2026-09-03 le
  # nettoyage est devenu conditionnel (il coutait plusieurs minutes a CHAQUE build) et la
  # condition regardait la taille de l'APK AVANT la passe — donc trop tot : l'APK de 15:03 est
  # sorti a 1,17 Go, cette garde l'a refuse, et l'owner n'a recu AUCUN build. Une garde qui
  # refuse sans reparer transforme un defaut connu en livraison manquante.
  # On repare donc a la sortie : au-dela du seuil, on nettoie et on rassemble UNE fois, puis on
  # rejuge. Le cout du nettoyage n'est paye que quand le defaut se manifeste vraiment.
  _apk=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
  _sz=$(stat -c %s "$_apk" 2>/dev/null || echo 0)
  if [ "$_sz" -gt 700000000 ]; then
    say "APK a $_sz octets (espace mort) — nettoyage et reassemblage, une seule fois"
    ( cd android && timeout 900 ./gradlew :app:clean >> "../$LOG" 2>&1 )
    if ( cd android && timeout 2400 ./gradlew assembleJak1Debug >> "../$LOG" 2>&1 ); then
      _sz=$(stat -c %s "$_apk" 2>/dev/null || echo 0)
      say "apres nettoyage : $_sz octets"
    else
      say_cause reassemblage-echoue "reassemblage apres nettoyage ECHOUE"
      ( cd android && timeout 120 ./gradlew --stop >/dev/null 2>&1 )
      fin_de_passe
      continue
    fi
    # ET ON REND LE DEMON ICI AUSSI. Le `--stop` de la passe normale est plus haut ; ce
    # reassemblage tourne APRES lui, donc il rallumait un demon qui survivait a la passe.
    # Mesure du 2026-09-05 : demon ne a 14:05:43 par ce bloc, toujours vivant a 14:12 ;
    # `busy_reason` (lib/proof_run.sh ET acquis/font-urbanist.sh) teste `pgrep -f '[g]radle'`
    # et ne distingue pas un demon INACTIF d'un build en cours. La porte de fermeture de
    # l'essai 3 de `recharged-settings-case-l10n` a donc rendu « un build ecrit encore
    # out/jak1/iso apres 420s » sur un arbre ou plus rien ne batissait : l'acquis Urbanist
    # n'a pas pu etre mesure et l'essai a ete brule. On ne relache pas la garde (elle empeche
    # un gk de demarrer pendant que out/jak1/iso se reecrit) : on eteint la cause.
    ( cd android && timeout 120 ./gradlew --stop >/dev/null 2>&1 )
  fi
  if [ "$_sz" -gt 700000000 ]; then
    say_cause apk-trop-gros "APK toujours anormalement gros ($_sz octets) apres nettoyage — NON publie"
    fin_de_passe
    continue
  fi
  # BUILD-INFO ECRIT A CHAQUE BUILD AUTOMATIQUE (2026-08-11 23:30). Sans ca, le publieur poussait
  # l'APK et laissait a cote une description vieille de 45 minutes decrivant un AUTRE build :
  # l'owner n'avait aucun moyen de savoir qu'un build etait arrive, ni ce qu'il contenait.
  # « Mais zero build pousse what the fuck » -- il y en avait un, invisible faute d'etiquette.
  TAGX=$(bash .autoport/build_tag.sh 2>/dev/null)
  TBLX=.autoport/reports/Grecharged-secondary-motion/keira-room-table.txt
  {
    echo "TAG: $TAGX      (a comparer sur ton telephone : files/.custom_pack_stamp_jak1)"
    echo "date: $(date -Is)     commit: $sha     build AUTOMATIQUE (etat compile${SNAP:+, instantane ${SNAP:0:12}})"
    echo
    echo "MOUVEMENT MESURE PAR CHAINE sur ce build (amplitude de pointe, max des 5 pilotages) :"
    if [ -f "$TBLX" ]; then
      awk '/^row /{ch="";tv=0;for(i=1;i<=NF;i++){if($i~/^chain=/){split($i,x,"=");ch=x[2]}
           if($i~/^tipvar=/){split($i,y,"=");tv=y[2]}}if(tv>m[ch])m[ch]=tv}
           END{n=0;for(k in m){printf "  %-13s %.4f\n",k,m[k];n++}}' "$TBLX" | sort
    else
      echo "  (pas de tableau de mesures disponible pour ce build)"
    fi
    # ------------------------------------------------------------------------------------------
    # LE PACK HD SE RE-TELECHARGE A LA MAIN, ET SANS CETTE LIGNE PERSONNE NE LE SAIT.
    # Les poids de peau du mesh HD ne voyagent JAMAIS dans l'APK (IP Naughty Dog) : ils partent
    # dans jak1_hd_assets.zip, que l'owner choisit et extrait lui-meme. Le 2026-08-13 le correctif
    # PRIORITE 1 des cheveux etait ENTIEREMENT dans ce pack : reprendre le seul APK n'aurait
    # montre STRICTEMENT AUCUNE difference, et le retour aurait ete « aucune amelioration » sur un
    # correctif jamais recu. La version est derivee du CONTENU, donc elle ne change que quand le
    # mesh change : il sait ainsi s'il doit le reprendre ou non, au lieu de le deviner.
    if [ -f out/artifacts/jak1_hd_assets.manifest.txt ]; then
      echo
      echo "PACK HD EXTERNE : $(grep -m1 '^version=' out/artifacts/jak1_hd_assets.manifest.txt | cut -d= -f2)"
      echo "  Si cette version a change depuis ton dernier test, RE-TELECHARGE jak1_hd_assets.zip"
      echo "  et RE-EXTRAIS-LE. Les modeles HD ne sont PAS dans l'APK (ils n'y seront jamais) :"
      echo "  tout correctif portant sur la GEOMETRIE ou les POIDS DE PEAU voyage uniquement la."
    fi
    echo
    echo "Ce fichier est ecrit AUTOMATIQUEMENT a chaque build, il decrit donc toujours l'APK"
    echo "qui est a cote de lui. Si les deux dates divergent, dis-le moi."
  } > out/artifacts/BUILD-INFO.txt
  if ! python3 .autoport/delivery_artifact.py seal "$build_commit" "$build_sources" >> "$LOG" 2>&1; then
    say_cause artefacts-incomplets "artefacts incomplets ou sources modifiees — prochain tour retente"
    fin_de_passe
    continue
  fi
  if ! mark_built "$h"; then
    rm -f .autoport/.delivery-ready.json
    say_cause reperes-non-ecrits "reperes non ecrits — prochain tour retente"
    fin_de_passe
    continue
  fi
  # Une nouvelle demande arrivee pendant le build appartient au tour suivant.
  if [ -n "$request_hash" ] && [ "$request_hash" = "$(sha256sum "$REQ" 2>/dev/null | cut -d' ' -f1)" ]; then
    rm -f "$REQ"
  fi
  say "APK + BUILD-INFO prets pour le commit $sha — le publieur prendra le relais"

  # On installe TOUT DE SUITE ce qu'on vient de produire, sans attendre le tour suivant.
  # Et si ce passage-ci reporte (mesure en cours, telephone absent, install ratee), le
  # tour suivant le retentera : c'est la boucle, en tete, qui garantit qu'un report ne
  # devient jamais un abandon.
  reconcilier_telephone
  fin_de_passe
done
