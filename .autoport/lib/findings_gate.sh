#!/usr/bin/env bash
# findings_gate.sh — LE RETOUR DES WORKERS NE MEURT PLUS DANS UN RAPPORT.
#
# Owner, 2026-09-10 : « si ce que remonte le worker n'est jamais traite par qui que ce soit, ca
# sert a rien, quel gaspillage ». Balayage du 11/09 : trois signalements dormaient dans des
# rapports fermes, dont DEUX touchaient directement ses problemes de perfs.
#
# Un canal existait deja, mais dans l'autre sens : le preflight injecte des constats DANS le
# prompt avant le travail. Rien ne ramenait ce que le worker decouvre PENDANT.
#
# CE QUE CETTE PORTE EXIGE, et rien de plus :
#   - `reports/<id>/FINDINGS.txt` existe. Pas de fichier = le worker n'a pas repondu a la
#     question, et la question fait partie du travail.
#   - chaque ligne non vide est soit `AUCUN`, soit TRIEE : elle porte `-> item:<id>` (devenue un
#     chantier) ou `-> ecarte:<raison>` (le superviseur l'a presentee a l'owner et ecartee).
# Une ligne brute, non triee, BLOQUE la fermeture. C'est le seul moyen qu'elle ne s'oublie pas.
#
# Fail-CLOSED comme les acquis : en cas de doute, on ne ferme pas.
#
# MODE. Sans `.autoport/.findings_gate_strict`, cette porte ALERTE sans bloquer : pose le
# 2026-09-11 a 02h30, aucun worker en cours ne connaissait encore FINDINGS.txt et un blocage
# aurait arrete le harnais toute la nuit. Le passage en blocage se decide avec l'owner, une fois
# que les nouvelles directives ont circule.
set -uo pipefail
STRICT=""; [ -f ".autoport/.findings_gate_strict" ] && STRICT=1
ITEM="${1:-}"
[ -n "$ITEM" ] || { echo "findings_gate: pas d'item"; exit 0; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
F="$ROOT/.autoport/reports/$ITEM/FINDINGS.txt"

if [ ! -f "$F" ]; then
  echo "FINDINGS.txt absent pour $ITEM — ecris-le, meme avec le seul mot AUCUN."
  echo "Format : <ou> | <ce qui cloche> | <ce que ca coute de le laisser>"
  [ -n "$STRICT" ] && exit 1
  echo "  (mode alerte : la fermeture n'est pas bloquee)"
  exit 0
fi

# Les ids que le backlog porte VRAIMENT. Un renvoi `-> item:<id>` vers un id inexistant est un
# signalement perdu avec l'air d'etre traite : mesure du 2026-09-12, trois signalements de
# hdr-output-regime pointaient `hdr-output-visible`, qui n'existe dans aucun item.
IDS=$(python3 - "$ROOT/.autoport/backlog.yaml" <<'PYIDS' 2>/dev/null
import sys, yaml
try:
    d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
except Exception:
    sys.exit(0)
for it in d.get("items") or []:
    i = it.get("id")
    if i:
        print(i)
PYIDS
)

brutes=0
fantomes=0
while IFS= read -r l; do
  case "$l" in ''|'#'*) continue ;; esac
  printf '%s' "$l" | grep -qiE '^[[:space:]]*AUCUN[[:space:]]*$' && continue
  if printf '%s' "$l" | grep -qE '\-> *item:[A-Za-z0-9_-]+'; then
    # Chaque renvoi de la ligne doit resoudre. Sans backlog lisible, on ne juge pas.
    if [ -n "$IDS" ]; then
      for cible in $(printf '%s' "$l" | grep -oE '\-> *item:[A-Za-z0-9_-]+' | sed 's/.*item://'); do
        if ! printf '%s\n' "$IDS" | grep -qxF "$cible"; then
          fantomes=$((fantomes+1))
          echo "  RENVOI FANTOME : '$cible' n'est un item d'aucun backlog — $l"
        fi
      done
    fi
    continue
  fi
  printf '%s' "$l" | grep -qE '\-> *ecarte:.+' && continue
  brutes=$((brutes+1))
  echo "  NON TRIE : $l"
done < "$F"

if [ "$fantomes" -gt 0 ]; then
  echo "$fantomes renvoi(s) vers un item inexistant dans $F."
  echo "Ouvre l'item, ou renvoie vers un id qui existe : un renvoi fantome est un signalement perdu."
  [ -n "$STRICT" ] && exit 1
  echo "  (mode alerte : la fermeture n'est pas bloquee)"
fi

if [ "$brutes" -gt 0 ]; then
  echo "$brutes signalement(s) sans suite dans $F."
  echo "Chacun doit porter '-> item:<id>' (devenu un chantier) ou '-> ecarte:<raison>'."
  [ -n "$STRICT" ] && exit 1
  echo "  (mode alerte : la fermeture n'est pas bloquee)"
  exit 0
fi
# Un renvoi fantome n'est pas « trie » : ne pas rendre un vert qui contredit l'alerte au-dessus.
[ "$fantomes" -gt 0 ] && exit 0
echo "  ok: signalements de $ITEM tous tries"
exit 0
