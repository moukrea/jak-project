#!/usr/bin/env bash
# census/harness-archive-and-status-write-leftovers.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`) ; sortie `cle=valeur`, aucun champ
# de proof.txt ecrit ici.
#
# CE QU'IL MESURE (via `lib/archive_leftovers_selftest.py`, sur le VRAI code, dans un tempdir) :
#   case_1  course hors groupe (setsid, comme gk) orpheline apres la coupure par archivage
#   case_2  un message du superviseur ressort des archives le ticket d'un item archive
#   case_3  ecritures dans reports/<id>/ apres la sauvegarde + outils laisses partir par pre-tool.sh
#   case_4  travail coupe non nomme dans les notes de l'item
#   case_5  adoption concurrente d'un ticket de l'owner : id en double / ticket adopte deux fois
#   case_6  champ pose en ramenant le statut tenu en memoire (dynamique + appelants statiques)
# `archive_status_leftovers` = somme des six + defauts d'instrument. INCONNU = DEFAUT : un bras vieux
# (code d'avant, ancre par marqueur) qui ne rougit pas, un controle negatif qui bouge, un rc != 0.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "archive_status_leftovers_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

BANC=$(mktemp); trap 'rm -f "$BANC"' EXIT
timeout 900 python3 "$AP/lib/archive_leftovers_selftest.py" > "$BANC" 2>/dev/null
BRC=$?
python3 - "$BRC" "$BANC" <<'PY'
import re, sys
brc = int(sys.argv[1])
kv = {}
for ln in open(sys.argv[2], encoding="utf-8", errors="replace").read().splitlines():
    m = re.match(r"^([A-Za-z0-9_-]+)=(.*)$", ln)
    if m:
        kv[m.group(1)] = m.group(2)

def pub(k, v):
    print("%s=%s" % (k, str(v).replace(" ", "_") or "-"))

def num(k):
    try:
        return int(kv[k])
    except (KeyError, ValueError):
        return None

for k, v in kv.items():
    pub("archive_leftovers_" + k, v)

defects = []
def need(cond, name):
    if not cond:
        defects.append(name)

need(brc == 0, "banc_rc")
rcs = [k for k in kv if k.endswith("_rc")]
need(len(rcs) == 9, "rc_absents")
for k in rcs:
    need(num(k) == 0, k)
total = 0
for n in range(1, 7):
    v = num("c%d_neuf_defect" % n)
    need(v is not None, "case_%d_absent" % n)
    pub("archive_leftovers_case_%d" % n, "-" if v is None else v)
    total += v or 0
    need((num("c%d_vieux_defect" % n) or 0) > 0, "c%d_vieux_ne_rougit_pas" % n)
need(num("c6_static_seed") == 1, "c6_static_seed")
need(num("c1_neuf_foreign_alive") == 1, "c1_ciblage_course_etrangere_tuee")
need(num("c3_neuf_hook_live_refusals") == 0, "c3_crochet_refuse_item_vivant")
need(num("c2_neuf_live_revived") == 1 and num("c2_neuf_live_posted") == 1, "c2_ticket_vivant_non_ressorti")
need(kv.get("c5_neuf_neg_id") == "owner-mon-ticket" and num("c5_neuf_neg_new") == 1, "c5_adoption_simple_alteree")
need(kv.get("temoin_outcome") == "fail" and num("temoin_validator_calls") == 1
     and num("temoin_retries_delta") == 1 and num("temoin_note_cut") == 0, "temoin_essai_sain_altere")
pub("archive_status_leftovers_instrument_defects", len(defects))
pub("archive_status_leftovers_instrument_defects_named", ",".join(defects) or "-")
pub("archive_status_leftovers", total + len(defects))
PY
