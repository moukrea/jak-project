#!/usr/bin/env bash
# lib/pidguard.sh — UN VERROU EST TENU PAR UN PROCESSUS, PAS PAR UN NUMERO.
#
# POURQUOI CE FICHIER EXISTE (harness-judge-binary-race-with-builder, 2026-09-20).
# Le 20/09 a 14:23, `auto_build_apk.sh` a lu `.autoport/.deploy-in-progress` et dit :
#   « livraison en cours (keira_room_x86 pid=2948601 started=2026-08-19T14:14:52, 540s,
#     detenteur vivant) — on ne rebatit pas »
# puis, 25 minutes plus tard : « patience depassee — build lance ». Le pid 2948601 REPONDAIT a
# `kill -0`, mais le processus qui avait pose ce marqueur etait mort depuis UN MOIS : le numero
# avait ete recycle par le systeme. La garde a donc cru le verrou tenu, attendu pour rien, puis
# construit PAR-DESSUS une course de preuve. Meme famille que `$PPID` lu apres l'exec : un pid
# seul n'identifie personne.
#
# LA REGLE. Un detenteur repond quand son pid VIT **et** que c'est LE MEME processus qu'au
# moment de la pose. La preuve du « meme processus » se lit dans l'ordre :
#   1. `starttime=` du verrou contre le champ `starttime` de /proc/<pid>/stat — exact, en jiffies ;
#   2. a defaut, `started=` (horloge murale) contre l'instant de demarrage REEL du processus ;
#   3. a defaut, rien : le verrou est tenu « sans temoin », et c'est un defaut de son ECRIVAIN,
#      compte comme tel par le recensement. On ne devine pas, on le NOMME.
# Un verrou SANS pid (un `touch` nu, que les DIRECTIVES interdisent) ne tient rien : perime.
# Un pid ZOMBIE a fini de tourner et repond encore a `kill -0` : perime.
#
# Usage, en source :  . lib/pidguard.sh  puis  pg_lock_holder <fichier> ; pg_lock_write <f> <quoi>
# Usage, en CLI    :  lib/pidguard.sh holder <fichier>   -> `pidguard_*` sur stdout, 0 = tenu
#                     lib/pidguard.sh write  <fichier> <quoi>
#                     lib/pidguard.sh starttime <pid>
#
# `set` N'EST POSE QU'EN EXECUTION DIRECTE. Sourcer ce fichier dans `auto_build_apk.sh` — un
# demon de plusieurs centaines de lignes ecrit sans `set -u` — lui imposerait `nounset` et le
# tuerait a la premiere variable non initialisee, tres loin d'ici. Une bibliotheque ne change pas
# le regime de son appelant.
[ "${BASH_SOURCE[0]}" = "$0" ] && set -uo pipefail

# L'INSTANT DE DEMARRAGE D'UN PID. Le nom du processus peut contenir une espace et des
# parentheses : on coupe apres la DERNIERE parenthese fermante, apres quoi `starttime` — champ 22
# de proc(5) en comptant depuis `pid` — est le vingtieme champ restant.
pg_starttime(){
  case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac
  sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}'
}

# VIVANT = repond ET n'est pas un zombie. `kill -0` REUSSIT sur un zombie tant que son parent ne
# l'a pas moissonne : une garde qui ne lit que lui attend un mort.
pg_alive(){
  case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null || return 1
  [ -r "/proc/$1/stat" ] || return 0
  local st; st=$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null); st=${st%% *}
  [ "$st" = Z ] && return 1
  return 0
}

# L'INSTANT DE DEMARRAGE EN SECONDES EPOCH, pour confronter un `started=` d'horloge murale.
pg_start_epoch(){
  local jif btime hz
  jif=$(pg_starttime "${1:-}") || return 1
  case "${jif:-}" in ''|*[!0-9]*) return 1 ;; esac
  btime=$(awk '/^btime /{print $2}' /proc/stat 2>/dev/null)
  case "${btime:-}" in ''|*[!0-9]*) return 1 ;; esac
  hz=$(getconf CLK_TCK 2>/dev/null); case "${hz:-}" in ''|*[!0-9]*) hz=100 ;; esac
  echo $(( btime + jif / hz ))
}

pg_lock_write(){  # pg_lock_write <fichier> <quoi>
  local f=${1:-} quoi=${2:-inconnu}
  [ -n "$f" ] || return 2
  printf 'who=%s pid=%s starttime=%s started=%s at=%s\n' \
    "$quoi" "$$" "$(pg_starttime $$)" "$(date -Is)" "$(date +%s)" > "$f"
}

# pg_lock_holder <fichier> -> 0 = TENU, 1 = perime ou libre. Publie `pidguard_*` sur stdout.
pg_lock_holder(){
  local f=${1:-} pid st stw started ep dt
  local etat raison
  if [ -z "$f" ] || [ ! -s "$f" ]; then
    etat=libre; raison=pas-de-verrou; pid=""
  else
    pid=$(sed -n 's/.*[^a-z]pid=\([0-9][0-9]*\).*/\1/p' "$f" | tail -1)
    [ -n "$pid" ] || pid=$(sed -n 's/^pid=\([0-9][0-9]*\).*/\1/p' "$f" | tail -1)
    if [ -z "$pid" ]; then
      etat=perime; raison=sans-pid
    elif ! pg_alive "$pid"; then
      etat=perime; raison=pid-mort
    else
      stw=$(sed -n 's/.*starttime=\([0-9][0-9]*\).*/\1/p' "$f" | tail -1)
      started=$(sed -n 's/.*started=\([0-9TZ:+.-]*\).*/\1/p' "$f" | tail -1)
      if [ -n "$stw" ]; then
        st=$(pg_starttime "$pid")
        if [ "$st" = "$stw" ]; then etat=tenu; raison=starttime-concorde
        else etat=perime; raison=pid-recycle; fi
      elif [ -n "$started" ]; then
        ep=$(pg_start_epoch "$pid" 2>/dev/null)
        dt=$(date -d "$started" +%s 2>/dev/null)
        if [ -n "$ep" ] && [ -n "$dt" ]; then
          # 300 s : un `date -Is` est pose juste apres le demarrage du detenteur, jamais un mois
          # avant. L'ecart mesure le 20/09 etait de TRENTE-DEUX JOURS.
          if [ $(( ep > dt ? ep - dt : dt - ep )) -le 300 ]; then etat=tenu; raison=date-concorde
          else etat=perime; raison=pid-recycle-date; fi
        else
          etat=tenu; raison=tenu-sans-temoin
        fi
      else
        # NI `starttime=` NI `started=` : le verrou ne dit pas QUI le tient. On ne le casse pas —
        # on le NOMME, et le recensement compte son ecrivain comme un defaut a corriger.
        etat=tenu; raison=tenu-sans-temoin
      fi
    fi
  fi
  printf 'pidguard_state=%s\npidguard_reason=%s\npidguard_pid=%s\n' "$etat" "$raison" "${pid:--}"
  [ "$etat" = tenu ]
}

# SOURCEE, CE FICHIER NE FAIT RIEN. En bash, un `.` sans argument laisse au fichier source les
# PARAMETRES DE SON APPELANT : sans cette garde, `lib/proof_inflight.sh count` faisait lire
# « count » a ce dispatcheur, qui sortait en 2 avec un message d'usage. Mesure : la premiere
# execution de `proof_inflight.sh count` a rendu rc=2 et le texte d'usage de CE fichier.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    holder)    pg_lock_holder "${2:-}" ;;
    write)     pg_lock_write "${2:-}" "${3:-inconnu}" ;;
    starttime) pg_starttime "${2:-}" ;;
    alive)     pg_alive "${2:-}" ;;
    *)         echo "usage: lib/pidguard.sh {holder|write|starttime|alive} ..." >&2; exit 2 ;;
  esac
fi
