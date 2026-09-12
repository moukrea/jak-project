#!/usr/bin/env bash
# census/harness-impossible-state-hygiene.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course,
# sa sortie `cle=valeur` rejoignant celle du moteur dans le meme journal. Il n'ecrit aucun champ
# de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, DANS L'ORDRE DES QUATRE POINTS DU LIVRABLE :
#   1. un etat d'impossibilite qui ne decrit plus le present est PURGE, pour une raison NOMMEE,
#      et les deux comptes — purges, encore debout — sont publies SEPAREMENT     -> ish_purge
#   2. le TEXTE RENDU a l'owner perd l'etat perime dans le bras d'APRES, le garde
#      dans celui d'AVANT                                                        -> ish_statut
#   3. le nom du fichier d'attente ECRIT et celui LU sont EGAUX, par bras,
#      l'ablation comprise — c'est elle qui etait aveugle                        -> ish_noms
#   4. le journal de validation ne commence plus par un diagnostic que la porte
#      va contredire                                                             -> ish_journal
#
# DEUX SOURCES, jamais une seule :
#   - LE BANC (`lib/impossible_hygiene_selftest.py`) : la VRAIE purge, le VRAI `status_report`,
#     la VRAIE garde de `proof_run.sh` et le VRAI ecrivain de journal, sur des etats SEMES par
#     le VRAI `lib/proof_impossible.sh` dans des dossiers jetables. Chaque mecanisme est joue
#     par DEUX codes : celui du disque et celui d'AVANT ce chantier, ancre par MARQUEUR et
#     jamais par `HEAD:`. Le commit retenu est publie.
#   - CE DEPOT, MAINTENANT : les etats encore debout, le journal des purges, et le fichier
#     d'attente que LA COURSE EN TRAIN DE SE FAIRE vient d'ecrire, relu sous le nom que
#     `lib/impossible.py` derive pour CE bras.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte.
#
# CE QUI EST PUBLIE SANS ETRE COMPTE, ET POURQUOI. Les etats DEBOUT de ce depot et le nombre de
# purges deja journalisees : exiger une impossibilite REELLE pour fermer serait exiger une
# panne. Un zero s'y lit « rien en cours », et le denominateur publie a cote dit que quelque
# chose a bien ete regarde. Les journaux CONTREDITS de l'historique non plus : un chantier ne
# reecrit pas les journaux d'hier. La non-vacuite vient du semis, ou tout est FABRIQUE a chaque
# course par les vrais producteurs.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ish_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

# LE MOISSONNEUR DE proof_run.sh NE GARDE QUE `^cle=valeur$` SANS ESPACE. Une valeur avec des
# espaces — « 6 h 38 », le texte rendu a l'owner — n'arriverait JAMAIS dans proof.txt : elle
# serait publiee pour personne. On colle donc les espaces ICI, au point de publication.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# ===================================================================== le banc, deux bras ===
BN=$(timeout 900 python3 "$AP/lib/impossible_hygiene_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$BN" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ================================================ ce depot, et la course en train de se faire =
LV=$(python3 - "$ROOT" "${AUTOPORT_CENSUS_DIR:-}" "${AUTOPORT_CENSUS_ARMED:-1}" <<'PY' 2>/dev/null
import os, subprocess, sys
from pathlib import Path
root, cdir, armed = sys.argv[1], sys.argv[2], sys.argv[3]
sys.path.insert(0, os.path.join(root, '.autoport', 'lib'))
import impossible as I                                             # noqa: E402

reports = os.path.join(root, '.autoport', 'reports')

# 1. LES DEUX COMPTES DU LIVRABLE, SEPAREMENT, sur CE depot. `scan` est le denominateur : sans
# lui, « 0 debout » et « rien regarde » se confondent.
deb = I.standing(reports)
print('live_standing=%d' % len(deb))
print('live_scanned=%d' % len(I.scan(reports)))
print('live_standing_list=%s' % (','.join('%s@%ss' % (d['item'], d['age_s'])
                                          for d in deb) or '-'))
tot, par = I.purge_counts(reports)
print('live_purged=%d' % tot)
print('live_purged_reasons=%s' % (','.join('%s:%d' % kv for kv in sorted(par.items())) or '-'))
print('live_purge_journal=%s' % os.path.relpath(I.purge_journal_path(reports), root))

# 2. LE FICHIER D'ATTENTE DE CETTE COURSE, relu sous le nom que l'AUTORITE derive pour CE bras.
# C'est l'egalite entre ce nom et le fichier REELLEMENT present qui est le verdict.
suf = I.arm_suffix(armed)
nom = I.arm_name('wait', suf)
print('run_arm=%s' % (suf or 'livre'))
print('run_wait_name_read=%s' % nom)
vus = sorted(p.name for p in Path(cdir).glob('proof*-wait.txt')) if cdir else []
print('run_wait_files=%s' % (','.join(vus) or '-'))
print('run_wait_name_observed=%s' % (nom if (cdir and (Path(cdir) / nom).exists()) else '-'))
print('run_wait_readable=%d' % int(bool(cdir and (Path(cdir) / nom).is_file()
                                        and (Path(cdir) / nom).stat().st_size > 0)))
w = {}
if cdir and (Path(cdir) / nom).exists():
    for line in (Path(cdir) / nom).read_text(errors='replace').splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            w[k] = v
for k in ('proof_wait_s', 'proof_wait_max_s', 'deploy_lock_pid', 'deploy_lock_alive'):
    print('run_%s=%s' % (k, w.get(k, '-') or '-'))

# 3. LE VRAI BINAIRE, LANCE ICI : `autoport status` ne doit pas mourir d'avoir appris a purger.
try:
    r = subprocess.run(['./.autoport/autoport', 'status'], cwd=root,
                       capture_output=True, text=True, timeout=300)
    out, rc = r.stdout, r.returncode
except Exception as exc:                                           # noqa: BLE001
    out, rc = '', 'exc:%s' % type(exc).__name__
print('status_rc=%s' % rc)
print('status_len=%d' % len(out))
print('status_has_section=%d' % int('## Preuve impossible' in out))

# 4. LES NOMS QUE L'AUTORITE DERIVE, les deux bras et les cinq genres : ce qui est publie est
# ce que le lecteur utilisera.
print('kinds=%d' % len(I.KINDS))
for suffixe, arm in (('', 'livre'), ('-off', 'ablation')):
    print('name_%s=%s' % (arm, ','.join(I.arm_name(k, suffixe) for k in sorted(I.KINDS))))
print('reasons=%s' % ','.join(I.PURGE_REASONS))
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

# Le banc doit AVOIR tourne, chaque bras doit avoir joue, et le temoin d'AVANT doit etre ancre
# par MARQUEUR — jamais par `HEAD:`, ou il s'accuserait lui-meme des le commit.
[ -n "$BN" ] || faute banc-muet
[ -n "$LV" ] || faute lecture-du-depot-muette
for bras in pg_apres pg_avant st_apres st_avant jl_apres jl_avant; do
  [ "$(n "${bras}_ran")" = 1 ] || faute "bras-$bras-muet"
done
[ "$(s before_impossible_commit)" = "-" ] && faute temoin-avant-purge-absent
[ "$(s before_orch_commit)" = "-" ] && faute temoin-avant-journal-absent
[ "$(n before_impossible_marker_absent)" = 1 ] || faute temoin-avant-purge-porte-le-marqueur
[ "$(n before_orch_marker_absent)" = 1 ] || faute temoin-avant-journal-porte-le-marqueur
[ "$(n marker_impossible_live)" = 1 ] || faute marqueur-purge-absent-du-disque
[ "$(n marker_orch_live)" = 1 ] || faute marqueur-journal-absent-du-disque

# --- 1. LA PURGE : CE QUI PART, CE QUI RESTE, ET POURQUOI. ----------------------------------
t_purge=0
t_purge=$((t_purge + $(eq pg_apres_purge_fn 1)))
t_purge=$((t_purge + $(eq pg_apres_seeded 4)))          # quatre etats SEMES par le vrai producteur
t_purge=$((t_purge + $(eq pg_apres_scan_avant 4)))      # ... et vus par le recensement AVANT
t_purge=$((t_purge + $(eq pg_apres_purged 3)))
t_purge=$((t_purge + $(eq pg_apres_standing 1)))
t_purge=$((t_purge + $(eqs pg_apres_reasons "changement-d-item,changement-de-bras,course-aboutie")))
t_purge=$((t_purge + $(eq pg_apres_parti_meme_bras 1)))
t_purge=$((t_purge + $(eq pg_apres_parti_item_abandonne 1)))
t_purge=$((t_purge + $(eq pg_apres_parti_course_aboutie 1)))
# LE CONTROLE A LAISSER : l'AUTRE bras de l'item en cours ne bouge pas. Sans lui, une purge
# qui viderait tout passerait cette porte.
t_purge=$((t_purge + $(eq pg_apres_reste_autre_bras 1)))
t_purge=$((t_purge + $(eq pg_apres_fichiers_restants 1)))
t_purge=$((t_purge + $(eq pg_apres_standing_apres 1)))
t_purge=$((t_purge + $(eq pg_apres_scan_apres 1)))
t_purge=$((t_purge + $(eq pg_apres_purge2 0)))              # idempotente
t_purge=$((t_purge + $(eq pg_apres_purge_sans_item 0)))     # sans item courant : rien de perime
t_purge=$((t_purge + $(eq pg_apres_reste_apres_purge_nue 1)))
# CE QU'ON EFFACE SE RACONTE : une ligne de journal par etat retire, sa raison avec.
t_purge=$((t_purge + $(eq pg_apres_journal_lines 3)))
t_purge=$((t_purge + $(eqs pg_apres_journal_reasons "changement-d-item:1,changement-de-bras:1,course-aboutie:1")))
# LE BRAS D'AVANT : MEMES quatre etats semes, il n'en purge AUCUN et les quatre restent.
t_purge=$((t_purge + $(eq pg_avant_purge_fn 0)))
t_purge=$((t_purge + $(eq pg_avant_seeded 4)))
t_purge=$((t_purge + $(eq pg_avant_purged 0)))
t_purge=$((t_purge + $(eq pg_avant_fichiers_restants 4)))
t_purge=$((t_purge + $(eq pg_avant_journal_lines 0)))

# --- 2. LE TEXTE RENDU A L'OWNER, JUGE COMME TEXTE. -----------------------------------------
t_statut=0
t_statut=$((t_statut + $(eq st_apres_avant_has_section 1)))       # avant purge : la section est la
t_statut=$((t_statut + $(eq st_apres_avant_names_abandonne 1)))   # ... et nomme l'item abandonne
t_statut=$((t_statut + $(eq st_apres_purges 1)))                  # UNE purge : celle de l'abandonne
t_statut=$((t_statut + $(eq st_apres_apres_names_abandonne 0)))   # APRES : il a disparu du TEXTE
t_statut=$((t_statut + $(eq st_apres_fichier_abandonne_reste 0))) # ... et du disque
# LE CONTROLE A LAISSER : l'item EN COURS reste dans le texte. Une section videe ne prouverait
# qu'une chose : qu'on sait effacer.
t_statut=$((t_statut + $(eq st_apres_apres_names_en_cours 1)))
t_statut=$((t_statut + $(eq st_apres_apres_has_section 1)))
t_statut=$((t_statut + $(eq st_apres_fichier_en_cours_reste 1)))
[ "$(n st_apres_delta_len)" -lt -100 ] 2>/dev/null || faute texte-de-statut-inchange-apres-purge
[ "$(s st_apres_texte_apres)" = "-" ] && faute texte-rendu-apres-non-publie
# LE BRAS D'AVANT : MEME semis, son texte ne perd pas UN SEUL OCTET.
t_statut=$((t_statut + $(eq st_avant_purge_fn 0)))
t_statut=$((t_statut + $(eq st_avant_purges 0)))
t_statut=$((t_statut + $(eq st_avant_apres_names_abandonne 1)))
t_statut=$((t_statut + $(eq st_avant_delta_len 0)))
t_statut=$((t_statut + $(eq st_avant_fichier_abandonne_reste 1)))
# LE VRAI BINAIRE, LANCE ICI, ne doit pas mourir d'avoir appris a purger.
t_statut=$((t_statut + $(eql status_rc 0)))
[ "$(ln_ status_len)" -gt 100 ] 2>/dev/null || faute autoport-status-rendu-vide

# --- 3. LES NOMS, PAR BRAS, L'ABLATION COMPRISE. --------------------------------------------
t_noms=0
t_noms=$((t_noms + $(eqs nm_livre_ecrit proof-wait.txt)))  # NOM-LITTERAL-ATTENDU: valeur-attendue-d-une-egalite
t_noms=$((t_noms + $(eqs nm_livre_lu proof-wait.txt)))  # NOM-LITTERAL-ATTENDU: valeur-attendue-d-une-egalite
t_noms=$((t_noms + $(eq nm_livre_egal 1)))
t_noms=$((t_noms + $(eqs nm_ablation_ecrit proof-off-wait.txt)))  # NOM-LITTERAL-ATTENDU: valeur-attendue-d-une-egalite
t_noms=$((t_noms + $(eqs nm_ablation_lu proof-off-wait.txt)))  # NOM-LITTERAL-ATTENDU: valeur-attendue-d-une-egalite
t_noms=$((t_noms + $(eq nm_ablation_egal 1)))              # LE BRAS QUI ETAIT AVEUGLE
t_noms=$((t_noms + $(eq nm_lecteurs_en_dur 0)))            # plus un seul nom code en dur
# LA GARDE DE COURSE, EXERCEE DANS LES DEUX SENS : elle laisse passer le bon nom et TUE la
# course sur un nom divergent. Une garde qu'on ne voit jamais refuser ne garde rien.
t_noms=$((t_noms + $(eq nm_garde_trouvee 1)))
t_noms=$((t_noms + $(eq nm_garde_bon_rc 0)))
t_noms=$((t_noms + $(eq nm_garde_bon_die3 0)))
t_noms=$((t_noms + $(eq nm_garde_divergent_rc 9)))
t_noms=$((t_noms + $(eq nm_garde_divergent_die3 1)))
t_noms=$((t_noms + $(eq src_proof_run_derive_nom 1)))
# ET LA COURSE EN TRAIN DE SE FAIRE : le fichier d'attente de CE bras est la, sous ce nom.
t_noms=$((t_noms + $(eql run_wait_readable 1)))
[ "$(l run_wait_name_observed)" = "$(l run_wait_name_read)" ] || faute nom-ecrit-different-du-nom-lu
[ "$(ln_ run_proof_wait_s)" -ge 0 ] 2>/dev/null || faute attente-de-cette-course-non-publiee

# --- 4. LE JOURNAL NE COMMENCE PLUS PAR UN DIAGNOSTIC CONTREDIT. ----------------------------
t_journal=0
t_journal=$((t_journal + $(eq jl_apres_fn 1)))
t_journal=$((t_journal + $(eq jl_apres_detecteur 1)))
t_journal=$((t_journal + $(eq jl_apres_contredisait 1)))      # il a VU la contradiction
t_journal=$((t_journal + $(eq jl_apres_l1_dit_impossible 1)))
t_journal=$((t_journal + $(eq jl_apres_l1_dit_absent 0)))
t_journal=$((t_journal + $(eq jl_apres_l1_nomme_cause 1)))
t_journal=$((t_journal + $(eq jl_apres_l1_nomme_age 1)))
t_journal=$((t_journal + $(eq jl_apres_corps_intact 1)))      # le constat du validateur reste
t_journal=$((t_journal + $(eq jl_apres_porte_presente 1)))
t_journal=$((t_journal + $(eq jl_apres_dit_present 1)))
t_journal=$((t_journal + $(eq jl_apres_contredit_maintenant 0)))
# LE CONTROLE A LAISSER : un echec ORDINAIRE n'est ni accuse ni touche.
t_journal=$((t_journal + $(eq jl_apres_ordinaire_accuse 0)))
t_journal=$((t_journal + $(eq jl_apres_ordinaire_intact 1)))
# LE BRAS D'AVANT : son site d'ajout EXISTE dans le blob d'avant — le temoin n'est pas une
# invention — et le journal qu'il produit commence par le diagnostic que la porte contredit.
t_journal=$((t_journal + $(eq jl_avant_site_append 1)))
t_journal=$((t_journal + $(eq jl_avant_fn 0)))
t_journal=$((t_journal + $(eq jl_avant_l1_dit_absent 1)))
t_journal=$((t_journal + $(eq jl_avant_l1_dit_impossible 0)))
t_journal=$((t_journal + $(eq jl_avant_contredit 1)))
t_journal=$((t_journal + $(eq src_orch_ecrit_journal 2)))     # une definition, un appel

# --- HORS PERIMETRE : la DETECTION ne bouge pas, le jeu non plus. ---------------------------
# LA PROPRETE DE L'ARBRE N'EST PLUS AFFIRMEE ICI (signalement 5 du 12/09, chantier
# harness-naming-authority-completion). Un recensement qui assert `git diff --quiet` ou
# `git status --porcelain` rougit pour TOUT chantier qui touche le fichier surveille,
# pour une raison qui n'est pas la sienne. C'est le travail des PORTES — GATE 0 refuse un
# arbre herite sale, GATE 1 lit `code_scope` — pas d'un instrument. La grandeur reste
# PUBLIEE plus bas : on retire l'affirmation, jamais la mesure.
[ "$(n src_marker_purge)" = 1 ] || faute marqueur-purge-absent
[ "$(n src_marker_nom)" = 1 ] || faute marqueur-nommage-absent
[ "$(n src_orch_appelle_purge)" = 1 ] || faute orchestrateur-n-appelle-pas-la-purge
[ "$(n src_proof_run_appelle_purge)" = 1 ] || faute proof_run-n-appelle-pas-la-purge

TOTAL=$((t_purge + t_statut + t_noms + t_journal + penalty))

# ========================================================================= la publication ====
pub ish_census_ran "$([ -n "$BN" ] && [ -n "$LV" ] && echo 1 || echo 0)"
pub impossible_hygiene_defects "$TOTAL"
pub impossible_hygiene_defects_terms \
  "purge$t_purge+statut$t_statut+noms$t_noms+journal$t_journal+penalite$penalty${why:+:$why}"
pub ish_purge "$t_purge"
pub ish_statut "$t_statut"
pub ish_noms "$t_noms"
pub ish_journal "$t_journal"
pub ish_witness_penalty "$penalty"

# 1. LES DEUX COMPTES, SEPAREMENT — purges d'un cote, encore debout de l'autre, jamais leur
# difference. Sur le banc (fabriques, donc falsifiables) ET sur ce depot (l'etat du monde).
pub impossible_purged_states "$(n pg_apres_purged)"
pub impossible_standing_states "$(n pg_apres_standing)"
pub impossible_purged_reasons "$(s pg_apres_reasons)"
pub impossible_purge_journal_lines "$(n pg_apres_journal_lines)"
pub impossible_states_seeded "$(n pg_apres_seeded)"
pub impossible_states_scanned_before "$(n pg_apres_scan_avant)"
pub impossible_states_scanned_after "$(n pg_apres_scan_apres)"
pub impossible_purged_states_before_arm "$(n pg_avant_purged)"
pub impossible_standing_states_before_arm "$(n pg_avant_standing)"
pub impossible_live_standing "$(ln_ live_standing)"
pub impossible_live_scanned "$(ln_ live_scanned)"
pub impossible_live_standing_list "$(l live_standing_list)"
pub impossible_live_purged "$(ln_ live_purged)"
pub impossible_live_purged_reasons "$(l live_purged_reasons)"
pub impossible_purge_journal_path "$(l live_purge_journal)"
pub impossible_purge_reasons_known "$(l reasons)"
# 2. LE TEXTE RENDU, les deux bras, recopie tel quel.
pub impossible_status_text_after "$(s st_apres_texte_apres)"
pub impossible_status_text_before "$(s st_apres_texte_avant)"
pub impossible_status_delta_after "$(n st_apres_delta_len)"
pub impossible_status_delta_before_arm "$(n st_avant_delta_len)"
pub impossible_status_rc "$(l status_rc)"
pub impossible_status_len "$(ln_ status_len)"
# 3. LE NOM ECRIT ET LE NOM LU, PAR BRAS. L'EGALITE EST LE VERDICT.
pub impossible_wait_written_livre "$(s nm_livre_ecrit)"
pub impossible_wait_read_livre "$(s nm_livre_lu)"
pub impossible_wait_equal_livre "$(n nm_livre_egal)"
pub impossible_wait_written_ablation "$(s nm_ablation_ecrit)"
pub impossible_wait_read_ablation "$(s nm_ablation_lu)"
pub impossible_wait_equal_ablation "$(n nm_ablation_egal)"
pub impossible_wait_hardcoded_readers "$(n nm_lecteurs_en_dur)"
pub impossible_wait_hardcoded_list "$(s nm_lecteurs_en_dur_liste)"
pub impossible_guard_ok_rc "$(n nm_garde_bon_rc)"
pub impossible_guard_divergent_rc "$(n nm_garde_divergent_rc)"
pub impossible_run_arm "$(l run_arm)"
pub impossible_run_wait_read "$(l run_wait_name_read)"
pub impossible_run_wait_observed "$(l run_wait_name_observed)"
pub impossible_run_wait_files "$(l run_wait_files)"
pub impossible_run_wait_s "$(l run_proof_wait_s)"
pub impossible_run_lock_pid "$(l run_deploy_lock_pid)"
# 4. LE JOURNAL : sa premiere ligne, des deux cotes.
pub impossible_journal_first_after "$(s jl_apres_l1)"
pub impossible_journal_first_before "$(s jl_avant_l1)"
pub impossible_journal_contradicted_after "$(n jl_apres_contredit_maintenant)"
pub impossible_journal_contradicted_before "$(n jl_avant_contredit)"
pub impossible_journal_body_intact "$(n jl_apres_corps_intact)"
pub impossible_journal_ordinary_untouched "$(n jl_apres_ordinaire_intact)"
pub impossible_journal_repo_seen "$(n jl_depot_journaux)"
pub impossible_journal_repo_contradicted "$(n jl_depot_contredits)"
# 5. LES TEMOINS D'AVANT, par leur commit, et le hors-perimetre.
pub impossible_before_purge_commit "$(s before_impossible_commit)"
pub impossible_before_journal_commit "$(s before_orch_commit)"
pub impossible_purete_arbre_retiree "$(n src_purete_arbre_retiree)"
pub engine_dirty_files "$(n src_engine_dirty)"
pub engine_dirty_list "$(s src_engine_dirty_list)"

# LES BRUTS, recopies tels quels : c'est ce qui rend la somme lisible et falsifiable. Sous un
# prefixe a eux — le moissonneur garde la DERNIERE valeur d'une cle, et un homonyme ecraserait
# un terme du verdict. Espaces colles, valeur vide rendue `-` : un brut qui n'arrive pas dans
# proof.txt n'est pas un brut, c'est une ligne de journal.
brut(){ awk -v p="$1" -F= '/^[a-z_][a-z0-9_]*=/ {k=$1; sub(/^[^=]*=/,"",$0);
          gsub(/[[:space:]]+/,"_",$0); if($0=="") $0="-"; printf "%s%s=%s\n", p, k, $0}'; }
printf '%s\n' "$BN" | brut ish_bn_
printf '%s\n' "$LV" | brut ish_live_

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in orchestrator.py lib/impossible.py lib/proof_run.sh lib/proof_impossible.sh \
         lib/backlog.py lib/impossible_hygiene_selftest.py \
         lib/census/harness-impossible-state-hygiene.sh; do
  k="ish_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
