#!/usr/bin/env python3
"""lib/suite_gate_selftest.py — LE BANC DE `harness-suite-must-be-a-close-gate`.

CE QU'IL FAIT. Il joue la VRAIE porte de fermeture — `orchestrator.close_gate` — sur des
depots JETABLES, dans les DEUX bras, avec une suite MINIATURE dont un test casse pour la MEME
raison que le 12/09 : une cle renommee en `_const`, le lecteur mis a jour, le test qui la cite
laisse en arriere.

LES SIX SEMIS, chacun dans son propre depot git jetable :

  vert                la suite passe                      -> LES DEUX bras ferment (le
                                                             CONTROLE A LAISSER : une porte
                                                             qui refuse un vert ne vaut rien)
  casse               un test rouge, aucune dispense       -> AVANT ferme, APRES REFUSE, et
                                                             la raison NOMME le test casse
  dispense_ancienne   rouge couvert par une entree du      -> APRES ferme : une dispense
                      registre DEJA commitee                  ecrite avant l'item tient
  dispense_propre     rouge couvert par une entree que     -> APRES REFUSE : un item ne se
                      L'ITEM COURANT vient d'ajouter          donne pas du vert tout seul
  ajout_non_nomme     suite VERTE, entree ajoutee au       -> APRES REFUSE : une dispense que
                      registre, rapport MUET                  personne ne lit est une
                                                             regression silencieuse
  ajout_nomme         la meme, NOMMEE dans le rapport      -> APRES ferme (le second CONTROLE
                                                             A LAISSER)

LE BRAS D'AVANT EST ANCRE PAR MARQUEUR, jamais lu a `HEAD:` : des le commit de ce chantier,
`HEAD` porte la porte et le temoin s'accuserait lui-meme. On remonte jusqu'au dernier commit ou
`CLOSE-GATE/suite` est ABSENT de `orchestrator.py`, et le commit retenu est PUBLIE.

LE COUT. La suite miniature compte trois tests et tourne en ~1 s : le banc mesure la DECISION
de la porte, pas la duree de la vraie suite. Celle-la est mesuree une fois, sur l'arbre livre,
par `lib/census/harness-suite-must-be-a-close-gate.sh`.

Sortie : des lignes `cle=valeur` sur stdout. Ce script ne juge rien et n'ecrit aucun champ de
proof.txt ; le recensement fait la somme.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve()
AP = HERE.parent.parent
REPO = AP.parent

MARQUEUR = "CLOSE-GATE/suite"
SANS_CODE = "Ne touche a aucun code du jeu. Ne desactive aucun test, ne remplit pas le registre."

CLE_NEUVE = "hdr_stretch_top_const"
CLE_VIEILLE = "hdr_stretch_top"

NODE_CASSE = ".autoport/tests/harness/test_petit.py::test_cle_publiee"
NODE_AILLEURS = ".autoport/tests/harness/test_petit.py::test_toujours_vert"

TEST_PETIT = '''"""Suite MINIATURE du banc : elle cite une cle publiee, comme les 44 tests du 12/09."""
from pathlib import Path

DONNEE = Path(__file__).resolve().parents[2] / "donnee.txt"


def test_cle_publiee():
    assert "%s=" % "{cle}" in DONNEE.read_text(encoding="utf-8")


def test_donnee_existe():
    assert DONNEE.exists()


def test_toujours_vert():
    assert 1 + 1 == 2
'''.replace("{cle}", CLE_NEUVE)


def kv(key, value):
    print("%s=%s" % (key, str(value).replace("\n", " ").replace(" ", "_")[:400] or "-"))


def charger(src: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def before_blob(rel: str, marker: str) -> tuple[str, str]:
    """Le premier commit, en remontant, dont `rel` ne porte PAS `marker`."""
    try:
        hist = subprocess.run(["git", "-C", str(REPO), "log", "--format=%H", "-n", "200",
                               "--", rel], capture_output=True, text=True,
                              timeout=60).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return "", ""
    for commit in hist:
        try:
            blob = subprocess.run(["git", "-C", str(REPO), "show", "%s:%s" % (commit, rel)],
                                  capture_output=True, text=True, timeout=60).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        if blob and marker not in blob:
            return commit, blob
    return "", ""


# ============================================================ les depots jetables ============
GIT_ENV = {**os.environ, "GIT_AUTHOR_NAME": "banc", "GIT_AUTHOR_EMAIL": "banc@local",
           "GIT_COMMITTER_NAME": "banc", "GIT_COMMITTER_EMAIL": "banc@local"}


def registre_yaml(entrees: list[tuple[str, str]]) -> str:
    if not entrees:
        return "attendus: []\n"
    out = ["attendus:"]
    for node, sig in entrees:
        out += ["  - nodeid: %s" % node,
                "    slug: banc-%s" % node.rsplit("::", 1)[1].replace("_", "-"),
                "    tranche: harnais",
                "    categorie: decision-owner",
                "    signature: %s" % sig]
    return "\n".join(out) + "\n"


def semer(racine: Path, iid: str, *, casse: bool, registre_base: list, registre_ajout: list,
          rapport: str) -> Path:
    """Un depot git jetable : la suite miniature, le registre COMMITE, puis le geste de l'item
    dans l'arbre de travail. Ce qui est commite est la BASE ; ce qui est ajoute apres est
    impute a l'item courant, exactement comme sur l'arbre livre."""
    root = racine
    ap = root / ".autoport"
    (ap / "tests" / "harness").mkdir(parents=True, exist_ok=True)
    (ap / "logs").mkdir(parents=True, exist_ok=True)
    (ap / "reports" / iid).mkdir(parents=True, exist_ok=True)
    (ap / "tests" / "harness" / "test_petit.py").write_text(TEST_PETIT, encoding="utf-8")
    (ap / "donnee.txt").write_text("%s=1\n" % CLE_NEUVE, encoding="utf-8")
    (ap / "tests" / "harness" / "ECHECS-ATTENDUS.yaml").write_text(
        registre_yaml(registre_base), encoding="utf-8")
    import yaml
    (ap / "backlog.yaml").write_text(yaml.safe_dump(
        {"version": 1, "items": [{"id": iid, "status": "in-progress", "priority": 1,
                                  "game": "jak1", "device": False, "owner_test": False,
                                  "owner_verify": False, "no_code": True,
                                  "feature": "banc de la porte de suite",
                                  "out_of_scope": SANS_CODE}]},
        allow_unicode=True, sort_keys=False), encoding="utf-8")
    subprocess.run(["git", "init", "-q", "."], cwd=root, capture_output=True, timeout=60)
    subprocess.run(["git", "add", "-A"], cwd=root, capture_output=True, timeout=60)
    subprocess.run(["git", "commit", "-q", "-m", "base du banc"], cwd=root, env=GIT_ENV,
                   capture_output=True, timeout=60)
    # ---- LE GESTE DE L'ITEM COURANT, dans l'arbre de travail, APRES la base ----
    if casse:
        (ap / "donnee.txt").write_text("%s=1\n" % CLE_VIEILLE, encoding="utf-8")
    if registre_ajout:
        (ap / "tests" / "harness" / "ECHECS-ATTENDUS.yaml").write_text(
            registre_yaml(registre_base + registre_ajout), encoding="utf-8")
    (ap / "reports" / iid / "report.txt").write_text(rapport, encoding="utf-8")
    return root


CAS = {
    # nom               casse  registre_base                registre_ajout             rapport
    "vert":            (False, [],                          [],                        "rien a signaler"),
    "casse":           (True,  [],                          [],                        "rien a signaler"),
    "dispense_ancienne": (True, [(NODE_CASSE, CLE_NEUVE)],   [],                        "rien a signaler"),
    "dispense_propre": (True,  [],                          [(NODE_CASSE, CLE_NEUVE)],
                        "j'ai inscrit " + NODE_CASSE + " au registre, raison : banc"),
    "ajout_non_nomme": (False, [],                          [(NODE_AILLEURS, "banc")], "rien a signaler"),
    "ajout_nomme":     (False, [],                          [(NODE_AILLEURS, "banc")],
                        "j'ai inscrit " + NODE_AILLEURS + " au registre, raison : banc"),
}


def axe(prefixe: str, racine: Path, O, iid: str) -> None:
    """Joue la VRAIE porte sur les six semis, avec le module d'orchestrateur du bras."""
    for nom, (casse, base, ajout, rapport) in CAS.items():
        d = racine / (prefixe + "-" + nom)
        d.mkdir(parents=True, exist_ok=True)
        semer(d, iid, casse=casse, registre_base=base, registre_ajout=ajout, rapport=rapport)
        O.REPO_ROOT = d
        O.AUTOPORT_DIR = d / ".autoport"
        O.BACKLOG_PATH = d / ".autoport" / "backlog.yaml"
        O.REPORTS_DIR = d / ".autoport" / "reports"
        O.OWNER_OK_DIR = d / ".autoport" / "owner-ok"
        O.log = lambda *a, **k: None
        item = {"id": iid, "status": "in-progress", "device": False, "owner_test": False,
                "owner_verify": False, "no_code": True, "out_of_scope": SANS_CODE,
                "feature": "banc de la porte de suite"}
        t0 = time.time()
        try:
            st, raison = O.close_gate(item, [], validator_ok=True, since=time.time())
        except Exception as exc:                                        # noqa: BLE001
            st, raison = "exception:%s" % type(exc).__name__, str(exc)
        raison = raison or "-"
        kv("%s_%s_statut" % (prefixe, nom), st)
        kv("%s_%s_suite" % (prefixe, nom), 1 if "CLOSE-GATE/suite" in raison else 0)
        kv("%s_%s_nomme_le_test" % (prefixe, nom), 1 if NODE_CASSE in raison else 0)
        kv("%s_%s_dit_propre" % (prefixe, nom), 1 if "ajoutees par CET item" in raison else 0)
        kv("%s_%s_dit_non_nomme" % (prefixe, nom), 1 if "NOMMEES nulle part" in raison else 0)
        kv("%s_%s_secondes" % (prefixe, nom), round(time.time() - t0, 1))
        kv("%s_%s_raison" % (prefixe, nom), raison[:220])
        shutil.rmtree(d, ignore_errors=True)
    kv("%s_ran" % prefixe, 1)


# ================================================= le juge, appele DIRECTEMENT ===============
def axe_juge(racine: Path, iid: str) -> None:
    """Les memes semis, mais lus par `lib/suite_gate.py` lui-meme : les GRANDEURS, pas
    seulement la decision. Une porte qui refuse sans publier ne se verifie pas."""
    sys.path.insert(0, str(AP / "lib"))
    import suite_gate as SG
    for nom, (casse, base, ajout, rapport) in CAS.items():
        d = racine / ("juge-" + nom)
        d.mkdir(parents=True, exist_ok=True)
        semer(d, iid, casse=casse, registre_base=base, registre_ajout=ajout, rapport=rapport)
        v = SG.judge(d, d / ".autoport", iid, record=False)
        for cle in ("verdict", "collected", "failed", "unwaived", "self_added",
                    "self_added_named", "waived_effective", "registry_entries", "rc",
                    "report_read", "base_ref", "duration_s", "budget_s", "over_budget",
                    "timed_out", "registry_sha"):
            kv("jg_%s_%s" % (nom, cle), v.get(cle, "-"))
        kv("jg_%s_unwaived_list" % nom, ",".join(v.get("unwaived_list") or []) or "-")
        shutil.rmtree(d, ignore_errors=True)
    # LE BUDGET, ABLATE SUR LE MEME SEMIS. Un budget que la suite miniature ne depasse jamais
    # ne prouverait pas que le depassement est DIT : on le rabaisse a zero, meme course, meme
    # arbre. Les deux bras sont publies — le haut est le CONTROLE A LAISSER.
    d = racine / "juge-budget"
    d.mkdir(parents=True, exist_ok=True)
    semer(d, iid, casse=False, registre_base=[], registre_ajout=[], rapport="rien a signaler")
    haut = SG.judge(d, d / ".autoport", iid, budget_s=3600, record=False)
    bas = SG.judge(d, d / ".autoport", iid, budget_s=0, record=False)
    kv("jg_budget_haut_over", haut.get("over_budget", "-"))
    kv("jg_budget_haut_verdict", haut.get("verdict", "-"))
    kv("jg_budget_bas_over", bas.get("over_budget", "-"))
    kv("jg_budget_bas_verdict", bas.get("verdict", "-"))
    kv("jg_budget_bas_secondes", bas.get("duration_s", "-"))
    shutil.rmtree(d, ignore_errors=True)
    # LE PLAFOND DUR, lui, REFUSE : une suite tuee n'a rien prouve. Le stimulus est une suite
    # qui PEND vraiment — un plafond abaisse sous une suite qui rend la main en 0,2 s ne se
    # declencherait jamais, et le temoin serait un decor.
    d = racine / "juge-plafond"
    d.mkdir(parents=True, exist_ok=True)
    semer(d, iid, casse=False, registre_base=[], registre_ajout=[], rapport="rien a signaler")
    (d / ".autoport" / "tests" / "harness" / "test_petit.py").write_text(
        "import time\n\n\ndef test_qui_pend():\n    time.sleep(120)\n", encoding="utf-8")
    tue = SG.judge(d, d / ".autoport", iid, timeout_s=3, record=False)
    kv("jg_plafond_timed_out", tue.get("timed_out", "-"))
    kv("jg_plafond_verdict", tue.get("verdict", "-"))
    kv("jg_plafond_collected", tue.get("collected", "-"))
    kv("jg_plafond_secondes", tue.get("duration_s", "-"))
    shutil.rmtree(d, ignore_errors=True)
    kv("jg_ran", 1)


# ====================================================== les temoins de source ================
def temoins_source(blob_avant: str) -> None:
    orch = (AP / "orchestrator.py").read_text(encoding="utf-8")
    # LA MESURE DU known_cause, REJOUEE : `grep -n pytest orchestrator.py validators/` ne
    # rendait RIEN. C'est ca, le defaut, et c'est ca qu'on mesure des deux cotes.
    val = ""
    for f in sorted((AP / "validators").glob("*.sh")):
        val += f.read_text(encoding="utf-8", errors="replace")
    kv("src_pytest_orch_avant", blob_avant.count("pytest") if blob_avant else -1)
    kv("src_pytest_orch_vivant", orch.count("pytest") + orch.count("suite_gate"))
    kv("src_suite_gate_appels", orch.count("suite_gate.judge("))
    kv("src_import_suite_gate", orch.count("from lib import suite_gate"))
    kv("src_marqueur_vivant", 1 if MARQUEUR in orch else 0)
    kv("src_marqueur_avant", 0 if (blob_avant and MARQUEUR not in blob_avant) else 1)
    kv("src_validators_pytest", val.count("pytest"))
    # AUCUN RECHARGEMENT NEUF : `harness-reload-must-not-kill-the-loop` publie « trois sites
    # dans l'orchestrateur ». Ce chantier ne doit pas lui faire perdre son compte.
    kv("src_reload_sites_orch", orch.count("safe_reload.reload("))
    kv("src_reload_bruts_orch", orch.count("importlib.reload("))
    # HORS PERIMETRE : le jeu n'est pas touche.
    r = subprocess.run(["git", "-C", str(REPO), "status", "--porcelain", "--",
                        "game/", "common/", "android/", "goal_src/", "goalc/"],
                       capture_output=True, text=True, timeout=120)
    sales = [x[3:] for x in r.stdout.splitlines() if x.strip()]
    kv("src_engine_dirty", len(sales))
    kv("src_engine_dirty_list", ",".join(sales[:12]) or "-")
    for rel in ("lib/suite_gate.py", "lib/suite_gate_selftest.py",
                "lib/census/harness-suite-must-be-a-close-gate.sh",
                "tests/harness/ECHECS-ATTENDUS.yaml"):
        try:
            h = hashlib.sha256((AP / rel).read_bytes()).hexdigest()[:16]
        except OSError:
            h = "-"
        kv("sha_" + rel.replace("/", "_").replace(".", "_").replace("-", "_"), h)


def main() -> int:
    iid = "zzz-banc-suite-gate"
    root = Path(tempfile.mkdtemp(prefix="suite-gate-banc-"))
    try:
        commit, blob = before_blob(".autoport/orchestrator.py", MARQUEUR)
        kv("before_commit", commit[:12] or "-")
        kv("before_marqueur_absent", 1 if (blob and MARQUEUR not in blob) else 0)
        temoins_source(blob)

        sys.path.insert(0, str(AP))
        sys.path.insert(0, str(AP / "lib"))

        O_neuf = charger(AP / "orchestrator.py", "orch_neuf_sg")
        O_neuf.log = lambda *a, **k: None
        axe("apres", root, O_neuf, iid)

        if blob:
            vieux = root / "vieux_orchestrator.py"
            vieux.write_text(blob, encoding="utf-8")
            O_vieux = charger(vieux, "orch_vieux_sg")
            O_vieux.log = lambda *a, **k: None
            axe("avant", root, O_vieux, iid)

        axe_juge(root, iid)
        return 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
