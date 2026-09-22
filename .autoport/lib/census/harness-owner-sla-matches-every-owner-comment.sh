#!/usr/bin/env bash
# census/harness-owner-sla-matches-every-owner-comment.sh — LE VERDICT DE L'ITEM.
#
# Lance par `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`) apres la course.
#
# CE QU'IL MESURE — un terme par point du livrable :
#   1. AVANT : l'ancien appariement (prefixe de 60 caracteres, 100 premiers commentaires du
#      ticket), rejoue sur la MEME fenetre ; chaque retour qu'il rate recoit sa CAUSE nommee.
#   2/3. APRES : le code LIVRE (`owner_sla.rows_from_backlog` -> `linear_sources` -> `collect`)
#      sur les vrais retours des 7 derniers jours -> `owner_sla_unmatched`, et son denominateur.
#   4. CONTROLES semes, hors reseau : un retour reecrit a la recopie EST retrouve ; un
#      commentaire du harnais qui cite l'owner mot pour mot N'EST PAS pris pour lui.
#
# INCONNU = DEFAUT. Linear injoignable -> `owner_sla_unmatched=-1` (la porte `== 0` rougit).
# Un controle qui echoue s'AJOUTE a `owner_sla_unmatched` : un zero obtenu par un appariement
# qui prend le harnais pour l'owner serait un faux vert. Le compte reel reste publie a part
# (`owner_sla_unmatched_real`).
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "owner_sla_unmatched=-1"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import datetime, json, os, sys, time

sys.path.insert(0, os.path.abspath(".autoport"))
sys.path.insert(0, os.path.abspath(".autoport/lib"))
import owner_sla as O

OUT, ORDRE = {}, []
def pub(k, v):
    if k not in OUT:
        ORDRE.append(k)
    OUT[k] = v


def old_match(comments, text, is_owner):
    """L'appariement d'AVANT (HEAD 011d52f817), recopie tel quel : c'est le bras condamne."""
    cible = O._normalise(text)
    if not cible:
        return None
    court = cible[:60]
    for c in comments:
        if not is_owner(c):
            continue
        corps = O._normalise(c.get("body"))
        if corps == cible or (court and (corps.startswith(court) or cible.startswith(corps[:60]))):
            return c
    return None


# ============================================================== 4. CONTROLES (hors reseau)
OWNER = {"user": {"id": "owner-1", "app": False}}
APP = {"user": {"id": "app-1", "app": True}}
is_owner = lambda c: (c.get("user") or {}).get("id") == "owner-1"
is_harness = lambda c: bool((c.get("user") or {}).get("app"))

def com(cid, body, at, who):
    d = {"id": cid, "body": body, "createdAt": at}
    d.update(who)
    return d

def run1(row, comments):
    return O.collect([row], lambda _t: comments, is_owner, is_harness, now=2e9)[0]

ctl_fail = 0
ctl = []
def check(name, ok):
    global ctl_fail
    ctl.append("%s:%s" % (name, "ok" if ok else "ECHEC"))
    if not ok:
        ctl_fail += 1

IMG = "![capture.png](https://uploads.linear.app/a/b/c.png)"
corps = "La jauge deborde encore\n\n" + IMG
recopie = corps + "\n[images enregistrees : .autoport/owner-feedback/x/20260923T1012-1.png]"
t1 = [com("c-own", corps, "2026-09-23T10:12:00.000Z", OWNER),
      com("c-app", "Corrige.", "2026-09-23T11:00:00.000Z", APP)]
# POSITIF a : texte reecrit a la recopie (image), SANS identifiant -> retrouve par le texte
r = run1({"item": "i", "ticket": "T", "text": recopie, "date": "2026-09-23"}, t1)
check("pos_image_rewrite_text", r["dated"] == 1 and r["match"] == "text" and r["answered"] == 1)
# POSITIF b : texte reecrit AU POINT d'etre meconnaissable, AVEC identifiant -> retrouve par l'id
r = run1({"item": "i", "ticket": "T", "text": "[texte expurge a la recopie]", "date": "2026-09-23",
          "via": {"comment": "c-own", "ticket": "T"}}, t1)
check("pos_rewrite_by_id", r["dated"] == 1 and r["match"] == "id")
# POSITIF c : ticket de 139 commentaires -> le retour du 101e est retrouve (pagination)
class FakeL:
    def __init__(self, nodes):
        self.nodes, self.n = nodes, 0
    def q(self, query, **v):
        self.n += 1
        if "issues(filter" in query:
            return {"issues": {"nodes": [{"id": "T", "comments": {
                "nodes": self.nodes[:100],
                "pageInfo": {"hasNextPage": True, "endCursor": "p100"}}}]}}
        return {"issue": {"comments": {"nodes": self.nodes[100:],
                                       "pageInfo": {"hasNextPage": False, "endCursor": None}}}}
nodes = [com("h%d" % i, "reponse %d" % i, "2026-09-22T%02d:%02d:00.000Z" % (i // 60, i % 60), APP)
         for i in range(138)]
nodes.append(com("vieux", "Alors je saurais dire si la particule est la bonne, elle est dessous",
                 "2026-09-19T07:50:00.000Z", OWNER))
old_fetch = {"T": nodes[:100]}
FL = FakeL(nodes)
import linear_sync as S
fetch, _o, _h = O.linear_sources(FL, "owner-1", tickets=["T"])
got = fetch("T")
r = O.collect([{"item": "i", "ticket": "T", "text": nodes[-1]["body"], "date": "2026-09-19"}],
              fetch, is_owner, is_harness, now=2e9)[0]
check("pos_comment_beyond_100", len(got) == 139 and r["dated"] == 1)
pub("owner_sla_ctl_old_rule_beyond_100_found",
    1 if old_match(old_fetch["T"], nodes[-1]["body"], is_owner) else 0)

# NEGATIF a : le harnais CITE l'owner mot pour mot (corps identique + citation), aucun
# commentaire de l'owner -> NON apparie
texte = "putain mais fonce, je veux tester la jauge"
t2 = [com("h1", texte, "2026-09-22T11:33:00.000Z", APP),
      com("h2", "Owner 22/09 : « %s »" % texte, "2026-09-22T11:34:00.000Z", APP)]
r = run1({"item": "i", "ticket": "T", "text": texte, "date": "2026-09-22"}, t2)
check("neg_harness_quotes_owner", r["dated"] == 0 and r["match"] == "")
# NEGATIF b : un identifiant qui designe un commentaire du HARNAIS ne date rien
r = run1({"item": "i", "ticket": "T", "text": texte, "date": "2026-09-22",
          "via": {"comment": "h1", "ticket": "T"}}, t2)
check("neg_id_of_harness_comment", r["dated"] == 0)
# NEGATIF c : un « oui » de l'owner ne date pas « oui ouvre le chantier »
t3 = [com("o1", "oui", "2026-09-20T09:00:00.000Z", OWNER)]
r = run1({"item": "i", "ticket": "T", "text": "oui ouvre le chantier", "date": "2026-09-23"}, t3)
check("neg_short_owner_prefix", r["dated"] == 0)
pub("owner_sla_ctl_old_rule_short_prefix_false_match",
    1 if old_match(t3, "oui ouvre le chantier", is_owner) else 0)

pub("owner_sla_controls", len(ctl))
pub("owner_sla_controls_failed", ctl_fail)
pub("owner_sla_controls_list", ",".join(ctl))

# ============================================================ 1 + 2/3. LES VRAIS RETOURS
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
    fetch, is_own, is_har = O.linear_sources(
        L, owner_id, tickets=[r["ticket"] for r in rows] + [r["item_ticket"] for r in rows])
    recs = O.collect(rows, fetch, is_own, is_har, now=now)
    c = O.cost_summary(recs, O.sla_seconds(), now=now)

    pub("owner_sla_window_days", O.FENETRE_JOURS)
    pub("owner_sla_window_since", depuis)
    pub("owner_sla_population", c["population"])
    pub("owner_sla_matched", c["dated"])
    pub("owner_sla_matched_by_id", c["by_id"])
    pub("owner_sla_matched_by_text", c["by_text"])
    for src in O.EXCLUDED_SOURCES:
        pub("owner_sla_excluded_%s" % src, c["excluded"].get(src, 0))
    pub("owner_sla_without_via", sum(1 for r in rows if not r["via"]))
    pub("owner_sla_answered", c["answered"])
    pub("owner_sla_open", c["open"])
    real = c["unmatched"]
    pub("owner_sla_unmatched_real", real)
    pub("owner_sla_unmatched_list", ";".join(
        "%s@%s" % (r["item"], r["date"]) for r in recs
        if not r["dated"] and not r.get("excluded")) or "-")

    # AVANT : l'ancien appariement, sur l'ITEM ticket et ses 100 premiers commentaires.
    causes = {}
    avant = 0
    for row, rec in zip(rows, recs):
        tous = fetch(row["item_ticket"])
        if old_match(tous[:100], row["text"], is_own) is not None:
            continue
        avant += 1
        via = row["via"] or {}
        src = O._origin(via)
        if src in O.EXCLUDED_SOURCES:
            cause = {"move": "deplacement-de-ticket", "supervisor": "relais-hors-linear",
                     "deleted": "commentaire-retire-de-linear"}[src]
        elif via.get("ticket") and via["ticket"] != row["item_ticket"]:
            cause = "dit-sur-un-autre-ticket"
        elif old_match(tous, row["text"], is_own) is not None:
            cause = "au-dela-des-100-premiers-commentaires"
        elif O.strip_recopy(row["text"]) != row["text"]:
            cause = "reecriture-image"
        else:
            cause = "autre"
        causes[cause] = causes.get(cause, 0) + 1
    pub("owner_sla_before_unmatched", avant)
    for k in sorted(causes):
        pub("owner_sla_before_cause_%s" % k.replace("-", "_"), causes[k])
    pub("owner_sla_before_cause_reecriture_image", causes.get("reecriture-image", 0))

    # NEGATIF REEL : sur JAK-176, « putain mais fonce » n'existe QUE cite par le harnais.
    t176 = (mp.get("hud-eco-gauge") or {}).get("issue_id")
    cites = [x for x in fetch(t176) if "putain mais fonce" in O._normalise(x.get("body"))]
    pub("owner_sla_real_harness_quotes_seen", sum(1 for x in cites if is_har(x)))
    pris = 1 if O._match_owner_comment(fetch(t176),
                                       "putain mais fonce, je dois te repeter combien de fois, "
                                       "je veux tester la jauge.casse couille !", is_own) else 0
    pub("owner_sla_real_harness_quote_taken_for_owner", pris)
    if pris or not cites:
        ctl_fail += 1  # pris pour l'owner = defaut ; plus de citation a JAK-176 = controle muet
    pub("owner_sla_linear_queries", L.n)
except Exception as exc:  # noqa: BLE001
    pub("owner_sla_error", str(exc).replace(" ", "_")[:120])

pub("owner_sla_unmatched", real + ctl_fail if real >= 0 else -1)
for k in ORDRE:
    print("%s=%s" % (k, OUT[k]))
PY
