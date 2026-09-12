#!/usr/bin/env bash
# census/harness-aborted-attempt-not-counted.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course,
# sa sortie `cle=valeur` rejoignant celle du moteur dans le meme journal. Il n'ecrit aucun champ
# de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, ET DANS QUEL ORDRE (les quatre points du livrable) :
#   1. l'essai tue par le lanceur est RECONNU        -> abt_recognition
#   2. il n'incremente PAS le budget d'essais        -> abt_counted
#   3. il ne passe PAS au validateur                 -> abt_validated
#   4. le journal le DIT, duree ET borne en vigueur  -> abt_journal
#
# DEUX SOURCES, jamais une seule :
#   - LE BANC (`lib/aborted_attempt_selftest.py`) : le VRAI `run_attempt` sur un etat jetable,
#     quatre bras — l'ancien code, le neuf, un flux sans abandon, et la borne d'abandons
#     d'affilee. C'est lui qui porte la preuve a deux bras du point 2.
#   - LES JOURNAUX REELS : la meme fonction de reconnaissance passee sur tous les
#     `logs/*/attempt-*.jsonl` du depot. Les quatre essais detruits du 12/09 doivent sortir,
#     et les journaux qui ne font que CITER la ligne (la consigne de cet item, le rapport de
#     gl-uniforms-dead-seven) ne doivent PAS sortir : c'est le piege du compteur 529, ou la
#     presence du litteral dans nos propres sources armait la detection.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte. Sans cette
# polarite, une porte `== 0` sur un nettoyage serait verte par INACTION.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "abt_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

# ===================================================================== le banc a 4 bras =====
ST=$(timeout 900 python3 "$AP/lib/aborted_attempt_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$ST" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ================================================================== les journaux reels ======
HI=$(python3 - "$ROOT" <<'PY' 2>/dev/null
import json, os, sys
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, '.autoport'))
from pathlib import Path
import orchestrator as O                                   # noqa: E402

logs = sorted(Path(root, '.autoport/logs').glob('*/attempt-*.jsonl'))
reconnus, cites, faux = [], [], []
for p in logs:
    bare = quoted = 0
    try:
        with p.open(errors='replace') as fh:
            for raw in fh:
                line = raw.rstrip('\n')
                if 'Background tasks still running' not in line:
                    continue
                try:
                    json.loads(line)
                    quoted += 1
                except ValueError:
                    bare += 1
    except OSError:
        continue
    vu = O.launcher_abort_from_log(p)
    name = p.parent.name + '/' + p.stem
    if bare:
        if vu is None:
            faux.append('RATE:' + name)                    # ligne nue non reconnue
        else:
            reconnus.append(name)
    elif quoted:
        cites.append(name)
        if vu is not None:
            faux.append('CITE:' + name)                    # citation prise pour un abandon
print('logs_lus=%d' % len(logs))
print('recognized=%d' % len(reconnus))
print('recognized_list=%s' % (','.join(sorted(reconnus)) or '-'))
print('quote_only=%d' % len(cites))
print('quote_only_list=%s' % (','.join(sorted(cites)) or '-'))
print('mismatch=%d' % len(faux))
print('mismatch_list=%s' % (','.join(sorted(faux)) or '-'))
# La borne en vigueur, telle que le module la calcule, et le garde-fou d'affilee.
print('ceiling_ms=%s' % O.BG_WAIT_CEILING_MS)
print('max_in_a_row=%s' % O.MAX_ABORTED_IN_A_ROW)
print('state_key=%d' % int('aborted' in O.STATE_KEYS))
PY
) || HI=""
h(){ printf '%s\n' "$HI" | sed -n "s/^$1=//p" | tail -1; }
hn(){ local v; v=$(h "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ==================================================================== les termes du verdict ==
penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
add(){ local v=$1; [ "$v" -ge 0 ] 2>/dev/null || v=1; echo "$v"; }

for arm in vieux neuf temoin borne; do
  [ "$(n "${arm}_ran")" = 1 ] || faute "bras-$arm-muet"
done
[ "$(s before_commit)" = "-" ] && faute temoin-avant-absent
[ "$(n before_marker_absent)" = 1 ] || faute temoin-avant-porte-le-marqueur

# --- 1. RECONNU. Le banc ET les journaux reels, separement.
t_reco=0
[ "$(s neuf_outcome)" = "aborted" ] || t_reco=$((t_reco+1))
[ "$(n neuf_log_abort_event)" = 1 ] || t_reco=$((t_reco+1))
[ "$(n neuf_log_waited_s)" = 600 ] || t_reco=$((t_reco+1))
[ "$(n neuf_end_launcher_abort_s)" = 600 ] || t_reco=$((t_reco+1))
[ "$(hn recognized)" -ge 4 ] 2>/dev/null || t_reco=$((t_reco+1))
t_reco=$((t_reco + $(add "$(hn mismatch)")))
# La population des CITATIONS doit exister, sinon le temoin anti-auto-detection est vide.
[ "$(hn quote_only)" -ge 2 ] 2>/dev/null || faute citations-insuffisantes
[ "$(hn logs_lus)" -ge 50 ] 2>/dev/null || faute population-de-journaux-trop-maigre

# --- 2. PAS COMPTE. Le bras d'AVANT compte, le bras d'APRES ne compte pas, MEME entree.
t_counted=0
t_counted=$((t_counted + $(add "$(n neuf_retries_delta)")))
t_counted=$((t_counted + $(add "$(n neuf_fingerprints_delta)")))
[ "$(n vieux_retries_delta)" = 1 ] || t_counted=$((t_counted+1))
[ "$(n vieux_fingerprints_delta)" = 1 ] || t_counted=$((t_counted+1))
[ "$(n temoin_retries_delta)" = 1 ] || t_counted=$((t_counted+1))
# Non compte ne veut pas dire perdu : le travail de l'essai doit etre commite.
[ "$(n neuf_checkpoints)" -ge 1 ] 2>/dev/null || faute travail-non-sauve
# L'abandon est COMPTE ailleurs : un essai qui disparait sans trace est le defaut d'origine.
[ "$(n neuf_aborted_total)" = 1 ] || faute abandon-non-comptabilise
[ "$(hn state_key)" = 1 ] || faute compteur-non-persiste

# --- 3. PAS DE VALIDATEUR. Le compte de validations EVITEES est la difference des deux bras.
t_valid=0
t_valid=$((t_valid + $(add "$(n neuf_validator_calls)")))
[ "$(n vieux_validator_calls)" = 1 ] || t_valid=$((t_valid+1))
[ "$(n temoin_validator_calls)" = 1 ] || t_valid=$((t_valid+1))

# --- 4. LE JOURNAL LE DIT : la duree atteinte ET la borne en vigueur, en toutes lettres.
t_journal=0
for k in neuf_journal_duration neuf_journal_ceiling neuf_journal_not_counted \
         neuf_journal_no_validator; do
  [ "$(n "$k")" = 1 ] || t_journal=$((t_journal+1))
done
# Le journal du bras d'AVANT doit etre MUET : sinon le neuf ne dit rien de plus.
[ "$(n vieux_journal_duration)" = 0 ] || faute bras-vieux-deja-corrige
[ "$(n vieux_journal_ceiling)" = 0 ] || faute bras-vieux-deja-corrige
[ "$(n temoin_journal_duration)" = 0 ] || faute temoin-annonce-un-abandon

# --- LE GARDE-FOU. Trois abandons d'affilee ne content rien, le quatrieme est COMPTE.
[ "$(s borne_kinds)" = "aborted,aborted,aborted,fail,aborted" ] || faute borne-non-eprouvee
[ "$(n borne_validator_calls)" = 1 ] || faute borne-validateur
[ "$(n borne_retries_delta)" = 1 ] || faute borne-budget
[ "$(hn max_in_a_row)" -ge 1 ] 2>/dev/null || faute borne-absente

TOTAL=$((t_reco + t_counted + t_valid + t_journal + penalty))

# ========================================================================= la publication ====
pub abt_census_ran "$([ -n "$ST" ] && [ -n "$HI" ] && echo 1 || echo 0)"
pub aborted_attempt_defects "$TOTAL"
pub aborted_attempt_defects_terms \
  "reconnu$t_reco+compte$t_counted+valide$t_valid+journal$t_journal+penalite$penalty${why:+:$why}"
pub abt_recognition "$t_reco"
pub abt_counted "$t_counted"
pub abt_validated "$t_valid"
pub abt_journal "$t_journal"
pub abt_witness_penalty "$penalty"

# LES GRANDEURS QUE LE LIVRABLE DEMANDE DE PUBLIER, nommees comme il les nomme.
pub abt_aborted_recognized "$(hn recognized)"          # essais abortes reconnus, journaux reels
pub abt_validations_avoided "$(( $(n vieux_validator_calls) - $(n neuf_validator_calls) ))"
pub abt_ceiling_ms "$(h ceiling_ms)"
pub abt_max_in_a_row "$(h max_in_a_row)"

# LES BRUTS, recopies tels quels : c'est ce qui rend la somme lisible et falsifiable. Sous un
# prefixe a eux — le moissonneur garde la DERNIERE valeur d'une cle, et un homonyme ecraserait
# un terme du verdict.
printf '%s\n' "$ST" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/abt_st_\1=/p'
printf '%s\n' "$HI" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/abt_hist_\1=/p'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in orchestrator.py lib/aborted_attempt_selftest.py \
         lib/census/harness-aborted-attempt-not-counted.sh; do
  k="abt_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
