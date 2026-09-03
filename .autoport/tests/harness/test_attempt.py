"""One attempt, end to end, against a fake `claude`.

The rule under test, owner-visible: **an attempt WE cut short is not the
worker's failure.** `_sig` used to set HALT and kill the child, then `run_phase`
carried on regardless — it ran the validator on an untouched tree, incremented
`retries`, appended a fingerprint and committed a WIP. 373 of 597 worker
sessions lasted under three minutes because of that, and items were blocked on
retries nobody had ever used (Gcine-cut: attempts 1 and 2, 56 s and 61 s, both
counted, both failing on a dirty golden the worker never touched).
"""
import json
import os
import signal
import subprocess
import textwrap
import threading

import pytest


def _git(root, *args):
    return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True)


@pytest.fixture()
def item_repo(orch, sandbox, monkeypatch):
    """A sandbox with a git repo, a prompt, a validator and a fake `claude`."""
    root = sandbox
    ap = orch.AUTOPORT_DIR
    (ap / "prompts").mkdir(parents=True, exist_ok=True)
    (ap / "prompts" / "item-demo.md").write_text("Fais la chose.\n")
    orch.GENERIC_VALIDATOR.write_text("#!/usr/bin/env bash\nexit ${VALIDATOR_RC:-1}\n")
    orch.GENERIC_VALIDATOR.chmod(0o755)

    _git(root, "init", "-q", "-b", "main")
    _git(root, "config", "user.email", "t@t")
    _git(root, "config", "user.name", "t")
    (root / "seed.txt").write_text("seed\n")
    # ignored exactly like the real repo ignores them: the point of the
    # watchdog test is the stamp list, not git's view of build output
    (root / ".gitignore").write_text("android/app/build/\n.autoport/tmp/\n")
    _git(root, "add", "seed.txt", ".gitignore")
    _git(root, "commit", "-qm", "seed")

    monkeypatch.setattr(orch, "build_instructions", lambda item, seq: "prompt\n")
    monkeypatch.setattr(orch, "READ_POLL_SEC", 0.2)
    return root


@pytest.fixture()
def prompt_only(orch, sandbox, monkeypatch):
    """Just enough to call the REAL build_instructions, with the contract and
    preflight modules stubbed out so no test ever writes in the real tree."""
    import sys
    import types
    (orch.AUTOPORT_DIR / "prompts").mkdir(parents=True, exist_ok=True)
    (orch.AUTOPORT_DIR / "prompts" / "item-demo.md").write_text("Fais la chose.\n")
    for name in ("directives", "preflight"):
        stub = types.ModuleType(name)          # no __spec__: reload() is refused,
        monkeypatch.setitem(sys.modules, name, stub)   # and the caller falls back
    return sandbox


def _fake_claude(orch, body: str) -> None:
    """Install a `claude` on PATH that emits `body` (a shell snippet)."""
    bindir = orch.AUTOPORT_DIR / "fakebin"
    bindir.mkdir(exist_ok=True)
    exe = bindir / "claude"
    exe.write_text("#!/usr/bin/env bash\ncat >/dev/null\n" + textwrap.dedent(body))
    exe.chmod(0o755)
    os.environ["PATH"] = f"{bindir}:{os.environ['PATH']}"


ITEM = {"id": "demo", "prompt": "prompts/item-demo.md", "feature": "la chose",
        "max_turns": 10, "max_retries": 6, "owner_verify": True}

_WORKS_THEN_EXITS = """
echo '{"type":"system","subtype":"init","session_id":"s","model":"fake"}'
echo '{"type":"assistant","message":{"usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"true"}}]}}'
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"duration_ms":10,"usage":{}}'
exit 0
"""

_WORKS_THEN_HANGS = """
echo '{"type":"system","subtype":"init","session_id":"s","model":"fake"}'
echo '{"type":"assistant","message":{"usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"true"}}]}}'
sleep 300
"""


def test_a_signal_does_not_burn_an_attempt(orch, item_repo, monkeypatch):
    _fake_claude(orch, _WORKS_THEN_HANGS)
    state = orch.load_state()

    threading.Timer(1.0, lambda: orch._sig(signal.SIGINT, None)).start()
    out = orch.run_attempt(dict(ITEM), state)

    assert out.kind == "interrupted"
    assert state["retries"].get("demo") is None, "a signal must not count an attempt"
    assert state["fingerprints"].get("demo") is None, "and must not fingerprint it"
    assert not list((orch.LOG_ROOT / "demo").glob("validator-*.txt")), \
        "the validator must not run on a tree we cut short"
    # the forensic log is still there, and numbered
    assert (orch.LOG_ROOT / "demo" / "attempt-001.jsonl").exists()


def test_a_scope_change_does_not_burn_an_attempt(orch, item_repo):
    _fake_claude(orch, _WORKS_THEN_HANGS)
    state = orch.load_state()
    orch.SCOPE_STAMP.write_text("0")

    def bump():
        orch.SCOPE_STAMP.write_text("1")
        os.utime(orch.SCOPE_STAMP, (2_000_000_000, 2_000_000_000))
    threading.Timer(1.0, bump).start()

    out = orch.run_attempt(dict(ITEM), state)
    assert out.kind == "interrupted"
    assert "périmètre" in out.reason
    assert state["retries"].get("demo") is None
    assert state["fingerprints"].get("demo") is None


def test_a_refusal_at_the_door_is_not_an_attempt_and_carries_the_reset_hour(orch, item_repo):
    _fake_claude(orch, """
        echo '{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","resetsAt":1779184200,"rateLimitType":"five_hour"}}'
        echo 'Claude AI usage limit reached' >&2
        exit 1
    """)
    state = orch.load_state()
    out = orch.run_attempt(dict(ITEM), state)

    assert out.kind == "no-start"
    assert out.resume_at == 1779184200, "we sleep until the hour the API returned"
    assert state["retries"].get("demo") is None
    assert state["fingerprints"].get("demo") is None
    assert any("usage limit" in l for l in out.stderr_tail), \
        "claude's stderr is the only account of a no-start; it must be kept"


def test_a_real_failure_is_counted_fingerprinted_and_leaves_a_handoff(orch, item_repo):
    _fake_claude(orch, _WORKS_THEN_EXITS)
    os.environ["VALIDATOR_RC"] = "1"
    orch.GENERIC_VALIDATOR.write_text(
        "#!/usr/bin/env bash\necho '[demo FAIL] flicker_episodes=4 attendu 0'\nexit 1\n")
    orch.GENERIC_VALIDATOR.chmod(0o755)
    (item_repo / "engine.cpp").write_text("int main(){}\n")   # the worker's work

    state = orch.load_state()
    out = orch.run_attempt(dict(ITEM), state)

    assert out.kind == "fail"
    assert state["retries"]["demo"] == 1
    assert len(state["fingerprints"]["demo"]) == 1
    hand = orch.handoff_path("demo")
    assert hand.exists(), "a failed attempt must leave a handoff for the next one"
    text = hand.read_text()
    assert len(text.splitlines()) <= orch.HANDOFF_MAX_LINES
    assert "flicker_episodes=4" in text
    assert "engine.cpp" in text


def test_the_handoff_replaces_the_validator_tail_in_the_next_prompt(orch, prompt_only):
    orch.handoff_path("demo").parent.mkdir(parents=True, exist_ok=True)
    orch.handoff_path("demo").write_text("# Handoff\n- établi : le compteur est à 4.\n")

    text = orch.build_instructions(dict(ITEM), 2)
    assert "le compteur est à 4" in text
    assert "handoff.md" in text
    assert "Validator output (last 4KB)" not in text
    assert "Previous attempt" not in text


def test_the_handoff_injection_is_capped(orch, prompt_only):
    p = orch.handoff_path("demo")
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("\n".join(f"ligne {i}" for i in range(200)))
    got = orch.read_handoff("demo")
    assert len(got.splitlines()) <= orch.HANDOFF_MAX_LINES + 1
    assert "tronqué" in got


def test_the_item_header_carries_the_owners_own_words(orch, item_repo):
    item = dict(ITEM, gate={"key": "flicker_episodes", "op": "==", "value": 0},
                owner_feedback=[{"date": "2026-09-03", "text": "bah non c'est toujours pété"}])
    head = orch._item_header(item, 3)
    assert "bah non c'est toujours pété" in head, \
        "the owner's words used to reach the worker through nothing at all"
    assert "flicker_episodes == 0" in head
    assert "essai 3" in head


def test_the_progress_watchdog_ignores_the_build_daemon(orch, item_repo):
    """The fingerprint used to include the APK and .autoport/tmp/, both rewritten
    by auto_build_apk.sh on its own schedule: an idle worker looked alive because
    a build finished next to it."""
    before = orch._progress_fingerprint("demo")
    tmp = orch.AUTOPORT_DIR / "tmp"
    tmp.mkdir(exist_ok=True)
    (tmp / "build-artifact").write_text("the daemon wrote this")
    apk = item_repo / "android/app/build/outputs/apk/jak1/debug"
    apk.mkdir(parents=True)
    (apk / "app-jak1-debug.apk").write_text("fresh apk")
    assert orch._progress_fingerprint("demo") == before, \
        "the daemon's artifacts must not read as the worker's progress"


def test_notes_and_handoff_count_as_progress(orch, item_repo):
    """A worker that reads and analyses for 45 minutes without touching the tree
    was killed 13 times. A written trace of thinking IS progress."""
    before = orch._progress_fingerprint("demo")
    notes = orch.REPORTS_DIR / "demo" / "notes"
    notes.mkdir(parents=True)
    (notes / "hypotheses.md").write_text("l'os 0 n'est jamais écrit")
    after_notes = orch._progress_fingerprint("demo")
    assert after_notes != before

    orch.handoff_path("demo").write_text("# Handoff\n")
    assert orch._progress_fingerprint("demo") != after_notes


def test_a_mid_run_api_refusal_is_not_the_workers_failure(orch, item_repo):
    """A quota refusal that lands after real work is still a quota refusal. It
    used to be counted as a failed attempt because the only 'not counted' path
    required ZERO tokens."""
    _fake_claude(orch, """
        echo '{"type":"system","subtype":"init","session_id":"s","model":"fake"}'
        echo '{"type":"assistant","message":{"usage":{"input_tokens":900,"output_tokens":80},"content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":"true"}}]}}'
        echo '{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","resetsAt":1779184200}}'
        exit 1
    """)
    state = orch.load_state()
    out = orch.run_attempt(dict(ITEM), state)

    assert out.kind == "no-start"
    assert out.resume_at == 1779184200
    assert state["retries"].get("demo") is None
    assert state["fingerprints"].get("demo") is None


def test_our_own_watchdog_kill_is_never_relabelled_an_infra_outage(orch, item_repo):
    """58 'storms' were logged, most of them exit 143 — our own SIGTERM."""
    orch.GENERIC_VALIDATOR.write_text("#!/usr/bin/env bash\necho '[demo FAIL] x'\nexit 1\n")
    orch.GENERIC_VALIDATOR.chmod(0o755)
    _fake_claude(orch, """
        echo '{"type":"system","subtype":"init","session_id":"s","model":"fake"}'
        echo '{"type":"assistant","message":{"usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":"cat orchestrator.py"}}]}}'
        echo '{"type":"user","message":{"content":[{"type":"tool_result","content":"529 529 529 overloaded overloaded"}]}}'
        echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"duration_ms":1,"usage":{}}'
        exit 143
    """)
    state = orch.load_state()
    out = orch.run_attempt(dict(ITEM), state)

    assert out.kind == "fail", "a tool output full of 529s is not an Anthropic outage"
    assert state["retries"]["demo"] == 1
