#!/usr/bin/env bash
# census/harness-linear-pull-reads-archived-tickets.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `owner_archived_comments_lost`.
#
# LE DEFAUT (owner 23/09 : « oui ouvre ») : un commentaire de l'owner pose sur un ticket ARCHIVE n'etait pas recopie,
# et un ticket de chantier vivant que l'owner archive lui-meme n'etait lu comme aucune decision. La synchro archive
# desormais d'elle-meme (129 tickets sur 220 le 23/09) : la population concernee est la majorite des tickets.
#
# CE QU'IL MESURE — `owner_archived_comments_lost` = somme de :
#   C  VIVANT, commentaires : chaque commentaire de l'owner (tous, pagines) sur un ticket ARCHIVE de la carte dont
#      l'identifiant n'est dans AUCUN `owner_feedback[].via.comment` de l'item du ticket.
#   A  VIVANT, decisions : chaque ticket de la carte dont le DERNIER archivage (historique Linear, seule source qui
#      dise QUI) est de l'owner, sans desarchivage de l'owner apres, alors que l'item est encore vivant
#      (open / in-progress / blocked / to-test) : archivage de l'owner non applique.
#   INCONNU = DEFAUT : un terme non mesure compte 1 ; un controle negatif qui ne rend pas 0 compte 1 ; un controle
#   positif qui ne rougit pas (ou qui ne NOMME pas son defaut) compte 1.
# CONTROLES (monde SIMULE : faux Linear en memoire, `pull_owner` et `push_existing` REELS, rejoues depuis le source) :
#   C-  code livre : 0 perte, 0 fausse decision, le ticket archive par l'owner le reste, aucun message ne lui part.
#   C+1 `includeArchived` retire du tirage : le commentaire sur l'archive est perdu et NOMME.
#   C+2 decision retiree (`ev = None`) : l'archivage de l'owner n'est pas applique et NOMME.
#   C+3 piege du `last_state` rendu (etat refuse sur un archive compte comme pose + tout ecart lu comme deplacement) :
#       le tirage suivant rouvre le chantier, le ressort des archives et lui ecrit : NOMME.
# Hors porte, publie : `linear_archived_write_unguarded` (livrable 2 : ecriture sur un ticket sans `on_ticket`, ni
# garde de l'appelant, ni exemption NOMMEE) avec ses controles.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "owner_archived_comments_lost=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import ast, copy, io, os, re, sys, types
from contextlib import redirect_stdout
from pathlib import Path
sys.path.insert(0, '.autoport')

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
unmeasured = []    # termes non mesures (1 chacun)
dead = []          # controles qui ne tiennent pas (1 chacun)
LIVE = ("open", "in-progress", "blocked", "to-test")
# `CENSUS_CONTROLS_ONLY=1` (harness-archived-census-controls-are-alive) : les CONTROLES seuls, sans toucher Linear.
# Le terme vivant n'est pas mesure et le dit (`owner_archived_live=saute`) : ce mode ne rend jamais la porte de CET item.
CONTROLS_ONLY = os.environ.get("CENSUS_CONTROLS_ONLY") == "1"
class SkipLive(Exception):
    pass
SRC_PATH = Path(".autoport/linear_sync.py")
SRC = SRC_PATH.read_text()


def author(e, owner_id):
    """Auteur d'un evenement d'historique, classe ICI (instrument independant de `history_author`)."""
    if e.get("autoArchived"):
        return "auto"
    if (e.get("botActor") or {}).get("id") or (e.get("actor") or {}).get("app"):
        return "app"
    who = (e.get("actor") or {}).get("id")
    if not who:
        return "inconnu"
    return "owner" if who == owner_id else "autre"


def undone_decision(hist, owner_id):
    """Le dernier archivage de l'owner, s'il n'a pas ete defait PAR L'OWNER ensuite ; sinon None."""
    hist = sorted(hist, key=lambda e: e["createdAt"])
    last = None
    for e in hist:
        if e.get("archived") is True and author(e, owner_id) == "owner":
            last = e
        elif e.get("archived") is False and author(e, owner_id) == "owner":
            last = None
    return last


def measure(world_issues, items_by_id, recs, owner_id, hist_of):
    """-> (commentaires perdus [noms], decisions non appliquees [noms], denominateurs)."""
    lost_c, lost_a, n_arch, n_oc, n_dec = [], [], 0, 0, 0
    for iid, rec in recs.items():
        iss = world_issues.get(rec["issue_id"])
        if iss is None:
            continue
        it = items_by_id.get(iid)
        have = {f["via"]["comment"] for f in ((it or {}).get("owner_feedback") or [])
                if isinstance(f, dict) and isinstance(f.get("via"), dict) and f["via"].get("comment")}
        if iss.get("archivedAt"):
            n_arch += 1
            for c in iss["comments"]:
                if c["_owner"]:
                    n_oc += 1
                    if c["id"] not in have:
                        lost_c.append("%s:%s:%s" % (rec.get("identifier"), iid, c["createdAt"]))
        hist = hist_of(rec["issue_id"], iss)
        if hist is None:
            continue
        ev = undone_decision(hist, owner_id)
        if ev:
            n_dec += 1
            if it is not None and it.get("status") in LIVE:
                lost_a.append("%s:%s:%s" % (rec.get("identifier"), iid, it.get("status")))
    return lost_c, lost_a, {"archived": n_arch, "owner_comments": n_oc, "owner_decisions": n_dec}


# ============================================================================== VIVANT (Linear) ==
try:
    if CONTROLS_ONLY:
        raise SkipLive
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
        d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:25, includeArchived:true){ nodes { id archivedAt '
                'comments(first:100){ pageInfo { hasNextPage endCursor } nodes { ' + OSLA.COMMENT_FIELDS + ' } } } } }',
                ids=ids[i:i + 25])
        for n in d["issues"]["nodes"]:
            cs = n["comments"]["nodes"] + OSLA._rest(L, n["id"], n["comments"]["pageInfo"])
            for c in cs:
                c["_owner"] = S.is_owner_comment(c, owner_id)
            world[n["id"]] = {"archivedAt": n.get("archivedAt"), "comments": cs}
    pub("owner_archived_tracked", len(recs))
    pub("owner_archived_returned", len(world))
    if len(world) != len(recs):
        unmeasured.append("tickets_non_rendus:%d" % (len(recs) - len(world)))

    def live_hist(issue_id, iss):
        # L'historique d'un ticket archive (qui a archive ?) et d'un ticket dont l'item a ete archive par NOTRE
        # decision (le desarchivage de l'owner doit se voir) ; les autres n'ont pas d'archivage a juger.
        if not iss.get("archivedAt") and not any(r.get("issue_id") == issue_id and r.get("owner_archived_at") for r in recs.values()):
            return []
        out, after = [], None
        while True:
            h = L.q('query($id:String!,$a:String){ issue(id:$id){ history(first:100, after:$a){ pageInfo { hasNextPage endCursor } '
                    'nodes { createdAt archived autoArchived actor { id app } botActor { id } } } } }', id=issue_id, a=after)["issue"]["history"]
            out += h["nodes"]
            if not h["pageInfo"]["hasNextPage"]:
                return out
            after = h["pageInfo"]["endCursor"]

    by_author = {}
    hists = {}
    def hist_of(issue_id, iss):
        if issue_id not in hists:
            hists[issue_id] = live_hist(issue_id, iss)
            last = next((e for e in sorted(hists[issue_id], key=lambda e: e["createdAt"], reverse=True) if e.get("archived") is True), None)
            if iss.get("archivedAt"):
                w = author(last, owner_id) if last else "sans_evenement"
                by_author[w] = by_author.get(w, 0) + 1
        return hists[issue_id]

    lost_c, lost_a, den = measure(world, {it["id"]: it for it in bl.items}, recs, owner_id, hist_of)
    pub("owner_archived_tickets", den["archived"])
    pub("owner_archived_owner_comments", den["owner_comments"])
    pub("owner_archived_comments_missing", len(lost_c))
    pub("owner_archived_comments_missing_first", ",".join(lost_c[:5]) or "-")
    pub("owner_archive_decisions", den["owner_decisions"])
    pub("owner_archive_decisions_unapplied", len(lost_a))
    pub("owner_archive_decisions_unapplied_first", ",".join(lost_a[:5]) or "-")
    pub("owner_archive_by_author", ",".join("%s:%d" % kv for kv in sorted(by_author.items())) or "-")
    pub("owner_archived_identity", getattr(L, "mode", "?"))
    pub("owner_archived_queries", L.n)
    live_lost = len(lost_c) + len(lost_a)
except SkipLive:
    live_lost = 0
    unmeasured.append("vivant:saute")
    pub("owner_archived_live", "saute")
except Exception as e:  # noqa: BLE001 — un terme non mesure est un DEFAUT, jamais un zero
    unmeasured.append("vivant:" + str(e)[:80])
    live_lost = 0
    pub("owner_archived_live_error", str(e)[:120])

# ============================================================================ MONDE SIMULE ==
OWNER, APP = "u-owner", "u-app"
STATES = {"Backlog": "s-bl", "Todo": "s-todo", "In Progress": "s-ip", "In Review": "s-ir", "À arbitrer": "s-arb",
          "Done": "s-done", "Canceled": "s-can"}


class FakeL:
    """Faux Linear : un ticket archive manque a une COLLECTION sans `includeArchived`, et refuse toute ecriture
    (« Entity not found ») tant qu'on ne l'a pas ressorti ; chaque ecriture est journalisee."""
    mode = "app"

    def __init__(self, issues):
        self.issues, self.n, self.writes = issues, 0, []

    def q(self, query, **v):
        self.n += 1
        if query.lstrip().startswith("mutation"):
            tid = v.get("id") or (v.get("i") or {}).get("issueId")
            iss = self.issues.get(tid)
            kind = re.search(r"\{\s*(\w+)\(", query).group(1)
            if kind == "issueUnarchive":
                iss["archivedAt"] = None
                iss["history"].append({"createdAt": "2026-09-23T12:00:%02dZ" % self.n, "archived": False, "actor": {"id": APP, "app": True}})
                self.writes.append((kind, tid))
                return {kind: {"success": True}}
            if iss is None or iss.get("archivedAt"):
                raise RuntimeError("Entity not found: Issue - %s" % kind)
            self.writes.append((kind, tid))
            if kind == "commentCreate":
                iss["comments"].append({"id": "c-app-%d" % self.n, "body": v["i"]["body"], "createdAt": "2026-09-23T12:00:%02dZ" % self.n,
                                        "user": {"id": APP, "app": True}, "botActor": None, "reactions": []})
            if kind == "issueUpdate" and "stateId" in (v.get("i") or {}):
                iss["state"] = {v2: k for k, v2 in STATES.items()}[v["i"]["stateId"]]
            return {kind: {"success": True}}
        if "history(" in query:
            return {"issue": {"history": {"pageInfo": {"hasNextPage": False, "endCursor": None},
                                          "nodes": sorted(self.issues[v["id"]]["history"], key=lambda e: e["createdAt"], reverse=True)}}}
        if "issues(filter:{id:{in:$ids}}" in query:
            keep = "includeArchived:true" in query.replace(" ", "")
            nodes = [{"id": i, "archivedAt": x["archivedAt"], "state": {"name": x["state"]}, "labels": {"nodes": []},
                      "comments": {"nodes": list(reversed(x["comments"]))}}
                     for i, x in self.issues.items() if i in v["ids"] and (keep or not x["archivedAt"])]
            return {"issues": {"nodes": nodes}}
        raise RuntimeError("faux Linear : requete inattendue : " + query[:60])


def fake_world():
    def oc(i, t):
        return {"id": i, "body": "retour %s" % i, "createdAt": t, "user": {"id": OWNER, "app": False}, "botActor": None, "reactions": []}
    ev = lambda t, a, who: {"createdAt": t, "archived": a, "actor": {"id": who, "app": who == APP}}
    issues = {
        # A : chantier valide, ticket archive par le harnais ; l'owner y commente apres l'archivage
        "t-a": {"state": "Done", "archivedAt": "2026-09-22T10:00:00Z", "comments": [oc("c-a1", "2026-09-22T11:00:00Z")],
                "history": [ev("2026-09-22T10:00:00Z", True, APP)]},
        # B : chantier OUVERT, ticket archive par l'OWNER : sa decision
        "t-b": {"state": "Todo", "archivedAt": "2026-09-22T12:00:00Z", "comments": [],
                "history": [ev("2026-09-22T12:00:00Z", True, OWNER)]},
        # C : chantier ouvert, ticket vivant, un commentaire (temoin de la voie normale)
        "t-c": {"state": "Todo", "archivedAt": None, "comments": [oc("c-c1", "2026-09-22T13:00:00Z")], "history": []},
        # D : chantier ROUVERT par le superviseur, ticket encore archive par le HARNAIS : pas une decision de l'owner
        "t-d": {"state": "Done", "archivedAt": "2026-09-21T10:00:00Z", "comments": [],
                "history": [ev("2026-09-21T10:00:00Z", True, APP)]},
    }
    items = [
        {"id": "item-a", "status": "validated", "owner_feedback": [], "notes": ""},
        {"id": "item-b", "status": "open", "owner_feedback": [], "notes": "", "priority": 5},
        {"id": "item-c", "status": "open", "owner_feedback": [], "notes": "", "priority": 6},
        {"id": "item-d", "status": "open", "owner_feedback": [], "notes": "", "priority": 7},
    ]
    mp = {"_owner": {"user_id": OWNER}}
    for k in "abcd":
        mp["item-" + k] = {"issue_id": "t-" + k, "identifier": "SIM-" + k.upper(), "last_state": issues["t-" + k]["state"],
                           "hash": "x", "pulled_at": "2026-09-20T00:00:00Z"}
    return issues, items, mp


class FakeBL:
    def __init__(self, items):
        self.items, self.path = items, "/dev/null"

    def get(self, i):
        return next((x for x in self.items if x["id"] == i), None)

    def set_status(self, i, status, **f):
        it = self.get(i); it["status"] = status; it.update(f); return it

    def add_owner_feedback(self, i, date, text, via=None):
        e = {"date": date, "text": text}
        if via:
            e["via"] = dict(via)
        self.get(i)["owner_feedback"].append(e)

    def validate(self, i, text, date=None, via=None):
        self.set_status(i, "validated", owner_ok=text)


def load_variant(seeds):
    """Le module `linear_sync` REEL, rejoue depuis son source avec les remplacements `seeds` (controles positifs).
    Un remplacement introuvable = controle MORT (le code a change sous lui)."""
    src, missing = SRC, []
    for old, new in seeds:
        if src.count(old) != 1:
            missing.append(old[:40])
        src = src.replace(old, new)
    m = types.ModuleType("linear_sync_sim")
    m.__file__ = str(SRC_PATH.resolve())
    exec(compile(src, "linear_sync_sim", "exec"), m.__dict__)
    return m, missing


def simulate(seeds):
    m, missing = load_variant(seeds)
    issues, items, mp = fake_world()
    L = FakeL(issues)
    bl = FakeBL(items)
    m.B = types.SimpleNamespace(load=lambda: bl)
    m.refresh_prompt = lambda it: None
    m.save_owner_images = lambda L_, iid, body, when: body
    m._CTX.update(bl=bl, mp=mp)
    log = io.StringIO()
    with redirect_stdout(log):
        for _pass in range(2):                       # tirage -> envoi -> tirage : le piege vit au 2e tirage
            m.pull_owner(L, bl, mp, {}, False)
            for it in bl.items:
                rec = mp[it["id"]]
                st = m.target_state(bl, it)
                if rec.get("last_state") != st:
                    m.push_existing(L, bl, it, rec, {"stateId": STATES[st]}, st, "h-" + st, None, None)
    world = {i: {"archivedAt": x["archivedAt"],
                 "comments": [dict(c, _owner=(c["user"]["id"] == OWNER)) for c in x["comments"]]} for i, x in issues.items()}
    recs = {k: v for k, v in mp.items() if not k.startswith("_")}
    lost_c, lost_a, den = measure(world, {it["id"]: it for it in items}, recs, OWNER, lambda i, iss: issues[i]["history"])
    # ce que le monde simule sait en plus : le ticket de l'owner reste archive, rien ne lui est ecrit, et le chantier
    # rouvert par le superviseur (D) n'est pas pris pour une decision de l'owner
    undone = ["SIM-B:ressorti"] if not issues["t-b"]["archivedAt"] else []
    undone += ["SIM-B:ecrit:%s" % k for k, t in L.writes if t == "t-b" and k != "issueUnarchive"]
    false_dec = ["SIM-D:%s" % bl.get("item-d")["status"]] if bl.get("item-d")["status"] not in LIVE else []
    names = lost_c + lost_a + undone + false_dec
    return {"lost": len(lost_c) + len(lost_a) + len(undone), "false": len(false_dec), "names": names,
            "missing": missing, "den": den, "log": log.getvalue()}


try:
    neg = simulate([])
    pub("owner_archived_ctl_neg_lost", neg["lost"])
    pub("owner_archived_ctl_neg_false_decisions", neg["false"])
    pub("owner_archived_ctl_neg_owner_comments", neg["den"]["owner_comments"])
    pub("owner_archived_ctl_neg_decisions", neg["den"]["owner_decisions"])
    if neg["lost"] or neg["false"] or neg["den"]["owner_comments"] < 1 or neg["den"]["owner_decisions"] < 1:
        dead.append("C-:" + (",".join(neg["names"]) or "denominateur_vide"))
    Q_OLD = "first:40, includeArchived:true){ nodes { id archivedAt state { name } labels"
    POS = {
        "flag": [(Q_OLD, Q_OLD.replace(", includeArchived:true", ""))],
        "decision": [("ev = owner_archived(L, hist, owner_id, rec)", "ev = None")],
        "last_state": [('rec.update({"hash": h, "stale_archived": True})', 'rec.update({"last_state": st, "hash": h})'),
                       # 23/09 (harness-linear-stale-map-never-fakes-an-owner-move) : l'attribution passe par `owner_move` pour
                       # TOUT ecart ; le defaut d'avant (tout ecart = l'owner) se seme sur son appel.
                       ('mv, why = owner_move(L, hist, owner_id, here, rec)', 'mv, why = {"createdAt": ""}, "carte"')],
    }
    EXPECT = {"flag": "SIM-A:item-a", "decision": "SIM-B:item-b", "last_state": "SIM-B:"}
    for tag, seeds in POS.items():
        r = simulate(seeds)
        pub("owner_archived_ctl_pos_%s_lost" % tag, r["lost"])
        pub("owner_archived_ctl_pos_%s_named" % tag, ",".join(r["names"][:3]) or "-")
        if r["missing"]:
            dead.append("C+_%s:introuvable" % tag)
        elif r["lost"] < 1 or not any(n.startswith(EXPECT[tag]) for n in r["names"]):
            dead.append("C+_%s:muet" % tag)
except Exception as e:  # noqa: BLE001
    unmeasured.append("simulation:" + str(e)[:80])
    pub("owner_archived_sim_error", str(e)[:120])

# ======================================== LIVRABLE 2 : toute ecriture sur un ticket passe par on_ticket ==
WRITE = re.compile(r"\{\s*(issueUpdate|commentCreate|commentUpdate|issueRelationCreate|issueArchive|issueUnarchive|"
                   r"issueDelete|attachmentCreate|attachmentLinkURL|reactionCreate|issueAddLabel|issueRemoveLabel)\s*\(")
# Ecritures qui ne visent JAMAIS un ticket archive, NOMMEES avec leur raison : (fichier, fonction, mutation, jeton de ligne).
EXEMPT = {
    (".autoport/linear_sync.py", "make_room", "issueArchive", "issueArchive"): "archive un ticket clos NON archive (liste tiree sans includeArchived)",
    (".autoport/linear_sync.py", "<module>", "issueUnarchive", "UNARCHIVE"): "le desarchivage lui-meme, appele par on_ticket",
    (".autoport/linear_sync.py", "main", "issueUpdate", 'states["Canceled"]'): "--check : garde par `not archivedAt` lu dans le meme passage",
    (".autoport/linear_sync.py", "main", "issueUpdate", "sortOrder"): "rang pose sur un ticket qu'on vient de CREER",
}


def functions(text):
    """-> [(debut, fin, nom)] par l'indentation."""
    lines, out = text.splitlines(), []
    for n, l in enumerate(lines):
        m = re.match(r"(\s*)def (\w+)", l)
        if m:
            ind = len(m.group(1)); end = len(lines)
            for k in range(n + 1, len(lines)):
                s = lines[k]
                if s.strip() and len(s) - len(s.lstrip()) <= ind and not s.lstrip().startswith(("#", ")")):
                    end = k; break
            out.append((n, end, m.group(2)))
    return out


def func_at(fns, n):
    inner = [f for f in fns if f[0] <= n < f[1]]
    return min(inner, key=lambda f: f[1] - f[0])[2] if inner else "<module>"


def guarded_at(lines, n):
    """La ligne n est-elle dans le `lambda` d'un `on_ticket(` ouvert sur elle ou les 3 precedentes ?"""
    win = "\n".join(lines[max(0, n - 3):n + 1])
    k = win.rfind("on_ticket(")
    return k >= 0 and "lambda" in win[k:]


def scan_writes(name, text):
    lines, fns, out = text.splitlines(), functions(text), []
    for m in WRITE.finditer(text):
        n = text.count("\n", 0, m.start())
        f = func_at(fns, n)
        site = {"where": "%s:%d:%s:%s" % (name, n + 1, f, m.group(1)), "guard": "", "exempt": None}
        if guarded_at(lines, n):
            site["guard"] = "on_ticket"
        else:
            # garde de l'APPELANT : chaque appel de la fonction est sous on_ticket (un niveau)
            calls = [k for k, l in enumerate(lines) if re.search(r"(?<![\w.])%s\(" % re.escape(f), l) and not re.match(r"\s*def ", l)]
            if f != "<module>" and calls and all(guarded_at(lines, k) for k in calls):
                site["guard"] = "appelant"
        if not site["guard"]:
            for (fn_, fu, mu, tok), why in EXEMPT.items():
                if fn_ == name and fu == f and mu == m.group(1) and tok in "\n".join(lines[n:n + 2]):
                    site["exempt"] = (fn_, fu, mu, tok)
        out.append(site)
    return out


def unguard(src, func, mutation):
    """Graine STRUCTURELLE : dans la fonction `func`, chaque appel `on_ticket(..., lambda: <corps>)` dont le corps porte
    `mutation` est remplace par `(<corps>)`. Lue sur l'ARBRE, pas sur une ligne : `return on_ticket(` devenu
    `r = on_ticket(` (ef3327822c) avait tue la graine litterale sans un mot. -> (source semee, nombre d'appels semes)."""
    b = src.encode()
    starts, k = [0], 0
    for l in b.splitlines(keepends=True):
        k += len(l)
        starts.append(k)
    at = lambda ln, col: starts[ln - 1] + col   # col_offset d'ast = octets UTF-8
    cuts = []
    for fn in ast.walk(ast.parse(src)):
        if not (isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)) and fn.name == func):
            continue
        for c in ast.walk(fn):
            if isinstance(c, ast.Call) and isinstance(c.func, ast.Name) and c.func.id == "on_ticket":
                lam = [a for a in c.args if isinstance(a, ast.Lambda)]
                body = b[at(lam[0].body.lineno, lam[0].body.col_offset):at(lam[0].body.end_lineno, lam[0].body.end_col_offset)] if lam else b""
                if mutation.encode() in body:
                    cuts.append((at(c.lineno, c.col_offset), at(c.end_lineno, c.end_col_offset), body))
    for s, e, body in sorted(cuts, reverse=True):
        b = b[:s] + b"(" + body + b")" + b[e:]
    return b.decode(), len(cuts)


try:
    import subprocess
    files = [f for f in subprocess.run(["git", "ls-files", ".autoport"], capture_output=True, text=True).stdout.split()
             if f.endswith((".py", ".sh", ".bash")) and not re.match(r"\.autoport/(archive|reports|logs|tests|lib/census)/", f)]
    sites = []
    for f in files:
        t = Path(f).read_text(errors="replace") if f != ".autoport/linear_sync.py" else SRC
        if WRITE.search(t):
            sites += scan_writes(f, t)
    bad = [s["where"] for s in sites if not s["guard"] and not s["exempt"]]
    used = {s["exempt"] for s in sites if s["exempt"]}
    pub("linear_archived_write_sites", len(sites))
    pub("linear_archived_write_guarded", len([s for s in sites if s["guard"]]))
    pub("linear_archived_write_exempt", len(used))
    pub("linear_archived_write_exempt_stale", ",".join("%s:%s" % k[1:3] for k in EXEMPT if k not in used) or "-")
    pub("linear_archived_write_unguarded", len(bad))
    pub("linear_archived_write_unguarded_first", ",".join(bad[:4]) or "-")
    # controles du recensement statique
    seeded, n_seeded = unguard(SRC, "post_comment", "commentCreate")
    pub("linear_archived_write_ctl_pos_seeded", n_seeded)
    seeded += "\n\ndef poke(L, i):\n    return L.q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }', i=i)\n"
    sb = [s["where"] for s in scan_writes(".autoport/linear_sync.py", seeded) if not s["guard"] and not s["exempt"]]
    pub("linear_archived_write_ctl_pos", ",".join(sb) or "-")
    if n_seeded != 1:
        dead.append("C+_statique:introuvable")
    elif not (any(w.endswith(":post_comment:commentCreate") for w in sb) and any(w.endswith(":poke:commentCreate") for w in sb)):
        dead.append("C+_statique")
    clean = "def poke(L, i):\n    return on_ticket(L, i, lambda: L.q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }', i=i))\n"
    if [s for s in scan_writes("sain.py", clean) if not s["guard"]]:
        dead.append("C-_statique")
except Exception as e:  # noqa: BLE001
    pub("linear_archived_write_unguarded", "inconnu")
    pub("linear_archived_write_error", str(e)[:120])

pub("owner_archived_unmeasured", len(unmeasured))
pub("owner_archived_unmeasured_list", ",".join(unmeasured) or "-")
pub("owner_archived_dead_controls", len(dead))
pub("owner_archived_dead_controls_list", ",".join(dead) or "-")
pub("owner_archived_comments_lost", live_lost + len(unmeasured) + len(dead))
for k_, v in OUT.items():
    print("%s=%s" % (k_, v))
PY
