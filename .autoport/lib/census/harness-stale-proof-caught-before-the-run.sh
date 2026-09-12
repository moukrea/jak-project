#!/usr/bin/env bash
# census/harness-stale-proof-caught-before-the-run.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il ne peut ecrire aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, ni les
# `proof_census_*` qui disent qu'il a tourne — ils sortent de la machine.
#
# CE QU'IL MESURE, DANS L'ORDRE DES QUATRE POINTS DU LIVRABLE :
#   1. LE COUT D'AVANT EST CHIFFRE      -> les refus archives pour ce motif, par item, LIGNES et
#                                          ESSAIS separes, sur une population de verdicts nommee.
#   2. LA LECTURE A LIEU AU DEMARRAGE   -> le releve que `lib/stale_precheck.sh` a laisse AVANT
#                                          la mesure de CETTE course : fichiers compares, code
#                                          rendu, et l'ordre prouve contre un autre fichier de
#                                          la machine.
#   3. LE TEMOIN A DEUX BRAS            -> `lib/stale_precheck_selftest.sh` : un arbre sale que la
#                                          detection doit voir, un arbre intact qu'elle doit
#                                          laisser passer, et le VRAI juge derriere chacun.
#   4. LE MOTIF DISPARAIT DES REFUS TARDIFS -> les verdicts posterieurs a la livraison, avec le
#                                          nombre de courses observees a cote.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte. Sans cette
# polarite, une porte `== 0` sur une suppression est verte par INACTION : il suffirait que rien
# ne tourne. Un zero sur zero course n'est pas une reussite, c'est un instrument eteint.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "stale_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }
penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
num(){ case "${1:-}" in ''|*[!0-9-]*) echo -1 ;; *) echo "$1" ;; esac; }

# ============================================ 1 + 4. LES VERDICTS ARCHIVES, ET CE QUI SUIT =====
# `logs/` est GITIGNORE : hors de l'arbre livre, ce balayage ne lit RIEN et publierait zero. On
# dit donc OU il a lu, on recompte le gel ligne a ligne, et on publie l'ecart.
LOGS=$(python3 - "$ROOT" <<'PY' 2>/dev/null
import glob, hashlib, os, subprocess, sys
root = sys.argv[1]
ap = os.path.join(root, '.autoport')
MOTIFS = ("source moteur editee APRES la preuve", "source du VERDICT editee APRES la preuve")

def lignes_motif(txt):
    return sum(txt.count(m) for m in MOTIFS)

# ---- le gel, et sa verification octet a octet -------------------------------------------------
gel = os.path.join(ap, 'lib', 'census', 'stale-proof-baseline.tsv')
fige = []
scannes_gel = -1
if os.path.exists(gel):
    for ligne in open(gel, encoding='utf-8'):
        if ligne.startswith('#TOTAL'):
            try:
                scannes_gel = int(ligne.rstrip('\n').split('\t')[2])
            except (IndexError, ValueError):
                scannes_gel = -1
            continue
        if ligne.startswith('#') or not ligne.strip():
            continue
        c = ligne.rstrip('\n').split('\t')
        if len(c) == 4:
            fige.append((c[0], c[1], int(c[2]), c[3]))
verifies = manquants = divergents = 0
for item, nom, n, sha in fige:
    chemin = os.path.join(ap, 'logs', item, nom)
    if not os.path.exists(chemin):
        manquants += 1
        continue
    txt = open(chemin, encoding='utf-8', errors='replace').read()
    if hashlib.sha256(txt.encode('utf-8', 'replace')).hexdigest()[:16] == sha:
        verifies += 1
    else:
        divergents += 1
par_item = {}
for item, _nom, n, _sha in fige:
    par_item[item] = par_item.get(item, 0) + n
print('stale_before_cost_lines=%d' % sum(n for _i, _n, n, _s in fige))
print('stale_before_cost_attempts=%d' % len(fige))
print('stale_before_cost_items=%d' % len(par_item))
print('stale_before_cost_by_item=%s' % (','.join('%s:%d' % kv for kv in sorted(par_item.items())) or '-'))
print('stale_before_cost_verdicts_scanned=%d' % scannes_gel)
print('stale_before_cost_frozen_verified=%d' % verifies)
print('stale_before_cost_frozen_missing=%d' % manquants)
print('stale_before_cost_frozen_divergent=%d' % divergents)

# ---- le recompte VIVANT, quand les journaux sont la ------------------------------------------
vus = sorted(glob.glob(os.path.join(ap, 'logs', '*', 'validator-*.txt')))
print('stale_logs_present=%d' % len(vus))
live_l = live_a = 0
for f in vus:
    n = lignes_motif(open(f, encoding='utf-8', errors='replace').read())
    if n:
        live_l += n
        live_a += 1
print('stale_before_cost_live_lines=%d' % (live_l if vus else -1))
print('stale_before_cost_live_attempts=%d' % (live_a if vus else -1))

# ---- 4. CE QUI SUIT LA LIVRAISON --------------------------------------------------------------
# L'instant de livraison est celui du COMMIT qui ajoute la detection : une empreinte de contenu,
# pas un chemin. A defaut de commit (la detection n'est pas encore versionnee), on le dit et on
# retombe sur le mtime du fichier — jamais en silence.
det = '.autoport/lib/stale_precheck.sh'
src = 'commit'
epoch = -1
r = subprocess.run(['git', '-C', root, 'log', '--diff-filter=A', '--format=%ct %H', '--', det],
                   capture_output=True, text=True)
lignes = [l for l in (r.stdout or '').splitlines() if l.strip()]
commit = '-'
if lignes:
    champs = lignes[-1].split()
    epoch = int(champs[0]); commit = champs[1][:12]
else:
    src = 'mtime'
    p = os.path.join(root, det)
    if os.path.exists(p):
        epoch = int(os.path.getmtime(p))
print('stale_landing_source=%s' % src)
print('stale_landing_commit=%s' % commit)
print('stale_landing_epoch=%d' % epoch)

# LES DEUX COTES EN SECONDES ENTIERES, et l'EGALITE COMPTEE COMME APRES : le sens de l'erreur est
# choisi CONTRE nous. Un verdict tombe dans la meme seconde que la livraison entre dans le compte
# des refus tardifs ; il ne peut donc pas verdir cette porte par arrondi.
apres = tardifs = 0
liste = []
if epoch >= 0:
    for f in vus:
        if int(os.path.getmtime(f)) < epoch:
            continue
        apres += 1
        n = lignes_motif(open(f, encoding='utf-8', errors='replace').read())
        if n:
            tardifs += n
            liste.append('%s/%s:%d' % (f.split(os.sep)[-2], os.path.basename(f), n))
print('stale_verdicts_after_landing=%d' % apres)
print('stale_late_refusals_after_landing=%d' % tardifs)
print('stale_late_refusals_list=%s' % (','.join(liste) or '-'))

# LE DENOMINATEUR DES REFUS TARDIFS : les courses REELLEMENT passees par la lecture anticipee.
# Le registre est ecrit par `lib/proof_run.sh`, une ligne par course, jamais par ce recensement.
reg = os.path.join(ap, 'logs', 'stale-precheck.tsv')
courses = 0
items = set()
vues_perimees = 0
if os.path.exists(reg):
    for ligne in open(reg, encoding='utf-8', errors='replace'):
        c = ligne.rstrip('\n').split('\t')
        if len(c) < 7:
            continue
        try:
            ts = int(c[0])
        except ValueError:
            continue
        if epoch >= 0 and ts < epoch:
            continue
        courses += 1
        items.add(c[1])
        if c[3] != '0':
            vues_perimees += 1
print('stale_runs_observed_after_landing=%d' % courses)
print('stale_runs_observed_items=%d' % len(items))
print('stale_runs_seen_stale=%d' % vues_perimees)
print('stale_ledger_present=%d' % int(os.path.exists(reg)))
PY
) || LOGS=""
g(){ printf '%s\n' "$LOGS" | sed -n "s/^$1=//p" | tail -1; }
gn(){ num "$(g "$1")"; }
[ -n "$LOGS" ] || faute balayage-des-journaux-muet

# ================================ 2. LE RELEVE LAISSE AVANT LA MESURE DE CETTE COURSE ==========
# Le nom du fichier vient de l'AUTORITE DE NOMMAGE, par bras : un lecteur qui code `proof` +
# extension en dur lit le bras livre pendant que l'ablation ecrit ailleurs, et l'ablation reste
# invisible sous une porte verte.
REL=$(python3 - "$ROOT" <<'PY' 2>/dev/null
import os, sys
from pathlib import Path
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, '.autoport', 'lib'))
import impossible as _I
suf = _I.arm_suffix(os.environ.get('AUTOPORT_CENSUS_ARMED', '1'))
cdir = os.environ.get('AUTOPORT_CENSUS_DIR', '')
nom = _I.arm_name('stale', suf)
print('rel_name_read=%s' % nom)
print('rel_arm_read=%s' % (suf or 'livre'))
vals = {}
if cdir and Path(cdir, nom).exists():
    for l in Path(cdir, nom).read_text(errors='replace').splitlines():
        if '=' in l:
            k, v = l.split('=', 1)
            vals[k] = v
print('rel_present=%d' % int(bool(vals)))
for k in ('stale_precheck_ran', 'stale_precheck_item', 'stale_precheck_arm',
          'stale_precheck_ref', 'stale_precheck_ref_present',
          'stale_precheck_verdict_compared', 'stale_precheck_engine_compared',
          'stale_precheck_files_compared', 'stale_precheck_verdict_newer',
          'stale_precheck_engine_newer', 'stale_precheck_stale_total',
          'stale_precheck_rc', 'stale_precheck_exit', 'stale_precheck_at',
          'stale_precheck_code_stale', 'stale_precheck_code_measure_fail',
          'stale_precheck_codes_distinct'):
    print('rel_%s=%s' % (k[15:] if k.startswith('stale_precheck_') else k, vals.get(k, '-') or '-'))
# L'ORDRE EST PROUVE CONTRE UN AUTRE FICHIER DE LA MACHINE, pas contre une affirmation : le
# fichier d'attente est ecrit APRES la lecture anticipee et AVANT la mesure. Deux horodatages
# ISO ecrits par le meme processus, compares comme du texte — meme forme, meme fuseau.
att = {}
if cdir:
    f = Path(cdir, _I.arm_name('wait', suf))
    if f.exists():
        for l in f.read_text(errors='replace').splitlines():
            if '=' in l:
                k, v = l.split('=', 1)
                att[k] = v
t_lu = vals.get('stale_precheck_at', '')
t_att = att.get('proof_wait_at', '')
print('rel_wait_at=%s' % (t_att or '-'))
print('rel_ordre_mesurable=%d' % int(bool(t_lu) and bool(t_att)))
print('rel_lu_avant_attente=%d' % int(bool(t_lu) and bool(t_att) and t_lu <= t_att))
PY
) || REL=""
r(){ printf '%s\n' "$REL" | sed -n "s/^$1=//p" | tail -1; }
rn(){ num "$(r "$1")"; }
[ -n "$REL" ] || faute releve-illisible

# ====================================== 3. LE TEMOIN A DEUX BRAS, DANS UN BAC A SABLE ==========
RAW=$(timeout -k 30 600 bash "$AP/lib/stale_precheck_selftest.sh" 2>/dev/null)
s(){ printf '%s\n' "$RAW" | sed -n "s/^$1=//p" | tail -1; }
sn(){ num "$(s "$1")"; }
[ "$(sn spq_selftest_ran)" = 1 ] || faute bac-a-sable-muet

# =============================================================== LES QUATRE TERMES ============
# 1. LE COUT D'AVANT. Un zero ici rendrait tout le reste vide : on ne corrige pas un defaut qui
#    n'a jamais coute. Le gel doit etre ancre a au moins un verdict ENCORE identique sur le
#    disque, sinon il ne vaut pas plus qu'une affirmation.
t_cout=0
[ "$(gn stale_before_cost_lines)"    -gt 0 ] 2>/dev/null || t_cout=$((t_cout+1))
[ "$(gn stale_before_cost_attempts)" -gt 0 ] 2>/dev/null || t_cout=$((t_cout+1))
[ "$(gn stale_before_cost_items)"    -gt 0 ] 2>/dev/null || t_cout=$((t_cout+1))
[ "$(gn stale_before_cost_verdicts_scanned)" -gt 0 ] 2>/dev/null || t_cout=$((t_cout+1))
[ "$(gn stale_before_cost_frozen_verified)"  -gt 0 ] 2>/dev/null || t_cout=$((t_cout+1))

# 2. LA LECTURE A EU LIEU AU DEMARRAGE DE CETTE COURSE. Le releve existe, il a compare des
#    fichiers — non nul — le code rendu est l'un des deux codes nommes, les deux voix (la cle du
#    script et le code pris par le processus) concordent, et l'ordre est prouve.
t_lecture=0
[ "$(rn rel_present)" = 1 ] || t_lecture=$((t_lecture+1))
[ "$(rn rel_ran)" = 1 ] || t_lecture=$((t_lecture+1))
[ "$(rn rel_files_compared)" -gt 0 ] 2>/dev/null || t_lecture=$((t_lecture+1))
[ "$(rn rel_verdict_compared)" -gt 0 ] 2>/dev/null || t_lecture=$((t_lecture+1))
[ "$(rn rel_engine_compared)" -gt 0 ] 2>/dev/null || t_lecture=$((t_lecture+1))
case "$(r rel_rc)" in 0|5) ;; *) t_lecture=$((t_lecture+1)) ;; esac
[ "$(r rel_rc)" = "$(r rel_exit)" ] || t_lecture=$((t_lecture+1))
[ "$(rn rel_codes_distinct)" = 1 ] || t_lecture=$((t_lecture+1))
[ "$(r rel_code_stale)" = 5 ] || t_lecture=$((t_lecture+1))
[ "$(r rel_code_measure_fail)" = 3 ] || t_lecture=$((t_lecture+1))
[ "$(rn rel_ordre_mesurable)" = 1 ] || t_lecture=$((t_lecture+1))
[ "$(rn rel_lu_avant_attente)" = 1 ] || t_lecture=$((t_lecture+1))
[ "$(r rel_item)" = "harness-stale-proof-caught-before-the-run" ] || t_lecture=$((t_lecture+1))

# 3. LES DEUX BRAS. Un seul bras prouve la moitie : le bras sale montre qu'elle VOIT, le bras
#    propre qu'elle ne CRIE PAS. Et le VRAI juge derriere chacun : une detection qui ne verrait
#    pas ce que le juge voit deplacerait un autre constat, pas celui-la.
t_temoin=0
[ "$(sn spq_propre_monte)" = 1 ] || t_temoin=$((t_temoin+1))
[ "$(sn spq_perime_monte)" = 1 ] || t_temoin=$((t_temoin+1))
# bras propre : rien vu, juge vert, aucun des deux motifs
[ "$(sn spq_propre_detection_rc)" = 0 ] || t_temoin=$((t_temoin+1))
[ "$(sn spq_propre_verdict_neufs)" = 0 ] || t_temoin=$((t_temoin+1))
[ "$(sn spq_propre_moteur_neufs)" = 0 ] || t_temoin=$((t_temoin+1))
[ "$(sn spq_propre_compares)" -gt 0 ] 2>/dev/null || t_temoin=$((t_temoin+1))
[ "$(sn spq_propre_juge_rc)" = 0 ] || t_temoin=$((t_temoin+1))
[ "$(sn spq_propre_juge_motif_verdict)" = 0 ] || t_temoin=$((t_temoin+1))
[ "$(sn spq_propre_juge_motif_moteur)" = 0 ] || t_temoin=$((t_temoin+1))
# bras perime : le code 5, les deux semis vus et NOMMES, et le juge qui rend les deux motifs
[ "$(sn spq_perime_detection_rc)" = 5 ] || t_temoin=$((t_temoin+1))
[ "$(sn spq_perime_verdict_neufs)" -ge 1 ] 2>/dev/null || t_temoin=$((t_temoin+1))
[ "$(sn spq_perime_moteur_neufs)"  -ge 1 ] 2>/dev/null || t_temoin=$((t_temoin+1))
[ "$(sn spq_perime_victime_nommee)" = 1 ] || t_temoin=$((t_temoin+1))
[ "$(sn spq_perime_moteur_nomme)" = 1 ] || t_temoin=$((t_temoin+1))
# le semis 1 est un `touch` NU : si son empreinte avait bouge, le bras ne prouverait plus que la
# FRAICHEUR voit ce que l'empreinte ne voit pas.
[ "$(sn spq_perime_victime_sha_stable)" = 1 ] || t_temoin=$((t_temoin+1))
[ "$(sn spq_perime_juge_rc)" != 0 ] || t_temoin=$((t_temoin+1))
[ "$(sn spq_perime_juge_motif_verdict)" = 1 ] || t_temoin=$((t_temoin+1))
[ "$(sn spq_perime_juge_motif_moteur)" = 1 ] || t_temoin=$((t_temoin+1))

# 4. LE MOTIF DANS LES REFUS TARDIFS. Le compte des refus, PLUS le defaut d'une population vide :
#    un zero sur zero course observee n'est pas une reussite.
t_tardif=$(gn stale_late_refusals_after_landing)
[ "$t_tardif" -ge 0 ] 2>/dev/null || t_tardif=1
[ "$(gn stale_runs_observed_after_landing)" -gt 0 ] 2>/dev/null || t_tardif=$((t_tardif+1))
[ "$(gn stale_landing_epoch)" -gt 0 ] 2>/dev/null || t_tardif=$((t_tardif+1))

TOTAL=$((t_cout + t_lecture + t_temoin + t_tardif + penalty))

# ============================================================================ LA PUBLICATION ===
pub stale_census_ran "$([ -n "$LOGS" ] && [ -n "$REL" ] && [ -n "$RAW" ] && echo 1 || echo 0)"
pub stale_proof_late_catches "$TOTAL"
pub stale_defects_terms \
  "cout$t_cout+lecture$t_lecture+temoin$t_temoin+tardif$t_tardif+penalite$penalty${why:+:$why}"
pub stale_term_cost_unmeasured "$t_cout"
pub stale_term_precheck_absent "$t_lecture"
pub stale_term_witness_incomplete "$t_temoin"
pub stale_term_late_refusals "$t_tardif"
pub stale_penalite "$penalty"

# LES GRANDEURS, EN CLAIR. Un verdict qui ne publie que son total ne dit pas ce qui a cede.
printf '%s\n' "$LOGS" | sed -n 's/^\(stale_[a-z0-9_]*\)=/\1=/p'
printf '%s\n' "$REL"  | sed -n 's/^rel_\([a-z0-9_]*\)=/stale_run_\1=/p'
printf '%s\n' "$RAW"  | sed -n 's/^spq_\([a-z0-9_]*\)=/stale_bac_\1=/p'

# OU LE COMPTE A ETE MESURE. `logs/` est gitignore : le meme recensement rend un autre chiffre
# dans un autre arbre, et il doit le DIRE au lieu de le laisser deviner.
pub stale_logs_root "$AP/logs"
pub stale_tree_root "$ROOT"
pub stale_tree_head "$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null)"

# LES OCTETS JUGES. Un chemin n'est pas une provenance ; le gel n'est pas un `.sh`, donc
# `lib/verdict_sources.sh` ne l'epingle pas : son empreinte est NOMMEE ici.
for f in lib/stale_precheck.sh lib/stale_precheck_selftest.sh \
         lib/census/stale-proof-baseline.tsv \
         lib/census/harness-stale-proof-caught-before-the-run.sh; do
  k="stale_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
