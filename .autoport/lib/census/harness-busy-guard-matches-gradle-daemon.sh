#!/usr/bin/env bash
# census/harness-busy-guard-matches-gradle-daemon.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il n'ecrit aucun champ de `proof.txt` : sa sortie `cle=valeur` rejoint celle du moteur dans le
# meme journal, moissonnee par la meme regle.
#
# LES QUATRE POINTS DU LIVRABLE, chacun avec son terme :
#   1. LE COUT D'AVANT EST CHIFFRE      -> lib/busy_guard_cost.py, sur les journaux archives.
#      Il doit etre NON NUL : une garde qu'on repare sans pouvoir montrer ce qu'elle a coute
#      n'a pas de defaut demontre. Un zero ici AJOUTE au verdict.
#   2. LA GARDE MESURE UN BUILD         -> ce que la course en train de se faire a LU et DECIDE,
#      relu dans le fichier d'attente que la MACHINE vient d'ecrire (proof.txt n'existe pas
#      encore quand ce script tourne).
#   3. LE TEMOIN A DEUX BRAS            -> lib/busy_guard_selftest.sh, verdicts cote a cote.
#   4. AUCUN FAUX rc=3 APRES            -> logs/busy-guard.tsv, le registre append-only que la
#      garde ecrit a chaque passage. Zero refus sans build reel, SUR N courses observees — et
#      N=0 est un defaut, pas un succes.
#
# POLARITE : INCONNU = DEFAUT. Chaque temoin manquant, muet ou degenere AJOUTE au compte. Sans
# cela, une porte `== 0` sur un nettoyage serait verte par INACTION.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "bg_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1
ID="${AUTOPORT_CENSUS_ID:-harness-busy-guard-matches-gradle-daemon}"
ARMED="${AUTOPORT_CENSUS_ARMED:-1}"
D="${AUTOPORT_CENSUS_DIR:-$AP/reports/$ID}"
REG="$AP/logs/busy-guard.tsv"

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }
penalite=0; pourquoi=""
faute(){ penalite=$((penalite+1)); pourquoi="${pourquoi:+$pourquoi+}$1"; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0` sans rien avoir mesure.
n(){ local v=$1; case "$v" in ''|*[!0-9]*) echo -1 ;; *) echo "$v" ;; esac; }

# ================================================== 1. LE COUT D'AVANT, DANS LES ARCHIVES =====
COUT=$(python3 "$AP/lib/busy_guard_cost.py" "$ID" 2>/dev/null) || COUT=""
c(){ printf '%s\n' "$COUT" | sed -n "s/^$1=//p" | tail -1; }
COUT_BRULES=$(n "$(c cost_attempts_burned)")
COUT_ATTENTES=$(n "$(c cost_wait_attempts)")
COUT_FICHIERS=$(n "$(c cost_files_scanned)")
t_cout=0
[ "$COUT_FICHIERS" -ge 100 ] 2>/dev/null || { t_cout=$((t_cout+1)); faute population-d-archives-trop-maigre; }
# NON NUL, SINON DEFAUT : « je n'ai rien trouve » ne demontre pas l'absence de defaut, il
# demontre que l'instrument n'a rien vu. Les deux populations comptent : l'essai TUE (rc=3) et
# l'essai qui a ATTENDU la garde sans mourir.
[ "$COUT_BRULES" -ge 1 ] 2>/dev/null || { t_cout=$((t_cout+1)); faute cout-avant-nul-rc3; }
[ "$COUT_ATTENTES" -ge 1 ] 2>/dev/null || { t_cout=$((t_cout+1)); faute cout-avant-nul-attentes; }

# ====================================== 2. CE QUE LA GARDE A LU ET DECIDE, CETTE COURSE-CI ====
SUF=""; [ "$ARMED" = 1 ] || SUF="-off"
WNAME=$(python3 "$AP/lib/impossible.py" name wait "$SUF" 2>/dev/null)
WF="$D/${WNAME:-nom-non-derive}"
w(){ sed -n "s/^$1=//p" "$WF" 2>/dev/null | tail -1; }
DEC=$(w busy_guard_decision); DEM=$(n "$(w busy_guard_daemon_present)")
AGE=$(w busy_guard_apk_age_s); WHY=$(w busy_guard_why)
t_lecture=0
[ -s "$WF" ] || { t_lecture=$((t_lecture+1)); faute fichier-d-attente-absent; }
case "$DEC" in passe|refus) ;; *) t_lecture=$((t_lecture+1)); faute decision-non-publiee ;; esac
[ "$DEM" -ge 0 ] 2>/dev/null || { t_lecture=$((t_lecture+1)); faute demon-non-lu; }
case "$AGE" in ''|*[!0-9-]*) t_lecture=$((t_lecture+1)); faute age-apk-non-lu ;; esac

# ======================================================= 3. LE TEMOIN A DEUX BRAS =============
ST=$(bash "$AP/lib/busy_guard_selftest.sh" 2>/dev/null) || ST="$ST"
s(){ printf '%s\n' "$ST" | sed -n "s/^$1=//p" | tail -1; }
t_bras=0
[ "$(n "$(s bg_selftest_ran)")" = 1 ] || { t_bras=$((t_bras+1)); faute bac-a-sable-muet; }
RATEES=$(n "$(s bg_legs_failed)")
if [ "$RATEES" -ge 0 ] 2>/dev/null; then t_bras=$((t_bras + RATEES)); else t_bras=$((t_bras+1)); faute jambes-non-comptees; fi
# LES BRAS NE SONT PAS VIDES : l'ancienne regle doit bloquer A TORT les deux tables que la
# nouvelle laisse passer. Sans ce terme, « les deux bras au vert » serait vrai aussi le jour ou
# la condition testee n'existe plus, et l'ablation ne mesurerait rien.
[ "$(n "$(s bg_vieille_regle_bloque_a_tort)")" -ge 2 ] 2>/dev/null \
  || { t_bras=$((t_bras+1)); faute ablation-vide-l-ancienne-regle-ne-bloque-plus; }
# LA DONNEE SUR LAQUELLE TOUT REPOSE, relue : le motif retenu est dans la ligne du CLIENT et
# PAS dans celle du DEMON, et c'est le MEME litteral que celui du script juge.
[ "$(n "$(s bg_motif_dans_client)")" -ge 1 ] 2>/dev/null || { t_bras=$((t_bras+1)); faute motif-absent-du-client; }
[ "$(n "$(s bg_motif_dans_demon)")" = 0 ] || { t_bras=$((t_bras+1)); faute motif-present-dans-le-demon; }
[ "$(n "$(s bg_motif_est_celui_du_script)")" -ge 1 ] 2>/dev/null || { t_bras=$((t_bras+1)); faute motif-du-banc-different-du-script; }

# ============================================ 4. AUCUN FAUX REFUS DEPUIS LA LIVRAISON =========
# Le registre est append-only et vit dans `logs/` : il n'est pas efface au demarrage d'une
# course, contrairement a proof.txt. C'est ce qui permet de compter les courses PRECEDENTES.
# LE COMPTEUR, DEFINI UNE SEULE FOIS : il sert sur le registre REEL et sur un registre SEME.
# Deux copies du meme awk divergeraient en silence, et le controle ne controlerait plus rien.
compte_registre(){          # $1 = fichier TSV -> REG_PASSE= REG_REFUS= FAUX= FAUX_LISTE=
  awk -F'\t' '
    $4=="passe" { p++ }
    $4=="refus" { r++
      # UN FAUX REFUS : la garde a nomme Gradle, et aucun APK ecrit dans la minute.
      if ($7 ~ /radle/ && ($9+0 >= 60 || $9+0 < 0)) { f++; l = l (l?",":"") $2 "@" $1 }
    }
    END { printf "REG_PASSE=%d\nREG_REFUS=%d\nFAUX=%d\nFAUX_LISTE=%c%s%c\n",
                 p+0, r+0, f+0, 39, (l==""?"-":l), 39 }
  ' "$1"
}
REG_N=0; REG_PASSE=0; REG_REFUS=0; FAUX=0; FAUX_LISTE="-"
if [ -s "$REG" ]; then
  REG_N=$(wc -l < "$REG"); REG_N=${REG_N// /}
  eval "$(compte_registre "$REG")"
fi
t_apres=$FAUX
# UN ZERO SUR ZERO N'EST PAS UN SUCCES. Si aucune course n'a traverse la garde depuis la
# livraison, il n'y a rien a constater — et c'est un defaut, pas un vert.
[ "$REG_N" -ge 1 ] 2>/dev/null || { t_apres=$((t_apres+1)); faute registre-vide-zero-sur-zero; }
[ "$REG_PASSE" -ge 1 ] 2>/dev/null || { t_apres=$((t_apres+1)); faute aucune-course-passee; }

# LE DETECTEUR EST CONTROLE, PAS SUPPOSE (feedback : temoin sur une POPULATION que le correctif
# VIDE). Un registre ou plus aucun refus n'apparait rend `FAUX=0` sans que rien ne prouve que le
# detecteur sait en reconnaitre un. On seme donc TROIS lignes dans un fichier jetable : un faux
# refus (Gradle nomme, APK vieux), un refus LEGITIME (APK ecrit il y a 3 s), et une course
# passee. Le detecteur doit en trouver EXACTEMENT un.
CTL=$(mktemp "${TMPDIR:-/tmp}/bgctl.XXXXXX") || CTL=""
CTL_TROUVE=-1; CTL_PASSE=-1
if [ -n "$CTL" ]; then
  printf '1000\tzzz-ctl-faux\tlivre\trefus\t1800\t1800\tprocessus [g]radle en cours\t1\t9000\t1\n'  > "$CTL"
  printf '1001\tzzz-ctl-vrai\tlivre\trefus\t1800\t1800\tAPK reecrit il y a 3s\t1\t3\t2\n'          >> "$CTL"
  printf '1002\tzzz-ctl-passe\tlivre\tpasse\t0\t1800\t-\t1\t9000\t3\n'                              >> "$CTL"
  eval "$(compte_registre "$CTL" | sed 's/^/CTL_/')"
  CTL_TROUVE=${CTL_FAUX:--1}; CTL_PASSE=${CTL_REG_PASSE:--1}
  rm -f "$CTL"
fi
[ "$CTL_TROUVE" = 1 ] || { t_apres=$((t_apres+1)); faute controle-detecteur-muet; }
[ "$CTL_PASSE" = 1 ] || { t_apres=$((t_apres+1)); faute controle-passe-mal-compte; }

# ========================================================================= LE VERDICT =========
TOTAL=$((t_cout + t_lecture + t_bras + t_apres + penalite))
pub busy_guard_false_positives "$TOTAL"
pub busy_guard_terms \
  "cout$t_cout+lecture$t_lecture+bras$t_bras+apres$t_apres+penalite$penalite${pourquoi:+:$pourquoi}"

# LES GRANDEURS BRUTES, recopiees telles quelles : une porte qui ne publie que son total ne dit
# pas ce qui a cede.
pub busy_guard_runs_observed "$REG_N"
pub busy_guard_runs_passed "$REG_PASSE"
pub busy_guard_runs_refused "$REG_REFUS"
pub busy_guard_false_refusals_after "$FAUX"
pub busy_guard_false_refusals_list "${FAUX_LISTE:--}"
pub busy_guard_registry "$REG"
pub busy_guard_ctl_detected "$CTL_TROUVE"
pub busy_guard_ctl_passed "$CTL_PASSE"
pub busy_guard_this_decision "${DEC:--}"
pub busy_guard_this_why "$(printf '%s' "${WHY:--}" | tr ' \t' '__')"
pub busy_guard_this_daemon_present "$DEM"
pub busy_guard_this_apk_age_s "${AGE:--}"
pub busy_guard_before_rc3_attempts "$COUT_BRULES"
pub busy_guard_before_wait_attempts "$COUT_ATTENTES"
pub bg_census_ran "$([ -n "$COUT" ] && [ -n "$ST" ] && echo 1 || echo 0)"

# Les bruts des deux instruments, sous un prefixe a eux : le moissonneur garde la DERNIERE
# valeur d'une cle, et un relai homonyme d'un terme du verdict l'ecraserait.
printf '%s\n' "$COUT" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/bgc_\1=/p'
printf '%s\n' "$ST"   | sed -n 's/^\([a-z_][a-z0-9_]*\)=/bgs_\1=/p'

# LES OCTETS JUGES. Un chemin n'est pas une provenance. Le releve de /proc n'est pas un `.sh` :
# `lib/verdict_sources.sh` ne l'epingle donc pas, et c'est son empreinte qui le tient ici.
for f in lib/proof_run.sh lib/busy_guard_selftest.sh lib/busy_guard_cost.py \
         lib/fixtures/gradle-cmdlines.tsv lib/census/$ID.sh; do
  k="bg_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done

exit 0
