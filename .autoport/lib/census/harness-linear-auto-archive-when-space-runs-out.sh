#!/usr/bin/env bash
# census/harness-linear-auto-archive-when-space-runs-out.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `linear_space_defects`.
#
# LA CAUSE MESUREE (23/09, logs/linear_sync.txt) : 275 tickets actifs pour une limite de 250 (plan gratuit,
# metrique `activeIssueCount` = tout ticket NON archive, clos compris) : chaque passage mourait sur
# `issueCreate` -> USAGE_LIMIT_EXCEEDED. Apres l'archivage de 169 tickets a la main, chaque passage mourait
# sur `commentCreate` -> « Entity not found: Issue » (un verdict adresse a un ticket archive), et le
# passage ENTIER tombait avec lui.
#
# CE QU'IL MESURE
#   A. CONTROLES FABRIQUES, hors reseau, sur un faux Linear qui repond comme le vrai (memes erreurs), en
#      appelant les VRAIES fonctions de linear_sync (make_room, post_comment, swap_labels, on_ticket,
#      ensure_ticket, announce_verdicts). Le bras « avant » rejoue l'appel nu d'avant le correctif et DOIT
#      rendre le defaut (sinon controle mort = un defaut).
#        C1  espace au-dessus du seuil      -> archivage des clos les plus anciens, jamais un chantier ouvert
#        C1b notre equipe n'a pas assez     -> les autres equipes seulement apres les notres
#        C2  sous le seuil (NEGATIF)        -> rien d'archive ; et le recensement ne se refait pas avant 5 min
#        C3  ticket archive commente        -> ressorti, commente, pas de plantage
#        C3L idem, espace A la limite       -> le desarchivage refuse fait de la place puis reussit
#        C3U mise a jour d'un clos archive  -> laisse archive (NEGATIF : on ne ressort pas pour rien)
#        C3S etiquette sur un ticket archive-> pas de plantage
#        C4  creation refusee (limite)      -> archivage puis UNE nouvelle tentative, ticket cree
#        C4b creation refusee, rien a archiver -> exactement 2 essais, refus remonte (pas de boucle)
#        C5  un ticket casse parmi trois    -> les deux autres sont annonces, le casse est NOMME
#   B. LINEAR VIVANT : tickets actifs / limite, clos archivables, chantiers actifs sans ticket ; et le
#      journal de la veille : les passages du code EN PLACE (ligne `SYNCHRO code=<empreinte>`) et leurs
#      plantages.
#   INCONNU = DEFAUT : un terme non mesure compte 1.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "linear_space_defects=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import io, json, shutil, sys, tempfile, time
from contextlib import redirect_stdout
from pathlib import Path
sys.path.insert(0, '.autoport')
import linear_sync as S

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
defects = 0
unmeasured = 0
SB = Path(tempfile.mkdtemp(prefix="linear-space-"))
TEAM, OTHER, TODO = "team-jak", "team-autre", "label-todo"


def err(msg, code):
    return RuntimeError(json.dumps([{"message": msg, "extensions": {"code": code}}]))


class FakeLinear:
    """Un Linear minimal qui repond comme le vrai : limite d'espace sur les tickets NON archives, et
    « Entity not found: Issue » sur toute ecriture adressee a un ticket archive ou absent."""
    mode = "app"
    def __init__(self, limit=250):
        self.limit, self.iss, self.n, self.calls, self.comments = limit, {}, 0, [], []
    def add(self, i, state="completed", when="2026-09-01", team=TEAM, labels=(), archived=False):
        self.iss[i] = {"id": i, "identifier": i.upper(), "state": state, "team": team, "labels": list(labels),
                       "archived": archived, "when": when}
    def active(self):
        return [x for x in self.iss.values() if not x["archived"]]
    def _live(self, i):
        x = self.iss.get(i)
        if x is None or x["archived"]:
            raise err("Entity not found: Issue", "INPUT_ERROR")
        return x
    def _page(self, nodes, a):
        k = int(a or 0)
        return {"issues": {"pageInfo": {"hasNextPage": k + 250 < len(nodes), "endCursor": str(k + 250)},
                           "nodes": nodes[k:k + 250]}}
    def q(self, query, **v):
        self.n += 1
        op = next((o for o in ("issueArchive", "issueUnarchive", "issueCreate", "commentCreate", "issueUpdate")
                   if o in query), "query")
        self.calls.append(op)
        if op == "issueArchive":
            self._live(v["id"])["archived"] = True; return {"issueArchive": {"success": True}}
        if op == "issueUnarchive":
            x = self.iss.get(v["id"])
            if x is None:
                raise err("Entity not found: Issue", "INPUT_ERROR")
            if len(self.active()) >= self.limit:
                raise err("usage limit exceeded", "USAGE_LIMIT_EXCEEDED")
            x["archived"] = False; return {"issueUnarchive": {"success": True}}
        if op == "issueCreate":
            if len(self.active()) >= self.limit:
                raise err("usage limit exceeded", "USAGE_LIMIT_EXCEEDED")
            i = "neuf-%d" % len(self.iss); self.add(i, state="unstarted", when="2026-09-23")
            return {"issueCreate": {"issue": {"id": i, "identifier": i.upper(), "url": "u"}}}
        if op == "commentCreate":
            self._live(v["i"]["issueId"]); self.comments.append(v["i"]["issueId"])
            return {"commentCreate": {"success": True}}
        if op == "issueUpdate":
            x = self._live(v["id"])
            if "labelIds" in v["i"]:
                x["labels"] = list(v["i"]["labelIds"])
            return {"issueUpdate": {"success": True}}
        if "issue(id:" in query:                                         # lecture : le vrai rend aussi l'archive
            x = self.iss.get(v["id"])
            return {"issue": {"labels": {"nodes": [{"id": l} for l in x["labels"]]}} if x else None}
        if "or:[" in query:                                              # find_issue_for : aucun existant
            return {"issues": {"nodes": []}}
        if "filter:{state" in query:                                     # archivable
            nodes = [{"id": x["id"], "identifier": x["identifier"], "completedAt": x["when"] + "T00:00:00.000Z",
                      "team": {"id": x["team"]}, "labels": {"nodes": [{"id": l} for l in x["labels"]]}}
                     for x in self.active() if x["state"] in ("completed", "canceled")]
            return self._page(nodes, v.get("a"))
        if "issues(first:250" in query:                                  # count_active
            return self._page([{"id": x["id"]} for x in self.active()], v.get("a"))
        raise AssertionError("requete non simulee : " + query[:80])


class FakeBacklog:
    def __init__(self, items): self.items = items
    def get(self, iid): return next((i for i in self.items if i["id"] == iid), None)


def reset(bl_items=(), mp=None):
    """Chaque controle part d'un bac a sable neuf : espace, carte, contexte, echecs."""
    d = Path(tempfile.mkdtemp(dir=SB))
    S.SPACE_PATH, S.MAP_PATH, S.SHADOW_PATH = d / "space.json", d / "map.json", d / "shadow.json"
    S._SAVED["body"] = None
    S.FAILED.clear()
    S._CTX.update(bl=FakeBacklog(list(bl_items)), mp=mp or {}, todo=TODO, team=TEAM)
    return d


def run(fn):
    buf = io.StringIO()
    with redirect_stdout(buf):
        r = fn()
    return r, buf.getvalue()


def control(tag, fn):
    """fn() rend le nombre de defauts du controle ; une exception = defaut + non mesure."""
    global defects, unmeasured
    try:
        bad = fn()
    except Exception as e:  # noqa: BLE001
        pub("linear_ctl_%s_error" % tag, str(e)[:160]); bad = 1; unmeasured += 1
    pub("linear_ctl_%s_defects" % tag, bad); defects += bad
    return bad == 0


def day(k):
    return "2026-%02d-%02d" % (1 + k // 28, 1 + k % 28)


def seed_space(L, n_open, n_closed, n_other=0, kept=0, todo=0):
    """n_open ouverts ; n_closed clos de notre equipe (les `kept` premiers relies a un chantier OUVERT du
    backlog, les `todo` suivants portant « A traiter ») ; n_other clos d'une autre equipe, plus ANCIENS."""
    for k in range(n_open):
        L.add("o%d" % k, state="unstarted")
    for k in range(n_other):
        L.add("x%d" % k, when=day(k), team=OTHER)
    items, mp = [], {}
    for k in range(n_closed):
        L.add("c%d" % k, when=day(k), labels=[TODO] if kept <= k < kept + todo else [])
        if k < kept:
            items.append({"id": "rouvert-%d" % k, "status": "in-progress"})
            mp["rouvert-%d" % k] = {"issue_id": "c%d" % k, "identifier": "C%d" % k}
    return items, mp


passed = 0
# ---------------------------------------------------------------- C1 : au-dessus du seuil ----
def c1():
    L = FakeLinear()
    items, mp = seed_space(L, 30, 190, n_other=10, kept=5, todo=1)       # 230 actifs, seuil 212, cible 187
    reset(items, mp)
    st, log = run(lambda: S.make_room(L, force=True))
    arch = [x["id"] for x in L.iss.values() if x["archived"]]
    want = ["c%d" % k for k in range(6, 6 + 44)]                        # les 44 plus anciens eligibles des notres
    pub("linear_ctl_c1_active_before", 230)
    pub("linear_ctl_c1_active_after", len(L.active()))
    pub("linear_ctl_c1_archived", len(arch))
    pub("linear_ctl_c1_archived_logged", log.count("ARCHIVE AUTO :"))
    pub("linear_ctl_c1_kept_archived", len([a for a in arch if a in ("c0", "c1", "c2", "c3", "c4", "c5")]))
    pub("linear_ctl_c1_other_team_archived", len([a for a in arch if a.startswith("x")]))
    pub("linear_ctl_c1_space_published", int(json.loads(S.SPACE_PATH.read_text()).get("active") == len(L.active())))
    return (int(sorted(arch) != sorted(want)) + int(len(L.active()) >= int(250 * S.SPACE_HIGH))
            + int(log.count("ARCHIVE AUTO :") != len(arch)) + int(st is None or st["archived"] != len(arch)))
passed += control("c1_above_threshold", c1)


def c1b():
    L = FakeLinear()
    items, mp = seed_space(L, 150, 20, n_other=60)                      # 230 : 20 des notres, 60 d'une autre equipe
    reset(items, mp)
    run(lambda: S.make_room(L, force=True))
    arch = [x["id"] for x in L.iss.values() if x["archived"]]
    ours, others = [a for a in arch if a.startswith("c")], [a for a in arch if a.startswith("x")]
    pub("linear_ctl_c1b_ours_archived", len(ours))
    pub("linear_ctl_c1b_others_archived", len(others))
    return int(len(ours) != 20) + int(sorted(others) != sorted("x%d" % k for k in range(24)))
passed += control("c1b_our_team_first", c1b)


# ---------------------------------------------------------------- C2 : sous le seuil (NEGATIF) ----
def c2():
    L = FakeLinear()
    items, mp = seed_space(L, 50, 150)                                  # 200 actifs < 212
    reset(items, mp)
    st, _ = run(lambda: S.make_room(L, force=True))
    n0 = L.n
    again, _ = run(lambda: S.make_room(L))                              # moins de 5 min apres : rien ne se refait
    pub("linear_ctl_c2_archived", L.calls.count("issueArchive"))
    pub("linear_ctl_c2_active_after", len(L.active()))
    pub("linear_ctl_c2_throttled_requests", L.n - n0)
    return int(L.calls.count("issueArchive") != 0) + int(st is None or st["archived"] != 0) + int(again is not None or L.n != n0)
passed += control("c2_below_threshold_negative", c2)


# ---------------------------------------------------------------- C3 : ticket archive ----
def c3(at_limit):
    L = FakeLinear()
    if at_limit:
        items, mp = seed_space(L, 190, 60)                              # 250 actifs : A la limite
    else:
        items, mp = seed_space(L, 50, 50)
    L.add("verdict", state="completed", archived=True)
    reset(items, mp)
    before_crash = 0
    try:                                                               # bras AVANT : l'appel nu
        L.q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }', i={"issueId": "verdict", "body": "x"})
    except RuntimeError as e:
        before_crash = int(S.is_missing_issue(e))
    crashed = 0
    try:
        run(lambda: S.post_comment(L, "verdict", "Essai 2 : porte tenue."))
    except Exception:  # noqa: BLE001
        crashed = 1
    tag = "c3l" if at_limit else "c3"
    pub("linear_ctl_%s_crash_before_fix" % tag, before_crash)
    pub("linear_ctl_%s_crash_fixed" % tag, crashed)
    pub("linear_ctl_%s_comment_landed" % tag, L.comments.count("verdict"))
    pub("linear_ctl_%s_unarchived" % tag, int(not L.iss["verdict"]["archived"]))
    bad = int(before_crash != 1) + crashed + int(L.comments.count("verdict") != 1) + int(L.iss["verdict"]["archived"])
    if at_limit:
        pub("linear_ctl_c3l_archived_to_make_room", L.calls.count("issueArchive"))
        bad += int(L.calls.count("issueArchive") < 1) + int(len(L.active()) > L.limit)
    return bad
passed += control("c3_archived_ticket_commented", lambda: c3(False))
passed += control("c3l_archived_ticket_commented_at_limit", lambda: c3(True))


def c3u():
    L = FakeLinear(); L.add("clos", archived=True); reset()
    r, log = run(lambda: S.on_ticket(L, "clos", lambda: L.q('mutation issueUpdate', id="clos", i={"title": "t"}), revive=False))
    pub("linear_ctl_c3u_left_archived", int(r is S.LEFT_ARCHIVED and L.iss["clos"]["archived"]))
    pub("linear_ctl_c3u_named", int("LAISSE ARCHIVE" in log))
    return int(r is not S.LEFT_ARCHIVED) + int(not L.iss["clos"]["archived"]) + int("LAISSE ARCHIVE" not in log)
passed += control("c3u_closed_archived_update_negative", c3u)


def c3s():
    L = FakeLinear(); L.add("lu", archived=True); reset()
    run(lambda: S.swap_labels(L, "lu", add="label-lire"))
    pub("linear_ctl_c3s_label_set", int("label-lire" in L.iss["lu"]["labels"]))
    return int("label-lire" not in L.iss["lu"]["labels"])
passed += control("c3s_archived_ticket_label", c3s)


# ---------------------------------------------------------------- C4 : creation refusee ----
def c4(room):
    L = FakeLinear()
    items, mp = seed_space(L, 250 - room, room)
    reset(items, mp)
    before_crash = 0
    try:
        L.q('mutation($i:IssueCreateInput!){ issueCreate(input:$i){ issue { id identifier url } } }', i={"title": "t"})
    except RuntimeError as e:
        before_crash = int(S.is_usage_limit(e))
    L.calls.clear()
    made, raised, buf = False, "", io.StringIO()
    with redirect_stdout(buf):                                          # le journal survit au refus final
        try:
            _rec, made = S.ensure_ticket(L, S._CTX["mp"], TEAM, "harness-neuf", "Un chantier neuf",
                                         {"title": "Un chantier neuf", "description": "d"}, "Todo", "h")
        except RuntimeError as e:
            raised = str(e)
    return L, before_crash, made, raised, buf.getvalue()


def c4a():
    L, before, made, raised, log = c4(100)
    pub("linear_ctl_c4_crash_before_fix", before)
    pub("linear_ctl_c4_ticket_created", int(made))
    pub("linear_ctl_c4_create_attempts", L.calls.count("issueCreate"))
    pub("linear_ctl_c4_archived", L.calls.count("issueArchive"))
    return int(before != 1) + int(not made) + int(bool(raised)) + int(L.calls.count("issueCreate") != 2) + int(L.calls.count("issueArchive") < 1)
passed += control("c4_create_refused_then_retried", c4a)


def c4b():
    L, before, made, raised, log = c4(0)                                # 250 ouverts, rien a archiver
    pub("linear_ctl_c4b_create_attempts", L.calls.count("issueCreate"))
    pub("linear_ctl_c4b_refusal_raised", int(S.is_usage_limit(raised)))
    pub("linear_ctl_c4b_saturation_named", int("SATURE" in log or "SATURE" in raised))
    return (int(made) + int(L.calls.count("issueCreate") != 2) + int(not S.is_usage_limit(raised))
            + int("SATURE" not in log))
passed += control("c4b_create_refused_nothing_to_archive", c4b)


# ---------------------------------------------------------------- C5 : un ticket casse parmi trois ----
def c5():
    L = FakeLinear()
    ap = SB / "ap"
    ids = ["harness-un", "harness-deux", "harness-trois"]
    mp = {}
    for k, iid in enumerate(ids):
        (ap / "logs" / iid).mkdir(parents=True)
        (ap / "logs" / iid / "validator-002.txt").write_text("[%s ok] porte tenue\n" % iid)
        mp[iid] = {"issue_id": "t%d" % k, "identifier": "T%d" % k, "last_verdict_announced": "validator-001.txt"}
        if iid != "harness-deux":                                        # le ticket de « deux » n'existe plus
            L.add("t%d" % k, state="started")
    items = [{"id": i, "status": "in-progress", "feature": i} for i in ids]
    reset(items, mp)
    old_ap = S.AP
    S.AP = ap
    try:
        _, log = run(lambda: S.announce_verdicts(L, FakeBacklog(items), mp, "label-lire", False))
    finally:
        S.AP = old_ap
    fixed = len(L.comments)
    # bras AVANT : la boucle d'avant postait sans garde et tombait au premier refus
    posted_before = 0
    for k in range(3):
        try:
            L.q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }', i={"issueId": "t%d" % k, "body": "x"})
            posted_before += 1
        except RuntimeError:
            break
    pub("linear_ctl_c5_announced_fixed", fixed)
    pub("linear_ctl_c5_announced_before_fix", posted_before)
    pub("linear_ctl_c5_failures_named", len(S.FAILED))
    pub("linear_ctl_c5_failure_names_item", int(any("harness-deux" in f for f in S.FAILED)))
    return int(fixed != 2) + int(posted_before != 1) + int(len(S.FAILED) != 1) + int(not any("harness-deux" in f for f in S.FAILED))
passed += control("c5_one_broken_ticket_does_not_stop_the_pass", c5)

pub("linear_space_controls_passed", passed)
pub("linear_space_controls_total", 10)
shutil.rmtree(SB, ignore_errors=True)

# ---------------------------------------------------------------- B : Linear VIVANT ----
try:
    import importlib
    S = importlib.reload(S)                                   # chemins et etat d'origine
    import linear_identity as LI
    from lib import backlog as B
    L = S.Linear(LI.resolve())
    bl = B.load()
    mp = json.loads(S.MAP_PATH.read_text())
    S._CTX.update(bl=bl, mp=mp, todo=mp["_ids"]["labels"]["todo"], team=mp["_ids"]["team"])
    st = S._space_state()
    limit = min(S.SPACE_LIMIT, int(st.get("learned_limit") or S.SPACE_LIMIT))
    active = S.count_active(L)
    high = int(limit * S.SPACE_HIGH)
    left = len(S.archivable(L, S.kept_ids()))
    over = int(active >= high and left > 0)
    missing = [it["id"] for it in bl.items if it["status"] in ("open", "in-progress", "to-test", "blocked") and it["id"] not in mp]
    act_ids = {mp[it["id"]]["issue_id"]: it["id"] for it in bl.items
               if it["status"] in ("open", "in-progress", "to-test", "blocked") and it["id"] in mp}
    on_arch = []
    ids = sorted(act_ids)
    for i in range(0, len(ids), 50):
        d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:50, includeArchived:true){ nodes { id identifier archivedAt } } }', ids=ids[i:i + 50])
        on_arch += ["%s:%s" % (act_ids[n["id"]], n["identifier"]) for n in d["issues"]["nodes"] if n.get("archivedAt")]
    pub("linear_space_active", active)
    pub("linear_space_limit", limit)
    pub("linear_space_threshold", high)
    pub("linear_space_archivable_closed", left)
    pub("linear_space_over_threshold_with_archivable", over)
    pub("linear_space_last_census_code", st.get("code", "-"))
    pub("linear_space_last_census_archived", st.get("archived", "-"))
    pub("linear_active_items_without_ticket", len(missing))
    pub("linear_active_items_without_ticket_list", ",".join(missing) or "-")
    pub("linear_active_items_on_archived_ticket", len(on_arch))           # affiche : la synchro les ressort quand elle leur parle
    pub("linear_active_items_on_archived_ticket_list", ",".join(on_arch) or "-")
    pub("linear_space_live_measured", 1)
    defects += over + len(missing)
except Exception as e:  # noqa: BLE001
    pub("linear_space_live_measured", 0)
    pub("linear_space_live_error", str(e)[:160])
    defects += 1; unmeasured += 1

# -------------------------------------------- B2 : les passages de la veille, code EN PLACE ----
try:
    log = (S.HOME / "logs" / "linear_sync.txt").read_text(errors="replace").splitlines()
    fp = S.CODE_FP
    segs, cur = [], None                                      # un segment = un passage, ouvert par `SYNCHRO code=`
    head = []
    for l in log:
        if l.startswith("SYNCHRO code="):
            cur = {"code": l.split("=", 1)[1].strip(), "lines": []}; segs.append(cur)
        elif cur is not None:
            cur["lines"].append(l)
        else:
            head.append(l)
    mine = [s for s in segs if s["code"] == fp]
    crashed = lambda s: any("Traceback" in l or l.endswith("synchro en erreur") for l in s["lines"])
    on_space = lambda ls: any("USAGE_LIMIT_EXCEEDED" in l or "Entity not found" in l for l in ls)
    crashes = [s for s in mine if crashed(s)]
    pub("linear_sync_code", fp)
    pub("linear_sync_passes_current_code", len(mine))
    pub("linear_sync_crashes_current_code", len(crashes))
    pub("linear_sync_crashes_current_code_on_limit_or_archive", len([s for s in crashes if on_space(s["lines"])]))
    pub("linear_sync_named_failures_current_code", sum(l.startswith("ECHEC LINEAR NOMME") for s in mine for l in s["lines"]))
    pub("linear_sync_space_census_current_code", sum(l.startswith("ESPACE LINEAR :") and "/" in l for s in mine for l in s["lines"]))
    # temoin d'AVANT : les plantages du journal ecrits avant la premiere ligne `SYNCHRO code=` (le 23/09)
    pub("linear_sync_crashes_before_fix_on_limit_or_archive",
        sum(1 for k, l in enumerate(head) if l.endswith("synchro en erreur") and on_space(head[max(0, k - 25):k])))
    if not mine:
        unmeasured += 1; defects += 1                        # aucun passage du code en place : rien n'est prouve
    defects += len(crashes)
except Exception as e:  # noqa: BLE001
    pub("linear_sync_log_error", str(e)[:160])
    defects += 1; unmeasured += 1

pub("linear_space_terms_unmeasured", unmeasured)
pub("linear_space_defects", defects)
for k, v in OUT.items():
    print("%s=%s" % (k, v))
PY
