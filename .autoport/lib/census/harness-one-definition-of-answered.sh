#!/usr/bin/env bash
# census/harness-one-definition-of-answered.sh — LE VERDICT DE L'ITEM.
#
# Lance par `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`) apres la course.
#
# LA GRANDEUR. `answered_definitions_disagree` = retours ouverts pour owner_sla mais absents du
# bloc « RETOURS DE L'OWNER SANS REPONSE » du reveil, PLUS ceux que le reveil liste et que
# owner_sla compte repondus. Compte PAR ITEM (une ligne du reveil = un retour ouvert), sur le
# texte que rend le VRAI `wake_gate.decide` — pas sur la fonction qu'il est cense appeler.
#
#   REEL      le releve `.owner_sla.json` du jour, `decide` rejoue sans rien ecrire.
#   AVANT     l'ancienne regle (etiquette « A traiter » lue dans logs/linear_sync.txt, HEAD
#             5c96e2d313) contre le MEME releve : le desaccord qu'on supprime, NOMME.
#   POSITIF   un releve et un journal FABRIQUES ou `--comment` hors fil a retire l'etiquette
#             d'un retour encore ouvert, et ou une etiquette survit a un retour repondu ;
#             l'ancienne regle rebranchee dans `decide` doit rougir et nommer les deux.
#   NEGATIF   le code livre sur le meme semis et sur un cas sain : 0.
#
# INCONNU = DEFAUT : releve absent -> -1. Un controle qui echoue s'AJOUTE a la grandeur ; le
# compte reel reste publie a part (`answered_definitions_disagree_real`).
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "answered_definitions_disagree=-1"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import collections, json, os, re, sys, tempfile, time

sys.path.insert(0, os.path.abspath(".autoport"))
sys.path.insert(0, os.path.abspath(".autoport/lib"))
import owner_sla as O
import wake_gate as W

OUT, ORDRE = {}, []
def pub(k, v):
    if k not in OUT:
        ORDRE.append(k)
    OUT[k] = str(v).replace(" ", "_")

ctl, ctl_fail = [], 0
def check(name, ok):
    global ctl_fail
    ctl.append("%s:%s" % (name, "ok" if ok else "ECHEC"))
    if not ok:
        ctl_fail += 1

PROMPT = ("Autoport supervision digest : point periodique de l'orchestrateur. " * 12).strip()
LIGNE = re.compile(r"^- (JAK-\d+|sans-ticket) (\S+)")
TETE = "## RETOURS DE L'OWNER SANS REPONSE"

W._memo = lambda: {}          # « premier passage » : decide construit toujours son texte
W._journal = lambda _l: None  # et n'ecrit rien


def listes_du_reveil():
    """Les items que le VRAI `decide` nomme dans son bloc, un par ligne."""
    dec, raison, texte = W.decide(PROMPT, ecrire=False)
    if dec != "passe":
        raise RuntimeError("decide=%s/%s" % (dec, raison))
    n, dedans = collections.Counter(), False
    for l in texte.splitlines():
        if l.startswith("## "):
            dedans = l.startswith(TETE)
            continue
        m = LIGNE.match(l) if dedans else None
        if m:
            n[m.group(2)] += 1
    return n


def desaccord(records):
    """(|ecart|, nomme) entre owner_sla.open_records et ce que decide liste."""
    attendu = collections.Counter(r.get("item") for r in O.open_records(records))
    vu = listes_du_reveil()
    manque = attendu - vu
    en_trop = vu - attendu
    nom = ";".join(["manque:%s" % k for k in sorted(manque.elements())]
                   + ["en_trop:%s" % k for k in sorted(en_trop.elements())]) or "-"
    return sum(manque.values()) + sum(en_trop.values()), nom, sum(attendu.values()), sum(vu.values())


# L'ancienne regle, telle que HEAD 5c96e2d313 l'avait dans `decide`, rebranchee a la place de la
# nouvelle : l'etiquette « A traiter » du dernier tour de la synchro.
def ancienne_regle(log):
    def f(records=None, at=None, maintenant=None):
        txt = open(log, encoding="utf-8", errors="replace").read()[-40000:]
        tours = txt.split("Linear : ")
        dernier = tours[-2] if len(tours) >= 2 else txt
        attente = sorted(set(re.findall(r"À TRAITER : (JAK-\d+ \S+)", dernier)))
        if not attente:
            return "", []
        return (TETE + " — REPONDRE A CHACUN AVANT TOUT DIGEST\n"
                + "\n".join("- " + a for a in attente) + "\n"), []
    return f

LIVRE = W.retours_sans_reponse


def avec(fn, regle=None, cache=None, carte=None):
    old_env, old_map = os.environ.get("AUTOPORT_OWNER_SLA_CACHE"), W.LINEAR_MAP
    if cache:
        os.environ["AUTOPORT_OWNER_SLA_CACHE"] = cache
    if carte:
        W.LINEAR_MAP = carte
    if regle:
        W.retours_sans_reponse = regle
    try:
        return fn()
    finally:
        W.retours_sans_reponse = LIVRE
        W.LINEAR_MAP = old_map
        if old_env is None:
            os.environ.pop("AUTOPORT_OWNER_SLA_CACHE", None)
        else:
            os.environ["AUTOPORT_OWNER_SLA_CACHE"] = old_env


def rec(item, open_, dated=1, text="retour"):
    return {"item": item, "text": text, "date": "2026-09-23", "key": O.feedback_key(item, text),
            "ts": time.time() - 3600, "dated": dated, "open": open_, "answered": 1 - open_,
            "delay_s": 3600}


# ================================================================ CONTROLES (hors reseau)
tmp = tempfile.mkdtemp(prefix="one-answered-")
carte = os.path.join(tmp, "linear_map.json")
json.dump({"item-ouvert": {"identifier": "JAK-901"}, "item-repondu": {"identifier": "JAK-902"},
           "item-sain": {"identifier": "JAK-903"}}, open(carte, "w"))
# Le semis : `item-ouvert` a un retour OUVERT dont l'etiquette a ete retiree par un --comment hors
# fil ; `item-repondu` a ete repondu dans le fil mais garde son etiquette (pouce pas encore vu).
seme = [rec("item-ouvert", 1), rec("item-ouvert", 1, text="second"), rec("item-repondu", 0),
        rec("item-hors-fenetre", 1, dated=0)]
cache_seme = os.path.join(tmp, "seme.json")
O.save_cache(seme, path=cache_seme)
log = os.path.join(tmp, "linear_sync.txt")
open(log, "w").write("Linear : tour 1\nÀ TRAITER : JAK-901 item-ouvert (retour owner sans réponse)\n"
                     "Linear : tour 2\nÀ TRAITER : JAK-902 item-repondu (retour owner sans réponse)\n"
                     "Linear : tour 3\n")

n, nom, att, vu = avec(lambda: desaccord(seme), ancienne_regle(log), cache_seme, carte)
pub("answered_definitions_ctl_pos_old_rule", n)
pub("answered_definitions_ctl_pos_named", nom)
check("pos-rougit", n == 3)
check("pos-nomme", nom == "manque:item-ouvert;manque:item-ouvert;en_trop:item-repondu")

n, nom, att, vu = avec(lambda: desaccord(seme), None, cache_seme, carte)
pub("answered_definitions_ctl_neg_same_seed", n)
pub("answered_definitions_ctl_neg_same_seed_listed", vu)
check("neg-meme-semis", n == 0 and vu == 2)

sain = [rec("item-sain", 1), rec("item-repondu", 0)]
cache_sain = os.path.join(tmp, "sain.json")
O.save_cache(sain, path=cache_sain)
n, nom, att, vu = avec(lambda: desaccord(sain), None, cache_sain, carte)
pub("answered_definitions_ctl_neg_healthy", n)
check("neg-sain", n == 0 and vu == 1)

# Le compteur et le reveil lisent la MEME fonction : un retour non date n'est ni compte ni liste.
check("compteur-meme-fonction", O.cost_summary(seme, 7200)["open"] == len(O.open_records(seme)) == 2)

# INCONNU = DEFAUT : sans releve, le reveil le DIT au lieu de se taire.
absent = os.path.join(tmp, "absent.json")
txt = avec(lambda: W.decide(PROMPT, ecrire=False)[2], None, absent, carte)
check("releve-absent-dit", "LISTE INCONNUE" in txt)
# Un releve PERIME aussi.
O.save_cache([], path=os.path.join(tmp, "vieux.json"), now=time.time() - 4 * 3600)
txt = avec(lambda: W.decide(PROMPT, ecrire=False)[2], None, os.path.join(tmp, "vieux.json"), carte)
check("releve-perime-dit", "PERIME" in txt)

pub("answered_definitions_controls", len(ctl))
pub("answered_definitions_controls_failed", ctl_fail)
pub("answered_definitions_controls_list", ",".join(ctl))

# ================================================================ REEL
real = -1
try:
    recs, at = O.load_cache()
    if not at:
        raise RuntimeError("releve owner_sla absent (%s)" % O.cache_path())
    pub("answered_definitions_population", len(recs))
    pub("answered_definitions_dated", sum(1 for r in recs if r.get("dated")))
    pub("answered_definitions_open_owner_sla", len(O.open_records(recs)))
    pub("answered_definitions_cache_age_s", int(time.time() - at))
    real, nom, att, vu = desaccord(recs)
    pub("answered_definitions_listed_by_wake", vu)
    pub("answered_definitions_disagree_real_named", nom)
    # AVANT : l'ancienne regle sur le VRAI journal, contre le meme releve.
    vrai_log = os.path.join(".autoport", "logs", "linear_sync.txt")
    if os.path.exists(vrai_log):
        b, bnom, _a, bvu = avec(lambda: desaccord(recs), ancienne_regle(vrai_log))
        pub("answered_definitions_disagree_before_real", b)
        pub("answered_definitions_disagree_before_named", bnom)
        pub("answered_definitions_listed_by_wake_before", bvu)
except Exception as exc:  # noqa: BLE001
    pub("answered_definitions_error", ("%s:%s" % (type(exc).__name__, exc))[:120])

pub("answered_definitions_disagree_real", real)
pub("answered_definitions_disagree", real + ctl_fail if real >= 0 else -1)
import shutil
shutil.rmtree(tmp, ignore_errors=True)
for k in ORDRE:
    print("%s=%s" % (k, OUT[k]))
PY
