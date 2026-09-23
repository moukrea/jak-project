#!/usr/bin/env bash
# census/harness-workers-reply-in-the-owner-thread.sh — LE VERDICT DE L'ITEM.
#
# Lance par `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`) apres la course ;
# sa sortie cle=valeur rejoint proof.txt par la moisson. Il n'ecrit rien sur Linear ni dans le backlog.
#
#   worker_replies_off_thread = messages REDIGES du harnais postes HORS FIL (sans `parentId`) alors
#       qu'un retour de l'owner attendait sur le ticket, sur 7 jours, depuis que l'outil adresse seul
#       (`owner_sla.THREAD_DEFAULT_SINCE`), sur le VRAI Linear, NOMMES
#       + chaque CONTROLE qui echoue. Denominateur publie : `worker_replies_examined`.
#   La dette d'AVANT (meme fenetre de 7 jours, avant le correctif) est publiee a part, nommee :
#       `worker_replies_off_thread_before_fix`.
#   CONTROLES, hors reseau, dans les VRAIES fonctions (`linear_sync.default_reply_target` ->
#   `owner_sla.linear_sources` -> `collect` -> `default_reply` ; `owner_sla.off_thread_replies`) :
#     NEGATIF  l'outil vise le retour ouvert ; la reponse postee dans ce fil l'eteint ; 0 hors fil
#     POSITIF  une reponse redigee SEMEE hors fil rougit le compteur de 1 et est NOMMEE
#     + fil d'un retour pose en reponse, retour le plus recent, rien a viser si deja repondu,
#       message automatique hors population, fenetre, ticket illisible compte.
#
# INCONNU = DEFAUT : Linear injoignable ou ticket illisible -> `worker_replies_off_thread=-1`.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "worker_replies_off_thread=-1"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import datetime, os, sys, time

sys.path.insert(0, os.path.abspath(".autoport"))
sys.path.insert(0, os.path.abspath(".autoport/lib"))
import owner_sla as O
import linear_sync as S

ID = "harness-workers-reply-in-the-owner-thread"
OWNER, APP = {"user": {"id": "owner-1", "app": False}}, {"user": {"id": "app-1", "app": True}}

def com(cid, body, at, who, parent=None):
    c = {"id": cid, "body": body, "createdAt": at, "reactions": []}
    c.update(who)
    if parent:
        c["parentId"] = parent
    return c

class FakeL:
    """Linear FABRIQUE : repond a la requete par paquets de `owner_sla.linear_sources`."""
    def __init__(self, tickets):
        self.tickets = tickets
    def q(self, query, **v):
        if "issues(filter" in query:
            return {"issues": {"nodes": [{"id": t, "comments": {
                "nodes": list(self.tickets.get(t, [])),
                "pageInfo": {"hasNextPage": False, "endCursor": None}}} for t in v.get("ids") or []]}}
        raise AssertionError("requete inattendue : %s" % query[:60])

class FakeB:
    def __init__(self, items):
        self.items = {it["id"]: it for it in items}
    def get(self, iid):
        return self.items.get(iid)

MP = {"_owner": {"user_id": "owner-1"}, "i": {"issue_id": "T", "identifier": "JAK-0"}}
is_owner = lambda c: S.is_owner_comment(c, "owner-1")
is_harness = S.is_harness_comment

def fb(text, cid, date="2026-09-23"):
    return {"date": date, "text": text, "via": {"comment": cid, "ticket": "T"}}

def records(comments, feedbacks):
    rows = O.rows_from_backlog([{"id": "i", "owner_feedback": feedbacks}], MP)
    return O.collect(rows, lambda _t: comments, is_owner, is_harness, now=2e9)

def target(comments, feedbacks):
    return S.default_reply_target(FakeL({"T": comments}), FakeB([{"id": "i", "owner_feedback": feedbacks}]), MP, "i")

ctl, ctl_fail = [], 0
def check(name, ok):
    global ctl_fail
    ctl.append("%s:%s" % (name, "ok" if ok else "ECHEC"))
    ctl_fail += 0 if ok else 1

try:
    O1 = com("o1", "La jauge deborde encore", "2026-09-23T10:00:00.000Z", OWNER)
    F1 = [fb(O1["body"], "o1")]
    # NEGATIF : l'outil vise o1 ; la reponse postee dans ce fil l'eteint, 0 hors fil sur 1 examinee
    t = target([O1], F1)
    check("neg_tool_targets_open_feedback", bool(t) and t[0] == "T" and t[1] == "o1")
    rep = com("a1", "Corrige : la jauge tient dans son cadre.", "2026-09-23T11:00:00.000Z", APP,
              parent=(t[1] if t else None))
    rs = records([O1, rep], F1)
    off = O.off_thread_replies(rs, lambda _t: [O1, rep], is_harness, since=0)
    check("neg_reply_in_thread_answers", rs[0]["answered"] == 1 and rs[0]["answer_how"] == "reply")
    check("neg_zero_off_thread", off["examined"] == 1 and off["in_thread"] == 1 and not off["off"])
    # POSITIF : la meme reponse SEMEE hors fil (ce que faisait `--comment` sans `--reply-to`)
    seme = com("seme-hors-fil", rep["body"], rep["createdAt"], APP)
    rs = records([O1, seme], F1)
    off = O.off_thread_replies(rs, lambda _t: [O1, seme], is_harness, since=0)
    check("pos_seeded_off_thread_named", rs[0]["open"] == 1 and len(off["off"]) == 1
          and off["off"][0]["comment"] == "seme-hors-fil" and off["off"][0]["items"] == ["i"])
    # un retour pose EN REPONSE a un message du harnais : Linear n'a qu'un niveau, le fil est le parent
    H0 = com("h0", "Build publie", "2026-09-23T09:00:00.000Z", APP)
    O2 = com("o2", "Toujours pareil chez moi", "2026-09-23T10:30:00.000Z", OWNER, parent="h0")
    t = target([H0, O2], [fb(O2["body"], "o2")])
    check("tool_thread_of_a_reply", bool(t) and t[1] == "h0")
    # deux retours ouverts : le plus recent
    O3 = com("o3", "Et la couleur est fausse", "2026-09-23T12:00:00.000Z", OWNER)
    t = target([O1, O3], F1 + [fb(O3["body"], "o3")])
    check("tool_latest_open", bool(t) and t[1] == "o3")
    # deja repondu dans son fil : rien a viser, le message part hors fil sans rien accuser
    t = target([O1, rep], F1)
    check("tool_none_when_answered", t is None)
    tardif = com("a2", "Autre chose", "2026-09-23T13:00:00.000Z", APP)
    off = O.off_thread_replies(records([O1, rep, tardif], F1), lambda _t: [O1, rep, tardif], is_harness, since=0)
    check("no_open_feedback_not_counted", off["examined"] == 1 and not off["off"])
    # message AUTOMATIQUE hors fil : pas une reponse, hors population
    auto = com("v1", "🤖 **Essai 2** : porte rouge", "2026-09-23T11:00:00.000Z", APP)
    off = O.off_thread_replies(records([O1, auto], F1), lambda _t: [O1, auto], is_harness, since=0)
    check("auto_message_not_counted", off["examined"] == 0 and not off["off"])
    # fenetre : le seme d'AVANT `since` n'entre pas
    off = O.off_thread_replies(records([O1, seme], F1), lambda _t: [O1, seme], is_harness,
                               since=O.iso_to_epoch("2026-09-23T12:00:00Z"))
    check("window_excludes_before", off["examined"] == 0 and not off["off"])
    # ticket illisible : compte, jamais lu comme vide
    def boom(_t):
        raise RuntimeError("reseau")
    off = O.off_thread_replies(records([O1, seme], F1), boom, is_harness, since=0)
    check("fetch_failure_counted", off["fetch_failed"] == 1 and off["examined"] == 0)
except Exception as exc:  # noqa: BLE001 — un controle qui plante est un controle rouge
    check("control_crash_%s" % type(exc).__name__, False)

# ------------------------------------------------------------------ le VRAI Linear
real = -1
try:
    import backlog as B
    import linear_identity as LI
    L = S.Linear(LI.resolve())
    mp = S.load_map()
    owner_id = S.owner_user_id(L, mp)
    now = time.time()
    depuis = (datetime.date.fromtimestamp(now) - datetime.timedelta(days=30)).isoformat()
    rows = O.rows_from_backlog(B.load().items, mp, since_date=depuis)
    fetch, is_own, is_har = O.linear_sources(L, owner_id, tickets=[r["ticket"] for r in rows])
    rs = O.collect(rows, fetch, is_own, is_har, now=now)
    since7 = now - O.FENETRE_JOURS * 86400
    fix = O.iso_to_epoch(O.THREAD_DEFAULT_SINCE)
    after = O.off_thread_replies(rs, fetch, is_har, since=max(since7, fix))
    before = O.off_thread_replies(rs, fetch, is_har, since=since7, until=fix)
    print("worker_replies_feedback_rows=%d" % len(rows))
    print("worker_replies_feedback_dated=%d" % sum(1 for r in rs if r.get("dated")))
    print("worker_replies_feedback_open=%d" % len(O.open_records(rs)))
    print("worker_replies_tickets=%d" % after["tickets"])
    print("worker_replies_fetch_failed=%d" % after["fetch_failed"])
    print("worker_replies_window_days=%d" % O.FENETRE_JOURS)
    print("worker_replies_fix_since=%s" % O.THREAD_DEFAULT_SINCE)
    print("worker_replies_examined=%d" % after["examined"])
    print("worker_replies_in_thread=%d" % after["in_thread"])
    print("worker_replies_off_thread_real=%d" % len(after["off"]))
    print("worker_replies_off_thread_named=%s" % (",".join(
        "%s@%s" % (o["comment"], "+".join(o["items"])) for o in after["off"]) or "-"))
    print("worker_replies_before_fix_examined=%d" % before["examined"])
    print("worker_replies_before_fix_in_thread=%d" % before["in_thread"])
    print("worker_replies_off_thread_before_fix=%d" % len(before["off"]))
    print("worker_replies_off_thread_before_fix_named=%s" % (",".join(
        "%s@%s" % (o["comment"], "+".join(o["items"])) for o in before["off"][:12]) or "-"))
    real = -1 if after["fetch_failed"] else len(after["off"])
except Exception as exc:  # noqa: BLE001
    print("worker_replies_linear_error=%s" % type(exc).__name__)

print("worker_replies_controls=%d" % len(ctl))
print("worker_replies_controls_failed=%d" % ctl_fail)
print("worker_replies_controls_list=%s" % ",".join(ctl))
print("worker_replies_off_thread=%d" % (-1 if real < 0 else real + ctl_fail))
PY
