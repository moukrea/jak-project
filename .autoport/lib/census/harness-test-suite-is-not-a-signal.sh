#!/usr/bin/env bash
# census/harness-test-suite-is-not-a-signal.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course,
# sa sortie `cle=valeur` rejoignant celle du moteur dans le meme journal. Il n'ecrit aucun champ
# de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, DANS L'ORDRE DES QUATRE POINTS DU LIVRABLE :
#   1. les echecs sont TRIES, un par un, et chaque classe est comptee     -> ts_triage
#   2. aucun test ne depend de ce que la machine fait au meme moment      -> ts_machine
#      DEUX COURSES DE LA SUITE ENTIERE : l'une avec un `ninja` factice vivant, l'autre sans.
#   3. la suite passe, ou l'echec restant a une raison ECRITE et un NOM   -> ts_rouge
#   4. depuis quand la suite n'est plus verte                             -> publie, ancre sur git
#
# TROIS SOURCES, jamais une seule :
#   - LA SUITE ELLE-MEME, deux fois, en junit-xml : le verdict par test, pas un compte.
#   - LE REGISTRE `tests/harness/ECHECS-ATTENDUS.yaml` : la seule dispense possible, versionnee,
#     dont l'empreinte est publiee. Un echec absent du registre est un DEFAUT ; une entree du
#     registre qui ne rougit plus est un DEFAUT (une dispense perimee n'est pas un acquis) ;
#     une entree qui rougit pour une AUTRE raison que sa signature est un DEFAUT.
#   - LE BRAS D'AVANT, ancre par MARQUEUR : le test de `busy_reason` TEL QU'IL ETAIT, avec le
#     `proof_run.sh` DE LA MEME EPOQUE, joue avec puis sans le `ninja` factice. Il doit rougir
#     dans le premier cas et passer dans le second — sinon le correctif ne corrige rien de
#     mesurable et la deuxieme course de la suite ne prouverait qu'un decor.
#
# POURQUOI LE BRAS D'AVANT PREND AUSSI L'ANCIEN proof_run.sh. Le neuf a factorise la lecture des
# processus dans `busy_procs`. L'ancien test DECOUPE `busy_reason` dans le fichier : rejoue
# contre le proof_run.sh d'aujourd'hui, il appellerait une fonction absente, bash rendrait 127,
# la garde serait MUETTE et l'ancien test passerait — un faux vert qui detruirait le temoin.
# Les deux fichiers viennent donc du MEME commit d'avant.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte. Sans cette
# polarite une porte `== 0` sur « la suite passe » serait verte par INACTION : une suite qui ne
# COLLECTE rien ne rate rien.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ts_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

SUITE=".autoport/tests/harness"
REGISTRE="$SUITE/ECHECS-ATTENDUS.yaml"
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/ts-census.XXXXXX") || { echo "ts_census_ran=0"; exit 1; }
FAUX_PID=""
# PID EXACT, jamais un motif : `pkill -f` se matche lui-meme. Le nettoyage est pose ici, avant
# le premier lancement, pour qu'aucune sortie ne laisse un faux `ninja` derriere elle.
nettoie(){ [ -n "$FAUX_PID" ] && kill "$FAUX_PID" 2>/dev/null; rm -rf "$TMPD"; }
trap nettoie EXIT

pytest_run(){   # $1 = dossier de travail, $2 = cible, $3 = xml de sortie ; rend le code pytest
  ( cd "$1" && timeout -k 15 600 python3 -m pytest "$2" -q -p no:cacheprovider \
      --junitxml="$3" >"$3.log" 2>&1 )
}

# Le code de retour de pytest ne suffit pas a juger le bras d'avant : 2, 3 ou 4 signifient
# « erreur d'usage / collecte impossible », et se liraient comme « le test a rougi » alors
# qu'il n'a rien mesure. On lit donc le junit : combien de cas, combien de rouges, et le
# rouge porte-t-il le NOM attendu.
avant_juge(){   # $1 = xml ; ecrit "<collectes> <rouges> <le-rouge-attendu-est-la>"
  python3 - "$1" <<'PY' 2>/dev/null || echo "-1 -1 -1"
import sys, xml.etree.ElementTree as ET
try:
    r = ET.parse(sys.argv[1]).getroot()
except Exception:
    print('-1 -1 -1'); raise SystemExit(0)
s = r if r.tag == 'testsuite' else r.find('testsuite')
if s is None:
    print('-1 -1 -1'); raise SystemExit(0)
n = rouges = nomme = 0
for tc in s.iter('testcase'):
    n += 1
    if any(e.tag in ('failure', 'error') for e in tc):
        rouges += 1
        if tc.get('name') == 'test_prompt_mentionnant_compilateur_ne_bloque_pas':
            nomme = 1
print('%d %d %d' % (n, rouges, nomme))
PY
}

# ====================================== 0. LE BRAS D'AVANT, ANCRE PAR MARQUEUR ===============
# Le temoin « avant » ne se lit JAMAIS a `HEAD:` : des le commit de ce chantier, `HEAD` porte le
# correctif et le temoin s'accuse lui-meme. On remonte jusqu'au dernier commit ou le marqueur
# est ABSENT du fichier de test, et on publie le commit retenu.
# LA FENETRE N'EST PLUS UN NOMBRE DE COMMITS (harness-verdict-integrity, 2026-09-12). Elle
# balayait les 60 derniers commits du chemin : une meche lente, qui aurait rendu le temoin
# d'avant introuvable et cette porte ROUGE sans qu'aucun defaut existe. L'ancre vient de
# `lib/ablation_anchor.sh` — la revision qui a INTRODUIT le marqueur, historique complet.
MARQUEUR='liste-injectee-2026-09-12'
AVANT=$(bash "$(git rev-parse --show-toplevel)/.autoport/lib/ablation_anchor.sh" \
        "$(git rev-parse --show-toplevel)" "$SUITE/test_proof_busy.py" "$MARQUEUR" commit 2>/dev/null) || AVANT=""
AVANT_OK=0
if [ -n "$AVANT" ]; then
  mkdir -p "$TMPD/avant/.autoport/tests/harness" "$TMPD/avant/.autoport/lib"
  git show "$AVANT:$SUITE/test_proof_busy.py" > "$TMPD/avant/.autoport/tests/harness/test_proof_busy.py" 2>/dev/null &&
  git show "$AVANT:$SUITE/conftest.py"        > "$TMPD/avant/.autoport/tests/harness/conftest.py" 2>/dev/null &&
  git show "$AVANT:.autoport/lib/proof_run.sh" > "$TMPD/avant/.autoport/lib/proof_run.sh" 2>/dev/null &&
  git show "$AVANT:.autoport/orchestrator.py"  > "$TMPD/avant/.autoport/orchestrator.py" 2>/dev/null &&
  AVANT_OK=1
fi
# Le temoin d'avant doit vraiment etre d'avant : ni le marqueur, ni l'indirection.
AVANT_SANS_MARQUEUR=0
if [ "$AVANT_OK" = 1 ]; then
  if ! grep -q "$MARQUEUR" "$TMPD/avant/.autoport/tests/harness/test_proof_busy.py" &&
     ! grep -q 'busy_procs' "$TMPD/avant/.autoport/lib/proof_run.sh"; then AVANT_SANS_MARQUEUR=1; fi
fi

# =============================== 1. LE `ninja` FACTICE, ET LA PREUVE QU'IL VIT ================
# Un processus dont le NOM est `ninja` (prctl), rien d'autre : il ne compile pas, il occupe le
# nom. C'est exactement ce que la garde de proof_run.sh regarde.
python3 -c 'import ctypes,sys,time; ctypes.CDLL(None).prctl(15,b"ninja",0,0,0); print("pret",flush=True); time.sleep(900)' \
  > "$TMPD/ninja.out" 2>/dev/null &
FAUX_PID=$!
FAUX_PRET=0
for _ in $(seq 1 100); do
  if grep -q pret "$TMPD/ninja.out" 2>/dev/null; then FAUX_PRET=1; break; fi
  sleep 0.1
done

# La garde LIVREE voit-elle ce ninja ? Si le correctif l'avait aveuglee, la preuve le dirait ici
# et non six semaines plus tard sur un KERNEL.CGO a moitie ecrit.
garde(){   # $1 = genre, $2 = motif ; ecrit 1 ou 0
  local corps
  corps=$(sed -n '/^busy_procs(){/,/^}/p' "$AP/lib/proof_run.sh")
  [ -n "$corps" ] || { echo -1; return; }
  printf '%s\nif busy_procs %s %s; then echo 1; else echo 0; fi\n' "$corps" "$1" "$2" > "$TMPD/garde.sh"
  bash "$TMPD/garde.sh" 2>/dev/null || echo -1
}
GARDE_VOIT=$(garde comm '"[n]inja(-build)?"')
GARDE_SENTINELLE=$(garde comm '"[z]zautoportqq"')   # n'existe sur aucune machine : doit rendre 0

# Le bras d'avant, AVEC le ninja factice : il doit ROUGIR. C'est la non-vacuite de tout le reste.
AVANT_AVEC=-1
if [ "$AVANT_OK" = 1 ]; then
  pytest_run "$TMPD/avant" ".autoport/tests/harness/test_proof_busy.py" "$TMPD/avant-avec.xml"
  AVANT_AVEC=$?
fi

# =========================== 2. LA SUITE ENTIERE, COURSE A : AVEC LE ninja ====================
pytest_run "$ROOT" "$SUITE" "$TMPD/a.xml"; RC_A=$?
FAUX_VIVANT_APRES=0; kill -0 "$FAUX_PID" 2>/dev/null && FAUX_VIVANT_APRES=1

# =========================== 3. ON ETEINT LE FACTICE, PAR SON PID EXACT =======================
kill "$FAUX_PID" 2>/dev/null; wait "$FAUX_PID" 2>/dev/null; FAUX_PID=""
FAUX_ETEINT=0
for _ in $(seq 1 50); do
  if [ "$(garde comm '"[n]inja(-build)?"')" = 0 ]; then FAUX_ETEINT=1; break; fi
  sleep 0.1
done

# Le bras d'avant, SANS le ninja : le MEME test, le MEME fichier, il doit passer.
AVANT_SANS=-1
if [ "$AVANT_OK" = 1 ]; then
  pytest_run "$TMPD/avant" ".autoport/tests/harness/test_proof_busy.py" "$TMPD/avant-sans.xml"
  AVANT_SANS=$?
fi

# =========================== 4. LA SUITE ENTIERE, COURSE B : SANS LE ninja ====================
pytest_run "$ROOT" "$SUITE" "$TMPD/b.xml"; RC_B=$?

# ================================================================== LE JUGEMENT ==============
JG=$(python3 - "$TMPD/a.xml" "$TMPD/b.xml" "$ROOT/$REGISTRE" <<'PY' 2>/dev/null
import re, sys, xml.etree.ElementTree as ET
import yaml

def lire(chemin):
    """nodeid -> (verdict, message). Un fichier absent ou tronque rend None : INCONNU."""
    try:
        racine = ET.parse(chemin).getroot()
    except Exception:
        return None
    suite = racine if racine.tag == 'testsuite' else racine.find('testsuite')
    if suite is None:
        return None
    res = {}
    for tc in suite.iter('testcase'):
        parts = (tc.get('classname') or '').split('.')
        fichier = '.' + '/'.join(parts[1:]) + '.py' if parts and parts[0] == '' else \
                  '/'.join(parts) + '.py'
        nodeid = '%s::%s' % (fichier, tc.get('name'))
        verdict, message = 'passed', ''
        for enfant in tc:
            if enfant.tag in ('failure', 'error'):
                verdict = enfant.tag
                message = (enfant.get('message') or '') + '\n' + (enfant.text or '')
            elif enfant.tag == 'skipped':
                verdict = 'skipped'
        res[nodeid] = (verdict, message)
    return res

a, b = lire(sys.argv[1]), lire(sys.argv[2])
try:
    reg = yaml.safe_load(open(sys.argv[3], encoding='utf-8')) or {}
except Exception:
    reg = None

print('a_lu=%d' % int(a is not None))
print('b_lu=%d' % int(b is not None))
print('registre_lu=%d' % int(reg is not None))
if a is None or b is None or reg is None:
    raise SystemExit(0)

rouges = lambda d: {k for k, (v, _) in d.items() if v in ('failure', 'error')}
ra, rb = rouges(a), rouges(b)
print('collectes_a=%d' % len(a))
print('collectes_b=%d' % len(b))
print('rouges_a=%d' % len(ra))
print('rouges_b=%d' % len(rb))
print('rouges_a_liste=%s' % (','.join(sorted(ra)) or '-'))
print('rouges_b_liste=%s' % (','.join(sorted(rb)) or '-'))
# LE POINT 2 DU LIVRABLE : le MEME verdict, que la machine compile ou non.
ecart = (ra ^ rb) | {k for k in set(a) ^ set(b)}
print('ecart_entre_courses=%d' % len(ecart))
print('ecart_liste=%s' % (','.join(sorted(ecart)) or '-'))

attendus = {e['nodeid']: e for e in (reg.get('attendus') or [])}
union = ra | rb
# a) un echec qu'AUCUNE dispense ne couvre : un vrai regressif.
non_couverts = sorted(union - set(attendus))
# b) une dispense qui ne rougit plus, ou dont le test a disparu : dispense PERIMEE.
perimees = sorted(n for n in attendus if n not in union)
# c) une dispense qui rougit pour une AUTRE raison que la sienne : un defaut cache dessous.
hors_signature = []
for n, e in attendus.items():
    if n not in union:
        continue
    msg = (a.get(n) or b.get(n) or ('', ''))[1]
    if not re.search(e.get('signature') or '(?!)', msg or ''):
        hors_signature.append(n)
print('non_couverts=%d' % len(non_couverts))
print('non_couverts_liste=%s' % (','.join(non_couverts) or '-'))
print('dispenses_perimees=%d' % len(perimees))
print('dispenses_perimees_liste=%s' % (','.join(perimees) or '-'))
print('hors_signature=%d' % len(hors_signature))
print('hors_signature_liste=%s' % (','.join(sorted(hors_signature)) or '-'))
print('dispenses=%d' % len(attendus))
print('dispenses_liste=%s' % (','.join(
    '%s:%s' % (e.get('slug', '?'), e.get('tranche', '?')) for e in attendus.values()) or '-'))
print('dispenses_owner=%d' % sum(
    1 for e in attendus.values() if e.get('categorie') == 'decision-owner'))

# LE TRI DEMANDE PAR LE LIVRABLE, une ligne par echec signale, et le compte de CHAQUE classe.
tri = reg.get('triage') or []
classes = ('defaut-de-code', 'decision-owner', 'test-devenu-faux')
for c in classes:
    print('triage_%s=%d' % (c.replace('-', '_'), sum(1 for t in tri if t.get('classe') == c)))
print('triage_total=%d' % len(tri))
print('triage_classes_inconnues=%d' % sum(1 for t in tri if t.get('classe') not in classes))
for i, t in enumerate(tri, 1):
    n = t['nodeid']
    etat = 'rouge' if n in union else ('vert' if n in a else 'absent')
    print('triage_%d=%s|%s|%s|%s' % (i, t.get('classe', '?'), t.get('slug', '?'), etat,
                                     t.get('cause_commit') or '-'))
# Un tri qui nomme un test INEXISTANT ne trie rien.
print('triage_inconnus=%d' % sum(1 for t in tri if t['nodeid'] not in a))
# Toute entree de `attendus` doit etre AUSSI dans le tri : pas de dispense hors classement.
print('dispenses_non_triees=%d' % sum(
    1 for n in attendus if n not in {t['nodeid'] for t in tri}))

v = reg.get('derniere_suite_verte') or {}
print('verte_commit=%s' % (v.get('commit') or '-'))
print('verte_date=%s' % (v.get('date') or '-'))
print('verte_premier_rouge=%s' % (v.get('premier_rouge') or '-'))
PY
) || JG=""
j(){ printf '%s\n' "$JG" | sed -n "s/^$1=//p" | tail -1; }
jn(){ local v; v=$(j "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ======================================================== les termes du verdict ==============
penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
add(){ local v=$1; [ "$v" -ge 0 ] 2>/dev/null || v=1; echo "$v"; }

[ -n "$JG" ] || faute jugement-muet
[ "$(jn a_lu)" = 1 ] || faute course-avec-ninja-illisible
[ "$(jn b_lu)" = 1 ] || faute course-sans-ninja-illisible
[ "$(jn registre_lu)" = 1 ] || faute registre-illisible
# NON-VACUITE : une suite qui ne collecte rien ne rate rien. Le plancher est dimensionne sur la
# population REELLEMENT lue (556 tests le 12/09), pas sur un chiffre rond choisi d'avance.
[ "$(jn collectes_a)" -ge 540 ] 2>/dev/null || faute course-a-trop-maigre
[ "$(jn collectes_b)" -ge 540 ] 2>/dev/null || faute course-b-trop-maigre

# --- 1. LE TRI. Les echecs signales sont classes un par un, et la classe existe.
t_triage=0
t_triage=$((t_triage + $(add "$(jn triage_classes_inconnues)")))
t_triage=$((t_triage + $(add "$(jn triage_inconnus)")))
t_triage=$((t_triage + $(add "$(jn dispenses_non_triees)")))
[ "$(jn triage_total)" -ge 6 ] 2>/dev/null || faute tri-incomplet

# --- 2. AUCUN TEST NE DEPEND DE CE QUE LA MACHINE FAIT AU MEME MOMENT.
t_machine=0
t_machine=$((t_machine + $(add "$(jn ecart_entre_courses)")))
# Le ninja factice a VRAIMENT vecu pendant la course A, et la garde livree l'a VRAIMENT vu.
[ "$FAUX_PRET" = 1 ] || faute ninja-factice-jamais-pret
[ "$FAUX_VIVANT_APRES" = 1 ] || faute ninja-factice-mort-avant-la-fin-de-la-course
[ "$GARDE_VOIT" = 1 ] || faute garde-livree-aveugle-au-ninja
[ "$GARDE_SENTINELLE" = 0 ] || faute garde-livree-repond-oui-a-tout
[ "$FAUX_ETEINT" = 1 ] || faute ninja-factice-encore-la-pour-la-course-b
# LE BRAS D'AVANT : le MEME test, la MEME machine, il rougit avec le ninja et passe sans.
[ "$AVANT_OK" = 1 ] || faute temoin-avant-absent
[ "$AVANT_SANS_MARQUEUR" = 1 ] || faute temoin-avant-porte-le-marqueur
read -r AV_N AV_R AV_NOM <<< "$(avant_juge "$TMPD/avant-avec.xml")"
read -r AS_N AS_R AS_NOM <<< "$(avant_juge "$TMPD/avant-sans.xml")"
[ "$AVANT_AVEC" = 1 ] || faute temoin-avant-ne-rougit-pas-sous-le-ninja
[ "$AV_NOM" = 1 ] || faute temoin-avant-rouge-pour-une-autre-raison
[ "$AV_N" -ge 5 ] 2>/dev/null || faute temoin-avant-ne-collecte-rien-sous-le-ninja
[ "$AVANT_SANS" = 0 ] || faute temoin-avant-rouge-meme-sans-ninja
[ "$AS_R" = 0 ] 2>/dev/null || faute temoin-avant-encore-rouge-sans-ninja
[ "$AS_N" -ge 5 ] 2>/dev/null || faute temoin-avant-ne-collecte-rien-sans-ninja

# --- 3. LA SUITE PASSE, OU L'ECHEC RESTANT A UNE RAISON ECRITE ET UN NOM.
t_rouge=0
t_rouge=$((t_rouge + $(add "$(jn non_couverts)")))
t_rouge=$((t_rouge + $(add "$(jn dispenses_perimees)")))
t_rouge=$((t_rouge + $(add "$(jn hors_signature)")))

# ------------------------------------------------- 4. DEPUIS QUAND, ANCRE DANS GIT ----------
# La date ne se RECOPIE pas du registre : elle est relue dans git. Un chemin n'est pas une
# provenance, et une date tapee a la main n'est pas une mesure. Le commit doit exister ET etre
# un ancetre de HEAD, sinon « depuis quand » reste inconnu — et l'inconnu est un defaut.
ancre(){   # $1 = sha du registre ; ecrit "<date> <existe> <ancetre>"
  local sha="$1" d="-" e=0 anc=0
  if [ -n "$sha" ] && [ "$sha" != "-" ] && git cat-file -e "$sha^{commit}" 2>/dev/null; then
    e=1; d=$(git log -1 --format=%cI "$sha" 2>/dev/null)
    git merge-base --is-ancestor "$sha" HEAD 2>/dev/null && anc=1
  fi
  printf '%s %s %s\n' "${d:--}" "$e" "$anc"
}
VC=$(j verte_commit);        read -r VC_DATE VC_EXISTE VC_ANCETRE <<< "$(ancre "$VC")"
PR=$(j verte_premier_rouge); read -r PR_DATE PR_EXISTE PR_ANCETRE <<< "$(ancre "$PR")"
# Il suffit que L'UNE des deux bornes soit mesuree : si aucun commit vert n'existe dans la
# fenetre fouillee, c'est le PREMIER ROUGE connu qui repond a « depuis quand ».
if [ "$VC_ANCETRE" != 1 ] && [ "$PR_ANCETRE" != 1 ]; then
  faute depuis-quand-non-mesure
fi

TOTAL=$((t_triage + t_machine + t_rouge + penalty))

# ========================================================================= la publication ====
pub ts_census_ran "$([ -n "$JG" ] && echo 1 || echo 0)"
pub test_suite_defects "$TOTAL"
pub test_suite_defects_terms \
  "tri$t_triage+machine$t_machine+rouge$t_rouge+penalite$penalty${why:+:$why}"
pub ts_triage "$t_triage"
pub ts_machine "$t_machine"
pub ts_rouge "$t_rouge"
pub ts_witness_penalty "$penalty"

# 1. LE TRI, classe par classe, puis ligne par ligne. Un total sans ventilation ne vaut rien.
pub test_triage_total "$(jn triage_total)"
pub test_triage_defaut_de_code "$(jn triage_defaut_de_code)"
pub test_triage_decision_owner "$(jn triage_decision_owner)"
pub test_triage_test_devenu_faux "$(jn triage_test_devenu_faux)"
i=1; while [ "$i" -le 12 ]; do
  v=$(j "triage_$i"); [ -n "$v" ] || break
  pub "test_triage_$i" "$v"; i=$((i+1))
done

# 2. LES DEUX COURSES, et ce qui les separe.
pub test_suite_collected_with_ninja "$(jn collectes_a)"
pub test_suite_collected_without_ninja "$(jn collectes_b)"
pub test_suite_failed_with_ninja "$(jn rouges_a)"
pub test_suite_failed_without_ninja "$(jn rouges_b)"
pub test_suite_failed_list "$(j rouges_b_liste)"
pub test_machine_dependent "$(jn ecart_entre_courses)"
pub test_machine_dependent_list "$(j ecart_liste)"
pub test_fake_ninja_ready "$FAUX_PRET"
pub test_fake_ninja_alive_through_run "$FAUX_VIVANT_APRES"
pub test_fake_ninja_cleared "$FAUX_ETEINT"
pub test_live_guard_sees_ninja "$GARDE_VOIT"
pub test_live_guard_sentinel "$GARDE_SENTINELLE"
pub test_before_commit "${AVANT:--}"
pub test_before_marker_absent "$AVANT_SANS_MARQUEUR"
pub test_before_red_under_ninja "$AVANT_AVEC"
pub test_before_green_without_ninja "$AVANT_SANS"
pub test_before_cases_under_ninja "$AV_N"
pub test_before_failures_under_ninja "$AV_R"
pub test_before_named_failure_under_ninja "$AV_NOM"
pub test_before_cases_without_ninja "$AS_N"
pub test_before_failures_without_ninja "$AS_R"
pub test_suite_rc_with_ninja "$RC_A"
pub test_suite_rc_without_ninja "$RC_B"

# 3. LES ECHECS QUI SURVIVENT, chacun avec sa raison ecrite et le nom de qui doit trancher.
pub test_waiting_owner "$(jn dispenses_owner)"
pub test_waived_total "$(jn dispenses)"
pub test_waived_list "$(j dispenses_liste)"
pub test_unwaived_failures "$(jn non_couverts)"
pub test_unwaived_list "$(j non_couverts_liste)"
pub test_stale_waivers "$(jn dispenses_perimees)"
pub test_stale_waivers_list "$(j dispenses_perimees_liste)"
pub test_waived_wrong_signature "$(jn hors_signature)"
pub test_waived_wrong_signature_list "$(j hors_signature_liste)"

# 4. DEPUIS QUAND, tel que git le date — pas tel que le registre le raconte.
pub test_last_green_commit "${VC:--}"
pub test_last_green_date "${VC_DATE:--}"
pub test_last_green_commit_exists "$VC_EXISTE"
pub test_last_green_is_ancestor "$VC_ANCETRE"
pub test_first_red_commit "${PR:--}"
pub test_first_red_date "${PR_DATE:--}"
pub test_first_red_is_ancestor "$PR_ANCETRE"

# LES BRUTS, recopies tels quels : c'est ce qui rend la somme lisible et falsifiable. Sous un
# prefixe a eux — le moissonneur garde la DERNIERE valeur d'une cle, et un homonyme ecraserait
# un terme du verdict.
printf '%s\n' "$JG" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/ts_jg_\1=/p'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in lib/proof_run.sh tests/harness/test_proof_busy.py tests/harness/test_cli_backend.py \
         tests/harness/ECHECS-ATTENDUS.yaml lib/census/harness-test-suite-is-not-a-signal.sh; do
  k="ts_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
