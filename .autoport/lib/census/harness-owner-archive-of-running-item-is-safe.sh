#!/usr/bin/env bash
# census/harness-owner-archive-of-running-item-is-safe.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`) apres la course ; sortie `cle=valeur`,
# aucun champ de proof.txt ecrit ici.
#
# CE QU'IL MESURE : l'owner archive un chantier pendant qu'un essai tourne dessus (la VRAIE
# `linear_sync.apply_owner_archive`, sur le VRAI `run_attempt`, via `lib/owner_archive_selftest.py`).
# `archived_item_attempt_side_effects` = ecritures au nom de l'item APRES l'archivage (commit sous son
# nom, validateur, juge, essai compte, empreinte, handoff, statut defait), sommees sur les trois
# moments d'archivage fabriques (pendant le worker, pendant le validateur, pendant la porte), PLUS les
# gardes des ecrivains du worker (commentaire Linear, commit) qui laisseraient passer, PLUS chaque
# temoin muet ou degenere (INCONNU = DEFAUT : sans cette polarite, un `== 0` serait vert par inaction).
#
# LES TEMOINS : `vieux` (code d'avant, ancre par marqueur) doit ROUGIR ; `seme` (detection
# neutralisee) doit ROUGIR et nommer ses effets ; `temoin` (aucun archivage) doit etre juge, compte
# et rouvert comme avant ; un item VIVANT et le superviseur ne sont jamais refuses.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "archived_item_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

BANC=$(mktemp); trap 'rm -f "$BANC"' EXIT
timeout 800 python3 "$AP/lib/owner_archive_selftest.py" > "$BANC" 2>/dev/null
BRC=$?
python3 - "$BRC" "$AP/backlog.yaml" "$BANC" <<'PY'
import re, sys
brc = int(sys.argv[1])
kv = {}
for ln in open(sys.argv[3], encoding="utf-8", errors="replace").read().splitlines():
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

defects = []            # temoins muets ou degeneres : chacun AJOUTE 1
def need(cond, name):
    if not cond:
        defects.append(name)

need(brc == 0, "banc_rc")
CUT_ARMS = ("neuf", "juge", "porte")
side = 0
for arm in ("vieux",) + CUT_ARMS + ("temoin", "seme"):
    need(num(arm + "_rc") == 0, arm + "_rc")
    for k in ("outcome", "side_effects", "side_effects_named", "archived", "final_status",
              "validator_calls", "retries_delta", "saved_work", "elapsed_s", "main_write_rc"):
        pub("archived_item_%s_%s" % (arm, k), kv.get("%s_%s" % (arm, k), "-"))
for arm in CUT_ARMS:
    n = num(arm + "_side_effects")
    need(n is not None, arm + "_side_effects_absent")
    need(num(arm + "_archived") == 1, arm + "_archivage_non_fabrique")
    need(kv.get(arm + "_outcome") == "archived", arm + "_issue_non_archived")
    need(num(arm + "_saved_work") == 1, arm + "_travail_non_sauve")
    side += n or 0
# le worker est COUPE, pas attendu (il dort 6 s apres l'archivage)
try:
    need(float(kv.get("neuf_elapsed_s", "99")) < 5.0, "neuf_worker_attendu")
except ValueError:
    defects.append("neuf_elapsed_illisible")
need(kv.get("neuf_abort_reason") == "archived", "neuf_abort_reason")
# temoin d'AVANT : il doit rougir (sinon un zero ne dit rien)
need((num("vieux_side_effects") or 0) > 0, "vieux_ne_rougit_pas")
need(kv.get("before_commit_orchestrator", "-") != "-", "vieux_commit_introuvable")
# controle POSITIF seme : rougit et NOMME
need((num("seme_side_effects") or 0) > 0 and kv.get("seme_side_effects_named", "-") != "-",
     "seme_ne_rougit_pas")
# controle NEGATIF : un essai sain est juge, compte, rouvert
need(num("temoin_archived") == 0 and kv.get("temoin_outcome") == "fail"
     and num("temoin_validator_calls") == 1 and num("temoin_retries_delta") == 1
     and kv.get("temoin_final_status") == "open", "temoin_essai_sain_altere")

# les gardes des ecrivains du worker
leaks = 0
for g in ("guard_comment_archived_worker", "guard_commit_archived_worker",
          "guard_hook_git_refused_archived"):
    v = num(g)
    need(v is not None, g + "_absent")
    leaks += 0 if v == 1 else 1
need(num("guard_hook_installed") == 1, "hook_commit_msg_non_installe")
false_refusals = 0
for g in ("guard_comment_archived_superviseur", "guard_commit_archived_superviseur",
          "guard_comment_in-progress_worker", "guard_commit_in-progress_worker",
          "guard_comment_in-progress_superviseur", "guard_commit_in-progress_superviseur",
          "guard_hook_git_refused_live"):
    v = num(g)
    need(v is not None, g + "_absent")
    false_refusals += 1 if v else 0
need(false_refusals == 0, "refus_a_tort")

pub("archived_item_before_commit", kv.get("before_commit_orchestrator", "-"))
pub("archived_item_archives_fabricated", sum(1 for a in CUT_ARMS if num(a + "_archived") == 1))
pub("archived_item_channels", 7)
pub("archived_item_writes_checked", 7 * len(CUT_ARMS) + 3)
pub("archived_item_cut_side_effects", side)
pub("archived_item_guard_leaks", leaks)
pub("archived_item_guard_false_refusals", false_refusals)
pub("archived_item_hook_installed", kv.get("guard_hook_installed", "-"))
pub("archived_item_instrument_defects", len(defects))
pub("archived_item_instrument_defects_named", ",".join(defects) or "-")
# l'historique reel : combien d'archivages de l'owner le backlog porte deja (il n'y en avait aucun
# avant ce correctif, donc aucun degat passe a rattraper)
try:
    notes = open(sys.argv[2], encoding="utf-8").read().count("chantier archivé")
except OSError:
    notes = -1
pub("archived_item_history_owner_archives", notes)
pub("archived_item_attempt_side_effects", side + leaks + len(defects))
PY
