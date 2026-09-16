#!/usr/bin/env bash
# census/harness-judge-runs-the-proof-when-the-worker-left-none.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Sa sortie `cle=valeur` rejoint celle du moteur. Il n'ecrit aucun champ de `proof.txt` : ni
# `sha`, ni `frames`, ni `crash`, ni les `proof_census_*` qui disent qu'il a tourne — ils
# sortent de la machine.
#
# CE QU'IL MESURE, DANS L'ORDRE DES CINQ POINTS DU LIVRABLE :
#   1. LE COUT D'AVANT, CHIFFRE sur les verdicts archives : ceux dont le PREMIER constat est une
#      preuve absente, perimee, ou d'une autre identite                        -> t_cout
#   2. LE JUGE MESURE : les quatre declencheurs, ET la jambe de CONTROLE ou il ne
#      mesure pas                                                              -> t_declencheur
#   3. UNE SEULE COURSE, BORNEE, JAMAIS PAR-DESSUS UNE COURSE VIVANTE          -> t_course
#   4. L'ESSAI COMPTE SUR LA MESURE NEUVE, ET PAS DU TOUT QUAND ELLE EST IMPOSSIBLE -> t_compte
#   5. LES DEUX BRAS COTE A COTE, l'ablation etant l'ABSENCE de la couche      -> t_bras
#
# DEUX SOURCES, ET ELLES NE SE RECOUVRENT PAS. Le banc `lib/judge_measure_selftest.py` leve le
# bloc de decision de `orchestrator.py` entre ses marqueurs et le fait tourner sur de VRAIS
# depots et de VRAIS processus ; le recensement d'archive, lui, ne mesure que ce qui a DEJA eu
# lieu. L'un dit que le correctif marche, l'autre dit combien le defaut a coute.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte, et `-1` (cle
# absente) ne passe aucune porte `== 0`. Sans cette polarite, une porte `== 0` serait verte par
# INACTION : il suffirait que rien ne tourne.
#
# CE QUI EST PUBLIE SANS ETRE COMPTE, ET POURQUOI. La consigne annonce « 48 sur 4 jours au
# 16/09 ». Les journaux de cette machine n'en portent pas 48 : ils en portent 87 EN TOUT sur les
# 339 verdicts qu'a rendus `validators/generic.sh`, et la meilleure fenetre de quatre jours en
# vaut 54. Le chiffre du contrat n'est donc pas reproductible ici — on publie CE QU'ON MESURE, a
# cote du chiffre annonce, plutot que de fabriquer un 48.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "juge_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

# LE MOISSONNEUR DE proof_run.sh NE GARDE QUE `^cle=valeur$` SANS ESPACE, et jette une valeur
# VIDE. On colle les espaces ICI, au point de publication, et le vide devient `-`.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# ============================================================= LE BANC, ONZE JAMBES REELLES ==
BN=$(timeout -k 30 900 python3 "$AP/lib/judge_measure_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$BN" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9.-]*) echo -1 ;; *) echo "${v%%.*}" ;; esac; }

penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
eq(){ [ "$(n "$1")" = "$2" ] && echo 0 || echo 1; }
eqs(){ [ "$(s "$1")" = "$2" ] && echo 0 || echo 1; }
ge(){ local v; v=$(n "$1"); [ "$v" != -1 ] && [ "$v" -ge "$2" ] 2>/dev/null && echo 0 || echo 1; }
entre(){ local v; v=$(n "$1")
         [ "$v" != -1 ] && [ "$v" -ge "$2" ] && [ "$v" -le "$3" ] 2>/dev/null && echo 0 || echo 1; }

[ -n "$BN" ] || faute banc-muet
[ "$(n banc_ran)" = 1 ] || faute banc-n-a-pas-tourne
[ "$(s banc_panne)" = "-" ] || faute "banc-en-panne"
JAMBES="neuve absent identite vieille sources vivante uneseule impossible plafond avant panne"
for j in $JAMBES; do
  [ "$(s "${j}_panne")" = "" ] || faute "jambe-$j-en-panne"
  [ "$(n "${j}_retries")" != -1 ] || faute "jambe-$j-muette"
done

# ===================================== 1. LE COUT D'AVANT, LU SUR LES VERDICTS ARCHIVES ======
# La population n'est PAS versionnee (`.gitignore` exclut `.autoport/logs/`) : elle vit sur
# cette machine et nulle part ailleurs. Le denominateur — le nombre de verdicts LUS — est publie
# a cote du compte : un plancher calibre sur une population vide rendrait vert par cecite.
ARCH=$(python3 - <<'PY' 2>/dev/null
import glob, os, re, time
from collections import Counter

# LES PHRASES SONT CELLES DE `validators/generic.sh`, ET ON VERIFIE QU'ELLES Y SONT ENCORE.
# On ne peut pas les lui demander — DIRECTIVES 5 interdit de le modifier pour qu'il les
# expose — alors on les EPINGLE et on compte combien survivent dans son texte. Le jour ou il
# reformule, l'ecart se voit au lieu de rendre un zero silencieux.
ABSENTE = ("proof.txt absent ou vide",)
PERIMEE = ("source moteur editee APRES la preuve",
           "source du VERDICT editee APRES la preuve")
IDENTITE = ("dans la preuve, essai courant",
            "recopie dans la preuve",
            "n'est pas celui de",
            "une garde d'acquis VALIDE PAR L'OWNER a change")
TOUTES = ABSENTE + PERIMEE + IDENTITE
juge = open('.autoport/validators/generic.sh', encoding='utf-8', errors='replace').read()
print('cout_phrases_epinglees=%d' % len(TOUTES))
print('cout_phrases_dans_le_juge=%d' % sum(1 for m in TOUTES if m in juge))

fichiers = sorted(glob.glob('.autoport/logs/*/validator-*.txt'))
print('cout_journaux_lus=%d' % len(fichiers))

generic = echecs = 0
fam = Counter(); par_item = Counter(); par_jour = Counter()
for p in fichiers:
    txt = open(p, encoding='utf-8', errors='replace').read()
    # LA POPULATION EST CELLE DE CE JUGE-CI. 564 des 903 journaux viennent de validateurs
    # SUPPRIMES depuis (phases numerotees, format `RESULT: PASS`) : les melanger noierait le
    # taux dans une population que ce correctif ne touche pas.
    if not re.search(r'constat\(s\) ci-dessus', txt) and not re.search(r'\[\S+ ok\] source=', txt):
        continue
    generic += 1
    refus = [l for l in txt.splitlines() if re.search(r'\[\S+ FAIL\]', l)]
    if not refus:
        continue
    echecs += 1
    premier = refus[0]
    if any(m in premier for m in ABSENTE):
        quoi = 'absente'
    elif any(m in premier for m in PERIMEE):
        quoi = 'perimee'
    elif any(m in premier for m in IDENTITE):
        quoi = 'identite'
    else:
        quoi = 'autre'
    fam[quoi] += 1
    if quoi != 'autre':
        par_item[os.path.basename(os.path.dirname(p))] += 1
        try:
            par_jour[time.strftime('%Y-%m-%d', time.localtime(os.path.getmtime(p)))] += 1
        except OSError:
            pass

perdus = fam['absente'] + fam['perimee'] + fam['identite']
print('cout_generic=%d' % generic)
print('cout_echecs=%d' % echecs)
print('cout_succes=%d' % (generic - echecs))
print('cout_absente=%d' % fam['absente'])
print('cout_perimee=%d' % fam['perimee'])
print('cout_identite=%d' % fam['identite'])
print('cout_perdus=%d' % perdus)
print('cout_autres=%d' % fam['autre'])
print('cout_items_touches=%d' % len(par_item))
print('cout_part_des_echecs_pour_mille=%d' % (perdus * 1000 // echecs if echecs else -1))
print('cout_par_item=%s' % ('+'.join('%s:%d' % kv for kv in sorted(par_item.items())[:12]) or '-'))
# LA MEILLEURE FENETRE DE QUATRE JOURS, pour confronter au « 48 sur 4 jours » de la consigne.
jours = sorted(par_jour)
best = 0
for i, j0 in enumerate(jours):
    t0 = time.mktime(time.strptime(j0, '%Y-%m-%d'))
    best = max(best, sum(v for d, v in par_jour.items()
                         if 0 <= time.mktime(time.strptime(d, '%Y-%m-%d')) - t0 < 4 * 86400))
print('cout_meilleure_fenetre_4j=%d' % best)
print('cout_contrat_annonce=48')
print('cout_contrat_retrouve=%d' % int(best == 48))
print('cout_jours_couverts=%d' % len(jours))
PY
)
a(){ printf '%s\n' "$ARCH" | sed -n "s/^$1=//p" | tail -1; }
an(){ local v; v=$(a "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }
age(){ local v; v=$(an "$1"); [ "$v" != -1 ] && [ "$v" -ge "$2" ] 2>/dev/null && echo 0 || echo 1; }
[ -n "$ARCH" ] || faute recensement-d-archive-muet

t_cout=0
# LE DENOMINATEUR D'ABORD : un plancher calibre sur une population vide est un faux vert.
t_cout=$((t_cout + $(age cout_journaux_lus 100)))
t_cout=$((t_cout + $(age cout_generic 50)))
t_cout=$((t_cout + $(age cout_echecs 20)))
# LE COUT, NON NUL — 87 verdicts, 31 items, 46,8 % des refus de ce juge, au 16/09.
t_cout=$((t_cout + $(age cout_perdus 20)))
t_cout=$((t_cout + $(age cout_items_touches 5)))
t_cout=$((t_cout + $(age cout_part_des_echecs_pour_mille 200)))
# LES TROIS FAMILLES SONT TOUTES PEUPLEES : une seule qui porterait tout le compte voudrait dire
# que les deux autres declencheurs n'ont jamais servi a rien.
t_cout=$((t_cout + $(age cout_absente 5)))
t_cout=$((t_cout + $(age cout_perimee 5)))
t_cout=$((t_cout + $(age cout_identite 5)))
# LA PARTITION FERME : absente + perimee + identite = perdus, et perdus + autres = echecs.
SOMME=$(( $(an cout_absente) + $(an cout_perimee) + $(an cout_identite) ))
[ "$SOMME" = "$(an cout_perdus)" ] || t_cout=$((t_cout + 1))
[ $(( $(an cout_perdus) + $(an cout_autres) )) = "$(an cout_echecs)" ] || t_cout=$((t_cout + 1))
# ET LES PHRASES EPINGLEES SONT ENCORE CELLES DU JUGE. Garde d'EGALITE : s'il reformule, cette
# porte rougit au lieu de compter zero sur un vocabulaire mort.
[ "$(an cout_phrases_dans_le_juge)" = "$(an cout_phrases_epinglees)" ] || t_cout=$((t_cout + 1))

# ================== 2. LE JUGE MESURE — LES QUATRE DECLENCHEURS, ET LE CONTROLE ==============
t_declencheur=0
# LA JAMBE DE CONTROLE D'ABORD. Une couche qui mesurerait a CHAQUE essai serait verte partout
# ailleurs et couterait une course par essai : ici la preuve EST celle de l'essai, et le juge
# ne doit RIEN lancer.
t_declencheur=$((t_declencheur + $(eqs neuve_trigger -)))
t_declencheur=$((t_declencheur + $(eq neuve_launched 0)))
t_declencheur=$((t_declencheur + $(eq neuve_courses_lancees 0)))
t_declencheur=$((t_declencheur + $(eqs neuve_measured_by worker)))
t_declencheur=$((t_declencheur + $(eq neuve_verdict_rc 0)))
t_declencheur=$((t_declencheur + $(eq neuve_precheck_rc 0)))
# PREUVE ABSENTE.
t_declencheur=$((t_declencheur + $(eqs absent_trigger absent)))
t_declencheur=$((t_declencheur + $(eq absent_launched 1)))
t_declencheur=$((t_declencheur + $(eq absent_rc 0)))
t_declencheur=$((t_declencheur + $(eqs absent_measured_by juge)))
t_declencheur=$((t_declencheur + $(eq absent_preuve_est_de_cet_essai 1)))
t_declencheur=$((t_declencheur + $(eq absent_verdict_rc 0)))
# PREUVE D'UN AUTRE ESSAI.
t_declencheur=$((t_declencheur + $(eqs identite_trigger identite)))
t_declencheur=$((t_declencheur + $(eq identite_launched 1)))
t_declencheur=$((t_declencheur + $(eq identite_preuve_est_de_cet_essai 1)))
t_declencheur=$((t_declencheur + $(eq identite_verdict_rc 0)))
# PREUVE PLUS VIEILLE QUE L'ESSAI.
t_declencheur=$((t_declencheur + $(eqs vieille_trigger perime)))
t_declencheur=$((t_declencheur + $(eq vieille_launched 1)))
t_declencheur=$((t_declencheur + $(eq vieille_verdict_rc 0)))
# SOURCE EDITEE APRES LA PREUVE — et c'est `lib/stale_precheck.sh` qui le dit, par son code 5.
t_declencheur=$((t_declencheur + $(eqs sources_trigger perime)))
t_declencheur=$((t_declencheur + $(eq sources_precheck_rc 5)))
t_declencheur=$((t_declencheur + $(eq sources_launched 1)))
t_declencheur=$((t_declencheur + $(eq sources_verdict_rc 0)))

# ===================== 3. UNE SEULE COURSE, BORNEE, JAMAIS SUR UNE COURSE VIVANTE ============
t_course=0
# HORS PERIMETRE, ET MESURE : on ne double JAMAIS une course vivante, et elle SURVIT.
t_course=$((t_course + $(eqs vivante_refused course-vivante)))
t_course=$((t_course + $(eq vivante_launched 0)))
t_course=$((t_course + $(eq vivante_courses_lancees 0)))
t_course=$((t_course + $(eq vivante_course_vivante_survit 1)))
# UNE SEULE COURSE PAR ESSAI, MEME APPELEE DEUX FOIS.
t_course=$((t_course + $(eq uneseule_courses_lancees 1)))
t_course=$((t_course + $(eqs uneseule_refused deja-mesure)))
t_course=$((t_course + $(eq uneseule_launched 1)))
# LA BORNE TRANCHE, ET LA COURSE EST VRAIMENT MORTE APRES.
t_course=$((t_course + $(eq plafond_expired 1)))
t_course=$((t_course + $(eq plafond_rc -15)))
t_course=$((t_course + $(eq plafond_course_bornee_morte 1)))
t_course=$((t_course + $(entre plafond_duration_s 3 9)))
t_course=$((t_course + $(eq plafond_courses_lancees 1)))
# LES BORNES REELLES, TERME PAR TERME — pas celles du bac a sable.
t_course=$((t_course + $(eq plafond_item_reel 1620)))
t_course=$((t_course + $(eq plafond_defaut_x86 1320)))
t_course=$((t_course + $(eq plafond_defaut_appareil 1380)))
t_course=$((t_course + $(eq plafond_recensement 900)))
t_course=$((t_course + $(eq plafond_amorcage 300)))
t_course=$((t_course + $(eq plafond_dur 3600)))
t_course=$((t_course + $(eq plafond_sur_valeur_illisible 1320)))
t_course=$((t_course + $(eq plafond_borne_par_le_dur 3600)))
# UNE BORNE POSEE AU `proof_timeout` SEUL TUERAIT UNE COURSE NORMALE : celle de l'item precedent
# a dure 502 s pour un `proof_timeout` de 420.
t_course=$((t_course + $(eq plafond_couvre_502s 1)))
t_course=$((t_course + $(eqs plafond_bras_x86 x86)))
t_course=$((t_course + $(eqs plafond_bras_appareil device)))
# ET LE BANC N'A JAMAIS LANCE LA VRAIE COURSE.
t_course=$((t_course + $(eq banc_vraie_course_lancee 0)))
# LA COUCHE QUI TOMBE NE PREND PAS L'ESSAI AVEC ELLE. `run_attempt` n'est protege que contre
# `StateConflict` : sans ce repli, une exception d'ici tuerait le pilote entier. La jambe
# `panne` fabrique l'exception et verifie qu'on retombe sur le comportement d'AVANT — essai
# JUGE (le validateur a rendu son verdict), rien de lance, et le compte avance comme avant.
t_course=$((t_course + $(eqs panne_refused couche-en-panne:RuntimeError)))
t_course=$((t_course + $(eq panne_launched 0)))
t_course=$((t_course + $(eq panne_courses_lancees 0)))
t_course=$((t_course + $(eq panne_verdict_rc 1)))
t_course=$((t_course + $(eq panne_retries 4)))

# =============== 4. L'ESSAI COMPTE SUR LA MESURE NEUVE, ET PAS DU TOUT SI ELLE EST IMPOSSIBLE =
t_compte=0
# LA COURSE QUI NE MESURE PAS (rc 6 : la garde binaire refuse, et `proof_run.sh` n'ecrit AUCUN
# etat dans ce cas-la). C'est le juge qui NOMME la cause, sinon l'essai serait debite.
t_compte=$((t_compte + $(eq impossible_rc 6)))
t_compte=$((t_compte + $(eq impossible_impossible_ecrit 1)))
t_compte=$((t_compte + $(eq impossible_impossible_vu_par_la_porte 1)))
t_compte=$((t_compte + $(eqs impossible_measured_by -)))
t_compte=$((t_compte + $(eq impossible_named 1)))
t_compte=$((t_compte + $(eq plafond_impossible_vu_par_la_porte 1)))
# ET RIEN N'EST NOMME QUAND LA COURSE A MESURE : un etat « impossible » pose a tort classerait
# a part des essais parfaitement jugeables.
t_compte=$((t_compte + $(eq absent_impossible_ecrit 0)))
t_compte=$((t_compte + $(eq neuve_impossible_ecrit 0)))
# LE COMPTE EST RENDU A L'IDENTIQUE — la fonction de production, sur un etat.
t_compte=$((t_compte + $(eqs compte_verdict requalifie)))
t_compte=$((t_compte + $(eq compte_rendu_a_l_identique 1)))
t_compte=$((t_compte + $(eq compte_retries_apres 4)))
t_compte=$((t_compte + $(eq compte_dit_non_compte 1)))
# LE HANDOFF DU WORKER N'EST PAS ECRASE, sur AUCUNE des onze jambes.
INTACTS=0
for j in $JAMBES; do [ "$(n "${j}_handoff_intact")" = 1 ] && INTACTS=$((INTACTS+1)); done
t_compte=$((t_compte + $([ "$INTACTS" = 11 ] && echo 0 || echo 1)))
# ET LE JOURNAL DIT QUI A MESURE.
t_compte=$((t_compte + $(eq absent_journal_dit_qui 1)))
t_compte=$((t_compte + $(eqs absent_journal_mesure_par juge)))
t_compte=$((t_compte + $(eqs neuve_journal_mesure_par worker)))
t_compte=$((t_compte + $(eqs absent_journal_declencheur absent)))
t_compte=$((t_compte + $(ge journal_dit_mesure 5)))
t_compte=$((t_compte + $(ge journal_dit_rien_a_mesurer 1)))
t_compte=$((t_compte + $(ge journal_dit_vivante 1)))
t_compte=$((t_compte + $(ge journal_dit_classe_a_part 2)))

# ========================= 5. LES DEUX BRAS, ET L'ABLATION EST L'ABSENCE =====================
t_bras=0
# LE BRAS D'AVANT NE CONTIENT PAS CE QU'IL ABLATE. Un drapeau a zero laisserait vivre les sites
# non gates ; ici la couche n'est pas desarmee, elle n'est pas la.
t_bras=$((t_bras + $(eq bloc_avant_nomme_la_couche 0)))
t_bras=$((t_bras + $(eq bloc_apres_nomme_la_couche 1)))
# ET CE BRAS JUGE ET COMPTE TOUJOURS : ce qui differe est la MESURE, pas le jugement.
t_bras=$((t_bras + $(eq bloc_avant_juge 1)))
t_bras=$((t_bras + $(eq bloc_avant_compte 1)))
t_bras=$((t_bras + $(ge bloc_apres_lignes 30)))
t_bras=$((t_bras + $(ge bloc_avant_lignes 10)))
# LES DEUX VERDICTS COTE A COTE, SUR LA MEME ABSENCE DE PREUVE :
#   arme   -> une course lancee, preuve de CET essai, juge a 0   (jambe `absent`)
#   absent -> aucune course, preuve absente,          juge a 1   (jambe `avant`)
t_bras=$((t_bras + $(eqs avant_launched -)))
t_bras=$((t_bras + $(eq avant_courses_lancees 0)))
t_bras=$((t_bras + $(eq avant_verdict_rc 1)))
t_bras=$((t_bras + $(eq avant_preuve_presente 0)))
t_bras=$((t_bras + $(eq avant_journal_dit_qui 0)))
t_bras=$((t_bras + $(eq absent_verdict_rc 0)))
t_bras=$((t_bras + $(eq absent_preuve_presente 1)))
# ET CE BRAS EST BIEN LE CODE QUI TOURNAIT LE 16/09 : confronte, ligne a ligne, au blob que
# `lib/ablation_anchor.sh` designe — le dernier commit sans le marqueur. Jamais `HEAD:`.
t_bras=$((t_bras + $(eq ancre_avant_egale_le_blob 1)))
t_bras=$((t_bras + $(eq ancre_blob_porte_le_marqueur 0)))
t_bras=$((t_bras + $(ge ancre_blob_octets 10000)))
# LE SITE D'APPEL EST DANS LA PRODUCTION, PAS DANS UNE REGION MORTE. Noeud d'AST, pas un grep :
# un grep compterait la docstring.
t_bras=$((t_bras + $(eq site_appels_proof_freshness 1)))
t_bras=$((t_bras + $(eq site_definitions_proof_freshness 1)))
t_bras=$((t_bras + $(eq site_appels_judge_measure 1)))
t_bras=$((t_bras + $(eq site_definitions_judge_measure 1)))
t_bras=$((t_bras + $(eq site_juge_dans_la_region 1)))
t_bras=$((t_bras + $(eq site_fraicheur_dans_la_region 1)))
t_bras=$((t_bras + $(eq site_mesure_dans_la_region 1)))
t_bras=$((t_bras + $(eq site_fraicheur_avant_mesure 1)))
t_bras=$((t_bras + $(eq site_mesure_avant_le_juge 1)))
t_bras=$((t_bras + $(eq site_mesure_sous_le_declencheur 1)))
# LES LITTERAUX EPINGLES SONT ENCORE CEUX DU JUGE (garde d'egalite, pas refactor).
t_bras=$((t_bras + $([ "$(n litteraux_dans_le_juge)" = "$(n litteraux_epingles)" ] \
                     && echo 0 || echo 1)))
t_bras=$((t_bras + $(eq litteraux_source_device 1)))
# LE FAUX JUGE DU BAC A SABLE EST LE BLOC DU VRAI, LEVE ENTRE SES MARQUEURS.
t_bras=$((t_bras + $(ge juge_bloc_identite_lignes 10)))
t_bras=$((t_bras + $(ge juge_bloc_identite_octets 500)))

# ======================================= COMBIEN DE TEMOINS ONT VRAIMENT ETE LUS ? ===========
# UNE SOMME A ZERO SUR DES TERMES AVEUGLES EST LE FAUX VERT LE PLUS CHER. La liste ci-dessous
# est le contrat de ce verdict : chaque cle qu'un terme interroge. Une cle absente compte deja
# pour un defaut (les comparateurs rendent 1 sur -1) ; ici on publie COMBIEN ont ete lues et on
# NOMME celles qui manquent — un total de 0 sur 0 temoin ne prouve rien.
# La recherche se fait par filtrage de motif, SANS TUBE : `grep -q` sous `pipefail` rend 141 sur
# un SIGPIPE et la condition devient fausse sur une population qui PORTE le motif.
TEMOINS="absent_courses_lancees absent_impossible_ecrit absent_journal_declencheur
absent_journal_dit_qui absent_journal_mesure_par absent_launched absent_measured_by
absent_preuve_est_de_cet_essai absent_preuve_presente absent_rc absent_trigger
absent_verdict_rc ancre_avant_egale_le_blob ancre_blob_octets ancre_blob_porte_le_marqueur
avant_courses_lancees avant_journal_dit_qui avant_launched avant_preuve_presente
avant_verdict_rc banc_ran banc_vraie_course_lancee bloc_apres_lignes
bloc_apres_nomme_la_couche bloc_avant_compte bloc_avant_juge bloc_avant_lignes
bloc_avant_nomme_la_couche compte_dit_non_compte compte_rendu_a_l_identique
compte_retries_apres compte_verdict identite_launched identite_preuve_est_de_cet_essai
identite_trigger identite_verdict_rc impossible_impossible_ecrit
impossible_impossible_vu_par_la_porte impossible_measured_by impossible_named impossible_rc
journal_dit_classe_a_part journal_dit_mesure journal_dit_rien_a_mesurer journal_dit_vivante
juge_bloc_identite_lignes juge_bloc_identite_octets litteraux_dans_le_juge
litteraux_epingles litteraux_source_device neuve_courses_lancees neuve_impossible_ecrit
neuve_journal_mesure_par neuve_launched neuve_measured_by neuve_precheck_rc neuve_trigger
neuve_verdict_rc plafond_amorcage plafond_borne_par_le_dur plafond_bras_appareil
plafond_bras_x86 plafond_course_bornee_morte plafond_courses_lancees plafond_couvre_502s
plafond_defaut_appareil plafond_defaut_x86 plafond_dur plafond_duration_s plafond_expired
plafond_impossible_vu_par_la_porte plafond_item_reel plafond_rc plafond_recensement
plafond_sur_valeur_illisible site_appels_judge_measure site_appels_proof_freshness
site_definitions_judge_measure site_definitions_proof_freshness site_fraicheur_avant_mesure
site_fraicheur_dans_la_region site_juge_dans_la_region site_mesure_avant_le_juge
site_mesure_dans_la_region site_mesure_sous_le_declencheur sources_launched
sources_precheck_rc sources_trigger sources_verdict_rc uneseule_courses_lancees
uneseule_launched uneseule_refused vieille_launched vieille_trigger vieille_verdict_rc
panne_courses_lancees panne_launched panne_refused panne_retries panne_verdict_rc
vivante_course_vivante_survit vivante_courses_lancees vivante_launched vivante_refused
cout_absente cout_echecs cout_generic cout_identite cout_items_touches cout_journaux_lus
cout_perdus cout_perimee cout_phrases_dans_le_juge cout_phrases_epinglees"
TOUT=$(printf '\n%s\n%s\n' "$BN" "$ARCH")
LUS=0; NTEMOINS=0; MANQUANTS=""
for k in $TEMOINS; do
  NTEMOINS=$((NTEMOINS+1))
  case "$TOUT" in
    *"
$k="*) LUS=$((LUS+1)) ;;
    *) MANQUANTS="${MANQUANTS:+$MANQUANTS+}$k" ;;
  esac
done

TOTAL=$((t_cout + t_declencheur + t_course + t_compte + t_bras + penalty))

# ======================================================================== CE QUI EST PUBLIE ==
# LE BANC A-T-IL MESURE ? Une sortie non vide ne suffit pas : il PUBLIE sa panne, et une panne
# publiee lue comme « il a tourne » serait le mensonge le plus facile de ce fichier.
pub juge_census_ran "$([ "$(n banc_ran)" = 1 ] && echo 1 || echo 0)"
pub juge_banc_panne "$(s banc_panne)"
pub stale_proof_verdicts "$TOTAL"
pub stale_defects_terms \
  "cout$t_cout+declencheur$t_declencheur+course$t_course+compte$t_compte+bras$t_bras+penalite$penalty${why:+:$why}"
pub juge_t_cout "$t_cout"
pub juge_t_declencheur "$t_declencheur"
pub juge_t_course "$t_course"
pub juge_t_compte "$t_compte"
pub juge_t_bras "$t_bras"
pub juge_witness_penalty "$penalty"
pub juge_terms_measured "$LUS"
pub juge_terms_total "$NTEMOINS"
pub juge_terms_missing "${MANQUANTS:--}"
pub juge_handoffs_intacts "$INTACTS"

# 1. LE COUT D'AVANT — la population, sa partition, et la fenetre que la consigne citait.
for k in cout_phrases_epinglees cout_phrases_dans_le_juge cout_journaux_lus cout_generic \
         cout_echecs cout_succes cout_absente cout_perimee cout_identite cout_perdus \
         cout_autres cout_items_touches cout_part_des_echecs_pour_mille cout_par_item \
         cout_meilleure_fenetre_4j cout_contrat_annonce cout_contrat_retrouve \
         cout_jours_couverts; do
  pub "juge_$k" "$(a "$k")"
done
# LA POPULATION N'EST PAS VERSIONNEE : un autre arbre ne rendrait pas le meme compte, et le
# dire fait partie du chiffre.
pub juge_cout_population_versionnee \
  "$(git -C "$ROOT" check-ignore -q .autoport/logs && echo 0 || echo 1)"

# 2/3/4/5. LES BRUTS DU BANC, sous un prefixe a eux : le moissonneur garde la DERNIERE valeur
# d'une cle, et un homonyme ecraserait un terme du verdict.
printf '%s\n' "$BN" | awk -F= '/^[a-z_][a-z0-9_]*=/ {k=$1; sub(/^[^=]*=/,"",$0);
   gsub(/[[:space:]]+/,"_",$0); if($0=="") $0="-"; printf "juge_bn_%s=%s\n", k, $0}'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in orchestrator.py lib/judge_measure_selftest.py lib/ablation_anchor.sh \
         lib/stale_precheck.sh lib/proof_impossible.sh validators/generic.sh \
         lib/census/harness-judge-runs-the-proof-when-the-worker-left-none.sh; do
  k="juge_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
