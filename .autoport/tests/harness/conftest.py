"""Fixtures for the harness tests.

RULE: no test touches the real `state.json`, the real `backlog.yaml`, the real
logs or the real repository. Every test that writes runs inside `tmp_path`, and
the `sandbox` fixture repoints the orchestrator's module-level paths at it.
"""
import os
import sys
from pathlib import Path

import pytest

AUTOPORT = Path(__file__).resolve().parents[2]
LIB = AUTOPORT / "lib"

for p in (str(AUTOPORT), str(LIB)):
    if p not in sys.path:
        sys.path.insert(0, p)

# ================= L'ENVIRONNEMENT DU BANC EST ASSAINI ICI, AVANT TOUTE COLLECTE =============
# harness-test-bench-does-not-inherit-the-worker-env, 2026-09-14. Le banc heritait TOUT
# l'environnement de qui le lance : lance depuis une session de worker, `AUTOPORT_ATTEMPT_ID`
# etait pose, `validators/generic.sh` exigeait alors `proof_attempt_id=` dans la preuve
# synthetique que `test_proof.py` n'ecrit pas, et LE CONTROLE POSITIF du banc rougissait. Un
# test qui change de verdict selon qui le lance mesure son lanceur.
#
# CE POINT-CI EST LE POINT DE PRODUCTION. `conftest.py` est importe avant tout module de test :
# les vingt sites qui font `dict(os.environ, ...)` heritent donc d'un environnement deja propre,
# sans avoir a etre touches, et le vingt-et-unieme naitra propre. La liste blanche, le bras
# d'ablation et ce qui a ete retire vivent dans `bench_env.py`, qui est le SEUL a le savoir.
# MARQUEUR: banc-env-maitrise-2026-09-14  (ancre du bras d'AVANT, lib/ablation_anchor.sh)
BANC = Path(__file__).resolve().parent
if str(BANC) not in sys.path:
    sys.path.insert(0, str(BANC))

import bench_env  # noqa: E402

BENCH_ENV = bench_env.install()


@pytest.fixture(autouse=True)
def _environ_propre():
    """L'ENVIRONNEMENT MAITRISE LE RESTE D'UN TEST AU SUIVANT.

    `bench_env.install()` assainit l'environnement UNE fois, a la collecte. Il ne dit rien de
    ce que le banc se fait a LUI-MEME ensuite, et le banc s'en faisait deux (recensement du
    14/09, `grep 'os.environ[...] ='` sur la suite, 2 sites) :

      * `test_attempt.py:143` posait `os.environ["VALIDATOR_RC"]="1"` a nu. La variable
        survivait a son test et etait encore lisible dans TOUS les suivants — mesure : la
        sonde `test_un_sous_processus_du_banc_ne_voit_que_la_liste_blanche` la voyait dans un
        sous-processus, `['VALIDATOR_RC']`, alors qu'aucun parent ne l'avait posee
        (`sonde_du_parent=0`). Elle y est morte : le validateur que ce test ecrit code
        `exit 1` EN DUR et ne lit jamais cette variable.
      * `_fake_claude()` prepend son `fakebin` a `PATH` A CHAQUE APPEL, sans jamais le
        retirer : une dizaine d'entrees empilees pointant sur des `tmp_path` deja effaces.

    LE POINT DE PRODUCTION, ENCORE (DIRECTIVES/non-destruction). Reparer les deux sites les
    laisse renaitre au troisieme, et il faudrait relire toute la suite pour savoir ce que
    l'environnement porte a un instant donne. On PHOTOGRAPHIE avant chaque test et on RESTITUE
    apres : les deux sites sont corriges sans etre touches, le troisieme naitra corrige, et il
    n'y a qu'UN endroit a lire. `monkeypatch.setenv` fait deja cela pour qui y pense ; ceci le
    fait pour qui n'y pense pas.

    ON RESTITUE, ON NE SOUSTRAIT PAS : `os.environ.clear()` puis `update()` remet aussi les
    variables qu'un test aurait SUPPRIMEES. Comparer des noms laisserait passer une valeur
    changee sous un nom conserve.

    SOUS LE BRAS D'ABLATION, CETTE GARDE NE TOURNE PAS. « OFF doit EGALER l'absence » : le bras
    d'avant doit rendre le banc tel qu'il etait, pollution comprise, sinon le cout d'AVANT
    qu'on publie n'est pas celui qu'on a paye.
    """
    if BENCH_ENV["mode"] != "maitrise":
        yield
        return
    photo = dict(os.environ)
    yield
    os.environ.clear()
    os.environ.update(photo)


@pytest.fixture(autouse=True)
def _module_cache_propre():
    """`backlog` ne doit JAMAIS survivre d'un test au suivant.

    Certains tests deposent un FAUX `backlog.py` dans le lib de leur bac a sable. Il reste
    ensuite dans `sys.modules`, et le `importlib.reload()` de `load_backlog()` re-execute ce
    faux module dans le test SUIVANT — qui echoue alors sur une variable d'environnement du
    test precedent. Symptome observe le 2026-09-03 : trois tests verts isoles, rouges dans la
    suite, avec un `KeyError` qui ne nommait aucun des deux.

    Purger `sys.modules` ne suffit pas : les tests qui deposent ce faux module inserent AUSSI
    le `lib` de leur bac a sable dans `sys.path`, et cette entree survit au test. L'import
    suivant retrouve donc le faux fichier SUR LE DISQUE. On restaure les deux.
    """
    chemin = list(sys.path)
    sys.modules.pop("backlog", None)
    yield
    sys.modules.pop("backlog", None)
    sys.path[:] = chemin


@pytest.fixture()
def orch():
    import orchestrator
    return orchestrator


@pytest.fixture()
def sandbox(orch, tmp_path, monkeypatch):
    """Point every path the orchestrator writes to at a throwaway directory."""
    root = tmp_path / "repo"
    ap = root / ".autoport"
    for d in ("logs", "reports", "owner-ok", "validators", "acquis-empty"):
        (ap / d).mkdir(parents=True, exist_ok=True)

    monkeypatch.setattr(orch, "REPO_ROOT", root)
    monkeypatch.setattr(orch, "AUTOPORT_DIR", ap)
    monkeypatch.setattr(orch, "STATE_PATH", ap / "state.json")
    monkeypatch.setattr(orch, "BACKLOG_PATH", ap / "backlog.yaml")
    monkeypatch.setattr(orch, "BACKLOG_LIB", ap / "lib" / "backlog.py")
    monkeypatch.setattr(orch, "LOG_ROOT", ap / "logs")
    monkeypatch.setattr(orch, "REPORTS_DIR", ap / "reports")
    monkeypatch.setattr(orch, "OWNER_OK_DIR", ap / "owner-ok")
    monkeypatch.setattr(orch, "SCOPE_STAMP", ap / ".scope_stamp")
    # `run_attempt` RELIT le profil a chaque essai (JAK-265, 23/09) : sans copie, chaque
    # banc lisait le VRAI model-profiles.json, essais croises du jour compris, et un test
    # qui posait `orch.MODEL` voyait sa valeur ecrasee par le fichier.
    profil = tmp_path / "model-profiles.json"   # HORS du depot simule : jamais commite
    profil.write_text(orch._PROFILE_PATH.read_text())
    monkeypatch.setattr(orch, "_PROFILE_PATH", profil)
    monkeypatch.setattr(orch, "GENERIC_VALIDATOR", ap / "validators" / "generic.sh")
    monkeypatch.setattr(orch, "SHIELD_GUARD", ap / "shield_guard.sh")
    monkeypatch.setattr(orch, "HALT", False)
    return root
