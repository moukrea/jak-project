#!/usr/bin/env bash
# census/harness-linear-check-survives-a-bad-ticket.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `linear_check_aborted`.
#
# LE DEFAUT (signale par trois workers, owner « oui ouvre » le 23/09) : dans `linear_sync.py --check`, la boucle
# des orphelins (issueUpdate -> Canceled, puis commentaire) n'etait pas gardee. Un ticket qui refusait levait hors
# de la boucle : les orphelins suivants, le compte des ecarts d'etat et l'ecriture de la carte ne se faisaient plus.
# Idem pour un id que Linear refuse dans la lecture par lots de 50. Desormais chaque ticket est traite dans SA
# garde (`fail` / `guard` de linear_sync.py) ; les echecs sont COMPTES et NOMMES (ligne « tickets en echec »).
#
# CE QU'IL MESURE — `linear_check_aborted` = somme de :
#   S   SIMULE, code livre : le vrai `main()` rejoue depuis le source contre un faux Linear en memoire. 8 tickets :
#       SIM-O1 refuse son passage en Canceled, SIM-O3 refuse son commentaire, SIM-BAD fait refuser la lecture de
#       son lot ; SIM-O2 / SIM-O5 sont des orphelins SAINS places APRES les fautifs, SIM-T1 porte un ecart d'etat.
#       Compte 1 : passage interrompu ; chaque fautif non NOMME ; chaque orphelin sain non archive ; ecart non
#       compte ; carte non ecrite ; tout echec nomme qui n'etait pas seme.
#   V   VIVANT, lecture seule : le vrai `main()` contre le VRAI Linear, toute mutation REFUSEE par le recensement
#       (donc chaque orphelin a archiver devient un « ticket qui refuse »). Deux items vivants sont retires du
#       backlog EN MEMOIRE pour fabriquer deux orphelins, et un id malforme est ajoute a la carte EN MEMOIRE.
#       Rien n'est ecrit : ni Linear, ni la carte. Compte 1 : passage interrompu ; chaque orphelin refuse non NOMME.
#   CONTROLE NEGATIF (S) : monde sain, zero refus -> zero echec, tous les orphelins archives, sinon controle mort.
#   CONTROLES POSITIFS : le defaut d'origine SEME dans une copie du source (boucle des orphelins non gardee ;
#   lecture par lots non gardee) doit INTERROMPRE le passage ET le ticket fautif doit etre NOMME par l'exception.
#   Le positif « orphelin » est aussi rejoue VIVANT. INCONNU = DEFAUT : terme non mesure = 1, controle mort = 1.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "linear_check_aborted=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import copy, io, json, sys, types
from contextlib import redirect_stdout
from pathlib import Path
sys.path.insert(0, '.autoport')
sys.path.insert(0, '.autoport/lib/census')
from lib.census import fake_backlog as FB  # noqa: E402
import anchor as A  # noqa: E402
import ast  # noqa: E402

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
unmeasured, dead = [], []
SRC_PATH = Path(".autoport/linear_sync.py")
SRC = SRC_PATH.read_text()

# Le code d'AVANT (regression seme dans une copie), recopie ici : jamais lu a HEAD (faux des le commit).
OLD_ORPH = '''                    L.q('mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id,input:$i){ success } }', id=rec["issue_id"], i={"stateId": states["Canceled"]})
                    post_comment(L, rec["issue_id"], mark(L) + "Ce chantier n'existe plus dans le backlog du harnais : ticket archivé.")
                    print("  orphelin archive :", rec["identifier"], iid)
'''
OLD_READ = '''            nodes = L.q(QCHK, ids=ids[i:i + 50])["issues"]["nodes"]
'''


def _try_containing(src, spec):
    """Le noeud `try` UNIQUE qui enveloppe le noeud designe par `spec` (`has` ne s'applique pas a un `try` lui
    meme : on designe une instruction INTERIEURE, structurellement unique, et on remonte a son `try` parent)."""
    tree = ast.parse(src)
    target = A.site(tree, **spec)
    found = [n for n in ast.walk(tree) if isinstance(n, ast.Try) and any(d is target for d in ast.walk(n))]
    if len(found) != 1:
        raise A.Introuvable("try:%s:%d" % (spec, len(found)))
    return found[0]


def _drop_try_guard(src, spec, replacement):
    """Remplace le `try`/`except` entier (identifie par `spec`) par `replacement` (le corps SANS la garde) :
    equivalent structurel de la regression d'avant le 23/09."""
    n = _try_containing(src, spec)
    a, b = A.span(src, n)
    line_start = src.rfind("\n", 0, a) + 1
    return src[:line_start] + replacement + src[b:]


def _seed_orphelin(src):
    return _drop_try_guard(src, dict(func="main", kind="expr", has=("  orphelin archive :",)), OLD_ORPH)


def _seed_lecture(src):
    return _drop_try_guard(src, dict(func="main", kind="for", has=("one",)), OLD_READ)


SEEDS = {"orphelin": [_seed_orphelin], "lecture": [_seed_lecture]}


def load_variant(seeds):
    """Le module `linear_sync` REEL, rejoue depuis son source avec les remplacements `seeds` (callables
    src->src, structurels). Une graine introuvable = controle MORT (le code a change sous elle)."""
    src, missing = SRC, []
    for s in seeds:
        try:
            src = s(src)
        except A.Introuvable as e:
            missing.append(str(e))
    m = types.ModuleType("linear_sync_sim")
    m.__file__ = str(SRC_PATH.resolve())
    exec(compile(src, "linear_sync_sim", "exec"), m.__dict__)
    return m, missing


def run_check(m, make_L, bl, mp, resolve=None, stub_team=True):
    """`main()` du module m avec `--check`, contre le Linear, le backlog et la carte FOURNIS. Rien n'est ecrit
    sur disque : ni carte, ni registre des commentaires, ni verrou."""
    saved = []
    m.map_lock = lambda: None
    m.load_map = lambda: mp
    m.save_map = lambda x: saved.append(len(x))
    # LE faux backlog partage (harness-census-fake-backlog-matches-real-api) : les items de `bl` sur un fichier
    # JETABLE, la vraie classe et le vrai module ; une ecriture de --check ne touche jamais le vrai backlog.
    sb = FB.Sandbox(bl.items)
    FB.install(m, sb)
    m.OCAP = types.SimpleNamespace(record=lambda *a, **k: None, published_build=lambda *a, **k: {})
    m.SM = types.SimpleNamespace(install_hooks=lambda **k: None, mask_tree=m.SM.mask_tree)
    m.LI = types.SimpleNamespace(resolve=resolve or (lambda: {"mode": "app", "why": "recensement"}))
    m.Linear = make_L
    if stub_team:
        m.ensure_team = lambda L: "team-sim"
        m.ensure_states = lambda L, t: {n: "st-" + n for n, _ in m.STATES}
    argv, sys.argv = sys.argv, ["linear_sync.py", "--check"]
    buf, exc = io.StringIO(), None
    try:
        with redirect_stdout(buf):
            m.main()
    except BaseException as e:  # noqa: BLE001 — SystemExit compris : c'est le passage qui s'arrete
        exc = e
    finally:
        sys.argv = argv
        sb.close()
    out = buf.getvalue()
    last = (out.strip().splitlines() or [""])[-1]
    return {"out": out, "exc": exc, "completed": exc is None and last.startswith("coherence :"),
            "failed": list(m.FAILED), "saved": saved, "last": last}


# ============================================================================== S : SIMULE ==

class FakeL:
    mode = "app"

    def __init__(self, issues, refuse_update=(), refuse_comment=(), bad_read=()):
        self.issues, self.n = issues, 0
        self.ru, self.rc, self.br = set(refuse_update), set(refuse_comment), set(bad_read)
        self.updated, self.commented = [], []

    def q(self, query, **v):
        self.n += 1
        if "issues(filter:{id:{in:$ids}}" in query:
            bad = [i for i in v["ids"] if i in self.br]
            if bad:
                raise RuntimeError('[{"message": "Argument Validation Error: id %s"}]' % self.issues[bad[0]]["title"])
            return {"issues": {"nodes": [copy.deepcopy(self.issues[i]) for i in v["ids"] if i in self.issues]}}
        if "issueUpdate(" in query:
            if v["id"] in self.ru:
                raise RuntimeError('[{"message": "refus seme sur %s"}]' % self.issues[v["id"]]["title"])
            self.updated.append(self.issues[v["id"]]["title"])
            return {"issueUpdate": {"success": True}}
        if "commentCreate(" in query:
            iid = v["i"]["issueId"]
            if iid in self.rc:
                raise RuntimeError('[{"message": "commentaire refuse (seme) sur %s"}]' % self.issues[iid]["title"])
            self.commented.append(self.issues[iid]["title"])
            return {"commentCreate": {"success": True, "comment": {"id": "c-%d" % self.n}}}
        raise RuntimeError("requete inattendue du recensement : %s" % " ".join(query.split())[:80])


def sim_world():
    def iss(k, st):
        return {"id": "i-" + k, "archivedAt": None, "state": {"name": st}, "title": "SIM-" + k.upper()}
    order = [("o1", "Todo"), ("o2", "In Progress"), ("o3", "Todo"), ("o4", "Canceled"), ("bad", "In Progress"),
             ("t1", "Todo"), ("t2", "In Review"), ("o5", "Todo")]
    issues = {"i-" + k: iss(k, st) for k, st in order}
    mp = {"_owner": {"user_id": "u-owner"}}
    for k, _ in order:
        mp["sim-" + k] = {"issue_id": "i-" + k, "identifier": "SIM-" + k.upper(), "last_state": "", "hash": "x"}
    from lib import backlog as B
    bl = B.Backlog({"items": [{"id": "sim-bad", "status": "in-progress", "feature": "sim"},
                              {"id": "sim-t1", "status": "in-progress", "feature": "sim"},
                              {"id": "sim-t2", "status": "to-test", "feature": "sim"}]}, "/dev/null")
    return issues, mp, bl


def simulate(seeds, faulty=True):
    m, missing = load_variant(seeds)
    issues, mp, bl = sim_world()
    L = FakeL(issues, *(([ "i-o1"], ["i-o3"], ["i-bad"]) if faulty else ((), (), ())))
    r = run_check(m, lambda ident: L, bl, mp)
    r.update(missing=missing, L=L)
    return r


def names_in(text, names):
    return [n for n in names if n in text]


try:
    # --- code livre, monde fautif ---
    s = simulate([])
    expect_fail = ["SIM-O1", "SIM-O3", "SIM-BAD"]
    fail_txt = " | ".join(s["failed"])
    s_aborted = 0 if s["completed"] else 1
    s_unnamed = [n for n in expect_fail if n not in fail_txt]
    s_extra = [f for f in s["failed"] if not names_in(f, expect_fail)]
    s_skipped = [n for n in ("SIM-O2", "SIM-O5") if n not in s["L"].updated or n not in s["L"].commented]
    if " 1 ecarts d'etat" not in s["last"]:
        s_skipped.append("ecart_SIM-T1")
    if not s["saved"]:
        s_skipped.append("carte_non_ecrite")
    echec_line = next((l for l in s["out"].splitlines() if l.startswith("tickets en echec :")), "")
    pub("linear_check_sim_aborted", s_aborted)
    pub("linear_check_sim_exception", (str(s["exc"])[:100] if s["exc"] else "-"))
    pub("linear_check_sim_tickets", len([k for k in s["L"].issues]))
    pub("linear_check_sim_seeded_bad", len(expect_fail))
    pub("linear_check_sim_failed", len(s["failed"]))
    pub("linear_check_sim_failed_named", ",".join(n for n in expect_fail if n in fail_txt) or "-")
    pub("linear_check_sim_unnamed", len(s_unnamed))
    pub("linear_check_sim_extra", len(s_extra))
    pub("linear_check_sim_skipped", len(s_skipped))
    pub("linear_check_sim_skipped_list", ",".join(s_skipped) or "-")
    pub("linear_check_sim_archived", ",".join(sorted(set(s["L"].updated) & set(s["L"].commented))) or "-")
    pub("linear_check_sim_echec_line", echec_line[:120] or "ABSENTE")
    if not echec_line.startswith("tickets en echec : 3 sur 8"):
        s_unnamed.append("ligne_echecs")
    sim_term = s_aborted + len(s_unnamed) + len(s_extra) + len(s_skipped)

    # --- controle NEGATIF : monde sain ---
    n = simulate([], faulty=False)
    n_arch = sorted(set(n["L"].updated) & set(n["L"].commented))
    pub("linear_check_ctl_neg_aborted", 0 if n["completed"] else 1)
    pub("linear_check_ctl_neg_failed", len(n["failed"]))
    pub("linear_check_ctl_neg_archived", len(n_arch))
    if not n["completed"] or n["failed"] or n_arch != ["SIM-O1", "SIM-O2", "SIM-O3", "SIM-O5"]:
        dead.append("C-:%s" % (",".join(n["failed"])[:60] or "archives=%s" % ",".join(n_arch)))

    # --- controles POSITIFS : le defaut d'origine seme ---
    EXPECT = {"orphelin": "SIM-O1", "lecture": "SIM-BAD"}
    for tag, seeds in SEEDS.items():
        p = simulate(seeds)
        named = EXPECT[tag] in str(p["exc"] or "")
        pub("linear_check_ctl_pos_%s_aborted" % tag, 0 if p["completed"] else 1)
        pub("linear_check_ctl_pos_%s_named" % tag, EXPECT[tag] if named else "-")
        if p["missing"]:
            dead.append("C+_%s:introuvable" % tag)
        elif p["completed"] or not named:
            dead.append("C+_%s:muet" % tag)
except Exception as e:  # noqa: BLE001
    sim_term = 0
    unmeasured.append("simulation:" + str(e)[:80])
    pub("linear_check_sim_error", str(e)[:120])

# ============================================================== V : VIVANT, lecture seule ==
live_term = 0
try:
    m0, _ = load_variant([])
    RealLinear, real_resolve = m0.Linear, m0.LI.resolve
    real_mp = json.loads(m0.MAP_PATH.read_text())
    from lib import backlog as B
    real_bl = B.load()


    class ReadOnly:
        """Le VRAI Linear, toute mutation refusee ICI (rien ne part) : chaque orphelin devient un ticket qui refuse."""
        def __init__(self, ident):
            self.L, self.refused = RealLinear(ident), []
            self.mode = self.L.mode if hasattr(self.L, "mode") else "owner"

        @property
        def n(self):
            return self.L.n

        def q(self, query, **v):
            if query.lstrip().startswith("mutation"):
                tgt = v.get("id") or (v.get("i") or {}).get("issueId") or "?"
                self.refused.append(tgt)
                raise RuntimeError('[{"message": "ecriture refusee par le recensement sur %s"}]' % tgt)
            return self.L.q(query, **v)

    def live_world():
        mp = copy.deepcopy(real_mp)
        bl = copy.deepcopy(real_bl)
        live_ids = {it["id"] for it in bl.items if it.get("status") in ("in-progress", "to-test", "open", "blocked")}
        victims = sorted(k for k in mp if not k.startswith("_") and k in live_ids
                         and k != "harness-linear-check-survives-a-bad-ticket")[:2]
        bl.items = [it for it in bl.items if it["id"] not in victims]
        mp["zz-census-malformed-id"] = {"issue_id": "pas-un-uuid-recensement", "identifier": "CENSUS-MALFORME",
                                        "last_state": "", "hash": "x"}
        return mp, bl, [mp[v]["identifier"] for v in victims]

    def live(seeds):
        m, missing = load_variant(seeds)
        mp, bl, victims = live_world()
        box = {}
        def mk(ident):
            box["L"] = ReadOnly(ident)
            return box["L"]
        r = run_check(m, mk, bl, mp, resolve=real_resolve, stub_team=False)
        r.update(missing=missing, victims=victims, L=box.get("L"), mp=mp)
        return r

    v = live([])
    if v["exc"] is not None and "Linear indisponible" in str(v["exc"]):
        raise RuntimeError("Linear injoignable : %s" % str(v["exc"])[:60])
    fail_txt = " | ".join(v["failed"])
    v_unnamed = [x for x in v["victims"] if x not in fail_txt]
    refused = v["L"].refused if v["L"] else []
    v_aborted = 0 if v["completed"] else 1
    pub("linear_check_live_aborted", v_aborted)
    pub("linear_check_live_exception", (str(v["exc"])[:100] if v["exc"] else "-"))
    pub("linear_check_live_tickets", len([k for k in v["mp"] if not k.startswith("_")]))
    pub("linear_check_live_victims", ",".join(v["victims"]) or "-")
    pub("linear_check_live_mutations_refused", len(refused))
    pub("linear_check_live_failed", len(v["failed"]))
    pub("linear_check_live_unnamed", len(v_unnamed))
    pub("linear_check_live_malformed_named", 1 if "CENSUS-MALFORME" in fail_txt or "pas-un-uuid" in fail_txt else 0)
    pub("linear_check_live_line", v["last"][:160] or "-")
    live_term = v_aborted + len(v_unnamed)
    if len(v["victims"]) < 2:
        unmeasured.append("vivant:moins_de_2_victimes")
    # controle positif VIVANT : la boucle d'origine doit tomber sur le premier orphelin refuse
    pv = live(SEEDS["orphelin"])
    pv_named = any(r in str(pv["exc"] or "") for r in (pv["L"].refused if pv["L"] else [])[:1])
    pub("linear_check_ctl_pos_live_aborted", 0 if pv["completed"] else 1)
    pub("linear_check_ctl_pos_live_named", (pv["L"].refused[0] if pv_named else "-"))
    if pv["missing"]:
        dead.append("C+_vivant:introuvable")
    elif pv["completed"] or not pv_named:
        dead.append("C+_vivant:muet")
except Exception as e:  # noqa: BLE001
    unmeasured.append("vivant:" + str(e)[:80])
    pub("linear_check_live_error", str(e)[:120])

pub("linear_check_terms_unmeasured", len(unmeasured))
pub("linear_check_unmeasured_list", ",".join(unmeasured)[:200] or "-")
pub("linear_check_controls_dead", len(dead))
pub("linear_check_controls_dead_list", ",".join(dead)[:200] or "-")
pub("linear_check_aborted", sim_term + live_term + len(unmeasured) + len(dead))
for k, v in OUT.items():
    print("%s=%s" % (k, v))
PY
