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
  # ANCRAGE. Le journal d'une course APPAREIL est un journal logcat : chaque ligne porte
  # `09-16 22:48:44.825 I/GK_STDOUT(22764): ` AVANT la cle. Un motif ancre sur `^` n'y matche
  # donc RIEN, et le crochet publiait `bras-avant-absent` alors que les DEUX bras avaient
  # mesure et imprime leur valeur (essai 8 : 15806 du cote avant, 16538 du cote livre, tous
  # deux presents dans les journaux, aucun gain publie). On accepte donc le debut de ligne OU
  # un separateur, jamais un caractere de nom : `xcodegen_busy_us=` ne doit pas passer.
  [ -s "$1" ] || return 1
  local v
  v=$(grep -aoE "(^|[^A-Za-z0-9_])$2=[0-9]+" "$1" | tail -1 | sed 's/.*=//')
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

# MOYENNE DE COURSE d'une cle FLOTTANTE publiee a chaque fenetre (ms/image), et SOMME des
# `goal_bucket_ms_*` hors `swap_display`. Pourquoi : `codegen_busy_us` vaut 16,5 ms/image quand
# la somme de TOUS les seaux de code GOAL vaut 2,7 ms/image ; le reste est du temps passe dans
# le chemin de presentation que l'instrument ne classe pas en attente. Publier la seule
# soustraction du contrat reviendrait a faire lire une difference de CADENCE comme un cout de
# codegen. La decomposition sort a cote, sur les memes deux courses, sans instrument neuf.
# Chaque cle est moyennee par SON propre denominateur : une cle vue moins souvent ne decale pas
# la somme.
arm_means() {  # <journal> -> "work_us vsync_us dispatch_us windows"
  [ -s "$1" ] || return 1
  awk '
    {
      while (match($0, /goal_(bucket_ms_[a-z_]+|vsync_wait_ms|dispatch_ms|syncpath_wait_ms)=[0-9]+\.[0-9]+/)) {
        kv = substr($0, RSTART, RLENGTH); $0 = substr($0, RSTART + RLENGTH)
        eq = index(kv, "="); k = substr(kv, 1, eq - 1); v = substr(kv, eq + 1) + 0
        s[k] += v; n[k]++
      }
    }
    END {
      work = 0; nw = 0
      for (k in s) {
        m = s[k] / n[k]
        if (k ~ /^goal_bucket_ms_/ && k != "goal_bucket_ms_swap_display") { work += m; if (n[k] > nw) nw = n[k] }
      }
      vs = (n["goal_vsync_wait_ms"] ? s["goal_vsync_wait_ms"] / n["goal_vsync_wait_ms"] : 0)
      di = (n["goal_dispatch_ms"] ? s["goal_dispatch_ms"] / n["goal_dispatch_ms"] : 0)
      printf "%d %d %d %d\n", work * 1000, vs * 1000, di * 1000, nw
    }' "$1"
}

# LE JOURNAL DE SA PROPRE COURSE. Le crochet tourne dans les DEUX bras, et le dossier de
# recensement est le meme : `proof-engine.log` du bras livre survit a la course du bras avant.
# Lire N_ENG quand on est le bras avant publierait dans `proof-off.txt` la valeur d'une AUTRE
# course — un chiffre frais a cote d'un chiffre perime, impossible a distinguer.
SELF_ENG="$N_ENG"; [ "$ARMED" = 1 ] || SELF_ENG="$N_OFF_ENG"
AFT_US=$(last_key "$D/$SELF_ENG" codegen_busy_us || true)
AFT_FR=$(last_key "$D/$SELF_ENG" codegen_busy_frames || true)
AFT_IN=$(last_key "$D/$SELF_ENG" codegen_call_max_instructions || true)

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

# ---------------------------------------------------------------------------------------------
# CE QUE LA SOUSTRACTION DU CONTRAT CONTIENT VRAIMENT. `codegen_busy_us` est
# `dispatch - (syncpath + vsync)` (game/system/perf_instruments.cpp:1088-1090) : il vaut 16,5 ms
# par image alors que la SOMME de tous les seaux de code GOAL vaut 2,7 ms. Le reste est du temps
# passe dans le chemin de presentation que l'instrument ne classe pas en attente. Sans les trois
# cles ci-dessous, un lecteur prend une difference de CADENCE pour un cout d'appel : sur l'essai
# 8, `codegen_gain_us` valait -732 alors que l'attente vsync avait bouge de +606 en sens
# INVERSE, et que le travail GOAL mesure seau par seau ne bougeait que de -73.
# Rien ici n'est un instrument neuf : ce sont les memes deux courses, relues autrement.
A_M=$(arm_means "$D/$N_ENG" || true)
B_M=$(arm_means "$D/$N_OFF_ENG" || true)
if [ -n "$A_M" ] && [ -n "$B_M" ]; then
  set -- $A_M; A_WORK=$1; A_VSYNC=$2; A_DISP=$3; A_WIN=$4
  set -- $B_M; B_WORK=$1; B_VSYNC=$2; B_DISP=$3; B_WIN=$4
  echo "codegen_gain_goalwork_us=$(( B_WORK - A_WORK ))"
  echo "codegen_gain_vsync_us=$(( B_VSYNC - A_VSYNC ))"
  echo "codegen_gain_dispatch_us=$(( B_DISP - A_DISP ))"
  echo "codegen_work_after_us=$A_WORK"
  echo "codegen_work_before_us=$B_WORK"
  echo "codegen_work_windows_after=$A_WIN"
  echo "codegen_work_windows_before=$B_WIN"
  echo "codegen_gain_decomposed=1"
else
  echo "codegen_gain_decomposed=0"
fi

# ASYMETRIE DE RECENSEMENT ENTRE LES DEUX BRAS. `note_hit_for` sort immediatement quand le bras
# est desarme (game/system/autoport_proof.cpp:293-299) : le bras LIVRE paye des millions de
# prises de mutex global que le bras AVANT ne paye pas. Ce cout n'est pas l'enrobage d'appel,
# il porte pourtant le meme signe. On le publie a cote du gain pour qu'il ne se lise pas comme
# du codegen ; on ne le corrige pas ici (ce serait toucher la semantique d'ablation de TOUS les
# items).
AFT_HITS=$(last_key "$D/$N_ENG" proof_feature_global_hits || true)
BEF_HITS=$(last_key "$D/$N_OFF_ENG" proof_feature_global_hits || true)
echo "codegen_gain_census_hits_after=${AFT_HITS:--}"
echo "codegen_gain_census_hits_before=${BEF_HITS:--}"
if [ -n "${AFT_HITS:-}" ] && [ -n "${BEF_HITS:-}" ] && [ "$AFT_HITS" = "$BEF_HITS" ]; then
  echo "codegen_gain_arms_census_symmetric=1"
else
  echo "codegen_gain_arms_census_symmetric=0"
fi
