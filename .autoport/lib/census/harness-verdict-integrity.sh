#!/usr/bin/env bash
# census/harness-verdict-integrity.sh — LE VERDICT DE L'ITEM `harness-verdict-integrity`.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course,
# sa sortie `cle=valeur` rejoignant celle du moteur dans le meme journal. Il ne peut ecrire
# aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, ET DANS QUEL ORDRE (les cinq points du livrable) :
#   1. le juge epingle les sources qui PRODUISENT le verdict -> vi_validator_unpinned
#   2. le teardown de FIN de course dit ce qu'il efface      -> vi_teardown_end_silent
#   3. le bras x86 relit /proc/<pid>/environ du processus MESURE -> vi_env_proc_unread
#   4. un getprop global muet est DISTINGUE d'un appareil nu -> vi_getprop_mute_conflated
#   5. la fenetre d'ablation n'est plus un compte de commits -> vi_window_commit_capped
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte. Un banc qui n'a
# pas tourne, une jambe de controle qui ne PASSE pas, un bras d'ablation aussi bavard que le
# bras neuf : tout cela rend la porte ROUGE. Sans cette polarite, une porte `== 0` sur une
# integrite est verte par INACTION.
#
# LA JAMBE `ok` EST LE CONTROLE A LAISSER. Les quatre autres jambes du juge sont des refus ;
# sans une jambe qui PASSE, un validateur qui refuserait tout les tiendrait toutes.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "vi_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

RAW=$(bash "$AP/lib/verdict_integrity_selftest.sh" 2>/dev/null)
g(){ printf '%s\n' "$RAW" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque ou n'est pas un nombre. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(g "$1"); case "$v" in ''|*[!0-9-]*|-) echo -1 ;; *) echo "$v" ;; esac; }
pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
eq(){ [ "$(n "$1")" = "$2" ] && echo 0 || echo 1; }
eqs(){ [ "$(g "$1")" = "$2" ] && echo 0 || echo 1; }
ge(){ [ "$(n "$1")" -ge "$2" ] 2>/dev/null && echo 0 || echo 1; }

[ -n "$RAW" ] || faute banc-muet
[ "$(n vi_selftest_ran)" = 1 ] || faute banc-non-abouti

# ============== 1. LE JUGE EPINGLE LES SOURCES QUI PRODUISENT LE VERDICT, `.autoport/` COMPRISE
# Cinq jambes sur le VRAI `validators/generic.sh`. La premiere PASSE (controle a laisser), les
# quatre autres REFUSENT, chacune pour la raison qui lui est propre — et `touche` prouve que la
# fraicheur ne se reduit pas a l'empreinte : un `touch` ne change aucun octet.
t_pin=0
for j in ok edite aide touche absent; do
  t_pin=$((t_pin + $(eq "va_${j}_monte" 1)))
done
t_pin=$((t_pin + $(eq va_ok_rc 0)))          # le controle a laisser
t_pin=$((t_pin + $(eq va_ok_change 0)))
t_pin=$((t_pin + $(eq va_ok_vieille 0)))
t_pin=$((t_pin + $(eq va_ok_absente 0)))
t_pin=$((t_pin + $(ge va_ok_epingles 4)))    # la liste n'est pas vide : la porte n'est pas vacante
t_pin=$((t_pin + $(eq va_edite_rc 1)))       # recensement EDITE apres la course
t_pin=$((t_pin + $(eq va_edite_change 1)))
t_pin=$((t_pin + $(eq va_aide_rc 1)))        # fichier atteint par la DERIVATION, jamais nomme
t_pin=$((t_pin + $(eq va_aide_change 1)))
t_pin=$((t_pin + $(eq va_touche_rc 1)))      # meme contenu, mtime plus recent
t_pin=$((t_pin + $(eq va_touche_vieille 1)))
t_pin=$((t_pin + $(eq va_touche_change 0)))  # ... et SEULEMENT pour cette raison
t_pin=$((t_pin + $(eq va_absent_rc 1)))      # preuve sans empreinte
t_pin=$((t_pin + $(eq va_absent_absente 1)))

# ================================ 2. LE TEARDOWN DE FIN DE COURSE DIT CE QU'IL EFFACE ==========
# Observable nulle part sans telephone : c'est le bac a sable de l'epinglage qui lance le VRAI
# `proof_run.sh` en mode appareil. Le bras VIEUX (scripts d'avant le correctif) doit etre MUET.
t_fin=0
t_fin=$((t_fin + $(eq vi_pin_arm_neuf_teardown_fin_ran 1)))
t_fin=$((t_fin + $(ge vi_pin_arm_neuf_teardown_fin_props_found 2)))
[ "$(g vi_pin_arm_neuf_teardown_fin_props_found)" = "$(g vi_pin_arm_neuf_teardown_fin_props_cleared)" ] \
  || faute teardown-fin-nomme-sans-effacer
case "$(g vi_pin_arm_neuf_teardown_fin_props_list)" in
  *debug.opengoal.hdr.out*) ;; *) faute teardown-fin-ne-nomme-pas ;;
esac
# L'ABLATION, GRATUITE : le bras vieux ne publie AUCUNE cle de teardown de fin.
[ -z "$(g vi_pin_arm_vieux_teardown_fin_ran)" ] || faute bras-vieux-deja-corrige

# ============================ 3. LE BRAS x86 RELIT /proc/<pid>/environ DU PROCESSUS MESURE =====
# Lu dans le fichier que CETTE course vient d'ecrire — `proof.txt` n'existe pas encore quand ce
# recensement tourne. Le nom sort de l'autorite de nommage, jamais d'un litteral ecrit ici.
ENVNOM=$(python3 - "${AUTOPORT_CENSUS_ARMED:-1}" <<'PY' 2>/dev/null
import sys
sys.path.insert(0, '.autoport/lib')
import impossible as I
print(I.arm_name('env', I.arm_suffix(sys.argv[1])))
PY
)
ENVF="${AUTOPORT_CENSUS_DIR:-$AP/reports/harness-verdict-integrity}/${ENVNOM:-nom-non-derive}"
e(){ sed -n "s/^$1=//p" "$ENVF" 2>/dev/null | tail -1; }
en(){ local v; v=$(e "$1"); case "$v" in ''|*[!0-9-]*|-) echo -1 ;; *) echo "$v" ;; esac; }
t_env=0
if [ ! -s "$ENVF" ]; then
  t_env=5; faute relecture-environnement-non-publiee
else
  [ "$(en proof_env_proc_read)" = 1 ] || t_env=$((t_env+1))
  [ "$(en proof_env_proc_count)" -ge 1 ] 2>/dev/null || t_env=$((t_env+1))
  [ "$(en proof_env_shell_count)" -ge 1 ] 2>/dev/null || t_env=$((t_env+1))
  # LE PROCESSUS MESURE, PAS LE SHELL : son `exe` est le binaire que la preuve juge.
  [ "$(e proof_env_proc_exe)" = "$(basename "$(e proof_env_binary)")" ] || t_env=$((t_env+1))
  [ "$(e proof_env_proc_pid)" != "-" ] || t_env=$((t_env+1))
fi

# ================== 4. UN `getprop` GLOBAL MUET N'EST PAS UN APPAREIL SANS PROPRIETES ==========
# Deux jambes sur le VRAI `lib/device_teardown.sh`. Les deux TOURNENT ; elles different sur
# l'enumeration. Dans la jambe muette, une propriete absente de la liste de secours est ratee :
# c'est exactement ce qui se lisait « rien n'etait pose ».
t_getp=0
t_getp=$((t_getp + $(eq td_plein_monte 1)))
t_getp=$((t_getp + $(eq td_muet_monte 1)))
t_getp=$((t_getp + $(eq td_plein_ran 1)))
t_getp=$((t_getp + $(eq td_muet_ran 1)))
t_getp=$((t_getp + $(eq td_plein_getprop_ok 1)))
t_getp=$((t_getp + $(ge td_plein_getprop_total 3)))
t_getp=$((t_getp + $(eqs td_plein_props_source enumere)))
t_getp=$((t_getp + $(eq td_plein_props_found 2)))
t_getp=$((t_getp + $(eq td_plein_inconnue_vue 1)))
t_getp=$((t_getp + $(eq td_muet_getprop_ok 0)))
t_getp=$((t_getp + $(eq td_muet_getprop_total 0)))
t_getp=$((t_getp + $(eqs td_muet_props_source secours)))
t_getp=$((t_getp + $(eq td_muet_props_found 1)))
t_getp=$((t_getp + $(eq td_muet_inconnue_vue 0)))

# ====================== 5. LA FENETRE D'ABLATION N'EST PLUS UN COMPTE DE COMMITS ===============
# La meche, allumee pour de vrai : un depot ou l'introduction est a 66 commits de HEAD. Ancienne
# fenetre AVEUGLE, ancre de contenu juste. Et sur le depot REEL, les cinq couples rendent le MEME
# commit qu'avant : le verdict d'aucun item deja ferme ne bouge.
t_win=0
t_win=$((t_win + $(eq audit_capped 0)))
t_win=$((t_win + $(ge win_hist_commits 61)))
t_win=$((t_win + $(eq win_old_found 0)))     # l'ancienne fenetre ne voyait RIEN
t_win=$((t_win + $(eq win_new_found 1)))
t_win=$((t_win + $(eq win_new_juste 1)))
t_win=$((t_win + $(eqs win_new_method introduction)))
[ "$(n win_new_depth)" -gt "$(n win_legacy_window)" ] 2>/dev/null || faute meche-non-allumee
t_win=$((t_win + $(eq par_total 5)))
t_win=$((t_win + $(eq par_same 5)))          # AUCUN verdict deja ferme ne bouge
t_win=$((t_win + $(eq par_new_ok 5)))
t_win=$((t_win + $(eqs vi_pin_ablation_proof_method introduction)))
t_win=$((t_win + $(eqs vi_pin_ablation_teardown_method introduction)))
[ -n "$(g vi_pin_ablation_proof_commit)" ] || faute ancre-vivante-absente

# ================================================ les temoins sans lesquels rien ne se lit =====
[ "$(n vi_pin_lu)" = 1 ] || faute bac-a-sable-epinglage-muet
[ "$(n vi_pin_selftest_arms_ok)" = 2 ] || faute bras-manquant
[ "$(n vi_pin_arm_neuf_proof)" = 1 ] || faute bras-neuf-sans-preuve
[ "$(n vi_pin_arm_vieux_proof)" = 1 ] || faute bras-vieux-sans-preuve

TOTAL=$((t_pin + t_fin + t_env + t_getp + t_win + penalty))

# ======================================================================== la publication ======
pub vi_census_ran "$([ -n "$RAW" ] && echo 1 || echo 0)"
pub verdict_integrity_defects "$TOTAL"
pub verdict_integrity_terms \
  "juge$t_pin+teardownfin$t_fin+environ$t_env+getprop$t_getp+fenetre$t_win+penalite$penalty${why:+:$why}"
pub vi_validator_unpinned "$t_pin"
pub vi_teardown_end_silent "$t_fin"
pub vi_env_proc_unread "$t_env"
pub vi_getprop_mute_conflated "$t_getp"
pub vi_window_commit_capped "$t_win"
pub vi_witness_penalty "$penalty"

# LA RELECTURE DE CETTE COURSE, recopiee telle quelle : c'est la seule grandeur du verdict qui
# ne vienne pas d'un bac a sable mais de la preuve en train de se faire.
pub vi_env_proc_pid "$(e proof_env_proc_pid)"
pub vi_env_proc_exe "$(e proof_env_proc_exe)"
pub vi_env_proc_read "$(e proof_env_proc_read)"
pub vi_env_proc_count "$(e proof_env_proc_count)"
pub vi_env_shell_count "$(e proof_env_shell_count)"
pub vi_env_proc_gap "$(( $(en proof_env_shell_count) - $(en proof_env_proc_count) ))"
pub vi_env_file "${ENVNOM:--}"

# LES GRANDEURS BRUTES, sous un prefixe a elles : un relai homonyme d'un terme du verdict
# ecraserait le terme (le moissonneur garde la DERNIERE valeur d'une cle). Une valeur VIDE est
# publiee `-` : le moissonneur jette `cle=` et la cle disparaitrait sans qu'on sache pourquoi.
printf '%s\n' "$RAW" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/vi_bn_\1=/p' | sed 's/=$/=-/'
