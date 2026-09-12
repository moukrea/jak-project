#!/usr/bin/env bash
# census/harness-proof-file-has-no-writer-lock.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il ne peut ecrire aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent
# de la machine.
#
# CE QU'IL MESURE, ET DANS QUEL ORDRE (les quatre points du livrable) :
#   1. UN SEUL ecrivain par preuve, par verrou : la seconde course attend ou refuse, elle
#      n'ecrase pas — et le nombre de tentatives concurrentes est publie -> pwl_verrou
#   2. la preuve porte l'identite de SA course, et la porte refuse celle d'un autre essai.
#      Deux bras : la preuve semee d'un essai precedent est ACCEPTEE avant, REFUSEE apres
#                                                                       -> pwl_identite
#   3. un `proof_run.sh` orphelin est detecte et ARRETE, et un ecrivain sain est LAISSE
#                                                                       -> pwl_orphelins
#   4. les commits survenus pendant la course sont comptes et NOMMES    -> pwl_commits
#   5. la course qui porte ce recensement tient elle-meme son verrou    -> pwl_course
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte. Un banc qui n'a
# pas tourne, un bras d'AVANT qui refuse comme le bras neuf (donc qui ne prouve rien), un
# controle sain qu'on a arrete avec les orphelins : tout cela rend la porte ROUGE. Sans cette
# polarite, une porte `== 0` sur un verrou serait verte par INACTION — il suffirait de ne
# jamais rencontrer deux ecrivains.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "pwl_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }
penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }

# ======================================================== LE BANC, TOUS SES BRAS D'UN COUP ====
RAW=$(timeout -k 30 600 bash "$AP/lib/proof_writer_selftest.sh" 2>/dev/null)
g(){ printf '%s\n' "$RAW" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(g "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }
[ "$(n selftest_ran)" = 1 ] || faute banc-muet

# ===================================== LA COURSE QUI PORTE CE RECENSEMENT, LUE SUR SON ETAT ===
# `proof.txt` n'existe pas encore quand ce script tourne : l'ecrivain publie son etat sous le
# nom que `lib/impossible.py` derive, et c'est CE fichier-la qu'on lit. Le nom vient de
# l'AUTORITE, jamais d'un litteral — un nom fabrique ici serait le deuxieme nommeur.
CD="${AUTOPORT_CENSUS_DIR:-}"
ARMED="${AUTOPORT_CENSUS_ARMED:-1}"
SUF=$(python3 - "$ARMED" <<'PY' 2>/dev/null
import os, sys
sys.path.insert(0, os.path.join('.autoport', 'lib'))
import impossible as I
print(I.arm_suffix(sys.argv[1]))
PY
)
NOM_RUN=$(python3 "$AP/lib/impossible.py" name run "$SUF" 2>/dev/null)
NOM_VERROU=$(python3 "$AP/lib/impossible.py" name writer "$SUF" 2>/dev/null)
RUNF="$CD/$NOM_RUN"; VERROUF="$CD/$NOM_VERROU"
r(){ sed -n "s/^$1=//p" "$RUNF" 2>/dev/null | tail -1; }
v(){ sed -n "s/^$1=//p" "$VERROUF" 2>/dev/null | tail -1; }
[ -n "$NOM_RUN" ] && [ -n "$NOM_VERROU" ] || faute autorite-ne-nomme-pas-le-verrou
[ -s "$RUNF" ] || faute etat-de-course-absent
[ -s "$VERROUF" ] || faute verrou-de-course-absent

# ===================================== LES ESSAIS JUGES AVANT L'ECRITURE DE LEUR PREUVE =======
# LA GRANDEUR QUI MANQUAIT, dite par le contrat. Le 12/09 a 18:12,
# `build-android-reinvalidates-itself` a ete BLOQUE sur trois refus identiques « proof.txt
# absent ou vide » alors que son travail etait commite a 18:04 et 18:06 et que sa preuve — 34 340
# octets — a ete ecrite a 18:21. PUBLIEE, PAS COMPTEE : c'est une population historique, et un
# item ne se ferme pas sur ce que d'autres ont vecu avant lui. Ce qui est COMPTE, c'est que le
# juge SACHE le dire (bras `ev_*` du banc) et que l'orchestrateur ATTENDE l'ecrivain.
JUG=$(python3 - "$ROOT" <<'PY' 2>/dev/null
import os, sys
racine = sys.argv[1]
# LE NOM DE LA PREUVE VIENT DE L'AUTORITE (NOMMAGE/un-seul-endroit) : un litteral ici serait un
# deuxieme nommeur, et il divergerait le jour ou l'autorite change d'extension.
sys.path.insert(0, os.path.join(racine, '.autoport', 'lib'))
import impossible as I
NOM_PREUVE = I.arm_name('proof', '')
logs = os.path.join(racine, '.autoport', 'logs')
rapports = os.path.join(racine, '.autoport', 'reports')
# NOM-LITTERAL-ATTENDU: message-du-juge-recherche-dans-son-journal
MOTIF = 'proof.txt absent ou vide'
lus = refus = avant = 0
items = 0
noms = []
for item in sorted(os.listdir(logs)) if os.path.isdir(logs) else []:
    d = os.path.join(logs, item)
    if not os.path.isdir(d):
        continue
    items += 1
    preuve = os.path.join(rapports, item, NOM_PREUVE)
    try:
        t_preuve = os.path.getmtime(preuve)
    except OSError:
        t_preuve = None
    for nom in sorted(os.listdir(d)):
        if not (nom.startswith('validator-') and nom.endswith('.txt')):
            continue
        chemin = os.path.join(d, nom)
        lus += 1
        try:
            texte = open(chemin, encoding='utf-8', errors='replace').read()
            t_juge = os.path.getmtime(chemin)
        except OSError:
            continue
        if MOTIF not in texte:
            continue
        refus += 1
        # LE JUGE EST PASSE AVANT : la preuve existe, et elle a ete ecrite APRES son verdict.
        if t_preuve is not None and t_preuve > t_juge:
            avant += 1
            noms.append('%s/%s' % (item, nom))
print('jug_items=%d' % items)
print('jug_lus=%d' % lus)
print('jug_refus_sans_preuve=%d' % refus)
print('jug_avant_preuve=%d' % avant)
print('jug_avant_liste=%s' % (','.join(noms[:12]) or '-'))
PY
) || JUG=""
j(){ printf '%s\n' "$JUG" | sed -n "s/^$1=//p" | tail -1; }
jn(){ local x; x=$(j "$1"); case "$x" in ''|*[!0-9-]*) echo -1 ;; *) echo "$x" ;; esac; }
[ -n "$JUG" ] || faute population-des-juges-muette
# LE DENOMINATEUR AVANT LE NUMERATEUR. `.autoport/logs/` est GITIGNORE : dans un worktree
# detache il est vide, et « zero essai juge trop tot » s'y lirait comme une reussite. On exige
# donc que quelque chose ait ete LU, et on dit ou.
[ "$(jn jug_lus)" -ge 50 ] 2>/dev/null || faute journaux-de-validation-trop-peu-nombreux

# =================================== L'ORCHESTRATEUR SAIT-IL ATTENDRE L'ECRIVAIN ? ============
# Le compteur `proof_writer` de `state.json` n'existe que si l'orchestrateur l'ECRIT : un
# compteur publie que personne n'incremente est le defaut d'a cote. On verifie donc le SITE
# D'ECRITURE — la cle est dans `STATE_KEYS`, donc elle survit a `save_state` — et l'appel qui
# retient le juge, par exécution : la fonction est chargee et jouee sur un etat seme.
ORCH=$(python3 - "$ROOT" <<'PY' 2>/dev/null
import ast, os, re, sys, tempfile, time
racine = sys.argv[1]
src = open(os.path.join(racine, '.autoport', 'orchestrator.py'), encoding='utf-8').read()
print('orch_state_key=%d' % int('"proof_writer"' in src))
print('orch_appel_attente=%d' % len(re.findall(r'wait_for_proof_writer\(', src)))
# LES DEUX COTES, COMPTES SEPAREMENT. Une identite posee pour le worker mais pas pour le juge
# ne compare rien ; posee pour le juge mais pas pour le worker, elle refuse TOUTE preuve. Et
# c'est le MEME jeton des deux cotes : on compte la variable, pas la chaine.
print('orch_env_essai=%d' % len(re.findall(r'AUTOPORT_ATTEMPT_ID', src)))
print('orch_essai_worker=%d' % len(re.findall(r'env\["AUTOPORT_ATTEMPT_ID"\]\s*=\s*attempt_token', src)))
print('orch_essai_juge=%d' % len(re.findall(r'"AUTOPORT_ATTEMPT_ID":\s*attempt_token', src)))
# LE NOM DU VERROU VIENT DE L'AUTORITE DANS L'ORCHESTRATEUR AUSSI : on le verifie en le
# demandant, jamais en cherchant un litteral.
sys.path.insert(0, os.path.join(racine, '.autoport', 'lib'))
import impossible as I
print('orch_nom_verrou=%s' % I.arm_name('writer', ''))
print('orch_litteral_verrou=%d' % src.count(I.arm_name('writer', '')))
# LA FONCTION, JOUEE. On la sort du module par `ast` — importer `orchestrator` construirait une
# console et lirait le backlog — et on la fait tourner sur un bac a sable ou l'on seme un verrou
# qui nomme un pid MORT : elle doit rendre (0, 0), et donc ne retenir personne.
arbre = ast.parse(src)
corps = [x for x in arbre.body
         if isinstance(x, ast.FunctionDef) and x.name in ('proof_writer_alive', 'wait_for_proof_writer')]
print('orch_fonctions=%d' % len(corps))
espace = {'impossible_state': I, 'time': time, 'Path': __import__('pathlib').Path,
          'PROOF_WRITER_WAIT_MAX': 5}
with tempfile.TemporaryDirectory() as bac:
    espace['AUTOPORT_DIR'] = __import__('pathlib').Path(bac)
    d = os.path.join(bac, 'reports', 'bac')
    os.makedirs(d)
    open(os.path.join(d, I.arm_name('writer', '')), 'w').write(
        'pid=999999999\nlauncher=1\nat=2026-09-12T18:12:00Z\n')
    for f in corps:
        exec(compile(ast.Module(body=[f], type_ignores=[]), '<orch>', 'exec'), espace)
    try:
        attendu, pid = espace['wait_for_proof_writer']('bac')
        print('orch_mort_attendu=%d' % attendu)
        print('orch_mort_pid=%d' % pid)
    except Exception as exc:                                       # noqa: BLE001
        print('orch_mort_attendu=-1')
        print('orch_mort_pid=-1')
        print('orch_erreur=%s' % type(exc).__name__)
    # ET LE CAS VIVANT : un verrou qui nomme NOTRE pid doit etre vu, et retenir le juge.
    open(os.path.join(d, I.arm_name('writer', '')), 'w').write(
        'pid=%d\nlauncher=1\nat=2026-09-12T18:12:00Z\n' % os.getpid())
    try:
        pid, quand = espace['proof_writer_alive']('bac')
        print('orch_vivant_pid=%d' % int(pid == os.getpid()))
    except Exception:                                              # noqa: BLE001
        print('orch_vivant_pid=-1')
PY
) || ORCH=""
o(){ printf '%s\n' "$ORCH" | sed -n "s/^$1=//p" | tail -1; }
on(){ local x; x=$(o "$1"); case "$x" in ''|*[!0-9-]*) echo -1 ;; *) echo "$x" ;; esac; }
[ -n "$ORCH" ] || faute lecture-orchestrateur-muette

# ====================================================================== LES TERMES DU VERDICT ==

# 1. UN SEUL ECRIVAIN. Le bras d'AVANT doit ECRASER (sinon l'ablation ne prouve aucun defaut),
#    le bras d'attente doit laisser gagner le DERNIER arrive, le bras de refus ne doit rien
#    ecrire du tout. Les tentatives concurrentes sont COMPTEES, pas supposees.
t_verrou=0
[ "$(g vr_attente_final)" = B ] || t_verrou=$((t_verrou+1))
[ "$(g vr_attente_ordre)" = A,B ] || t_verrou=$((t_verrou+1))
[ "$(n vr_attente_concurrent)" -ge 1 ] 2>/dev/null || t_verrou=$((t_verrou+1))
[ "$(n vr_attente_s)" -ge 1 ] 2>/dev/null || t_verrou=$((t_verrou+1))
[ "$(n vr_refus_rc)" = 7 ] || t_verrou=$((t_verrou+1))
[ "$(n vr_refus_b_ecrit)" = 0 ] || t_verrou=$((t_verrou+1))
[ "$(g vr_refus_final)" = A ] || t_verrou=$((t_verrou+1))
[ "$(n vr_refus_concurrent)" -ge 1 ] 2>/dev/null || t_verrou=$((t_verrou+1))
# LE BRAS D'AVANT EST LE TEMOIN POSITIF : sans ecrasement mesure, « ca n'ecrase plus » ne
# decrirait aucun defaut corrige.
[ "$(n vr_avant_ecrasement)" = 1 ] || faute avant-sans-ecrasement
[ "$(g vr_avant_ordre)" = B,A ] || faute avant-ordre-inattendu
[ "$(n bloc_verrou_octets)" -ge 2000 ] 2>/dev/null || faute bloc-verrou-trop-court
[ "$(n avant_verrou_octets)" = 0 ] || faute avant-portait-deja-le-verrou
[ "$(n avant_flock_sites)" = 0 ] || faute avant-portait-deja-flock
[ "$(n avant_proof_run_octets)" -ge 10000 ] 2>/dev/null || faute avant-blob-proof-run-vide

# 2. L'IDENTITE DE LA COURSE. Quatre cas, dans les deux sens : refuser une preuve d'un autre
#    essai, ACCEPTER celle de l'essai courant, refuser une preuve muette, et ne rien refuser
#    quand aucun essai n'est pose (course lancee a la main).
t_ident=0
[ "$(g id_apres_perime)"     = refuse  ] || t_ident=$((t_ident+1))
[ "$(g id_apres_courant)"    = accepte ] || t_ident=$((t_ident+1))
[ "$(g id_apres_sans_cle)"   = refuse  ] || t_ident=$((t_ident+1))
[ "$(g id_apres_sans_essai)" = accepte ] || t_ident=$((t_ident+1))
[ "$(g id_avant_perime)"  = accepte ] || faute avant-refusait-deja-la-preuve-perimee
[ "$(g id_avant_courant)" = accepte ] || faute avant-refusait-tout
[ "$(n avant_identite_sites)"  = 0 ] || faute avant-portait-deja-l-identite
[ "$(n bloc_identite_octets)" -ge 400 ] 2>/dev/null || faute bloc-identite-trop-court
# ET L'ORCHESTRATEUR POSE BIEN L'IDENTITE DES DEUX COTES : l'essai ET le juge.
[ "$(on orch_essai_worker)" = 1 ] || t_ident=$((t_ident+1))
[ "$(on orch_essai_juge)"   = 1 ] || t_ident=$((t_ident+1))

# 3. L'ORPHELIN ARRETE, ET LE SAIN LAISSE. Deux populations semees : sans la seconde, « on
#    arrete les orphelins » serait vert pour un balayage qui tue tout ce qui tient le verrou.
t_orph=0
[ "$(n vr_orph_trouves)"  = 1 ] || t_orph=$((t_orph+1))
[ "$(n vr_orph_arretes)"  = 1 ] || t_orph=$((t_orph+1))
[ "$(n vr_orph_restes)"   = 0 ] || t_orph=$((t_orph+1))
[ "$(n vr_orph_a_vivant)" = 0 ] || t_orph=$((t_orph+1))
[ "$(n vr_orph_a_ecrit)"  = 0 ] || t_orph=$((t_orph+1))
[ "$(g vr_orph_final)"    = B ] || t_orph=$((t_orph+1))
[ "$(n vr_sain_trouves)"  = 0 ] || t_orph=$((t_orph+1))
[ "$(n vr_sain_a_vivant)" = 1 ] || t_orph=$((t_orph+1))
[ "$(n vr_sain_a_ecrit)"  = 1 ] || t_orph=$((t_orph+1))
[ "$(g vr_sain_final)"    = A ] || t_orph=$((t_orph+1))

# 4. LES COMMITS PENDANT LA COURSE, COMPTES ET NOMMES. Le compte doit etre EXACT a chaque cran
#    de l'histoire, les DEUX populations doivent exister, et un depart inconnu doit rendre -1 —
#    jamais 0, qui se lirait « rien n'a bouge ».
t_commits=0
[ "$(n rc_population)" -ge 20 ] 2>/dev/null || t_commits=$((t_commits+1))
[ "$(n rc_compte_exact)" = "$(n rc_population)" ] || t_commits=$((t_commits+1))
[ "$(n rc_avec_source)" -ge 1 ] 2>/dev/null || t_commits=$((t_commits+1))
[ "$(n rc_sans_source)" -ge 1 ] 2>/dev/null || t_commits=$((t_commits+1))
[ "$(n rc_total_verdict)" = "$(n rc_avec_source)" ] || t_commits=$((t_commits+1))
[ "$(n rc_inconnu)" = -1 ] || t_commits=$((t_commits+1))
[ "$(n rc_zero)" = 0 ] || t_commits=$((t_commits+1))
# ET LE JUGE SAIT DIRE QU'UNE COURSE ECRIT, au lieu d'accuser un travail deja fait.
[ "$(g ev_vivant)" = nomme ] || t_commits=$((t_commits+1))
[ "$(g ev_mort)"   = muet  ] || t_commits=$((t_commits+1))
[ "$(n bloc_envol_octets)" -ge 400 ] 2>/dev/null || faute bloc-envol-trop-court

# 5. LA COURSE QUI PORTE CE RECENSEMENT TIENT SON PROPRE VERROU. Un banc en bac a sable prouve
#    le geste ; ce terme-ci prouve qu'il est ARME dans la course en cours — c'est la difference
#    entre un mecanisme qui marche et un mecanisme qui tourne.
t_course=0
PID_ECRIVAIN=$(v pid)
[ -n "$PID_ECRIVAIN" ] && kill -0 "$PID_ECRIVAIN" 2>/dev/null || t_course=$((t_course+1))
[ "$(r proof_run_id)" != "" ] || t_course=$((t_course+1))
[ "$(r proof_writer_lock)" = "$VERROUF" ] || t_course=$((t_course+1))
[ "$(v run)" = "$(r proof_run_id)" ] || t_course=$((t_course+1))
[ "$(v attempt)" = "$(r proof_attempt_id)" ] || t_course=$((t_course+1))
[ "$(r proof_orphans_survived)" = 0 ] || t_course=$((t_course+1))
[ "$(r proof_commits_start_known)" = 1 ] || t_course=$((t_course+1))
# L'ORCHESTRATEUR RETIENT LE JUGE, et il ne retient personne sur un pid mort.
[ "$(on orch_fonctions)" = 2 ] || t_course=$((t_course+1))
[ "$(on orch_appel_attente)" -ge 2 ] 2>/dev/null || t_course=$((t_course+1))
[ "$(on orch_state_key)" = 1 ] || t_course=$((t_course+1))
[ "$(on orch_mort_pid)" = 0 ] || t_course=$((t_course+1))
[ "$(on orch_vivant_pid)" = 1 ] || t_course=$((t_course+1))
# UN NOM FABRIQUE DEUX FOIS DIVERGE : l'orchestrateur ne doit porter AUCUN litteral du verrou.
[ "$(on orch_litteral_verrou)" = 0 ] || faute orchestrateur-code-le-nom-du-verrou-en-dur

TOTAL=$((t_verrou + t_ident + t_orph + t_commits + t_course + penalty))

# ========================================================================== LA PUBLICATION =====
pub pwl_census_ran "$([ -n "$RAW" ] && [ -n "$JUG" ] && [ -n "$ORCH" ] && echo 1 || echo 0)"
pub proof_writer_defects "$TOTAL"
pub pwl_defects_terms \
  "verrou$t_verrou+identite$t_ident+orphelins$t_orph+commits$t_commits+course$t_course+penalite$penalty${why:+:$why}"
pub pwl_verrou     "$t_verrou"
pub pwl_identite   "$t_ident"
pub pwl_orphelins  "$t_orph"
pub pwl_commits    "$t_commits"
pub pwl_course     "$t_course"
pub pwl_penalite   "$penalty"

# LE LIVRABLE, EN CLAIR — les quatre grandeurs que le contrat demande de PUBLIER.
pub pwl_concurrents_rencontres "$(r proof_writer_concurrent)"
pub pwl_attente_s              "$(r proof_writer_wait_s)"
pub pwl_orphelins_trouves      "$(r proof_orphans_found)"
pub pwl_orphelins_arretes      "$(r proof_orphans_stopped)"
pub pwl_orphelins_survivants   "$(r proof_orphans_survived)"
pub pwl_commits_pendant_course "$(r proof_commits_during_run)"
pub pwl_commits_sur_le_juge    "$(r proof_commits_verdict_sources)"
pub pwl_commits_liste          "$(r proof_commits_verdict_list)"
pub pwl_identite_de_la_course  "$(r proof_attempt_id)"
pub pwl_course_id              "$(r proof_run_id)"
pub pwl_verrou_pid             "$(v pid)"
pub pwl_verrou_lanceur         "$(v launcher)"
pub pwl_verrou_nom             "$NOM_VERROU"
pub pwl_etat_nom               "$NOM_RUN"

# LA POPULATION HISTORIQUE, PUBLIEE ET JAMAIS COMPTEE, avec son denominateur et l'endroit ou
# elle a ete lue : `.autoport/logs/` est GITIGNORE, un worktree detache en rendrait zero.
pub pwl_juges_avant_preuve  "$(j jug_avant_preuve)"
pub pwl_juges_avant_liste   "$(j jug_avant_liste)"
pub pwl_validateurs_lus     "$(j jug_lus)"
pub pwl_refus_sans_preuve   "$(j jug_refus_sans_preuve)"
pub pwl_items_avec_journal  "$(j jug_items)"
pub pwl_journaux_lus_dans   "$ROOT/.autoport/logs"

# LES GRANDEURS BRUTES, sous des prefixes a eux : le moissonneur de `proof_run.sh` garde la
# DERNIERE valeur d'une cle, et un brut homonyme d'un terme du verdict l'ecraserait en silence.
printf '%s\n' "$RAW"  | sed -n 's/^\([a-z_][a-z0-9_]*\)=/pwl_banc_\1=/p'
printf '%s\n' "$ORCH" | sed -n 's/^orch_\([a-z0-9_]*\)=/pwl_orch_\1=/p'
printf '%s\n' "$JUG"  | sed -n 's/^jug_\([a-z0-9_]*\)=/pwl_jug_\1=/p'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in lib/proof_run.sh lib/run_commits.sh lib/proof_writer_selftest.sh lib/impossible.py \
         validators/generic.sh orchestrator.py lib/census/harness-proof-file-has-no-writer-lock.sh; do
  k="pwl_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
