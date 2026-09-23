#!/usr/bin/env bash
# census/harness-linear-relink-keeps-owner-comments.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `owner_comments_skipped_on_relink`.
#
# LE DEFAUT (owner 23/09 : « Ok », JAK-229) : quand la synchro perd la trace d'un ticket (carte ET cliche perdus) puis
# le retrouve dans Linear, la fiche reliee partait avec `pulled_at` = maintenant : un retour de l'owner poste pendant
# la perte n'etait jamais recopie. Deux chemins relient (`ensure_ticket`, `adopt_owner_issues`) ; ils passent
# desormais par UNE fabrique, `relinked_rec`, dont le curseur part d'avant la creation du ticket. Trouve en mesurant :
# `pull_owner` ne lisait que les 50 commentaires les plus RECENTS (JAK-176 en porte 142) ; un retour enfoui sous 50
# messages du harnais restait invisible au ticket relie, quel que soit son curseur.
#
# CE QU'IL MESURE — `owner_comments_skipped_on_relink` = somme de :
#   V  VIVANT, rejeu : chaque ticket de la carte est relie A NEUF par la vraie `relinked_rec`, puis le vrai `pull_owner`
#      tourne A BLANC sur le vrai Linear (toute ecriture REFUSEE par le mandataire). Un commentaire de l'owner (tous,
#      pagines) que ce tirage ne voit pas et dont l'identifiant n'est dans aucun `owner_feedback[].via.comment` de
#      son item = saute.
#   S  SIMULE, code livre : faux Linear en memoire, vrais `ensure_ticket` / `adopt_owner_issues` / `pull_owner`. Carte
#      perdue, retours de l'owner poses pendant la perte (dont un sous 60 messages du harnais), reliaison, retour poste
#      apres. Chaque retour non recopie = saute, NOMME.
#   INCONNU = DEFAUT : un terme non mesure compte 1 ; un controle negatif qui ne rend pas 0 (saute, doublon, ticket
#   cree) compte 1 ; un controle positif qui ne rougit pas ou ne NOMME pas son retour compte 1.
# CONTROLES POSITIFS (le defaut SEME dans une copie du source) :
#   C+ensure  `ensure_ticket` relie avec `pulled_at` = maintenant (le code d'avant le 23/09) -> SIM-A:c-a2 nomme
#   C+adopt   `adopt_owner_issues` relie avec `pulled_at` = maintenant                  -> SIM-B:c-b1 nomme
#   C+page    `pull_owner` sans la suite des commentaires                               -> SIM-A:c-a2 nomme
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "owner_comments_skipped_on_relink=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import copy, datetime as dt, io, re, sys, types
from contextlib import redirect_stdout
from pathlib import Path
sys.path.insert(0, '.autoport')
from lib.census import fake_backlog as FB

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
unmeasured, dead = [], []
SRC_PATH = Path(".autoport/linear_sync.py")
SRC = SRC_PATH.read_text()
REST_LINE = '            iss["comments"]["nodes"] += OSLA._rest(L, iss["id"], iss["comments"].get("pageInfo"))\n'


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


def via_ids(it):
    return [f["via"]["comment"] for f in ((it or {}).get("owner_feedback") or [])
            if isinstance(f, dict) and isinstance(f.get("via"), dict) and f["via"].get("comment")]


# ============================================================================== VIVANT (rejeu) ==
try:
    import linear_sync as S, linear_identity as LI
    from lib import owner_sla as OSLA
    L = S.Linear(LI.resolve())
    mp = S.load_map()
    bl = S.B.load()
    owner_id = S.owner_user_id(L, mp)
    if not owner_id:
        raise RuntimeError("owner inconnu")
    recs = {k: v for k, v in mp.items() if not k.startswith("_") and isinstance(v, dict) and v.get("issue_id")}
    ids = [v["issue_id"] for v in recs.values()]
    world = {}
    for i in range(0, len(ids), 25):
        d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:25, includeArchived:true){ nodes { id identifier '
                'comments(first:100){ pageInfo { hasNextPage endCursor } nodes { ' + OSLA.COMMENT_FIELDS + ' } } } } }',
                ids=ids[i:i + 25])
        for n in d["issues"]["nodes"]:
            cs = n["comments"]["nodes"] + OSLA._rest(L, n["id"], n["comments"]["pageInfo"])
            world[n["id"]] = [c for c in cs if S.is_owner_comment(c, owner_id)]
    pub("relink_live_tickets", len(recs))
    pub("relink_live_tickets_returned", len(world))
    pub("relink_live_owner_comments", sum(len(v) for v in world.values()))
    if len(world) != len(recs):
        unmeasured.append("tickets_non_rendus:%d" % (len(recs) - len(world)))

    class ReadOnly:
        """Le vrai Linear, en LECTURE : toute mutation leve ; chaque commentaire rendu est note."""
        def __init__(self):
            self.mode, self.seen, self.refused = L.mode, set(), 0
        def q(self, query, **v):
            if query.lstrip().startswith("mutation"):
                self.refused += 1
                raise RuntimeError("rejeu en lecture seule")
            d = L.q(query, **v)
            for n in ((d.get("issues") or {}).get("nodes") or []) + [d.get("issue") or {}]:
                self.seen |= {c["id"] for c in ((n.get("comments") or {}).get("nodes") or [])}
            return d

    by_issue = {v["issue_id"]: k for k, v in recs.items()}
    for tag, seeds in (("after", []), ("before", [(REST_LINE, "")])):
        m = S if not seeds else load_variant(seeds)[0]
        if seeds:
            m.B = S.B
        # chaque ticket RELIE a neuf, par la fabrique livree (le bras « avant » garde la meme fiche : il ne retire que la suite)
        relinked = {k: v for k, v in mp.items() if k.startswith("_")}
        for k, v in recs.items():
            relinked[k] = S.relinked_rec({"id": v["issue_id"], "identifier": v.get("identifier") or "?",
                                          "url": v.get("url"), "state": {"name": v.get("last_state") or ""}})
        ro = ReadOnly()
        with redirect_stdout(io.StringIO()):
            m.pull_owner(ro, bl, relinked, {}, True)
        unseen, skipped = [], []
        for issue_id, owner_cs in world.items():
            iid = by_issue[issue_id]
            have = set(via_ids(bl.get(iid)))
            for c in owner_cs:
                if c["id"] not in ro.seen:
                    unseen.append(c)
                    if c["id"] not in have:
                        skipped.append("%s:%s:%s" % (recs[iid].get("identifier"), iid, c["createdAt"]))
        pub("relink_live_%s_cursor" % tag, relinked[next(iter(recs))]["pulled_at"] if recs else "-")
        pub("relink_live_%s_owner_unseen" % tag, len(unseen))
        pub("relink_live_%s_skipped" % tag, len(skipped))
        pub("relink_live_%s_skipped_first" % tag, ",".join(skipped[:4]) or "-")
        pub("relink_live_%s_writes_refused" % tag, ro.refused)
        if tag == "after":
            live_skipped = len(skipped)
    pub("relink_live_queries", L.n)
except Exception as e:  # noqa: BLE001 — un terme non mesure est un DEFAUT, jamais un zero
    unmeasured.append("vivant:" + str(e)[:80])
    live_skipped = 0
    pub("relink_live_error", str(e)[:120])

# ============================================================================ MONDE SIMULE ==
OWNER, APP, TEAM = "u-owner", "u-app", "team-sim"
NOW = dt.datetime.now(dt.timezone.utc)
LATER = (NOW + dt.timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%S.000Z")   # poste APRES la reliaison


def oc(i, t):
    return {"id": i, "body": "retour %s" % i, "createdAt": t, "user": {"id": OWNER, "app": False}, "botActor": None,
            "reactions": {"nodes": []}}


def hc(i, t):
    return {"id": i, "body": "\U0001F916 verdict %s" % i, "createdAt": t, "user": {"id": APP, "app": True}, "botActor": None,
            "reactions": {"nodes": []}}


class FakeL:
    """Faux Linear : sans `first`, une collection de commentaires rend les 50 plus RECENTS (mesure le 23/09 sur JAK-176) ;
    la suite se lit par `issue(id){ comments(after) }`. Toute creation de ticket est journalisee."""
    mode = "app"

    def __init__(self, issues):
        self.issues, self.n, self.writes = issues, 0, []

    def page(self, iss, query, after=None):
        m = re.search(r"comments\(first:(\d+)", query)
        size = int(m.group(1)) if m else 50
        cs = sorted(iss["comments"], key=lambda c: c["createdAt"], reverse=True)
        at = int(after or 0)
        chunk = cs[at:at + size]
        return {"pageInfo": {"hasNextPage": at + size < len(cs), "endCursor": str(at + size)}, "nodes": copy.deepcopy(chunk)}

    def q(self, query, **v):
        self.n += 1
        q1 = query.replace(" ", "")
        if query.lstrip().startswith("mutation"):
            kind = re.search(r"\{\s*(\w+)\(", query).group(1)
            self.writes.append(kind)
            return {kind: {"success": True, "issue": {"id": "t-new", "identifier": "SIM-NEW", "url": "u"}}}
        if "issues(filter:{id:{in:$ids}}" in q1:
            return {"issues": {"nodes": [{"id": i, "archivedAt": None, "state": {"name": x["state"]}, "labels": {"nodes": []},
                                          "comments": self.page(x, query)}
                                         for i, x in self.issues.items() if i in v["ids"]]}}
        if "issue(id:$id){comments(" in q1:
            return {"issue": {"comments": self.page(self.issues[v["id"]], query, v.get("a"))}}
        if "issues(first:20,includeArchived:true" in q1:   # find_issue_for
            return {"issues": {"nodes": [self.node(i, x) for i, x in self.issues.items()
                                         if v["k"] in x["description"] or x["title"] == v["ti"]]}}
        if "team(id:$t){issues(" in q1:                    # adopt_owner_issues
            return {"team": {"issues": {"pageInfo": {"hasNextPage": False, "endCursor": None},
                                        "nodes": [dict(self.node(i, x), creator={"id": APP, "app": True})
                                                  for i, x in self.issues.items()]}}}
        if "history(" in query:
            return {"issue": {"history": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": []}}}
        raise RuntimeError("faux Linear : requete inattendue : " + query[:60])

    def node(self, i, x):
        return {"id": i, "identifier": x["identifier"], "url": "https://linear.app/sim/" + x["identifier"], "title": x["title"],
                "description": x["description"], "createdAt": x["createdAt"], "state": {"name": x["state"], "type": x["type"]}}


_SANDBOXES = []


def simulate(seeds):
    m, missing = load_variant(seeds)
    key = lambda iid: "…\n\n" + m.KEY_FMT % iid
    issues = {
        # A : relie par `ensure_ticket`. c-a1 deja recopie avant la perte ; c-a2 poste PENDANT la perte puis enfoui sous
        # 60 messages du harnais ; c-a3 poste apres la reliaison.
        "t-a": {"identifier": "SIM-A", "title": "item a", "description": key("item-a"), "createdAt": "2026-09-19T00:00:00.000Z",
                "state": "In Progress", "type": "started",
                "comments": [oc("c-a1", "2026-09-20T10:00:00.000Z"), oc("c-a2", "2026-09-21T12:00:00.000Z")]
                            + [hc("h-a%02d" % k, "2026-09-21T13:%02d:00.000Z" % k) for k in range(60)]},
        # B : relie par `adopt_owner_issues` (ticket ouvert hors carte, qui porte la cle de l'item)
        "t-b": {"identifier": "SIM-B", "title": "item b", "description": key("item-b"), "createdAt": "2026-09-19T00:00:00.000Z",
                "state": "Todo", "type": "unstarted",
                "comments": [hc("h-b1", "2026-09-20T09:00:00.000Z"), oc("c-b1", "2026-09-21T12:30:00.000Z")]},
        # C : jamais perdu (temoin de la voie ordinaire, curseur pose)
        "t-c": {"identifier": "SIM-C", "title": "item c", "description": key("item-c"), "createdAt": "2026-09-19T00:00:00.000Z",
                "state": "Todo", "type": "unstarted", "comments": [oc("c-c1", "2026-09-22T12:00:00.000Z")]},
    }
    items = [{"id": "item-a", "status": "in-progress", "feature": "item a", "owner_feedback":
              [{"date": "2026-09-20", "text": "retour c-a1", "via": {"comment": "c-a1", "ticket": "t-a", "at": "2026-09-20T10:00:00.000Z"}}]},
             {"id": "item-b", "status": "open", "feature": "item b", "owner_feedback": []},
             {"id": "item-c", "status": "open", "feature": "item c", "owner_feedback": []}]
    # la carte a PERDU item-a et item-b (carte et cliche) ; item-c y est
    mp = {"_owner": {"user_id": OWNER},
          "item-c": {"issue_id": "t-c", "identifier": "SIM-C", "last_state": "Todo", "hash": "x", "pulled_at": "2026-09-22T00:00:00.000Z"}}
    L = FakeL(issues)
    sb = FB.Sandbox(items)
    _SANDBOXES.append(sb)
    FB.install(m, sb)
    bl = sb.load()
    m.save_map = lambda mp_: None
    m.refresh_prompt = lambda it: None
    m.save_owner_images = lambda L_, iid, body, when: body
    m._CTX.update(bl=bl, mp=mp)
    log = io.StringIO()
    with redirect_stdout(log):
        m.ensure_ticket(L, mp, TEAM, "item-a", "item a", {"title": "item a"}, "In Progress", "h")
        m.adopt_owner_issues(L, bl, mp, TEAM, None, False)
        for x in issues.values():   # apres la reliaison
            x["comments"].append(oc("c-%s9" % x["identifier"][-1].lower(), LATER))
        m.pull_owner(L, bl, mp, {}, False)
        m.pull_owner(L, bl, mp, {}, False)   # un 2e passage ne recopie rien deux fois
    skipped, dups, den = [], [], 0
    for issue_id, x in issues.items():
        iid = "item-" + x["identifier"][-1].lower()
        have = via_ids(sb.item(iid))
        dups += ["%s:%s" % (x["identifier"], c) for c in set(have) if have.count(c) > 1]
        for c in x["comments"]:
            if c["user"]["id"] == OWNER:
                den += 1
                if c["id"] not in have:
                    skipped.append("SIM-%s:%s" % (x["identifier"][-1], c["id"]))
    relinked = sum(1 for k in ("item-a", "item-b") if (mp.get(k) or {}).get("issue_id") == "t-" + k[-1])
    return {"skipped": skipped, "dups": dups, "created": [w for w in L.writes if w == "issueCreate"], "den": den,
            "relinked": relinked, "missing": missing, "log": log.getvalue()}


try:
    neg = simulate([])
    pub("relink_sim_owner_comments", neg["den"])
    pub("relink_sim_relinked", neg["relinked"])
    pub("relink_sim_skipped", len(neg["skipped"]))
    pub("relink_sim_skipped_named", ",".join(neg["skipped"]) or "-")
    pub("relink_sim_duplicated", len(neg["dups"]))
    pub("relink_sim_created", len(neg["created"]))
    if neg["dups"] or neg["created"] or neg["den"] < 6 or neg["relinked"] != 2:
        dead.append("C-:" + (",".join(neg["dups"] + neg["created"]) or "monde_incomplet"))
    sim_skipped = len(neg["skipped"])
    NOW_EXPR = 'dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")'
    POS = {
        "ensure": ([("        mp[iid] = relinked_rec(found)\n", "        mp[iid] = dict(relinked_rec(found), pulled_at=now)\n")], "SIM-A:c-a2"),
        "adopt": ([("                mp[what] = relinked_rec(iss)\n", "                mp[what] = dict(relinked_rec(iss), pulled_at=%s)\n" % NOW_EXPR)], "SIM-B:c-b1"),
        "page": ([(REST_LINE, "")], "SIM-A:c-a2"),
    }
    for tag, (seeds, expect) in POS.items():
        r = simulate(seeds)
        pub("relink_ctl_pos_%s_skipped" % tag, len(r["skipped"]))
        pub("relink_ctl_pos_%s_named" % tag, ",".join(r["skipped"][:3]) or "-")
        if r["missing"]:
            dead.append("C+_%s:introuvable" % tag)
        elif expect not in r["skipped"]:
            dead.append("C+_%s:muet" % tag)
except Exception as e:  # noqa: BLE001
    unmeasured.append("simulation:" + str(e)[:80])
    sim_skipped = 0
    pub("relink_sim_error", str(e)[:120])

pub("relink_unmeasured", len(unmeasured))
pub("relink_unmeasured_list", ",".join(unmeasured) or "-")
pub("relink_dead_controls", len(dead))
pub("relink_dead_controls_list", ",".join(dead) or "-")
pub("owner_comments_skipped_on_relink", live_skipped + sim_skipped + len(unmeasured) + len(dead))
for k_, v in OUT.items():
    print("%s=%s" % (k_, v))
PY
