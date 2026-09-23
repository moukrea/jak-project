#!/usr/bin/env bash
# census/harness-linear-stale-map-never-fakes-an-owner-move.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `fake_owner_moves`.
#
# LE DEFAUT (23/09 00:19:47) : un `git reset` a fait reculer `linear_map.json` ; le `last_state` qu'il portait
# etait perime. Au passage suivant, l'ecart entre ce `last_state` perime et l'etat REEL du ticket a ete pris pour
# un deplacement de l'owner : DEUX ont ete appliques ce soir-la (`harness-x86-proof-for-a-device-item-must-shout-at-launch`
# Todo -> In Progress, `harness-supervisor-death-is-an-alarm` In Progress -> In Review) alors que personne n'avait
# touche a ces tickets. `owner_move` (linear_sync.py) lit desormais l'historique du ticket (seule source qui dise
# QUI a change l'etat) et exige que l'evenement soit posterieur a `state_at`, la date du dernier passage qui a pose
# ou constate cet etat — la carte seule ne prouve plus rien.
#
# CE QU'IL MESURE — `fake_owner_moves` = somme de :
#   S   SIMULE, code livre : faux Linear en memoire, le vrai `owner_move`/`pull_owner` (rejoues depuis le source),
#       une carte perimee (sans `state_at`, ou reculee) contre un historique qui dit qui a VRAIMENT bouge l'etat.
#       Chaque deplacement APPLIQUE dont la verite terrain (posee independamment dans ce census) dit « pas l'owner »
#       compte 1, NOMME.
#   V1  VIVANT, carte telle quelle : rejeu en lecture seule de `pull_owner` sur la vraie carte ; chaque deplacement
#       qu'il dit APPLIQUE est rejuge par un juge INDEPENDANT (meme requete d'historique, critere ecrit ici) ; non
#       prouve = fake.
#   V2  VIVANT, carte RECULEE fabriquee (state_at retire, last_state remis en arriere) sur jusqu'a 40 tickets +
#       les deux tickets du 23/09 : meme rejeu, meme juge independant. Le CONTROLE POSITIF VIVANT rejoue le meme
#       monde avec l'ancienne regle (tout ecart = l'owner) et doit rougir.
#   CONTROLES POSITIFS (S) : le defaut SEME dans une copie du source (regle d'avant, auteur ignore, cle ignoree,
#   anteriorite ignoree) doit rougir ET NOMMER, sinon mort.
#   INCONNU = DEFAUT : un terme non mesure compte 1 ; un controle mort (introuvable ou muet) compte 1.
#
# Hors somme, informatif : V3 relit `logs/linear_sync.txt` pour les deux deplacements du 23/09 et confirme, par le
# meme juge independant sur l'historique reel, qu'ils ne sont pas prouves owner (ce n'est pas une exigence de porte).
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "fake_owner_moves=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import copy, datetime as dt, io, re, sys, types
from contextlib import redirect_stdout
from pathlib import Path
sys.path.insert(0, '.autoport')

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
unmeasured, dead = [], []
SRC_PATH = Path(".autoport/linear_sync.py")
SRC = SRC_PATH.read_text()
OWNER_KEY_UNTIL = "2026-09-18T00:00:00.000Z"


def load_variant(seeds):
    """Le module `linear_sync` REEL, rejoue depuis son source avec les remplacements `seeds`.
    Un remplacement introuvable = controle MORT (le code a change sous lui)."""
    src, missing = SRC, []
    for old, new in seeds:
        if src.count(old) != 1:
            missing.append(old.strip()[:40])
        src = src.replace(old, new)
    m = types.ModuleType("linear_sync_sim")
    m.__file__ = str(SRC_PATH.resolve())
    exec(compile(src, "linear_sync_sim", "exec"), m.__dict__)
    return m, missing


def independent_owner_proof(hist, owner_id, to_state, after):
    """Juge INDEPENDANT (n'appelle rien de `linear_sync`) : le DERNIER evenement d'historique portant `toState` va
    vers `to_state`, signe par l'humain `owner_id` (pas une app, pas un bot), et posterieur a `after`."""
    mv = next((e for e in hist if e.get("toState")), None)
    if not mv or mv["toState"]["name"] != to_state:
        return False
    if (mv.get("botActor") or {}).get("id"):
        return False
    actor = mv.get("actor") or {}
    if actor.get("app"):
        return False
    if actor.get("id") != owner_id:
        return False
    if mv.get("createdAt", "") <= after:
        return False
    return True


# ============================================================================== S : SIMULE ==
OWNER, APP = "u-owner", "u-app"


def ev(to_state, when, who):
    actor = {"id": OWNER, "app": False} if who == "owner" else {"id": APP, "app": True}
    return {"createdAt": when, "toState": {"name": to_state}, "actor": actor, "botActor": None,
            "archived": None, "autoArchived": False}


# iid -> (truth_owner_move, backlog_item_or_None)
def sim_world():
    issues = {
        "sim-stale": {"identifier": "SIM-STALE", "state": "In Progress", "archivedAt": None,
                      "history": [ev("Todo", "2026-09-22T09:00:00.000Z", "app"),
                                  ev("In Progress", "2026-09-23T00:10:00.000Z", "app")]},
        "sim-prekey": {"identifier": "SIM-PREKEY", "state": "In Review", "archivedAt": None,
                       "history": [ev("In Review", "2026-09-16T10:00:00.000Z", "owner")]},
        "sim-arch": {"identifier": "SIM-ARCH", "state": "Todo", "archivedAt": "2026-09-21T10:05:00.000Z",
                     "history": [ev("Todo", "2026-09-21T10:00:00.000Z", "app")]},
        "sim-noev": {"identifier": "SIM-NOEV", "state": "Todo", "archivedAt": None, "history": []},
        "sim-over": {"identifier": "SIM-OVER", "state": "Todo", "archivedAt": None,
                     "history": [ev("Canceled", "2026-09-22T08:00:00.000Z", "owner"),
                                 ev("Todo", "2026-09-22T08:05:00.000Z", "app")]},
        "sim-real": {"identifier": "SIM-REAL", "state": "Canceled", "archivedAt": None,
                     "history": [ev("Canceled", "2026-09-22T12:00:00.000Z", "owner")]},
        "sim-calm": {"identifier": "SIM-CALM", "state": "Todo", "archivedAt": None, "history": []},
    }
    mp = {"_owner": {"user_id": OWNER},
          "sim-stale": {"issue_id": "sim-stale", "identifier": "SIM-STALE", "last_state": "Todo", "hash": "x"},
          "sim-prekey": {"issue_id": "sim-prekey", "identifier": "SIM-PREKEY", "last_state": "Todo", "hash": "x"},
          "sim-arch": {"issue_id": "sim-arch", "identifier": "SIM-ARCH", "last_state": "Done", "hash": "x"},
          "sim-noev": {"issue_id": "sim-noev", "identifier": "SIM-NOEV", "last_state": "Backlog", "hash": "x"},
          "sim-over": {"issue_id": "sim-over", "identifier": "SIM-OVER", "last_state": "Canceled", "hash": "x"},
          "sim-real": {"issue_id": "sim-real", "identifier": "SIM-REAL", "last_state": "Todo", "hash": "x",
                       "state_at": "2026-09-22T00:00:00.000Z"},
          "sim-calm": {"issue_id": "sim-calm", "identifier": "SIM-CALM", "last_state": "Todo", "hash": "x"}}
    items = [{"id": "sim-real", "status": "open", "feature": "sim real", "owner_feedback": []}]
    truth = {"sim-stale": False, "sim-prekey": False, "sim-arch": False, "sim-noev": False,
             "sim-over": False, "sim-real": True, "sim-calm": False}
    return issues, mp, items, truth


def owner_world():
    """Passe mode owner (repli sous la cle personnelle) : SIM-OWNKEY (le push a deja pose `state_at` sur le meme
    evenement, le repli ne doit pas le reappliquer) et SIM-REAL2 (le repli prouve quand meme un VRAI deplacement)."""
    issues = {
        "sim-ownkey": {"identifier": "SIM-OWNKEY", "state": "In Progress", "archivedAt": None,
                       "history": [ev("In Progress", "2026-09-22T10:00:00.000Z", "owner")]},
        "sim-real2": {"identifier": "SIM-REAL2", "state": "Canceled", "archivedAt": None,
                      "history": [ev("Canceled", "2026-09-22T12:00:00.000Z", "owner")]},
    }
    mp = {"_owner": {"user_id": OWNER},
          "sim-ownkey": {"issue_id": "sim-ownkey", "identifier": "SIM-OWNKEY", "last_state": "Todo", "hash": "x",
                         "state_at": "2026-09-22T10:00:05.000Z"},
          "sim-real2": {"issue_id": "sim-real2", "identifier": "SIM-REAL2", "last_state": "Todo", "hash": "x",
                        "state_at": "2026-09-22T00:00:00.000Z"}}
    items = [{"id": "sim-real2", "status": "open", "feature": "sim real2", "owner_feedback": []}]
    truth = {"sim-ownkey": False, "sim-real2": True}
    return issues, mp, items, truth


class FakeL:
    def __init__(self, issues, mode="app"):
        self.issues, self.mode, self.n, self.history_calls = issues, mode, 0, []

    def q(self, query, **v):
        self.n += 1
        q1 = query.replace(" ", "")
        if query.lstrip().startswith("mutation"):
            return {"commentCreate": {"success": True, "comment": {"id": "c-fake"}}}
        if "issues(filter:{id:{in:$ids}}" in q1:
            nodes = []
            for i, x in self.issues.items():
                if i not in v["ids"]:
                    continue
                nodes.append({"id": i, "archivedAt": x["archivedAt"], "state": {"name": x["state"]},
                              "labels": {"nodes": []},
                              "comments": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": []}})
            return {"issues": {"nodes": nodes}}
        if "history(" in query:
            self.history_calls.append(v["id"])
            return {"issue": {"history": {"pageInfo": {"hasNextPage": False, "endCursor": None},
                                          "nodes": copy.deepcopy(self.issues[v["id"]]["history"])}}}
        if "comments(first:100" in q1:
            return {"issue": {"comments": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": []}}}
        raise RuntimeError("faux Linear : requete inattendue : " + query[:60])


class FakeBL:
    def __init__(self, items):
        self.items = items

    def get(self, i):
        return next((x for x in self.items if x["id"] == i), None)

    def set_status(self, iid, status, **fields):
        it = self.get(iid)
        if it is None:
            return
        it["status"] = status
        it.update(fields)

    def validate(self, iid, text, date=None, via=None):
        self.set_status(iid, "archived", owner_ok=True)

    def add_owner_feedback(self, iid, date, text, via=None):
        it = self.get(iid)
        if it is None:
            return
        it.setdefault("owner_feedback", []).append({"date": date, "text": text, "via": dict(via) if via else None})


def run_sim(seeds, mode, issues, mp, items, truth):
    m, missing = load_variant(seeds)
    bl = FakeBL(items)
    m.B = types.SimpleNamespace(load=lambda: bl)
    m.refresh_prompt = lambda it: None
    m._say = lambda L_, rec, text: None
    m.post_comment = lambda *a, **k: None
    L = FakeL(issues, mode=mode)
    m.MOVES.clear()
    log = io.StringIO()
    with redirect_stdout(log):
        m.pull_owner(L, bl, mp, {}, False)
    moves = list(m.MOVES)
    fake, named = [], []
    for mv_ in moves:
        iid = mv_["iid"]
        if mv_["applied"] and not truth.get(iid, False):
            tag = "%s:%s->%s" % (mp[iid]["identifier"], mv_["from"], mv_["to"])
            fake.append(tag)
    missing_ok = not missing
    return {"moves": moves, "fake": fake, "missing": missing, "L": L, "bl": bl, "m": m}


try:
    issues, mp, items, truth = sim_world()
    r = run_sim([], "app", issues, mp, items, truth)
    moves = r["moves"]
    pub("stale_sim_drifts", len(moves))
    pub("stale_sim_fake", len(r["fake"]))
    pub("stale_sim_fake_named", ",".join(r["fake"]) or "-")
    applied_iids = {mv_["iid"] for mv_ in moves if mv_["applied"]}
    real_applied = "sim-real" in applied_iids and r["bl"].get("sim-real")["status"] == "archived"
    pub("stale_sim_owner_applied", 1 if real_applied else 0)
    if not real_applied:
        dead.append("C-:SIM-REAL_non_applique_app")
    pub("stale_sim_history_calls_calm", r["L"].history_calls.count("sim-calm"))
    if r["L"].history_calls.count("sim-calm") != 0:
        dead.append("C-:historique_lu_sur_ticket_calme")
    for mv_ in moves:
        pub("stale_sim_why_%s" % mv_["iid"], (mv_["why"] or "-")[:60])
    sim_fake_app = len(r["fake"])
    missed_app = [mv_ for mv_ in moves if truth.get(mv_["iid"]) and not mv_["applied"]]
    if missed_app:
        dead.append("C-:SIM-REAL:non_applique")

    issues2, mp2, items2, truth2 = owner_world()
    r2 = run_sim([], "owner", issues2, mp2, items2, truth2)
    moves2 = r2["moves"]
    pub("stale_sim_owner_drifts", len(moves2))
    pub("stale_sim_owner_fake", len(r2["fake"]))
    pub("stale_sim_owner_fake_named", ",".join(r2["fake"]) or "-")
    applied2 = {mv_["iid"] for mv_ in moves2 if mv_["applied"]}
    real2_applied = "sim-real2" in applied2 and r2["bl"].get("sim-real2")["status"] == "archived"
    pub("stale_sim_owner_real_applied", 1 if real2_applied else 0)
    if not real2_applied:
        dead.append("C-:SIM-REAL2_non_applique_owner")
    for mv_ in moves2:
        pub("stale_sim_why_%s" % mv_["iid"], (mv_["why"] or "-")[:60])

    sim_fake = sim_fake_app + len(r2["fake"])
except Exception as e:  # noqa: BLE001
    unmeasured.append("simule:" + str(e)[:80])
    sim_fake = 0
    pub("stale_sim_error", str(e)[:160])

# --------------------------------------------------------------------- CONTROLES POSITIFS (S) --
POS = {
    "map": ([('                mv, why = owner_move(L, hist, owner_id, here, rec)\n',
              '                mv, why = {"createdAt": ""}, "carte"\n')], "sim-stale", "app"),
    "author": ([('    who = history_author(mv, owner_id)\n    if who != "owner":\n',
                 '    who = history_author(mv, owner_id)\n    if False:\n')], "sim-stale", "app"),
    "key": ([('    if mv["createdAt"] <= OWNER_KEY_UNTIL:\n', '    if False:\n')], "sim-prekey", "app"),
    "since": ([('    if since and mv["createdAt"] <= since:\n', '    if False:\n')], "sim-ownkey", "owner"),
}
for tag, (seeds, target, mode) in POS.items():
    try:
        if mode == "app":
            iw, mw, itw, tw = sim_world()
        else:
            iw, mw, itw, tw = owner_world()
        r = run_sim(seeds, mode, iw, mw, itw, tw)
        pub("stale_ctl_pos_%s_fake" % tag, len(r["fake"]))
        pub("stale_ctl_pos_%s_named" % tag, ",".join(r["fake"][:3]) or "-")
        if r["missing"]:
            dead.append("C+_%s:introuvable" % tag)
        elif not any(t.startswith(mw[target]["identifier"] + ":") for t in r["fake"]):
            dead.append("C+_%s:muet" % tag)
    except Exception as e:  # noqa: BLE001
        dead.append("C+_%s:erreur_%s" % (tag, str(e)[:40]))
        pub("stale_ctl_pos_%s_error" % tag, str(e)[:120])

# ============================================================================== V : VIVANT ==
queries_used = [0]


def owner_thread_query(ro, issue_id):
    d = ro.q('query($id:String!,$a:String){ issue(id:$id){ history(first:100, after:$a){ pageInfo { hasNextPage '
             'endCursor } nodes { createdAt archived autoArchived toState { name } actor { id app } botActor { id } } } } }',
             id=issue_id, a=None)
    return d["issue"]["history"]["nodes"]


try:
    import linear_sync as S, linear_identity as LI
    owner_id = None
    L = S.Linear(LI.resolve())
    mp_live = S.load_map()
    from lib import backlog as B  # noqa: PLC0415
    bl_live = B.load()
    owner_id = S.owner_user_id(L, mp_live)
    if not owner_id:
        raise RuntimeError("owner inconnu")

    class ReadOnly:
        """Le vrai Linear, en LECTURE : toute mutation leve. L'historique d'un ticket, idempotent dans la fenetre
        d'un passage, est mis en cache : V2 et le controle a l'ancienne regle interrogent les MEMES tickets."""
        def __init__(self, inner):
            self.inner, self.mode, self.n, self.hist_cache = inner, inner.mode, 0, {}
        def q(self, query, **v):
            if query.lstrip().startswith("mutation"):
                raise RuntimeError("rejeu en lecture seule")
            if "history(" in query and "id" in v:
                key = (v["id"], v.get("a"))
                if key in self.hist_cache:
                    return self.hist_cache[key]
                self.n += 1
                queries_used[0] += 1
                d = self.inner.q(query, **v)
                self.hist_cache[key] = d
                return d
            self.n += 1
            queries_used[0] += 1
            return self.inner.q(query, **v)

    ro = ReadOnly(L)

    def judge_applied(mp_before, moves):
        fake = []
        for mv_ in moves:
            if not mv_["applied"]:
                continue
            hist = owner_thread_query(ro, mv_["ticket"])
            ok = independent_owner_proof(hist, owner_id, mv_["to"], "2026-09-18T00:00:00.000Z")
            if not ok:
                iid = mv_["iid"]
                ident = (mp_before.get(iid) or {}).get("identifier") or iid
                fake.append("%s:%s->%s" % (ident, mv_["from"], mv_["to"]))
        return fake

    # ------- V1 : carte telle quelle
    mp_cur = copy.deepcopy(mp_live)
    S.MOVES.clear()
    with redirect_stdout(io.StringIO()):
        S.pull_owner(ro, bl_live, mp_cur, {}, True)
    moves_v1 = list(S.MOVES)
    fake_v1 = judge_applied(mp_live, moves_v1)
    pub("stale_live_current_drifts", len(moves_v1))
    pub("stale_live_current_fake", len(fake_v1))
    pub("stale_live_current_fake_named", ",".join(fake_v1[:3]) or "-")

    # ------- V2 : carte RECULEE fabriquee
    recs = {k: v for k, v in mp_live.items() if not k.startswith("_") and isinstance(v, dict)}
    def jak_num(v):
        m_ = re.search(r"JAK-(\d+)", v.get("identifier") or "")
        return int(m_.group(1)) if m_ else -1
    top = sorted(recs.items(), key=lambda kv: jak_num(kv[1]), reverse=True)[:40]
    picked = dict(top)
    for extra in ("harness-x86-proof-for-a-device-item-must-shout-at-launch", "harness-supervisor-death-is-an-alarm"):
        if extra in recs:
            picked[extra] = recs[extra]
    rewound = {"_owner": mp_live.get("_owner", {})}
    for k, v in picked.items():
        vv = dict(v)
        vv["last_state"] = "Backlog"
        vv.pop("state_at", None)
        rewound[k] = vv
    S.MOVES.clear()
    with redirect_stdout(io.StringIO()):
        S.pull_owner(ro, bl_live, rewound, {}, True)
    moves_v2 = list(S.MOVES)
    fake_v2 = judge_applied(rewound, moves_v2)
    owner_proven = sum(1 for mv_ in moves_v2 if mv_["applied"] and (
        "%s:%s->%s" % ((rewound.get(mv_["iid"]) or {}).get("identifier") or mv_["iid"], mv_["from"], mv_["to"])
    ) not in fake_v2)
    pub("stale_live_rewound_tickets", len(rewound) - 1)
    pub("stale_live_rewound_drifts", len(moves_v2))
    pub("stale_live_rewound_fake", len(fake_v2))
    pub("stale_live_rewound_fake_named", ",".join(fake_v2[:3]) or "-")
    pub("stale_live_rewound_owner_proven", owner_proven)

    # ------- controle positif VIVANT : l'ancienne regle (tout ecart = l'owner) doit rougir sur ce meme monde reculé
    if len(moves_v2) == 0:
        unmeasured.append("vivant_sans_ecart")
    else:
        try:
            old, missing_old = load_variant([('                mv, why = owner_move(L, hist, owner_id, here, rec)\n',
                                               '                mv, why = {"createdAt": ""}, "carte"\n')])
            old.B = types.SimpleNamespace(load=lambda: bl_live)
            old.refresh_prompt = lambda it: None
            old._say = lambda L_, rec, text: None
            old.MOVES.clear()
            rewound2 = copy.deepcopy(rewound)
            with redirect_stdout(io.StringIO()):
                old.pull_owner(ro, bl_live, rewound2, {}, True)
            moves_old = list(old.MOVES)
            fake_old = judge_applied(rewound2, moves_old)
            pub("stale_live_old_rule_fake", len(fake_old))
            pub("stale_live_old_rule_fake_named", ",".join(fake_old[:3]) or "-")
            if missing_old:
                dead.append("C+_vivant:introuvable")
            elif not fake_old:
                dead.append("C+_vivant:muet")
        except Exception as e:  # noqa: BLE001
            dead.append("C+_vivant:erreur_%s" % str(e)[:40])
            pub("stale_live_old_rule_error", str(e)[:120])

    live_fake = len(fake_v1) + len(fake_v2)
    pub("stale_live_queries", queries_used[0])
except Exception as e:  # noqa: BLE001
    unmeasured.append("vivant:" + str(e)[:80])
    live_fake = 0
    pub("stale_live_error", str(e)[:160])

# ============================================================================== V3 : JOURNAL (informatif) ==
try:
    log_path = Path(".autoport/logs/linear_sync.txt")
    text = log_path.read_text(errors="replace")
    # les etats portent des espaces (« In Progress », « À arbitrer ») : on coupe sur « -> », jamais sur \S+
    rx = re.compile(r"owner a d\S*plac\S* (\S+) : (.+?) -> (.+?)\s*$")
    seen = []
    for line in text.splitlines():
        mm = rx.search(line)
        if mm and "(historique" not in line:
            seen.append((mm.group(1), mm.group(2).strip(), mm.group(3).strip()))
    total = len(seen)
    unproven, mapped = [], 0
    for iid, a, b in seen:
        rec = mp_live.get(iid) if "mp_live" in dir() else None
        ticket = (rec or {}).get("issue_id")
        if not ticket:
            continue
        mapped += 1
        try:
            hist = owner_thread_query(ro, ticket)
        except Exception:  # noqa: BLE001
            continue
        # historique : l'etat a pu rebouger depuis ; la question est « un changement vers B signe de l'owner a-t-il
        # JAMAIS existe apres la bascule d'identite ? », pas « est-il le dernier ».
        if not any(independent_owner_proof([e], owner_id, b, "2026-09-18T00:00:00.000Z") for e in hist if e.get("toState")):
            unproven.append("%s:%s->%s" % (iid, a, b))
    pub("journal_owner_moves_total", total)
    pub("journal_owner_moves_mapped", mapped)
    pub("journal_owner_moves_unproven", len(unproven))
    pub("journal_owner_moves_unproven_named", ",".join(unproven[:6]) or "-")
except Exception as e:  # noqa: BLE001
    pub("journal_error", str(e)[:160])

pub("unmeasured_terms", len(unmeasured))
pub("unmeasured_terms_list", ",".join(unmeasured) or "-")
pub("dead_controls", len(dead))
pub("dead_controls_list", ",".join(dead) or "-")
pub("fake_owner_moves_dead", ",".join(dead) or "-")
pub("fake_owner_moves_unmeasured", ",".join(unmeasured) or "-")
pub("fake_owner_moves", sim_fake + live_fake + len(unmeasured) + len(dead))
for k_, v in OUT.items():
    print("%s=%s" % (k_, v))
PY
