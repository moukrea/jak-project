#!/usr/bin/env bash
# census/perf-codegen-arm64-scalar.sh — AJOUTE LE TERME DE PARITE A `codegen_lot_defects`.
#
# CE QUE LE MOTEUR NE PEUT PAS DIRE. Le moteur (game/system/perf_instruments.cpp,
# publish_codegen_scalar) lit le code LIE sur l'appareil : les nouvelles sequences float->int,
# division et swizzle y sont, les anciennes n'y sont plus, et le jeu a tenu 600 images. Il ne
# peut pas dire que les nouvelles sequences rendent le MEME nombre que les anciennes : il
# faudrait les executer sur toutes les entrees, et la course ne les rencontre qu'au gre du jeu.
#
# CE QUE CE CROCHET FAIT. Apres la course, sur le MEME telephone, il lance
# `.autoport/tests/codegen_scalar/run.sh device <serie>` : les sequences emises par l'emetteur
# de l'arbre (le meme IGenARM64.cpp que le goalc qui a bati les CGO), ET les sequences qu'elles
# remplacent, sont executees par le processeur de l'appareil — float->int sur les 2^32 entrees
# contre le modele x86 (lui-meme verifie contre la vraie instruction cvttss2si sur l'hote),
# division sur ses bornes contre l'ancienne sequence, swizzle et pshuf sur leurs 256 motifs.
# Le moindre ecart, un test qui ne va pas au bout, ou un test lance ailleurs que sur
# l'appareil = `codegen_defect_parity=1`.
#
# POURQUOI LA SOMME SORT D'ICI. `lib/proof_run.sh` garde la DERNIERE valeur de chaque cle, et
# le recensement est ajoute APRES le journal moteur : c'est cette somme-la que porte proof.txt.
# Illisible = 255, une sentinelle nommee, jamais un vert.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

D="${AUTOPORT_CENSUS_DIR:?AUTOPORT_CENSUS_DIR manquant}"
ARMED="${AUTOPORT_CENSUS_ARMED:-1}"

eval "$(python3 - <<'PY'
import sys
sys.path.insert(0, '.autoport/lib')
import impossible as I
q = lambda s: "'" + str(s).replace("'", "'\\''") + "'"
print("N_ENG=%s" % q(I.arm_name('engine', '')))
PY
)"

# Derniere occurrence d'une cle. Journal appareil = logcat : la cle suit un prefixe, jamais `^`.
# `grep -c`/`tail` plutot que `grep -q` : sous pipefail, `-q` rend 141 sur un gros fichier.
last_key() {  # <fichier> <cle>
  [ -s "$1" ] || return 1
  local v
  v=$(grep -aoE "(^|[^A-Za-z0-9_])$2=[0-9]+" "$1" | tail -1 | sed 's/.*=//')
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

verdict() {  # <defaut_de_parite 0|1>
  local eng
  eng=$(last_key "$D/${N_ENG:-}" codegen_lot_defects || true)
  echo "codegen_defect_parity=$1"
  if [ -z "${eng:-}" ]; then
    echo "codegen_lot_defects_engine=-"
    echo "codegen_lot_defects=255"
  else
    echo "codegen_lot_defects_engine=$eng"
    echo "codegen_lot_defects=$(( eng + $1 ))"
  fi
}

if [ "$ARMED" != 1 ]; then
  echo "codegen_parity_state=bras-desarme"
  verdict 1
  exit 0
fi

SERIAL="${ANDROID_SERIAL:-}"
[ -n "$SERIAL" ] || SERIAL=$(bash .autoport/lib/pick_device.sh 2>/dev/null | head -1 | tr -d '[:space:]')
case "$SERIAL" in
  "") echo "codegen_parity_state=appareil-absent"; verdict 1; exit 0 ;;
  *:*) echo "codegen_parity_state=appareil-reseau-interdit"; verdict 1; exit 0 ;;
esac

OUT="$D/codegen-parity.log"
bash .autoport/tests/codegen_scalar/run.sh device "$SERIAL" > "$OUT" 2> "$D/codegen-parity.err"
RC=$?
echo "codegen_parity_rc=$RC"
# Les cles du test, telles quelles : elles ne portent aucun nom reserve a la machine.
grep -aE '^(parity|host|gen)_[a-z0-9_]+=[^ ]*$' "$OUT" 2>/dev/null

kv() { grep -aE "^$1=" "$OUT" 2>/dev/null | tail -1 | cut -d= -f2-; }
bad=0
[ "$RC" = 0 ] || bad=1
[ "$(kv parity_done)" = 1 ] || bad=1
[ "$(kv parity_mode)" = device ] || bad=1
[ "$(kv parity_total_bad)" = 0 ] || bad=1
[ "$(kv host_f2i_model_mismatches)" = 0 ] || bad=1
[ "$(kv host_matcher_defects)" = 0 ] || bad=1
stride=$(kv parity_f2i_sweep_stride); [ -z "$stride" ] || [ "$stride" = 1 ] || bad=1
# Le balayage doit couvrir les 2^32 motifs : le 25/09, un fil finissait a (uint32_t)2^32 = 0
# et le dernier quart (negatifs <= -2, -Inf, NaN negatifs) n'etait jamais execute.
[ "$(kv parity_f2i_sweep_cases)" = 4294967296 ] || bad=1
echo "codegen_parity_state=$([ "$bad" = 0 ] && echo ok || echo defaut)"
verdict "$bad"
exit 0
