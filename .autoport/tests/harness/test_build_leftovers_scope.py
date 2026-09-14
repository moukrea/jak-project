"""Scope diagnostics must leave the gate's existing authority unchanged."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BEFORE = "30f3a9b540881303d31f3b93862275ada159fcdc"
spec = importlib.util.spec_from_file_location(
    "build_leftovers_scope_checks", ROOT / ".autoport/lib/build_leftovers_scope_checks.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


def test_scope_authority_and_legacy_api_unchanged():
    before = checks._scope_module(checks._read(ROOT, ".autoport/lib/gate_verdict.py", BEFORE))
    after = checks._scope_module(checks._read(ROOT, ".autoport/lib/gate_verdict.py", None))
    for scope in (None, "engine", "harness", "none", "jeu", "inconnu", ""):
        for flag in (False, True):
            for prose in ("", "Ne touche à aucun code du jeu.", "Documentation seulement."):
                item = dict(code_scope=scope, no_code=flag, out_of_scope=prose)
                assert after.scope_decision(item) == before.scope_decision(item)
                assert after.code_free_item(item) == before.code_free_item(item)


def test_contradictions_count_explicit_engine_even_with_legacy_flag():
    module = checks._scope_module(checks._read(ROOT, ".autoport/lib/gate_verdict.py", None))
    result = module.scope_census([
        {"id": "conflict", "code_scope": "engine", "no_code": True,
         "out_of_scope": "Ne touche à aucun code du jeu."},
        {"id": "consistent", "code_scope": "harness", "out_of_scope": "Aucun code moteur."},
        {"id": "silent", "code_scope": "engine"},
        {"id": "fallback", "out_of_scope": "Aucun code moteur."},
        {"id": "bad", "code_scope": "invalid", "out_of_scope": "Aucun code moteur."},
        None,
    ])
    assert result["contradictions_count"] == 1
    assert [x["id"] for x in result["contradictions"]] == ["conflict"]
    assert result["explicite"] == ["conflict", "consistent", "silent"]
    assert result["devine"] == ["fallback", "bad"]


def test_same_detector_reproduces_before_and_absent_after():
    before, after = checks.run_checks(ROOT, BEFORE), checks.run_checks(ROOT)
    for point in ("point_1", "point_2", "point_8"):
        assert before[point]["defects"] == 1
        assert after[point]["defects"] == 0
    # No new GUARD enforcement is claimed by the documentation correction.
    assert not before["point_8"]["guard_detected"]
    assert not after["point_8"]["guard_detected"]
