#!/usr/bin/env bash
# census/harness-test-bench-does-not-inherit-the-worker-env.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il n'ecrit aucun champ de `proof.txt` : sa sortie `cle=valeur` rejoint celle du moteur dans le
# meme journal, moissonnee par la meme regle.
#
# LES QUATRE POINTS DU LIVRABLE, CHACUN AVEC SON TERME :
#   1. LE COUT D'AVANT EST CHIFFRE -> la suite ENTIERE, jouee deux fois SOUS LE BRAS D'AVANT
#      (`AUTOPORT_BENCH_ENV_INHERIT=1`, qui rend au banc l'heritage integral) : une fois depuis
#      un environnement nu, une fois avec les quatre `AUTOPORT_*` que l'orchestrateur pose dans
#      la session d'un worker. Le compte de tests dont le VERDICT differe doit etre NON NUL, et
#      il est publie PAR NOM. Un zero ici AJOUTE au verdict : « je n'ai rien trouve » ne
#      demontre pas l'absence de defaut, il demontre que l'instrument n'a rien vu.
#   2. LE BANC PART D'UN ENVIRONNEMENT MAITRISE -> les deux MEMES lancements, bras livre. Le
#      compte de verdicts qui different s'AJOUTE au total : il doit valoir zero. La liste
#      blanche effective est publiee, telle que le banc la voit depuis l'interieur.
#   3. LE CONTROLE POSITIF TIENT SOUS LES DEUX LANCEMENTS -> `test_une_preuve_produite_par_la_
#      machine_passe` est lu NOMMEMENT dans les quatre junit. Vert des deux cotes du bras livre ;
#      et ROUGE du cote worker sous le bras d'avant, sans quoi la comparaison ne mesure rien.
#   4. AUCUNE FUITE APRES -> la sonde `tests/harness/test_bench_env.py`, qui lit de l'INTERIEUR
#      du banc ce qui reste de l'environnement du parent, et publie son denominateur.
#
# POURQUOI LE BRAS D'AVANT EST UN COMMUTATEUR ET NON UN BLOB DE GIT. Le banc entier ne se rejoue
# pas hors de son depot : ses jambes copient des fichiers de `ROOT`, lancent `verdict_sources.sh`
# et le juge reel, et un arbre detache leur rend un AUTRE verdict (7 rouges contre 5 au meme
# commit, mesure du 12/09). Le commutateur, lui, est le SEUL site : `conftest.py` n'avait AUCUN
# assainissement avant ce chantier, donc `INHERIT=1` ne desarme pas un site parmi d'autres — il
# restitue l'etat d'avant en entier. C'est verifie ici, pas affirme : le commit d'AVANT est
# ancre par MARQUEUR (`lib/ablation_anchor.sh`), et on lit dans SON blob que ni le marqueur ni
# l'appel a `bench_env.install(` n'y sont.
#
# POLARITE : INCONNU = DEFAUT. Chaque temoin manquant, muet ou degenere AJOUTE au compte. Sans
# cela, une porte `== 0` sur un nettoyage serait verte par INACTION — une suite qui ne COLLECTE
# rien ne rate rien.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "bev_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1
ID="${AUTOPORT_CENSUS_ID:-harness-test-bench-does-not-inherit-the-worker-env}"
ARMED="${AUTOPORT_CENSUS_ARMED:-1}"

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }
penalite=0; pourquoi=""
faute(){ penalite=$((penalite+1)); pourquoi="${pourquoi:+$pourquoi+}$1"; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0` sans rien avoir mesure.
n(){ local v=${1:-}; case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

SUITE=".autoport/tests/harness"
SONDE="$SUITE/test_bench_env.py"
CONFTEST="$SUITE/conftest.py"
CTL="test_une_preuve_produite_par_la_machine_passe"
MARQ="banc-env-maitrise-2026-09-14"

# LE BRAS DESARME NE REJOUE PAS LA SUITE QUATRE FOIS. Sa seule charge est la ligne FEATURE du
# MOTEUR (`armed=0 hits=0`), que le validateur lit dans `proof-off.txt` ; l'ablation PROPRE a cet
# item est mesuree DANS le bras arme, jambes `avant_*`. Rejouer ici coute 6 minutes pour un
# chiffre que personne ne lit.
if [ "$ARMED" != 1 ]; then
  pub bev_census_ran 1
  pub bev_census_armed 0
  pub bev_note "bras desarme : les jambes de comparaison vivent dans le bras arme"
  exit 0
fi

# LE BANC ECRIT BEAUCOUP DANS TMPDIR — mesure du 14/09 : environ 160 Mo par course, et /tmp
# etait a son quota utilisateur (6311M/6311M), ce qui a rendu 78 faux rouges et un junit
# tronque sur `OSError: [Errno 122] Disk quota exceeded`. Les quatre jambes ecrivent donc dans
# un dossier a elles, sur /home, efface a la sortie.
mkdir -p "$HOME/.cache" 2>/dev/null
TMPD=$(mktemp -d "$HOME/.cache/bench-env-census.XXXXXX") || { echo "bev_census_ran=0"; exit 1; }
TMPBANC="$TMPD/tmp"; mkdir -p "$TMPBANC"
# `rm -rf` sur un bac a sable que ce script vient de creer, jamais sur du code.
trap 'rm -rf "$TMPD"' EXIT

# LES QUATRE VARIABLES QUE L'ORCHESTRATEUR POSE dans la session d'un worker (orchestrator.py,
# `env[...] = ...`). C'est `AUTOPORT_ATTEMPT_ID` qui portait le defaut : `validators/generic.sh`
# exige alors `proof_attempt_id=` dans la preuve, que le fixture synthetique n'ecrit pas.
WORKER=( "AUTOPORT_ATTEMPT_ID=$ID@1#1789000000"
         "AUTOPORT_PHASE_ID=$ID"
         "AUTOPORT_PHASE_VALIDATOR=$AP/validators/generic.sh"
         "AUTOPORT_BACKEND=claude" )

declare -A RC=()
jambe(){   # $1=nom  $2=herite(0|1)  $3=worker(0|1)
  local nom=$1 herite=$2 worker=$3
  local -a e=(env -i "PATH=$PATH" "HOME=$HOME" "TMPDIR=$TMPBANC"
              "AUTOPORT_BENCH_ENV_MANIFEST=$TMPD/$nom.manifest")
  [ -n "${LANG:-}" ]   && e+=("LANG=$LANG")
  [ -n "${LC_ALL:-}" ] && e+=("LC_ALL=$LC_ALL")
  [ "$herite" = 1 ] && e+=("AUTOPORT_BENCH_ENV_INHERIT=1")
  [ "$worker" = 1 ] && e+=("${WORKER[@]}")
  "${e[@]}" timeout -k 15 900 python3 -m pytest "$SUITE" -q -p no:cacheprovider \
      --junitxml="$TMPD/$nom.xml" > "$TMPD/$nom.log" 2>&1
  RC[$nom]=$?
  return 0
}

# L'ORDRE EST CHOISI : le bras livre d'abord. Si le plafond du recensement tombe, ce sont les
# jambes du livrable qu'on veut avoir dans le journal, pas celles de l'archeologie.
jambe apres_nu     0 0
jambe apres_worker 0 1
jambe avant_nu     1 0
jambe avant_worker 1 1

# ================================================== LA COMPARAISON, UN SEUL COMPARATEUR ======
# Deux derivations du nodeid divergeraient en silence : celle-ci est la meme que
# `lib/suite_gate.py:read_junit`, au caractere pres.
eval "$(python3 - "$TMPD" "$SONDE" "$CTL" <<'PY' 2>/dev/null || echo "CMP_OK=0"
import os, sys, xml.etree.ElementTree as ET

d, sonde, ctl = sys.argv[1], sys.argv[2], sys.argv[3]


def lire(nom):
    try:
        r = ET.parse(os.path.join(d, nom + ".xml")).getroot()
    except Exception:                                                  # noqa: BLE001
        return None
    s = r if r.tag == "testsuite" else r.find("testsuite")
    if s is None:
        return None
    res = {}
    for tc in s.iter("testcase"):
        parts = (tc.get("classname") or "").split(".")
        f = ("." + "/".join(parts[1:]) + ".py") if parts and parts[0] == "" \
            else "/".join(parts) + ".py"
        v = "pass"
        for e in tc:
            if e.tag in ("failure", "error"):
                v = e.tag
            elif e.tag == "skipped":
                v = "skipped"
        res["%s::%s" % (f, tc.get("name"))] = v
    return res


def ecart(a, b, sans_sonde):
    if a is None or b is None:
        return None
    noms = set(a) | set(b)
    if sans_sonde:
        noms = {k for k in noms if not k.startswith(sonde + "::")}
    return sorted(k for k in noms if a.get(k, "absent") != b.get(k, "absent"))


def q(s):
    return "'" + str(s).replace("'", "'\\''") + "'"


J = {nom: lire(nom) for nom in
     ("apres_nu", "apres_worker", "avant_nu", "avant_worker")}
out = ["CMP_OK=1"]
for nom, j in J.items():
    out.append("N_%s=%d" % (nom, -1 if j is None else len(j)))
    v = "-" if j is None else next(
        (v for k, v in j.items() if k.endswith("::" + ctl)), "absent")
    out.append("CTL_%s=%s" % (nom, q(v)))
    out.append("SONDE_%s=%d" % (nom, 0 if j is None else
                                len([k for k in j if k.startswith(sonde + "::")])))

for etiq, a, b, sans in (("AVANT", "avant_nu", "avant_worker", True),
                         ("AVANT_TOUT", "avant_nu", "avant_worker", False),
                         ("APRES", "apres_nu", "apres_worker", False)):
    e = ecart(J[a], J[b], sans)
    out.append("D_%s=%d" % (etiq, -1 if e is None else len(e)))
    out.append("L_%s=%s" % (etiq, q("-" if e is None else (",".join(e) or "-"))))
print(" ".join(out))
PY
)"
CMP_OK=${CMP_OK:-0}

# ================================================ LE MANIFESTE DE LA SONDE, BRAS LIVRE =======
# Ecrit par `test_bench_env.py` DEPUIS L'INTERIEUR du banc, sous l'environnement de worker :
# c'est la seule voix qui puisse dire ce qui a survecu au retrait.
MAN="$TMPD/apres_worker.manifest"
m(){ sed -n "s/^$1=//p" "$MAN" 2>/dev/null | tail -1; }
M_MODE=$(m mode); M_PARENT=$(n "$(m parent)"); M_GARD=$(n "$(m gardees)")
M_RET=$(n "$(m retirees)"); M_FUITES=$(n "$(m fuites)"); M_HORS=$(n "$(m hors_liste)")
M_APSURV=$(n "$(m autoport_survivants)"); M_APPAR=$(n "$(m autoport_parent)")
M_SONDE_PAR=$(n "$(m sonde_du_parent)"); M_SONDE_VUES=$(n "$(m sonde_vues)")

# ==================================== L'ANCRE DU BRAS D'AVANT, PAR MARQUEUR ===================
AVANT_C=$(bash "$AP/lib/ablation_anchor.sh" "$ROOT" "$CONFTEST" "$MARQ" commit 2>/dev/null) || AVANT_C=""
# JAMAIS `git show | grep -q` : sous `pipefail`, `grep -q` sort a la premiere occurrence,
# `git show` meurt en SIGPIPE (141) et la condition devient FAUSSE sur un fichier qui PORTE le
# motif. Le blob passe par une variable, et `grep -c` compte.
BLOB_AVANT=""
[ -n "$AVANT_C" ] && BLOB_AVANT=$(git show "$AVANT_C:$CONFTEST" 2>/dev/null)
cpte(){ printf '%s' "$2" | grep -cF -- "$1" 2>/dev/null || true; }
AV_MARQ=$(cpte "$MARQ" "$BLOB_AVANT")
AV_INST=$(cpte "bench_env.install(" "$BLOB_AVANT")
AP_MARQ=$(cpte "$MARQ" "$(cat "$CONFTEST" 2>/dev/null)")
AP_INST=$(cpte "bench_env.install(" "$(cat "$CONFTEST" 2>/dev/null)")

# LE GESTE, RECENSE : combien de sites du banc fabriquent un environnement a partir de
# `os.environ`. C'est la population que l'UNIQUE point d'assainissement gouverne ; la publier
# est ce qui rend verifiable « OFF egale l'absence », puisqu'il n'y a pas d'autre site a
# desarmer.
SITES=$(grep -rhoF 'os.environ' "$SUITE"/*.py 2>/dev/null | grep -c . || true)
POINTS=$(grep -cF 'bench_env.install(' "$CONFTEST" 2>/dev/null || true)

# ================================================================= LES TERMES ================
# 1. LE COUT D'AVANT
t_cout=0
D_AVANT=$(n "${D_AVANT:-}")
[ "$CMP_OK" = 1 ] || { t_cout=$((t_cout+1)); faute comparateur-muet; }
[ "$D_AVANT" -ge 1 ] 2>/dev/null || { t_cout=$((t_cout+1)); faute cout-avant-nul-ou-illisible; }
[ "${CTL_avant_nu:-}" = pass ] || { t_cout=$((t_cout+1)); faute avant-nu-ne-passe-pas-le-controle-positif; }
[ "${CTL_avant_worker:-}" = failure ] || { t_cout=$((t_cout+1)); faute avant-worker-ne-rougit-pas-le-defaut-ne-se-rejoue-pas; }
# LA SONDE DE CET ITEM NE DOIT PAS GONFLER LE COUT D'AVANT : sautee des deux cotes, elle ne
# change aucun verdict. L'ecart calcule AVEC elle doit valoir celui calcule SANS.
[ "$(n "${D_AVANT_TOUT:-}")" = "$D_AVANT" ] || { t_cout=$((t_cout+1)); faute la-sonde-de-l-item-pese-sur-le-cout-d-avant; }

# 2. LE BANC PART D'UN ENVIRONNEMENT MAITRISE
t_apres=0
D_APRES=$(n "${D_APRES:-}")
if [ "$D_APRES" -ge 0 ] 2>/dev/null; then t_apres=$((t_apres + D_APRES))
else t_apres=$((t_apres+1)); faute ecart-apres-illisible; fi
[ "$M_MODE" = maitrise ] || { t_apres=$((t_apres+1)); faute banc-livre-pas-en-mode-maitrise; }
[ "$M_HORS" = 0 ] || { t_apres=$((t_apres+1)); faute garde-hors-liste-blanche; }

# 3. LE CONTROLE POSITIF TIENT SOUS LES DEUX LANCEMENTS
t_ctl=0
[ "${CTL_apres_nu:-}" = pass ]     || { t_ctl=$((t_ctl+1)); faute controle-positif-rouge-depuis-un-shell-nu; }
[ "${CTL_apres_worker:-}" = pass ] || { t_ctl=$((t_ctl+1)); faute controle-positif-rouge-depuis-une-session-de-worker; }
# LES QUATRE JAMBES ONT VRAIMENT COLLECTE. Plancher calibre sur la population NON filtree :
# 599 cas le 14/09 (595 tests du banc + 4 jambes de la sonde). 500 dit qu'on a lu une suite,
# pas trois rescapes d'une collecte cassee.
for nom in apres_nu apres_worker avant_nu avant_worker; do
  eval "cnt=\${N_$nom:--1}"
  [ "$(n "$cnt")" -ge 500 ] 2>/dev/null || { t_ctl=$((t_ctl+1)); faute "jambe-maigre:$nom=$cnt"; }
done
# La sonde TOURNE dans le bras livre et se SAUTE dans le bras d'avant : ses jambes sont
# collectees dans les quatre cas (une jambe sautee reste un `testcase` du junit).
[ "$(n "${SONDE_apres_worker:-}")" -ge 1 ] 2>/dev/null || { t_ctl=$((t_ctl+1)); faute sonde-non-collectee; }

# 4. AUCUNE FUITE APRES
t_fuite=0
if [ "$M_FUITES" -ge 0 ] 2>/dev/null; then t_fuite=$((t_fuite + M_FUITES))
else t_fuite=$((t_fuite+1)); faute manifeste-de-la-sonde-absent; fi
if [ "$M_SONDE_PAR" -ge 0 ] 2>/dev/null; then t_fuite=$((t_fuite + M_SONDE_PAR))
else t_fuite=$((t_fuite+1)); faute sonde-de-sous-processus-muette; fi
# LE DENOMINATEUR : « zero fuite sur zero retrait » n'est pas un succes. Le parent de la jambe
# `apres_worker` pose 4 `AUTOPORT_*`, et un seul — le canal du manifeste — a le droit de passer.
[ "$M_RET" -ge 1 ] 2>/dev/null || { t_fuite=$((t_fuite+1)); faute rien-retire-instrument-aveugle; }
[ "$M_APPAR" -ge 4 ] 2>/dev/null || { t_fuite=$((t_fuite+1)); faute moins-de-quatre-autoport-au-parent-simulation-degeneree; }
[ "$M_APSURV" = 1 ] || { t_fuite=$((t_fuite+1)); faute autoport-survivants-hors-mention-explicite; }

# L'ANCRE : sans elle, « OFF egale l'etat d'avant » serait une affirmation.
t_ancre=0
[ -n "$AVANT_C" ] || { t_ancre=$((t_ancre+1)); faute bras-avant-non-ancre; }
[ "$AV_MARQ" = 0 ] || { t_ancre=$((t_ancre+1)); faute marqueur-deja-present-avant; }
[ "$AV_INST" = 0 ] || { t_ancre=$((t_ancre+1)); faute assainissement-deja-present-avant; }
[ "$AP_MARQ" -ge 1 ] 2>/dev/null || { t_ancre=$((t_ancre+1)); faute marqueur-absent-de-l-arbre-livre; }
[ "$AP_INST" -ge 1 ] 2>/dev/null || { t_ancre=$((t_ancre+1)); faute assainissement-absent-de-l-arbre-livre; }
[ "$POINTS" = 1 ] || { t_ancre=$((t_ancre+1)); faute "points-d-assainissement=$POINTS-il-en-faut-exactement-un"; }
[ "$SITES" -ge 1 ] 2>/dev/null || { t_ancre=$((t_ancre+1)); faute aucun-site-os-environ-recense; }

# ============================= LE COMPTE QUI DONNE SON NOM A LA PORTE =========================
TOTAL=$((t_cout + t_apres + t_ctl + t_fuite + t_ancre + penalite))
pub bench_env_leaks "$TOTAL"
pub bench_env_terms \
  "cout$t_cout+apres$t_apres+ctl$t_ctl+fuite$t_fuite+ancre$t_ancre+penalite$penalite${pourquoi:+:$pourquoi}"

# LES GRANDEURS BRUTES : une porte qui ne publie que son total ne dit pas ce qui a cede.
pub bev_before_diff "$D_AVANT"
pub bev_before_diff_list "${L_AVANT:--}"
pub bev_before_diff_all "$(n "${D_AVANT_TOUT:-}")"
pub bev_after_diff "$D_APRES"
pub bev_after_diff_list "${L_APRES:--}"
pub bev_ctl_before_bare "${CTL_avant_nu:--}"
pub bev_ctl_before_worker "${CTL_avant_worker:--}"
pub bev_ctl_after_bare "${CTL_apres_nu:--}"
pub bev_ctl_after_worker "${CTL_apres_worker:--}"
for nom in apres_nu apres_worker avant_nu avant_worker; do
  eval "pub bev_leg_${nom}_tests \"\${N_$nom:--1}\""
  pub "bev_leg_${nom}_rc" "${RC[$nom]:--1}"
done
pub bev_worker_vars "$(printf '%s\n' "${WORKER[@]}" | sed 's/=.*//' | paste -sd, -)"
pub bev_whitelist "$(m liste_blanche)"
pub bev_explicites "$(m explicites)"
pub bev_kept_list "$(m gardees_liste)"
pub bev_parent_vars "$M_PARENT"
pub bev_kept_vars "$M_GARD"
pub bev_removed_vars "$M_RET"
pub bev_leaks_from_parent "$M_FUITES"
pub bev_leaks_list "$(m fuites_liste)"
pub bev_kept_outside_whitelist "$M_HORS"
pub bev_autoport_at_parent "$M_APPAR"
pub bev_autoport_at_parent_list "$(m autoport_parent_liste)"
pub bev_autoport_survivors "$M_APSURV"
pub bev_autoport_survivors_list "$(m autoport_survivants_liste)"
pub bev_probe_subproc_seen "$M_SONDE_VUES"
pub bev_probe_subproc_from_parent "$M_SONDE_PAR"
pub bev_probe_nodes "$(n "${SONDE_apres_worker:-}")"
pub bev_before_commit "${AVANT_C:--}"
pub bev_before_marker "$AV_MARQ"
pub bev_before_install "$AV_INST"
pub bev_after_marker "$AP_MARQ"
pub bev_after_install "$AP_INST"
pub bev_scrub_points "$POINTS"
pub bev_environ_sites "$SITES"
pub bev_census_armed 1
pub bev_census_ran "$([ "$CMP_OK" = 1 ] && [ -s "$MAN" ] && echo 1 || echo 0)"

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in tests/harness/bench_env.py tests/harness/conftest.py tests/harness/test_bench_env.py \
         lib/census/$ID.sh; do
  k="bev_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done

exit 0
