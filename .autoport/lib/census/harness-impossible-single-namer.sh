#!/usr/bin/env bash
# census/harness-impossible-single-namer.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Sa sortie `cle=valeur` rejoint celle du moteur dans le meme journal. Il n'ecrit aucun champ
# de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, DANS L'ORDRE DES QUATRE POINTS DU LIVRABLE :
#   1. l'ECRIVAIN et le LECTEUR derivent le nom du MEME endroit, SUR LES DEUX BRAS —
#      l'ablation comprise, c'est elle qui etait aveugle                        -> sn_noms
#   2. la sortie du JUGE ne commence plus par un diagnostic que la porte contredit,
#      mesure sur un etat SEME, sans qu'un seul constat disparaisse              -> sn_juge
#   3. le journal des purges a UN seul ecrivain et une BORNE                     -> sn_journal
#   4. un etat debout sur un item HORS FILE figure dans le texte RENDU           -> sn_texte
#
# DEUX SOURCES, jamais une seule :
#   - LE BANC (`lib/single_namer_selftest.py`) : le VRAI ecrivain, le VRAI juge, le VRAI
#     `status_report`, le VRAI journal, sur des etats SEMES dans des dossiers jetables. Chaque
#     mecanisme est joue par DEUX codes — celui du disque et celui d'AVANT ce chantier, ancre
#     par MARQUEUR et jamais par `HEAD:`. Le commit retenu est publie.
#   - CE DEPOT, MAINTENANT : le journal des purges, les etats encore debout, et le nom que
#     l'autorite derive pour LE bras de la course en train de se faire.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte.
#
# CE QUI EST PUBLIE SANS ETRE COMPTE, ET POURQUOI. Le journal VIVANT de ce depot (0 octet le
# 12/09) : exiger des purges reelles serait exiger une panne. Les noms d'etat encore codes en
# dur chez d'AUTRES items : les corriger casserait le temoin epingle d'un item deja valide, ils
# partent en signalement. La non-vacuite vient du semis, ou tout est FABRIQUE a chaque course
# par les vrais producteurs — et du CONTROLE NEGATIF du compteur de sites d'ecriture.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "sn_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

# LE MOISSONNEUR DE proof_run.sh NE GARDE QUE `^cle=valeur$` SANS ESPACE. Une valeur avec des
# espaces — « 6 h 38 », la premiere ligne du juge — n'arriverait JAMAIS dans proof.txt : elle
# serait publiee pour personne. On colle donc les espaces ICI, au point de publication.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# ===================================================================== le banc, deux bras ===
BN=$(timeout 900 python3 "$AP/lib/single_namer_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$BN" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ================================================ ce depot, et la course en train de se faire =
LV=$(python3 - "$ROOT" "${AUTOPORT_CENSUS_ARMED:-1}" <<'PY' 2>/dev/null
import os, sys
root, armed = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(root, '.autoport', 'lib'))
import impossible as I                                             # noqa: E402

reports = os.path.join(root, '.autoport', 'reports')
suf = I.arm_suffix(armed)
print('run_arm=%s' % (suf or 'livre'))
print('run_state_name=%s' % I.arm_name('impossible', suf))
print('run_kinds=%d' % len(I.KINDS))

# LE JOURNAL DES PURGES DE CE DEPOT. Publie, jamais compte : un zero s'y lit « rien a purger »,
# et le denominateur a cote dit que quelque chose a bien ete regarde.
st = I.journal_stats(reports)
for k in ('bytes', 'rotated_bytes', 'max_bytes', 'over_bound', 'lines', 'legacy',
          'malformed', 'lock_available'):
    print('live_journal_%s=%s' % (k, st[k]))
print('live_journal_writers=%d' % len(st['writers']))
print('live_journal_writers_list=%s' % (','.join(st['writers']) or '-'))
print('live_journal_callers_list=%s' % (','.join(st['callers']) or '-'))
print('live_journal_path=%s' % os.path.relpath(st['path'], root))

deb = I.standing(reports)
print('live_standing=%d' % len(deb))
print('live_scanned=%d' % len(I.scan(reports)))
print('live_standing_list=%s' % (','.join('%s@%ss' % (d['item'], d['age_s'])
                                          for d in deb) or '-'))
PY
) || LV=""
l(){ printf '%s\n' "$LV" | sed -n "s/^$1=//p" | tail -1; }
ln_(){ local v; v=$(l "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ==================================================================== les termes du verdict ==
penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
eq(){ [ "$(n "$1")" = "$2" ] && echo 0 || echo 1; }
eqs(){ [ "$(s "$1")" = "$2" ] && echo 0 || echo 1; }
eql(){ [ "$(l "$1")" = "$2" ] && echo 0 || echo 1; }

# Le banc doit AVOIR tourne, chaque bras doit avoir joue, et chaque temoin d'AVANT doit etre
# ancre par MARQUEUR — jamais par `HEAD:`, ou il s'accuserait lui-meme des le commit.
[ -n "$BN" ] || faute banc-muet
[ -n "$LV" ] || faute lecture-du-depot-muette
for t in writer validator backlog journal; do
  [ "$(s "before_${t}_commit")" = "-" ] && faute "temoin-avant-$t-absent"
  [ "$(n "before_${t}_marker_absent")" = 1 ] || faute "temoin-avant-$t-porte-le-marqueur"
done
for m in writer validator backlog journal run; do
  [ "$(n "src_marker_$m")" = 1 ] || faute "marqueur-$m-absent-du-disque"
done
for bras in vl_apres vl_avant tx_apres tx_avant; do
  [ "$(n "${bras}_ran")" = 1 ] || faute "bras-$bras-muet"
done

# --- 1. LE NOM, PAR BRAS, L'ABLATION COMPRISE. L'EGALITE EST LE VERDICT. --------------------
t_noms=0
for arm in livre ablation; do
  t_noms=$((t_noms + $(eq "nm_${arm}_rc" 0)))
  t_noms=$((t_noms + $(eq "nm_${arm}_fichiers" 1)))     # UN fichier pose, pas deux noms
  t_noms=$((t_noms + $(eq "nm_${arm}_egal" 1)))         # ecrit == lu
  t_noms=$((t_noms + $(eq "nm_${arm}_cles" 12)))        # l'etat lui-meme n'a pas bouge
  t_noms=$((t_noms + $(eq "nm_${arm}_relu" 1)))         # ... et le LECTEUR le retrouve
  [ "$(s "nm_${arm}_ecrit")" = "$(s "nm_${arm}_lu")" ] || faute "nom-ecrit-different-du-nom-lu-$arm"
done
t_noms=$((t_noms + $(eqs nm_livre_lu proof-impossible.txt)))  # NOM-LITTERAL-ATTENDU: valeur-attendue-d-une-egalite
t_noms=$((t_noms + $(eqs nm_ablation_lu proof-off-impossible.txt)))  # NOM-LITTERAL-ATTENDU: valeur-attendue-d-une-egalite
t_noms=$((t_noms + $(eqs nm_livre_relu_bras livre)))
t_noms=$((t_noms + $(eqs nm_ablation_relu_bras ablation)))
# LA GARDE, EXERCEE DANS LES DEUX SENS : autorite injoignable -> l'ecrivain d'APRES refuse et ne
# pose RIEN ; celui d'AVANT pose quand meme un nom qu'il a fabrique seul. C'est une difference
# de COMPORTEMENT, pas de texte.
t_noms=$((t_noms + $(eq nm_garde_apres_rc 2)))
t_noms=$((t_noms + $(eq nm_garde_apres_fichiers 0)))
t_noms=$((t_noms + $(eq nm_garde_avant_rc 0)))
t_noms=$((t_noms + $(eq nm_garde_avant_fichiers 1)))
t_noms=$((t_noms + $(eq nm_avant_demande_autorite 0)))
t_noms=$((t_noms + $(eq nm_apres_demande_autorite 1)))
t_noms=$((t_noms + $(eq nm_ecrivain_litteral 0)))       # plus un seul nom fabrique par l'ecrivain
t_noms=$((t_noms + $(eq nm_apres_cles_texte 12)))
t_noms=$((t_noms + $(eq nm_avant_cles_texte 12)))       # l'etat ECRIT est identique mot pour mot
# ... et le nom que l'autorite derive pour LE bras de la course en train de se faire.
[ "$(l run_state_name)" = "$(s "nm_$([ "${AUTOPORT_CENSUS_ARMED:-1}" = 1 ] && echo livre || echo ablation)_lu")" ] \
  || faute nom-de-ce-bras-non-derive-par-l-autorite

# --- 2. LA SORTIE DU JUGE : LA CAUSE D'ABORD, ET PAS UN CONSTAT DE MOINS. -------------------
t_juge=0
t_juge=$((t_juge + $(eq vl_semis_etat 1)))              # l'etat SEME existe...
t_juge=$((t_juge + $(eq vl_semis_lu 1)))                # ... et l'autorite le lit
t_juge=$((t_juge + $(eq vl_apres_l1_dit_impossible 1)))
t_juge=$((t_juge + $(eq vl_apres_l1_dit_absent 0)))
t_juge=$((t_juge + $(eq vl_apres_l1_nomme_cause 1)))
t_juge=$((t_juge + $(eq vl_apres_l1_nomme_age 1)))      # « 6 h 38 », pas « il y a un moment »
t_juge=$((t_juge + $(eq vl_apres_contredit 0)))
t_juge=$((t_juge + $(eq vl_apres_corps_intact 1)))      # le constat du juge n'est pas masque
t_juge=$((t_juge + $(eq vl_apres_rc 1)))                # ... et il refuse toujours
# LE BRAS D'AVANT, sur LE MEME semis : sa premiere ligne accuse une absence que la porte
# requalifie plus bas.
t_juge=$((t_juge + $(eq vl_avant_l1_dit_absent 1)))
t_juge=$((t_juge + $(eq vl_avant_l1_dit_impossible 0)))
t_juge=$((t_juge + $(eq vl_avant_contredit 1)))
t_juge=$((t_juge + $(eq vl_avant_rc 1)))
# RIEN N'A ETE ASSOUPLI : le MEME nombre de constats des deux cotes. Un juge qui nomme la cause
# et qui compte un constat de moins serait un faux vert, pas un progres.
[ "$(n vl_apres_constats)" = "$(n vl_avant_constats)" ] || faute constats-du-juge-modifies
[ "$(n vl_apres_constats)" -ge 1 ] 2>/dev/null || faute juge-sans-constat
# LE CONTROLE A LAISSER : un echec ORDINAIRE ne gagne pas l'en-tete. Une premiere ligne qui
# crierait « impossible » sur tous les echecs ne dirait plus rien.
t_juge=$((t_juge + $(eq vl_ordinaire_l1_dit_impossible 0)))
t_juge=$((t_juge + $(eq vl_ordinaire_contredit 0)))
t_juge=$((t_juge + $(eq src_juge_appelle_autorite 1)))
t_juge=$((t_juge + $(eq src_juge_litteral_etat 0)))     # le juge ne fabrique aucun nom

# --- 3. LE JOURNAL : UN SEUL ECRIVAIN, UNE BORNE. ------------------------------------------
t_journal=0
t_journal=$((t_journal + $(eq jn_sites 1)))                 # UN site d'ecriture dans tout .autoport
t_journal=$((t_journal + $(eqs jn_sites_liste "impossible.py:1")))
t_journal=$((t_journal + $(eq jn_sites_controle_negatif 2)))  # le compteur SAIT monter a deux
# LES DEUX APPELANTS REELS, chacun par SON geste : l'orchestrateur dans son processus, la course
# par la CLI. Un seul ecrivain, deux appelants NOMMES.
t_journal=$((t_journal + $(eq jn_appelants_purge_orch 1)))
t_journal=$((t_journal + $(eq jn_appelants_lignes 2)))
t_journal=$((t_journal + $(eq jn_appelants_ecrivains 1)))
t_journal=$((t_journal + $(eqs jn_appelants_ecrivains_liste lib/impossible.py)))
t_journal=$((t_journal + $(eq jn_appelants 2)))
t_journal=$((t_journal + $(eqs jn_appelants_liste "course,orchestrateur")))
t_journal=$((t_journal + $(eq jn_appelants_malformees 0)))
# SIX PROCESSUS SUR LE MEME JOURNAL : le compte est exact et aucune ligne n'est coupee.
t_journal=$((t_journal + $(eq jn_conc_lignes 900)))
t_journal=$((t_journal + $(eq jn_conc_attendu 900)))
t_journal=$((t_journal + $(eq jn_conc_malformees 0)))
t_journal=$((t_journal + $(eq jn_conc_ecrivains 1)))
t_journal=$((t_journal + $(eq jn_conc_appelants 6)))
t_journal=$((t_journal + $(eq jn_conc_verrou 1)))
# LA BORNE, LES DEUX BRAS, JUGEE PAR LA MEME BORNE : le bras d'avant n'en declarait aucune.
t_journal=$((t_journal + $(eq jn_borne_hors_portee 0)))   # une borne hors de portee n'en est pas une
t_journal=$((t_journal + $(eq jn_borne_apres_ran 1)))
t_journal=$((t_journal + $(eq jn_borne_apres_sous_borne 1)))
t_journal=$((t_journal + $(eq jn_borne_apres_rotation 1)))
t_journal=$((t_journal + $(eq jn_borne_avant_ran 1)))
t_journal=$((t_journal + $(eq jn_borne_avant_sous_borne 0)))   # sans borne, il deborde
t_journal=$((t_journal + $(eq jn_borne_avant_rotation 0)))
[ "$(n jn_borne_avant_octets)" -gt "$(n jn_borne_apres_octets)" ] 2>/dev/null \
  || faute borne-sans-effet-mesurable
[ "$(n jn_borne_apres_lignes_relues)" -gt 0 ] 2>/dev/null || faute journal-borne-illisible
t_journal=$((t_journal + $(eq src_orch_who 1)))
t_journal=$((t_journal + $(eq src_run_who 1)))
# CE DEPOT : son journal ne deborde pas et ne porte aucune ligne cassee.
t_journal=$((t_journal + $(eql live_journal_over_bound 0)))
t_journal=$((t_journal + $(eql live_journal_malformed 0)))

# --- 4. LE TEXTE RENDU : L'ETAT SE LIT PARTOUT OU IL EXISTE. -------------------------------
t_texte=0
t_texte=$((t_texte + $(eq tx_apres_semes 3)))
t_texte=$((t_texte + $(eq tx_avant_semes 3)))            # MEME semis des deux cotes
t_texte=$((t_texte + $(eq tx_apres_section 1)))
t_texte=$((t_texte + $(eq tx_apres_nomme_valide 1)))     # l'item VALIDE y figure enfin
t_texte=$((t_texte + $(eq tx_apres_nomme_fantome 1)))    # ... et l'id qui n'est plus au backlog
t_texte=$((t_texte + $(eq tx_apres_dit_hors_file 1)))    # « hors file » n'est pas « en cours »
# LE CONTROLE A LAISSER : l'item EN COURS reste nomme. Un bloc qui grossit en perdant ce qu'il
# disait deja ne prouverait rien.
t_texte=$((t_texte + $(eq tx_apres_nomme_en_cours 1)))
t_texte=$((t_texte + $(eq tx_avant_nomme_en_cours 1)))
# LE BRAS D'AVANT, MEME semis, MEME renderer : il ne nomme NI le valide NI le fantome.
t_texte=$((t_texte + $(eq tx_avant_nomme_valide 0)))
t_texte=$((t_texte + $(eq tx_avant_nomme_fantome 0)))
t_texte=$((t_texte + $(eq tx_avant_dit_hors_file 0)))
t_texte=$((t_texte + $(eq tx_avant_section 1)))
[ "$(n tx_apres_len)" -gt "$(n tx_avant_len)" ] 2>/dev/null || faute texte-rendu-inchange
[ "$(s tx_apres_bloc)" = "-" ] && faute bloc-rendu-apres-non-publie
[ "$(s tx_avant_bloc)" = "-" ] && faute bloc-rendu-avant-non-publie
t_texte=$((t_texte + $(eq src_bl_lit_tout 1)))
t_texte=$((t_texte + $(eq src_bl_un_renderer 1)))        # UN renderer, deux jeux d'items

# --- HORS PERIMETRE : les MOTIFS de purge, la DETECTION, et le jeu. -------------------------
[ "$(s src_raisons_purge)" = "$(s src_raisons_purge_avant)" ] || faute motifs-de-purge-modifies
[ "$(s src_die3_raisons)" = "$(s src_die3_raisons_avant)" ] || faute detection-de-l-impossibilite-modifiee
[ "$(n src_cles_etat)" = 12 ] || faute cles-de-l-etat-modifiees
# LA PROPRETE DE L'ARBRE N'EST PLUS AFFIRMEE ICI (signalement 5 du 12/09, chantier
# harness-naming-authority-completion). Un recensement qui assert `git diff --quiet` ou
# `git status --porcelain` rougit pour TOUT chantier qui touche le fichier surveille,
# pour une raison qui n'est pas la sienne. C'est le travail des PORTES — GATE 0 refuse un
# arbre herite sale, GATE 1 lit `code_scope` — pas d'un instrument. La grandeur reste
# PUBLIEE plus bas : on retire l'affirmation, jamais la mesure.

TOTAL=$((t_noms + t_juge + t_journal + t_texte + penalty))

# ========================================================================= la publication ====
pub sn_census_ran "$([ -n "$BN" ] && [ -n "$LV" ] && echo 1 || echo 0)"
pub single_namer_defects "$TOTAL"
pub single_namer_defects_terms \
  "noms$t_noms+juge$t_juge+journal$t_journal+texte$t_texte+penalite$penalty${why:+:$why}"
pub sn_noms "$t_noms"
pub sn_juge "$t_juge"
pub sn_journal "$t_journal"
pub sn_texte "$t_texte"
pub sn_witness_penalty "$penalty"

# 1. LE NOM ECRIT ET LE NOM LU, PAR BRAS. L'EGALITE EST LE VERDICT.
pub single_namer_state_written_livre "$(s nm_livre_ecrit)"
pub single_namer_state_read_livre "$(s nm_livre_lu)"
pub single_namer_state_equal_livre "$(n nm_livre_egal)"
pub single_namer_state_written_ablation "$(s nm_ablation_ecrit)"
pub single_namer_state_read_ablation "$(s nm_ablation_lu)"
pub single_namer_state_equal_ablation "$(n nm_ablation_egal)"
pub single_namer_state_keys_livre "$(n nm_livre_cles)"
pub single_namer_state_keys_ablation "$(n nm_ablation_cles)"
pub single_namer_writer_asks_authority "$(n nm_apres_demande_autorite)"
pub single_namer_writer_asked_before "$(n nm_avant_demande_autorite)"
pub single_namer_guard_refuses_rc "$(n nm_garde_apres_rc)"
pub single_namer_guard_refuses_files "$(n nm_garde_apres_fichiers)"
pub single_namer_guard_before_rc "$(n nm_garde_avant_rc)"
pub single_namer_guard_before_files "$(n nm_garde_avant_fichiers)"
pub single_namer_run_arm "$(l run_arm)"
pub single_namer_run_state_name "$(l run_state_name)"
# PUBLIE, JAMAIS COMPTE : les noms d'etat encore codes en dur ailleurs. Hors perimetre, et un
# temoin epingle d'un item deja valide les cite mot pour mot. Ils partent en signalement.
pub single_namer_other_literals "$(n nm_autres_litteraux)"
pub single_namer_other_literals_list "$(s nm_autres_litteraux_liste)"

# 2. LA PREMIERE LIGNE DU JUGE, DES DEUX COTES, ET LE COMPTE DE SORTIES CONTREDITES.
pub single_namer_validator_first_after "$(s vl_apres_l1)"
pub single_namer_validator_first_before "$(s vl_avant_l1)"
pub single_namer_validator_contradicted_after "$(n vl_apres_contredit)"
pub single_namer_validator_contradicted_before "$(n vl_avant_contredit)"
pub single_namer_validator_findings_after "$(n vl_apres_constats)"
pub single_namer_validator_findings_before "$(n vl_avant_constats)"
pub single_namer_validator_rc_after "$(n vl_apres_rc)"
pub single_namer_validator_body_intact "$(n vl_apres_corps_intact)"
pub single_namer_validator_ordinary_first "$(s vl_ordinaire_l1)"
pub single_namer_validator_ordinary_impossible "$(n vl_ordinaire_l1_dit_impossible)"

# 3. LE JOURNAL : SA TAILLE, SA BORNE, SES ECRIVAINS.
pub single_namer_journal_write_sites "$(n jn_sites)"
pub single_namer_journal_write_sites_list "$(s jn_sites_liste)"
pub single_namer_journal_write_sites_control "$(n jn_sites_controle_negatif)"
pub single_namer_journal_writers "$(n jn_appelants_ecrivains)"
pub single_namer_journal_writers_list "$(s jn_appelants_ecrivains_liste)"
pub single_namer_journal_callers "$(n jn_appelants)"
pub single_namer_journal_callers_list "$(s jn_appelants_liste)"
pub single_namer_journal_bytes_after "$(n jn_borne_apres_octets)"
pub single_namer_journal_bytes_before "$(n jn_borne_avant_octets)"
pub single_namer_journal_max_bytes "$(n jn_borne_apres_borne_declaree)"
pub single_namer_journal_rotated_after "$(n jn_borne_apres_rotation)"
pub single_namer_journal_rotated_before "$(n jn_borne_avant_rotation)"
pub single_namer_journal_concurrent_lines "$(n jn_conc_lignes)"
pub single_namer_journal_concurrent_expected "$(n jn_conc_attendu)"
pub single_namer_journal_concurrent_malformed "$(n jn_conc_malformees)"
pub single_namer_journal_live_bytes "$(ln_ live_journal_bytes)"
pub single_namer_journal_live_lines "$(ln_ live_journal_lines)"
pub single_namer_journal_live_writers "$(ln_ live_journal_writers)"
pub single_namer_journal_live_writers_list "$(l live_journal_writers_list)"
pub single_namer_journal_live_callers_list "$(l live_journal_callers_list)"
pub single_namer_journal_live_over_bound "$(ln_ live_journal_over_bound)"
pub single_namer_journal_path "$(l live_journal_path)"

# 4. LE TEXTE RENDU, LES DEUX BRAS, RECOPIE TEL QUEL.
pub single_namer_text_after "$(s tx_apres_bloc)"
pub single_namer_text_before "$(s tx_avant_bloc)"
pub single_namer_text_len_after "$(n tx_apres_len)"
pub single_namer_text_len_before "$(n tx_avant_len)"
pub single_namer_text_names_validated_after "$(n tx_apres_nomme_valide)"
pub single_namer_text_names_validated_before "$(n tx_avant_nomme_valide)"
pub single_namer_text_names_ghost_after "$(n tx_apres_nomme_fantome)"
pub single_namer_text_names_ghost_before "$(n tx_avant_nomme_fantome)"
pub single_namer_text_names_current_after "$(n tx_apres_nomme_en_cours)"
pub single_namer_seeded_states "$(n tx_apres_semes)"

# 5. LES TEMOINS D'AVANT, PAR LEUR COMMIT, ET LE HORS-PERIMETRE.
pub single_namer_before_writer_commit "$(s before_writer_commit)"
pub single_namer_before_validator_commit "$(s before_validator_commit)"
pub single_namer_before_backlog_commit "$(s before_backlog_commit)"
pub single_namer_before_journal_commit "$(s before_journal_commit)"
pub single_namer_purge_reasons "$(s src_raisons_purge)"
pub single_namer_purge_reasons_before "$(s src_raisons_purge_avant)"
pub single_namer_die3_reasons_equal \
  "$([ "$(s src_die3_raisons)" = "$(s src_die3_raisons_avant)" ] && echo 1 || echo 0)"
pub single_namer_live_standing "$(ln_ live_standing)"
pub single_namer_live_scanned "$(ln_ live_scanned)"
pub single_namer_live_standing_list "$(l live_standing_list)"
pub engine_dirty_files "$(n src_engine_dirty)"
pub engine_dirty_list "$(s src_engine_dirty_list)"

# LES BRUTS, recopies tels quels : c'est ce qui rend la somme lisible et falsifiable. Sous un
# prefixe a eux — le moissonneur garde la DERNIERE valeur d'une cle, et un homonyme ecraserait
# un terme du verdict.
brut(){ awk -v p="$1" -F= '/^[a-z_][a-z0-9_]*=/ {k=$1; sub(/^[^=]*=/,"",$0);
          gsub(/[[:space:]]+/,"_",$0); if($0=="") $0="-"; printf "%s%s=%s\n", p, k, $0}'; }
printf '%s\n' "$BN" | brut sn_bn_
printf '%s\n' "$LV" | brut sn_live_

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in lib/impossible.py lib/proof_impossible.sh lib/proof_run.sh lib/backlog.py \
         validators/generic.sh orchestrator.py lib/single_namer_selftest.py \
         lib/census/harness-impossible-single-namer.sh; do
  k="sn_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
