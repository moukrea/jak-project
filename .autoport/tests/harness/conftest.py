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
