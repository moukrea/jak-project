#!/usr/bin/env bash
# pre-tool.sh — GARDE MECANIQUE. Tourne avant chaque Bash/Edit/Write, doit rester sous ~50 ms
# (deux appels a jq au plus, tout le reste en bash pur : pas de basename, pas de sous-shell
# dans la boucle).
#
# Il ne remplace aucune consigne : il rend MECANIQUES six regles qui ont chacune coute au moins
# une journee tant qu'elles n'etaient que de la prose. Il refuse TRES peu de choses. Un faux
# refus coute plus cher qu'un oubli : en cas de doute il laisse passer, il ne juge jamais une
# commande qui ne fait que manipuler du texte, et chaque refus dit QUOI FAIRE A LA PLACE.
#
# Sortie : 0 = laisse passer. 2 = refuse (le message de stderr revient a Claude).
set -uo pipefail

IN=$(cat 2>/dev/null || true)
[ -n "$IN" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

HEAD=$(printf '%s' "$IN" | jq -r '(.tool_name // "") + "\u0001" + (.tool_input.file_path // "") + "\u0001" + (.session_id // "")' 2>/dev/null) || exit 0
TOOL=${HEAD%%$'\001'*}; REST=${HEAD#*$'\001'}; FP=${REST%%$'\001'*}; SID=${REST#*$'\001'}
[ -n "${TOOL:-}" ] || exit 0

refuse(){ printf '[autoport pre-tool] REFUS : %s\n\nA LA PLACE : %s\n' "$1" "$2" >&2; exit 2; }

# ARCHIVE-LEFTOVERS/ — harness-archive-and-status-write-leftovers (24/09). L'owner a archive l'item
# de CET essai : l'orchestrateur le voit dans la seconde et coupe, mais un outil lance entre-temps
# ecrivait encore dans reports/<id>/, apres l'archivage. Le refus est ici, au point de production :
# plus aucun outil ne part au nom d'un item archive. Un awk, sans tube : quelques ms.
if [ -n "${AUTOPORT_PHASE_ID:-}" ]; then
  _BL=${AUTOPORT_BACKLOG:-${CLAUDE_PROJECT_DIR:-.}/.autoport/backlog.yaml}
  _ST=$(awk -v id="$AUTOPORT_PHASE_ID" '$0=="- id: "id{f=1;next} f&&/^- id:/{exit} f&&/^  status:/{print $2;exit}' "$_BL" 2>/dev/null)
  [ "${_ST:-}" = archived ] && refuse "l'item ${AUTOPORT_PHASE_ID} est ARCHIVE par l'owner : l'essai est coupe, plus rien ne s'ecrit en son nom." \
    "arrete-toi la, sans rien ecrire : l'orchestrateur sauve ton travail et le nomme dans les notes de l'item."
fi

# ---------------------------------------------------------------- Write / Edit / MultiEdit ----
# On ne regarde QUE le chemin, jamais le contenu : un script qui PARLE d'adb n'est pas un
# script qui LANCE adb, et juger le contenu ferait refuser l'ecriture de cette garde elle-meme.
case "$TOOL" in
  Bash) ;;
  Write|Edit|MultiEdit|NotebookEdit)
    case "$FP" in
      *.autoport/reports/*.png|*.autoport/reports/*.PNG)
        refuse "ecriture d'une image sous .autoport/reports/ ($FP) : la preuve visuelle est interdite." \
               "publie un COMPTEUR produit par le moteur dans reports/<id>/proof.txt (lib/proof_run.sh)." ;;
    esac
    exit 0 ;;
  *) exit 0 ;;
esac

CMD=$(printf '%s' "$IN" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -n "${CMD:-}" ] || exit 0

# --- 1. enlever les corps de heredoc et les lignes de commentaire ----------------------------
# Sans ca, `cat > x <<'EOF' ... pkill -f ... EOF` serait refuse alors qu'il ECRIT du texte.
CLEAN=""; term=""; skip=0
while IFS= read -r ln; do
  if [ "$skip" = 1 ]; then
    t=${ln#"${ln%%[![:space:]]*}"}; t=${t%"${t##*[![:space:]]}"}
    [ "$t" = "$term" ] && skip=0
    continue
  fi
  case "${ln#"${ln%%[![:space:]]*}"}" in \#*) continue ;; esac
  CLEAN+="$ln"$'\n'
  case "$ln" in
    *'<<'*)
      t=${ln#*<<}
      case "$t" in
        '<'*) ;;                       # <<< est une here-string, pas un heredoc
        *) t=${t#-}; t=${t#"${t%%[![:space:]]*}"}
           t=${t%%[[:space:];\)\|\&\<\>]*}; t=${t//\'/}; t=${t//\"/}
           case "$t" in ''|*[!A-Za-z0-9_]*) ;; *) term=$t; skip=1 ;; esac ;;
      esac ;;
  esac
done <<< "$CMD"

# Le mot en POSITION DE COMMANDE, prefixes retires. Ecrit dans CW, sans sous-shell.
CW=""
cmdword(){
  local s=${1#"${1%%[![:space:]]*}"} w
  while [ -n "$s" ]; do
    w=${s%%[[:space:]]*}
    case "$w" in
      *=*|sudo|env|nohup|exec|time|timeout|stdbuf|nice|ionice|-*|[0-9]*) s=${s#"$w"} ;;
      *) break ;;
    esac
    s=${s#"${s%%[![:space:]]*}"}
  done
  w=${s%%[[:space:]]*}; CW=${w##*/}; CW=${CW//\"/}; CW=${CW//\'/}
}
# Une commande qui ne fait que MANIPULER DU TEXTE ne lance rien : on ne la juge pas sur ce
# qu'elle contient. C'est ce qui permet d'ecrire un rapport qui cite `pgrep -f`.
is_text(){ case "$1" in
    echo|printf|cat|grep|egrep|fgrep|rg|sed|awk|head|tail|wc|sort|uniq|tee|jq|yq|python3|python|node|git|less|ls|find|stat|file|md5sum|sha256sum|diff|cut|tr|comm) return 0 ;;
    *) return 1 ;; esac; }

cmdword "$CLEAN"; FIRST=$CW

# --- 2. tout appareil JOINT PAR LE RESEAU -----------------------------------------------------
# On interdit par FORME, pas par valeur. Nommer l'adresse de la SHIELD ici obligerait chaque
# fichier qui la protege a l'ecrire, et shield_guard.sh — qui balaye le depot par VALEUR —
# refuserait alors le demarrage a cause du code qui l'interdit. C'est arrive le 2026-09-03.
# La regle vraie est plus simple et plus large : le seul appareil autorise est branche en USB
# et porte un numero de serie ; tout ce qui se joint par une adresse IP est hors perimetre,
# quelle que soit l'adresse et meme si elle change.
if ! is_text "$FIRST"; then
  # L'ordre compte : chaque [[ =~ ]] ECRASE BASH_REMATCH, donc on capture avant de retester.
  IPFOUND=""
  [[ $CLEAN =~ (^|[^0-9])([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})(:[0-9]+)?([^0-9]|$) ]] \
    && IPFOUND=${BASH_REMATCH[2]}
  if [ -n "$IPFOUND" ] && [[ $CLEAN =~ (adb|connect|scrcpy) ]]; then
    refuse "la commande vise un appareil par une adresse reseau ($IPFOUND) : seul l'appareil USB est autorise." \
           "l'appareil de preuve est celui branche en USB, quel qu'il soit : adb -s \$(.autoport/lib/pick_device.sh) ..." ;
  fi
  # `until ! pgrep -f x` ne finit jamais quand le motif se matche lui-meme : 4 incidents,
  # 24 minutes perdues une fois. La regle porte sur la BOUCLE, pas sur le motif.
  if [[ $CLEAN =~ (while|until)[^$'\n']*pgrep ]]; then
    refuse "une boucle while/until qui attend sur \`pgrep\`." \
           "attends sur le verrou et son PID (kill -0), comme lib/proof_run.sh : un verrou dont le PID est mort ne vaut rien." ;
  fi
  # UNE BOUCLE DE SONDAGE COUTE UN CONTEXTE ENTIER PAR COUP DE SONDE
  # (harness-main-agent-context-volume, 19/09). Mesure sur les 278 essais opus-5 : 16,2 tours
  # d'attente par essai — `sleep` 9,27 %, `tail` de journal 7,73 %, `pgrep/ps` 3,17 % — soit
  # 20,2 % de l'integrale de contexte de l'agent principal, et 434,8 heures de sommeil declare
  # sur l'ensemble des journaux. Le sondage n'apprend RIEN avant la fin : c'est l'attente
  # elle-meme qui doit tenir dans UN tour. La regle porte sur la BOUCLE qui dort, pas sur
  # `sleep` : une pause courte de stabilisation reste permise, et un corps de heredoc est
  # deja retire plus haut — ECRIRE un script qui boucle n'est pas le LANCER.
  if [[ $CLEAN =~ (while|until|for)([[:space:]]|\() ]]; then
    BOUCLE_SLEEP=""
    [[ $CLEAN =~ sleep[[:space:]]+([0-9]+) ]] && BOUCLE_SLEEP=${BASH_REMATCH[1]}
    if [ -n "$BOUCLE_SLEEP" ] && [ "$BOUCLE_SLEEP" -ge 5 ] 2>/dev/null; then
      refuse "une boucle qui dort ${BOUCLE_SLEEP}s entre deux sondes : chaque coup de sonde relit tout le contexte (195 000 jetons en moyenne)." \
             "attends une SEULE fois, dans le shell : .autoport/lib/await.sh pid <pid> --log <journal>   (aussi: await.sh lock <verrou>, await.sh proof <id-d-item>)" ;
    fi
  fi
fi

# --- 3. regles par segment -------------------------------------------------------------------
# On NEUTRALISE d'abord le contenu des chaines entre guillemets. Sans ca, decouper sur `|`
# coupe AU MILIEU d'un motif comme grep -E "refuse|adb|png" et fabrique un faux segment `adb`,
# qui se fait refuser alors que la commande ne lance rien : cette garde a refuse sa propre
# relecture le 2026-09-03. Un mot entre guillemets est du TEXTE, pas une invocation ; le
# manquer est moins cher qu'un faux refus, et c'est la regle que ce fichier s'est donnee.
SAFE=$(printf '%s' "$CLEAN" | awk '{ r=""; q=0
  for (i=1; i<=length($0); i++) { c=substr($0,i,1)
    if (q==0 && (c=="\"" || c=="'"'"'")) { q=1; d=c; r=r c }
    else if (q==1 && c==d)              { q=0; r=r c }
    else if (q==1)                      { r=r (c=="|" || c==";" || c=="&" ? "X" : c) }
    else                                { r=r c } }
  print r }')
[ -n "$SAFE" ] || SAFE=$CLEAN
SEGS=${SAFE//&&/$'\n'}; SEGS=${SEGS//||/$'\n'}; SEGS=${SEGS//;/$'\n'}; SEGS=${SEGS//|/$'\n'}
while IFS= read -r seg; do
  [ -n "${seg//[[:space:]]/}" ] || continue
  cmdword "$seg"
  if [[ $seg =~ \.autoport/reports/[^[:space:]]*\.[pP][nN][gG] ]] \
     && [[ $seg =~ (\>|[[:space:]]cp[[:space:]]|[[:space:]]mv[[:space:]]|tee|convert|magick|ffmpeg) ]]; then
    refuse "ecriture d'une image sous .autoport/reports/ : la preuve visuelle est interdite." \
           "publie un compteur produit par le moteur dans reports/<id>/proof.txt." ;
  fi
  is_text "$CW" && continue

  # 3a-bis. `sleep` SEUL EN POSITION DE COMMANDE : un tour d'agent pour ne rien apprendre.
  # Le seuil vient des journaux, pas du gout : 2 882 des 4 757 `sleep` mesures dorment 10 s ou
  # plus (20 s est la valeur la plus frequente, 637 fois). Sous 10 s on laisse passer — une
  # stabilisation courte est reelle, et un faux refus coute plus cher qu'un oubli.
  if [ "$CW" = sleep ]; then
    DUREE=""
    [[ $seg =~ sleep[[:space:]]+([0-9]+) ]] && DUREE=${BASH_REMATCH[1]}
    if [ -n "$DUREE" ] && [ "$DUREE" -ge 10 ] 2>/dev/null; then
      refuse "\`sleep $DUREE\` : ce tour relit tout le contexte (195 000 jetons en moyenne) et n'apprend rien." \
             "attends la cible elle-meme, une seule fois : .autoport/lib/await.sh pid <pid> --log <journal>   (aussi: await.sh lock <verrou>, await.sh proof <id-d-item>)" ;
    fi
  fi

  # 3a. pgrep/pkill -f sans classe de caracteres : le motif se matche LUI-MEME.
  # Deux exemptions, toutes deux parce qu'on ne PEUT PAS juger : un motif qui contient deja des
  # crochets, et un motif passe par une VARIABLE (`pgrep -cf "$p"`), dont on ne voit pas le
  # contenu. Refuser le second serait un faux refus, et cette garde s'est donne pour regle que
  # laisser passer coute moins cher que bloquer a tort — elle a refuse sa propre verification
  # le 2026-09-03 avant cette exemption.
  if [[ $seg =~ (pgrep|pkill)([[:space:]]|$) ]] && [[ $seg =~ (-[a-zA-Z]*f([[:space:]]|$)|--full) ]]; then
    case "$seg" in
      *'['*|*'$'*) ;;
      *) refuse "\`pgrep/pkill -f\` avec un motif sans classe de caracteres : il se matche lui-meme." \
                "mets une lettre entre crochets : pgrep -f '[o]rchestrator'" ;;
    esac
  fi
  # 3b. Proteger les builds existants, sans bloquer le premier configure d'un temoin neuf.
  # Le parseur ne s'execute que pour CMake ; il lit la commande originale, non neutralisee.
  if [ "$CW" = cmake ] && [[ $seg =~ (^|[[:space:]])-B ]]; then
    if ! printf '%s' "$CLEAN" | python3 "${BASH_SOURCE[0]%/*}/cmake_initial_configure.py"; then
      refuse "\`cmake -B\` : configuration initiale d'un dossier neuf non etablie ; build existant protege." \
             "construis sans reconfigurer : .autoport/lib/build_x86.sh --target gk. Pour un temoin neuf : cmake -S <source absolue> -B <dossier absolu vide ou inexistant>." ;
    fi
  fi
  # 3b-bis. LA CONSTRUCTION DE BUREAU PASSE PAR SA PORTE (build-tree-reinvalidates-itself, 12/09).
  # `cmake --build build` a rendu 0 sur trois passes d'affilee en laissant `build/game/gk` NON
  # RELIE — `libruntime.a` a 14:43:15 pour un `gk` reste a 14:36:03 — et en recompilant les 338
  # cibles a chaque fois, parce que `build/.ninja_deps` etait illisible a partir du milieu. Ni
  # l'un ni l'autre n'est visible dans son code de retour. `lib/build_x86.sh` lance EXACTEMENT le
  # meme ninja, mais il repare le journal avant, compare le binaire a chacune de ses entrees
  # apres, et SORT EN 4 sur un binaire perime. Aucun script du harnais ne construit l'arbre de
  # bureau : ce point d'appel-ci est le seul, donc c'est ici que la perte se rend impossible.
  # `build-android` et `build-arm64` ne sont pas concernes : le motif exige `build` tout court.
  if [ "$CW" = cmake ] && [[ $seg =~ (^|[[:space:]])--build[[:space:]]+\.?/?build([[:space:]]|/|$) ]]; then
    refuse "\`cmake --build build\` rend 0 sur un binaire qu'il n'a pas relie, et recompile tout." \
           "passe par la porte : .autoport/lib/build_x86.sh --target gk   (elle lance le meme ninja, et elle juge le lien)" ;
  fi
  if [ "$CW" = ninja ] && [[ $seg =~ (^|[[:space:]])-C[[:space:]]+\.?/?build([[:space:]]|/|$) ]] \
     && [[ ! $seg =~ (^|[[:space:]])-(n|t)([[:space:]]|$) ]]; then
    refuse "\`ninja -C build\` construit sans juger ni le journal de dependances ni le lien." \
           "passe par la porte : .autoport/lib/build_x86.sh --target gk   (un essai a vide reste permis : ninja -C build -n ...)" ;
  fi
  # 3c. adb sans -s : viser le mauvais appareil rend un resultat FAUX, pas une erreur visible.
  case "$CW" in
    adb|'$ADB'|'${ADB}')
      if [[ ! $seg =~ (^|[[:space:]])-s([[:space:]]|=|\") ]]; then
        case "$seg" in
          *devices*|*start-server*|*kill-server*|*" version"*|*" help"*) ;;
          *) refuse "\`adb\` sans -s : la commande vise n'importe quel appareil branche." \
                    "nomme l'appareil : adb -s \$(.autoport/lib/pick_device.sh) <commande> (jamais une adresse reseau)" ;;
        esac
      fi ;;
  esac
  # 3d. preuve visuelle : interdite par l'owner, et illisible par une porte.
  # EXCEPTION (owner 25/09 : « tu devrais pouvoir prendre des captures, surtout si c'est pour les
  # joindre à la conversation sur Linear ») : une capture ecrite sous .autoport/linear-attach/
  # sert d'ILLUSTRATION pour --attach ; aucune porte ne lit ce dossier, ce n'est jamais une preuve.
  if [[ $seg =~ (screencap|screenrecord) ]]; then
    _cap="${BASH_REMATCH[1]}"
  else
    _cap=""
  fi
  # ASSOUPLI (owner 25/09 : « ça peut servir de mesure dans certains cas… faut pas non plus être
  # débile. Mais je veux pas que ça parte dans des mesures visuelles complexes à fumer X millions
  # tokens et prendre 4h de capture ») : une capture est permise, mais PLAFONNEE par essai. Au-dela
  # de CAPTURE_MAX, c'est une campagne visuelle : refusee. Hors d'un essai (superviseur), pas de plafond.
  if [[ -n $_cap ]]; then
    _att="${AUTOPORT_ATTEMPT_ID:-}"
    if [[ -n $_att ]]; then
      _cf="${CLAUDE_PROJECT_DIR:-.}/.autoport/logs/.captures-${_att//[^A-Za-z0-9_.@-]/_}"
      _n=$(( $(cat "$_cf" 2>/dev/null || echo 0) + 1 ))
      echo "$_n" > "$_cf" 2>/dev/null || true
      if (( _n > ${CAPTURE_MAX:-8} )); then
        refuse "\`${_cap}\` : ${_n}e capture de cet essai (plafond ${CAPTURE_MAX:-8}) : c'est une campagne visuelle." \
               "une ou deux captures pour illustrer ou verifier un cas simple ; au-dela, livre le build et laisse l'owner juger (5 minutes pour lui)."
      fi
    fi
  fi
done <<< "$SEGS"

# --- 4. CINQ TOURS DE LECTURE D'AFFILEE -------------------------------------------------------
# MESURE (harness-main-agent-context-volume, essai 2, 20/09, sur les 15 essais deja armes) :
# 75,4 tours par essai, dont 30,7 de LECTURE PURE — un tour qui ne fait que lire. Ces tours-la
# portent 36,8 % de l'integrale de contexte de l'agent principal. 55 % d'entre eux ne tiennent
# qu'UNE seule commande, et 78 % appartiennent a une sequence d'au moins deux lectures
# consecutives, 35 % a une sequence d'au moins cinq. Pendant
# ce temps la delegation mesuree est de 0,87 appel de sous-agent par essai — alors que les tours
# d'un sous-agent NE COMPTENT PAS dans le contexte de l'agent principal : seul son rapport
# revient. Cinq lectures separees coutent cinq relectures du contexte entier ; la meme chose en
# une commande n'en coute qu'une.
#
# CE QU'ELLE NE FAIT PAS. Elle ne refuse JAMAIS deux fois de suite : le compteur est remis a
# zero par le refus lui-meme, donc la commande rejouee telle quelle passe. Le pire cas est donc
# UN tour ajoute par sequence, le meilleur est quatre tours retires. Tout ce qui n'est pas une
# lecture pure (un `git add`, un `python3`, une ecriture, une construction) remet aussi le
# compteur a zero : la garde ne voit que les rafales de lecture, pas le travail.
#
# AUCUN ETAT, AUCUN REFUS. Sans `session_id` on ne peut pas separer deux sessions : on ne compte
# pas plutot que de compter faux.
if [ -n "${SID:-}" ]; then
  # LECTURE PURE = tous les mots en position de commande lisent, et rien n'est ECRIT. Une
  # redirection vers un fichier fabrique un artefact : ce n'est plus une lecture. `git` n'est
  # PAS dans la liste (git log lit, git add ecrit) — le manquer coute moins cher qu'un faux refus.
  PURE=1
  RED=${SAFE//2>&1/}; RED=${RED//&>\/dev\/null/}; RED=${RED//>\/dev\/null/}
  RED=${RED//> \/dev\/null/}; RED=${RED//>&2/}
  case "$RED" in *'>'*) PURE=0 ;; esac
  if [ "$PURE" = 1 ]; then
    while IFS= read -r seg; do
      [ -n "${seg//[[:space:]]/}" ] || continue
      cmdword "$seg"
      case "$CW" in
        cat|sed|head|tail|wc|ls|grep|egrep|fgrep|rg|awk|find|cut|sort|uniq|tr|comm|diff|column|\
        nm|objdump|readelf|strings|file|stat|md5sum|sha256sum|basename|dirname|realpath|\
        echo|printf|jq|xxd|od|true|pwd) ;;
        *) PURE=0; break ;;
      esac
    done <<< "$SEGS"
  fi
  LECT="${TMPDIR:-/tmp}/autoport-lecture-${SID//[^A-Za-z0-9_-]/_}"
  N=0; T=0
  if [ -r "$LECT" ]; then read -r T N < "$LECT" 2>/dev/null || { T=0; N=0; }; fi
  case "$T$N" in ''|*[!0-9]*) T=0; N=0 ;; esac
  # Un etat de plus de six heures appartient a une autre session de travail : on repart de zero.
  [ $(( ${EPOCHSECONDS:-0} - T )) -gt 21600 ] 2>/dev/null && N=0
  if [ "$PURE" = 1 ]; then N=$((N+1)); else N=0; fi
  if [ "$N" -ge 5 ] 2>/dev/null; then
    printf '%s 0\n' "${EPOCHSECONDS:-0}" > "$LECT" 2>/dev/null
    refuse "cinquieme tour de LECTURE d'affilee : chaque tour relit TOUT ton contexte (195 000 jetons en moyenne), donc cinq lectures separees coutent cinq relectures la ou une seule commande n'en coute qu'une (mesure : 30,7 lectures par essai, 36,8 % de l'integrale)." \
           "groupe-les en UNE commande (sed -n 1,40p a ; echo --- ; grep -n motif b), ou delegue la fouille a un sous-agent autoport-researcher : ses tours ne comptent PAS dans ton contexte, seul son rapport revient. Rejoue tel quel si tu as vraiment besoin de ce tour : le compteur vient d'etre remis a zero."
  fi
  printf '%s %s\n' "${EPOCHSECONDS:-0}" "$N" > "$LECT" 2>/dev/null
fi

exit 0
