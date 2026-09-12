#!/usr/bin/env bash
# census/harness-subsecond-freshness-is-blind.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il ne peut ecrire aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent
# de la machine.
#
# CE QU'IL MESURE, ET DANS QUEL ORDRE (les quatre points du livrable) :
#   1. chaque comparaison corrigee lit la MEME resolution des deux cotes -> sf_resolution_asym
#   2. l'egalite ne vaut plus fraicheur, et les cas rencontres sont comptes -> sf_egalite_acceptee
#   3. les deux bras sur un bac a sable : AVANT accepte, APRES refuse  -> sf_bras_avant/sf_bras_apres
#   4. la population complete est publiee, avec ce qui est laisse et pourquoi -> sf_non_classe
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte. Un bac a sable qui
# n'a pas tourne, un bras d'ablation qui refuse comme le bras neuf (donc qui ne prouve rien), une
# occurrence d'horodatage que le registre ne couvre pas : tout cela rend la porte ROUGE. Sans
# cette polarite, une porte `== 0` sur un nettoyage est verte par INACTION.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "sf_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1
REGISTRE="$AP/lib/freshness_registry.tsv"

pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }
penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }

# ============================================================ LE BAC A SABLE, DEUX BRAS =======
RAW=$(timeout -k 30 600 bash "$AP/lib/subsecond_freshness_selftest.sh" 2>/dev/null)
g(){ printf '%s\n' "$RAW" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(g "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

[ "$(n selftest_ran)" = 1 ] || faute bac-a-sable-muet

# ============================================== LE SITE PYTHON : `orchestrator.py`, DEUX BRAS =
# Le bras APRES fait jouer la VRAIE fonction. Le bras AVANT rejoue l'OPERATEUR du dernier etat
# sans le correctif — ancre par `lib/ablation_anchor.sh` sur un MARQUEUR, jamais lu a `HEAD:`,
# qui s'accuserait lui-meme des le commit qui corrige. On ne DECOUPE pas une tranche de script :
# on extrait la ligne de comparaison, on EXIGE qu'il y en ait exactement une, et on EXECUTE son
# operateur sur le cas d'egalite. Zero ou deux occurrences = defaut, pas un vert par defaut.
ORCH=$(python3 - "$ROOT" <<'PY' 2>/dev/null
import os, re, subprocess, sys
root = sys.argv[1]
ap = os.path.join(root, '.autoport')
sys.path.insert(0, os.path.join(ap, 'lib'))
out = {}
import freshness as F  # noqa: E402

# --- bras APRES : la vraie fonction, sur les trois cas. t0 = 100.
frais, douteux = F.classer_artefacts("99 files/avant.txt\n100 files/pile.txt\n101 files/apres.txt\n", 100)
out['orch_apres_frais'] = ','.join(frais) or '-'
out['orch_apres_douteux'] = ','.join(douteux) or '-'
out['orch_apres_egal_refuse'] = int('files/pile.txt' not in frais)
out['orch_apres_futur_frais'] = int('files/apres.txt' in frais)
out['orch_apres_passe_refuse'] = int('files/avant.txt' not in frais and 'files/avant.txt' not in douteux)
out['orch_res_artefact'] = F.RESOLUTION_APPAREIL
out['orch_res_t0'] = F.RESOLUTION_APPAREIL

# --- bras AVANT : l'operateur du dernier etat sans `classer_artefacts`.
def anchor(rel, marqueur):
    try:
        s = subprocess.run(['bash', os.path.join(ap, 'lib', 'ablation_anchor.sh'),
                            root, rel, marqueur, 'kv'],
                           capture_output=True, text=True, timeout=180).stdout
    except Exception:
        return '', 'erreur'
    ch = dict(l.split('=', 1) for l in s.splitlines() if '=' in l)
    return ch.get('anchor_commit', '-'), ch.get('anchor_method', 'absent')

commit, methode = anchor('.autoport/orchestrator.py', 'classer_artefacts')
out['orch_avant_ref'] = commit[:12] if commit and commit != '-' else '-'
out['orch_avant_methode'] = methode
blob = ''
if commit and commit != '-':
    try:
        blob = subprocess.run(['git', '-C', root, 'show', '%s:.autoport/orchestrator.py' % commit],
                              capture_output=True, text=True, timeout=60).stdout
    except Exception:
        blob = ''
out['orch_avant_octets'] = len(blob)
lignes = re.findall(r'^\s*if len\(bits\) == 2 and bits\[0\]\.strip\(\)\.isdigit\(\) '
                    r'and int\(bits\[0\]\) (>=|>|<=|<) t0:\s*$', blob, re.M)
out['orch_avant_lignes'] = len(lignes)
if len(lignes) == 1:
    op = lignes[0]
    out['orch_avant_op'] = {'>=': 'ge', '>': 'gt', '<=': 'le', '<': 'lt'}[op]
    # L'OPERATEUR EST EXECUTE, pas lu : c'est lui, et lui seul, qui decidait.
    bits = ['100']
    t0 = 100
    out['orch_avant_egal_accepte'] = int(bool(eval('int(bits[0]) %s t0' % op)))  # noqa: S307
else:
    out['orch_avant_op'] = '-'
    out['orch_avant_egal_accepte'] = -1

for k, v in out.items():
    print('%s=%s' % (k, v))
PY
) || ORCH=""
o(){ printf '%s\n' "$ORCH" | sed -n "s/^$1=//p" | tail -1; }
on(){ local v; v=$(o "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }
[ -n "$ORCH" ] || faute site-python-muet

# ====================================================== LE BALAYAGE, ET LE REGISTRE QUI CLASSE =
# La population n'est pas une impression : c'est un balayage reproductible du harnais VIVANT,
# confronte ligne a ligne au registre. Une occurrence que personne ne couvre est un defaut ; une
# regle que plus aucune occurrence ne rencontre en est un autre.
BAL=$(python3 - "$ROOT" "$REGISTRE" <<'PY' 2>/dev/null
import os, re, sys
root, registre = sys.argv[1], sys.argv[2]
EXCLUS = ('.autoport/reports/', '.autoport/logs/', '.autoport/archive/',
          '.autoport/backups/', '.autoport/scratch/', '.autoport/tmp/')
fichiers = []
for base, dirs, noms in os.walk(os.path.join(root, '.autoport')):
    dirs[:] = [d for d in dirs if d != '__pycache__']
    for nom in noms:
        if not nom.endswith(('.sh', '.py')) or '.bak' in nom:
            continue
        rel = os.path.relpath(os.path.join(base, nom), root)
        if rel.startswith(EXCLUS):
            continue
        fichiers.append(rel)
fichiers.sort()

MOTIF = re.compile(r"""stat -c ['"]?[^ ]*%(\.9)?Y|%T@|getmtime|st_mtime|st_ctime"""
                   r"""|\s-nt\s|\s-ot\s|-newer|fromtimestamp""")

regles = []          # (chemin, motif, classe, raison, touches)
for ligne in open(registre, encoding='utf-8'):
    if ligne.startswith('#') or not ligne.strip():
        continue
    ch, mo, cl, ra = ligne.rstrip('\n').split('\t')
    regles.append([ch, mo, cl, ra, 0])

occurrences = 0
non_classees = []
par_classe = {}
for rel in fichiers:
    try:
        texte = open(os.path.join(root, rel), encoding='utf-8', errors='replace').read()
    except OSError:
        continue
    for no, ligne in enumerate(texte.splitlines(), 1):
        if not MOTIF.search(ligne):
            continue
        occurrences += 1
        vues = [r for r in regles if r[0] == rel and r[1] in ligne]
        if not vues:
            non_classees.append('%s:%d' % (rel, no))
            continue
        for r in vues:
            r[4] += 1
        # UNE occurrence compte pour UNE classe : la plus engageante l'emporte, pour qu'une
        # regle de prose ne puisse jamais blanchir une vraie comparaison qui lui ressemble.
        rang = {'corrige': 0, 'laisse': 1, 'non-fraicheur': 2, 'prose': 3}
        cl = sorted((r[2] for r in vues), key=lambda c: rang.get(c, 9))[0]
        par_classe[cl] = par_classe.get(cl, 0) + 1

mortes = ['%s|%s' % (r[0], r[1]) for r in regles if r[4] == 0]
laisses = ['%s|%s' % (r[0], r[1]) for r in regles if r[2] == 'laisse']

print('bal_scripts=%d' % len(fichiers))
print('bal_occurrences=%d' % occurrences)
print('bal_regles=%d' % len(regles))
print('bal_non_classees=%d' % len(non_classees))
print('bal_non_classees_liste=%s' % (','.join(non_classees) or '-'))
print('bal_regles_mortes=%d' % len(mortes))
print('bal_regles_mortes_liste=%s' % (','.join(mortes) or '-'))
for cl in ('corrige', 'laisse', 'non-fraicheur', 'prose'):
    print('bal_classe_%s=%d' % (cl.replace('-', '_'), par_classe.get(cl, 0)))
print('bal_laisses=%d' % len(laisses))
print('bal_laisses_liste=%s' % (','.join(laisses) or '-'))
PY
) || BAL=""
b(){ printf '%s\n' "$BAL" | sed -n "s/^$1=//p" | tail -1; }
bn(){ local v; v=$(b "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }
[ -n "$BAL" ] || faute balayage-muet

# ====================================================================== LES TERMES DU VERDICT ==

# 1. LA MEME RESOLUTION DES DEUX COTES, RELEVEE A L'EXECUTION (jamais lue dans le texte). Le
#    banc pose des sous-secondes NON NULLES des deux cotes : un `s` en sortie est donc une
#    troncature, pas un hasard. Le site de l'appareil est a part — il est `s` des deux cotes et
#    le restera (toybox n'a pas de sous-seconde) : ce qui compte la, c'est la SYMETRIE.
t_res=0
for couple in "dv_res_art:dv_res_src" "dva_res_art:dva_res_src" "bx_res_art:bx_res_src"; do
  a=$(g "${couple%%:*}"); s=$(g "${couple##*:}")
  [ "$a" = ns ] && [ "$s" = ns ] || t_res=$((t_res+1))
done
[ "$(o orch_res_artefact)" = "$(o orch_res_t0)" ] && [ -n "$(o orch_res_artefact)" ] || t_res=$((t_res+1))

# 2. L'EGALITE NE VAUT PLUS FRAICHEUR. Un terme par site corrige.
t_egal=0
[ "$(g dv_apres_egal)"  = refuse ] || t_egal=$((t_egal+1))
[ "$(g dva_apres_egal)" = refuse ] || t_egal=$((t_egal+1))
[ "$(g bx_egal_verdict)" = douteux ] && [ "$(n bx_egal_rc)" = 4 ] || t_egal=$((t_egal+1))
[ "$(on orch_apres_egal_refuse)" = 1 ] || t_egal=$((t_egal+1))
# ET LES CAS SONT COMPTES, pas seulement refuses. Zero cas rencontre voudrait dire que le banc
# n'a jamais atteint l'egalite : le terme serait vert sans avoir rien mesure.
[ "$(n egalites_rencontrees)" -ge 3 ] 2>/dev/null || faute aucune-egalite-rencontree

# 3. LES DEUX BRAS. APRES doit REFUSER l'etat perime ; AVANT doit l'ACCEPTER (sinon l'ablation
#    est sans objet et « ca refuse » ne prouve aucun defaut) ; et le CONTROLE SAIN doit passer
#    des deux cotes, sinon une porte qui refuse TOUT serait verte.
t_apres=0
[ "$(g dv_apres_perime)"  = refuse ] || t_apres=$((t_apres+1))
[ "$(g dva_apres_perime)" = refuse ] || t_apres=$((t_apres+1))
[ "$(g bx_sain_verdict)"  = frais ]  || faute bx-controle-sain-refuse

t_avant=0
[ "$(g dv_avant_perime)"  = accepte ] || t_avant=$((t_avant+1))
[ "$(g dva_avant_perime)" = accepte ] || t_avant=$((t_avant+1))
[ "$(on orch_avant_egal_accepte)" = 1 ] || t_avant=$((t_avant+1))
[ "$(on orch_avant_lignes)" = 1 ] || faute orch-avant-extraction-ambigue
[ "$(on orch_avant_octets)" -gt 1000 ] 2>/dev/null || faute orch-avant-blob-vide
[ "$(n dv_avant_octets)"  -gt 1000 ] 2>/dev/null || faute dv-avant-blob-vide
[ "$(n dva_avant_octets)" -gt 1000 ] 2>/dev/null || faute dva-avant-blob-vide

t_sain=0
[ "$(g dv_apres_sain)"  = accepte ] || t_sain=$((t_sain+1))
[ "$(g dva_apres_sain)" = accepte ] || t_sain=$((t_sain+1))
[ "$(on orch_apres_futur_frais)"  = 1 ] || t_sain=$((t_sain+1))
[ "$(on orch_apres_passe_refuse)" = 1 ] || t_sain=$((t_sain+1))

# 4. LA POPULATION. Une occurrence que le registre ne couvre pas, ou une regle que plus aucune
#    occurrence ne rencontre : les deux sont des defauts. Le registre ne peut ni oublier ni
#    garder ses morts.
t_pop=$(bn bal_non_classees); [ "$t_pop" -ge 0 ] 2>/dev/null || t_pop=1
t_mortes=$(bn bal_regles_mortes); [ "$t_mortes" -ge 0 ] 2>/dev/null || t_mortes=1
# Le denominateur ne peut pas etre degenere : un balayage qui ne lit rien rend zero partout.
[ "$(bn bal_scripts)" -ge 200 ] 2>/dev/null || faute balayage-trop-court
[ "$(bn bal_occurrences)" -ge 40 ] 2>/dev/null || faute population-degeneree
[ "$(bn bal_classe_corrige)" -ge 6 ] 2>/dev/null || faute sites-corriges-introuvables

TOTAL=$((t_res + t_egal + t_apres + t_avant + t_sain + t_pop + t_mortes + penalty))

# ========================================================================== LA PUBLICATION =====
pub sf_census_ran "$([ -n "$RAW" ] && [ -n "$BAL" ] && [ -n "$ORCH" ] && echo 1 || echo 0)"
pub subsecond_freshness_defects "$TOTAL"
pub sf_defects_terms \
  "resolution$t_res+egalite$t_egal+apres$t_apres+avant$t_avant+sain$t_sain+nonclasse$t_pop+mortes$t_mortes+penalite$penalty${why:+:$why}"
pub sf_resolution_asym   "$t_res"
pub sf_egalite_acceptee  "$t_egal"
pub sf_bras_apres        "$t_apres"
pub sf_bras_avant        "$t_avant"
pub sf_controle_sain     "$t_sain"
pub sf_non_classe        "$t_pop"
pub sf_regles_mortes     "$t_mortes"
pub sf_penalite          "$penalty"

# LA POPULATION, EN CLAIR. Un verdict qui ne publie que son total ne dit pas ce qui a cede.
pub sf_scripts_balayes   "$(b bal_scripts)"
pub sf_occurrences       "$(b bal_occurrences)"
pub sf_sites_corriges    "$(b bal_classe_corrige)"
pub sf_sites_laisses     "$(b bal_laisses)"
pub sf_laisses_liste     "$(b bal_laisses_liste)"
pub sf_non_classees_liste "$(b bal_non_classees_liste)"
pub sf_regles_mortes_liste "$(b bal_regles_mortes_liste)"
pub sf_egalites_rencontrees "$(g egalites_rencontrees)"

# LES GRANDEURS BRUTES, recopiees telles quelles, sous des prefixes a eux : le moissonneur de
# `proof_run.sh` garde la DERNIERE valeur d'une cle, et un brut homonyme d'un terme du verdict
# l'ecraserait en silence.
printf '%s\n' "$RAW"  | sed -n 's/^\([a-z_][a-z0-9_]*\)=/sf_bac_\1=/p'
printf '%s\n' "$ORCH" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/sf_py_\1=/p'
printf '%s\n' "$BAL"  | sed -n 's/^bal_\([a-z0-9_]*\)=/sf_bal_\1=/p'

# LES OCTETS JUGES. Un chemin n'est pas une provenance. `freshness_registry.tsv` n'est pas un
# `.sh` : `lib/verdict_sources.sh` ne l'epingle pas, donc son empreinte est NOMMEE ici — ce qui
# la nomme, sans la garder.
for f in lib/freshness.sh lib/freshness.py lib/freshness_registry.tsv \
         lib/subsecond_freshness_selftest.sh lib/deploy_verify.sh lib/deploy_verify_assets.sh \
         lib/build_x86.sh orchestrator.py lib/census/harness-subsecond-freshness-is-blind.sh; do
  k="sf_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
