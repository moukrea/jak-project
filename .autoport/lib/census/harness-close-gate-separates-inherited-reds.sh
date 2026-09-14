#!/usr/bin/env bash
# census/harness-close-gate-separates-inherited-reds.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il n'ecrit aucun champ de `proof.txt` : sa sortie `cle=valeur` rejoint celle du moteur dans le
# meme journal, moissonnee par la meme regle.
#
# LES QUATRE POINTS DU LIVRABLE, chacun avec son terme :
#   1. LE COUT D'AVANT EST CHIFFRE   -> lib/inherited_red_cost.py, sur les 809 journaux
#      archives. Il doit etre NON NUL : une porte qu'on repare sans pouvoir montrer ce qu'elle a
#      coute n'a pas de defaut demontre. Un zero ici AJOUTE au verdict.
#   2. LA PORTE DISTINGUE            -> sur LE MEME cas d'archive, rejoue par la mecanique
#      LIVREE : les deux rouges qui ont tue l'essai 2 de `hdr-shadow-range` sont ROUGES a la
#      base de l'ESSAI (donc herites), et la base que la porte d'alors avait retenue n'etait
#      pas celle-la. C'est une mesure sur donnee reelle, pas un miroir de nos propres variables.
#   3. L'HERITE NE MEURT PAS EN SILENCE -> le semis `herite_muet` du banc : un rouge herite que
#      ni le rapport ni FINDINGS.txt ne nomment REFUSE encore — mais pour le SIGNALEMENT, et la
#      raison le dit. Le semis `herite_signale`, lui, ferme.
#   4. LE TEMOIN A DEUX BRAS         -> lib/inherited_red_selftest.py : quatre semis joues par
#      le juge d'AVANT (blob ancre sur un marqueur) et par celui d'APRES, verdicts cote a cote.
#
# CE QUE COMPTE `inherited_red_refusals` : les refus qui IMPUTENT a l'essai un rouge qu'il a
# herite. Un refus qui demande un SIGNALEMENT n'en est pas un — il ne dit pas « ce build la rend
# rouge », il dit « ecris-le pour que le suivant ne repaie pas l'enquete ». Les deux sont
# publies separement, et le second est un ACQUIS de l'item, pas un defaut.
#
# POLARITE : INCONNU = DEFAUT. Chaque temoin manquant, muet ou degenere AJOUTE au compte. Sans
# cela, une porte `== 0` sur un nettoyage serait verte par INACTION.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "irh_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1
ID="${AUTOPORT_CENSUS_ID:-harness-close-gate-separates-inherited-reds}"

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }
penalite=0; pourquoi=""
faute(){ penalite=$((penalite+1)); pourquoi="${pourquoi:+$pourquoi+}$1"; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0` sans rien avoir mesure.
n(){ local v=${1:-}; case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ================================================== 1. LE COUT D'AVANT, DANS LES ARCHIVES =====
COUT=$(python3 "$AP/lib/inherited_red_cost.py" "$ID" 2>/dev/null) || COUT=""
c(){ printf '%s\n' "$COUT" | sed -n "s/^$1=//p" | tail -1; }
C_RAN=$(n "$(c cost_ran)")
C_FICHIERS=$(n "$(c cost_files_scanned)")
C_REFUS=$(n "$(c cost_refusals)")
C_HERITE=$(n "$(c cost_all_inherited)")
C_RESOLUS=$(n "$(c cost_resolved)")
C_INDEC=$(n "$(c cost_undecidable)")
t_cout=0
[ "$C_RAN" = 1 ] || { t_cout=$((t_cout+1)); faute cout-muet; }
# LE DENOMINATEUR N'EST PAS SOUS-ENTENDU : 809 journaux le 14/09. Un plancher a 100 dit qu'on a
# bien lu une population, pas trois fichiers rescapes d'un nettoyage de `logs/`.
[ "$C_FICHIERS" -ge 100 ] 2>/dev/null || { t_cout=$((t_cout+1)); faute population-d-archives-trop-maigre; }
# NON NUL, SINON DEFAUT : « je n'ai rien trouve » ne demontre pas l'absence de defaut, il
# demontre que l'instrument n'a rien vu.
[ "$C_REFUS" -ge 1 ] 2>/dev/null || { t_cout=$((t_cout+1)); faute aucun-refus-de-porte-de-suite-archive; }
[ "$C_HERITE" -ge 1 ] 2>/dev/null || { t_cout=$((t_cout+1)); faute cout-avant-nul; }
[ "$C_INDEC" = 0 ] || { t_cout=$((t_cout+1)); faute refus-archive-indecidable; }

# ============================ 2. LA PORTE DISTINGUE, SUR LE CAS REEL QUI A COUTE L'ESSAI ======
# Chaque refus archive porte sa base d'ESSAI mesuree et la base que la porte d'alors avait
# retenue. `base_is_gate_base=0` est la faute elle-meme : la porte jugeait sur une autre
# revision que celle que l'essai a trouvee en arrivant.
t_porte=0
R_VERDICT=$(c cost_r1_verdict)
R_BASE=$(c cost_r1_base)
R_GATE_BASE=$(c cost_r1_gate_base)
R_MEME=$(n "$(c cost_r1_base_is_gate_base)")
R_NOEUDS=$(n "$(c cost_r1_nodes)")
[ "$R_VERDICT" = herite ] || { t_porte=$((t_porte+1)); faute cas-d-archive-non-classe-herite; }
[ "$R_MEME" = 0 ] || { t_porte=$((t_porte+1)); faute base-d-essai-egale-base-de-la-porte-rien-a-corriger; }
[ "$R_NOEUDS" -ge 1 ] 2>/dev/null || { t_porte=$((t_porte+1)); faute cas-d-archive-sans-nodeid; }
# LA PORTE PUBLIE CE QU'ELLE CALCULE, et c'est le PUBLICATEUR qu'on interroge, pas le fichier :
# une cle calculee mais jamais publiee ne se lit nulle part.
CLES=$(python3 -c "
import sys; sys.path.insert(0, '$AP/lib')
import suite_gate
print(','.join(l.split('=')[0] for l in suite_gate.publish({})))" 2>/dev/null)
for cle in suite_unwaived_known suite_unwaived_known_list suite_unwaived_new \
           suite_unwaived_new_list suite_red_base_ref suite_red_base_kind suite_replay_ran; do
  case ",$CLES," in *",$cle,"*) ;; *) t_porte=$((t_porte+1)); faute "non-publie:$cle" ;; esac
done

# ======================================================= 4. LE TEMOIN A DEUX BRAS =============
BANC=$(python3 "$AP/lib/inherited_red_selftest.py" 2>/dev/null) || BANC="$BANC"
s(){ printf '%s\n' "$BANC" | sed -n "s/^$1=//p" | tail -1; }
t_bras=0
[ "$(n "$(s banc_ran)")" = 1 ] || { t_bras=$((t_bras+1)); faute bac-a-sable-muet; }
[ "$(n "$(s apres_ran)")" = 1 ] || { t_bras=$((t_bras+1)); faute bras-apres-muet; }
[ "$(n "$(s avant_ran)")" = 1 ] || { t_bras=$((t_bras+1)); faute bras-avant-muet; }
# LA TABLE DE CONFORMITE EST DANS LE BANC, PAS ICI : deux tables divergeraient en silence.
ECARTS=$(n "$(s conformite_ecarts)")
if [ "$ECARTS" -ge 0 ] 2>/dev/null; then t_bras=$((t_bras + ECARTS)); else t_bras=$((t_bras+1)); faute conformite-non-comptee; fi
# LE COMPARATEUR EST CONTROLE, PAS SUPPOSE. La MEME table passee au bras d'AVANT doit rendre des
# ecarts NON NULS. Sans ce terme, un comparateur mort rendrait `conformite_ecarts=0` et se
# lirait comme une reussite.
ECARTS_AVANT=$(n "$(s conformite_ecarts_avant)")
[ "$ECARTS_AVANT" -ge 1 ] 2>/dev/null || { t_bras=$((t_bras+1)); faute comparateur-aveugle-zero-ecart-sur-l-avant; }
# L'ABLATION N'EST PAS VIDE. Le juge d'AVANT doit REFUSER le semis herite : c'est le defaut. Si
# les deux bras fermaient, « la porte distingue » serait vrai aussi le jour ou plus aucun rouge
# ne peut etre herite, et la comparaison ne mesurerait plus rien.
[ "$(n "$(s ablation_avant_refuse_l_herite)")" = 1 ] || { t_bras=$((t_bras+1)); faute ablation-vide-l-avant-ne-refuse-plus-l-herite; }
[ "$(n "$(s ablation_apres_ferme_l_herite)")" = 1 ] || { t_bras=$((t_bras+1)); faute l-apres-ne-ferme-pas-l-herite; }
# HORS PERIMETRE, TENU : le NEUF reste refuse par les DEUX bras, et le vert ferme des deux cotes.
[ "$(n "$(s ablation_les_deux_refusent_le_neuf)")" = 1 ] || { t_bras=$((t_bras+1)); faute un-rouge-NEUF-a-ete-relache; }
[ "$(n "$(s ablation_les_deux_ferment_le_vert)")" = 1 ] || { t_bras=$((t_bras+1)); faute controle-positif-refuse; }
# LE MARQUEUR QUI ANCRE LE BRAS D'AVANT, et le commit retenu : un « avant » lu a `HEAD:` serait
# faux des le commit de ce chantier.
[ "$(n "$(s before_marqueur_absent)")" = 1 ] || { t_bras=$((t_bras+1)); faute bras-avant-non-ancre; }
[ "$(n "$(s after_marqueur_present)")" = 1 ] || { t_bras=$((t_bras+1)); faute marqueur-absent-de-l-arbre-livre; }
[ "$(n "$(s src_replay_apres)")" -ge 1 ] 2>/dev/null || { t_bras=$((t_bras+1)); faute rejeu-absent-de-l-arbre-livre; }
[ "$(n "$(s src_replay_avant)")" = 0 ] || { t_bras=$((t_bras+1)); faute rejeu-deja-present-avant; }

# ================================== 3. L'HERITE NE MEURT PAS EN SILENCE =======================
t_signal=0
[ "$(s apres_herite_muet_verdict)" = refuse ] || { t_signal=$((t_signal+1)); faute herite-muet-ferme-sans-signalement; }
[ "$(n "$(s apres_herite_muet_dit_signalement)")" = 1 ] || { t_signal=$((t_signal+1)); faute refus-muet-ne-dit-pas-signalement; }
[ "$(n "$(s apres_herite_muet_dit_ce_travail)")" = 0 ] || { t_signal=$((t_signal+1)); faute refus-du-muet-accuse-encore-le-travail; }
[ "$(n "$(s apres_herite_muet_unfiled)")" -ge 1 ] 2>/dev/null || { t_signal=$((t_signal+1)); faute non-signale-non-compte; }
[ "$(s apres_herite_signale_verdict)" = pass ] || { t_signal=$((t_signal+1)); faute herite-signale-refuse-quand-meme; }
[ "$(n "$(s apres_herite_signale_filed)")" -ge 1 ] 2>/dev/null || { t_signal=$((t_signal+1)); faute signalement-non-compte; }

# ============================= LE COMPTE QUI DONNE SON NOM A LA PORTE =========================
# Les fermetures JUGEES par la porte livree, et parmi elles celles qui IMPUTENT a l'essai un
# rouge herite. Le denominateur : les semis du banc (joues par le module livre) plus les
# entrees du journal des courses ecrites par lui — un `0 sur 0` ne serait pas un succes.
# IMPUTER, c'est refuser EN CHARGEANT l'essai d'un rouge qu'il n'a pas fabrique : verdict
# `refuse`, la cause `neufs` au dossier, et pourtant aucun rouge neuf. Le seul `refuse` de
# genre `signalement` n'en est PAS un — il ne dit pas « ce build la rend rouge ». Sans
# `refused_for`, les deux se ressemblent : le bras `--off` du 14/09 a compte 1 la ou la porte
# avait simplement demande d'ecrire une ligne. C'est ce qui a fait ajouter ce champ.
#
# LE DETECTEUR EST CONTROLE, PAS SUPPOSE. Un journal ou plus aucune imputation n'apparait rend
# zero sans que rien ne prouve que le detecteur sait en reconnaitre une. On SEME donc trois
# entrees dans un journal jetable — une vraie imputation, un refus de SIGNALEMENT, un refus
# legitime pour un rouge neuf — et il doit en trouver EXACTEMENT une.
JOURNAL="$AP/.last_suite_gate.json"
eval "$(python3 - "$JOURNAL" <<'PY' 2>/dev/null || echo "J_NEUVES=-1 J_IMPUTES=-1 J_CTL=-1 J_CTL_SIG=-1"
import json, sys


def compte(runs):
    """LE COMPTEUR, DEFINI UNE SEULE FOIS : il sert sur le journal REEL et sur le journal SEME.
    Deux copies du meme predicat divergeraient en silence."""
    neuves = [r for r in runs if "red_base_kind" in r]
    imputes = [r for r in neuves
               if r.get("verdict") == "refuse"
               and "neufs" in (r.get("refused_for") or [])
               and not (r.get("introduced") or [])]
    signale = [r for r in neuves
               if r.get("verdict") == "refuse"
               and "signalement" in (r.get("refused_for") or [])]
    return len(neuves), len(imputes), len(signale)


try:
    runs = (json.load(open(sys.argv[1], encoding="utf-8")) or {}).get("runs") or []
except Exception:
    runs = []
neuves, imputes, _sig = compte(runs)
SEME = [
    # une VRAIE imputation : refus pour `neufs`, aucun rouge neuf, des herites au dossier
    {"red_base_kind": "attempt", "verdict": "refuse", "refused_for": ["neufs"],
     "introduced": [], "inherited": ["a.py::x"]},
    # un refus de SIGNALEMENT : c'est un acquis de l'item, pas une imputation
    {"red_base_kind": "attempt", "verdict": "refuse", "refused_for": ["signalement"],
     "introduced": [], "inherited": ["a.py::y"]},
    # un refus LEGITIME : l'essai a bien casse quelque chose
    {"red_base_kind": "attempt", "verdict": "refuse", "refused_for": ["neufs"],
     "introduced": ["a.py::z"], "inherited": []},
]
_n, ctl, ctl_sig = compte(SEME)
print("J_TOTAL=%d J_NEUVES=%d J_IMPUTES=%d J_CTL=%d J_CTL_SIG=%d"
      % (len(runs), neuves, imputes, ctl, ctl_sig))
PY
)"
J_TOTAL=${J_TOTAL:--1}; J_NEUVES=${J_NEUVES:--1}; J_IMPUTES=${J_IMPUTES:--1}
J_CTL=${J_CTL:--1}; J_CTL_SIG=${J_CTL_SIG:--1}
BANC_LEGS=0
for nom in vert herite_signale herite_muet neuf; do
  [ -n "$(s "apres_${nom}_verdict")" ] && BANC_LEGS=$((BANC_LEGS+1))
done
FERMETURES=$((BANC_LEGS + (J_NEUVES > 0 ? J_NEUVES : 0)))
t_apres=0
[ "$FERMETURES" -ge 1 ] 2>/dev/null || { t_apres=$((t_apres+1)); faute aucune-fermeture-jugee-zero-sur-zero; }
# Un refus qui IMPUTE un rouge herite, sous la porte livree, est exactement ce que cet item
# supprime. Il doit etre nul, sur un denominateur non nul.
if [ "$J_IMPUTES" -ge 0 ] 2>/dev/null; then t_apres=$((t_apres + J_IMPUTES)); else t_apres=$((t_apres+1)); faute journal-illisible; fi
# LE CONTROLE SEME : EXACTEMENT une imputation trouvee sur trois entrees, et le refus de
# signalement n'est pas confondu avec elle. Un detecteur muet rendrait zero sur le journal reel
# et se lirait comme une reussite.
[ "$J_CTL" = 1 ] || { t_apres=$((t_apres+1)); faute controle-detecteur-d-imputation-muet; }
[ "$J_CTL_SIG" = 1 ] || { t_apres=$((t_apres+1)); faute controle-signalement-mal-compte; }
# LA CAUSE EST NOMMEE PAR LA PORTE, pas devinee ici : sans `refused_for`, « refuse » ne
# distingue pas « ce build a casse la suite » de « signale ce rouge qui n'est pas de toi ».
case ",$CLES," in *",suite_refused_for,"*) ;; *) t_apres=$((t_apres+1)); faute cause-du-refus-non-publiee ;; esac
# Le banc compte double ici : ses semis herites sont des fermetures jugees, et aucune ne doit
# imputer. `herite_signale` ferme, `herite_muet` refuse SANS dire « ce travail-ci ».
[ "$(n "$(s apres_herite_signale_neufs)")" = 0 ] || { t_apres=$((t_apres+1)); faute herite-compte-comme-neuf; }
[ "$(n "$(s apres_herite_muet_neufs)")" = 0 ] || { t_apres=$((t_apres+1)); faute herite-muet-compte-comme-neuf; }
[ "$(n "$(s apres_neuf_neufs)")" -ge 1 ] 2>/dev/null || { t_apres=$((t_apres+1)); faute neuf-non-compte-comme-neuf; }

# ========================================================================= LE VERDICT =========
TOTAL=$((t_cout + t_porte + t_bras + t_signal + t_apres + penalite))
pub inherited_red_refusals "$TOTAL"
pub inherited_red_terms \
  "cout$t_cout+porte$t_porte+bras$t_bras+signal$t_signal+apres$t_apres+penalite$penalite${pourquoi:+:$pourquoi}"

# LES GRANDEURS BRUTES, recopiees telles quelles : une porte qui ne publie que son total ne dit
# pas ce qui a cede.
pub irh_cost_files_scanned "$C_FICHIERS"
pub irh_cost_refusals "$C_REFUS"
pub irh_cost_all_inherited "$C_HERITE"
pub irh_cost_resolved "$C_RESOLUS"
pub irh_cost_undecidable "$C_INDEC"
pub irh_cost_items "$(c cost_items)"
pub irh_case_verdict "$R_VERDICT"
pub irh_case_attempt_base "$R_BASE"
pub irh_case_gate_base "$R_GATE_BASE"
pub irh_case_bases_agree "$R_MEME"
pub irh_case_nodes "$R_NOEUDS"
pub irh_banc_ecarts "$ECARTS"
pub irh_banc_ecarts_avant "$ECARTS_AVANT"
pub irh_banc_before_commit "$(s before_commit)"
pub irh_closures_judged "$FERMETURES"
pub irh_closures_bench "$BANC_LEGS"
pub irh_journal_runs "$J_TOTAL"
pub irh_journal_new_gate "$J_NEUVES"
pub irh_refusals_charging_inherited "$J_IMPUTES"
pub irh_ctl_imputation_detected "$J_CTL"
pub irh_ctl_signalement_detected "$J_CTL_SIG"
pub irh_census_ran "$([ -n "$COUT" ] && [ -n "$BANC" ] && echo 1 || echo 0)"

# Les bruts des deux instruments, sous un prefixe a eux : le moissonneur garde la DERNIERE
# valeur d'une cle, et un relai homonyme d'un terme du verdict l'ecraserait.
printf '%s\n' "$COUT" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/irc_\1=/p'
printf '%s\n' "$BANC" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/irb_\1=/p'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in lib/suite_gate.py lib/inherited_red_cost.py lib/inherited_red_selftest.py \
         lib/census/$ID.sh; do
  k="irh_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done

exit 0
