#!/usr/bin/env bash
# census/harness-owner-thumbs-up-closes-the-thread.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `thumbed_tickets_still_labeled`.
#
# LE DEFAUT (owner 23/09, JAK-176) : « Pourquoi les labels subsistent, j'ai mis le pouce sur le dernier message ».
# RECHUTE (owner 25/09, JAK-50/277/77, Done) : pouce sur « → Terminé » (racine), reponse de fil du superviseur une
# minute avant le pouce : la regle ne regardait que le DERNIER message du harnais, les etiquettes sont restees.
#
# LA REGLE MESUREE (contrat, ajout du 25/09) — une discussion est CLOSE, et ne doit garder ni « A lire » ni
# « A traiter » ni « En discussion », quand :
#   P  un pouce/✅ de l'OWNER est pose sur N'IMPORTE QUEL message du harnais poste apres son dernier commentaire
#      (racine ou fil), sans commentaire de l'owner ni nouveau message RACINE du harnais apres ce pouce ;
#   D  le ticket est Done/Canceled et l'owner n'a rien ecrit apres ce passage (`completedAt` / `canceledAt`).
# `thumbed_tickets_still_labeled` = V + D_vivant + controles morts :
#   V / D_vivant : tickets NON archives portant une des 3 etiquettes et clos par P / par D (commentaires pagines EN
#      ENTIER), classes ICI sans `owner_sla` (instrument independant). Linear injoignable -> -1.
# CONTROLES (monde SIMULE : faux Linear en memoire, `pull_owner` / `pull_labeled_unmapped` / `owner_sla.collect` REELS),
# backlog ET hors backlog :
#   pos      pouce sur un message automatique apres un retour (JAK-176) : tout tombe ; code d'avant l'essai 1 rouge.
#   rechute  pouce sur la racine « → Terminé », reponse de fil plus recente sans pouce, ticket EN COURS (P seul) :
#            tout tombe ; le code de l'essai 1 (commit epingle) garde ses etiquettes, la mesure le NOMME.
#   neg      pouce sur un message ANTERIEUR au dernier retour de l'owner : rien ne change.
#   reopen   commentaire de l'owner APRES le pouce : « A traiter » reste.
#   root     nouveau message racine du harnais APRES le pouce (annonce non lue) : « A lire » reste.
#   done     ticket Done sans retour depuis : tout tombe ; done_after : retour de l'owner apres le Done : rien ne tombe.
#   replay   JAK-50, JAK-277, JAK-77 relus sur Linear, coupes avant la plainte du 25/09 05:31, etiquettes remises :
#            tout tombe (etat Done, puis etat force « en cours » pour isoler P) ; le code de l'essai 1 les garde.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "thumbed_tickets_still_labeled=-1"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import io, subprocess, sys, types
from contextlib import redirect_stdout
sys.path.insert(0, '.autoport')
from lib.census import fake_backlog as FB

OUT, ORDRE = {}, []
def pub(k, v):
    if k not in OUT:
        ORDRE.append(k)
    OUT[k] = str(v).replace(" ", "_")
dead = []
def check(name, ok):
    pub("thumb_ctl_%s" % name, "ok" if ok else "ROUGE")
    if not ok:
        dead.append(name)

OK = ("+1", "thumbsup", "👍", "white_check_mark", "heavy_check_mark", "ballot_box_with_check", "✅", "☑", "✔")


def app(c):
    return bool((c.get("botActor") or {}).get("id")) or bool((c.get("user") or {}).get("app")) \
        or (c.get("body") or "").startswith("🤖")


def classify(comments, owner_id, state_type=None, completed_at=None, canceled_at=None):
    """'closed' (P) | 'done' (D) | 'reopened' | '' — mesure INDEPENDANTE (pas de owner_sla) du fil tel que l'owner le voit.
    Les horodatages ISO de Linear ont tous le meme format : ils se comparent comme des chaines."""
    cs = sorted(comments, key=lambda c: c["createdAt"])
    mine = [c["createdAt"] for c in cs if not app(c) and (c.get("user") or {}).get("id") == owner_id]
    last_owner = max(mine, default="")
    thumbs, any_thumb = [], False
    for h in cs:
        if not app(h):
            continue
        for r in h.get("reactions") or []:
            if any(k in str(r.get("emoji")) for k in OK) and (r.get("user") or {}).get("id") == owner_id:
                any_thumb = True
                before = max((m for m in mine if m < r["createdAt"]), default="")
                if h["createdAt"] > before:
                    thumbs.append(r["createdAt"])
    if thumbs:
        t = max(thumbs)
        if last_owner <= t and not any(app(c) and not c.get("parentId") and c["createdAt"] > t for c in cs):
            return "closed"
    ref = {"completed": completed_at, "canceled": canceled_at}.get(state_type or "")
    if ref and last_owner <= ref:
        return "done"
    return "reopened" if any_thumb and thumbs and last_owner > max(thumbs) else ""


def measure(tickets, owner_id, watched):
    """tickets: [{identifier, archivedAt, labels:set, comments, state_type, completedAt, canceledAt}]
    -> (clos par P encore etiquetes, clos par D encore etiquetes, rouverts, archives)."""
    still, done, reopened, archived = [], [], [], []
    for t in tickets:
        if not (t["labels"] & watched):
            continue
        k = classify(t["comments"], owner_id, t.get("state_type"), t.get("completedAt"), t.get("canceledAt"))
        if k in ("closed", "done"):
            (archived if t.get("archivedAt") else still if k == "closed" else done).append(t["identifier"])
        elif k == "reopened":
            reopened.append(t["identifier"])
    return still, done, reopened, archived


# ============================================================================== VIVANT (Linear) ==
real = -1
REPLAY = {}   # identifiant -> ticket relu (controle replay)
try:
    import linear_sync as S, linear_identity as LI
    from lib import owner_sla as OSLA
    L = S.Linear(LI.resolve())
    mp = S.load_map()
    owner_id = S.owner_user_id(L, mp)
    if not owner_id:
        raise RuntimeError("owner inconnu")
    team = S.ensure_team(L)
    names = {"read": S.LABEL_READ, "todo": S.LABEL_TODO, "talk": S.LABEL_TALK}
    labs = {}
    d = L.q('query($t:String!){ team(id:$t){ labels { nodes { id name } } } }', t=team)
    for l in d["team"]["labels"]["nodes"]:
        for k, n in names.items():
            if l["name"] == n:
                labs[k] = l["id"]
    if len(labs) != 3:
        raise RuntimeError("etiquettes introuvables : %s" % sorted(labs))
    ISS = 'id identifier archivedAt completedAt canceledAt state { type } labels { nodes { id } }'

    def ticket(n, cs):
        return {"identifier": n["identifier"], "archivedAt": n.get("archivedAt"), "labels": {x["id"] for x in n["labels"]["nodes"]},
                "state_type": n["state"]["type"], "completedAt": n.get("completedAt"), "canceledAt": n.get("canceledAt"),
                "comments": cs}
    tickets = {}
    for k, lab in labs.items():
        after, n_lab = None, 0
        while True:
            q = L.q('query($id:String!,$a:String){ issueLabel(id:$id){ issues(first:100, after:$a, includeArchived:true){ '
                    'pageInfo { hasNextPage endCursor } nodes { ' + ISS + ' } } } }', id=lab, a=after)["issueLabel"]["issues"]
            for n in q["nodes"]:
                n_lab += 1
                tickets.setdefault(n["id"], ticket(n, None))
            if not q["pageInfo"]["hasNextPage"]:
                break
            after = q["pageInfo"]["endCursor"]
        pub("thumb_labeled_%s" % k, n_lab)
    for iid, t in tickets.items():
        t["comments"] = OSLA._rest(L, iid, {"hasNextPage": True, "endCursor": None})
    still, done, reopened, archived = measure(list(tickets.values()), owner_id, set(labs.values()))
    pub("thumb_labeled_tickets", len(tickets))
    pub("thumb_labeled_comments_read", sum(len(t["comments"]) for t in tickets.values()))
    pub("thumbed_still_labeled_live", len(still))
    pub("thumbed_still_labeled_list", ",".join(sorted(still)) or "-")
    pub("done_still_labeled_live", len(done))
    pub("done_still_labeled_list", ",".join(sorted(done)) or "-")
    pub("thumbed_reopened_by_owner_comment", len(reopened))
    pub("thumbed_reopened_list", ",".join(sorted(reopened)) or "-")
    pub("thumbed_archived_still_labeled", len(archived))
    pub("thumbed_archived_list", ",".join(sorted(archived)) or "-")
    # DENOMINATEUR : tous les tickets suivis (carte), etiquetes ou non. Un classificateur qui ne voit AUCUN fil clos
    # par un pouce sur 200+ tickets est aveugle (champ de reaction absent, auteur mal lu) : le terme compte 1.
    ids = [v["issue_id"] for k, v in mp.items() if not k.startswith("_") and isinstance(v, dict) and v.get("issue_id")]
    closed_all, done_all, n_seen, n_react = [], [], 0, 0
    for i in range(0, len(ids), 40):
        dd = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:40, includeArchived:true){ nodes { ' + ISS +
                 ' comments(first:100){ pageInfo { hasNextPage endCursor } nodes { ' + OSLA.COMMENT_FIELDS + ' } } } } }',
                 ids=ids[i:i + 40])
        for n in dd["issues"]["nodes"]:
            n_seen += 1
            cs = n["comments"]["nodes"] + OSLA._rest(L, n["id"], n["comments"]["pageInfo"])
            n_react += sum(len(x.get("reactions") or []) for x in cs)
            k = classify(cs, owner_id, n["state"]["type"], n.get("completedAt"), n.get("canceledAt"))
            (closed_all if k == "closed" else done_all if k == "done" else []).append(n["identifier"])
            if n["identifier"] in ("JAK-50", "JAK-277", "JAK-77"):
                REPLAY[n["identifier"]] = ticket(n, cs)
    pub("thumb_mapped_tickets", len(ids))
    pub("thumb_mapped_tickets_read", n_seen)
    pub("thumb_mapped_reactions_read", n_react)
    pub("thumb_closed_threads_mapped", len(closed_all))
    pub("done_closed_threads_mapped", len(done_all))
    if n_seen != len(ids) or not closed_all or not done_all:
        dead.append("vivant_aveugle")
    real = len(still) + len(done)
    REPLAY["_owner"] = owner_id
except Exception as e:  # noqa: BLE001
    pub("thumb_live_error", str(e)[:120])
pub("thumbed_tickets_live", real)


# ============================================================================= MONDE SIMULE ====
OWNER, APP = "owner-1", "app-1"
READ, TODO, TALK = "lab-read", "lab-todo", "lab-talk"


def c(cid, at, who, body="", reacts=(), parent=None):
    return {"id": cid, "createdAt": at, "body": body, "parentId": parent,
            "user": {"id": OWNER if who == "o" else APP, "app": who != "o"}, "botActor": None,
            "reactions": [{"emoji": "+1", "createdAt": r, "user": {"id": OWNER, "app": False}} for r in reacts]}


class FakeL:
    mode = "app"
    def __init__(self, issues):
        self.issues = issues   # id -> {id, identifier, labels:set, comments, state, type, completedAt}
        self.writes = 0
    def _node(self, i):
        return {"id": i["id"], "identifier": i["identifier"], "archivedAt": None,
                "state": {"name": i["state"], "type": i["type"]},
                "completedAt": i.get("completedAt"), "canceledAt": i.get("canceledAt"),
                "labels": {"nodes": [{"id": x} for x in sorted(i["labels"])]},
                "comments": {"pageInfo": {"hasNextPage": False, "endCursor": None},
                             "nodes": sorted(i["comments"], key=lambda x: x["createdAt"], reverse=True)}}
    def q(self, query, **v):
        if "issueUpdate" in query:
            self.issues[v["id"]]["labels"] = set(v["i"]["labelIds"]); self.writes += 1
            return {"issueUpdate": {"success": True}}
        if "issueLabel(" in query:
            return {"issueLabel": {"issues": {"pageInfo": {"hasNextPage": False, "endCursor": None},
                                              "nodes": [self._node(i) for i in self.issues.values() if v["id"] in i["labels"]]}}}
        if "issues(filter" in query:
            return {"issues": {"nodes": [self._node(self.issues[x]) for x in v["ids"] if x in self.issues]}}
        if "issue(id" in query:
            return {"issue": self._node(self.issues[v["id"]])}
        raise RuntimeError("requete non simulee : %s" % query[:60])


DONE_AT = "2026-09-22T21:25:17Z"


def world(kind):
    """-> (commentaires, etat, type, completedAt)."""
    h1 = c("h1", "2026-09-22T20:00:00Z", "a", "Voici la jauge.")
    o1 = c("o1", "2026-09-22T21:23:38Z", "o", "Pour l'eco bleue c'est parfait")
    if kind == "pos":
        return [h1, o1, c("h2", DONE_AT, "a", "→ **Terminé**.", reacts=["2026-09-23T01:37:57Z"])], "Done", "completed", DONE_AT
    if kind == "rechute":   # JAK-50 : pouce sur la racine, reponse de fil plus recente sans pouce ; EN COURS : P seul
        return [h1, o1, c("h2", "2026-09-22T21:25:17Z", "a", "→ **En cours**.", reacts=["2026-09-22T21:53:30Z"]),
                c("h3", "2026-09-22T21:26:00Z", "a", "Validé, c'est posé.", parent="o1")], "In Progress", "started", None
    if kind == "neg":       # pouce sur un message ANTERIEUR au dernier retour de l'owner
        return [c("h1", "2026-09-22T20:00:00Z", "a", "Voici la jauge.", reacts=["2026-09-22T22:00:00Z"]), o1,
                c("h2", "2026-09-22T21:25:17Z", "a", "→ **En cours**.")], "In Progress", "started", None
    if kind == "reopen":
        return [h1, o1, c("h2", DONE_AT, "a", "→ **Terminé**.", reacts=["2026-09-23T01:00:00Z"]),
                c("o2", "2026-09-23T01:39:41Z", "o", "Et la rouge ?")], "Done", "completed", DONE_AT
    if kind == "root":      # annonce RACINE du harnais apres le pouce : non lue
        return [h1, o1, c("h2", "2026-09-22T21:25:17Z", "a", "Réponse.", reacts=["2026-09-22T22:00:00Z"]),
                c("h3", "2026-09-22T23:00:00Z", "a", "→ **À tester par toi**.")], "In Review", "started", None
    if kind == "done":      # Done, pas de pouce, retour de l'owner AVANT le passage
        return [h1, o1, c("h2", DONE_AT, "a", "→ **Terminé**.")], "Done", "completed", DONE_AT
    if kind == "done_after":  # retour de l'owner APRES le passage en Done
        return [h1, c("h2", DONE_AT, "a", "→ **Terminé**."), c("o2", "2026-09-22T22:00:00Z", "o", "Ils sont en done ?")], \
            "Done", "completed", DONE_AT
    raise KeyError(kind)


def run(mod, kind, mapped, spec=None, owner=OWNER):
    """Rejoue UN passage de synchro (`pull_owner` si le ticket est dans la carte, sinon `pull_labeled_unmapped`)."""
    cs, st, ty, done_at = spec or world(kind)
    iss = {"id": "iss-1", "identifier": "JAK-900", "state": st, "type": ty, "completedAt": done_at,
           "labels": {READ, TODO, TALK}, "comments": cs}
    L = FakeL({"iss-1": iss})
    mp = {"_owner": {"user_id": owner}}
    if mapped:
        # les retours sont deja recopies au passage precedent ; ceux poses apres `pulled_at` sont NOUVEAUX
        pa = "2026-09-22T21:30:00Z" if not spec else max(x["createdAt"] for x in cs)
        mp["hud-x"] = {"issue_id": "iss-1", "identifier": "JAK-900", "last_state": st, "pulled_at": pa}
    mod._TALK.update({"id": TALK, "read": READ, "todo": TODO})
    saved = {k: getattr(mod, k) for k in ("save_owner_images", "refresh_prompt")}
    saved_B = mod.B
    sb = FB.Sandbox([{"id": "hud-x", "status": "validated", "owner_feedback": []}])
    FB.install(mod, sb)
    bl = sb.load()
    mod.save_owner_images = lambda L_, iid, body, when: body
    mod.refresh_prompt = lambda it: None
    try:
        with redirect_stdout(io.StringIO()):
            if mapped:
                mod.pull_owner(L, bl, mp, {}, False, READ, TODO)
            else:
                mod.pull_labeled_unmapped(L, mp, READ, TODO, TALK, False)
    finally:
        for k, v in saved.items():
            setattr(mod, k, v)
        mod.B = saved_B
        sb.close()
    t = {"identifier": "JAK-900", "archivedAt": None, "labels": set(iss["labels"]), "comments": iss["comments"],
         "state_type": ty, "completedAt": done_at}
    still, done, reopened, _ = measure([t], owner, {READ, TODO, TALK})
    return iss["labels"], still + done, reopened


def sla(osla, kind):
    cs = world(kind)[0]
    rows = [{"item": "hud-x", "ticket": "iss-1", "text": x["body"], "date": x["createdAt"][:10], "via": {"comment": x["id"]}}
            for x in cs if x["user"]["id"] == OWNER]
    is_owner = lambda x: not (x.get("user") or {}).get("app") and (x.get("user") or {}).get("id") == OWNER
    is_h = lambda x: bool((x.get("user") or {}).get("app"))
    return {r["text"]: r for r in osla.collect(rows, lambda t: cs, is_owner, is_h, now=1.9e9)}


def old_code(commit):
    """linear_sync ET owner_sla tels qu'au commit epingle (jamais HEAD : il deviendrait le nouveau des le commit)."""
    def load(path, name):
        src = subprocess.run(["git", "show", "%s:.autoport/%s" % (commit, path)], capture_output=True, text=True, check=True).stdout
        m = types.ModuleType(name); m.__file__ = S.__file__
        exec(compile(src, "%s@%s" % (path, commit), "exec"), m.__dict__)
        return m
    mod = load("linear_sync.py", "linear_sync_%s" % commit)
    mod.OSLA = load("lib/owner_sla.py", "owner_sla_%s" % commit)
    return mod


OLD_COMMIT = "ccd1d662fc"   # avant l'essai 1 : le pouce ne retirait que « A lire »
TRY1_COMMIT = "4b43abf704"  # essai 1 livre : pouce sur le DERNIER message du harnais seulement
CUT = "2026-09-25T05:00:00"  # plainte de l'owner a 05:31 : le fil tel qu'il etait quand les etiquettes restaient
try:
    import linear_sync as S
    from lib import owner_sla as OSLA
    OLD, TRY1 = old_code(OLD_COMMIT), old_code(TRY1_COMMIT)
    pub("thumb_old_commit", OLD_COMMIT)
    pub("thumb_try1_commit", TRY1_COMMIT)
    for mapped, tag in ((True, "backlog"), (False, "hors_backlog")):
        labs, still, _ = run(S, "pos", mapped)
        check("pos_%s_all_labels_dropped" % tag, labs == set() and still == [])
        labs_o, still_o, _ = run(OLD, "pos", mapped)
        pub("thumb_ctl_pos_%s_old_code_kept" % tag, len(labs_o))
        check("pos_%s_old_code_red_and_named" % tag, bool(labs_o) and still_o == ["JAK-900"])
        labs, still, _ = run(S, "rechute", mapped)
        check("rechute_%s_all_labels_dropped" % tag, labs == set() and still == [])
        labs_o, still_o, _ = run(TRY1, "rechute", mapped)
        pub("thumb_ctl_rechute_%s_try1_code_kept" % tag, len(labs_o))
        check("rechute_%s_try1_code_red_and_named" % tag, bool(labs_o) and still_o == ["JAK-900"])
        labs, still, _ = run(S, "neg", mapped)
        check("neg_%s_older_than_owner_nothing_changes" % tag, labs == {READ, TODO, TALK} and still == [])
        labs, still, reop = run(S, "reopen", mapped)
        check("reopen_%s_todo_kept" % tag, TODO in labs and reop == ["JAK-900"] and still == [])
        labs, still, _ = run(S, "root", mapped)
        check("root_%s_unread_announce_kept" % tag, READ in labs and still == [])
        labs, still, _ = run(S, "done", mapped)
        check("done_%s_all_labels_dropped" % tag, labs == set() and still == [])
        labs_o, still_o, _ = run(TRY1, "done", mapped)
        check("done_%s_try1_code_red_and_named" % tag, bool(labs_o) and still_o == ["JAK-900"])
        labs, still, _ = run(S, "done_after", mapped)
        check("done_after_%s_owner_wrote_after_kept" % tag, bool(labs) and still == [])
        # REJEU des trois tickets du 25/09, coupes avant la plainte de 05:31
        for ident in ("JAK-50", "JAK-277", "JAK-77"):
            r = REPLAY.get(ident)
            if not r:
                check("replay_%s_%s_read" % (ident, tag), False)
                continue
            cs = [x for x in r["comments"] if x["createdAt"] < CUT]
            cs = [dict(x, reactions=[y for y in (x.get("reactions") or []) if y["createdAt"] < CUT]) for x in cs]
            own = REPLAY["_owner"]
            spec = (cs, "Done", r["state_type"], r["completedAt"])
            labs, still, _ = run(S, None, mapped, spec, own)
            labs_o, still_o, _ = run(TRY1, None, mapped, spec, own)
            check("replay_%s_%s_done_dropped" % (ident.replace("-", ""), tag), labs == set() and still == []
                  and bool(labs_o) and still_o == ["JAK-900"])
            labs, still, _ = run(S, None, mapped, (cs, "In Progress", "started", None), own)
            labs_o, still_o, _ = run(TRY1, None, mapped, (cs, "In Progress", "started", None), own)
            check("replay_%s_%s_thumb_alone_dropped" % (ident.replace("-", ""), tag), labs == set() and still == []
                  and bool(labs_o) and still_o == ["JAK-900"])
    r = sla(OSLA, "pos")["Pour l'eco bleue c'est parfait"]
    check("pos_sla_answered_by_reaction", r["answered"] == 1 and r["answer_how"] == "reaction" and r["answer_auto"] == ""
          and OSLA.cost_summary([r], 7200)["auto_answered"] == 0)
    r = sla(OSLA, "rechute")["Pour l'eco bleue c'est parfait"]
    check("rechute_sla_answered", r["answered"] == 1 and r["open"] == 0)
    r = sla(OSLA, "neg")["Pour l'eco bleue c'est parfait"]
    check("neg_sla_still_open", r["open"] == 1 and r["answered"] == 0)
    rr = sla(OSLA, "reopen")
    check("reopen_sla_before_answered_after_open",
          rr["Pour l'eco bleue c'est parfait"]["answer_how"] == "reaction" and rr["Et la rouge ?"]["open"] == 1)
except Exception as e:  # noqa: BLE001
    import traceback
    pub("thumb_ctl_error", (str(e) + "@" + traceback.format_exc().strip().splitlines()[-2].strip())[:200])
    dead.append("controles_non_executes")

pub("thumb_ctl_run", len([k for k in OUT if k.startswith("thumb_ctl_") and OUT[k] in ("ok", "ROUGE")]))
pub("thumb_ctl_failed", len(dead))
pub("thumb_ctl_failed_list", ",".join(dead) or "-")
pub("thumbed_tickets_still_labeled", real + len(dead) if real >= 0 else -1)
for k in ORDRE:
    print("%s=%s" % (k, OUT[k]))
PY
