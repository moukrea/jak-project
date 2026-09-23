#!/usr/bin/env bash
# census/harness-owner-thumbs-up-closes-the-thread.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `thumbed_tickets_still_labeled`.
#
# LE DEFAUT (owner 23/09, JAK-176) : « Pourquoi les labels subsistent, j'ai mis le pouce sur le dernier message ».
# Le pouce ne retirait que « A lire » ; « A traiter » restait des qu'un retour de l'owner precedait un message
# automatique (qui n'est plus une reponse depuis le 23/09), et « En discussion » suivait.
#
# CE QU'IL MESURE — `thumbed_tickets_still_labeled` = somme de :
#   V  VIVANT : chaque ticket NON archive portant « A lire », « A traiter » ou « En discussion » dont le DERNIER message
#      du harnais (commentaires pagines EN ENTIER) porte un pouce/✅ de l'OWNER (auteur de la reaction = son id), sans
#      commentaire de l'owner pose apres ce pouce. Classe ICI, sans `owner_sla.thread_closed` (instrument independant).
#   INCONNU = DEFAUT : Linear injoignable -> -1 ; un controle qui ne tient pas compte 1.
# CONTROLES (monde SIMULE : faux Linear en memoire, `pull_owner` / `pull_labeled_unmapped` / `owner_sla.collect` REELS) :
#   C+  pouce sur un message AUTOMATIQUE poste apres un retour de l'owner : les 3 etiquettes tombent, le retour compte
#       repondu (`reaction`) — backlog ET hors backlog. Avec le code d'AVANT (commit epingle OLD_COMMIT), le meme
#       monde garde ses etiquettes : la mesure V le COMPTE et le NOMME.
#   C-  pouce sur un message ANCIEN (un plus recent existe) : rien ne change, le retour reste ouvert.
#   C3  commentaire de l'owner APRES le pouce : « A traiter » est pose, ce retour-la reste ouvert.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "thumbed_tickets_still_labeled=-1"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import io, subprocess, sys, types
from contextlib import redirect_stdout
sys.path.insert(0, '.autoport')

OLD_COMMIT = "ccd1d662fc"   # dernier commit ou le pouce ne retirait que « A lire »
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


def classify(comments, owner_id):
    """'closed' | 'reopened' | '' — mesure INDEPENDANTE (pas de owner_sla) du fil tel que l'owner le voit."""
    def app(c):
        return bool((c.get("botActor") or {}).get("id")) or bool((c.get("user") or {}).get("app")) \
            or (c.get("body") or "").startswith("🤖")
    cs = sorted(comments, key=lambda c: c["createdAt"])
    ours = [c for c in cs if app(c)]
    if not ours:
        return ""
    thumbs = [r["createdAt"] for r in (ours[-1].get("reactions") or [])
              if any(k in str(r.get("emoji")) for k in OK) and (r.get("user") or {}).get("id") == owner_id]
    if not thumbs:
        return ""
    t = max(thumbs)
    later = [c for c in cs if not app(c) and (c.get("user") or {}).get("id") == owner_id and c["createdAt"] > t]
    return "reopened" if later else "closed"


def measure(tickets, owner_id, watched):
    """tickets: [{identifier, archivedAt, labels:set, comments}] -> (noms encore etiquetes, reouverts, archives)."""
    still, reopened, archived = [], [], []
    for t in tickets:
        kept = t["labels"] & watched
        if not kept:
            continue
        k = classify(t["comments"], owner_id)
        if k == "closed":
            (archived if t.get("archivedAt") else still).append(t["identifier"])
        elif k == "reopened":
            reopened.append(t["identifier"])
    return still, reopened, archived


# ============================================================================== VIVANT (Linear) ==
real = -1
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
    tickets = {}
    for k, lab in labs.items():
        after, n_lab = None, 0
        while True:
            q = L.q('query($id:String!,$a:String){ issueLabel(id:$id){ issues(first:100, after:$a, includeArchived:true){ '
                    'pageInfo { hasNextPage endCursor } nodes { id identifier archivedAt labels { nodes { id } } } } } }',
                    id=lab, a=after)["issueLabel"]["issues"]
            for n in q["nodes"]:
                n_lab += 1
                tickets.setdefault(n["id"], {"identifier": n["identifier"], "archivedAt": n.get("archivedAt"),
                                             "labels": {x["id"] for x in n["labels"]["nodes"]}})
            if not q["pageInfo"]["hasNextPage"]:
                break
            after = q["pageInfo"]["endCursor"]
        pub("thumb_labeled_%s" % k, n_lab)
    for iid, t in tickets.items():
        t["comments"] = OSLA._rest(L, iid, {"hasNextPage": True, "endCursor": None})
    still, reopened, archived = measure(list(tickets.values()), owner_id, set(labs.values()))
    pub("thumb_labeled_tickets", len(tickets))
    pub("thumb_labeled_comments_read", sum(len(t["comments"]) for t in tickets.values()))
    pub("thumbed_still_labeled_list", ",".join(sorted(still)) or "-")
    pub("thumbed_reopened_by_owner_comment", len(reopened))
    pub("thumbed_reopened_list", ",".join(sorted(reopened)) or "-")
    pub("thumbed_archived_still_labeled", len(archived))
    pub("thumbed_archived_list", ",".join(sorted(archived)) or "-")
    # DENOMINATEUR : tous les tickets suivis (carte), etiquetes ou non. Un classificateur qui ne voit AUCUN fil clos
    # par un pouce sur 200+ tickets est aveugle (champ de reaction absent, auteur mal lu) : le terme compte 1.
    ids = [v["issue_id"] for k, v in mp.items() if not k.startswith("_") and isinstance(v, dict) and v.get("issue_id")]
    closed_all, n_seen, n_react = [], 0, 0
    for i in range(0, len(ids), 40):
        dd = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:40, includeArchived:true){ nodes { id identifier '
                 'archivedAt labels { nodes { id } } comments(first:100){ pageInfo { hasNextPage endCursor } nodes { '
                 + OSLA.COMMENT_FIELDS + ' } } } } }', ids=ids[i:i + 40])
        for n in dd["issues"]["nodes"]:
            n_seen += 1
            cs = n["comments"]["nodes"] + OSLA._rest(L, n["id"], n["comments"]["pageInfo"])
            n_react += sum(len(x.get("reactions") or []) for x in cs)
            if classify(cs, owner_id) == "closed":
                closed_all.append(n["identifier"])
    pub("thumb_mapped_tickets", len(ids))
    pub("thumb_mapped_tickets_read", n_seen)
    pub("thumb_mapped_reactions_read", n_react)
    pub("thumb_closed_threads_mapped", len(closed_all))
    if n_seen != len(ids) or not closed_all:
        dead.append("vivant_aveugle")
    real = len(still)
except Exception as e:  # noqa: BLE001
    pub("thumb_live_error", str(e)[:120])
pub("thumbed_tickets_live", real)


# ============================================================================= MONDE SIMULE ====
OWNER, APP = "owner-1", "app-1"
READ, TODO, TALK = "lab-read", "lab-todo", "lab-talk"


def c(cid, at, who, body="", reacts=()):
    return {"id": cid, "createdAt": at, "body": body, "parentId": None,
            "user": {"id": OWNER if who == "o" else APP, "app": who != "o"}, "botActor": None,
            "reactions": [{"emoji": "+1", "createdAt": r, "user": {"id": OWNER, "app": False}} for r in reacts]}


class FakeL:
    mode = "app"
    def __init__(self, issues):
        self.issues = issues   # id -> {id, identifier, labels:set, comments, state}
        self.writes = 0
    def _node(self, i):
        return {"id": i["id"], "identifier": i["identifier"], "archivedAt": None, "state": {"name": i["state"]},
                "labels": {"nodes": [{"id": x} for x in sorted(i["labels"])]},
                "comments": {"nodes": sorted(i["comments"], key=lambda x: x["createdAt"], reverse=True)}}
    def q(self, query, **v):
        if "issueUpdate" in query:
            self.issues[v["id"]]["labels"] = set(v["i"]["labelIds"]); self.writes += 1
            return {"issueUpdate": {"success": True}}
        if "issueLabel(" in query:
            return {"issueLabel": {"issues": {"nodes": [self._node(i) for i in self.issues.values() if v["id"] in i["labels"]]}}}
        if "issues(filter" in query:
            return {"issues": {"nodes": [self._node(self.issues[x]) for x in v["ids"] if x in self.issues]}}
        if "issue(id" in query:
            return {"issue": self._node(self.issues[v["id"]])}
        raise RuntimeError("requete non simulee : %s" % query[:60])


class FakeBL:
    def __init__(self): self.fb = []
    def get(self, iid): return {"id": iid, "status": "validated", "owner_feedback": []}
    def add_owner_feedback(self, iid, date, text, via=None): self.fb.append((iid, text))


def world(kind):
    """Trois fils : 'pos' (JAK-176), 'neg' (pouce sur un ANCIEN), 'reopen' (retour apres le pouce)."""
    if kind == "pos":
        cs = [c("h1", "2026-09-22T20:00:00Z", "a", "Voici la jauge."),
              c("o1", "2026-09-22T21:23:38Z", "o", "Pour l'eco bleue c'est parfait"),
              c("h2", "2026-09-22T21:25:17Z", "a", "→ **Terminé**.", reacts=["2026-09-23T01:37:57Z"])]
    elif kind == "neg":
        cs = [c("h1", "2026-09-22T20:00:00Z", "a", "Voici la jauge.", reacts=["2026-09-22T22:00:00Z"]),
              c("o1", "2026-09-22T21:23:38Z", "o", "Pour l'eco bleue c'est parfait"),
              c("h2", "2026-09-22T21:25:17Z", "a", "→ **Terminé**.")]
    else:
        cs = [c("h1", "2026-09-22T20:00:00Z", "a", "Voici la jauge."),
              c("o1", "2026-09-22T21:23:38Z", "o", "Pour l'eco bleue c'est parfait"),
              c("h2", "2026-09-22T21:25:17Z", "a", "→ **Terminé**.", reacts=["2026-09-23T01:00:00Z"]),
              c("o2", "2026-09-23T01:39:41Z", "o", "Et la rouge ?")]
    return cs


def run(mod, kind, mapped):
    """Rejoue UN passage de synchro (`pull_owner` si le ticket est dans la carte, sinon `pull_labeled_unmapped`)."""
    iss = {"id": "iss-1", "identifier": "JAK-900", "state": "Done",
           "labels": {READ, TODO, TALK}, "comments": world(kind)}
    L = FakeL({"iss-1": iss})
    mp = {"_owner": {"user_id": OWNER}}
    if mapped:
        # le retour o1 est deja recopie au passage precedent ; o2 (reopen) est NOUVEAU
        mp["hud-x"] = {"issue_id": "iss-1", "identifier": "JAK-900", "last_state": "Done", "pulled_at": "2026-09-22T21:30:00Z"}
    mod._TALK.update({"id": TALK, "read": READ, "todo": TODO})
    saved = {k: getattr(mod, k) for k in ("save_owner_images", "refresh_prompt")}
    saved_load = mod.B.load
    bl = FakeBL()
    mod.save_owner_images = lambda L_, iid, body, when: body
    mod.refresh_prompt = lambda it: None
    mod.B.load = lambda: bl
    try:
        with redirect_stdout(io.StringIO()):
            if mapped:
                mod.pull_owner(L, bl, mp, {}, False, READ, TODO)
            else:
                mod.pull_labeled_unmapped(L, mp, READ, TODO, TALK, False)
    finally:
        for k, v in saved.items():
            setattr(mod, k, v)
        mod.B.load = saved_load
    t = {"identifier": "JAK-900", "archivedAt": None, "labels": set(iss["labels"]), "comments": iss["comments"]}
    still, reopened, _ = measure([t], OWNER, {READ, TODO, TALK})
    return iss["labels"], still, reopened


def sla(osla, kind):
    cs = world(kind)
    rows = [{"item": "hud-x", "ticket": "iss-1", "text": x["body"], "date": x["createdAt"][:10], "via": {"comment": x["id"]}}
            for x in cs if x["user"]["id"] == OWNER]
    is_owner = lambda x: not (x.get("user") or {}).get("app") and (x.get("user") or {}).get("id") == OWNER
    is_h = lambda x: bool((x.get("user") or {}).get("app"))
    return {r["text"]: r for r in osla.collect(rows, lambda t: cs, is_owner, is_h, now=1.9e9)}


try:
    import linear_sync as S
    from lib import owner_sla as OSLA
    # ancien code, epingle (jamais HEAD : il deviendrait le nouveau des le commit)
    src = subprocess.run(["git", "show", "%s:.autoport/linear_sync.py" % OLD_COMMIT], capture_output=True, text=True, check=True).stdout
    OLD = types.ModuleType("linear_sync_old"); OLD.__file__ = S.__file__
    exec(compile(src, "linear_sync@%s" % OLD_COMMIT, "exec"), OLD.__dict__)
    pub("thumb_old_commit", OLD_COMMIT)
    for mapped, tag in ((True, "backlog"), (False, "hors_backlog")):
        labs, still, _ = run(S, "pos", mapped)
        check("pos_%s_all_labels_dropped" % tag, labs == set() and still == [])
        labs_o, still_o, _ = run(OLD, "pos", mapped)
        pub("thumb_ctl_pos_%s_old_code_kept" % tag, len(labs_o))
        check("pos_%s_old_code_red_and_named" % tag, bool(labs_o) and still_o == ["JAK-900"])
        labs, still, _ = run(S, "neg", mapped)
        check("neg_%s_old_message_nothing_changes" % tag, labs == {READ, TODO, TALK})
        labs, still, reop = run(S, "reopen", mapped)
        check("reopen_%s_todo_kept" % tag, TODO in labs and reop == ["JAK-900"] and still == [])
    r = sla(OSLA, "pos")["Pour l'eco bleue c'est parfait"]
    check("pos_sla_answered_by_reaction", r["answered"] == 1 and r["answer_how"] == "reaction" and r["answer_auto"] == ""
          and OSLA.cost_summary([r], 7200)["auto_answered"] == 0)
    r = sla(OSLA, "neg")["Pour l'eco bleue c'est parfait"]
    check("neg_sla_still_open", r["open"] == 1 and r["answered"] == 0)
    rr = sla(OSLA, "reopen")
    check("reopen_sla_before_answered_after_open",
          rr["Pour l'eco bleue c'est parfait"]["answer_how"] == "reaction" and rr["Et la rouge ?"]["open"] == 1)
except Exception as e:  # noqa: BLE001
    pub("thumb_ctl_error", str(e)[:160])
    dead.append("controles_non_executes")

pub("thumb_ctl_failed", len(dead))
pub("thumb_ctl_failed_list", ",".join(dead) or "-")
pub("thumbed_tickets_still_labeled", real + len(dead) if real >= 0 else -1)
for k in ORDRE:
    print("%s=%s" % (k, OUT[k]))
PY
