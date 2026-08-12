#!/usr/bin/env bash
# phase_claim.sh — UN SEUL WORKER PAR PHASE, garanti au POINT DE PRODUCTION.
#
# POURQUOI CE FICHIER EXISTE
# --------------------------
# Le 2026-08-12, DEUX orchestrateurs (PID 705057 demarre la veille a 23:39, PID 924374 demarre
# a 06:59) ont lance DEUX workers sur la phase Grecharged-secondary-motion, sur le MEME arbre :
#
#     1174951  (fils de 705057)  detenait 117 lignes non commitees de jak-hd-physics.gc
#     1156312  (fils de 924374)  arrivait sur les memes fichiers
#
# C'est la DEUXIEME occurrence. La premiere a ete corrigee le matin meme par un `flock` pose
# dans `.autoport/orchestrator.py` — et elle s'est reproduite quand meme, pour une raison
# mecanique qui etait ecrite noir sur blanc dans le rapport de la tentative precedente :
#
#     « Les deux orchestrateurs en cours ne sont pas affectes (Python lit le fichier a
#       l'import) : la correction prend effet au prochain demarrage. »
#
# Un processus Python deja lance ne relit JAMAIS son propre source. Une correction posee dans
# l'orchestrateur ne peut donc pas arreter les orchestrateurs qui tournent — elle ne protege
# que d'un futur qui n'arrive pas. C'est exactement ce que l'owner a interdit :
#
#     « T'assurer que ton travail n'est pas systematiquement detruit, c'est chelou comme
#       comportement, tu peux pas juste dire "ah oups", corriger et laisser reproduire en
#       boucle ! »  —  et la regle qui en decoule : quand une perte se repete, on la rend
#       impossible AU POINT DE PRODUCTION, pas detectable au point de controle.
#
# LE POINT DE PRODUCTION D'UN DOUBLON DE WORKER N'EST PAS L'ORCHESTRATEUR, C'EST LE DEMARRAGE
# DU WORKER. Le hook `SessionStart` est RE-EXECUTE a chaque lancement de `claude -p`, par
# n'importe quel orchestrateur, deja lance ou non. Une garde posee la prend effet au PROCHAIN
# worker, sans redemarrer quoi que ce soit et sans tuer personne.
#
# IDENTITE D'UN PROCESSUS, ET PAS UN MOTIF
# ----------------------------------------
# La liveness se lit sur (pid, heure de demarrage du noyau, nom du programme) :
#   * `/proc/<pid>` existe                      -> le pid est pris
#   * champ 22 de `/proc/<pid>/stat` identique  -> c'est LE MEME processus (pas un pid recycle)
#   * `/proc/<pid>/comm` == "claude"            -> c'est bien un worker
# Aucune correspondance de motif sur une ligne de commande : `pkill -f "pat"` s'auto-matche, et
# une boucle d'attente qui contient son propre motif s'attend elle-meme pour toujours. On lit
# le NOM du programme, jamais sa ligne de commande. Et on ne TUE rien : on refuse d'entrer.
#
# USAGE
#   phase_claim.sh claim   <phase-id>   -> 0 = la phase est a nous, 3 = un worker vivant l'a deja
#   phase_claim.sh release <phase-id>   -> libere si et seulement si le jeton est le notre
#   phase_claim.sh status  <phase-id>   -> imprime le detenteur, 0 s'il y en a un, 1 sinon

set -uo pipefail

AUTOPORT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/.autoport"
LOGDIR="$AUTOPORT_DIR/logs"
LOCK="$AUTOPORT_DIR/.phase-claim.lock"

cmd="${1:-}"
phase="${2:-}"
[ -n "$cmd" ] && [ -n "$phase" ] || { echo "usage: phase_claim.sh {claim|release|status} <phase-id>" >&2; exit 2; }

# Un nom de fichier par phase, assaini : deux phases differentes ne se bloquent pas.
safe=$(printf '%s' "$phase" | tr -c 'A-Za-z0-9._-' '_')
CLAIM="$AUTOPORT_DIR/.phase-claim.$safe"

mkdir -p "$LOGDIR" 2>/dev/null || true

# --- identite du processus -----------------------------------------------------------------
# `comm` (champ 2 de /proc/<pid>/stat) est entre parentheses et peut contenir des espaces ET
# des parentheses. On coupe apres la DERNIERE ')' de la ligne (les champs suivants sont tous
# numeriques, donc il n'y en a aucune apres). Sur la chaine restante :
#     $1 = state   $2 = ppid   ...   $20 = starttime (champ 22 de la ligne complete)
proc_tail() { sed 's/.*) //' "/proc/$1/stat" 2>/dev/null; }
proc_starttime() { proc_tail "$1" | awk 'NF{print $20}'; }
proc_ppid()      { proc_tail "$1" | awk 'NF{print $2}'; }
proc_comm()      { cat "/proc/$1/comm" 2>/dev/null; }

# Le worker est le premier ancetre dont le NOM de programme est `claude`. Le hook tourne dans
# un bash lance par lui, donc on remonte la chaine des parents plutot que de supposer $PPID.
find_worker_pid() {
    local pid="${PPID:-$$}" hops=0 ppid
    while [ "$hops" -lt 12 ] && [ "${pid:-0}" -gt 1 ] 2>/dev/null; do
        if [ "$(proc_comm "$pid")" = "claude" ]; then printf '%s' "$pid"; return 0; fi
        ppid=$(proc_ppid "$pid")
        [ -n "${ppid:-}" ] || return 1
        pid="$ppid"; hops=$((hops + 1))
    done
    return 1
}

# Un jeton est VIVANT si son pid tourne encore, que c'est le meme processus (heure de
# demarrage identique, donc pas un pid recycle) et que c'est bien un worker.
claim_is_live() {
    local f="$1" pid st comm now_st
    [ -s "$f" ] || return 1
    pid=$(sed -n 's/^pid=\([0-9]\+\).*/\1/p' "$f" | head -1)
    st=$(sed -n 's/.*starttime=\([0-9]\+\).*/\1/p' "$f" | head -1)
    [ -n "${pid:-}" ] && [ -n "${st:-}" ] || return 1
    [ -d "/proc/$pid" ] || return 1
    now_st=$(proc_starttime "$pid") || return 1
    [ "$now_st" = "$st" ] || return 1          # pid recycle : le jeton est perime
    comm=$(proc_comm "$pid")
    [ "$comm" = "claude" ] || return 1         # ce n'est plus un worker
    return 0
}

claim_holder() { sed -n 's/^pid=\([0-9]\+\).*/\1/p' "$1" 2>/dev/null | head -1; }

case "$cmd" in
  status)
      if claim_is_live "$CLAIM"; then cat "$CLAIM"; exit 0; fi
      echo "libre"; exit 1 ;;

  claim)
      wpid=$(find_worker_pid) || wpid="$$"
      wst=$(proc_starttime "$wpid" || echo 0)
      # flock sur un fichier SEPARE : le jeton lui-meme est reecrit, donc le verrouiller
      # directement ouvrirait une fenetre entre la troncature et l'ecriture.
      exec 9>"$LOCK"
      flock -x 9
      if claim_is_live "$CLAIM"; then
          holder=$(claim_holder "$CLAIM")
          if [ "$holder" = "$wpid" ]; then exec 9>&-; exit 0; fi   # deja le notre
          {
              echo "$(date -Is) REFUS phase=$phase demandeur=$wpid detenteur=$holder"
              sed 's/^/    /' "$CLAIM"
          } >> "$LOGDIR/phase-claim.log" 2>/dev/null || true
          printf 'pid=%s\n' "$holder"
          exec 9>&-
          exit 3
      fi
      printf 'pid=%s starttime=%s orch=%s phase=%s ts=%s\n' \
             "$wpid" "$wst" "$(proc_ppid "$wpid")" "$phase" "$(date -Is)" > "$CLAIM"
      echo "$(date -Is) PRIS  phase=$phase worker=$wpid" >> "$LOGDIR/phase-claim.log" 2>/dev/null || true
      exec 9>&-
      exit 0 ;;

  release)
      wpid=$(find_worker_pid) || wpid="$$"
      exec 9>"$LOCK"
      flock -x 9
      holder=$(claim_holder "$CLAIM")
      if [ -n "${holder:-}" ] && [ "$holder" = "$wpid" ]; then
          rm -f "$CLAIM"
          echo "$(date -Is) RENDU phase=$phase worker=$wpid" >> "$LOGDIR/phase-claim.log" 2>/dev/null || true
      fi
      exec 9>&-
      exit 0 ;;

  *) echo "usage: phase_claim.sh {claim|release|status} <phase-id>" >&2; exit 2 ;;
esac
