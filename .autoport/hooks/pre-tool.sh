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

HEAD=$(printf '%s' "$IN" | jq -r '(.tool_name // "") + "\u0001" + (.tool_input.file_path // "")' 2>/dev/null) || exit 0
TOOL=${HEAD%%$'\001'*}; FP=${HEAD#*$'\001'}
[ -n "${TOOL:-}" ] || exit 0

refuse(){ printf '[autoport pre-tool] REFUS : %s\n\nA LA PLACE : %s\n' "$1" "$2" >&2; exit 2; }

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
           "l'appareil de preuve est le Redmi, branche en USB : adb -s eae4df44 ..." ;
  fi
  # `until ! pgrep -f x` ne finit jamais quand le motif se matche lui-meme : 4 incidents,
  # 24 minutes perdues une fois. La regle porte sur la BOUCLE, pas sur le motif.
  if [[ $CLEAN =~ (while|until)[^$'\n']*pgrep ]]; then
    refuse "une boucle while/until qui attend sur \`pgrep\`." \
           "attends sur le verrou et son PID (kill -0), comme lib/proof_run.sh : un verrou dont le PID est mort ne vaut rien." ;
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

  # 3a. pgrep/pkill -f sans classe de caracteres : le motif se matche LUI-MEME.
  if [[ $seg =~ (pgrep|pkill)([[:space:]]|$) ]] && [[ $seg =~ (-[a-zA-Z]*f([[:space:]]|$)|--full) ]]; then
    case "$seg" in *'['*) ;; *)
      refuse "\`pgrep/pkill -f\` avec un motif sans classe de caracteres : il se matche lui-meme." \
             "mets une lettre entre crochets : pgrep -f '[o]rchestrator'" ;;
    esac
  fi
  # 3b. cmake -B : une reconfiguration invalide tout le cache d'objets (~1300).
  if [ "$CW" = cmake ] && [[ $seg =~ (^|[[:space:]])-B([[:space:]]|=) ]]; then
    refuse "\`cmake -B\` reconfigure et jette le cache d'objets." \
           "construis sans reconfigurer : cmake --build build --target gk -j\$(nproc)" ;
  fi
  # 3c. adb sans -s : viser le mauvais appareil rend un resultat FAUX, pas une erreur visible.
  case "$CW" in
    adb|'$ADB'|'${ADB}')
      if [[ ! $seg =~ (^|[[:space:]])-s([[:space:]]|=|\") ]]; then
        case "$seg" in
          *devices*|*start-server*|*kill-server*|*" version"*|*" help"*) ;;
          *) refuse "\`adb\` sans -s : la commande vise n'importe quel appareil branche." \
                    "nomme le Redmi : adb -s eae4df44 <commande> (jamais la SHIELD)" ;;
        esac
      fi ;;
  esac
  # 3d. preuve visuelle : interdite par l'owner, et illisible par une porte.
  if [[ $seg =~ (screencap|screenrecord) ]]; then
    refuse "\`${BASH_REMATCH[1]}\` : la preuve par image est interdite." \
           "publie un compteur ecrit par le moteur, lu par .autoport/lib/proof_run.sh." ;
  fi
done <<< "$SEGS"

exit 0
