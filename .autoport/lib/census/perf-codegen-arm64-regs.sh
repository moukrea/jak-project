#!/usr/bin/env bash
# census/perf-codegen-arm64-regs.sh — AJOUTE LES TERMES QUE LE MOTEUR NE PEUT PAS DIRE A
# `codegen_lot_defects`.
#
# CE QUE LE MOTEUR DIT DEJA. `game/system/perf_instruments.cpp::publish_codegen_regs` lit le
# code LIE sur l'appareil, apres 600 images : un compte > 0 sur X19-X28/V3-V15 (jamais ouverts
# avant cet item) prouve que le nouveau CGO est bien celui qui tourne, et `codegen_regs_x18`
# > 0 est deja un defaut de site cote moteur.
#
# CE QUE CE CROCHET AJOUTE. `.autoport/tests/codegen_regs/run.sh` desassemble, sur le MEME
# arbre, les fonctions des objets du paquet livre (`jak1_cgo.zip`) qui correspondent
# (meme FNV-1a64) au dump que goalc ecrit dans `out/jak1/codegen-regs/` : une analyse de flot
# MUST verifie qu'aucune lecture d'un registre neuf ne precede son ecriture sur tous les
# chemins, que la liste declaree par le compilateur correspond a ce que le code reference
# reellement, que X18 n'est jamais touche, et que les compteurs de debordement diminuent. Il
# compte aussi, cote hote, avec le MEME en-tete que le moteur, les registres neufs des
# fonctions ENGINE/GAME de segment principal, pour les comparer aux comptes de l'appareil.
#
# POURQUOI LA SOMME SORT D'ICI. `lib/proof_run.sh` garde la DERNIERE valeur de chaque cle, et
# ce recensement est ajoute APRES le journal moteur : c'est cette somme-la que porte
# proof.txt. Illisible = 255, une sentinelle nommee, jamais un vert.
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

# Derniere occurrence d'une cle. `grep -c`/`tail` plutot que `grep -q` : sous pipefail, `-q`
# rend 141 sur un gros fichier (voir MEMORY, feedback_grep_q_under_pipefail...).
last_key() {  # <fichier> <cle>
  [ -s "$1" ] || return 1
  local v
  v=$(grep -aoE "(^|[^A-Za-z0-9_])$2=[0-9]+" "$1" | tail -1 | sed 's/.*=//')
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

verdict() {  # <defaut_verify> <defaut_pack> <defaut_spills> <defaut_device_sites>
  local eng sum=$(( $1 + $2 + $3 + $4 ))
  eng=$(last_key "$D/${N_ENG:-}" codegen_lot_defects || true)
  echo "codegen_lot_defects_engine=${eng:--}"
  if [ -z "${eng:-}" ]; then
    echo "codegen_lot_defects=255"
  else
    echo "codegen_lot_defects=$(( eng + sum ))"
  fi
}

if [ "$ARMED" != 1 ]; then
  echo "codegen_regs_state=bras-desarme"
  verdict 1 1 1 1
  exit 0
fi

OUT="$D/codegen-regs.log"
bash .autoport/tests/codegen_regs/run.sh > "$OUT" 2> "$D/codegen-regs.err"
RC=$?
echo "codegen_regs_rc=$RC"
grep -aE '^regs_[a-z0-9_]+=[^ ]*$' "$OUT" 2>/dev/null

kv() { grep -aE "^$1=" "$OUT" 2>/dev/null | tail -1 | cut -d= -f2-; }

# Un chiffre ABSENT est un defaut, jamais un vert par defaut : `pos` exige un entier > 0.
pos() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -gt 0 ]; }
zero() { [ "${1:-x}" = 0 ]; }

# Le verificateur est lui-meme verifie : ses cas synthetiques (branche conditionnelle, boucle,
# appel, idiome EOR, insertion de voie, variable indefinie) doivent tous rendre le bon compte.
SELF=$(python3 .autoport/tests/codegen_regs/selftest.py 2>&1 | tail -1)
echo "codegen_regs_selftest=${SELF#selftest=}"

defect_verify=0
[ "$RC" = 0 ] || defect_verify=1
[ "$SELF" = "selftest=ok" ] || defect_verify=1
[ "$(kv regs_done)" = 1 ] || defect_verify=1
pos "$(kv regs_functions_checked)" || defect_verify=1
pos "$(kv regs_functions_using_new)" || defect_verify=1
zero "$(kv regs_violations)" || defect_verify=1
zero "$(kv regs_undeclared)" || defect_verify=1
zero "$(kv regs_x18)" || defect_verify=1
zero "$(kv regs_host_x18)" || defect_verify=1

defect_pack=0
zero "$(kv regs_stale)" || defect_pack=1
en_matched="$(kv regs_engine_game_matched)"
en_objects="$(kv regs_engine_game_objects)"
pos "$en_matched" || defect_pack=1
[ "$en_matched" = "$en_objects" ] || defect_pack=1
zero "$(kv regs_legacy_objects)" || defect_pack=1

defect_spills=0
sb="$(kv regs_spills_before)"; sa="$(kv regs_spills_after)"
if ! pos "$sb" || ! { pos "$sa" || zero "$sa"; } || [ "$sa" -ge "$sb" ]; then
  defect_spills=1
fi
# Aucune fonction ne doit spiller PLUS qu'avant : les registres neufs s'ajoutent, ils ne retirent rien.
zero "$(kv regs_functions_more_spills)" || defect_spills=1

# Le moteur a deja tranche `codegen_defect_sites` (voir publish_codegen_regs), mais il ne
# peut pas comparer a ce que l'hote trouve dans les MEMES octets : le crochet le fait ici.
defect_device_sites=0
eng_gpr=$(last_key "$D/${N_ENG:-}" codegen_regs_gpr_new || true)
eng_v=$(last_key "$D/${N_ENG:-}" codegen_regs_v_new || true)
host_gpr="$(kv regs_host_gpr_new)"
host_v="$(kv regs_host_v_new)"
echo "codegen_regs_device_gpr_new=${eng_gpr:--}"
echo "codegen_regs_device_v_new=${eng_v:--}"
# L'appareil lit le code LIE du tas global, qui porte aussi des donnees : il peut compter PLUS
# que l'hote, jamais moins. Moins = une partie du code de cet item n'est pas sur le telephone.
if ! pos "${host_gpr:-}" || ! pos "${host_v:-}" || ! pos "${eng_gpr:-}" || ! pos "${eng_v:-}"; then
  defect_device_sites=1
elif [ "$eng_gpr" -lt "$host_gpr" ] || [ "$eng_v" -lt "$host_v" ]; then
  defect_device_sites=1
fi

echo "codegen_defect_verify=$defect_verify"
echo "codegen_defect_pack=$defect_pack"
echo "codegen_defect_spills=$defect_spills"
echo "codegen_defect_device_sites=$defect_device_sites"
echo "codegen_regs_state=$([ $((defect_verify+defect_pack+defect_spills+defect_device_sites)) = 0 ] && echo ok || echo defaut)"
verdict "$defect_verify" "$defect_pack" "$defect_spills" "$defect_device_sites"
exit 0
