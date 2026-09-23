#!/usr/bin/env bash
# census/harness-linear-owner-moves-never-lost.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `owner_moves_lost`.
# Il n'ecrit rien dans le vrai backlog ni sur Linear : backlog = copie jetable, Linear = faux en memoire.
#
# LE DEFAUT (23/09, signale par quatre workers) :
#   1. `push_existing` renvoyait l'etat a CHAQUE mise a jour, meme de simple description, sans relire le ticket : un
#      deplacement de l'owner fait entre le tirage (`pull_owner`) et l'envoi du meme passage etait ECRASE, et perdu.
#   2. `owner_move` sous le repli « cle de l'owner » : un vrai deplacement sans `state_at` n'etait pas applique
#      (auteur indistinguable) et n'etait dit a personne : PERDU.
#   3. carte ET cliche reculés sous le `state_at` : un deplacement deja applique etait RE-APPLIQUE (priorite remise
#      en tete, « Noté. » repete).
#
# CE QU'IL MESURE — `owner_moves_lost` = ecrases + perdus + re-appliques, sur le code LIVRE, dans un monde simule
# (faux Linear avec historique signe et horodate, vrai module rejoue depuis son source, vrai `Backlog` sur une copie) :
#   S1   l'owner deplace le ticket entre le tirage et l'envoi d'un CHANGEMENT d'etat
#   S1b  meme fenetre, l'envoi n'est qu'une retouche de description
#   S2   l'owner deplace le ticket entre la RELECTURE et l'ecriture (fenetre residuelle, dans la mutation meme)
#   S3   repli sous la cle de l'owner, vrai deplacement sans `state_at` : doit etre applique ou NOMME, une seule fois
#   S4   deplacement applique, puis carte reculee (fiche du ticket remise a l'avant-passage) : jamais refait
# CONTROLES NEGATIFS (cas sains, chacun compte ses ecarts) : S5 (identite app) et S6 (repli owner) : un vrai
# deplacement fait AVANT le tirage est applique UNE fois, un changement d'etat du backlog est bien pose, rien n'est
# differe, rattrape ni nomme a tort.
# CONTROLES POSITIFS : chaque garde retiree d'une copie du source doit rougir SON scenario et le NOMMER, sinon mort.
# INCONNU = DEFAUT : un scenario qui leve compte 1 ; un controle mort compte 1.
# Informatif (hors somme) : le code d'AVANT, epingle au commit e24135c281, sur les memes scenarios.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "owner_moves_lost=99"; exit 1; }
cd "$ROOT" || exit 1
mkdir -p "$HOME/.autoport-tmp"
export TMPDIR="${TMPDIR:-$HOME/.autoport-tmp}"

python3 - <<'PY'
import copy, datetime as dt, io, os, re, shutil, subprocess, sys, tempfile, types
from contextlib import redirect_stdout
from pathlib import Path
sys.path.insert(0, '.autoport')
from lib import backlog as B

B.build_sha = lambda: "census-sha"
OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
unmeasured, dead = [], []
SRC_PATH = Path(".autoport/linear_sync.py")
SRC = SRC_PATH.read_text()
BEFORE_COMMIT = "e24135c281"
OWNER, APP = "u-owner", "u-app"
SID = {n: "s-" + n for n in ("Backlog", "Todo", "In Progress", "In Review", "À arbitrer", "Done", "Canceled")}
NAME_OF = {v: k for k, v in SID.items()}
OLD = "2026-09-22T00:00:00.000Z"


def load_variant(src, seeds=()):
    missing = []
    for old, new in seeds:
        if src.count(old) != 1:
            missing.append(old.strip()[:40])
        src = src.replace(old, new)
    m = types.ModuleType("linear_sync_sim")
    m.__file__ = str(SRC_PATH.resolve())
    exec(compile(src, "linear_sync_sim", "exec"), m.__dict__)
    return m, missing


class World:
    """Le Linear simule : etat, historique signe (owner / app) et horodate, commentaires, fenetre de concurrence."""
    def __init__(self, mode):
        self.mode, self.issues, self.comments, self.window, self.n, self._t = mode, {}, [], {}, 0, None

    def stamp(self):
        now = dt.datetime.now(dt.timezone.utc)
        now = now.replace(microsecond=now.microsecond // 1000 * 1000)   # Linear date a la ms : deux evenements, deux ms
        if self._t and now <= self._t:
            now = self._t + dt.timedelta(milliseconds=1)
        self._t = now
        return now.strftime("%Y-%m-%dT%H:%M:%S.") + "%03dZ" % (now.microsecond // 1000)

    def add(self, tid, state):
        self.issues[tid] = {"state": state, "history": []}

    def ev(self, tid, to, by, when=None):
        """`by` = VERITE du census (owner | harness) ; la signature suit l'identite : sous le repli, le harnais signe owner."""
        self.n += 1
        signed_owner = by == "owner" or self.mode != "app"
        e = {"id": "ev-%s-%d" % (tid, self.n), "createdAt": when or self.stamp(), "toState": {"name": to},
             "actor": {"id": OWNER, "app": False} if signed_owner else {"id": APP, "app": True},
             "botActor": None, "archived": None, "autoArchived": False, "_by": by}
        self.issues[tid]["history"].append(e)
        self.issues[tid]["state"] = to
        return e


class FakeL:
    def __init__(self, w):
        self.w, self.mode, self.n = w, w.mode, 0

    def q(self, query, **v):
        self.n += 1
        if query.lstrip().startswith("mutation"):
            kind = re.search(r"\{\s*(\w+)\(", query).group(1)
            if kind == "issueUpdate":
                tid, i = v["id"], v["i"]
                if tid in self.w.window:        # l'owner deplace le ticket PENDANT l'envoi
                    self.w.ev(tid, self.w.window.pop(tid), "owner")
                if "stateId" in i and self.w.issues[tid]["state"] != NAME_OF[i["stateId"]]:
                    self.w.ev(tid, NAME_OF[i["stateId"]], "harness")
                return {kind: {"success": True}}
            if kind == "commentCreate":
                self.w.comments.append((v["i"]["issueId"], v["i"]["body"]))
                return {kind: {"success": True, "comment": {"id": "c-%d" % len(self.w.comments)}}}
            return {kind: {"success": True}}
        if "history(" in query:
            nodes = sorted((dict((k, x) for k, x in e.items() if k != "_by") for e in self.w.issues[v["id"]]["history"]),
                           key=lambda e: e["createdAt"], reverse=True)
            return {"issue": {"history": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": nodes}}}
        if "issues(filter:{id:{in:$ids}}" in query.replace(" ", ""):
            return {"issues": {"nodes": [{"id": t, "archivedAt": None, "state": {"name": x["state"]}, "labels": {"nodes": []},
                                          "comments": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": []}}
                                         for t, x in self.w.issues.items() if t in v["ids"]]}}
        raise RuntimeError("faux Linear : requete inattendue : " + query[:60])


class Scene:
    def __init__(self, src, seeds, mode, items, tickets):
        self.m, self.missing = load_variant(src, seeds)
        self.tmp = tempfile.mkdtemp(prefix="owner-moves-")
        self.path = os.path.join(self.tmp, "backlog.yaml")
        base = {"feature": "sim", "prompt": "prompts/none.md", "depends_on": [], "owner_feedback": [], "notes": ""}
        with open(self.path, "w", encoding="utf-8") as fh:
            fh.write(B._dump({"version": 1, "items": [dict(base, **x) for x in items]}))
        self.w = World(mode)
        self.L = FakeL(self.w)
        self.mp = {"_owner": {"user_id": OWNER}}
        for iid, (tid, state, rec) in tickets.items():
            self.w.add(tid, state)
            self.mp[iid] = dict({"issue_id": tid, "identifier": "SIM-" + iid.upper(), "last_state": state, "hash": "x",
                                 "pulled_at": "2026-09-20T00:00:00Z"}, **rec)
        m = self.m
        m.refresh_prompt = lambda it: None
        m.post_comment = lambda L, issue_id, body, parent=None, capture_failed="": L.q(
            'mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success comment { id } } }',
            i={"issueId": issue_id, "body": body})
        m._CTX.update(mp=self.mp)
        if hasattr(m, "PUSH_GUARD"):
            del m.PUSH_GUARD[:]

    def set(self, iid, **f):
        def ch(t, _items):
            t.update(f)
            return True
        B.load(self.path).update(iid, ch)

    def item(self, iid):
        return B.load(self.path).get(iid)

    def one_pass(self, after_pull=None, tag="", pull=True, push=True):
        m = self.m
        bl = B.load(self.path)
        m._CTX.update(bl=bl, mp=self.mp)
        with redirect_stdout(self.log):
            if pull:
                m.pull_owner(self.L, bl, self.mp, {}, False)
            if after_pull:
                after_pull()
            if not push:
                return
            bl = B.load(self.path)
            m._CTX["bl"] = bl
            for it in bl.items:
                rec = self.mp.get(it["id"])
                if not rec:
                    continue
                st = m.target_state(bl, it)
                h = "%s|%s|%s|%s" % (st, it["status"], it.get("priority"), tag)
                if rec.get("hash") == h:
                    continue
                m.push_existing(self.L, bl, it, rec, {"stateId": SID[st], "description": "d" + tag}, st, h, None, None)

    def comments(self, tid):
        return [b for t, b in self.w.comments if t == tid]

    def harness_after(self, tid, e):
        return [x for x in self.w.issues[tid]["history"] if x["_by"] == "harness" and x["createdAt"] > e["createdAt"]]

    def close(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    log = None


def verdict_effect(sc, iid, tid, G, want):
    """-> [] ou ['<scenario>:ecrase'|'<scenario>:perdu'] : l'effet du deplacement G est-il dans le backlog ?"""
    if sc.item(iid)["status"] == want:
        return []
    return ["%s:ecrase" % iid.upper()] if sc.harness_after(tid, G) else ["%s:perdu" % iid.upper()]


# ------------------------------------------------------------------ les scenarios : (sc, [fautes], infos)
def s1(src, seeds):
    sc = Scene(src, seeds, "app", [{"id": "s1", "status": "blocked", "block_reason": "sim", "priority": 5}],
               {"s1": ("t1", "À arbitrer", {"state_at": OLD})})
    sc.set("s1", status="open")          # le superviseur rouvre : la synchro va poser Todo
    G = {}
    sc.one_pass(after_pull=lambda: G.update(e=sc.w.ev("t1", "Canceled", "owner")))
    sc.one_pass(); sc.one_pass()
    return sc, verdict_effect(sc, "s1", "t1", G["e"], "archived")


def s1b(src, seeds):
    sc = Scene(src, seeds, "app", [{"id": "s1b", "status": "open", "priority": 6}], {"s1b": ("t1b", "Todo", {"state_at": OLD})})
    G = {}
    sc.one_pass(after_pull=lambda: G.update(e=sc.w.ev("t1b", "Canceled", "owner")), tag="1")
    sc.one_pass(tag="2"); sc.one_pass(tag="3")
    return sc, verdict_effect(sc, "s1b", "t1b", G["e"], "archived")


def s2(src, seeds):
    sc = Scene(src, seeds, "app", [{"id": "s2", "status": "blocked", "block_reason": "sim", "priority": 5}],
               {"s2": ("t2", "À arbitrer", {"state_at": OLD})})
    sc.set("s2", status="open")
    sc.w.window["t2"] = "Canceled"       # l'owner deplace le ticket au moment meme de notre ecriture
    sc.one_pass(); sc.one_pass(); sc.one_pass()
    G = next(e for e in sc.w.issues["t2"]["history"] if e["_by"] == "owner")
    return sc, verdict_effect(sc, "s2", "t2", G, "archived")


def s3(src, seeds):
    sc = Scene(src, seeds, "owner", [{"id": "s3", "status": "open", "priority": 5}], {"s3": ("t3", "Todo", {})})
    sc.w.ev("t3", "Canceled", "owner", when="2026-09-23T01:00:00.000Z")
    rec0 = copy.deepcopy(sc.mp["s3"])
    sc.one_pass(push=False)
    sc.mp["s3"] = copy.deepcopy(rec0)    # carte reculee entre deux tirages : le nom ne se repete pas
    sc.one_pass(); sc.one_pass()
    named = [b for b in sc.comments("t3") if "« Canceled »" in b]
    bad = []
    if sc.item("s3")["status"] != "archived" and not named:
        bad.append("S3:perdu")
    bad += ["S3:nomme_%dx" % len(named)] * (len(named) - 1 if len(named) > 1 else 0)
    return sc, bad


def s4(src, seeds):
    sc = Scene(src, seeds, "app", [{"id": "s4", "status": "blocked", "block_reason": "sim", "priority": 7},
                                   {"id": "s4o", "status": "open", "priority": 10}],
               {"s4": ("t4", "À arbitrer", {"state_at": OLD})})
    sc.w.ev("t4", "Todo", "owner")
    rec0 = copy.deepcopy(sc.mp["s4"])
    sc.one_pass()
    bad = [] if sc.item("s4")["status"] == "open" else ["S4:perdu"]
    p1, c1 = sc.item("s4")["priority"], len(sc.comments("t4"))
    sc.mp["s4"] = rec0                   # carte ET cliche reculés : la fiche du ticket revient a l'avant-passage
    sc.set("s4o", priority=3)            # une re-application se lirait sur le rang (tete = 2)
    sc.one_pass(); sc.one_pass()
    if sc.item("s4")["priority"] != p1 or len(sc.comments("t4")) != c1:
        bad.append("S4:reapplique")
    return sc, bad


def s5(src, seeds):
    """NEGATIF app : a = vrai deplacement avant le tirage ; b = changement du backlog a poser ; c = calme."""
    sc = Scene(src, seeds, "app", [{"id": "a", "status": "open", "priority": 5}, {"id": "b", "status": "open", "priority": 6},
                                   {"id": "c", "status": "open", "priority": 7}],
               {"a": ("ta", "Todo", {"state_at": OLD}), "b": ("tb", "Todo", {"state_at": OLD}), "c": ("tc", "Todo", {"state_at": OLD})})
    sc.w.ev("ta", "Canceled", "owner")
    sc.set("b", status="in-progress")
    for k in "123":
        sc.one_pass(tag=k)
    bad = []
    if sc.item("a")["status"] != "archived":
        bad.append("S5:a_non_applique")
    if (sc.item("a").get("notes") or "").count("archivé par l'owner") != 1:
        bad.append("S5:a_applique_%dx" % (sc.item("a").get("notes") or "").count("archivé par l'owner"))
    if sc.w.issues["tb"]["state"] != "In Progress":
        bad.append("S5:b_etat_non_pose")
    if [e for e in sc.w.issues["tc"]["history"] if e["_by"] == "harness"]:
        bad.append("S5:c_etat_reecrit")
    if sc.item("b")["status"] != "in-progress" or sc.item("c")["status"] != "open":
        bad.append("S5:backlog_touche")
    g = getattr(sc.m, "PUSH_GUARD", [])
    bad += ["S5:%s" % x["kind"] for x in g]
    bad += ["S5:nomme" for mv in sc.m.MOVES if mv.get("named")]
    return sc, bad


def s6(src, seeds):
    """NEGATIF repli owner : r = vrai deplacement apres `state_at` ; q = changement du backlog, signe owner par le harnais."""
    sc = Scene(src, seeds, "owner", [{"id": "r", "status": "open", "priority": 5}, {"id": "q", "status": "open", "priority": 6}],
               {"r": ("tr", "Todo", {"state_at": OLD}), "q": ("tq", "Todo", {"state_at": OLD})})
    sc.w.ev("tr", "Canceled", "owner")
    sc.set("q", status="in-progress")
    for k in "123":
        sc.one_pass(tag=k)
    bad = []
    if sc.item("r")["status"] != "archived":
        bad.append("S6:r_non_applique")
    if sc.item("q")["status"] != "in-progress" or sc.w.issues["tq"]["state"] != "In Progress":
        bad.append("S6:q_faux")
    bad += ["S6:%s" % x["kind"] for x in getattr(sc.m, "PUSH_GUARD", [])]
    bad += ["S6:nomme" for c in sc.w.comments if "je parlais sous ton nom" in c[1]]
    return sc, bad


FAULTS = {"S1": s1, "S1B": s1b, "S2": s2, "S3": s3, "S4": s4}
NEG = {"S5": s5, "S6": s6}


def play(fn, src, seeds=()):
    sc = None
    try:
        buf = io.StringIO()
        Scene.log = buf
        sc, bad = fn(src, seeds)
        return bad, sc.missing, sc
    except Exception as e:  # noqa: BLE001 — INCONNU = DEFAUT
        return ["%s:erreur_%s" % (fn.__name__.upper(), type(e).__name__)], [], sc
    finally:
        if sc:
            sc.close()


# ------------------------------------------------------------------ code LIVRE
lost = 0
names, guard_kinds = [], []
for tag, fn in FAULTS.items():
    bad, _, sc = play(fn, SRC)
    pub("owner_moves_%s" % tag.lower(), len(bad))
    if sc is not None:
        guard_kinds += ["%s:%s" % (tag, x["kind"]) for x in sc.m.PUSH_GUARD]
        guard_kinds += ["%s:nomme" % tag for x in sc.m.MOVES if x.get("named")]
    names += bad
    lost += len(bad)
pub("owner_moves_shipped_named", ",".join(names) or "-")
pub("owner_moves_guard_actions", ",".join(guard_kinds) or "-")
pub("owner_moves_overwritten", sum(1 for n in names if n.endswith(":ecrase")))
pub("owner_moves_dropped", sum(1 for n in names if n.endswith(":perdu") or ":erreur" in n))
pub("owner_moves_reapplied", sum(1 for n in names if ":reapplique" in n or ":nomme_" in n))

neg_bad = 0
for tag, fn in NEG.items():
    bad, _, _sc = play(fn, SRC)
    pub("owner_moves_ctl_neg_%s" % tag.lower(), len(bad))
    pub("owner_moves_ctl_neg_%s_named" % tag.lower(), ",".join(bad) or "-")
    neg_bad += len(bad)
pub("owner_moves_scenarios", "%d_fautifs+%d_sains" % (len(FAULTS), len(NEG)))
pub("owner_moves_genuine", 7)   # un vrai deplacement de l'owner par scenario, deux de plus dans les sains (a, r)

# ------------------------------------------------------------------ CONTROLES POSITIFS : chaque garde retiree
POS = {
    "relecture": ([('        if now_state is not None and now_state != rec["last_state"]:\n', '        if False:\n')], s1, "S1:ecrase"),
    "etat_omis": ([('        payload = {k: v for k, v in payload.items() if k != "stateId"}\n', '        pass\n')], s1b, "S1B:ecrase"),
    "apres_coup": ([('        ours_at, caught = catch_overwritten(L, bl, it["id"], rec, st, seen)\n',
                     '        ours_at, caught = None, None\n')], s2, "S2:ecrase"),
    "nom": ([('                if not mv and why.startswith(AMBIGUOUS) and not dry:\n', '                if False:\n')], s3, "S3:perdu"),
    "trace": ([('        if ev_id in moves_traced(t):\n            return ("already", t.get("status"))\n',
                '        if False:\n            return ("already", t.get("status"))\n'),
               ('                if mv and mv.get("id") and mv["id"] in moves_traced(bl.get(iid)):\n', '                if False:\n')],
              s4, "S4:reapplique"),
}
for tag, (seeds, fn, want) in POS.items():
    bad, missing, _sc = play(fn, SRC, seeds)
    pub("owner_moves_ctl_pos_%s" % tag, len(bad))
    pub("owner_moves_ctl_pos_%s_named" % tag, ",".join(bad) or "-")
    if missing:
        dead.append("C+_%s:introuvable" % tag)
    elif not any(b.startswith(want) and ":erreur" not in b for b in bad):
        dead.append("C+_%s:muet" % tag)

# ------------------------------------------------------------------ AVANT (informatif) : le code du commit epingle
try:
    old_src = subprocess.run(["git", "show", "%s:.autoport/linear_sync.py" % BEFORE_COMMIT], capture_output=True,
                             text=True, check=True).stdout
    before = []
    for tag, fn in FAULTS.items():
        bad, _, _sc = play(fn, old_src)
        before += bad
    pub("owner_moves_before_commit", BEFORE_COMMIT)
    pub("owner_moves_before_lost", len(before))
    pub("owner_moves_before_named", ",".join(before) or "-")
except Exception as e:  # noqa: BLE001
    pub("owner_moves_before_error", str(e)[:120])

pub("owner_moves_ctl_neg_bad", neg_bad)
pub("owner_moves_controls_dead", ",".join(dead) or "-")
pub("owner_moves_unmeasured", ",".join(unmeasured) or "-")
pub("owner_moves_lost", lost + neg_bad + len(dead) + len(unmeasured))
for k_, v in OUT.items():
    print("%s=%s" % (k_, v))
PY
