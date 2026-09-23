#!/usr/bin/env bash
# census/harness-status-says-when-linear-cache-is-stale.sh — LE VERDICT DE L'ITEM.
#
# Lance par `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`) apres la course.
#
# LE DEFAUT : `backlog.status_report` lisait `(records, at) = owner_sla.load_cache()` et jetait
# `at`. Synchro Linear morte = releve fige, rubrique muette, et ce silence se lisait « aucun
# retour n'attend ».
#
# CE QU'IL MESURE — la porte : `status_stale_cache_silent` = rapports rendus par le VRAI
# `status_report` sur un releve PERIME ou ABSENT sans le dire. Doit valoir 0.
#   * POPULATION SEMEE (repertoire jetable, `AUTOPORT_OWNER_SLA_CACHE`) : cas perimes, absents,
#     illisibles, ET cas frais — horloge FIGEE, pour que la borne se juge a la seconde pres.
#   * CONTROLE NEGATIF : les cas frais ne doivent RIEN dire (`status_fresh_cache_flagged` = 0).
#     Un code qui crierait toujours « arretee » aurait sinon 0 silencieux par construction.
#   * CONTROLE POSITIF : la MEME population, rendue avec l'en-tete d'age neutralise (= le code
#     d'avant, qui ignorait `at`), doit taire TOUS les cas perimes — et les NOMMER.
#   * LE HARNAIS REEL : le vrai releve, le vrai backlog ; perime ET muet = +1.
# Un controle qui ne separe pas = instrument invalide : la porte vaut 99, jamais 0.
#
# RIEN ICI N'ECRIT DANS L'ETAT DU HARNAIS QUI TOURNE : on ne vieillit jamais le vrai
# `.owner_sla.json` pour le mesurer.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "status_stale_cache_silent=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY' || echo "status_stale_cache_silent=99"
import json, os, sys, tempfile, time, types

AP = os.path.abspath(".autoport")
sys.path.insert(0, AP)
sys.path.insert(0, os.path.join(AP, "lib"))

import yaml
import owner_sla as O
import backlog as B
import wake_gate as W

def pub(k, v):
    print("%s=%s" % (k, v), flush=True)

TMP = tempfile.mkdtemp(prefix="stale-cache-census-")
SEUIL = O.cache_stale_s()
pub("status_stale_threshold_s", SEUIL)

# Un backlog minimal : le rendu ne doit dependre que du releve.
BK = os.path.join(TMP, "backlog.yaml")
with open(BK, "w", encoding="utf-8") as fh:
    yaml.safe_dump({"version": 1, "items": [{
        "id": "semis", "feature": "Un sujet seme", "status": "in-progress", "priority": 50,
        "owner_feedback": [], "gate": None, "game": "jak1", "max_turns": 100, "max_retries": 3,
        "depends_on": [], "history": [], "prompt": None, "owner_ok": None}]}, fh)

T = int(time.time())
VRAI_TEMPS = O.time

def horloge(t):
    O.time = types.SimpleNamespace(time=lambda: float(t), strftime=time.strftime,
                                   localtime=time.localtime)

RETOUR = [{"dated": True, "open": True, "answered": False, "ts": T - 30 * 3600,
           "item": "semis", "key": "semis:1", "text": "retour seme", "date": "2026-09-22"}]

# (nom, contenu du releve : None = pas de fichier, str = octets bruts, dict = JSON ; perime ?)
CAS = [
    ("frais-60s",             {"at": T - 60, "records": []},               False),
    ("frais-a-la-borne",      {"at": T - SEUIL, "records": []},            False),
    ("frais-avec-retour",     {"at": T - 300, "records": RETOUR},          False),
    ("perime-borne+1s",       {"at": T - SEUIL - 1, "records": []},        True),
    ("perime-2h",             {"at": T - 2 * 3600 - 5, "records": []},     True),
    ("perime-26h-avec-retour", {"at": T - 26 * 3600, "records": RETOUR},   True),
    ("absent",                None,                                         True),
    ("illisible",             "{pas du json",                               True),
    ("at-zero",               {"at": 0, "records": RETOUR},                True),
]
MARQUES = ("SYNCHRO LINEAR ARRETEE DEPUIS", "SYNCHRO LINEAR : AUCUN RELEVE")

def semer(nom, contenu):
    p = os.path.join(TMP, "releve-%s.json" % nom)
    if contenu is not None:
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(contenu if isinstance(contenu, str) else json.dumps(contenu))
    os.environ["AUTOPORT_OWNER_SLA_CACHE"] = p
    return p

def rendre(nom, contenu, t=T):
    semer(nom, contenu)
    horloge(t)
    try:
        return B.load(BK).status_report()
    finally:
        O.time = VRAI_TEMPS

def dit(texte):
    return any(m in texte for m in MARQUES)

def passe(neutraliser):
    silencieux, faux, desaccord = [], [], []
    livre = O.cache_lines
    if neutraliser:
        O.cache_lines = lambda at, now=None, pid_path=None: []
    try:
        for nom, contenu, perime in CAS:
            texte = rendre(nom, contenu)
            if perime and not dit(texte):
                silencieux.append(nom)
            if not perime and dit(texte):
                faux.append(nom)
            if not neutraliser:
                # LE REVEIL DU SUPERVISEUR lit la MEME definition : il doit dire la meme chose.
                recs, at = O.load_cache()
                wg, _ = W.retours_sans_reponse(records=recs, at=at, maintenant=T)
                if perime != ("PERIME" in wg or "LISTE INCONNUE" in wg):
                    desaccord.append(nom)
    finally:
        O.cache_lines = livre
    return silencieux, faux, desaccord

n_perime = sum(1 for c in CAS if c[2])
pub("status_stale_cases_total", len(CAS))
pub("status_stale_cases_stale", n_perime)
pub("status_stale_cases_fresh", len(CAS) - n_perime)

sil, faux, desac = passe(False)
pub("status_stale_silent_named", ",".join(sil) or "-")
pub("status_fresh_cache_flagged", len(faux))
pub("status_fresh_cache_flagged_named", ",".join(faux) or "-")
pub("status_stale_wake_gate_disagree", len(desac))
pub("status_stale_wake_gate_disagree_named", ",".join(desac) or "-")

abl_sil, abl_faux, _ = passe(True)
pub("status_stale_ablation_silent", len(abl_sil))
pub("status_stale_ablation_silent_named", ",".join(abl_sil) or "-")

# LE TEXTE EST RELU EN BOUCLE par watch.py : 60 s de plus dans le meme palier ne changent rien,
# un palier franchi se voit.
releve = {"at": T - 2 * 3600 - 5, "records": []}
a, b = rendre("palier-a", releve, T), rendre("palier-b", releve, T + 60)
c = rendre("palier-c", releve, T + 4 * 3600)
pub("status_stale_text_changes_within_palier", 0 if a == b else 1)
pub("status_stale_text_changes_on_palier", 1 if a != c else 0)

# LE HARNAIS REEL : le vrai releve, le vrai backlog, la vraie veille.
os.environ.pop("AUTOPORT_OWNER_SLA_CACHE", None)
recs, at = O.load_cache()
age, etat = O.cache_age(at)
pub("status_live_cache_age_s", age)
pub("status_live_cache_state", etat)
pub("status_live_cache_records", len(recs))
_pid, _viv = O.veille_vivante()
pub("status_live_watch_pid", _pid)
pub("status_live_watch_alive", 1 if _viv else 0)
vrai = B.load().status_report()
live_silent = 1 if etat != "frais" and not dit(vrai) else 0
live_flagged = 1 if etat == "frais" and dit(vrai) else 0
pub("status_live_stale_silent", live_silent)
pub("status_live_fresh_flagged", live_flagged)

# L'INSTRUMENT SEPARE-T-IL ? Sinon la porte ne peut pas valoir 0.
invalide = []
if len(abl_sil) != n_perime:
    invalide.append("controle-positif-%d-sur-%d" % (len(abl_sil), n_perime))
if faux or live_flagged:
    invalide.append("controle-negatif-%d" % (len(faux) + live_flagged))
if desac:
    invalide.append("reveil-en-desaccord-%d" % len(desac))
pub("status_stale_census_invalid", ",".join(invalide) or "-")
total = len(sil) + live_silent
pub("status_stale_cache_silent", 99 if invalide else total)
PY
