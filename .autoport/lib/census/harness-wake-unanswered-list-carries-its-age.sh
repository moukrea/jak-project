#!/usr/bin/env bash
# census/harness-wake-unanswered-list-carries-its-age.sh — LE VERDICT DE L'ITEM.
#
# Lance par `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`) apres la course.
#
# LA GRANDEUR. `wake_unanswered_lost` = retours de l'owner ouverts pour owner_sla (`open_records`)
# que le reveil du superviseur ne lui LIVRE pas entiers, compte par retour, sur le texte que rend le
# VRAI `wake_gate.decide` :
#   absent          aucune ligne du bloc « RETOURS DE L'OWNER SANS REPONSE » ne le nomme, ou le
#                   reveil est REFUSE alors que son cran a monte depuis le dernier reveil livre
#   sans_age        sa ligne ne dit pas depuis quand il attend (« attend depuis »)
#   non_escalade    il a passe le delai convenu (`owner_sla.sla_seconds()`) et sa ligne ne le dit pas
#   tete_muette     1 si un retour au moins est en retard et que la tete du bloc ne le dit pas
# Publie a part, hors porte : `faux_retard` (ligne marquee EN RETARD dans le delai).
#
#   AVANT-JOURNAL  la regle de 5c96e2d313 (etiquette « A traiter » lue par regex dans les 40 000
#                  derniers octets de logs/linear_sync.txt), module entier rejoue sur un journal
#                  FABRIQUE ou une trace de 45 ko pousse la ligne hors de la fenetre.
#   AVANT-AGE      la regle de ccca1d6d3e (owner_sla, sans age ni cran) sur le meme semis, et sur
#                  un retour qui franchit le delai entre deux reveils (la veille le refuse).
#   NEGATIF        le code livre sur les memes semis, sur un cas sain, et la veille qui refuse
#                  toujours un reveil ou rien n'a monte (l'age a la minute n'est pas dans la signature).
#   REEL           le releve `.owner_sla.json` du jour, `decide` rejoue sans rien ecrire.
#
# INCONNU = DEFAUT : releve absent -> -1. Un controle qui echoue s'AJOUTE a la grandeur ; le compte
# reel reste publie a part (`wake_unanswered_lost_real`).
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "wake_unanswered_lost=-1"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import collections, hashlib, json, os, re, shutil, subprocess, sys, tempfile, time, types

sys.path.insert(0, os.path.abspath(".autoport"))
sys.path.insert(0, os.path.abspath(".autoport/lib"))
import owner_sla as O
import wake_gate as W
from lib import backlog as B

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
TETE = "## RETOURS DE L'OWNER SANS REPONSE"
LIGNE = re.compile(r"^- (JAK-\d+|sans-ticket) (\S+)")
SLA = O.sla_seconds()
pub("wake_unanswered_sla_s", SLA)
TERMES = ("absent", "sans_age", "non_escalade", "tete_muette")


# ------------------------------------------------------------------ les deux regles d'AVANT
def module_au_commit(commit, nom, fichier):
    src = subprocess.run(["git", "show", "%s:.autoport/lib/wake_gate.py" % commit],
                         capture_output=True, text=True, check=True).stdout
    m = types.ModuleType(nom)
    m.__file__ = fichier
    exec(compile(src, "%s@%s" % (fichier, commit), "exec"), m.__dict__)
    pub("wake_unanswered_before_%s_sha" % nom, hashlib.sha256(src.encode()).hexdigest()[:16])
    return m


tmp = tempfile.mkdtemp(prefix="wake-age-")
os.makedirs(os.path.join(tmp, "lib"))
os.makedirs(os.path.join(tmp, "logs"))
AVANT = {}
for commit, nom, fichier in (("5c96e2d313", "journal", os.path.join(tmp, "lib", "wake_gate.py")),
                             ("ccca1d6d3e", "sans_age", os.path.abspath(".autoport/lib/wake_gate.py"))):
    pub("wake_unanswered_before_%s_commit" % nom, commit)
    try:
        AVANT[nom] = module_au_commit(commit, nom, fichier)
    except Exception as exc:  # noqa: BLE001
        pub("wake_unanswered_before_%s_error" % nom, type(exc).__name__)


# ------------------------------------------------------------------ l'instrument
class Carnet:
    """Un backlog sans rien : la signature ne bouge que par ce que le controle fait bouger."""
    items = []
    def signature_digest(self):
        return "carnet"
    def status_report(self):
        return ""


def attendus(records, T):
    out = []
    for r in sorted(O.open_records(records), key=lambda r: r.get("ts") or 0):
        a = W.age_retour(r, T)
        out.append((r, W.cran_retour(a, SLA)))
    return out


def rejouer(mod, T, memo, cache, carte, stub=True):
    """(decision, raison, texte) du VRAI `decide` du module, sans rien ecrire."""
    old_env, old_load = os.environ.get("AUTOPORT_OWNER_SLA_CACHE"), B.load
    old = {k: getattr(mod, k, None) for k in ("_memo", "_journal", "LINEAR_MAP", "etat_sante")}
    os.environ["AUTOPORT_OWNER_SLA_CACHE"] = cache
    mod._memo = lambda: dict(memo)
    mod._journal = lambda _l: None
    mod.LINEAR_MAP = carte
    if stub:
        mod.etat_sante = lambda: {"sante": 1}
        B.load = lambda *a, **k: Carnet()
    try:
        return mod.decide(PROMPT, maintenant=T, ecrire=False)
    finally:
        B.load = old_load
        for k, v in old.items():
            setattr(mod, k, v)
        if old_env is None:
            os.environ.pop("AUTOPORT_OWNER_SLA_CACHE", None)
        else:
            os.environ["AUTOPORT_OWNER_SLA_CACHE"] = old_env


def mesurer(records, T, rendu, deja_livre=None):
    """Compte les retours ouverts que `rendu` ne livre pas entiers. `deja_livre` = {cle: cran} vus
    au dernier reveil LIVRE : un reveil refuse ne perd que ce dont le cran a monte depuis."""
    dec, raison, texte = rendu
    att = attendus(records, T)
    n = dict.fromkeys(TERMES + ("faux_retard",), 0)
    noms = []
    if dec != "passe":
        for r, c in att:
            if (deja_livre or {}).get(r.get("key"), -1) != c:
                n["absent"] += 1
                noms.append("absent:%s(refus:%s)" % (r.get("item"), raison))
        return n, noms, att, 0
    tete, lignes, dedans = "", collections.defaultdict(list), False
    for l in texte.splitlines():
        if l.startswith("## "):
            dedans = l.startswith(TETE)
            if dedans:
                tete = l
            continue
        m = LIGNE.match(l) if dedans else None
        if m:
            lignes[m.group(2)].append(l)
    listees = sum(len(v) for v in lignes.values())
    for r, c in att:
        item = r.get("item")
        if not lignes[item]:
            n["absent"] += 1
            noms.append("absent:%s" % item)
            continue
        l = lignes[item].pop(0)
        if "attend depuis" not in l:
            n["sans_age"] += 1
            noms.append("sans_age:%s" % item)
        if c >= 1 and "EN RETARD" not in l:
            n["non_escalade"] += 1
            noms.append("non_escalade:%s" % item)
        if c == 0 and "EN RETARD" in l:
            n["faux_retard"] += 1
            noms.append("faux_retard:%s" % item)
    if any(c >= 1 for _r, c in att) and "EN RETARD" not in tete:
        n["tete_muette"] = 1
        noms.append("tete_muette")
    return n, noms, att, listees


def total(n):
    return sum(n[k] for k in TERMES)


def rec(item, age, T, text="retour", open_=1, dated=1):
    return {"item": item, "text": text, "date": "2026-09-23", "key": O.feedback_key(item, text),
            "ts": T - age, "dated": dated, "open": open_, "answered": 1 - open_, "delay_s": age}


def semer(nom, records, T):
    p = os.path.join(tmp, nom + ".json")
    O.save_cache(records, path=p, now=T - 60)
    return p


# ================================================================ CONTROLES (hors reseau)
T = time.time()
carte = os.path.join(tmp, "linear_map.json")
json.dump({"item-frais": {"identifier": "JAK-901"}, "item-retard": {"identifier": "JAK-902"},
           "item-jour": {"identifier": "JAK-903"}, "item-repondu": {"identifier": "JAK-904"}},
          open(carte, "w"))
# Le semis : un retour dans le delai, un en retard, un de plus d'un jour ; plus un retour repondu
# et un non date, que ni le compteur ni le reveil ne doivent lister.
seme = [rec("item-frais", 30 * 60, T), rec("item-retard", 3 * 3600, T),
        rec("item-jour", 30 * 3600, T), rec("item-repondu", 5 * 3600, T, open_=0),
        rec("item-hors-fenetre", 5 * 3600, T, dated=0)]
c_seme = semer("seme", seme, T)
pub("wake_unanswered_ctl_seed_open", len(O.open_records(seme)))
pub("wake_unanswered_ctl_seed_overdue", sum(1 for _r, c in attendus(seme, T) if c))

# POSITIF 1 — la regle du journal : une trace de 45 ko pousse la ligne hors des 40 ko.
if "journal" in AVANT:
    open(os.path.join(tmp, "logs", "linear_sync.txt"), "w", encoding="utf-8").write(
        "Linear : tour 1\n"
        "À TRAITER : JAK-901 item-frais (retour owner sans réponse)\n"
        "À TRAITER : JAK-902 item-retard (retour owner sans réponse)\n"
        "À TRAITER : JAK-903 item-jour (retour owner sans réponse)\n"
        "Linear : tour 2\n" + "Traceback (most recent call last): urllib.error.URLError\n" * 800
        + "Linear : tour 3\n")
    n, noms, _a, _l = mesurer(seme, T, rejouer(AVANT["journal"], T, {}, c_seme, carte))
    pub("wake_unanswered_ctl_pos_journal", total(n))
    pub("wake_unanswered_ctl_pos_journal_named", ";".join(noms) or "-")
    check("pos-journal-rougit", n["absent"] == 3)
    check("pos-journal-nomme", sorted(noms) == ["absent:item-frais", "absent:item-jour",
                                                  "absent:item-retard", "tete_muette"])
else:
    check("pos-journal-charge", False)

# POSITIF 2 — la regle d'hier (owner_sla, sans age) : tout est liste, rien ne dit depuis quand.
if "sans_age" in AVANT:
    n, noms, _a, _l = mesurer(seme, T, rejouer(AVANT["sans_age"], T, {}, c_seme, carte))
    pub("wake_unanswered_ctl_pos_ageless", total(n))
    pub("wake_unanswered_ctl_pos_ageless_named", ";".join(noms) or "-")
    check("pos-sans-age-rougit", n["absent"] == 0 and n["sans_age"] == 3
          and n["non_escalade"] == 2 and n["tete_muette"] == 1)
else:
    check("pos-sans-age-charge", False)

# FRANCHISSEMENT — un seul retour, 10 min SOUS le delai au reveil livre, 10 min AU-DELA au suivant.
T0, T1 = T - 20 * 60, T
fr = [rec("item-retard", SLA - 10 * 60, T0)]
c_fr = semer("franchit", fr, T1)
livre0 = {r["key"]: c for r, c in attendus(fr, T0)}
check("franchit-semis", list(livre0.values()) == [0] and [c for _r, c in attendus(fr, T1)] == [1])

def memo_de(mod, T_, cache):
    old = os.environ.get("AUTOPORT_OWNER_SLA_CACHE")
    os.environ["AUTOPORT_OWNER_SLA_CACHE"] = cache
    old_sante, mod.etat_sante = mod.etat_sante, (lambda: {"sante": 1})
    try:
        try:
            sig = mod.signature(Carnet(), T_)[0]
        except TypeError:                     # la signature d'avant ne prend pas l'heure
            sig = mod.signature(Carnet())[0]
    finally:
        mod.etat_sante = old_sante
        os.environ["AUTOPORT_OWNER_SLA_CACHE"] = old if old is not None else ""
        if old is None:
            os.environ.pop("AUTOPORT_OWNER_SLA_CACHE")
    return {"signature": sig, "dernier_reveil": T_, "refus_consecutifs": 0}

if "sans_age" in AVANT:
    m = AVANT["sans_age"]
    rendu = rejouer(m, T1, memo_de(m, T0, c_fr), c_fr, carte)
    n, noms, _a, _l = mesurer(fr, T1, rendu, livre0)
    pub("wake_unanswered_ctl_pos_crossing", total(n))
    pub("wake_unanswered_ctl_pos_crossing_named", ";".join(noms) or "-")
    check("pos-franchit-refuse", rendu[0] == "refuse" and n["absent"] == 1)

rendu = rejouer(W, T1, memo_de(W, T0, c_fr), c_fr, carte)
n, noms, _a, _l = mesurer(fr, T1, rendu, livre0)
pub("wake_unanswered_ctl_neg_crossing", total(n))
pub("wake_unanswered_ctl_neg_crossing_reason", rendu[1])
pub("wake_unanswered_ctl_neg_crossing_named", ";".join(noms) or "-")
check("neg-franchit-reveille", rendu[0] == "passe" and rendu[1] == "etat-change" and total(n) == 0)

# ECONOMIE — une minute plus tard, rien n'a monte : la veille doit toujours refuser.
rendu = rejouer(W, T1 + 60, memo_de(W, T1, c_fr), c_fr, carte)
n, noms, _a, _l = mesurer(fr, T1 + 60, rendu, {r["key"]: c for r, c in attendus(fr, T1)})
pub("wake_unanswered_ctl_neg_economy_decision", rendu[0])
check("neg-economie-refuse", rendu[0] == "refuse" and total(n) == 0)

# NEGATIF — le code livre sur le meme semis que les positifs.
n, noms, _a, listees = mesurer(seme, T, rejouer(W, T, {}, c_seme, carte))
pub("wake_unanswered_ctl_neg_same_seed", total(n))
pub("wake_unanswered_ctl_neg_same_seed_listed", listees)
pub("wake_unanswered_ctl_neg_same_seed_named", ";".join(noms) or "-")
check("neg-meme-semis", total(n) == 0 and listees == 3 and n["faux_retard"] == 0)

# NEGATIF — un cas sain : un retour frais, un repondu. Rien en retard, rien de crie.
sain = [rec("item-frais", 10 * 60, T), rec("item-repondu", 5 * 3600, T, open_=0)]
c_sain = semer("sain", sain, T)
rendu = rejouer(W, T, {}, c_sain, carte)
n, noms, _a, listees = mesurer(sain, T, rendu)
pub("wake_unanswered_ctl_neg_healthy", total(n))
pub("wake_unanswered_ctl_neg_healthy_false_escalation", n["faux_retard"])
check("neg-sain", total(n) == 0 and listees == 1 and n["faux_retard"] == 0
      and "EN RETARD" not in rendu[2])

pub("wake_unanswered_controls", len(ctl))
pub("wake_unanswered_controls_failed", ctl_fail)
pub("wake_unanswered_controls_list", ",".join(ctl))

# ================================================================ REEL
real = -1
try:
    recs, at = O.load_cache()
    if not at:
        raise RuntimeError("releve owner_sla absent (%s)" % O.cache_path())
    Tr = time.time()
    pub("wake_unanswered_population", len(recs))
    pub("wake_unanswered_dated", sum(1 for r in recs if r.get("dated")))
    pub("wake_unanswered_open", len(O.open_records(recs)))
    pub("wake_unanswered_open_overdue", sum(1 for _r, c in attendus(recs, Tr) if c >= 1))
    pub("wake_unanswered_open_over_a_day", sum(1 for _r, c in attendus(recs, Tr) if c >= 2))
    pub("wake_unanswered_cache_age_s", int(Tr - at))
    rendu = rejouer(W, Tr, {}, O.cache_path(), W.LINEAR_MAP, stub=False)
    pub("wake_unanswered_real_decision", "%s/%s" % rendu[:2])
    n, noms, _a, listees = mesurer(recs, Tr, rendu)
    pub("wake_unanswered_listed_by_wake", listees)
    for k in TERMES + ("faux_retard",):
        pub("wake_unanswered_real_%s" % k, n[k])
    pub("wake_unanswered_real_named", ";".join(noms) or "-")
    real = total(n)
except Exception as exc:  # noqa: BLE001
    pub("wake_unanswered_error", ("%s:%s" % (type(exc).__name__, exc))[:120])

pub("wake_unanswered_lost_real", real)
pub("wake_unanswered_lost", real + ctl_fail if real >= 0 else -1)
shutil.rmtree(tmp, ignore_errors=True)
for k in ORDRE:
    print("%s=%s" % (k, OUT[k]))
PY
