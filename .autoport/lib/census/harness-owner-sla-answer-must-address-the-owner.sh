#!/usr/bin/env bash
# census/harness-owner-sla-answer-must-address-the-owner.sh — LE VERDICT DE L'ITEM.
#
# Lance par `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`) apres la course.
#
# CE QU'IL MESURE — un terme par point du livrable :
#   1. AVANT : l'ancienne regle (« repondu » = le premier commentaire du harnais qui suit le
#      retour, HEAD d99e8f420f), rejouee sur la MEME fenetre de 7 jours. Combien de retours
#      n'etaient « repondus » QUE par des messages automatiques, et par quel producteur.
#   2. APRES : le code LIVRE (`owner_sla.rows_from_backlog` -> `linear_sources` -> `collect`)
#      sur les vrais retours -> `owner_sla_auto_answered_real`, avec son denominateur.
#   3. CONTROLES semes, hors reseau, dans les VRAIES fonctions :
#      POSITIF  l'ancienne regle, rebranchee dans `collect`, fait rougir la porte et NOMME le
#               producteur (etat, verdict, alerte-sla) ; le code livre laisse ces retours OUVERTS.
#      NEGATIF  une reponse dans le fil (`parentId`) et une reponse redigee d'avant la bascule
#               eteignent le retour ; auto_answered = 0.
#
# INCONNU = DEFAUT. Linear injoignable -> `owner_sla_auto_answered=-1` (la porte `== 0` rougit).
# Un controle qui echoue s'AJOUTE a `owner_sla_auto_answered` ; le compte reel reste publie a
# part (`owner_sla_auto_answered_real`).
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "owner_sla_auto_answered=-1"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import datetime, json, os, sys, time

sys.path.insert(0, os.path.abspath(".autoport"))
sys.path.insert(0, os.path.abspath(".autoport/lib"))
import owner_sla as O
import linear_sync as S
from lib.census import fake_backlog as FB

OUT, ORDRE = {}, []
def pub(k, v):
    if k not in OUT:
        ORDRE.append(k)
    OUT[k] = str(v).replace(" ", "_")

ctl_fail = 0
ctl = []
def check(name, ok):
    global ctl_fail
    ctl.append("%s:%s" % (name, "ok" if ok else "ECHEC"))
    if not ok:
        ctl_fail += 1


LIVRE = O.answer_how
def old_rule(comment, owner_comment, ts_of=None):
    """L'ancienne regle, BRANCHEE dans le vrai `collect` : tout commentaire du harnais repond."""
    return "legacy"


def with_old_rule(fn):
    O.answer_how = old_rule
    try:
        return fn()
    finally:
        O.answer_how = LIVRE


# ============================================================== 3. CONTROLES (hors reseau)
OWNER = {"user": {"id": "owner-1", "app": False}}
APP = {"user": {"id": "app-1", "app": True}}
is_owner = lambda c: (c.get("user") or {}).get("id") == "owner-1"
is_harness = lambda c: bool((c.get("user") or {}).get("app"))
APRES = "2026-09-24T10:00:00.000Z"          # retours poses APRES la bascule
AVANT = "2026-09-21T10:00:00.000Z"          # ... et AVANT

def com(cid, body, at, who, parent=None):
    d = {"id": cid, "body": body, "createdAt": at, "parentId": parent}
    d.update(who)
    return d

def plus(iso, h):
    t = datetime.datetime.fromisoformat(iso.replace("Z", "+00:00")) + datetime.timedelta(hours=h)
    return t.strftime("%Y-%m-%dT%H:%M:%S.000Z")

def seme(at, reponse_body, parent=None, own_parent=None):
    own = com("o1", "la jauge deborde encore a droite", at, OWNER, own_parent)
    rep = com("h1", reponse_body, plus(at, 1), APP, parent)
    return {"item": "i", "ticket": "T", "text": own["body"], "date": at[:10],
            "via": {"comment": "o1", "ticket": "T"}}, [own, rep]

def run(row, comments):
    return O.collect([row], lambda _t: comments, is_owner, is_harness, now=2e9)

# POSITIFS : un message AUTOMATIQUE suit le retour, rien d'autre.
for nom, corps in (("etat", "→ **En cours** : le harnais (agent Claude) y travaille — essai 1 sur 5."),
                   ("verdict", "**Essai 2 : échec.**\nCritère : « x »"),
                   ("alerte-sla", O.comment_body({"ts": 0}, {}, {"alive": False}, now=10800))):
    row, cs = seme(APRES, corps)
    avant = with_old_rule(lambda: run(row, cs))
    ca = O.cost_summary(avant, 7200, now=2e9)
    apres = run(row, cs)
    cb = O.cost_summary(apres, 7200, now=2e9)
    # le defaut seme ROUGIT la porte (ancienne regle) et est NOMME ; le code livre le laisse ouvert
    check("pos_%s_old_rule_red" % nom, ca["auto_answered"] == 1 and avant[0]["answer_auto"] == nom)
    check("pos_%s_shipped_open" % nom, cb["auto_answered"] == 0 and apres[0]["open"] == 1
          and apres[0]["auto_after"] == 1)
    pub("owner_sla_ctl_pos_%s_old_rule" % nom.replace("-", "_"), ca["auto_answered"])
    pub("owner_sla_ctl_pos_%s_named" % nom.replace("-", "_"), avant[0]["answer_auto"] or "-")

# L'alerte de ce module ne s'eteint plus ELLE-MEME : apres son post, le retour reste en retard.
row, cs = seme(APRES, O.comment_body({"ts": 0}, {}, {"alive": False}, now=10800))
recs = run(row, cs)
ev = O.evaluate(recs, {"alive": False}, now=2e9, sla_s=7200)
check("pos_alert_does_not_silence_itself", ev["overdue_n"] == 1)

# NEGATIFS (cas sains) : ce qui DOIT eteindre le retour l'eteint, sans rien compter d'automatique.
row, cs = seme(APRES, "Tu as raison, c'est corrige.", parent="o1")
r = run(row, cs)
check("neg_reply_in_thread", r[0]["answered"] == 1 and r[0]["answer_how"] == "reply"
      and O.cost_summary(r, 7200)["auto_answered"] == 0)
row, cs = seme(APRES, "Oui, c'est note.", parent="h0", own_parent="h0")
r = run(row, cs)
check("neg_reply_in_thread_of_a_thread", r[0]["answer_how"] == "reply")
row, cs = seme(AVANT, "Tu as raison, c'est corrige.")
r = run(row, cs)
check("neg_legacy_written_answer", r[0]["answer_how"] == "legacy" and r[0]["answer_auto"] == "")
# ... et ce qui ne VISE pas le retour ne l'eteint pas.
row, cs = seme(APRES, "Tu as raison, c'est corrige.")
r = run(row, cs)
check("neg_written_but_off_thread_stays_open", r[0]["open"] == 1)
row, cs = seme(APRES, "Tu as raison.", parent="o1")
cs[1]["createdAt"] = plus(APRES, -1)
r = run(row, cs)
check("neg_reply_before_feedback_is_not_an_answer", r[0]["open"] == 1)
# L'historique ne se recrie pas : avant la bascule, eteint par un automatique = pas d'alerte ;
# sans AUCUN message du harnais = alerte, comme avant.
row, cs = seme(AVANT, "→ **Terminé**.")
ev = O.evaluate(run(row, cs), {"alive": False}, now=2e9, sla_s=7200)
check("neg_history_not_realerted", ev["overdue_n"] == 0)
row, cs = seme(AVANT, "x")
ev = O.evaluate(run(row, cs[:1]), {"alive": False}, now=2e9, sla_s=7200)
check("pos_history_silence_still_alerted", ev["overdue_n"] == 1)

# LE POINT DE PRODUCTION : `--reply-to` pose le fil ; un message automatique ne le pose jamais.
class FakeL:
    mode = "app"
    def __init__(self, comment):
        self.comment, self.sent = comment, []
    def q(self, query, **v):
        if "comment(id:" in query:
            return {"comment": self.comment}
        self.sent.append(v.get("i"))
        return {"commentCreate": {"success": True}}
L1 = FakeL({"id": "o9", "parentId": "h3", "issue": {"id": "T9"}, "user": {"id": "owner-1", "app": False}})
sla_sb = FB.Sandbox([{"id": "i", "status": "open", "owner_feedback":
                      [{"date": "2026-09-01", "text": "a", "via": {"comment": "o8"}},
                       {"date": "2026-09-02", "text": "b", "via": {"comment": "o9"}}]}])
tk, parent = S.reply_target(L1, sla_sb.load(), "i", "last")
S._CTX["mp"] = {"i": {"issue_id": "T9", "identifier": "FAKE-9"}}  # un commentaire sans chantier ne part plus
S.post_comment(L1, tk, "reponse", parent=parent)
S.post_comment(L1, "T9", "→ **En cours**")
check("prod_reply_to_last_posts_in_thread", (tk, parent) == ("T9", "h3")
      and L1.sent[0].get("parentId") == "h3" and "parentId" not in L1.sent[1])
L2 = FakeL({"id": "h7", "issue": {"id": "T9"}, "user": {"id": "app-1", "app": True}})
try:
    S.reply_target(L2, sla_sb.load(), "i", "h7")
    refuse = False
except SystemExit:
    refuse = True
check("prod_reply_to_harness_comment_refused", refuse)
sla_sb.close()

pub("owner_sla_controls", len(ctl))
pub("owner_sla_controls_failed", ctl_fail)
pub("owner_sla_controls_list", ",".join(ctl))
pub("owner_sla_reply_since", O.REPLY_SINCE)

# ============================================================ 1 + 2. LES VRAIS RETOURS
real = -1
try:
    import yaml
    import linear_identity as LI

    L = S.Linear(LI.resolve())
    mp = json.loads(open(".autoport/linear_map.json").read())
    owner_id = (mp.get("_owner") or {}).get("user_id")
    bl = yaml.safe_load(open(".autoport/backlog.yaml"))
    items = bl["items"] if isinstance(bl, dict) and "items" in bl else bl
    now = time.time()
    depuis = (datetime.date.fromtimestamp(now)
              - datetime.timedelta(days=O.FENETRE_JOURS)).isoformat()
    rows = O.rows_from_backlog(items, mp, since_date=depuis)
    fetch, is_own, is_har = O.linear_sources(L, owner_id, tickets=[r["ticket"] for r in rows])
    apres = O.collect(rows, fetch, is_own, is_har, now=now)
    avant = with_old_rule(lambda: O.collect(rows, fetch, is_own, is_har, now=now))
    ca = O.cost_summary(avant, O.sla_seconds(), now=now)
    cb = O.cost_summary(apres, O.sla_seconds(), now=now)

    pub("owner_sla_window_days", O.FENETRE_JOURS)
    pub("owner_sla_window_since", depuis)
    pub("owner_sla_population", cb["population"])
    pub("owner_sla_dated", cb["dated"])

    # 1. AVANT
    pub("owner_sla_before_answered", ca["answered"])
    only = [r for r in avant if r["answered"] and r["harness_after"] == r["auto_after"]]
    first = [r for r in avant if r["answered"] and r["answer_auto"]]
    pub("owner_sla_before_auto_answered_only", len(only))
    pub("owner_sla_before_auto_answered_first", len(first))
    kinds = {}
    for r in first:
        kinds[r["answer_auto"]] = kinds.get(r["answer_auto"], 0) + 1
    for k in sorted(kinds):
        pub("owner_sla_before_auto_first_by_%s" % k.replace("-", "_"), kinds[k])
    # Le COUT de l'ancienne regle : le delai qu'elle arretait trop tot.
    pub("owner_sla_before_max_delay_s", ca["max_delay_s"])
    pub("owner_sla_before_over_sla", ca["over_sla"])
    pub("owner_sla_after_max_delay_s", cb["max_delay_s"])
    pub("owner_sla_after_over_sla", cb["over_sla"])
    pub("owner_sla_before_auto_only_list", ";".join(
        "%s@%s" % (r["item"], r["date"]) for r in only) or "-")

    # 2. APRES
    real = cb["auto_answered"]
    pub("owner_sla_answered", cb["answered"])
    pub("owner_sla_answered_by_reply", cb["by_reply"])
    pub("owner_sla_answered_by_legacy", cb["by_legacy"])
    pub("owner_sla_open", cb["open"])
    pub("owner_sla_auto_answered_real", real)
    pub("owner_sla_auto_answered_list", ";".join(
        "%s@%s:%s" % (r["item"], r["date"], r["answer_auto"]) for r in apres
        if r["answered"] and r["answer_auto"]) or "-")
    rouverts = [a for a, b in zip(avant, apres) if a["answered"] and not b["answered"]]
    pub("owner_sla_reopened_by_the_fix", len(rouverts))
    # Pas de rafale d'alertes sur l'historique : ce qui serait crie si le lecteur mourait.
    ev_b = with_old_rule(lambda: O.evaluate(avant, {"alive": False}, now=now))
    ev_a = O.evaluate(apres, {"alive": False}, now=now)
    pub("owner_sla_alert_overdue_if_reader_dead_before", ev_b["overdue_n"])
    pub("owner_sla_alert_overdue_if_reader_dead_after", ev_a["overdue_n"])
    pub("owner_sla_linear_queries", getattr(L, "n", -1))
except Exception as exc:  # noqa: BLE001
    pub("owner_sla_error", ("%s:%s" % (type(exc).__name__, exc))[:120])

pub("owner_sla_auto_answered", real + ctl_fail if real >= 0 else -1)
for k in ORDRE:
    print("%s=%s" % (k, OUT[k]))
PY
