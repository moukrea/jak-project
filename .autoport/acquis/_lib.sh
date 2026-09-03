#!/usr/bin/env bash
# acquis/_lib.sh — SOCLE COMMUN DES ACQUIS. Ce fichier n'est pas un acquis : l'orchestrateur
# lance tous les `acquis/*.sh`, donc lance aussi celui-ci, et il doit alors ne rien faire.
[ "${BASH_SOURCE[0]}" = "$0" ] && exit 0

# ------------------------------------------------------------------------------------------
# CE QUE GARANTIT CE SOCLE
#
# 1. UNE SEULE COURSE gk POUR PLUSIEURS ACQUIS. Six gardes qui bootent chacune le jeu, c'est
#    dix minutes a chaque fermeture. Les courses sont donc MISES EN CACHE par « tag » (le jeu
#    d'options qui les distingue). Le cache est INVALIDE des que le gk change de sha ou qu'une
#    source moteur est plus recente que le journal : une garde qui juge la course d'hier ne
#    garde rien.
# 2. UN ACCIDENT NE BLOQUE JAMAIS TOUTES LES PHASES. La porte des acquis est fail-CLOSED cote
#    orchestrateur : un `exit 1` bloque la fermeture de N'IMPORTE QUELLE phase. Donc ici, seule
#    une CONTRADICTION MESUREE rend 1 (`acq_broken`). Tout le reste — pas d'ecran, pas de gk,
#    build en cours, instrument jamais atteint — rend 0 en disant `ACQUIS UNPROVABLE`.
# 3. AUCUNE GARDE NE LIT UN RAPPORT. Elles lisent la sortie du MOTEUR, et rien d'autre.
#
# LIMITE ASSUMEE : la jambe est x86. Les instruments de ces six features partent dans logcat
# sur l'appareil, ce qui demande une capture vivante de plusieurs minutes — trop cher pour une
# porte de fermeture. Une regression propre a l'ARM64 n'est donc PAS couverte par ces gardes.
# ------------------------------------------------------------------------------------------
set -uo pipefail
ACQ_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$ACQ_ROOT" || exit 0
ACQ_NAME="${ACQ_NAME:-$(basename "${0%.sh}")}"
ACQ_CACHE=.autoport/reports/_acquis
ACQ_GK=build/game/gk
ACQ_TTL="${ACQ_CACHE_TTL:-1800}"

acq_ok(){         printf '[acquis/%s] TENU : %s\n' "$ACQ_NAME" "$*"; exit 0; }
acq_unprovable(){ printf 'ACQUIS UNPROVABLE %s — %s\n' "$ACQ_NAME" "$*"; exit 0; }
acq_broken(){     printf '[acquis/%s] PLUS TENU : %s\n' "$ACQ_NAME" "$*" >&2; exit 1; }

# La sortie de gk est prefixee du temps ecoule (`    4.423 CINEVP ...`). Ancrer sur `^` sans
# enlever ce prefixe, c'est ne rien trouver, jamais.
# gk prefixe : temps ecoule, puis pour lg::info une horloge et un niveau.
#   `   63.722 [24:05:634] [info] [recharged-grass] PLACE-TIME ...`
# Les gardes matchent donc l'ETIQUETTE, jamais `^`.
acq_norm(){ sed -E 's/\r$//; s/^[[:space:]]*[0-9]+\.[0-9]+[[:space:]]+//; s/^\[[0-9:]+\] \[[a-z]+\] //' "$1"; }

# Un build qui reecrit out/jak1/iso/ tue gk en SIGILL sur un CGO a moitie ecrit. Ce n'est pas
# un defaut du jeu : on ne mesure pas, et on ne bloque personne.
acq_build_busy(){
  local p f=.autoport/.deploy-in-progress pat age
  if [ -f "$f" ]; then
    p=$(sed -n 's/.*pid=\([0-9]\{1,\}\).*/\1/p' "$f" | head -1)
    [ -n "${p:-}" ] && kill -0 "$p" 2>/dev/null && { echo "un build tourne (pid=$p)"; return 0; }
  fi
  for pat in '[g]radle' '[n]inja' '[g]oalc'; do
    pgrep -f "$pat" >/dev/null 2>&1 && { echo "un build tourne ($pat)"; return 0; }
  done
  if [ -f out/jak1/iso/GAME.CGO ]; then
    age=$(( $(date +%s) - $(stat -c %Y out/jak1/iso/GAME.CGO 2>/dev/null || echo 0) ))
    [ "$age" -lt 60 ] && { echo "GAME.CGO reecrit il y a ${age}s"; return 0; }
  fi
  return 1
}

# acq_x86_log <tag> <timeout_s> [VAR=VALEUR ...]
# Ecrit le chemin du journal sur stdout et rend 0, ou rend 1 (rien de mesurable).
acq_x86_log(){
  local tag="$1" to="$2"; shift 2
  local log="$ACQ_CACHE/$tag.log" stamp="$ACQ_CACHE/$tag.stamp" sig sha now age neuf
  mkdir -p "$ACQ_CACHE" || return 1
  [ -x "$ACQ_GK" ] || return 1
  sha=$(sha256sum "$ACQ_GK" | cut -c1-16)
  sig="$sha|${ACQ_GK_ARGS:---portable}|$*"
  if [ -s "$log" ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$sig" ]; then
    now=$(date +%s); age=$(( now - $(stat -c %Y "$log" 2>/dev/null || echo 0) ))
    neuf=$(find game common goal_src -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.gc' \) -newer "$log" -print -quit 2>/dev/null)
    if [ "$age" -lt "$ACQ_TTL" ] && [ -z "$neuf" ]; then printf '%s\n' "$log"; return 0; fi
  fi
  acq_build_busy >/dev/null && return 1
  export DISPLAY="${DISPLAY:-:0}"
  if [ -z "${XAUTHORITY:-}" ]; then
    for x in /run/user/"$(id -u)"/.mutter-Xwaylandauth.*; do [ -e "$x" ] && export XAUTHORITY="$x"; done
  fi
  export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
  # stdbuf : une sortie redirigee est bufferisee par BLOCS — 70 lignes produites, 0 comptees.
  # ACQ_GK_ARGS permet a une garde de remplacer `--portable` (par exemple par un
  # `--config-path` jetable) SANS jamais toucher le settings.ini de l'owner.
  local -a gkargs=(${ACQ_GK_ARGS:---portable})
  stdbuf -oL -eL timeout -k 5 "$to" env "$@" "$ACQ_GK" \
      --game jak1 "${gkargs[@]}" -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso \
      -- -boot -debug-mem > "$log" 2>&1
  [ -s "$log" ] || return 1
  printf '%s\n' "$sig" > "$stamp"
  printf '%s\n' "$log"
}

# acq_reach <journal_normalise> <motif> : le point de repere qui distingue « la garde a
# regarde et le defaut est la » de « la garde n'a jamais atteint son instrument ».
acq_reach(){ grep -qaE "$2" "$1"; }
