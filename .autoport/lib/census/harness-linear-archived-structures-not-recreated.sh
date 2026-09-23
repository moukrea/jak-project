#!/usr/bin/env bash
# census/harness-linear-archived-structures-not-recreated.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `linear_structures_duplicated`.
#
# LA CAUSE (23/09) : `ensure_projects`, `ensure_label`, `ensure_view` (linear_sync.py) lisaient `team{projects}`,
# `team{labels}`, `customViews` SANS `includeArchived:true` : un projet, une etiquette ou une vue archives par
# l'owner etaient invisibles et auraient ete RECREES au premier passage sans cache `_ids`. Et, mesure vivante :
# une vue PRIVEE n'est lue que par son createur. Les vues « À lire », « À traiter », « En discussion » de l'owner
# (creees sous sa cle le 17/09 07:36-07:48) sont invisibles a l'application : a la bascule d'identite
# (17/09 19:17:56) celle-ci en a cree trois copies privees que personne ne voyait.
#
# CE QU'IL MESURE — `linear_structures_duplicated` = somme de :
#   A. HORS RESEAU, les VRAIES fonctions (ensure_projects, labels -> ensure_label + ensure_view) contre un faux
#      Linear qui applique les regles de l'API : collection sans `includeArchived:true` = archives ecartes ;
#      vue privee = lue par son seul createur. Un defaut = une creation dont (genre, equipe, nom) existait deja.
#        W1 tout archive (identite app)       W2 tout archive (repli owner)
#        W3 vues de l'owner privees, actives  W4 vues de l'owner privees, cle personnelle ABSENTE
#      Denominateur : 17 structures gerees par scenario (10 projets, 4 etiquettes, 3 vues).
#      Consommateurs : les fonctions qui lisent une etiquette rendue None (archivee) ne plantent pas.
#   B. CONTROLES. C- (W5 monde vide) : les 17 DOIVENT etre creees, vues partagees — sinon la porte serait verte
#      par inaction ; W6 vues homonymes dans une AUTRE equipe : les 3 DOIVENT etre creees. C+1 = W1 avec le
#      drapeau retire a la volee ; C+2 = W3 avec une lecture owner qui voit comme l'application. Un C+ qui ne
#      rougit pas (ou ne NOMME pas) compte 1.
#   C. VIVANT : les structures de l'equipe, archives comprises, vues sous les DEUX cles ; par (genre, nom) gere,
#      tout membre ACTIF cree apres un homonyme = un doublon, nomme. INCONNU = DEFAUT : un terme non mesure compte 1.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "linear_structures_duplicated=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import copy, inspect, io, re, sys
from contextlib import redirect_stdout
sys.path.insert(0, '.autoport')
import linear_sync as S

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
dups = 0
unmeasured = []
dead = []
FLAG = "includeArchived:true"
TEAM, OTHER = "team-jak", "team-jau"
ARCH = "2026-09-20T00:00:00Z"

PROJ = sorted(set(S.PROJECTS.values()) | {"Divers"})
LABS = [S.LABEL_READ, S.LABEL_TODO, S.LABEL_TALK, S.LABEL_OK]
VIEWS = [inspect.signature(S.ensure_view).parameters["name"].default] + \
    re.findall(r'ensure_view\([^)]*?name="([^"]+)"', inspect.getsource(S.labels))
pub("linear_structures_managed", "%d_projets,%d_etiquettes,%d_vues" % (len(PROJ), len(LABS), len(VIEWS)))
MANAGED = len(PROJ) + len(LABS) + len(VIEWS)


def world(archived, views_owner_private=True, views_team=TEAM, empty=False):
    if empty:
        return {"projects": [], "labels": [], "views": []}
    a = ARCH if archived else None
    return {"projects": [{"id": "p%d" % i, "name": n, "archivedAt": a, "trashed": None} for i, n in enumerate(PROJ)],
            "labels": [{"id": "l%d" % i, "name": n, "archivedAt": a} for i, n in enumerate(LABS)],
            "views": [{"id": "v%d" % i, "name": n, "archivedAt": a, "team": {"id": views_team}, "creator": "owner",
                       "shared": not views_owner_private} for i, n in enumerate(VIEWS)]}


class Fake:
    """Faux Linear aux regles de l'API. `strip` = le defaut seme (drapeau retire)."""
    def __init__(self, w, ident, strip=False):
        self.w, self.mode, self.strip, self.created, self.n = w, ident, strip, [], 0

    def q(self, query, **v):
        self.n += 1
        if self.strip:
            query = query.replace(", " + FLAG, "").replace(FLAG + ", ", "").replace(FLAG, "")
        flag = FLAG in query.replace(" ", "")
        live = lambda ns: [dict(x) for x in ns if flag or not (x.get("archivedAt") or x.get("trashed"))]
        for mut, kind, key in (("projectCreate", "project", "projects"), ("issueLabelCreate", "label", "labels"),
                               ("customViewCreate", "view", "views")):
            if mut in query:
                i = v["i"]; nid = "%s-new%d" % (kind, len(self.created))
                node = {"id": nid, "name": i["name"], "archivedAt": None, "trashed": None,
                        "team": {"id": i.get("teamId") or (i.get("teamIds") or [None])[0]},
                        "creator": self.mode, "shared": bool(i.get("shared"))}
                self.created.append((kind, node["team"]["id"], i["name"], node["shared"]))
                self.w[key].append(node)
                return {mut: {{"project": "project", "label": "issueLabel", "view": "customView"}[kind]: {"id": nid}}}
        if "projects" in query:
            return {"team": {"projects": {"nodes": live(self.w["projects"])}}}
        if "labels" in query and "team(" in query:
            return {"team": {"labels": {"nodes": live(self.w["labels"])}}}
        if "customViews" in query:
            seen = [x for x in self.w["views"] if x["shared"] or x["creator"] == self.mode]
            return {"customViews": {"nodes": live(seen)}}
        if "issueLabel(" in query:
            return {"issueLabel": {"issues": {"nodes": []}}}
        raise RuntimeError("requete inattendue du faux Linear : " + query[:80])


def run(name, w, ident="app", key=True, strip=False, owner_sees_as="owner"):
    """-> (creations, doublons nommes, crash). Doublon = creation dont (genre, equipe, nom) existait AVANT."""
    before = {("project", TEAM, p["name"]) for p in w["projects"]} | {("label", TEAM, l["name"]) for l in w["labels"]} | \
             {("view", x["team"]["id"], x["name"]) for x in w["views"]}
    L = Fake(w, ident, strip)
    le, lg = S.LI.load_env, S.LI.gql
    S.LI.load_env = lambda: {"LINEAR_API_KEY": "cle-factice"} if key else {}
    S.LI.gql = lambda k, q, *a, **kw: Fake(w, owner_sees_as, strip).q(q)
    crash = "-"
    try:
        with redirect_stdout(io.StringIO()):
            S.ensure_projects(L, TEAM)
            read, todo = S.labels(L, TEAM)
            # consommateurs d'une etiquette eventuellement None
            S.sweep_talk(L, read, todo, S._TALK.get("id"), True)
            S.pull_labeled_unmapped(L, {"_owner": {"user_id": "u-owner"}}, read, todo, S._TALK.get("id"), True)
    except Exception as e:  # noqa: BLE001
        crash = "%s:%s" % (type(e).__name__, str(e)[:80])
    finally:
        S.LI.load_env, S.LI.gql = le, lg
    d = ["%s:%s" % (k, n) for (k, t, n, _) in L.created if (k, t, n) in before]
    pub("linear_w_%s_created" % name, len(L.created))
    pub("linear_w_%s_dups" % name, len(d))
    pub("linear_w_%s_dups_list" % name, ",".join(d) or "-")
    pub("linear_w_%s_crash" % name, crash)
    return L.created, d, crash


# ------------------------------------------------------------------------ A : le code livre
for name, w, kw in (("w1_arch_app", world(True), {}),
                    ("w2_arch_owner", world(True), {"ident": "owner"}),
                    ("w3_views_private", world(False), {}),
                    ("w4_views_private_nokey", world(False), {"key": False})):
    created, d, crash = run(name, w, **kw)
    dups += len(d) + (crash != "-")
pub("linear_scenarios_denominator", "4x%d" % MANAGED)

# ------------------------------------------------------------------------ B : controles
created, d, crash = run("c_neg_empty", world(False, empty=True))
bad = abs(len(created) - MANAGED) + sum(1 for c in created if c[0] == "view" and not c[3]) + (crash != "-")
pub("linear_ctl_neg_empty_bad", bad)
dups += bad
created, d, crash = run("c_neg_other_team", world(False, views_team=OTHER))
bad = abs(sum(1 for c in created if c[0] == "view") - len(VIEWS)) + len(d) + (crash != "-")
pub("linear_ctl_neg_other_team_bad", bad)
dups += bad
created, d, crash = run("c_pos_no_flag", world(True), strip=True)
if len(d) != MANAGED:
    dead.append("C+1_sans_drapeau")
created, d, crash = run("c_pos_owner_blind", world(False), owner_sees_as="app")
if sorted(d) != sorted("view:" + v for v in VIEWS):
    dead.append("C+2_vues_privees")

# ------------------------------------------------------------------------ C : vivant
try:
    import linear_identity as LI
    L = S.Linear(LI.resolve())
    team = S.ensure_team(L)
    d = L.q('query($t:String!){ team(id:$t){ projects(first:250, includeArchived:true) { nodes { id name archivedAt trashed createdAt creator { name } } } '
            'labels(first:250, includeArchived:true) { nodes { id name archivedAt createdAt creator { name } } } } }', t=team)["team"]
    qv = '{ customViews(first:250, includeArchived:true) { nodes { id name archivedAt createdAt shared creator { name } team { id } } } }'
    views = {v["id"]: v for v in L.q(qv)["customViews"]["nodes"]}
    key = LI.load_env().get("LINEAR_API_KEY")
    if not key:
        raise RuntimeError("cle personnelle absente : vues privees de l'owner illisibles")
    views.update({v["id"]: v for v in LI.gql(key, qv)["customViews"]["nodes"]})
    pools = [("project", PROJ, d["projects"]["nodes"]), ("label", LABS, d["labels"]["nodes"]),
             ("view", VIEWS, [v for v in views.values() if (v.get("team") or {}).get("id") == team])]
    live, seen_n = [], 0
    for kind, names, nodes in pools:
        for n in names:
            grp = sorted((x for x in nodes if x["name"] == n), key=lambda x: x["createdAt"])
            seen_n += len(grp)
            for x in grp[1:]:
                if not (x.get("archivedAt") or x.get("trashed")):
                    live.append("%s:%s:%s:%s:%s" % (kind, n, x["id"][:8], (x.get("creator") or {}).get("name", "?"), x["createdAt"][:10]))
    pub("linear_live_structures_read", seen_n)
    pub("linear_live_views_read", len(views))
    pub("linear_live_dups", len(live))
    pub("linear_live_dups_list", ",".join(live) or "-")
    dups += len(live)
except Exception as e:  # noqa: BLE001
    pub("linear_live_error", str(e)[:200])
    unmeasured.append("C_vivant")

pub("linear_structures_unmeasured", ",".join(unmeasured) or "-")
pub("linear_structures_controls_dead", ",".join(dead) or "-")
dups += len(unmeasured) + len(dead)
pub("linear_structures_duplicated", dups)
for k_, v in OUT.items():
    print("%s=%s" % (k_, v))
PY
