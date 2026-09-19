#!/usr/bin/env bash
# lib/await.sh — ATTENDRE EN UN SEUL TOUR.
#
# POURQUOI (harness-main-agent-context-volume, 19/09). Un tour d'agent principal relit TOUT le
# contexte : 195 000 jetons en moyenne sur nos 278 essais opus-5. Attendre une construction ou
# une course de preuve par `sleep 20 ; tail ; pgrep` coute donc un contexte entier PAR COUP DE
# SONDE — et nos journaux en comptent 16,2 par essai, soit 20,2 % de l'integrale de contexte
# (sleep 9,27 % + tail de journal 7,73 % + pgrep/ps 3,17 %). En temps : 434,8 heures de sommeil
# declarees sur l'ensemble des journaux. Le sondage ne rapporte RIEN a l'agent : il n'apprend
# qu'a la fin. Ce script fait l'attente ICI, dans le shell, et ne rend la main qu'une fois.
#
# CE QU'IL GARANTIT :
#   - il BORNE (defaut 570 s, sous le plafond de l'outil Bash ; plafond dur 3600 s) ;
#   - il rend une sortie COURTE (dernieres lignes, plafonnees) : une attente ne doit pas
#     ajouter au contexte ce qu'elle vient d'economiser ;
#   - il publie `await_*` en `cle=valeur` : ce qu'il a attendu, combien de temps, s'il a abouti.
#     Un depassement de borne n'est PAS une erreur : l'agent rappelle, une fois.
#   - un PID mort depuis le debut rend 0 immediatement : « deja fini » n'est pas « jamais lance ».
#
# Usage :
#   lib/await.sh pid   <pid>        [--timeout S] [--log F] [--tail N]
#   lib/await.sh lock  <fichier>    [--timeout S] [--log F] [--tail N]   (lit `pid=` dedans)
#   lib/await.sh proof <id-d-item>  [--timeout S] [--tail N]
#
# Codes : 0 = la cible est finie. 3 = borne atteinte, la cible tourne encore. 2 = usage.
set -uo pipefail
export LC_ALL=C

MODE="${1:-}"; TARGET="${2:-}"; shift 2 2>/dev/null || true
TIMEOUT=570; LOG=""; TAILN=20
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="${2:-570}"; shift 2 ;;
    --log)     LOG="${2:-}";        shift 2 ;;
    --tail)    TAILN="${2:-20}";    shift 2 ;;
    *) shift ;;
  esac
done
case "$TIMEOUT" in ''|*[!0-9]*) TIMEOUT=570 ;; esac
[ "$TIMEOUT" -le 3600 ] || TIMEOUT=3600
[ "$TIMEOUT" -ge 1 ]    || TIMEOUT=1
case "$TAILN" in ''|*[!0-9]*) TAILN=20 ;; esac
[ "$TAILN" -le 200 ] || TAILN=200

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=.

pub(){ printf 'await_%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }
usage(){ printf 'lib/await.sh {pid|lock|proof} <cible> [--timeout S] [--log F] [--tail N]\n' >&2; exit 2; }

PID=""
case "$MODE" in
  pid)
    PID="$TARGET" ;;
  lock)
    [ -n "$TARGET" ] || usage
    [ -s "$TARGET" ] && PID=$(sed -n 's/.*[^a-z]pid=\([0-9][0-9]*\).*/\1/p' "$TARGET" | tail -1) ;;
  proof)
    [ -n "$TARGET" ] || usage
    D="$ROOT/.autoport/reports/$TARGET"
    # Le nom du verrou d'ecriture vient du nommeur, jamais d'un litteral (NOMMAGE/un-seul-endroit).
    WRN=$(cd "$ROOT" && python3 -c "import sys;sys.path.insert(0,'.autoport/lib');import impossible;print(impossible.arm_name('writer',''))" 2>/dev/null)
    [ -n "$WRN" ] || WRN=proof-run.lock
    [ -s "$D/$WRN" ] && PID=$(sed -n 's/.*[^a-z]pid=\([0-9][0-9]*\).*/\1/p' "$D/$WRN" | tail -1)
    [ -n "$LOG" ] || LOG="$D/proof-engine.log" ;;
  *) usage ;;
esac
case "${PID:-}" in ''|*[!0-9]*) PID="" ;; esac

pub mode "$MODE"
pub target "$TARGET"
pub pid "${PID:-absent}"

if [ -z "$PID" ]; then
  # RIEN A ATTENDRE N'EST PAS UNE PANNE, et ce n'est pas non plus « c'est fini » : on le NOMME.
  pub state "aucun-pid"
  pub waited_s 0
  pub finished 0
  [ -n "$LOG" ] && [ -s "$LOG" ] && { echo "--- ${LOG#"$ROOT/"} (dernieres $TAILN lignes) ---"; tail -n "$TAILN" "$LOG" | cut -c1-400; }
  exit 0
fi

# UN ZOMBIE A FINI DE TOURNER, ET `kill -0` REUSSIT ENCORE SUR LUI tant que son parent ne
# l'a pas moissonne. Une attente qui ne regarde que `kill -0` ne finit alors JAMAIS : mesure au
# banc, 61 s d'attente bornee sur un processus mort depuis 6. L'etat se lit dans /proc, et on
# saute par-dessus `comm` — un nom de commande peut contenir une parenthese ou un espace.
ZOMBIE=0
vivant(){
  kill -0 "$1" 2>/dev/null || return 1
  [ -r "/proc/$1/stat" ] || return 0
  local st; st=$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null); st=${st%% *}
  [ "$st" = Z ] && { ZOMBIE=1; return 1; }
  return 0
}

T0=$(date +%s)
if ! vivant "$PID"; then
  pub state "deja-fini"
else
  while vivant "$PID"; do
    [ $(( $(date +%s) - T0 )) -lt "$TIMEOUT" ] || break
    sleep 2
  done
  vivant "$PID" && pub state "borne-atteinte" || pub state "fini"
fi
WAITED=$(( $(date +%s) - T0 ))
pub waited_s "$WAITED"
if vivant "$PID"; then pub finished 0; RC=3; else pub finished 1; RC=0; fi
pub zombie "$ZOMBIE"
pub timeout_s "$TIMEOUT"

# LA SORTIE EST BORNEE. Une attente qui recrache 30 000 caracteres de journal rend au contexte
# ce qu'elle vient de lui economiser : N lignes, 400 caracteres chacune au plus.
if [ -n "$LOG" ] && [ -s "$LOG" ]; then
  echo "--- ${LOG#"$ROOT/"} (dernieres $TAILN lignes) ---"
  tail -n "$TAILN" "$LOG" | cut -c1-400
fi
exit "$RC"
