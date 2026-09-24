#!/usr/bin/env bash
# census/harness-linear-watch-comment-matches-its-period.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Il n'ecrit aucun champ de proof.txt.
#
# CE QU'IL MESURE : l'ecart entre la periode que `linear_watch.sh` ANNONCE (toute occurrence de
# « toutes les <N|$VAR> <unite> » dans son texte : commentaires et ligne de journal) et celle qu'il
# EXECUTE. La periode executee n'est pas lue dans le source : le script est LANCE dans un bac a sable
# jetable, `python3` et `sleep` remplaces par des temoins ; le temoin `sleep` consigne l'argument
# qu'il a recu, puis arrete la veille. C'est la trace d'execution qui fait foi.
#
# INCONNU = DEFAUT : aucune annonce, annonce non resolue, aucun `sleep` execute -> +1 chacun.
# CONTROLES (sur des copies, jamais sur le vrai fichier) :
#   pos_hist  le script du commit dc7eb801a7 (« 5 min » annonce, `sleep 30`) : doit rougir et nommer.
#   pos_seed  le script courant ou le `sleep` est remplace par un litteral different : doit rougir.
#   neg       copie du script courant : doit rendre 0.
# Un controle qui ne se comporte pas comme attendu est un instrument AVEUGLE : il s'ajoute au compte.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "linear_watch_period_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
REAL="$AP/linear_watch.sh"
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

# mesure <nom> <script> -> imprime « <nom>_mismatch=… <nom>_announced=… … »
mesure() {
  local nom=$1 src=$2 box="$T/$1"
  mkdir -p "$box/.autoport/logs" "$box/bin"
  cp "$src" "$box/.autoport/linear_watch.sh"
  printf '#!/bin/sh\nexit 0\n' > "$box/bin/python3"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/sleep.args"\nkill -TERM "$PPID"\nexit 0\n' "$box" > "$box/bin/sleep"
  chmod +x "$box/bin/python3" "$box/bin/sleep"
  ( cd "$box" && env -u LINEAR_WATCH_PERIOD_S PATH="$box/bin:$PATH" \
      timeout -k 2 20 bash .autoport/linear_watch.sh >/dev/null 2>&1 ) || true
  python3 - "$nom" "$box/.autoport/linear_watch.sh" "$box/sleep.args" "$(basename "$src")" <<'PY'
import re, sys
nom, script, args_path, label = sys.argv[1:5]
UNIT = {'s': 1, 'sec': 1, 'seconde': 1, 'secondes': 1, 'min': 60, 'minute': 60, 'minutes': 60,
        'h': 3600, 'heure': 3600, 'heures': 3600}
def secs(tok):
    m = re.fullmatch(r'(\d+(?:\.\d+)?)([smhd]?)', tok.strip())
    if not m: return None
    return float(m.group(1)) * {'': 1, 's': 1, 'm': 60, 'h': 3600, 'd': 86400}[m.group(2)]
lines = open(script, errors='replace').read().splitlines()
var = {}
for l in lines:
    m = re.match(r'\s*(?:export\s+)?([A-Za-z_]\w*)=["\']?(?:\$\{\w+:-)?(\d+)', l)
    if m: var[m.group(1)] = float(m.group(2))
try:
    runs = [a for a in open(args_path).read().split('\n') if a.strip()]
except OSError:
    runs = []
executed = secs(runs[0]) if runs else None
annonces, defauts = [], []
for i, l in enumerate(lines, 1):
    for m in re.finditer(r'toutes les\s+(\$\{?(\w+)\}?|\d+(?:[.,]\d+)?)\s*([A-Za-z]+)?', l):
        n = var.get(m.group(2)) if m.group(2) else float(m.group(1).replace(',', '.'))
        u = UNIT.get((m.group(3) or 's').lower())
        if n is None or u is None:
            defauts.append(f'{label}:{i}:annonce_non_resolue:{m.group(0).strip()}'); continue
        annonces.append((i, n * u))
if not annonces: defauts.append(f'{label}:aucune_annonce')
if executed is None: defauts.append(f'{label}:aucun_sleep_execute')
else:
    for i, a in annonces:
        if a != executed:
            defauts.append(f'{label}:{i}:annonce={a:g}s:execute={executed:g}s')
fmt = lambda v: '-' if v is None else f'{v:g}'
print(f'{nom}_mismatch={len(defauts)}')
print(f'{nom}_announcements={len(annonces)}')
print(f'{nom}_announced_s={",".join(fmt(a) for _, a in annonces) or "-"}')
print(f'{nom}_executed_s={fmt(executed)}')
print(f'{nom}_sleep_calls={len(runs)}')
print(f'{nom}_culprit={";".join(defauts) or "-"}')
PY
}

get() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p" | tail -1; }

git -C "$ROOT" show dc7eb801a7:.autoport/linear_watch.sh > "$T/linear_watch.hist.sh" 2>/dev/null
sed -E 's/^([[:space:]]*sleep)[[:space:]].*$/\1 7/' "$REAL" > "$T/linear_watch.seed.sh"
cp "$REAL" "$T/linear_watch.neg.sh"

OUT=$( mesure lw "$REAL"; mesure ctl_pos_hist "$T/linear_watch.hist.sh"
       mesure ctl_pos_seed "$T/linear_watch.seed.sh"; mesure ctl_neg "$T/linear_watch.neg.sh" )
printf '%s\n' "$OUT" | sed 's/^/linear_watch_period_/'

blind=0; blind_why=
chk() { # <nom> <attendu: rouge|zero>
  local v; v=$(get "$1_mismatch")
  case "$2:$v" in
    rouge:[1-9]*|zero:0) ;;
    *) blind=$((blind + 1)); blind_why="${blind_why}$1:attendu_$2:obtenu_${v:-absent};" ;;
  esac
}
chk ctl_pos_hist rouge; chk ctl_pos_seed rouge; chk ctl_neg zero
main=$(get lw_mismatch); case "$main" in ''|*[!0-9]*) main=1 ;; esac

echo "linear_watch_period_controls=3"
echo "linear_watch_period_controls_blind=$blind"
echo "linear_watch_period_controls_blind_why=${blind_why:--}"
echo "linear_watch_period_mismatch=$((main + blind))"
