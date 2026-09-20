#!/usr/bin/env bash
# lib/proof_inflight.sh — QUELLE COURSE DE PREUVE ECRIT EN CE MOMENT, LU SUR UNE DONNEE.
#
# POURQUOI CE FICHIER EXISTE (harness-judge-binary-race-with-builder, 2026-09-20).
# `auto_build_apk.sh` cherchait les courses de preuve par MOTIF DE LIGNE DE COMMANDE
# (`ps | awk '/[p]roof_run\.sh/'`). C'est le defaut deja paye le 12/09 sur le demon Gradle : un
# shell qui NOMME le motif se matche lui-meme, et un `proof_run.sh` dont la ligne de commande ne
# porte pas le motif attendu est invisible. Pire, la garde n'etait qu'un age (`etimes < 2400`) :
# une course plus longue que 40 min n'existait plus pour elle, et le chemin « patience depassee »
# n'en tenait aucun compte. Le 20/09, le constructeur a lance un build PENDANT une course.
#
# LA DONNEE, ELLE, EXISTE : chaque course pose `reports/<id>/proof<suf>-writer.lock` avec son pid
# et son instant de demarrage. C'est le SEUL canal qu'une course ne peut pas ne pas ecrire, et
# c'est celui que lit le balayage d'orphelins. On le lit ici aussi, avec la garde pid+starttime
# de `lib/pidguard.sh` — un numero recycle n'est pas une course.
#
# Usage :  lib/proof_inflight.sh list   -> une ligne `<id> <bras> <pid>` par course en vol
#          lib/proof_inflight.sh pid    -> le pid de la premiere course en vol, ou rien
#          lib/proof_inflight.sh count  -> combien
# Codes : 0 = au moins une course en vol. 1 = aucune. 2 = usage.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "proof_inflight: pas dans un depot git" >&2; exit 2; }
cd "$ROOT" || exit 2
AP=.autoport
# shellcheck source=/dev/null
. "$AP/lib/pidguard.sh"

# LES NOMS DES VERROUS SORTENT DE L'AUTORITE (NOMMAGE/un-seul-endroit) : un litteral recopie ici
# ne trouverait plus rien le jour ou le nom bouge, et « aucun verrou » se lit « rien en vol ».
NOMS=$(python3 - <<'PY' 2>/dev/null
import sys
sys.path.insert(0, '.autoport/lib')
import impossible
print(" ".join(impossible.arm_name('writer', s) for s in ('', '-off')))
PY
)
[ -n "$NOMS" ] || NOMS="proof-writer.lock proof-off-writer.lock"

lister(){
  local d id n f arm
  for d in "$AP"/reports/*/; do
    [ -d "$d" ] || continue
    id=$(basename "$d")
    for n in $NOMS; do
      f="$d$n"
      [ -s "$f" ] || continue
      pg_lock_holder "$f" >/dev/null || continue
      arm=$(sed -n 's/^arm=//p' "$f" | tail -1); [ -n "$arm" ] || arm=livre
      printf '%s %s %s\n' "$id" "$arm" "$(sed -n 's/^pid=\([0-9][0-9]*\).*/\1/p' "$f" | tail -1)"
    done
  done
}

case "${1:-list}" in
  list)  OUT=$(lister); [ -n "$OUT" ] && printf '%s\n' "$OUT"; [ -n "$OUT" ] ;;
  pid)   OUT=$(lister); [ -n "$OUT" ] && printf '%s\n' "$OUT" | head -1 | awk '{print $3}'; [ -n "$OUT" ] ;;
  count) OUT=$(lister); printf '%s\n' "$(printf '%s' "$OUT" | grep -c .)"; [ -n "$OUT" ] ;;
  *) echo "usage: lib/proof_inflight.sh {list|pid|count}" >&2; exit 2 ;;
esac
