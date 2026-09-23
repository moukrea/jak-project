#!/usr/bin/env bash
# census/harness-linear-relinks-closed-tickets.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `closed_tickets_unlinked`.
#
# LE DEFAUT (23/09, trouve par 4 workers, owner : « traite comme tu l'entends ») : `adopt_owner_issues` ne relie que les
# tickets OUVERTS, et `ensure_ticket` ne repasse plus sur un item clos (il n'est plus miroite). Un ticket Done/Canceled
# ou archive sorti de la carte n'etait donc jamais relie, et un « ca marche toujours pas » de l'owner dessus jamais tire.
# Correctif : `relink_closed_tickets`, appele par `main` AVANT `pull_owner`.
#
# CE QU'IL MESURE — `closed_tickets_unlinked` = somme de :
#   V  VIVANT : tous les tickets de l'equipe qui portent une cle d'item (requete PROPRE au recensement, archives compris),
#      clos ou archives ; ceux absents de la carte. Denominateur publie, ventile (reliable / item relie ailleurs / item
#      hors backlog).
#   R  REJEU VIVANT : la carte est privee de TOUS ses tickets clos ou archives (en memoire), la vraie
#      `relink_closed_tickets` tourne sur le vrai Linear (ecriture de carte neutralisee, toute mutation refusee). Chaque
#      ticket non rendu a SON item = rate.
#   S  SIMULE : faux Linear, vrais `relink_closed_tickets` + `pull_owner`. Carte perdue pour un ticket Done et un ticket
#      Canceled archive, chacun porte un retour de l'owner poste apres la cloture. Chaque ticket non relie et chaque retour
#      non recopie = defaut, NOMME.
#   A  APPEL : `main` appelle `relink_closed_tickets` AVANT `pull_owner` (noeud d'appel AST, pas le texte).
#   INCONNU = DEFAUT : un terme non mesure compte 1 ; un controle negatif qui ne rend pas 0 compte 1 ; un controle positif
#   qui ne rougit pas ou ne NOMME pas son ticket compte 1.
# CONTROLES POSITIFS (defaut SEME dans une copie du source) :
#   C+clos     la regle d'AVANT (ouverts seuls)              -> SIM-D et SIM-E nommes
#   C+archive  requete privee de `includeArchived`           -> SIM-E nomme
#   C+appel    `main` prive de l'appel                       -> A nomme `main`
# CONTROLE NEGATIF : le monde sain rend 0 ; le doublon clos d'un item deja relie (SIM-G) n'est PAS relie a sa place ; rien
# n'est cree dans Linear ; le ticket jamais perdu (SIM-F) garde sa fiche.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "closed_tickets_unlinked=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import ast, copy, datetime as dt, io, re, sys, types
from contextlib import redirect_stdout
from pathlib import Path
sys.path.insert(0, '.autoport')
from lib.census import fake_backlog as FB

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
unmeasured, dead = [], []
SRC_PATH = Path(".autoport/linear_sync.py")
SRC = SRC_PATH.read_text()
CLOSED = ("completed", "canceled")


def load_variant(seeds):
    src, missing = SRC, []
    for old, new in seeds:
        if src.count(old) != 1:
            missing.append(old.strip()[:40])
        src = src.replace(old, new)
    m = types.ModuleType("linear_sync_sim")
    m.__file__ = str(SRC_PATH.resolve())
    exec(compile(src, "linear_sync_sim", "exec"), m.__dict__)
    return m, missing, src


# ====================================================================================== A : APPEL ==
def call_order(src):
    """Lignes des appels a `relink_closed_tickets` et `pull_owner` dans le corps de `main` (noeuds d'appel)."""
    tree = ast.parse(src)
    main = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "main"), None)
    at = {"relink_closed_tickets": [], "pull_owner": []}
    for n in ast.walk(main) if main else []:
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in at:
            at[n.func.id].append(n.lineno)
    return at


def call_defect(src):
    at = call_order(src)
    ok = at["relink_closed_tickets"] and at["pull_owner"] and min(at["relink_closed_tickets"]) < min(at["pull_owner"])
    return [] if ok else ["main"]


CALL_LINE = '        guard("tickets clos perdus", lambda: relink_closed_tickets(L, bl, mp, team, a.dry_run), 0)\n'
call_bad = call_defect(SRC)
pub("relink_closed_call_lines", ",".join(map(str, call_order(SRC)["relink_closed_tickets"])) or "-")
pub("relink_closed_call_defect", ",".join(call_bad) or "-")
seeded = SRC.replace(CALL_LINE, "") if SRC.count(CALL_LINE) == 1 else None
if seeded is None:
    dead.append("C+_appel:introuvable")
else:
    c = call_defect(seeded)
    pub("relink_closed_ctl_pos_appel_named", ",".join(c) or "-")
    if c != ["main"]:
        dead.append("C+_appel:muet")

# ===================================================================================== V + R : VIVANT ==
live_unlinked, live_missed = 0, 0
try:
    import linear_sync as S, linear_identity as LI
    L = S.Linear(LI.resolve())
    mp = S.load_map()
    bl = S.B.load()
    team = (mp.get("_ids") or {}).get("team")
    if not team:
        raise RuntimeError("equipe inconnue dans la carte")
    recs = {k: v for k, v in mp.items() if not k.startswith("_") and isinstance(v, dict) and v.get("issue_id")}
    by_issue = {v["issue_id"]: k for k, v in recs.items()}
    keyed, after = [], None
    while True:   # requete PROPRE : ni `nin`, ni la fonction jugee
        d = L.q('query($t:ID!,$a:String){ issues(first:100, after:$a, includeArchived:true, filter:{team:{id:{eq:$t}}, '
                'description:{contains:"Identifiant harnais"}}){ pageInfo { hasNextPage endCursor } nodes { id identifier '
                'description archivedAt state { type } } } }', t=team, a=after)
        keyed += [n for n in d["issues"]["nodes"] if S.issue_key(n)]
        if not d["issues"]["pageInfo"]["hasNextPage"]:
            break
        after = d["issues"]["pageInfo"]["endCursor"]
    closed = [n for n in keyed if n["state"]["type"] in CLOSED or n["archivedAt"]]
    lost = [n for n in closed if n["id"] not in by_issue]
    kinds = {"reliable": [], "item_relie_ailleurs": [], "item_hors_backlog": []}
    for n in lost:
        k = S.issue_key(n)
        kinds["item_hors_backlog" if not bl.get(k) else "item_relie_ailleurs" if k in recs else "reliable"].append(n["identifier"])
    pub("closed_tickets_keyed_total", len(keyed))
    pub("closed_tickets_total", len(closed))
    pub("closed_tickets_archived", sum(1 for n in closed if n["archivedAt"]))
    pub("closed_tickets_in_map", len(closed) - len(lost))
    for k, v in kinds.items():
        pub("closed_tickets_unlinked_%s" % k, len(v))
    pub("closed_tickets_unlinked_list", ",".join(n["identifier"] for n in lost[:12]) or "-")
    live_unlinked = len(lost)
    if not closed:
        unmeasured.append("V_aucun_ticket_clos")

    # R : la carte privee de tous ses tickets clos ; la vraie fonction doit les rendre, chacun a SON item
    class ReadOnly:
        def __init__(self):
            self.mode, self.refused, self.n = L.mode, 0, 0
        def q(self, query, **v):
            if query.lstrip().startswith("mutation"):
                self.refused += 1
                raise RuntimeError("rejeu en lecture seule")
            self.n += 1
            return L.q(query, **v)
    removed = {by_issue[n["id"]]: n["id"] for n in closed if n["id"] in by_issue}
    m2 = {k: copy.deepcopy(v) for k, v in mp.items() if k not in removed}
    ro, saved = ReadOnly(), S.save_map
    S.save_map = lambda mp_: None
    try:
        with redirect_stdout(io.StringIO()) as log:
            got = S.relink_closed_tickets(ro, bl, m2, team, False)
    finally:
        S.save_map = saved
    missed = sorted(k for k, i in removed.items() if (m2.get(k) or {}).get("issue_id") != i)
    wrong = sorted(k for k in m2 if not k.startswith("_") and k not in mp)   # relie a un item qui n'avait pas de ticket
    pub("relink_closed_live_removed", len(removed))
    pub("relink_closed_live_relinked", got)
    pub("relink_closed_live_missed", len(missed))
    pub("relink_closed_live_missed_list", ",".join(missed[:8]) or "-")
    pub("relink_closed_live_foreign", len(wrong))
    pub("relink_closed_live_queries", ro.n)
    pub("relink_closed_live_writes_refused", ro.refused)
    live_missed = len(missed) + len(wrong) + ro.refused
    if not removed:
        unmeasured.append("R_rien_a_retirer")
    # regime normal : carte complete, une page vide
    ro2 = ReadOnly()
    with redirect_stdout(io.StringIO()):
        steady = S.relink_closed_tickets(ro2, bl, copy.deepcopy(mp), team, True)
    pub("relink_closed_steady_relinked", steady)
    pub("relink_closed_steady_queries", ro2.n)
except Exception as e:  # noqa: BLE001 — un terme non mesure est un DEFAUT, jamais un zero
    unmeasured.append("vivant:" + str(e)[:80])
    pub("relink_closed_live_error", str(e)[:120])

# ===================================================================================== S : SIMULE ==
OWNER, APP, TEAM = "u-owner", "u-app", "team-sim"


def oc(i, t):
    return {"id": i, "body": "ca marche toujours pas %s" % i, "createdAt": t, "user": {"id": OWNER, "app": False},
            "botActor": None, "reactions": {"nodes": []}}


class FakeL:
    """Faux Linear : une collection ecarte les archives sans `includeArchived:true` (regle de l'API, mesuree le 23/09)."""
    mode = "app"

    def __init__(self, issues):
        self.issues, self.writes = issues, []

    def visible(self, q1):
        return {i: x for i, x in self.issues.items() if "includeArchived:true" in q1 or not x["archivedAt"]}

    def node(self, i, x):
        return {"id": i, "identifier": x["identifier"], "url": "https://linear.app/sim/" + x["identifier"], "title": x["title"],
                "description": x["description"], "createdAt": "2026-09-01T00:00:00.000Z", "archivedAt": x["archivedAt"],
                "creator": {"id": APP, "app": True}, "state": {"name": x["state"], "type": x["type"]}}

    def q(self, query, **v):
        q1 = query.replace(" ", "")
        if query.lstrip().startswith("mutation"):
            kind = re.search(r"\{\s*(\w+)\(", query).group(1)
            self.writes.append(kind)
            return {kind: {"success": True, "issue": {"id": "t-new", "identifier": "SIM-NEW", "url": "u"}}}
        if "description:{contains:$k}" in q1:               # relink_closed_tickets
            nodes = [self.node(i, x) for i, x in self.visible(q1).items()
                     if v["k"] in x["description"] and i not in (v.get("n") or [])]
            return {"issues": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": nodes}}
        if "issues(filter:{id:{in:$ids}}" in q1:            # pull_owner
            return {"issues": {"nodes": [{"id": i, "archivedAt": x["archivedAt"], "state": {"name": x["state"]},
                                          "labels": {"nodes": []},
                                          "comments": {"pageInfo": {"hasNextPage": False, "endCursor": None},
                                                       "nodes": copy.deepcopy(x["comments"])}}
                                         for i, x in self.visible(q1).items() if i in v["ids"]]}}
        if "history(" in query:
            return {"issue": {"history": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": []}}}
        raise RuntimeError("faux Linear : requete inattendue : " + query[:60])


def simulate(seeds):
    m, missing, _ = load_variant(seeds)
    key = lambda iid: "…\n\n" + m.KEY_FMT % iid
    issues = {  # D, E : perdus de la carte ; F : jamais perdu (temoin) ; G : doublon clos de l'item de F
        "t-d": {"identifier": "SIM-D", "title": "item d", "description": key("item-d"), "state": "Done", "type": "completed",
                "archivedAt": None, "comments": [oc("c-d1", "2026-09-22T10:00:00.000Z")]},
        "t-e": {"identifier": "SIM-E", "title": "item e", "description": key("item-e"), "state": "Canceled", "type": "canceled",
                "archivedAt": "2026-09-21T00:00:00.000Z", "comments": [oc("c-e1", "2026-09-22T11:00:00.000Z")]},
        "t-f": {"identifier": "SIM-F", "title": "item f", "description": key("item-f"), "state": "Done", "type": "completed",
                "archivedAt": None, "comments": [oc("c-f1", "2026-09-22T12:00:00.000Z")]},
        "t-g": {"identifier": "SIM-G", "title": "item f (doublon)", "description": key("item-f"), "state": "Canceled",
                "type": "canceled", "archivedAt": "2026-09-21T00:00:00.000Z", "comments": []},
    }
    items = [{"id": "item-" + c, "status": "validated", "feature": "item " + c, "owner_feedback": []} for c in "def"]
    mp = {"_owner": {"user_id": OWNER},
          "item-f": {"issue_id": "t-f", "identifier": "SIM-F", "last_state": "Done", "hash": "x", "pulled_at": "2026-09-20T00:00:00.000Z"}}
    L = FakeL(issues)
    sb = FB.Sandbox(items)
    FB.install(m, sb)
    bl = sb.load()
    m.save_map = lambda mp_: None
    m.refresh_prompt = lambda it: None
    m.save_owner_images = lambda L_, iid, body, when: body
    m._CTX.update(bl=bl, mp=mp)
    with redirect_stdout(io.StringIO()) as log:
        m.relink_closed_tickets(L, bl, mp, TEAM, False)
        m.pull_owner(L, bl, mp, {}, False)
    defects = []
    for iid, tid in (("item-d", "t-d"), ("item-e", "t-e"), ("item-f", "t-f")):
        x = issues[tid]
        if (mp.get(iid) or {}).get("issue_id") != tid:
            defects.append("%s:non_relie" % x["identifier"])
        have = {f["via"]["comment"] for f in sb.item(iid)["owner_feedback"] if isinstance(f.get("via"), dict)}
        defects += ["%s:%s" % (x["identifier"], c["id"]) for c in x["comments"] if c["id"] not in have]
    neg = [w for w in L.writes if w == "issueCreate"]
    if (mp.get("item-f") or {}).get("issue_id") == "t-g":
        neg.append("SIM-G:relie_a_la_place_de_SIM-F")
    return {"defects": defects, "neg": neg, "missing": missing, "log": log.getvalue(),
            "den": sum(len(x["comments"]) for x in issues.values())}


sim_defects = 0
try:
    r = simulate([])
    pub("relink_closed_sim_owner_comments", r["den"])
    pub("relink_closed_sim_defects", len(r["defects"]))
    pub("relink_closed_sim_defects_named", ",".join(r["defects"]) or "-")
    pub("relink_closed_sim_negative", ",".join(r["neg"]) or "-")
    if r["neg"] or r["den"] != 3:
        dead.append("C-:" + (",".join(r["neg"]) or "monde_incomplet"))
    sim_defects = len(r["defects"])
    POS = {
        "clos": ([('        if not issue_key(iss) or iss["id"] in {',
                   '        if iss["state"]["type"] in ("completed", "canceled") or iss.get("archivedAt"):\n            continue\n'
                   '        if not issue_key(iss) or iss["id"] in {')], ("SIM-D:non_relie", "SIM-E:non_relie", "SIM-D:c-d1", "SIM-E:c-e1")),
        "archive": ([("issues(first:100, after:$a, includeArchived:true, filter:{team:{id:{eq:$t}}, '\n                'description:{contains:$k}",
                      "issues(first:100, after:$a, filter:{team:{id:{eq:$t}}, '\n                'description:{contains:$k}")],
                    ("SIM-E:non_relie", "SIM-E:c-e1")),
    }
    for tag, (seeds, expect) in POS.items():
        p = simulate(seeds)
        pub("relink_closed_ctl_pos_%s_defects" % tag, len(p["defects"]))
        pub("relink_closed_ctl_pos_%s_named" % tag, ",".join(p["defects"][:4]) or "-")
        if p["missing"]:
            dead.append("C+_%s:introuvable" % tag)
        elif not all(e in p["defects"] for e in expect):
            dead.append("C+_%s:muet" % tag)
except Exception as e:  # noqa: BLE001
    unmeasured.append("simulation:" + str(e)[:80])
    pub("relink_closed_sim_error", str(e)[:120])

pub("relink_closed_unmeasured", len(unmeasured))
pub("relink_closed_unmeasured_list", ",".join(unmeasured) or "-")
pub("relink_closed_dead_controls", len(dead))
pub("relink_closed_dead_controls_list", ",".join(dead) or "-")
pub("closed_tickets_unlinked", live_unlinked + live_missed + sim_defects + len(call_bad) + len(unmeasured) + len(dead))
for k_, v in OUT.items():
    print("%s=%s" % (k_, v))
PY
