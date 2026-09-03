"""state.json — atomic, versioned, five keys, and an attempt number that never
goes backwards.

Two incidents are pinned here.

LOST UPDATE (2026-09-03 02:13). An orchestrator that had received a signal was
still running its validator at 02:15 while a new one started at 02:13:18 and
rewrote state.json at 02:13:19. The first run's verdict was never recorded. A
write now refuses a file whose version moved under it.

OVERWRITTEN LOGS. The attempt number was `retries + 1`, and one exemption reset
`retries` to 0 — so the next attempt was numbered 1 again and reopened
`attempt-01.jsonl` in "w". One item had 117 fingerprints and 18 attempt logs.
"""
import json

import pytest


def test_state_keeps_only_the_five_mechanical_keys(orch, sandbox):
    orch.STATE_PATH.write_text(json.dumps({
        "current_phase_idx": 109, "completed": ["a"], "blocked": ["b"],
        "parked": {"c": "why"}, "validator_passed": ["d"], "stuck_reasons": {},
        "supervisor_rollback": "may", "retries": {"x": 2},
    }))
    st = orch.load_state()
    assert set(st) == set(orch.STATE_KEYS)
    orch.save_state(st)
    on_disk = json.loads(orch.STATE_PATH.read_text())
    assert set(on_disk) == set(orch.STATE_KEYS)
    for gone in ("current_phase_idx", "completed", "parked", "validator_passed"):
        assert gone not in on_disk, f"{gone} lives in backlog.yaml now, not here"
    assert on_disk["retries"] == {"x": 2}


def test_save_state_bumps_the_version_and_is_atomic(orch, sandbox):
    st = orch.load_state()
    assert st["version"] == 0
    orch.save_state(st)
    assert st["version"] == 1
    assert json.loads(orch.STATE_PATH.read_text())["version"] == 1
    orch.save_state(st)
    assert json.loads(orch.STATE_PATH.read_text())["version"] == 2
    # no temporary file left behind
    assert not list(orch.STATE_PATH.parent.glob("state.json.tmp*"))


def test_save_state_refuses_a_version_that_moved_under_us(orch, sandbox):
    mine = orch.load_state()
    orch.save_state(mine)                       # version 1, mine

    other = orch.load_state()                   # a second orchestrator
    other["retries"]["theirs"] = 7
    orch.save_state(other)                      # version 2, on disk

    mine["retries"]["mine"] = 1
    with pytest.raises(orch.StateConflict):
        orch.save_state(mine)

    # the other run's work is INTACT — that is the whole point
    on_disk = json.loads(orch.STATE_PATH.read_text())
    assert on_disk["retries"] == {"theirs": 7}
    assert on_disk["version"] == 2


def test_attempt_number_never_goes_backwards(orch, sandbox):
    st = orch.load_state()
    seen = [orch.next_attempt_seq(st, "item-a") for _ in range(3)]
    assert seen == [1, 2, 3]

    # the exact regression: something resets the retry counter
    st["retries"]["item-a"] = 0
    assert orch.next_attempt_seq(st, "item-a") == 4

    # and it survives a reload from disk
    st2 = orch.load_state()
    assert orch.next_attempt_seq(st2, "item-a") == 5


def test_attempt_number_skips_an_existing_log(orch, sandbox):
    """Even a hand-edited state.json cannot make us overwrite a forensic log."""
    st = orch.load_state()
    d = orch.LOG_ROOT / "item-b"
    d.mkdir(parents=True)
    for n in (1, 2, 3):
        (d / f"attempt-{n:03d}.jsonl").write_text("{}\n")
    assert orch.next_attempt_seq(st, "item-b") == 4


def test_attempt_numbers_are_per_item(orch, sandbox):
    st = orch.load_state()
    assert orch.next_attempt_seq(st, "one") == 1
    assert orch.next_attempt_seq(st, "two") == 1
    assert orch.next_attempt_seq(st, "one") == 2


def test_the_legacy_statuses_are_backed_up_before_the_first_write(orch, sandbox):
    """`completed`, `parked`, `blocked`, `validator_passed` moved to backlog.yaml
    and tools/migrate_backlog.py reads them: the first write must not eat them."""
    legacy = {"current_phase_idx": 109, "completed": ["a", "b"],
              "parked": {"c": "en attente owner"}, "validator_passed": ["d"],
              "retries": {"a": 3}}
    orch.STATE_PATH.write_text(json.dumps(legacy))

    st = orch.load_state()
    backup = orch.STATE_PATH.with_name(orch.STATE_PATH.name + ".legacy")
    assert backup.exists()
    assert json.loads(backup.read_text()) == legacy

    orch.save_state(st)
    assert "completed" not in json.loads(orch.STATE_PATH.read_text())
    assert json.loads(backup.read_text())["completed"] == ["a", "b"]

    # a second load must not overwrite the backup with the already-trimmed file
    orch.load_state()
    assert json.loads(backup.read_text())["parked"] == {"c": "en attente owner"}
