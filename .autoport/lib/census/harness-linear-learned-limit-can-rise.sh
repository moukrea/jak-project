#!/usr/bin/env bash
# census/harness-linear-learned-limit-can-rise.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `linear_learned_limit_stale`.
#
# LE DEFAUT (signale par trois workers, owner « oui ouvre » le 23/09) : `make_room` apprend une limite d'espace sur
# un refus Linear (`learned_limit` dans .linear_space.json) et ne la relevait JAMAIS : l'owner qui change de plan
# gardait un archivage calcule sur l'ancienne limite jusqu'a l'effacement du fichier. Desormais `relax_learned` la
# fait tomber des que Linear laisse exister plus de tickets actifs qu'elle (creation ou desarchivage accepte :
# `note_accepted` dans `with_room` ; recensement), et au plus tard apres LEARNED_TTL_S (re-sondage : le prochain
# refus la reapprend, un seul essai perdu).
#
# CE QU'IL MESURE — `linear_learned_limit_stale` = somme de :
#   V   VIVANT : l'etat reel (.linear_space.json) juge par `judge` : 1 si une limite apprise est plus basse que le
#       plus grand compte que Linear a accepte depuis, ou toujours en place a un recensement posterieur a sa duree
#       de vie. Aucune limite apprise = 0, et `linear_learned_limit_present=0` le dit (denominateur).
#   C   CONTROLES FABRIQUES, hors reseau, sur un faux Linear (memes erreurs que le vrai) avec les VRAIES fonctions
#       (make_room, ensure_ticket -> with_room). La verite (le plus grand compte ACCEPTE) est celle du FAUX Linear,
#       jamais celle que le code ecrit. Chaque controle du code livre qui finit en defaut compte 1 ; chaque controle
#       POSITIF (le defaut SEME : copie du module ou `relax_learned`/`note_accepted` sont neutralises) qui ne rougit
#       pas, ou rougit sans NOMMER le terme, compte 1 (controle mort).
#         N1  limite vraie 150, apprise il y a 1 min     -> gardee, archivage fait (NEGATIF)
#         N2  limite vraie 150, apprise il y a 7 h       -> re-sondee : 1 refus, reapprise a 150, 2 essais
#         P1  plan passe a 250, 40 creations d'affilee   -> tombe a la 1re creation au-dela de 150
#         P1s idem, defaut SEME                          -> reste a 150 sous 160 acceptes : ROUGE et NOMME
#         P2  plan passe a 250, apprise il y a 7 h       -> tombe au recensement, rien d'archive, 1 essai
#         P2s idem, defaut SEME                          -> gardee et archivage : ROUGE et NOMME
#   INCONNU = DEFAUT : un terme non mesure compte 1.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "linear_learned_limit_stale=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import importlib.util, io, json, shutil, sys, tempfile, time
from contextlib import redirect_stdout
from pathlib import Path
sys.path.insert(0, '.autoport')
import linear_sync as S

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
stale, unmeasured, failed = 0, 0, []
SB = Path(tempfile.mkdtemp(prefix="linear-learned-"))
TEAM = "team-jak"
TTL = getattr(S, "LEARNED_TTL_S", None)


def judge(st, truth=None):
    """(0|1, terme). `truth` : le plus grand compte accepte selon le FAUX Linear ; sinon celui que l'etat porte."""
    ll = int(st.get("learned_limit") or 0)
    if not ll:
        return 0, "aucune_limite_apprise"
    acc = truth if truth is not None else int(st.get("accepted_max") or 0)
    if acc > ll:
        return 1, "limite_apprise_%d_sous_%d_acceptes" % (ll, acc)
    late = float(st.get("checked") or 0) - float(st.get("learned_at") or 0)
    if TTL is None or late > TTL:
        return 1, "limite_apprise_%d_encore_en_place_%dh_apres" % (ll, late // 3600)
    return 0, "limite_apprise_%d_saine" % ll


def err(msg, code):
    return RuntimeError(json.dumps([{"message": msg, "extensions": {"code": code}}]))


class FakeLinear:
    """Limite d'espace sur les tickets NON archives ; `accepted_max` = le plus grand compte atteint par une creation
    acceptee (la verite du controle)."""
    mode = "app"
    def __init__(self, limit):
        self.limit, self.iss, self.calls, self.accepted_max = limit, {}, [], 0
    def add(self, i, state="completed", when="2026-09-01"):
        self.iss[i] = {"id": i, "identifier": i.upper(), "state": state, "archived": False, "when": when}
    def active(self):
        return [x for x in self.iss.values() if not x["archived"]]
    def _page(self, nodes, a):
        k = int(a or 0)
        return {"issues": {"pageInfo": {"hasNextPage": k + 250 < len(nodes), "endCursor": str(k + 250)},
                           "nodes": nodes[k:k + 250]}}
    def q(self, query, **v):
        op = next((o for o in ("issueArchive", "issueCreate") if o in query), "query")
        self.calls.append(op)
        if op == "issueArchive":
            self.iss[v["id"]]["archived"] = True; return {"issueArchive": {"success": True}}
        if op == "issueCreate":
            if len(self.active()) >= self.limit:
                raise err("usage limit exceeded", "USAGE_LIMIT_EXCEEDED")
            i = "neuf-%d" % len(self.iss); self.add(i, state="unstarted", when="2026-09-23")
            self.accepted_max = max(self.accepted_max, len(self.active()))
            return {"issueCreate": {"issue": {"id": i, "identifier": i.upper(), "url": "u"}}}
        if "or:[" in query:                                              # find_issue_for : aucun existant
            return {"issues": {"nodes": []}}
        if "filter:{state" in query:                                     # archivable
            return self._page([{"id": x["id"], "identifier": x["identifier"], "completedAt": x["when"] + "T00:00:00.000Z",
                                "team": {"id": TEAM}, "labels": {"nodes": []}}
                               for x in self.active() if x["state"] == "completed"], v.get("a"))
        if "issues(first:250" in query:                                  # count_active
            return self._page([{"id": x["id"]} for x in self.active()], v.get("a"))
        raise AssertionError("requete non simulee : " + query[:80])


class FakeBacklog:
    items = []
    def get(self, iid): return None


def module(seeded):
    """Une copie NEUVE du vrai module ; `seeded` : le defaut d'origine seme (limite apprise jamais relevee)."""
    spec = importlib.util.spec_from_file_location("ls_%s" % ("seme" if seeded else "livre"), ".autoport/linear_sync.py")
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    d = Path(tempfile.mkdtemp(dir=SB))
    m.SPACE_PATH, m.MAP_PATH, m.SHADOW_PATH = d / "space.json", d / "map.json", d / "shadow.json"
    m.save_map = lambda mp: None
    m._CTX.update(bl=FakeBacklog(), mp={}, todo="label-todo", team=TEAM)
    if seeded:
        m.relax_learned = lambda *a, **k: False
        m.note_accepted = lambda *a, **k: None
    return m


def scenario(seeded, true_limit, n_open, n_closed, learned, age_s, creations):
    m = module(seeded)
    L = FakeLinear(true_limit)
    for k in range(n_open):
        L.add("o%d" % k, state="unstarted")
    for k in range(n_closed):
        L.add("c%d" % k, when="2026-%02d-%02d" % (1 + k // 28, 1 + k % 28))
    now = time.time()
    m.SPACE_PATH.write_text(json.dumps({"learned_limit": learned, "learned_at": now - age_s, "accepted_max": learned}))
    buf, raised, made = io.StringIO(), "", 0
    with redirect_stdout(buf):
        m.make_room(L, force=True)
        arch0 = L.calls.count("issueArchive")
        L.calls.clear()
        for k in range(creations):
            try:
                made += int(m.ensure_ticket(L, {}, TEAM, "item-%d" % k, "t%d" % k, {"title": "t%d" % k}, "Todo", "h")[1])
            except RuntimeError as e:
                raised = str(e)[:120]; break
    st = json.loads(m.SPACE_PATH.read_text())
    return {"st": st, "L": L, "log": buf.getvalue(), "archived_census": arch0, "made": made, "raised": raised,
            "creates": L.calls.count("issueCreate"), "verdict": judge(st, truth=L.accepted_max)}


def control(tag, fn):
    global unmeasured
    try:
        bad, detail = fn()
    except Exception as e:  # noqa: BLE001
        pub("linear_learned_ctl_%s_error" % tag, str(e)[:160]); bad, detail = 1, "erreur"; unmeasured += 1
    pub("linear_learned_ctl_%s_defects" % tag, bad)
    pub("linear_learned_ctl_%s_detail" % tag, detail)
    if bad:
        failed.append(tag)


def n1():
    r = scenario(False, 150, 20, 120, 150, 60, 0)                       # 140 actifs >= 127 : archivage attendu
    kept = int(r["st"].get("learned_limit") == 150)
    return int(not kept) + int(r["archived_census"] == 0) + r["verdict"][0], \
        "gardee=%d_archives=%d_%s" % (kept, r["archived_census"], r["verdict"][1])


def n2():
    r = scenario(False, 150, 30, 120, 150, 7 * 3600, 1)                 # 150 actifs : le re-sondage est refuse une fois
    ll = r["st"].get("learned_limit")
    return int(ll != 150) + int(r["creates"] != 2) + int(r["made"] != 1) + int("RELEVEE" not in r["log"]) + r["verdict"][0], \
        "reapprise=%s_essais=%d_cree=%d_%s" % (ll, r["creates"], r["made"], r["verdict"][1])


def p1(seeded):
    r = scenario(seeded, 250, 20, 100, 150, 60, 40)                     # 120 actifs, 40 creations d'affilee
    v, term = r["verdict"]
    if seeded:                                                          # le defaut seme DOIT rougir et etre NOMME
        return int(v != 1) + int("sous_160" not in term), "seme_%s" % term
    ll = r["st"].get("learned_limit")
    named = int("161" in r["log"] or "151" in r["log"])
    return v + int(ll is not None) + int(r["made"] != 40) + int(not named), \
        "limite=%s_cree=%d_acceptes=%d_%s" % (ll, r["made"], r["L"].accepted_max, term)


def p2(seeded):
    r = scenario(seeded, 250, 20, 120, 150, 7 * 3600, 1)                # 140 actifs : l'ancien code archive a 127
    v, term = r["verdict"]
    if seeded:
        return int(v != 1) + int("encore_en_place" not in term) + int(r["archived_census"] == 0), \
            "seme_%s_archives=%d" % (term, r["archived_census"])
    ll = r["st"].get("learned_limit")
    return v + int(ll is not None) + r["archived_census"] + int(r["creates"] != 1), \
        "limite=%s_archives=%d_essais=%d_%s" % (ll, r["archived_census"], r["creates"], term)


if TTL is None:
    unmeasured += 1
    pub("linear_learned_ttl_missing", 1)
control("n1_fresh_limit_kept_negative", n1)
control("n2_old_limit_reprobed_negative", n2)
control("p1_burst_beyond_raises", lambda: p1(False))
control("p1s_burst_beyond_seeded_defect", lambda: p1(True))
control("p2_old_limit_expires", lambda: p2(False))
control("p2s_old_limit_seeded_defect", lambda: p2(True))
pub("linear_learned_controls_total", 6)
pub("linear_learned_controls_failed", len(failed))
pub("linear_learned_controls_failed_list", ",".join(failed) or "-")
shutil.rmtree(SB, ignore_errors=True)

# ---------------------------------------------------------------- V : l'etat VIVANT ----
live = 0
try:
    st = S._space_state()
    live, term = judge(st)
    pub("linear_learned_limit_present", int(bool(st.get("learned_limit"))))
    pub("linear_learned_limit_value", st.get("learned_limit") or "-")
    pub("linear_learned_limit_accepted_max", st.get("accepted_max") or "-")
    pub("linear_learned_limit_age_h", "%.1f" % ((time.time() - float(st["learned_at"])) / 3600) if st.get("learned_at") else "-")
    pub("linear_learned_limit_last_dropped_why", st.get("learned_dropped_why") or "-")
    pub("linear_learned_limit_live_term", term)
    pub("linear_learned_limit_states_judged", 1)
    pub("linear_space_census_code", st.get("code") or "-")
    pub("linear_sync_code", S.CODE_FP)
except Exception as e:  # noqa: BLE001
    pub("linear_learned_limit_live_error", str(e)[:160]); unmeasured += 1
try:
    log = (S.HOME / "logs" / "linear_sync.txt").read_text(errors="replace")
    pub("linear_learned_log_learned", log.count("LIMITE LINEAR APPRISE"))
    pub("linear_learned_log_raised", log.count("LIMITE LINEAR RELEVEE"))
except OSError:
    pub("linear_learned_log_learned", "-")

pub("linear_learned_limit_stale_live", live)
pub("linear_learned_terms_unmeasured", unmeasured)
pub("linear_learned_limit_stale", live + len(failed) + unmeasured)
for k, v in OUT.items():
    print("%s=%s" % (k, v))
PY
