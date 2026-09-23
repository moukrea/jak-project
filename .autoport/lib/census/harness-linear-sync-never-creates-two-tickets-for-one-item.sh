#!/usr/bin/env bash
# census/harness-linear-sync-never-creates-two-tickets-for-one-item.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `linear_duplicate_tickets`.
#
# LA CAUSE MESUREE (23/09) : `linear_map.json` est VERSIONNE. A 00:19:19-25 un `git revert` suivi d'un
# `git reset HEAD~1` l'a remis a son dernier commit : la correspondance de JAK-195 (creee a 00:12:46)
# a disparu, la veille a cree JAK-196 pour le meme item a 00:19:47, puis a adopte JAK-195 comme
# « NOUVEAU TICKET OWNER ». Le verrou n'etait pas en cause (toutes les voies le prenaient deja) ; il
# l'est depuis un worktree, ou carte ET verrou etaient ceux de l'arbre du worktree.
#
# CE QU'IL MESURE
#   A. CONTROLES FABRIQUES, hors reseau, sur un faux Linear partage (fichier + flock), en appelant les
#      VRAIES fonctions de linear_sync (ensure_ticket, load_map, save_map, map_lock, _home,
#      adopt_owner_issues). Chaque scenario a DEUX bras : le code livre, et le code d'avant
#      (lecture nue de la carte, verrou de l'arbre courant, creation sans recherche, adoption de tout
#      ticket hors carte). Bras d'avant qui ne rend PAS le defaut = controle mort = un defaut.
#        S1 carte reculee par git            (la cause du 23/09)
#        S2 carte reculee + cliche efface    (git clean -x : seule la recherche dans Linear reste)
#        S3 deux executions CONCURRENTES depuis deux arbres (principal + worktree)
#        S4 adoption : 3 tickets du harnais hors carte + 1 vrai ticket de l'owner (controle negatif :
#           il DOIT rester adopte, sinon la porte serait verte par inaction)
#   B. RECENSEMENT VIVANT de Linear : items relies a plus d'un ticket vivant, items owner-* nes d'un
#      ticket du harnais et encore actifs ; ET l'historique (etats clos compris).
#   INCONNU = DEFAUT : un terme non mesure compte 1.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "linear_duplicate_tickets=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import fcntl, io, json, multiprocessing as mp_, os, re, shutil, subprocess, sys, tempfile, time
from contextlib import redirect_stdout
from pathlib import Path
sys.path.insert(0, '.autoport')
import linear_sync as S
from lib.census import fake_backlog as FB

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
defects = 0
unmeasured = 0
SB = Path(tempfile.mkdtemp(prefix="linear-dup-"))


class FakeLinear:
    """Un Linear minimal, PARTAGE entre processus : l'etat vit dans un fichier sous flock."""
    mode = "app"
    def __init__(self, path):
        self.path = Path(path); self.n = 0
    def _tx(self, fn):
        with open(str(self.path) + ".lock", "a+") as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            st = json.loads(self.path.read_text()) if self.path.exists() else {"issues": []}
            r = fn(st)
            self.path.write_text(json.dumps(st))
            return r
    def issues(self):
        return self._tx(lambda st: list(st["issues"]))
    def q(self, query, **v):
        self.n += 1
        if "issueCreate" in query:
            def mk(st):
                i = v["i"]; n = len(st["issues"]) + 1
                iss = {"id": "fake-%d" % n, "identifier": "FAKE-%d" % n, "url": "u", "title": i["title"],
                       "description": i.get("description", ""), "createdAt": "2026-09-23T00:00:%02dZ" % n,
                       "state": {"name": "Todo", "type": "unstarted"}, "creator": {"id": "app", "app": True}}
                st["issues"].append(iss); return iss
            iss = self._tx(mk)
            return {"issueCreate": {"issue": {k: iss[k] for k in ("id", "identifier", "url")}}}
        if "includeArchived:true" in query and "or:[" in query:          # find_issue_for
            return {"issues": {"nodes": [i for i in self.issues()
                                         if v["k"] in (i["description"] or "") or i["title"] == v["ti"]]}}
        if "pageInfo" in query:                                             # adopt_owner_issues
            return {"team": {"issues": {"pageInfo": {"hasNextPage": False, "endCursor": None},
                                        "nodes": [i for i in self.issues() if i["state"]["type"] not in ("completed", "canceled")]}}}
        return {}


def point_at(tree):
    """Ce que le code LIVRE resout pour un arbre : la carte, le cliche, le verrou de son arbre principal."""
    S.AP = Path(tree) / ".autoport"
    home = S._home()
    S.HOME, S.MAP_PATH, S.SHADOW_PATH, S.LOCK_PATH = home, home / "linear_map.json", home / ".linear_map.shadow.json", home / ".linear_sync.lock"
    S._SAVED["body"] = None
    return home


ITEM = "harness-temoin-neuf"
TITLE = "Un chantier neuf du temoin"
DESC = S.KEY_FMT % ITEM + " — rang 12 — spec : —"


def pass_new(fake, map_path, tree_home, delay=0.0):
    """Code LIVRE : verrou + carte resolus depuis l'arbre, recherche puis creation."""
    L = FakeLinear(fake)
    lk = S.map_lock()
    with redirect_stdout(io.StringIO()):                 # ses lignes (CARTE RECULEE, RELIE) ne sont pas des cles
        mp = S.load_map()
        if ITEM not in mp:
            time.sleep(delay)
            S.ensure_ticket(L, mp, "team", ITEM, TITLE, {"title": TITLE, "description": DESC}, "Todo", "h")
    lk.close()


def pass_old(fake, tree, delay=0.0):
    """Code d'AVANT : verrou et carte de l'arbre COURANT, lecture nue, creation sans recherche."""
    L = FakeLinear(fake)
    ap = Path(tree) / ".autoport"
    lk = open(ap / ".linear_sync.lock", "a+"); fcntl.flock(lk, fcntl.LOCK_EX)
    mp = json.loads((ap / "linear_map.json").read_text()) if (ap / "linear_map.json").exists() else {}
    if ITEM not in mp:
        time.sleep(delay)
        r = L.q('mutation issueCreate', i={"title": TITLE, "description": DESC})
        mp[ITEM] = {"issue_id": r["issueCreate"]["issue"]["id"]}
        (ap / "linear_map.json").write_text(json.dumps(mp))
    lk.close()


def tickets(fake):
    return len([i for i in FakeLinear(fake).issues() if i["title"] == TITLE])


def mk_repo(name):
    """Un depot git jetable avec un worktree : la topologie exacte du depot et de ses worktrees."""
    main = SB / name / "main"; wt = SB / name / "wt"
    (main / ".autoport").mkdir(parents=True)
    (main / ".autoport" / "linear_sync.py").write_text("# temoin\n")
    (main / ".autoport" / "linear_map.json").write_text(json.dumps({"_gen": 0, "autre-item": {"issue_id": "x"}}))
    g = lambda *a, cwd=main: subprocess.run(["git", "-C", str(cwd)] + list(a), capture_output=True, text=True, check=True)
    g("init", "-q"); g("add", "-A")
    g("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
    g("worktree", "add", "-q", "--detach", str(wt))
    return main, wt


scen_ok = 0
# ------------------------------------------------------------------ S1 / S2 : carte reculee ----
for tag, wipe_shadow in (("s1_rollback", False), ("s2_rollback_clean", True)):
    try:
        res = {}
        for arm in ("new", "old"):
            main, _wt = mk_repo("%s-%s" % (tag, arm))
            fake = SB / ("%s-%s.fake.json" % (tag, arm))
            mapf = main / ".autoport" / "linear_map.json"
            committed = mapf.read_bytes()                       # l'etat du dernier commit
            if arm == "new":
                point_at(main); pass_new(fake, mapf, main)
            else:
                pass_old(fake, main)
            mapf.write_bytes(committed)                         # git reset --hard : la carte suivie recule
            if wipe_shadow:                                     # git clean -x : le cliche ignore part aussi
                (main / ".autoport" / ".linear_map.shadow.json").unlink(missing_ok=True)
            if arm == "new":
                point_at(main); pass_new(fake, mapf, main)
            else:
                pass_old(fake, main)
            res[arm] = tickets(fake)
        pub("linear_ctl_%s_tickets_fixed" % tag, res["new"])
        pub("linear_ctl_%s_tickets_before_fix" % tag, res["old"])
        bad = int(res["new"] != 1) + int(res["old"] != 2)
        pub("linear_ctl_%s_defects" % tag, bad); defects += bad; scen_ok += (bad == 0)
    except Exception as e:  # noqa: BLE001
        pub("linear_ctl_%s_error" % tag, str(e)[:160]); defects += 1; unmeasured += 1

# ------------------------------------------------------------ S3 : deux arbres, en meme temps ----
try:
    res = {}
    for arm in ("new", "old"):
        main, wt = mk_repo("s3-" + arm)
        fake = SB / ("s3-%s.fake.json" % arm)
        if arm == "new":
            homes = {str(point_at(main)), str(point_at(wt))}
            pub("linear_ctl_s3_homes_resolved", len(homes))     # 1 = le worktree vise l'arbre principal
            def run(tree):
                h = point_at(tree); pass_new(fake, h / "linear_map.json", h, delay=0.5)
        else:
            pub("linear_ctl_s3_homes_before_fix", len({str(main / ".autoport"), str(wt / ".autoport")}))
            def run(tree):
                pass_old(fake, tree, delay=0.5)
        ctx = mp_.get_context("fork")
        ps = [ctx.Process(target=run, args=(t,)) for t in (main, wt)]
        [p.start() for p in ps]; [p.join(60) for p in ps]
        res[arm] = tickets(fake)
        pub("linear_ctl_s3_exitcodes_%s" % arm, ",".join(str(p.exitcode) for p in ps))
    pub("linear_ctl_s3_concurrent_tickets_fixed", res["new"])
    pub("linear_ctl_s3_concurrent_tickets_before_fix", res["old"])
    bad = int(res["new"] != 1) + int(res["old"] != 2)
    pub("linear_ctl_s3_defects", bad); defects += bad; scen_ok += (bad == 0)
except Exception as e:  # noqa: BLE001
    pub("linear_ctl_s3_error", str(e)[:160]); defects += 1; unmeasured += 1

# ------------------------------------------------------------------------ S4 : adoption ----
try:
    fake = SB / "s4.fake.json"
    s4_sb = FB.Sandbox([{"id": "item-relie", "status": "open", "feature": "Chantier relie"},
                        {"id": "item-perdu", "status": "open", "feature": "Chantier perdu"},
                        {"id": "item-ancien", "status": "open", "feature": "Chantier d'avant la cle"}])
    bl = s4_sb.load()
    mp = {"item-relie": {"issue_id": "vivant-1"}, "item-ancien": {"issue_id": "vivant-2"}}
    seed = [  # (titre, description, creator.app, attendu livre)
        ("Chantier relie", S.KEY_FMT % "item-relie", True, "harness"),       # doublon d'un item relie
        ("Chantier perdu", S.KEY_FMT % "item-perdu", True, "relink"),        # ticket perdu d'un item
        ("Chantier d'avant la cle", "sans cle", False, "harness"),           # repli owner, titre du harnais
        ("Le saut de Jak est trop court", "vrai ticket", False, "owner"),    # CONTROLE NEGATIF
    ]
    st = {"issues": [{"id": "s4-%d" % n, "identifier": "FAKE-%d" % n, "title": t, "description": d,
                      "createdAt": "x", "state": {"name": "Todo", "type": "unstarted"},
                      "creator": {"id": "app" if a else "owner", "app": a}} for n, (t, d, a, _) in enumerate(seed)]}
    fake.write_text(json.dumps(st))
    buf = io.StringIO()
    with redirect_stdout(buf):
        S.adopt_owner_issues(FakeLinear(fake), bl, dict(mp), "team", None, True)
    lines = buf.getvalue().splitlines()
    adopted_new = [l for l in lines if l.startswith("NOUVEAU TICKET OWNER")]
    relinked = [l for l in lines if l.startswith("TICKET DU HARNAIS RELIE")]
    phantoms_new = len([l for l in adopted_new if "Le saut de Jak" not in l])
    owner_kept = len(adopted_new) - phantoms_new
    # regle d'AVANT : tout ticket hors carte et non clos devient un ticket de l'owner
    known = {v["issue_id"] for v in mp.values()}
    adopted_old = [i for i in st["issues"] if i["id"] not in known and i["state"]["type"] not in ("completed", "canceled")]
    phantoms_old = len([i for i in adopted_old if i["title"] != "Le saut de Jak est trop court"])
    pub("linear_ctl_s4_phantoms_fixed", phantoms_new)
    pub("linear_ctl_s4_phantoms_before_fix", phantoms_old)
    pub("linear_ctl_s4_owner_ticket_adopted", owner_kept)
    pub("linear_ctl_s4_relinked", len(relinked))
    bad = int(phantoms_new != 0) + int(phantoms_old != 3) + int(owner_kept != 1) + int(len(relinked) != 1)
    pub("linear_ctl_s4_defects", bad); defects += bad; scen_ok += (bad == 0)
    s4_sb.close()
except Exception as e:  # noqa: BLE001
    pub("linear_ctl_s4_error", str(e)[:160]); defects += 1; unmeasured += 1

pub("linear_controls_passed", scen_ok)
pub("linear_controls_total", 4)
shutil.rmtree(SB, ignore_errors=True)

# ---------------------------------------------------------------- B : Linear VIVANT ----
try:
    import importlib
    S = importlib.reload(S)                                   # chemins d'origine
    import linear_identity as LI
    from lib import backlog as B
    L = S.Linear(LI.resolve())
    bl = B.load()
    mp = json.loads(S.MAP_PATH.read_text())
    team = mp["_ids"]["team"]
    nodes, after = [], None
    while True:
        d = L.q('query($t:String!,$a:String){ team(id:$t){ issues(first:100, after:$a, includeArchived:true){ '
                'pageInfo { hasNextPage endCursor } nodes { id identifier title description archivedAt '
                'state { type } creator { app } } } } }', t=team, a=after)
        pg = d["team"]["issues"]; nodes += pg["nodes"]
        if not pg["pageInfo"]["hasNextPage"]:
            break
        after = pg["pageInfo"]["endCursor"]
    by_id = {n["id"]: n for n in nodes}
    feat = {S.item_title(it): it["id"] for it in bl.items if not it["id"].startswith("owner-")}
    alive = lambda n: not n.get("archivedAt") and n["state"]["type"] != "canceled"
    per_item = {}
    for n in nodes:
        k = S.issue_key(n)
        if k and k.startswith("owner-"):
            k = None                                          # le ticket d'un fantome se juge ci-dessous
        k = k or feat.get((n.get("title") or "").strip())
        if k and bl.get(k):
            per_item.setdefault(k, []).append(n)
    dup_hist = sorted(k for k, v in per_item.items() if len(v) > 1)
    dup_live = sorted(k for k, v in per_item.items() if len([n for n in v if alive(n)]) > 1)
    ph_hist, ph_live = [], []
    for it in bl.items:
        if not it["id"].startswith("owner-") or it["id"] not in mp:
            continue
        n = by_id.get(mp[it["id"]]["issue_id"])
        if n and ((n.get("creator") or {}).get("app") or (n.get("title") or "").strip() in feat):
            ph_hist.append("%s:%s" % (it["id"][:40], n["identifier"]))
            if it["status"] != "archived" or alive(n):
                ph_live.append("%s:%s" % (it["id"][:40], n["identifier"]))
    pub("linear_tickets_scanned", len(nodes))
    pub("linear_items_with_ticket", len(per_item))
    pub("linear_dup_items_live", len(dup_live))
    pub("linear_dup_items_live_list", ",".join(dup_live) or "-")
    pub("linear_dup_items_history", len(dup_hist))
    pub("linear_dup_items_history_list", ",".join(dup_hist) or "-")
    pub("linear_owner_items_total", len([i for i in bl.items if i["id"].startswith("owner-")]))
    pub("linear_phantom_owner_items_live", len(ph_live))
    pub("linear_phantom_owner_items_live_list", ",".join(ph_live) or "-")
    pub("linear_phantom_owner_items_history", len(ph_hist))
    pub("linear_phantom_owner_items_history_list", ",".join(ph_hist) or "-")
    pub("linear_live_measured", 1)
    defects += len(dup_live) + len(ph_live)
except Exception as e:  # noqa: BLE001
    pub("linear_live_measured", 0)
    pub("linear_live_error", str(e)[:160])
    defects += 1; unmeasured += 1

pub("linear_duplicate_terms_unmeasured", unmeasured)
pub("linear_duplicate_tickets", defects)
for k, v in OUT.items():
    print("%s=%s" % (k, v))
PY
