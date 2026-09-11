#!/usr/bin/env bash
# census/harness-proof-props-pin.sh — LE VERDICT DE L'ITEM `harness-proof-props-pin`.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course,
# sa sortie `cle=valeur` rejoignant celle du moteur dans le meme journal. Il ne peut ecrire
# aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, ET DANS QUEL ORDRE (les six points du livrable) :
#   1. l'effacement du teardown n'est plus silencieux  -> pin_teardown_silent
#   2. `proof_props` est trace de bout en bout          -> pin_trace_incomplete, pin_props_lost
#   3. la course publie le regime OBSERVE               -> pin_observed_missing
#   4. `machine_proved_to_validated` ecrit, ou n'existe pas -> pin_dead_fn
#   5. le chemin recommande est dit ou un worker le lit -> pin_doc_missing
#   6. un `owner_test: false` n'est jamais parque       -> pin_parked_owner_false
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte. Un bac a sable
# qui n'a pas tourne, un bras d'ablation qui publie autant que le bras neuf, un backlog ou il
# n'y avait rien a liberer : tout cela rend la porte ROUGE. Sans cette polarite, une porte `== 0`
# sur un nettoyage est verte par INACTION.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "pin_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

RAW=$(bash "$AP/lib/pin_props_selftest.sh" 2>/dev/null)
g(){ printf '%s\n' "$RAW" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(g "$1"); case "$v" in ''|*[!0-9]*) echo -1 ;; *) echo "$v" ;; esac; }

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

# ============================================================ le backlog et l'orchestrateur ===
BK=$(python3 - "$ROOT" <<'PY' 2>/dev/null
import os, re, shutil, subprocess, sys, tempfile
root = sys.argv[1]
ap = os.path.join(root, '.autoport')
sys.path.insert(0, os.path.join(ap, 'lib'))
sys.path.insert(0, ap)   # orchestrator.py vit a la racine de .autoport, pas dans lib/
out = {}

def txt(p):
    try:
        return open(p, encoding='utf-8', errors='replace').read()
    except OSError:
        return ''

blib = txt(os.path.join(ap, 'lib', 'backlog.py'))
orch = txt(os.path.join(ap, 'orchestrator.py'))

# 4. LA FONCTION MORTE. Definie ? appelee ? ecrit-elle par set_status ? Les trois separement :
# « supprimee » et « rebranchee » sont deux sorties acceptables, « definie et muette » non.
defined = 'def machine_proved_to_validated' in blib
called = len(re.findall(r'\bmachine_proved_to_validated\s*\(', blib + orch)) - (1 if defined else 0)
body = ''
if defined:
    body = blib.split('def machine_proved_to_validated', 1)[1]
    body = body.split('\n    def ', 1)[0]
out['dead_fn_defined'] = int(defined)
out['dead_fn_callers'] = called
out['dead_fn_writes'] = int('set_status(' in body)
out['dead_fn_mutates_memory'] = int(bool(re.search(r'it\[.status.\]\s*=', body)))
# LE TEMOIN « AVANT » : au commit d'avant ce chantier elle etait definie et sans appelant. Sans
# lui, un zero ne dirait pas si le piege a ete desarme ou s'il n'a jamais existe.
try:
    old = subprocess.run(['git', '-C', root, 'show', 'HEAD:.autoport/lib/backlog.py'],
                         capture_output=True, text=True, timeout=30).stdout
    oldo = subprocess.run(['git', '-C', root, 'show', 'HEAD:.autoport/orchestrator.py'],
                          capture_output=True, text=True, timeout=30).stdout
    od = 'def machine_proved_to_validated' in old
    oc = len(re.findall(r'\bmachine_proved_to_validated\s*\(', old + oldo)) - (1 if od else 0)
    out['dead_fn_before_defined'] = int(od)
    out['dead_fn_before_callers'] = oc
except Exception:
    out['dead_fn_before_defined'] = -1
    out['dead_fn_before_callers'] = -1

# 5. LE CHEMIN RECOMMANDE, la ou un worker le lit : le preambule que l'orchestrateur inline dans
# CHAQUE prompt. On teste le TEXTE REELLEMENT ASSEMBLE, pas la presence d'une ligne source.
try:
    import orchestrator  # noqa: E402
    pre = orchestrator._delegation_preamble('high')
except Exception:
    pre = ''
out['doc_in_prompt'] = int(all(m in pre for m in (
    'proof_props:', 'device_teardown.sh', 'proof_prop_obs_', 'owner_test: false')))
out['doc_in_proof_run'] = int('POSER UN REGLAGE DE COURSE' in txt(os.path.join(ap, 'lib', 'proof_run.sh')))
out['doc_in_teardown'] = int('POUR UN WORKER' in txt(os.path.join(ap, 'lib', 'device_teardown.sh')))

# 6. LES ITEMS PARQUES, et le `owner_test` de chacun.
import backlog as B  # noqa: E402
real = B.load(os.path.join(ap, 'backlog.yaml'))
parked = real.parked_for_owner()
out['parked'] = len(parked)
out['parked_owner_false'] = sum(1 for _i, o in parked if not o)
out['parked_list'] = ','.join('%s:%s' % (i, 'true' if o else 'false') for i, o in parked) or '-'
# LE RATTRAPAGE, JOUE SUR UNE COPIE. On ne touche pas au backlog reel depuis une preuve : c'est
# l'orchestrateur qui l'ecrira, au tour suivant. Ce qu'on mesure ici, c'est que le mecanisme
# LIBERE ce qu'il doit et NE TOUCHE PAS a ce qui attend vraiment l'owner — et qu'il ECRIT sur
# le disque, ce que la version d'avant ne faisait pas.
with tempfile.TemporaryDirectory() as d:
    copy = os.path.join(d, 'backlog.yaml')
    shutil.copyfile(os.path.join(ap, 'backlog.yaml'), copy)
    sb = B.load(copy)
    before_true = {i for i, o in sb.parked_for_owner() if o}
    try:
        freed = sb.machine_proved_to_validated()
    except Exception as e:  # noqa: BLE001
        freed = []
        out['promoter_error'] = type(e).__name__
    reread = B.load(copy)                       # RELU DU DISQUE : la mutation en memoire ne compte pas
    after = reread.parked_for_owner()
    out['promoter_freed'] = len(freed)
    out['promoter_left'] = sum(1 for _i, o in after if not o)
    out['promoter_persisted'] = int(all(
        (reread.get(i) or {}).get('status') == 'validated' for i in freed)) if freed else 0
    out['promoter_touched_owner_true'] = len(before_true - {i for i, o in after if o})
    out['promoter_freed_list'] = ','.join(freed) or '-'

for k, v in out.items():
    print('%s=%s' % (k, v))
PY
) || BK=""
b(){ printf '%s\n' "$BK" | sed -n "s/^$1=//p" | tail -1; }
bn(){ local v; v=$(b "$1"); case "$v" in ''|-[!0-9]*|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ================================================================== les termes du verdict =====
penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }

ran=$(n selftest_ran); arms=$(n selftest_arms_ok)
[ "$ran" = 1 ] || faute bac-a-sable-muet
[ "$arms" = 2 ] || faute bras-manquant

# 1. L'EFFACEMENT N'EST PLUS SILENCIEUX. Le bras neuf doit NOMMER la propriete posee a la main.
t_silent=1
[ "$(n arm_neuf_teardown_ran)" = 1 ] && [ "$(n arm_neuf_host_prop_named)" = 1 ] && t_silent=0
# Le teardown doit CONTINUER d'effacer : publier sans nettoyer serait un autre defaut.
[ "$(n arm_neuf_host_prop_cleared)" = 1 ] || faute teardown-n-efface-plus
# Il doit avoir trouve les DEUX proprietes plantees ; une seule, et la liste n'est pas fiable.
[ "$(n arm_neuf_teardown_props_found)" -ge 2 ] 2>/dev/null || faute teardown-liste-incomplete

# 2. LA TRACE DE BOUT EN BOUT : les trois chiffres, et leur ecart.
t_trace=0
for k in arm_neuf_proof_props_file arm_neuf_proof_props_extracted arm_neuf_proof_props_effective; do
  [ "$(n "$k")" -ge 0 ] 2>/dev/null || t_trace=$((t_trace+1))
done
file=$(n arm_neuf_proof_props_file); eff=$(n arm_neuf_proof_props_effective)
t_lost=$(n arm_neuf_proof_props_lost)
[ "$t_lost" -ge 0 ] 2>/dev/null || t_lost=1
[ "$file" -ge 2 ] 2>/dev/null || faute rien-a-epingler
[ "$eff" = "$file" ] || faute ecart-fichier-appareil

# 3. LE REGIME OBSERVE, relu apres l'amorcage : une cle par propriete, la BONNE valeur.
obs=$(n arm_neuf_proof_props_observed_match)
t_observed=0
if [ "$obs" -ge 0 ] 2>/dev/null && [ "$file" -ge 0 ] 2>/dev/null; then
  t_observed=$((file - obs)); [ "$t_observed" -lt 0 ] && t_observed=0
else
  t_observed=1
fi
# Le moteur a-t-il VRAIMENT lu l'epinglage ? C'est le seul temoin qui ne vient pas du runner.
[ "$(g arm_neuf_sandbox_engine_saw_hdr_out)" = 2 ] || faute moteur-n-a-pas-vu-l-epinglage
# Et la propriete posee A LA MAIN, elle, n'arrive PAS au moteur : c'est le defaut qu'on rend
# visible, pas qu'on repare. S'il s'averait qu'elle arrive, la trace ne servirait a rien.
[ "$(g arm_neuf_sandbox_engine_saw_hostpin)" = "-" ] || faute epinglage-manuel-survit

# LE CONTROLE POSITIF. Le bras vieux doit etre MUET : zero cle de trace, et la propriete posee
# a la main effacee sans etre nommee. Un bras vieux qui publierait rendrait le neuf sans objet.
[ "$(n arm_vieux_proof)" = 1 ] || faute bras-vieux-sans-preuve
[ "$(n arm_vieux_trace_keys)" = 0 ] || faute bras-vieux-pas-muet
[ "$(n arm_vieux_host_prop_named)" = 0 ] || faute bras-vieux-deja-corrige
[ "$(n arm_vieux_host_prop_cleared)" = 1 ] || faute bras-vieux-n-efface-pas
[ "$(n arm_neuf_trace_keys)" -ge 10 ] 2>/dev/null || faute trace-trop-maigre

# 4. LA FONCTION MORTE : supprimee, ou rebranchee ET ecrivante. Definie-sans-appelant = piege.
t_dead=1
if [ "$(bn dead_fn_defined)" = 0 ]; then
  t_dead=0
elif [ "$(bn dead_fn_callers)" -ge 1 ] 2>/dev/null && [ "$(bn dead_fn_writes)" = 1 ] \
     && [ "$(bn dead_fn_mutates_memory)" = 0 ]; then
  t_dead=0
fi
[ "$(bn dead_fn_before_defined)" = 1 ] && [ "$(bn dead_fn_before_callers)" = 0 ] \
  || faute temoin-avant-absent

# 5. LE CHEMIN RECOMMANDE, dit la ou un worker lit.
t_doc=0
[ "$(bn doc_in_prompt)" = 1 ] || t_doc=$((t_doc+1))
[ "$(bn doc_in_proof_run)" = 1 ] || t_doc=$((t_doc+1))

# 6. AUCUN `owner_test: false` PARQUE. La grandeur est ce que le mecanisme LAISSE derriere lui
# sur une copie du backlog reel, pas l'etat du fichier a la seconde ou cette preuve tourne :
# c'est l'orchestrateur qui ecrira, au tour suivant, et lui seul.
t_parked=$(bn promoter_left); [ "$t_parked" -ge 0 ] 2>/dev/null || t_parked=1
[ "$(bn parked_owner_false)" -ge 1 ] 2>/dev/null || faute rien-a-liberer
[ "$(bn promoter_persisted)" = 1 ] || faute promotion-non-ecrite
[ "$(bn promoter_touched_owner_true)" = 0 ] || faute promotion-trop-large

TOTAL=$((t_silent + t_trace + t_lost + t_observed + t_dead + t_doc + t_parked + penalty))

# ======================================================================== la publication ======
pub pin_census_ran "$([ -n "$RAW" ] && [ -n "$BK" ] && echo 1 || echo 0)"
pub pin_props_defects "$TOTAL"
pub pin_props_defects_terms \
  "silence$t_silent+trace$t_trace+perdu$t_lost+observe$t_observed+morte$t_dead+doc$t_doc+parque$t_parked+penalite$penalty${why:+:$why}"
pub pin_teardown_silent "$t_silent"
pub pin_trace_incomplete "$t_trace"
pub pin_props_lost "$t_lost"
pub pin_observed_missing "$t_observed"
pub pin_dead_fn "$t_dead"
pub pin_doc_missing "$t_doc"
pub pin_parked_owner_false "$t_parked"
pub pin_witness_penalty "$penalty"

# LES GRANDEURS BRUTES, recopiees telles quelles : c'est ce qui rend la somme lisible et
# falsifiable. Une porte qui ne publie que son total ne dit pas ce qui a cede.
# ATTENTION AU DERNIER MOT. Le moissonneur de proof_run.sh garde la DERNIERE valeur publiee
# pour une cle : un relai brut homonyme d'un terme du verdict (`parked_owner_false`) ecraserait
# le terme, et la porte lirait le compte du backlog a la place du verdict du mecanisme. Les
# bruts vivent donc sous un prefixe a eux, `pin_st_` (bac a sable) et `pin_bk_` (backlog).
printf '%s\n' "$RAW" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/pin_st_\1=/p'
printf '%s\n' "$BK"  | sed -n 's/^\([a-z_][a-z0-9_]*\)=/pin_bk_\1=/p'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in lib/proof_run.sh lib/device_teardown.sh lib/backlog.py orchestrator.py \
         lib/pin_props_selftest.sh lib/census/harness-proof-props-pin.sh; do
  k="pin_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
