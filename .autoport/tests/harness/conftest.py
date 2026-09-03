"""Fixtures for the harness tests.

RULE: no test touches the real `state.json`, the real `backlog.yaml`, the real
logs or the real repository. Every test that writes runs inside `tmp_path`, and
the `sandbox` fixture repoints the orchestrator's module-level paths at it.
"""
import sys
from pathlib import Path

import pytest

AUTOPORT = Path(__file__).resolve().parents[2]
LIB = AUTOPORT / "lib"

for p in (str(AUTOPORT), str(LIB)):
    if p not in sys.path:
        sys.path.insert(0, p)


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
    monkeypatch.setattr(orch, "GENERIC_VALIDATOR", ap / "validators" / "generic.sh")
    monkeypatch.setattr(orch, "SHIELD_GUARD", ap / "shield_guard.sh")
    monkeypatch.setattr(orch, "HALT", False)
    return root
