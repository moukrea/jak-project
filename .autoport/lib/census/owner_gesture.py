#!/usr/bin/env python3
"""lib/census/owner_gesture.py — LE RECENSEMENT DE harness-owner-gesture-not-imputed-to-running-item.

LE DEFAUT (23/09, 11:01). L'essai 2 de harness-invisible-item-comment-has-no-capture-boilerplate est
refuse par la porte de la suite pour deux tests de `test_backlog.py`, « VERTS a la base de CET essai ».
Ils etaient rouges a cause de JAK-265 : un ticket que l'owner venait d'ouvrir, adopte PENDANT l'essai
dans `backlog.yaml` par la synchro Linear, sans consigne. Et l'adoption le classait `code_scope: jeu`
en dur, alors que JAK-265 etait un sujet de harnais.

CE QU'IL MESURE, chaque terme publie a part, la somme dans `owner_gesture_misimputed` :

  banc      Le VRAI juge (`lib/suite_gate.py`) sur des depots git JETABLES ou l'histoire est semee.
            Deux bras : APRES (le module livre) et AVANT (le dernier blob sans le marqueur
            `GESTE-ETRANGER/rejeu`, commit publie). Les semis :
              vert              rien de rouge                                  -> ferme
              geste             la VRAIE `linear_sync.adopt_owner_issues` adopte un ticket sans
                                consigne pendant l'essai (CONTROLE POSITIF)    -> APRES ferme,
                                                                                  AVANT refuse
              geste_commite     le meme, puis le superviseur commite le backlog -> idem
              neuf              l'essai casse le test lui-meme (CONTROLE NEGATIF) -> refuse
              neuf_sous_geste   l'essai casse le test ET un geste tombe        -> refuse : le geste
                                                                                  ne blanchit pas
              geste_a_la_main   la meme adoption ecrite SANS le journal        -> refuse : sans
                                                                                  auteur, pas d'excuse
  reel      Le cas du 23/09 lui-meme, sur les commits reels (a18246d727 base de l'essai,
            3336c0fcbb tete), les deux nodeids reels, et le geste reel reconstruit par le
            constructeur LIVRE (`linear_sync.adopted_item`). Les bras sans geste sont ce que le juge
            d'avant voyait (il imputait) ; le juge d'apres doit classer les deux rouges « geste ».
  adoption  `code_scope: a-cadrer` sur l'item adopte ; `next_open` le saute, meme consigne posee ;
            il le prend une fois le perimetre pose ; un item `jeu` ordinaire reste pris (controle).
  auteur    la ligne de commande `autoport` journalise sous `superviseur` hors essai, et NE journalise
            PAS sous un essai (AUTOPORT_ATTEMPT_ID pose) ; l'adoption journalise sous `linear_sync`.

POLARITE : INCONNU = DEFAUT. Un semis qui ne rend rien, un bras muet, un terme non mesure AJOUTE au
compte. Le denominateur est publie : `owner_gesture_closures_judged`.
"""
from __future__ import annotations

import contextlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve()
AP = HERE.parents[2]
REPO = AP.parent
for p in (str(AP), str(AP / "lib")):
    if p not in sys.path:
        sys.path.insert(0, p)

from lib import backlog as B  # noqa: E402
import linear_sync as LS  # noqa: E402

MARQUEUR = "GESTE-ETRANGER/rejeu"
IID = "zzz-banc-geste-owner"
NODE = ".autoport/tests/harness/test_petit.py::test_chaque_item_ouvert_designe_une_consigne"

TEST_PETIT = '''"""Suite MINIATURE : la forme du test qui a rougi le 23/09 (une consigne par item ouvert)."""
from pathlib import Path

import yaml

AP = Path(__file__).resolve().parents[2]


def test_chaque_item_ouvert_designe_une_consigne():
    doc = yaml.safe_load((AP / "backlog.yaml").read_text(encoding="utf-8"))
    manquants = [it["id"] for it in doc["items"] if it.get("status") == "open"
                 and not (it.get("prompt") and (AP / it["prompt"]).exists())]
    assert not manquants, manquants


def test_toujours_vert():
    assert 1 + 1 == 2
'''

GIT_ENV = {**os.environ, "GIT_AUTHOR_NAME": "banc", "GIT_AUTHOR_EMAIL": "banc@local",
           "GIT_COMMITTER_NAME": "banc", "GIT_COMMITTER_EMAIL": "banc@local"}
for _k in ("AUTOPORT_ATTEMPT_ID", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
    GIT_ENV.pop(_k, None)

OUT: dict = {}


def kv(key, value):
    s = str(value).replace("\n", " ").replace(" ", "_")[:400] or "-"
    OUT[key] = s
    print("%s=%s" % (key, s), flush=True)


def charger(src: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def before_blob(rel: str, marker: str) -> tuple[str, str]:
    """Le premier commit, en remontant, dont `rel` ne porte PAS `marker` (jamais lu a `HEAD:`)."""
    hist = subprocess.run(["git", "-C", str(REPO), "log", "--format=%H", "-n", "200", "--", rel],
                          capture_output=True, text=True, timeout=60).stdout.split()
    for commit in hist:
        blob = subprocess.run(["git", "-C", str(REPO), "show", "%s:%s" % (commit, rel)],
                              capture_output=True, text=True, timeout=60).stdout
        if blob and marker not in blob:
            return commit, blob
    return "", ""


def _git(root: Path, *args: str, quand: int = 0):
    env = dict(GIT_ENV)
    if quand:
        env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = "@%d +0000" % quand
    return subprocess.run(["git", *args], cwd=root, env=env, capture_output=True, text=True,
                          timeout=120)


class FakeL:
    """Le client Linear de la synchro, reduit a la page de tickets que lit `adopt_owner_issues`."""
    mode = "app"

    def __init__(self, nodes):
        self.nodes = nodes

    def q(self, query, **_kw):
        if "issues(" in query:
            return {"team": {"issues": {"pageInfo": {"hasNextPage": False, "endCursor": None},
                                        "nodes": self.nodes}}}
        return {}


def ticket(ident="JAK-265", titre="Attention aux profils opus 5.5 bouscule tout"):
    return {"id": "iss-" + ident, "identifier": ident, "title": titre,
            "description": "profils de modeles (banc)", "createdAt": "2026-09-23T10:30:00Z",
            "creator": {"id": "owner", "app": False}, "state": {"name": "Todo", "type": "unstarted"}}


def adopter(backlog_path: str) -> tuple[int, str]:
    """La VRAIE adoption de la synchro, reseau retire : `_say` et `swap_labels` parlent a Linear."""
    say, swap = LS._say, LS.swap_labels
    LS._say = lambda *a, **k: None
    LS.swap_labels = lambda *a, **k: None
    try:
        bl = B.load(backlog_path)
        mp: dict = {}
        with contextlib.redirect_stdout(sys.stderr):    # sa ligne « NOUVEAU TICKET » n'est pas une cle
            n = LS.adopt_owner_issues(FakeL([ticket()]), bl, mp, "team", "label", False)
    finally:
        LS._say, LS.swap_labels = say, swap
    return n, next(iter(mp), "-")


def semer(racine: Path, *, casse_par_l_item=False, geste=False, geste_commite=False,
          geste_a_la_main=False) -> float:
    ap = racine / ".autoport"
    for d in (ap / "tests" / "harness", ap / "prompts", ap / "reports" / IID, ap / "logs"):
        d.mkdir(parents=True, exist_ok=True)
    (ap / "tests" / "harness" / "test_petit.py").write_text(TEST_PETIT, encoding="utf-8")
    (ap / "tests" / "harness" / "ECHECS-ATTENDUS.yaml").write_text("attendus: []\n", encoding="utf-8")
    for nom in ("en-cours", "deja-la"):
        (ap / "prompts" / ("%s.md" % nom)).write_text("consigne\n", encoding="utf-8")
    items = [{"id": IID, "status": "in-progress", "priority": 1, "code_scope": "harnais",
              "prompt": "prompts/en-cours.md", "feature": "banc du geste de l'owner"},
             {"id": "deja-la", "status": "open", "priority": 2, "code_scope": "jeu",
              "prompt": "prompts/deja-la.md", "feature": "item ordinaire"}]
    bl_path = ap / "backlog.yaml"
    B._atomic_write(str(bl_path), B._dump({"version": 1, "items": items}))
    t0 = int(time.time()) - 900
    _git(racine, "init", "-q", ".")
    _git(racine, "add", "-A")
    _git(racine, "commit", "-q", "-m", "base du banc", quand=t0)
    depart = float(t0 + 30)
    if casse_par_l_item:
        doc = B._read(str(bl_path))
        doc["items"].append({"id": "casse-par-l-essai", "status": "open", "priority": 3,
                             "feature": "l'essai ajoute un item sans consigne"})
        B._atomic_write(str(bl_path), B._dump(doc))
    (ap / "notes.txt").write_text("le geste de l'essai\n", encoding="utf-8")
    _git(racine, "add", "-A")
    _git(racine, "commit", "-q", "-m", "[autoport/%s] le geste de l'essai" % IID, quand=t0 + 60)
    if geste:
        adopter(str(bl_path))
        if geste_commite:
            _git(racine, "add", ".autoport/backlog.yaml")
            _git(racine, "commit", "-q", "-m", "[autoport/supervisor] backlog", quand=t0 + 120)
    if geste_a_la_main:
        doc = B._read(str(bl_path))
        doc["items"].append(LS.adopted_item("owner-a-la-main", ticket()))
        B._atomic_write(str(bl_path), B._dump(doc))
    (ap / "reports" / IID / "report.txt").write_text("rien a signaler\n", encoding="utf-8")
    (ap / "reports" / IID / "FINDINGS.txt").write_text("AUCUN\n", encoding="utf-8")
    return depart


CAS = {
    "vert":            {},
    "geste":           {"geste": True},
    "geste_commite":   {"geste": True, "geste_commite": True},
    "neuf":            {"casse_par_l_item": True},
    "neuf_sous_geste": {"casse_par_l_item": True, "geste": True},
    "geste_a_la_main": {"geste_a_la_main": True},
}
VERITE_GESTE = ("geste", "geste_commite")
VERITE_NEUF = ("neuf", "neuf_sous_geste", "geste_a_la_main")
# APRES : (verdict, rouges neufs, rouges nes d'un geste)
ATTENDU = {
    "vert":            ("pass", 0, 0),
    "geste":           ("pass", 0, 1),
    "geste_commite":   ("pass", 0, 1),
    "neuf":            ("refuse", 1, 0),
    "neuf_sous_geste": ("refuse", 1, 0),
    "geste_a_la_main": ("refuse", 1, 0),
}


def impute(v: dict) -> bool:
    """IMPUTER, c'est refuser pour `neufs` en nommant le rouge : la definition, UNE fois."""
    return (v.get("verdict") == "refuse" and "neufs" in (v.get("refused_for") or [])
            and NODE in (v.get("unwaived_new_list") or []))


def bras(prefixe: str, SG, racine: Path) -> dict:
    res = {}
    for nom, semis in CAS.items():
        d = racine / (prefixe + "-" + nom)
        d.mkdir(parents=True, exist_ok=True)
        t = time.time()
        try:
            depart = semer(d, **semis)
            v = SG.judge(d, d / ".autoport", IID, record=False, since=depart)
        except Exception as exc:                                        # noqa: BLE001
            v = {"verdict": "exception:%s" % type(exc).__name__, "reason": str(exc)[:200]}
        res[nom] = v
        kv("%s_%s_verdict" % (prefixe, nom), v.get("verdict", "-"))
        kv("%s_%s_neufs" % (prefixe, nom), v.get("unwaived_new", "-"))
        kv("%s_%s_geste" % (prefixe, nom), v.get("owner_gesture", "absent"))
        kv("%s_%s_impute" % (prefixe, nom), 1 if impute(v) else 0)
        kv("%s_%s_refused_for" % (prefixe, nom), ",".join(v.get("refused_for") or []) or "-")
        kv("%s_%s_gesture_writes" % (prefixe, nom), v.get("gesture_writes", "absent"))
        kv("%s_%s_gesture_replay" % (prefixe, nom), ",".join(v.get("gesture_replay") or []) or "-")
        kv("%s_%s_secondes" % (prefixe, nom), round(time.time() - t, 1))
        shutil.rmtree(d, ignore_errors=True)
    return res


# ======================================================================== le cas reel ==========
REEL = {"item": "harness-invisible-item-comment-has-no-capture-boilerplate",
        "base": "a18246d727", "head": "3336c0fcbb", "since": 1790151625,
        "iid": "owner-attention-aux-profils-opus-5-5-bouscule-tout",
        "nodes": [".autoport/tests/harness/test_backlog.py::"
                  "test_every_open_item_of_the_real_backlog_has_a_prompt_on_disk",
                  ".autoport/tests/harness/test_backlog.py::"
                  "test_real_backlog_only_fails_lint_on_missing_gates"]}


def cas_reel(SG) -> dict:
    sha = {}
    for k in ("base", "head"):
        sha[k] = subprocess.run(["git", "-C", str(REPO), "rev-parse", "--verify", "-q",
                                 REEL[k] + "^{commit}"], capture_output=True, text=True,
                                timeout=30).stdout.strip()
    if not (sha["base"] and sha["head"]):
        kv("reel_ran", 0)
        kv("reel_error", "commits-introuvables")
        return {"ran": 0}
    item = LS.adopted_item(REEL["iid"], ticket())
    geste = [{"at": REEL["since"] + 1, "author": "linear_sync", "via": "adopt_owner_issues",
              "items": [{"id": REEL["iid"], "before": None, "after": item}]}]
    t = time.time()
    nes, info = SG.gesture_reds(str(REPO), str(AP), REEL["nodes"], sha["base"], sha["head"],
                                REEL["since"], gestes=geste)
    # CE QUE LE JUGE D'AVANT VOYAIT : les bras SANS geste sont les revisions telles que commitees
    # (le geste n'y est pas : `apply_gestures` n'y touche rien). Rouge ailleurs qu'aux deux = NEUF,
    # donc impute : c'est la faute du 23/09, reproduite sur ses propres commits.
    detail = {}
    for ligne in info.get("gesture_replay") or []:
        n, sep, arms = ligne.partition(":base-")          # le nodeid porte lui-meme des « : »
        if sep:
            detail[n] = dict(a.split("=", 1) for a in ("base-" + arms).split("/") if "=" in a)
    avant = [n for n in REEL["nodes"]
             if not (detail.get(n, {}).get("base-sans") == "failed"
                     and detail.get(n, {}).get("head-sans") == "failed")]
    kv("reel_ran", info.get("gesture_replay_ran", 0))
    kv("reel_error", info.get("gesture_replay_error", "-"))
    kv("reel_item", REEL["item"])
    kv("reel_base", sha["base"][:12])
    kv("reel_head", sha["head"][:12])
    kv("reel_nodes", len(REEL["nodes"]))
    kv("reel_replay", ",".join(info.get("gesture_replay") or []) or "-")
    kv("reel_classes_geste", len(nes))
    kv("reel_apres_impute", len(REEL["nodes"]) - len(nes))
    kv("reel_avant_impute", len(avant))
    kv("reel_secondes", round(time.time() - t, 1))
    return {"ran": info.get("gesture_replay_ran", 0), "nes": nes, "avant": avant}


# =================================================================== adoption et auteur =========
def adoption_et_auteur() -> dict:
    from lib.census.fake_backlog import Sandbox
    r = {}
    with Sandbox([]) as sb:
        n, iid = adopter(sb.path)
        it = sb.items().get(iid) or {}
        r["adopte"] = n
        r["scope"] = it.get("code_scope", "-")
        r["pris_brut"] = 1 if (B.load(sb.path).next_open() or {}).get("id") == iid else 0
        gestes = B.read_gestures(sb.path)
        r["journal_adoption"] = sum(1 for g in gestes if g.get("author") == "linear_sync"
                                    and g.get("via") == "adopt_owner_issues"
                                    and any(x.get("before") is None and x.get("id") == iid
                                            for x in g.get("items") or []))
        bl = B.load(sb.path)
        bl.set_status(iid, "open", prompt="prompts/%s.md" % iid)
        r["pris_avec_consigne"] = 1 if (B.load(sb.path).next_open() or {}).get("id") == iid else 0
        B.load(sb.path).set_scope(iid, "harnais", source="banc")
        r["pris_une_fois_cadre"] = 1 if (B.load(sb.path).next_open() or {}).get("id") == iid else 0
        # L'AUTEUR : la ligne de commande, hors essai puis sous un essai.
        cli = [sys.executable, str(AP / "autoport"), "--file", sb.path, "set", iid, "blocked",
               "--reason", "banc"]
        env = {k: v for k, v in os.environ.items() if k != "AUTOPORT_ATTEMPT_ID"}
        avant = len(B.read_gestures(sb.path))
        rc1 = subprocess.run(cli, env=env, capture_output=True, text=True, timeout=60).returncode
        apres_sup = B.read_gestures(sb.path)
        r["cli_rc"] = rc1
        r["cli_superviseur_journalise"] = sum(1 for g in apres_sup[avant:]
                                              if g.get("author") == "superviseur")
        env2 = dict(env, AUTOPORT_ATTEMPT_ID="%s@1#%d" % (IID, int(time.time())))
        cli2 = cli[:-3] + ["open"]
        rc2 = subprocess.run(cli2, env=env2, capture_output=True, text=True, timeout=60).returncode
        r["cli_worker_rc"] = rc2
        r["cli_worker_journalise"] = len(B.read_gestures(sb.path)) - len(apres_sup)
    # CONTROLE NEGATIF : un item `jeu` ordinaire, consigne posee, est PRIS — le saut n'est pas general.
    with Sandbox([{"id": "controle-jeu", "status": "open", "priority": 5, "code_scope": "jeu",
                   "prompt": "prompts/controle-jeu.md", "feature": "controle"}]) as sb:
        r["controle_jeu_pris"] = 1 if (B.load(sb.path).next_open() or {}).get("id") == "controle-jeu" else 0
    for k, v in r.items():
        kv("adopt_" + k, v)
    return r


def main() -> int:
    t_all = time.time()
    fautes: list[str] = []
    racine = Path(tempfile.mkdtemp(prefix="owner-gesture-banc-"))
    try:
        SG = charger(AP / "lib" / "suite_gate.py", "suite_gate_apres")
        commit_avant, blob = before_blob(".autoport/lib/suite_gate.py", MARQUEUR)
        kv("avant_commit", commit_avant[:12] or "-")
        kv("apres_marqueur_present", 1 if MARQUEUR in (AP / "lib" / "suite_gate.py").read_text() else 0)
        SG0 = None
        if blob:
            f = racine / "suite_gate_avant.py"
            f.write_text(blob, encoding="utf-8")
            SG0 = charger(f, "suite_gate_avant")
        apres = bras("apres", SG, racine)
        avant = bras("avant", SG0, racine) if SG0 is not None else {}
    finally:
        shutil.rmtree(racine, ignore_errors=True)

    # ---- banc : conformite du bras APRES, imputations, blanchiments, ablation ----
    ecarts = []
    for nom, (verdict, neufs, geste) in ATTENDU.items():
        v = apres.get(nom) or {}
        for cle, attendu, obtenu in (("verdict", verdict, v.get("verdict")),
                                     ("neufs", neufs, v.get("unwaived_new")),
                                     ("geste", geste, v.get("owner_gesture"))):
            if str(obtenu) != str(attendu):
                ecarts.append("%s.%s=%s!=%s" % (nom, cle, obtenu, attendu))
    apres_imputes = sum(1 for n in VERITE_GESTE if impute(apres.get(n) or {}))
    apres_blanchis = sum(1 for n in VERITE_NEUF if not impute(apres.get(n) or {}))
    avant_imputes = sum(1 for n in VERITE_GESTE if impute(avant.get(n) or {}))
    kv("banc_conformite_ecarts", len(ecarts))
    kv("banc_conformite_detail", ",".join(ecarts) or "-")
    kv("banc_apres_imputes", apres_imputes)
    kv("banc_apres_blanchis", apres_blanchis)
    kv("banc_avant_imputes", avant_imputes)
    t_banc = len(ecarts)
    if not avant:
        fautes.append("bras-avant-introuvable")
    elif avant_imputes < 1:
        fautes.append("ablation-vide-l-avant-n-impute-pas-le-geste")

    # ---- cas reel ----
    reel = cas_reel(SG)
    t_reel = 0
    if not reel.get("ran"):
        fautes.append("cas-reel-non-rejoue")
    else:
        t_reel = len(REEL["nodes"]) - len(reel.get("nes") or [])
        if len(reel.get("avant") or []) < 1:
            fautes.append("cas-reel-ne-reproduit-pas-l-imputation-d-avant")

    # ---- adoption et auteur ----
    ad = adoption_et_auteur()
    attendus_ad = {"adopte": 1, "scope": "a-cadrer", "pris_brut": 0, "journal_adoption": 1,
                   "pris_avec_consigne": 0, "pris_une_fois_cadre": 1, "cli_rc": 0,
                   "cli_superviseur_journalise": 1, "cli_worker_journalise": 0,
                   "controle_jeu_pris": 1}
    ad_ecarts = ["%s=%s!=%s" % (k, ad.get(k), v) for k, v in attendus_ad.items()
                 if str(ad.get(k)) != str(v)]
    kv("adopt_ecarts", len(ad_ecarts))
    kv("adopt_detail", ",".join(ad_ecarts) or "-")

    # ---- publication : le publicateur, pas le fichier ----
    cles = {l.split("=")[0] for l in SG.publish({})}
    manquantes = [k for k in ("suite_owner_gesture", "suite_owner_gesture_list",
                              "suite_gesture_writes", "suite_gesture_replay")
                  if k not in cles]
    kv("publie_manquantes", ",".join(manquantes) or "-")
    if manquantes:
        fautes.append("non-publie")

    juges = len(apres) + (len(REEL["nodes"]) if reel.get("ran") else 0)
    kv("owner_gesture_closures_judged", juges)
    kv("owner_gesture_seeds_gesture", len(VERITE_GESTE))
    kv("owner_gesture_seeds_new", len(VERITE_NEUF))
    if juges < 1:
        fautes.append("zero-sur-zero")
    # LE COMPTE : chaque imputation d'un geste sous le juge livre (banc + cas reel), chaque ecart a
    # la table (dont les blanchiments d'un rouge NEUF), chaque ecart d'adoption, chaque temoin muet.
    total = t_banc + t_reel + len(ad_ecarts) + len(fautes)
    kv("owner_gesture_misimputed_banc", apres_imputes)
    kv("owner_gesture_misimputed_reel", t_reel if reel.get("ran") else -1)
    kv("owner_gesture_misimputed_before", avant_imputes + len(reel.get("avant") or []))
    kv("owner_gesture_faults", "+".join(fautes) or "-")
    kv("owner_gesture_seconds", round(time.time() - t_all, 1))
    kv("owner_gesture_misimputed", total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
