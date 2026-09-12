#!/usr/bin/env bash
# census/harness-naming-authority-completion.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Sa sortie `cle=valeur` rejoint celle du moteur dans le meme journal. Il n'ecrit aucun champ de
# `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, UN TERME PAR POINT DU LIVRABLE, CHAQUE TERME PUBLIE SEPAREMENT :
#   1. UN SEUL NOMMEUR      les sites qui fabriquent un nom de fichier de course    -> na_nommeur
#   2. LE BRAS D'ABLATION   par bras et par LECTEUR, nom ecrit == nom lu            -> na_bras
#   3. LES TEMOINS          convertis en comportement / restes litteraux + raison   -> na_temoins
#   4. LA PROPRETE D'ARBRE  plus aucun recensement ne l'affirme, et on nomme qui le fait
#                           respecter a sa place                                    -> na_purete
#   5. LA PURGE             deux purges ensemble sur le meme fichier                -> na_purge
#   6. LE BLOC RENDU        borne, et il dit combien il n'affiche pas               -> na_bloc
#   7. L'ORIGINE            un refus de promotion nomme d'ou vient son verdict      -> na_origine
#   8. LA CITATION          un croisillon dans une chaine ne coupe plus la ligne    -> na_citation
#   9. LE SCEAU             la paire de la course precedente est archivee           -> na_sceau
#  10. LE PERIMETRE         `code_scope` MESURE, les muets NOMMES, zero devinette   -> na_perimetre
#
# DEUX SOURCES, jamais une seule :
#   - LE BANC (`lib/naming_authority_selftest.py`) : le VRAI ecrivain, le VRAI lecteur, le VRAI
#     `backlog.py`, le VRAI bloc d'archivage de `proof_run.sh` leve entre ses marqueurs, sur des
#     etats SEMES dans des dossiers jetables. Chaque mecanisme est joue par DEUX codes — celui du
#     disque et celui d'AVANT ce chantier, ancre par MARQUEUR et jamais par `HEAD:`. Le commit
#     retenu est publie.
#   - CE DEPOT, MAINTENANT : le perimetre que chaque item declare, et la source de cette
#     declaration telle que `lib/gate_verdict.py` la lit.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte.
#
# CE QUI EST PUBLIE SANS ETRE COMPTE, ET POURQUOI.
#   * `ci_citations_recuperees` : ZERO aujourd'hui dans ce depot. Exiger qu'il soit non nul
#     serait exiger qu'une citation soit cassee quelque part. La non-vacuite vient du CONTROLE
#     NEGATIF (`ci_ctrl_vieux_perd` / `ci_ctrl_neuf_garde`), sur une ligne FABRIQUEE.
#   * `na_perimetre_muets` : 177 items sans aucun commit a leur nom. Leur perimetre ne se MESURE
#     pas, et le deviner serait blanchir la devinette qu'on veut voir. Ils sont NOMMES.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "na_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

# LE MOISSONNEUR DE proof_run.sh NE GARDE QUE `^cle=valeur$` SANS ESPACE. Une valeur qui en porte
# un ne serait publiee pour personne : on colle les espaces ICI, au point de publication.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# ===================================================================== le banc, deux bras ===
BN=$(timeout 2400 python3 "$AP/lib/naming_authority_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$BN" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ============================================ ce depot, maintenant : le perimetre declare ====
LV=$(python3 - "$ROOT" <<'PY' 2>/dev/null
import os, sys
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, '.autoport', 'lib'))
import backlog as B                                                # noqa: E402
import gate_verdict as G                                           # noqa: E402

bk = B.load()
cen = G.scope_census(bk.items)
print('live_items=%d' % len(bk.items))
print('live_scope_explicite=%d' % len(cen['explicite']))
print('live_scope_devine=%d' % len(cen['devine']))
for src, ids in sorted(cen['par_source'].items()):
    print('live_scope_src_%s=%d' % (src.replace('-', '_'), len(ids)))
muets = cen['par_source'].get(G.SRC_SILENT, [])
print('live_scope_muets=%d' % len(muets))
print('live_scope_muets_liste=%s' % (','.join(sorted(muets)[:40]) or '-'))
# L'ECRIVAIN DU CHAMP EST UNIQUE : `backlog.set_scope`, qui prend le verrou et reecrit par
# rename atomique. Une edition a la main de backlog.yaml est effacee par l'orchestrateur en
# quelques secondes — c'est mesure, pas suppose.
print('live_scope_ecrivain=%d' % (1 if hasattr(bk, 'set_scope') else 0))
print('live_scope_source_champ=%s' % G.SCOPE_FIELD)
PY
) || LV=""
l(){ printf '%s\n' "$LV" | sed -n "s/^$1=//p" | tail -1; }
ln_(){ local v; v=$(l "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ==================================================================== les termes du verdict ==
penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
eq(){ [ "$(n "$1")" = "$2" ] && echo 0 || echo 1; }
eqs(){ [ "$(s "$1")" = "$2" ] && echo 0 || echo 1; }
ge(){ [ "$(n "$1")" -ge "$2" ] 2>/dev/null && echo 0 || echo 1; }
eql(){ [ "$(ln_ "$1")" = "$2" ] && echo 0 || echo 1; }
gel(){ [ "$(ln_ "$1")" -ge "$2" ] 2>/dev/null && echo 0 || echo 1; }

[ -n "$BN" ] || faute banc-muet
[ -n "$LV" ] || faute lecture-du-depot-muette
# Chaque temoin d'AVANT est ancre par MARQUEUR — jamais par `HEAD:`, ou il s'accuserait lui-meme
# des le commit — et le marqueur doit etre VIVANT sur le disque.
for t in purge bloc origine citation paire; do
  [ "$(s "before_${t}_commit")" = "-" ] && faute "temoin-avant-$t-absent"
  [ "$(n "before_${t}_marqueur_absent")" = 1 ] || faute "temoin-avant-$t-porte-le-marqueur"
  [ "$(n "marqueur_${t}_vivant")" = 1 ] || faute "marqueur-$t-absent-du-disque"
done
for bras in pg_apres pg_avant bl_apres bl_avant or_apres or_avant; do
  [ "$(n "${bras}_ran")" = 1 ] || faute "bras-$bras-muet"
done

# --- 1. UN SEUL NOMMEUR. LE COMPTE VIENT D'UN RECENSEMENT, PAS D'UNE AFFIRMATION. -----------
t_nommeur=0
t_nommeur=$((t_nommeur + $(eq nm_sites 0)))                 # plus un seul nom fabrique
t_nommeur=$((t_nommeur + $(eq nm_marques_sans_raison 0)))   # aucun laissez-passer muet
# LE CONTROLE NEGATIF, DANS LES DEUX SENS : sans lui, `nm_sites=0` se lirait aussi bien « plus
# un seul nommeur » que « le compteur ne regarde rien ».
t_nommeur=$((t_nommeur + $(eq nm_ctrl_sans_marqueur 1)))
t_nommeur=$((t_nommeur + $(eq nm_ctrl_avec_marqueur 0)))
t_nommeur=$((t_nommeur + $(eq nm_ctrl_marque_vue 1)))
# ET LE RECENSEMENT A BIEN REGARDE QUELQUE CHOSE : le denominateur, sinon un zero ne dit rien.
t_nommeur=$((t_nommeur + $(ge nm_population 120)))
t_nommeur=$((t_nommeur + $(ge nm_lignes_lues 20000)))
t_nommeur=$((t_nommeur + $(ge nm_aiguilles 20)))

# --- 2. LE BRAS D'ABLATION EST COUVERT PARTOUT OU LE BRAS LIVRE L'EST. ----------------------
t_bras=0
for arm in livre ablation; do
  t_bras=$((t_bras + $(eq "br_${arm}_pose" 1)))
  t_bras=$((t_bras + $(eq "br_${arm}_lecteurs_egaux" 1)))   # ecrit == lu, pour CHAQUE lecteur
  t_bras=$((t_bras + $(eq "br_${arm}_lecteurs" 4)))
  t_bras=$((t_bras + $(eq "br_${arm}_vu_recensement" 1)))
  for lecteur in autorite juge recensement texte; do
    [ "$(s "br_${arm}_lu_${lecteur}")" = "$(s "br_${arm}_ecrit")" ] \
      || faute "nom-lu-different-du-nom-ecrit-$arm-$lecteur"
  done
done
t_bras=$((t_bras + $(eq br_tous_bras_egaux 1)))
t_bras=$((t_bras + $(eqs br_livre_ecrit proof-impossible.txt)))       # NOM-LITTERAL-ATTENDU: valeur-attendue-d-une-egalite
t_bras=$((t_bras + $(eqs br_ablation_ecrit proof-off-impossible.txt)))
# LE DEFAUT, MESURE : le MEME recensement, a son commit d'AVANT, sur le MEME semis d'ablation,
# ne voit RIEN. Sans cette jambe, l'egalite ci-dessus serait vraie par construction.
t_bras=$((t_bras + $(eq br_avant_vu_ablation 0)))
t_bras=$((t_bras + $(eq br_avant_marqueur_absent 1)))

# --- 3. LES TEMOINS : CONVERTIS, OU LITTERAUX AVEC LEUR RAISON. -----------------------------
t_temoins=0
t_temoins=$((t_temoins + $(eq tm_convertis 2)))
t_temoins=$((t_temoins + $(eq tm_converti_vrai 1)))
# ... et le temoin converti SAIT ROUGIR : la meme mesure sur une expression qui RE-FABRIQUE le
# nom en dur doit echouer. Un temoin de comportement qui ne peut pas tomber n'en est pas un.
t_temoins=$((t_temoins + $(eq tm_converti_controle_nom_en_dur 0)))
# LES LITTERAUX QUI RESTENT SONT COMPTES ET PORTENT UNE RAISON ECRITE.
t_temoins=$((t_temoins + $(ge nm_marques 10)))
t_temoins=$((t_temoins + $(ge nm_raisons 5)))

# --- 4. AUCUN RECENSEMENT N'AFFIRME LA PROPRETE DE L'ARBRE. ---------------------------------
t_purete=0
t_purete=$((t_purete + $(eq pu_apres_affirmations 0)))
t_purete=$((t_purete + $(ge pu_avant_affirmations 6)))      # LE DEFAUT, MESURE, avant retrait
t_purete=$((t_purete + $(ge pu_retirees 6)))
t_purete=$((t_purete + $(ge pu_recensements_lus 15)))
t_purete=$((t_purete + $(ge pu_avant_ancres 15)))
# RETIRER SANS NOMMER CE QUI PREND LA RELEVE SERAIT UN RETRAIT, PAS UNE CORRECTION : la porte
# GATE 0 refuse un arbre herite sale, GATE 1 lit `code_scope`. Les deux sont dans le code.
t_purete=$((t_purete + $(ge pu_gate0_arbre_sale 1)))
t_purete=$((t_purete + $(ge pu_gate1_lit_le_champ 1)))
t_purete=$((t_purete + $(ge pu_gate1_appelee 1)))

# --- 5. LA SUPPRESSION DE L'ETAT EST SERIALISEE PAR LE VERROU DU JOURNAL. -------------------
t_purge=0
t_purge=$((t_purge + $(eq pg_apres_echecs 0)))              # aucune collision
t_purge=$((t_purge + $(ge pg_avant_echecs 1)))              # LE DEFAUT, MESURE, meme instrument
t_purge=$((t_purge + $(eq pg_apres_semes 60)))
t_purge=$((t_purge + $(eq pg_apres_purges_cumules 60)))     # chaque etat retire UNE fois
t_purge=$((t_purge + $(eq pg_apres_restants 0)))
t_purge=$((t_purge + $(eq pg_apres_journal_lignes 60)))
t_purge=$((t_purge + $(eq pg_apres_journal_malformees 0)))
[ "$(n pg_avant_echecs)" -gt "$(n pg_apres_echecs)" ] 2>/dev/null \
  || faute verrou-de-purge-sans-effet-mesurable

# --- 6. LE BLOC RENDU EST BORNE, ET IL DIT CE QU'IL NE MONTRE PAS. -------------------------
t_bloc=0
t_bloc=$((t_bloc + $(eq bl_apres_etats 20)))
t_bloc=$((t_bloc + $(eq bl_apres_detailles 8)))
t_bloc=$((t_bloc + $(eq bl_apres_compte_publie 12)))
t_bloc=$((t_bloc + $(eq bl_apres_dit_caches 1)))
t_bloc=$((t_bloc + $(eq bl_apres_digest_dit_caches 1)))
# LE DIGEST PORTE LE COMPTE, PAS LES NOMS : son hash ne doit pas bouger parce qu'un item s'est
# ajoute a une liste que personne ne lit.
t_bloc=$((t_bloc + $(eq bl_apres_digest_nomme_les_caches 0)))
# LE BRAS D'AVANT, MEME SEMIS, MEME renderer : il detaille tout et ne dit rien.
t_bloc=$((t_bloc + $(eq bl_avant_etats 20)))
t_bloc=$((t_bloc + $(eq bl_avant_detailles 20)))
t_bloc=$((t_bloc + $(eq bl_avant_dit_caches 0)))
t_bloc=$((t_bloc + $(eq bl_avant_compte_publie -1)))        # il n'avait pas de compte a publier
[ "$(n bl_apres_len)" -lt "$(n bl_avant_len)" ] 2>/dev/null || faute bloc-rendu-non-borne

# --- 7. L'ORIGINE DU VERDICT VOYAGE AVEC LE VERDICT. ----------------------------------------
t_origine=0
t_origine=$((t_origine + $(eq or_apres_refus 1)))
t_origine=$((t_origine + $(eq or_apres_champs 4)))
t_origine=$((t_origine + $(eqs or_apres_origine journal)))
t_origine=$((t_origine + $(eq or_avant_champs 3)))          # LE DEFAUT, MESURE
t_origine=$((t_origine + $(eqs or_avant_origine -)))
t_origine=$((t_origine + $(eqs or_orch_deballe origine)))   # l'orchestrateur la RECOIT...
t_origine=$((t_origine + $(eq or_orch_imprime_origine 1)))  # ... et il l'IMPRIME

# --- 8. UN CROISILLON DANS UNE CHAINE NE COUPE PLUS LA LIGNE. ------------------------------
t_citation=0
t_citation=$((t_citation + $(eq ci_ctrl_vieux_perd 1)))     # l'ANCIENNE regle perd la citation
t_citation=$((t_citation + $(eq ci_ctrl_neuf_garde 1)))     # ... la neuve la garde
t_citation=$((t_citation + $(ge ci_lignes_differentes 1)))
t_citation=$((t_citation + $(ge ci_fichiers 120)))
t_citation=$((t_citation + $(ge ci_sources_epinglees 10)))  # la liste epinglee n'est pas vide

# --- 9. LE SCEAU : LA PAIRE DE LA COURSE PRECEDENTE SURVIT A SON EFFACEMENT. ---------------
t_sceau=0
t_sceau=$((t_sceau + $(eq sc_bloc_leve 1)))
for arm in livre ablation; do
  t_sceau=$((t_sceau + $(eq "sc_${arm}_complet_rc" 0)))
  t_sceau=$((t_sceau + $(eq "sc_${arm}_complet_prev_proof" 1)))
  t_sceau=$((t_sceau + $(eq "sc_${arm}_complet_prev_seal" 1)))
  t_sceau=$((t_sceau + $(eq "sc_${arm}_complet_prev_contenu" 1)))  # les OCTETS d'avant, pas un nom
  t_sceau=$((t_sceau + $(eq "sc_${arm}_complet_courant_parti" 1)))
  # UNE PAIRE INCOMPLETE N'EST PAS UNE PAIRE : la moitie d'avant ne reste pas a trainer.
  t_sceau=$((t_sceau + $(eq "sc_${arm}_incomplet_prev_proof" 0)))
  t_sceau=$((t_sceau + $(eq "sc_${arm}_incomplet_prev_seal" 0)))
  # ... et le globber existant (`${sf%.seal}.txt`) apparie les deux noms neufs sans rien savoir
  # d'eux : sans ca la paire archivee serait invisible a celui-la meme qui la cherche.
  t_sceau=$((t_sceau + $(eq "sc_${arm}_appariable" 1)))
done

# --- 10. LE PERIMETRE SE DECLARE, IL NE SE DEVINE PLUS. ------------------------------------
t_perimetre=0
t_perimetre=$((t_perimetre + $(eql live_scope_devine 0)))   # plus une seule decision sur la prose
t_perimetre=$((t_perimetre + $(gel live_scope_explicite 60)))
t_perimetre=$((t_perimetre + $(gel live_items 200)))
t_perimetre=$((t_perimetre + $(eql live_scope_ecrivain 1)))
[ "$(l live_scope_source_champ)" = "code_scope" ] || faute champ-de-perimetre-renomme
# LES MUETS SONT NOMMES, PAS DEVINES : on publie leur compte et leur liste, on ne les compte pas
# comme un defaut. Deviner leur perimetre serait blanchir exactement la devinette qu'on retire.

TOTAL=$((t_nommeur + t_bras + t_temoins + t_purete + t_purge + t_bloc + t_origine \
         + t_citation + t_sceau + t_perimetre + penalty))

# ========================================================================= la publication ====
pub na_census_ran "$([ -n "$BN" ] && [ -n "$LV" ] && echo 1 || echo 0)"
pub naming_authority_defects "$TOTAL"
pub naming_authority_defects_terms \
  "nommeur$t_nommeur+bras$t_bras+temoins$t_temoins+purete$t_purete+purge$t_purge+bloc$t_bloc+origine$t_origine+citation$t_citation+sceau$t_sceau+perimetre$t_perimetre+penalite$penalty${why:+:$why}"
pub na_nommeur "$t_nommeur"
pub na_bras "$t_bras"
pub na_temoins "$t_temoins"
pub na_purete "$t_purete"
pub na_purge "$t_purge"
pub na_bloc "$t_bloc"
pub na_origine "$t_origine"
pub na_citation "$t_citation"
pub na_sceau "$t_sceau"
pub na_perimetre "$t_perimetre"
pub na_witness_penalty "$penalty"

# 1. LE RECENSEMENT DES NOMMEURS, AVEC SON DENOMINATEUR ET SES CONTROLES.
pub naming_sites "$(n nm_sites)"
pub naming_sites_list "$(s nm_sites_liste)"
pub naming_population "$(n nm_population)"
pub naming_lines_scanned "$(n nm_lignes_lues)"
pub naming_needles "$(n nm_aiguilles)"
pub naming_ctrl_unmarked "$(n nm_ctrl_sans_marqueur)"
pub naming_ctrl_marked "$(n nm_ctrl_avec_marqueur)"

# 2. LE NOM ECRIT ET LE NOM LU, PAR BRAS ET PAR LECTEUR. L'EGALITE EST LE VERDICT.
for arm in livre ablation; do
  pub "naming_${arm}_written" "$(s "br_${arm}_ecrit")"
  for lecteur in autorite juge recensement texte; do
    pub "naming_${arm}_read_${lecteur}" "$(s "br_${arm}_lu_${lecteur}")"
  done
  pub "naming_${arm}_readers_equal" "$(n "br_${arm}_lecteurs_egaux")"
done
pub naming_before_census_saw_ablation "$(n br_avant_vu_ablation)"
pub naming_before_census_commit "$(s br_avant_commit)"

# 3. LES TEMOINS : CONVERTIS, ET RESTES LITTERAUX AVEC LEUR RAISON.
pub naming_witnesses_converted "$(n tm_convertis)"
pub naming_witnesses_converted_list "$(s tm_convertis_liste)"
pub naming_witnesses_converted_control "$(n tm_converti_controle_nom_en_dur)"
pub naming_witnesses_literal "$(n nm_marques)"
pub naming_witnesses_literal_list "$(s nm_marques_liste)"
pub naming_witnesses_literal_reasons "$(s nm_raisons_liste)"
pub naming_witnesses_literal_unreasoned "$(n nm_marques_sans_raison)"

# 4. LA PROPRETE D'ARBRE : RETIREE ICI, TENUE LA-BAS.
pub naming_tree_purity_after "$(n pu_apres_affirmations)"
pub naming_tree_purity_before "$(n pu_avant_affirmations)"
pub naming_tree_purity_removed "$(n pu_retirees)"
pub naming_tree_purity_details "$(s pu_avant_details)"
pub naming_gate0_dirty_reader "$(n pu_gate0_arbre_sale)"
pub naming_gate1_scope_reader "$(n pu_gate1_lit_le_champ)"

# 5. LA PURGE, DEUX BRAS, MEME INSTRUMENT.
pub naming_purge_seeded "$(n pg_apres_semes)"
pub naming_purge_removed_after "$(n pg_apres_purges_cumules)"
pub naming_purge_failures_after "$(n pg_apres_echecs)"
pub naming_purge_failures_before "$(n pg_avant_echecs)"
pub naming_purge_journal_lines "$(n pg_apres_journal_lignes)"
pub naming_purge_journal_malformed "$(n pg_apres_journal_malformees)"

# 6. LE BLOC RENDU, LES DEUX BRAS.
pub naming_block_states "$(n bl_apres_etats)"
pub naming_block_detailed_after "$(n bl_apres_detailles)"
pub naming_block_hidden_after "$(n bl_apres_compte_publie)"
pub naming_block_detailed_before "$(n bl_avant_detailles)"
pub naming_block_len_after "$(n bl_apres_len)"
pub naming_block_len_before "$(n bl_avant_len)"
pub naming_block_says_hidden "$(n bl_apres_dit_caches)"

# 7. L'ORIGINE DU VERDICT.
pub naming_refusal_fields_after "$(n or_apres_champs)"
pub naming_refusal_fields_before "$(n or_avant_champs)"
pub naming_refusal_origin "$(s or_apres_origine)"
pub naming_orchestrator_prints_origin "$(n or_orch_imprime_origine)"

# 8. LA CITATION.
pub naming_comment_lines_differ "$(n ci_lignes_differentes)"
pub naming_comment_files_differ "$(n ci_decoupage_different)"
pub naming_citations_recovered "$(n ci_citations_recuperees)"
pub naming_citation_ctrl_old_loses "$(n ci_ctrl_vieux_perd)"
pub naming_citation_ctrl_new_keeps "$(n ci_ctrl_neuf_garde)"
pub naming_pinned_sources "$(n ci_sources_epinglees)"

# 9. LE SCEAU.
pub naming_seal_block_lifted "$(n sc_bloc_leve)"
for arm in livre ablation; do
  pub "naming_seal_${arm}_prev_pair" "$(n "sc_${arm}_complet_prev_proof")"
  pub "naming_seal_${arm}_prev_bytes" "$(n "sc_${arm}_complet_prev_contenu")"
  pub "naming_seal_${arm}_partial_kept" "$(n "sc_${arm}_incomplet_prev_proof")"
  pub "naming_seal_${arm}_pairable" "$(n "sc_${arm}_appariable")"
done

# 10. LE PERIMETRE, LU SUR LE DEPOT MAINTENANT.
pub naming_scope_items "$(ln_ live_items)"
pub naming_scope_explicit "$(ln_ live_scope_explicite)"
pub naming_scope_guessed "$(ln_ live_scope_devine)"
pub naming_scope_silent "$(ln_ live_scope_muets)"
pub naming_scope_silent_list "$(l live_scope_muets_liste)"
pub naming_scope_writer "$(ln_ live_scope_ecrivain)"

# LES BRUTS, recopies tels quels : c'est ce qui rend la somme lisible et falsifiable. Sous un
# prefixe a eux — le moissonneur garde la DERNIERE valeur d'une cle, et un homonyme ecraserait
# un terme du verdict.
brut(){ awk -v p="$1" -F= '/^[a-z_][a-z0-9_]*=/ {k=$1; sub(/^[^=]*=/,"",$0);
          gsub(/[[:space:]]+/,"_",$0); if($0=="") $0="-"; printf "%s%s=%s\n", p, k, $0}'; }
printf '%s\n' "$BN" | brut na_bn_
printf '%s\n' "$LV" | brut na_live_

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in lib/impossible.py lib/proof_run.sh lib/backlog.py lib/verdict_sources.sh \
         lib/gate_verdict.py validators/generic.sh lib/foreign_cause_selftest.py \
         lib/naming_authority_selftest.py lib/census/harness-naming-authority-completion.sh; do
  k="na_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
