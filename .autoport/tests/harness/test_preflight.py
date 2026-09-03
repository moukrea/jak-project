"""PREFLIGHT — every check must produce (sev, code, message) TRIPLES.

This file exists because of a four-day outage nobody noticed. One check
`return`ed a 2-tuple where the nine others `yield`ed triples; `run()` did
`extend`, which appended its two STRINGS as two findings, and `prompt_block`
raised `ValueError: not enough values to unpack (expected 3, got 2)`. The
orchestrator swallowed that exception, so from 2026-08-30 to 2026-09-03 every
attempt logged `preflight unavailable` (278 occurrences) and not one finding
ever reached a worker or a supervisor.

The shape of a finding is now tested, so the same bug cannot come back silently.
"""
import preflight


def _is_triple(x):
    return isinstance(x, tuple) and len(x) == 3 and all(isinstance(p, str) for p in x)


def test_every_check_produces_triples():
    """The regression that killed the module: run each check for real."""
    assert preflight.CHECKS, "preflight has no checks left"
    for fn in preflight.CHECKS:
        args = ("an-item-that-does-not-exist",) if fn.__code__.co_argcount else ()
        produced = list(fn(*args) or ())
        for item in produced:
            assert _is_triple(item), (
                f"{fn.__name__} produced {item!r}; a check YIELDS (sev, code, msg) "
                f"triples of strings and never returns a tuple")


def test_every_check_is_a_generator():
    """A check that `return`s cannot be extended into the finding list safely."""
    import inspect
    for fn in preflight.CHECKS:
        assert inspect.isgeneratorfunction(fn), (
            f"{fn.__name__} is not a generator: it must `yield` its findings")


def test_run_returns_only_triples():
    for item in preflight.run("an-item-that-does-not-exist"):
        assert _is_triple(item)


def test_a_malformed_check_becomes_a_finding_not_a_crash(monkeypatch):
    """The exact B1 shape: a check that returns a 2-tuple."""
    def broken_check():
        return ("ok", "everything is fine")          # noqa: the bug, on purpose
    monkeypatch.setattr(preflight, "CHECKS", [broken_check])
    findings = preflight.run()
    assert findings, "a malformed check must be reported, not silently dropped"
    assert all(_is_triple(f) for f in findings)
    assert any(f[1] == "PREFLIGHT-BROKEN" for f in findings)
    # and the formatting site, which is where the ValueError used to be raised
    preflight.prompt_block()


def test_a_raising_check_does_not_break_the_run(monkeypatch):
    def explodes():
        raise RuntimeError("boom")
        yield  # pragma: no cover
    monkeypatch.setattr(preflight, "CHECKS", [explodes])
    findings = preflight.run()
    assert [f[1] for f in findings] == ["PREFLIGHT-ERR"]


def test_prompt_is_capped_and_overflow_is_kept(monkeypatch):
    """HARD CAP: at most 5 findings in the prompt, the rest go to the log."""
    n = preflight.MAX_PROMPT_FINDINGS + 4

    def many():
        for i in range(n):
            yield ("WARN", "SELF-KILL", f"finding {i}")
    monkeypatch.setattr(preflight, "CHECKS", [many])
    injected, overflow, sup = preflight.prompt_findings()
    assert len(injected) == preflight.MAX_PROMPT_FINDINGS
    assert len(overflow) == n - preflight.MAX_PROMPT_FINDINGS
    assert sup == []
    block = preflight.prompt_block()
    assert block.count("* **") == preflight.MAX_PROMPT_FINDINGS
    assert "au-delà du plafond" in block


def test_blockers_are_injected_before_warnings(monkeypatch):
    def mixed():
        for i in range(preflight.MAX_PROMPT_FINDINGS):
            yield ("WARN", "SELF-KILL", f"warn {i}")
        yield ("BLOCKER", "GD-LINK", "the blocker")
    monkeypatch.setattr(preflight, "CHECKS", [mixed])
    injected, _overflow, _sup = preflight.prompt_findings()
    assert injected[0][0] == "BLOCKER", "a BLOCKER must never be dropped by the cap"


def test_module_is_reduced_to_the_four_useful_checks():
    """The two removed checks produced 145 of 147 findings, or a permanent
    BLOCKER over a moved capital letter."""
    names = {fn.__name__ for fn in preflight.CHECKS}
    assert names == {
        "check_goal_objects_linked",     # GD-LINK
        "check_self_matching_kills",     # SELF-KILL
        "check_device_prop_leak",        # DEVICE-PROP-LEAK
        "check_report_not_stale",        # REPORT-STALE
    }
    assert not hasattr(preflight, "check_metric_frame_declared")
    assert not hasattr(preflight, "check_guards_still_installed")


def test_preflight_never_runs_a_device_or_a_build():
    """The module's own contract: cheap, no adb, under a second."""
    src = (preflight.__file__ or "")
    text = open(src, encoding="utf-8").read()
    body = text.split('"""', 2)[-1]          # skip the module docstring
    for forbidden in ("adb", "gradle", "ninja", "cmake", "shield_guard"):
        assert forbidden not in body, (
            f"preflight must not reach for {forbidden}: it runs before EVERY "
            f"attempt and must stay under a second")
