#!/usr/bin/env bash
# census/harness-linear-owner-move-reads-fresh-item.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `linear_sync_stale_item_writes`.
# Il n'ecrit rien dans le vrai backlog : tout se joue sur des COPIES jetables, Linear est simule.
#
# LE DEFAUT (signale par trois workers, ouvert par le superviseur le 23/09) : `apply_owner_move` decidait
# d'un deplacement de ticket par l'owner sur le statut LU EN MEMOIRE en debut de passe et recomposait
# `notes` depuis cette copie avant `set_status` ; `adopt_owner_order` reposait le statut en memoire avec
# le rang ; `apply_owner_archive` recomposait `notes` depuis la memoire. Un statut (essai lance par
# l'orchestrateur) ou une note (superviseur) ecrits entre-temps etaient ecrases. Desormais les trois
# decident dans `Backlog.update`, sur l'item RELU sous le verrou.
#
# CE QU'IL MESURE — `linear_sync_stale_item_writes` = somme de :
#   L   ecritures PERIMEES du code livre sur les courses FABRIQUEES (copie chargee AVANT un ecrivain
#       frais, puis la reaction de la synchro) : note perdue, statut ramene, rang calcule sur la
#       copie, feu vert reecrit, message poste sur une decision perimee. Une par scenario fautif.
#   N   CONTROLE NEGATIF : les memes scenarios SANS recouvrement (copie chargee apres l'ecrivain frais),
#       code livre ET code semé : doit donner 0 des deux cotes, sinon le juge de scenario est faux.
#   W   appels `set_status(` restant dans linear_sync.py (AST, noeud d'APPEL) : le seul chemin qui
#       repose un statut ou des notes tenus en memoire.
#   D   CONTROLES MORTS : le code d'AVANT (les trois fonctions extraites du commit 69b8fee8f9, embarquees
#       ci-dessous) doit rougir sur CHAQUE scenario perime, et l'AST doit y trouver ses set_status.
#   F   l'adoption de l'ordre de la colonne Todo, jouee HORS course, doit toujours reclasser (1 sinon).
#   INCONNU = DEFAUT : un scenario qui leve compte 1 et est nomme.
# Denominateur publie : scenarios joues, et sites d'ecriture du backlog recenses dans linear_sync.py.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "linear_sync_stale_item_writes=99"; exit 1; }
cd "$ROOT" || exit 1
mkdir -p "$HOME/.autoport-tmp"
export TMPDIR="${TMPDIR:-$HOME/.autoport-tmp}"

python3 - "$ROOT" <<'PY'
import ast, os, shutil, sys, tempfile

root = sys.argv[1]
AP = os.path.join(root, ".autoport")
sys.path.insert(0, AP)
sys.path.insert(0, os.path.join(AP, "lib"))
import backlog as B
import linear_sync as LS
if LS.B is not B:           # un seul module backlog, sinon les patches ne visent pas le bon
    B = LS.B

SEED_COMMIT = "69b8fee8f9"
SEEDED = r'''
def apply_owner_move(L, bl, iid, rec, here):
    """Un deplacement de ticket fait par l'owner est une DECISION : le backlog suit, et on le dit.
    Owner 17/09 : « si je change un status de ticket moi même […] ça serait con que ce soit systématiquement écrasé »."""
    it = bl.get(iid)
    if it is None:
        return bl
    today = dt.date.today().isoformat()
    s = it["status"]
    def top_priority():
        opens = [x.get("priority") for x in bl.items if x["status"] == "open" and isinstance(x.get("priority"), int)]
        return (min(opens) - 1) if opens else 0
    if here == "Done":
        if not it.get("owner_ok"):
            bl.validate(iid, "Déplacé en « Done » dans Linear par l'owner", date=today,
                        via={"source": "move", "ticket": rec["issue_id"]})
            _say(L, rec, "Passé Done par ton déplacement : c'est ton feu vert, enregistré tel quel.")
            if _TALK.get("ok"):
                swap_labels(L, rec["issue_id"], remove=_TALK["ok"])
    elif here == "Canceled":
        if s != "archived":
            bl.set_status(iid, "archived", notes=((it.get("notes") or "").rstrip() + "\n%s : archivé par l'owner dans Linear." % today).strip())
            _say(L, rec, "Archivé sur ton déplacement : le harnais ne le reprendra plus.")
    elif here == "À arbitrer":
        if s == "in-progress":
            bl.add_owner_feedback(iid, today, "[Linear] déplacé en « À arbitrer » pendant un essai : sera mis de côté à la fin de l'essai en cours",
                                  via={"source": "move", "ticket": rec["issue_id"]})
            _say(L, rec, "Un essai est en cours dessus ; je le bloque dès qu'il se termine, pas au milieu.")
        elif s != "blocked":
            bl.set_status(iid, "blocked", block_reason="Bloqué par l'owner dans Linear le %s" % today)
            _say(L, rec, "Bloqué sur ton déplacement : le harnais ne le prendra pas tant que tu ne le remets pas dans À faire ou Backlog.")
    elif here in ("Backlog", "Todo", "In Progress"):
        fields = {}
        if s in ("blocked", "to-test", "validated", "archived"):
            fields["status"] = "open"
            if s == "validated":
                fields["owner_ok"] = None
            if _TALK.get("ok"):
                swap_labels(L, rec["issue_id"], remove=_TALK["ok"])
        if here in ("Todo", "In Progress"):
            fields["priority"] = top_priority()
        if fields:
            status = fields.pop("status", s if s != "archived" else "open")
            if s in ("blocked", "to-test", "validated", "archived"):
                status = "open"
            bl.set_status(iid, status, **fields)
            msg = "Rouvert sur ton déplacement." if s != "open" else "Noté."
            if here in ("Todo", "In Progress"):
                msg += " Passé en tête de file : il démarre dès que l'essai en cours se termine (le harnais fait un chantier à la fois)."
            _say(L, rec, msg)
    elif here == "In Review":
        _say(L, rec, "In Review est posé par la machine quand une porte mesurée tient. Je le remets où le backlog le place ; si tu veux forcer, commente ce que tu attends.")
        rec["hash"] = ""  # recalage par la synchro
    bl = B.load()
    it = bl.get(iid)
    if it and it["status"] != "archived":
        try:
            refresh_prompt(it)
        except Exception as e:  # noqa: BLE001
            print("  prompt non refabrique pour %s : %s" % (iid, e))
    return bl


def adopt_owner_order(L, bl, mp, states, dry, skip=()):
    """Le pendant natif du rang = l'ordre manuel de la colonne Todo (sortOrder). Si l'owner reordonne
    a la main, le backlog adopte cet ordre : les rangs des eligibles sont permutes, rien d'autre ne bouge
    (owner 17/09, JAK-174 : « si ça pouvait être adapté programmatiquement ce serait encore mieux »)."""
    # 18/09 07:30 : un ticket CREE dans ce tour est place en tete de colonne par Linear lui-meme
    # (le `sortOrder` passe a la creation ne survit pas au reglage d'equipe). Sans l'exclusion, la
    # synchro lisait sa propre creation comme un geste de l'owner, ecrivait « owner a reordonne » et
    # permutait les rangs : la regression de la jauge est passee DERRIERE le ticket qui venait de
    # naitre. On n'adopte que l'ordre des tickets qui existaient AVANT ce tour.
    el = [i for i in bl.items if i["status"] == "open" and isinstance(i.get("priority"), int)
          and eligible(bl, i) and i["id"] in mp and i["id"] not in skip]
    if len(el) < 2:
        return 0
    ids = {mp[i["id"]]["issue_id"]: i for i in el}
    # 23/09 : sans `includeArchived`, un ticket archive manquait a la reponse et prenait le rang 0 (tete de
    # colonne) : un faux « owner a reordonne ». On le LIT, puis on l'ecarte : il n'est plus dans la colonne.
    d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:100, includeArchived:true){ nodes { id sortOrder archivedAt } } }', ids=list(ids))
    gone = {n["id"] for n in d["issues"]["nodes"] if n.get("archivedAt")}
    ids = {k: v for k, v in ids.items() if k not in gone}
    el = [i for i in el if mp[i["id"]]["issue_id"] not in gone]
    if len(el) < 2:
        return 0
    so = {n["id"]: n["sortOrder"] for n in d["issues"]["nodes"]}
    linear_order = [ids[k]["id"] for k in sorted(ids, key=lambda k: (so.get(k, 0), ids[k]["id"]))]
    backlog_order = [i["id"] for i in sorted(el, key=lambda i: (i["priority"], i["id"]))]
    if linear_order == backlog_order:
        return 0
    ranks = sorted(i["priority"] for i in el)
    print("  owner a reordonne la colonne Todo : le backlog adopte cet ordre : " + " > ".join(linear_order))
    if dry:
        return 1
    for iid, rank in zip(linear_order, ranks):
        it = bl.get(iid)
        if it["priority"] != rank:
            bl.set_status(iid, it["status"], priority=rank); bl = B.load(); refresh_prompt(bl.get(iid))
    return 1


def apply_owner_archive(bl, iid, rec, ev):
    """Owner 23/09 (« oui ouvre ») : un ticket de chantier VIVANT que l'owner archive lui-meme est sa DECISION, comme un
    deplacement en « Canceled ». On ne lui ecrit rien : tout message ressortirait le ticket des archives et defairait son
    geste. La synchro qui suit l'envoie en « Canceled » sans le ressortir (`revive` faux pour un etat clos)."""
    it = bl.get(iid)
    today = dt.date.today().isoformat()
    bl.set_status(iid, "archived", notes=((it.get("notes") or "").rstrip()
                                          + "\n%s : ticket archivé par l'owner dans Linear (%s) : chantier archivé." % (today, ev["createdAt"])).strip())
    rec["owner_archived_at"] = ev["createdAt"]
    print("ARCHIVAGE PAR L'OWNER APPLIQUE : %s %s (archive le %s) : %s -> archived ; aucun message (il ressortirait le ticket)"
          % (rec.get("identifier"), iid, ev["createdAt"], it["status"]))
    return B.load()
'''

ID = "harness-linear-owner-move-reads-fresh-item"
MSGS = []
unknown = []
OUT = {}


class FakeL:
    mode = "app"

    def __init__(self, nodes=None):
        self.nodes = nodes or []

    def q(self, *_a, **_k):
        return {"issues": {"nodes": self.nodes}}


# ----------------------------------------------------------------- Linear et prompts simules
LS._say = lambda L, rec, text: MSGS.append(text)
LS.swap_labels = lambda *a, **k: None
LS.refresh_prompt = lambda it: None
B.build_sha = lambda: "census-sha"
REAL = os.path.join(AP, "backlog.yaml")

SHIPPED = {k: getattr(LS, k) for k in ("apply_owner_move", "adopt_owner_order", "apply_owner_archive")}
_ns = dict(LS.__dict__)
exec(compile(SEEDED, "seeded-" + SEED_COMMIT, "exec"), _ns)
SEED = {k: _ns[k] for k in SHIPPED}


def fresh_copy():
    """Copie jetable REDUITE a deux items (le notre + un autre) : memes champs, meme chemin
    d'ecriture, sans relire 1 Mo de YAML a chaque chargement."""
    tmp = tempfile.mkdtemp(prefix="move-fresh-")
    T = os.path.join(tmp, "backlog.yaml")
    doc = dict(DOC0, items=[dict(x) for x in DOC0["items"]])
    with open(T, "w", encoding="utf-8") as fh:
        fh.write(B._dump(doc))
    B.DEFAULT_PATH = T      # le code d'avant recharge par `B.load()` sans chemin
    return tmp, T


_full = B._read(REAL)
_other = next(i for i in _full["items"] if i.get("id") != ID)
DOC0 = dict(_full, items=[next(i for i in _full["items"] if i.get("id") == ID), _other])
OTHER = _other["id"]
del _full


def setf(T, iid, **f):
    def ch(t, _items):
        t.update(f)
        return True
    B.load(T).update(iid, ch)


def add_note(T, iid, text):
    def ch(t, _items):
        t["notes"] = ((t.get("notes") or "") + "\n" + text).strip()
        return True
    B.load(T).update(iid, ch)


def it(T, iid=ID):
    return B.load(T).get(iid)


def validate(T):
    B.load(T).validate(ID, "FEU-VERT-OWNER", date="2026-09-23", sha="census-sha")


REC = {"issue_id": "census-ticket", "identifier": "JAK-0"}
EV = {"createdAt": "2026-09-23T00:00:00.000Z"}
BASE = dict(status="open", notes="NOTE-0", owner_ok=None, block_reason=None, depends_on=[], priority=5)
BLOCKED = dict(status="blocked", block_reason="census")
# colonne Todo : notre item DEVANT l'autre, l'inverse du backlog (6 contre 5). Il est reclasse le PREMIER : le code
# d'avant rechargeait apres chaque ecriture, seule la premiere portait la copie de debut de passe.
NODES = [{"id": "t-id", "sortOrder": 1.0, "archivedAt": None}, {"id": "t-o", "sortOrder": 2.0, "archivedAt": None}]


def move(here):
    return lambda F, b: F["apply_owner_move"](FakeL(), b, ID, dict(REC), here)


def archive(F, b):
    # l'appelant (pull) ne l'appelle que sur un item VIVANT dans SA copie
    if (b.get(ID) or {}).get("status") in LS.LIVE:
        F["apply_owner_archive"](b, ID, dict(REC), EV)


def rerank(F, b):
    F["adopt_owner_order"](FakeL(NODES), b, {ID: {"issue_id": "t-id"}, OTHER: {"issue_id": "t-o"}}, {}, False)


def judge(**checks):
    return lambda T: [n for n, f in checks.items() if f(it(T))]


def notes_have(tag):
    return lambda x: tag not in (x.get("notes") or "")


def said(word):
    return lambda _x: any(word in m for m in MSGS)


# (nom, etat initial de l'item, preparation hors course, ECRIVAIN FRAIS, reaction de la synchro, juge -> fautes)
SCEN = [
    ("canceled_note", {}, None, lambda T: add_note(T, ID, "NOTE-FRAICHE"), move("Canceled"),
     judge(note_lost=notes_have("NOTE-FRAICHE"), not_archived=lambda x: x["status"] != "archived")),
    ("canceled_already_archived", {}, None,
     lambda T: (setf(T, ID, status="archived"), add_note(T, ID, "ARCHIVE-SUPERVISEUR")), move("Canceled"),
     judge(note_lost=notes_have("ARCHIVE-SUPERVISEUR"), stale_message=said("Archivé"))),
    ("arbitrate_running", {}, None, lambda T: setf(T, ID, status="in-progress"), move("À arbitrer"),
     judge(status_reverted=lambda x: x["status"] != "in-progress",
           feedback_missing=lambda x: not any(isinstance(e, dict) and "À arbitrer" in (e.get("text") or "")
                                              for e in x.get("owner_feedback") or []))),
    ("backlog_running", BLOCKED, None, lambda T: setf(T, ID, status="in-progress"), move("Backlog"),
     judge(status_reverted=lambda x: x["status"] != "in-progress", stale_message=said("Rouvert"))),
    ("todo_rank", BLOCKED, None, lambda T: setf(T, OTHER, status="open", priority=-10 ** 6, depends_on=[]), move("Todo"),
     judge(rank_from_stale_copy=lambda x: x.get("priority") != -10 ** 6 - 1, not_reopened=lambda x: x["status"] != "open")),
    ("done_already_validated", {}, None, validate, move("Done"),
     judge(owner_ok_rewritten=lambda x: (x.get("owner_ok") or {}).get("text") != "FEU-VERT-OWNER",
           stale_message=said("Passé Done"))),
    ("archive_note", {}, None, lambda T: add_note(T, ID, "NOTE-FRAICHE"), archive,
     judge(note_lost=notes_have("NOTE-FRAICHE"), not_archived=lambda x: x["status"] != "archived")),
    ("archive_validated", {}, None, validate, archive,
     judge(status_overwritten=lambda x: x["status"] != "validated")),
    ("rerank_running", dict(priority=6), lambda T: setf(T, OTHER, status="open", priority=5, depends_on=[]),
     lambda T: setf(T, ID, status="in-progress"), rerank,
     judge(status_reverted=lambda x: x["status"] != "in-progress")),
]


def run(side, mode, sc):
    name, init, pre, writer, react, jg = sc
    F = SHIPPED if side == "shipped" else SEED
    tmp, T = fresh_copy()
    MSGS.clear()
    try:
        setf(T, ID, **dict(BASE, **init))
        if pre:
            pre(T)
        if mode == "stale":          # la synchro charge, PUIS un autre ecrivain passe, PUIS elle reagit
            b = B.load(T)
            writer(T)
        else:                        # NEGATIF : aucun recouvrement, la synchro charge apres l'ecrivain
            writer(T)
            b = B.load(T)
        react(F, b)
        return jg(T)
    except Exception as e:  # noqa: BLE001 — INCONNU = DEFAUT
        unknown.append("%s/%s/%s:%s" % (side, mode, name, type(e).__name__))
        print("# %s/%s/%s : %r" % (side, mode, name, e), file=sys.stderr)
        return None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
        B.DEFAULT_PATH = REAL


res = {}
for side in ("shipped", "seeded"):
    for mode in ("stale", "sequential"):
        for sc in SCEN:
            res[(side, mode, sc[0])] = run(side, mode, sc)


def rerank_functional():
    """Hors course : l'ordre de la colonne est-il toujours ADOPTE ? (le correctif ne doit pas l'eteindre)"""
    tmp, T = fresh_copy()
    try:
        setf(T, ID, **dict(BASE, priority=6))
        setf(T, OTHER, status="open", priority=5, depends_on=[])
        rerank(SHIPPED, B.load(T))
        return it(T).get("priority") == 5 and it(T, OTHER).get("priority") == 6 and it(T)["status"] == "open"
    except Exception as e:  # noqa: BLE001
        unknown.append("shipped/functional/rerank:%s" % type(e).__name__)
        return False
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
        B.DEFAULT_PATH = REAL


FUNCTIONAL_OK = rerank_functional()


def faulty(side, mode):
    return [n for (s, m, n), r in res.items() if s == side and m == mode and r]


L_ = faulty("shipped", "stale")
N_ = faulty("shipped", "sequential") + ["seeded:" + n for n in faulty("seeded", "sequential")]
dead = [n for n, *_ in SCEN if res[("seeded", "stale", n)] is not None and not res[("seeded", "stale", n)]]
OUT["linear_sync_stale_scenarios"] = len(SCEN)
OUT["linear_sync_stale_shipped_faulty"] = len(L_)
OUT["linear_sync_stale_shipped_faulty_named"] = ",".join(L_) or "-"
for (s, m, n), r in sorted(res.items()):
    if s == "shipped" and m == "stale":
        OUT["linear_sync_stale_%s" % n] = "ERR" if r is None else (",".join(r) or "ok")
OUT["linear_sync_stale_negative_faulty"] = len(N_)
OUT["linear_sync_stale_negative_faulty_named"] = ",".join(N_) or "-"
OUT["linear_sync_stale_seeded_commit"] = SEED_COMMIT
OUT["linear_sync_stale_seeded_reddened"] = sum(1 for n, *_ in SCEN if res[("seeded", "stale", n)])
OUT["linear_sync_stale_seeded_named"] = ",".join("%s:%s" % (n, "+".join(res[("seeded", "stale", n)]))
                                                  for n, *_ in SCEN if res[("seeded", "stale", n)]) or "-"

# ----------------------------------------------------------------- W : recensement statique (AST)
WRITERS = {"set_status", "update", "add_owner_feedback", "validate", "set_feedback_via", "set_scope", "_atomic_write"}


def census_calls(src, label):
    tree = ast.parse(src)
    sites = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in WRITERS:
            recv = ast.unparse(node.func.value)
            if node.func.attr == "validate" and recv not in ("bl", "self"):
                continue
            if node.func.attr == "update" and recv != "bl":
                continue
            if node.func.attr == "_atomic_write" and recv != "B":
                continue
            sites.append((node.lineno, node.func.attr))
    return sorted(sites)


with open(os.path.join(AP, "linear_sync.py"), encoding="utf-8") as fh:
    sites = census_calls(fh.read(), "shipped")
stale_sites = [s for s in sites if s[1] == "set_status"]
seed_sites = [s for s in census_calls(SEEDED, "seeded") if s[1] == "set_status"]
OUT["linear_sync_backlog_write_sites"] = len(sites)
OUT["linear_sync_backlog_write_sites_named"] = ",".join("%d:%s" % s for s in sites) or "-"
OUT["linear_sync_backlog_set_status_calls"] = len(stale_sites)
OUT["linear_sync_backlog_set_status_named"] = ",".join("%d" % s[0] for s in stale_sites) or "-"
OUT["linear_sync_stale_seeded_set_status_calls"] = len(seed_sites)
if not seed_sites:
    dead.append("static_set_status")

OUT["linear_sync_stale_dead_controls"] = len(dead)
OUT["linear_sync_stale_dead_named"] = ",".join(dead) or "-"
OUT["linear_sync_stale_unknown"] = len(unknown)
OUT["linear_sync_stale_unknown_named"] = ",".join(unknown) or "-"
OUT["linear_sync_stale_rerank_functional"] = "ok" if FUNCTIONAL_OK else "ECHEC"
total = len(L_) + len(N_) + len(stale_sites) + len(dead) + len(unknown) + (0 if FUNCTIONAL_OK else 1)
for k, v in OUT.items():
    print("%s=%s" % (k, v))
print("linear_sync_stale_item_writes=%d" % total)
PY
