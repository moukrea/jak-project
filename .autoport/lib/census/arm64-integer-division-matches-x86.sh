#!/usr/bin/env bash
# census/arm64-integer-division-matches-x86.sh — publie le terme de porte
# `int_div_arm64_x86_mismatch` de l'item arm64-integer-division-matches-x86.
#
# CE QUE LE MOTEUR NE PEUT PAS DIRE. Le detecteur (game/system/codegen_arm64_scalar.h)
# ne voit dans le code LIE que « la forme 32 bits est presente », jamais si elle rend le MEME
# nombre que la division 32 bits x86 sur toutes les entrees — il faudrait executer les deux
# cotes sur un large echantillon, et une course de jeu ne rencontre les diviseurs qu'au gre du
# script.
#
# CE QUE CE CROCHET FAIT. Il lance .autoport/tests/int_div_parity/run.sh qemu : le vrai
# emetteur x86 (IGenX86.cpp) construit les noyaux idiv/udiv/imod/umod 32 bits et les execute
# nativement sur l'hote pour verite ; le vrai emetteur arm64 (IGenARM64.cpp, int_div_w) et
# l'ancienne sequence 64 bits (int_div_x, rejouee localement comme temoin que le banc voit
# reellement le defaut) sont executes sous qemu-user sur les memes paires.
#
# POURQUOI LA SENTINELLE. `lib/proof_run.sh` garde la DERNIERE valeur de chaque cle ; la cle
# de porte doit sortir en dernier. Illisible ou bras desarme = 255, jamais un vert muet.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

D="${AUTOPORT_CENSUS_DIR:?AUTOPORT_CENSUS_DIR manquant}"
ARMED="${AUTOPORT_CENSUS_ARMED:-1}"

OUT="$D/int-div-parity.log"
ERR="$D/int-div-parity.err"

kv() { grep -aE "^$1=" "$OUT" 2>/dev/null | tail -1 | cut -d= -f2-; }

gate() {  # <valeur> <etat>
  echo "int_div_census_state=$2"
  echo "int_div_arm64_x86_mismatch=$1"
}

if [ "$ARMED" != 1 ]; then
  : > "$OUT" 2>/dev/null || true
  gate 255 bras-desarme
  exit 0
fi

bash .autoport/tests/int_div_parity/run.sh qemu > "$OUT" 2> "$ERR"
RC=$?
echo "int_div_parity_rc=$RC"

# Les cles du test, telles quelles.
grep -aE '^int_div_[a-z0-9_]+=[^ ]*$' "$OUT" 2>/dev/null

CALL_SITES=$(grep -c 'ARM64::int_div_w(' goalc/compiler/IR.cpp 2>/dev/null || echo 0)
echo "int_div_ir_call_sites=$CALL_SITES"

mismatch=$(kv int_div_arm64_x86_mismatch)
compared=$(kv int_div_arm64_x86_compared)
pairs=$(kv int_div_pairs)
done_flag=$(kv int_div_runner_done)
traps_other=$(kv int_div_x86_traps_other)
variant_disagree=$(kv int_div_x86_variant_disagree)
bad_signal=$(kv int_div_arm64_bad_signal)
before_mismatch=$(kv int_div_before_arm64_x86_mismatch)

reason=""
[ "$RC" = 0 ] || reason="rc-non-nul"
[ -n "$reason" ] || { [ "$done_flag" = 1 ] || reason="runner-inacheve"; }
[ -n "$reason" ] || { [ -n "$pairs" ] && [ "$pairs" != 0 ] || reason="pairs-vide"; }
[ -n "$reason" ] || { [ -n "$compared" ] && [ "$compared" != 0 ] || reason="compared-vide"; }
[ -n "$reason" ] || { [ "${traps_other:-0}" = 0 ] || reason="traps-autres"; }
[ -n "$reason" ] || { [ "${variant_disagree:-0}" = 0 ] || reason="variantes-x86-en-desaccord"; }
[ -n "$reason" ] || { [ "${bad_signal:-0}" = 0 ] || reason="signal-inattendu-arm64"; }
[ -n "$reason" ] || { [ -n "$before_mismatch" ] && [ "$before_mismatch" != 0 ] || reason="banc-aveugle"; }
[ -n "$reason" ] || { [ "$CALL_SITES" = 1 ] || reason="site-appel-ir-inattendu"; }
[ -n "$reason" ] || { [ -n "$mismatch" ] || reason="mismatch-illisible"; }

if [ -n "$reason" ]; then
  gate 255 "$reason"
else
  gate "$mismatch" ok
fi
exit 0
