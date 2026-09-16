#!/usr/bin/env bash
# census/perf-codegen-arm64-calls.sh — PUBLIE `codegen_gain_us`, ET RIEN QUE LUI.
#
# POURQUOI UN CROCHET, ET PAS LE MOTEUR. Le livrable N du contrat exige « goal_busy par image
# AVANT moins APRES sur l'appareil, meme scene, >= 300 images par bras ». Un seul processus `gk`
# ne voit qu'un bras : il ne peut pas soustraire. Le moteur publie donc la MOYENNE DE SA COURSE
# (`codegen_busy_us`, avec son denominateur `codegen_busy_frames`), et la soustraction se fait
# ici, apres la course, par le crochet generique de `lib/proof_run.sh`.
#
# QUEL BRAS EST « AVANT ». L'interrupteur `OG_CODEGEN_LEGACY_CALLS=1` est lu par goalc A LA
# COMPILATION : les deux bras sont deux jeux de CGO distincts, pas deux reglages d'execution.
# Le bras `--off` porte les CGO batis avec l'ancien enrobage d'appel (ADD + 3 STP + BLR + 3 LDP),
# le bras livre porte les CGO a deux instructions. Le TEMOIN que l'ablation a vraiment eu lieu
# n'est pas une intention : c'est `codegen_call_max_instructions`, mesure par le moteur dans les
# deux bras sur les memes 5 fonctions marqueurs. S'il ne MONTE pas du cote « avant », les deux
# bras portent le meme code et la soustraction ne vaut rien : on refuse de publier le gain.
#
# POLARITE. Ce crochet ne fabrique jamais une cle manquante. Quand il ne peut pas mesurer, il
# publie un ETAT NOMME et tait `codegen_gain_us` — le validateur est rouge, et la cause se lit.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

D="${AUTOPORT_CENSUS_DIR:?AUTOPORT_CENSUS_DIR manquant}"
ARMED="${AUTOPORT_CENSUS_ARMED:-1}"

# NOMMAGE/un-seul-endroit : aucun nom d'artefact en dur, ils viennent de lib/impossible.py.
eval "$(python3 - <<'PY'
import sys
sys.path.insert(0, '.autoport/lib')
import impossible as I
q = lambda s: "'" + str(s).replace("'", "'\\''") + "'"
print("N_ENG=%s N_OFF_ENG=%s N_OFF_PROOF=%s" %
      (q(I.arm_name('engine', '')), q(I.arm_name('engine', '-off')), q(I.arm_name('proof', '-off'))))
PY
)"
[ -n "${N_ENG:-}" ] && [ -n "${N_OFF_ENG:-}" ] && [ -n "${N_OFF_PROOF:-}" ] || {
  echo "codegen_gain_state=noms-non-resolus"; exit 0; }

# DERNIERE OCCURRENCE d'une cle dans un journal moteur. `grep -c` plutot que `grep -q` : sous
# `pipefail`, un `-q` sur un gros journal rend 141 (SIGPIPE) et la condition devient fausse sur
# un fichier qui PORTE le motif.
last_key() {  # <journal> <cle>
  [ -s "$1" ] || return 1
  local v
  v=$(grep -aoE "^$2=[0-9]+" "$1" | tail -1 | cut -d= -f2)
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

AFT_US=$(last_key "$D/$N_ENG" codegen_busy_us || true)
AFT_FR=$(last_key "$D/$N_ENG" codegen_busy_frames || true)
AFT_IN=$(last_key "$D/$N_ENG" codegen_call_max_instructions || true)

echo "codegen_busy_us_seen=${AFT_US:--}"
echo "codegen_busy_frames_seen=${AFT_FR:--}"

if [ "$ARMED" != 1 ]; then
  # Bras « avant » : le bras livre n'existe pas encore, il n'y a rien a soustraire.
  echo "codegen_gain_state=bras-avant-seul"
  exit 0
fi

BEF_US=$(last_key "$D/$N_OFF_ENG" codegen_busy_us || true)
BEF_FR=$(last_key "$D/$N_OFF_ENG" codegen_busy_frames || true)
BEF_IN=$(last_key "$D/$N_OFF_ENG" codegen_call_max_instructions || true)

echo "codegen_gain_before_us=${BEF_US:--}"
echo "codegen_gain_before_frames=${BEF_FR:--}"
echo "codegen_gain_before_instructions=${BEF_IN:--}"
echo "codegen_gain_after_instructions=${AFT_IN:--}"

if [ -z "${BEF_US:-}" ] || [ -z "${AFT_US:-}" ]; then
  echo "codegen_gain_state=bras-avant-absent"; exit 0
fi

# LES DEUX BRAS DOIVENT ETRE DU MEME ESSAI. Un `proof-off.txt` laisse par un essai anterieur
# decrit un AUTRE binaire : on compare l'identite de la course, jamais un horodatage.
BEF_ATT=$(sed -n 's/^proof_attempt_id=//p' "$D/$N_OFF_PROOF" 2>/dev/null | tail -1)
CUR_ATT="${AUTOPORT_ATTEMPT_ID:--}"
echo "codegen_gain_before_attempt=${BEF_ATT:--}"
echo "codegen_gain_after_attempt=$CUR_ATT"
if [ "${BEF_ATT:--}" != "$CUR_ATT" ] || [ "$CUR_ATT" = "-" ]; then
  echo "codegen_gain_state=bras-avant-d-un-autre-essai"; exit 0
fi

# >= 300 IMAGES PAR BRAS, exige par le livrable. Le denominateur est publie a cote.
if [ "${BEF_FR:-0}" -lt 300 ] || [ "${AFT_FR:-0}" -lt 300 ]; then
  echo "codegen_gain_state=images-insuffisantes"; exit 0
fi

# L'ABLATION A-T-ELLE VRAIMENT EU LIEU ? Sans cette porte, deux bras identiques rendraient un
# gain de ~0 qu'on lirait comme « l'optimisation ne sert a rien » au lieu de « je n'ai pas
# mesure ce que je crois ».
if [ -z "${BEF_IN:-}" ] || [ -z "${AFT_IN:-}" ] || [ "$BEF_IN" -le "$AFT_IN" ]; then
  echo "codegen_gain_state=ablation-sans-effet-mesure"; exit 0
fi

echo "codegen_gain_us=$(( BEF_US - AFT_US ))"
echo "codegen_gain_state=mesure"
