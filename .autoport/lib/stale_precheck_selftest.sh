#!/usr/bin/env bash
# lib/stale_precheck_selftest.sh — LE BANC DE `harness-stale-proof-caught-before-the-run`.
#
# CE QU'IL MESURE. Un temoin a UN SEUL bras ne prouve que la moitie : une detection qui crie
# toujours « perime » passerait le bras sale et ferait rougir tout le harnais. On seme donc DEUX
# controles dans des depots jetables, et on les lit cote a cote :
#
#   BRAS PERIME  un arbre ou, APRES la capture de la preuve, deux fichiers bougent — une source
#                du VERDICT touchee sans que son contenu change (peremption de pure fraicheur,
#                le sha ne la verrait pas) et une source MOTEUR neuve. La detection doit voir
#                les deux, et rendre 5.
#   BRAS PROPRE  le meme arbre, intact. La detection doit rendre 0 et ne nommer personne.
#
# ET, POUR CHAQUE BRAS, LE VRAI JUGE PASSE DERRIERE. `validators/generic.sh` est lance TEL QUEL
# sur le meme depot : c'est ce qui distingue « ma detection est d'accord avec elle-meme » de
# « ma detection voit exactement ce que le juge verra une heure plus tard ». Une detection plus
# SEVERE que le juge serait un deuxieme juge, et ferait payer des essais que personne n'a
# touches ; une detection plus LACHE laisserait passer ce qu'on pretend avoir supprime.
#
# Il ne JUGE rien : la somme et la polarite « inconnu = defaut » vivent dans
# lib/census/harness-stale-proof-caught-before-the-run.sh. Sortie : des `cle=valeur` sur stdout.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "spq_selftest_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1
SB=$(mktemp -d -t staleprecheck.XXXXXX) || { echo "spq_selftest_ran=0"; exit 1; }
trap 'rm -rf "$SB"' EXIT
kv(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }
note(){ printf '[spq-selftest] %s\n' "$*" >&2; }

SANDITEM="sandbox-stale-precheck"
# Les noms sortent de l'autorite de nommage, jamais d'un litteral : un banc qui reecrit un nom
# lit un fichier vide le jour ou le nom bouge, et un banc muet ressemble a un banc satisfait.
PROOFNAME=$(python3 "$AP/lib/impossible.py" name proof "")
[ -n "$PROOFNAME" ] || { echo "spq_selftest_ran=0"; exit 1; }

monte(){  # monte <dossier> : un depot jetable que `validators/generic.sh` peut juger
  local dir=$1 rel
  mkdir -p "$dir/.autoport/reports/$SANDITEM" "$dir/build/game" \
           "$dir/game" "$dir/common" "$dir/android" "$dir/goal_src" || return 1
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mkdir -p "$dir/$(dirname "$rel")" || return 1
    cp "$ROOT/$rel" "$dir/$rel" || return 1
  done < <(bash "$AP/lib/verdict_sources.sh" "$SANDITEM" list)
  # La detection est lancee DANS le depot jetable : elle doit y etre.
  cp "$AP/lib/stale_precheck.sh" "$dir/.autoport/lib/" || return 1
  cp "$AP/lib/impossible.py" "$dir/.autoport/lib/" 2>/dev/null || true
  git -C "$dir" init -q >/dev/null 2>&1 || return 1           # git-sandbox-ok
  printf 'faux gk du banc de la lecture anticipee\n' > "$dir/build/game/gk"
  printf '// source moteur du depot jetable\n' > "$dir/game/sonde_origine.cpp"
  cat > "$dir/.autoport/backlog.yaml" <<YAML
version: 1
items:
  - id: $SANDITEM
    feature: "banc de la lecture anticipee de fraicheur"
    status: open
    device: false
    gate: {key: episodes, op: "==", value: 0}
YAML
}

pose_preuve(){  # pose_preuve <dossier> : une preuve comme la machine l'ecrit, l'epingle comprise
  local dir=$1 sha
  sha=$(sha256sum "$dir/build/game/gk" | cut -c1-16)
  { echo "source=x86"; echo "binary=build/game/gk"; echo "sha=$sha"
    echo "started_at=2026-09-12T09:00:00Z"; echo "duration_s=62"; echo "crash=0"; echo "frames=1800"
    echo "proof_feature_id=$SANDITEM"; echo "proof_feature_state=hit"
    echo "proof_feature_declared=1"; echo "proof_feature_own_hits=37"
    echo "proof_feature_global_hits=4419755"
    echo "proof_census_present=0"; echo "proof_census_rc=-1"; echo "proof_census_keys=0"
    ( cd "$dir" && bash .autoport/lib/verdict_sources.sh "$SANDITEM" kv )
    echo "FEATURE $SANDITEM armed=1 hits=37"
    echo "episodes=0"
  } > "$dir/.autoport/reports/$SANDITEM/$PROOFNAME"
}

# LE JUGE, TEL QUEL. `AUTOPORT_ATTEMPT_ID` est RETIRE de son environnement : l'orchestrateur en
# pose un pour l'essai en cours, et il traverserait jusqu'ici — le juge comparerait alors
# l'identite d'un essai REEL a une preuve de bac a sable, et refuserait pour une raison qui n'a
# rien a voir avec ce qu'on mesure. Sans identite posee, il ne compare pas ce qu'on ne lui a pas
# donne : c'est sa regle, ecrite dans son propre bloc IDENTITE-DE-LA-COURSE.
juge(){  # juge <dossier> -> code de retour ; la sortie va dans $JUGE_OUT
  JUGE_OUT=$( cd "$1" && env -u AUTOPORT_ATTEMPT_ID AUTOPORT_PHASE_ID="$SANDITEM" \
              bash .autoport/validators/generic.sh 2>&1 )
  return $?
}
motif_verdict(){ case "$JUGE_OUT" in *"source du VERDICT editee APRES la preuve"*) echo 1 ;; *) echo 0 ;; esac; }
motif_moteur(){  case "$JUGE_OUT" in *"source moteur editee APRES la preuve"*) echo 1 ;; *) echo 0 ;; esac; }

detecte(){  # detecte <dossier> -> code de retour ; les cles vont dans $DET_OUT
  DET_OUT=$(bash "$1/.autoport/lib/stale_precheck.sh" "$SANDITEM" --root "$1" 2>/dev/null)
  return $?
}
d(){ printf '%s\n' "$DET_OUT" | sed -n "s/^$1=//p" | tail -1; }

# ====================================================== BRAS PROPRE : l'arbre intact ==========
if monte "$SB/propre"; then
  kv spq_propre_monte 1
  pose_preuve "$SB/propre"
  detecte "$SB/propre"; PRC=$?
  kv spq_propre_detection_rc "$PRC"
  kv spq_propre_verdict_neufs "$(d stale_precheck_verdict_newer)"
  kv spq_propre_moteur_neufs  "$(d stale_precheck_engine_newer)"
  kv spq_propre_compares      "$(d stale_precheck_files_compared)"
  kv spq_propre_ref_presente  "$(d stale_precheck_ref_present)"
  juge "$SB/propre"; kv spq_propre_juge_rc $?
  kv spq_propre_juge_motif_verdict "$(motif_verdict)"
  kv spq_propre_juge_motif_moteur  "$(motif_moteur)"
  kv spq_propre_juge_sortie "$(printf '%s' "$JUGE_OUT" | tr '\n' '|' | cut -c1-160)"
else
  kv spq_propre_monte 0
  note "le depot jetable du bras propre n'a pas pu etre monte"
fi

# ====================================================== BRAS PERIME : deux semis apres la capture
# LE SEMIS 1 EST UN `touch` NU : le contenu ne change pas, donc l'empreinte ne bouge pas et seule
# la FRAICHEUR peut le voir. C'est le cas que `verdict_sources_sha` rate et que ce chantier vise.
# Le sommeil n'est pas une precaution de principe : l'horloge d'inode de cette machine n'avance
# que par tics d'environ 300 us, et deux ecritures qui se suivent peuvent porter le MEME
# horodatage a la nanoseconde. A horodatage egal, `-nt` est faux : le semis serait invisible, et
# le banc accuserait la detection d'un defaut qui serait le sien.
if monte "$SB/perime"; then
  kv spq_perime_monte 1
  pose_preuve "$SB/perime"
  sleep 0.3
  VICTIME=$( cd "$SB/perime" && bash .autoport/lib/verdict_sources.sh "$SANDITEM" list \
             | grep -v '^\.autoport/acquis/' | grep -v 'verdict_sources.sh$' | head -1 )
  kv spq_perime_victime "${VICTIME:--}"
  SHA_AVANT=$(sha256sum "$SB/perime/$VICTIME" 2>/dev/null | cut -c1-16)
  touch "$SB/perime/$VICTIME"
  SHA_APRES=$(sha256sum "$SB/perime/$VICTIME" 2>/dev/null | cut -c1-16)
  kv spq_perime_victime_sha_stable "$([ "$SHA_AVANT" = "$SHA_APRES" ] && echo 1 || echo 0)"
  printf '// source moteur ecrite APRES la capture de la preuve\n' > "$SB/perime/game/sonde_tardive.cpp"
  detecte "$SB/perime"; PRC=$?
  kv spq_perime_detection_rc "$PRC"
  kv spq_perime_verdict_neufs "$(d stale_precheck_verdict_newer)"
  kv spq_perime_moteur_neufs  "$(d stale_precheck_engine_newer)"
  kv spq_perime_compares      "$(d stale_precheck_files_compared)"
  case "$(d stale_precheck_verdict_newer_list)" in
    *"$(basename "${VICTIME:-aucune}")"*) kv spq_perime_victime_nommee 1 ;;
    *) kv spq_perime_victime_nommee 0 ;;
  esac
  case "$(d stale_precheck_engine_newer_list)" in
    *sonde_tardive.cpp*) kv spq_perime_moteur_nomme 1 ;;
    *) kv spq_perime_moteur_nomme 0 ;;
  esac
  juge "$SB/perime"; kv spq_perime_juge_rc $?
  kv spq_perime_juge_motif_verdict "$(motif_verdict)"
  kv spq_perime_juge_motif_moteur  "$(motif_moteur)"
  kv spq_perime_juge_sortie "$(printf '%s' "$JUGE_OUT" | tr '\n' '|' | cut -c1-200)"
else
  kv spq_perime_monte 0
  note "le depot jetable du bras perime n'a pas pu etre monte"
fi

# ====================================== LA CONCORDANCE : la MEME chose, une heure plus tot =====
# Les deux bras sont lus ensemble. La detection et le juge doivent etre d'accord SUR LES DEUX :
# d'accord sur le bras perime prouve qu'elle voit ; d'accord sur le bras propre prouve qu'elle
# ne crie pas. L'un sans l'autre ne prouve rien.
kv spq_selftest_ran 1
