"""Choosing the work: `backlog.next_open()`, and nothing else.

The cursor it replaces was `current_phase_idx`, a POSITION in a YAML list that
the supervisor edited while the orchestrator ran. The same index meant Gcine-cut
at 18:18 and Gcutscene-npc-flicker-2 at 02:13 the same night, because five items
had been inserted at indices 109-113 in between.

`lib/backlog.py` belongs to another workstream. These tests run against a fake
that implements the API documented in INTERFACES-2026-09-03.md §5 — so they also
serve as the executable statement of what this orchestrator expects from it.
"""
import sys
import textwrap

import pytest
import yaml

FAKE_BACKLOG = '''
"""Reference stand-in for lib/backlog.py (INTERFACES-2026-09-03.md §5)."""
import os
import pathlib
import yaml

PATH = pathlib.Path(os.environ["FAKE_BACKLOG_PATH"])


class Backlog:
    def __init__(self, data):
        self._data = data

    @property
    def items(self):
        return self._data.get("items", [])

    def get(self, item_id):
        for it in self.items:
            if it.get("id") == item_id:
                return it
        return None

    def next_open(self):
        """First `open` item, by priority, whose dependencies are all validated."""
        done = {i["id"] for i in self.items if i.get("status") == "validated"}
        cands = [i for i in self.items if i.get("status") == "open"
                 and all(d in done for d in (i.get("depends_on") or []))]
        cands.sort(key=lambda i: (i.get("priority", 1000), self.items.index(i)))
        return cands[0] if cands else None

    def set_status(self, item_id, status, **fields):
        with open(str(PATH) + ".calls", "a") as fh:      # trace pour les tests
            fh.write(item_id + " " + status + chr(10))
        data = yaml.safe_load(PATH.read_text())          # relit avant d'ecrire
        for it in data.get("items", []):
            if it.get("id") == item_id:
                it["status"] = status
                it.update(fields)
        tmp = PATH.with_suffix(".tmp")
        tmp.write_text(yaml.safe_dump(data, allow_unicode=True))
        os.replace(tmp, PATH)
        self._data = data


def load(path=None):
    return Backlog(yaml.safe_load(pathlib.Path(path or PATH).read_text()))
'''


def _items(*specs):
    out = []
    for i, s in enumerate(specs):
        it = {"id": s["id"], "status": s.get("status", "open"),
              "priority": s.get("priority", 10 + i),
              "feature": s.get("feature", s["id"]),
              "prompt": "prompts/item-%s.md" % s["id"],
              "max_turns": 5, "max_retries": s.get("max_retries", 6),
              "depends_on": s.get("depends_on", [])}
        if "owner_ok" in s:
            it["owner_ok"] = s["owner_ok"]
        out.append(it)
    return out


@pytest.fixture()
def fake_backlog(orch, sandbox, monkeypatch):
    lib = orch.AUTOPORT_DIR / "lib"
    lib.mkdir(parents=True, exist_ok=True)
    (lib / "backlog.py").write_text(textwrap.dedent(FAKE_BACKLOG))
    monkeypatch.setenv("FAKE_BACKLOG_PATH", str(orch.BACKLOG_PATH))
    monkeypatch.delitem(sys.modules, "backlog", raising=False)

    def write(items):
        orch.BACKLOG_PATH.write_text(
            yaml.safe_dump({"version": 1, "items": items}, allow_unicode=True))
    return write


def test_the_first_open_item_without_an_open_dependency_is_taken(orch, fake_backlog):
    fake_backlog(_items(
        {"id": "done-one", "status": "validated", "priority": 1},
        {"id": "waiting", "priority": 5, "depends_on": ["not-done"]},
        {"id": "not-done", "status": "open", "priority": 50},
        {"id": "ready", "priority": 20},
    ))
    bk = orch.load_backlog()
    assert bk.next_open()["id"] == "ready", \
        "an item whose dependency is still open must not be selected"

    bk.set_status("not-done", "validated")
    assert orch.load_backlog().next_open()["id"] == "waiting", \
        "once the dependency is validated the blocked item comes first (priority 5)"


def test_to_test_and_blocked_items_are_never_selected(orch, fake_backlog):
    fake_backlog(_items(
        {"id": "a", "status": "to-test", "priority": 1},
        {"id": "b", "status": "blocked", "priority": 2},
        {"id": "c", "status": "in-progress", "priority": 3},
        {"id": "d", "status": "validated", "priority": 4},
    ))
    assert orch.load_backlog().next_open() is None


def test_the_owners_word_closes_a_to_test_item(orch, fake_backlog):
    """B9: nine items had the owner's green light and could never close, because
    the 'parked' shortcut ran BEFORE the token was read and re-parked them on
    sight, forever."""
    fake_backlog(_items(
        {"id": "spoken-for", "status": "to-test",
         "owner_ok": {"date": "2026-09-03", "text": "c'est bon"}},
        {"id": "still-waiting", "status": "to-test"},
    ))
    bk = orch.load_backlog()
    assert orch.promote_owner_validated(bk) == ["spoken-for"]

    after = orch.load_backlog()
    assert after.get("spoken-for")["status"] == "validated"
    assert after.get("still-waiting")["status"] == "to-test"


def test_a_legacy_owner_ok_token_on_disk_also_closes_the_item(orch, fake_backlog):
    fake_backlog(_items({"id": "tokened", "status": "to-test"}))
    (orch.OWNER_OK_DIR / "tokened").write_text("")

    bk = orch.load_backlog()
    assert orch.promote_owner_validated(bk) == ["tokened"]
    item = orch.load_backlog().get("tokened")
    assert item["status"] == "validated"
    assert item["owner_ok"]["text"].startswith("jeton")


def test_an_item_left_in_progress_by_a_killed_run_is_freed(orch, fake_backlog):
    fake_backlog(_items({"id": "orphan", "status": "in-progress"}))
    bk = orch.load_backlog()
    assert orch.release_stale_in_progress(bk) == ["orphan"]
    assert orch.load_backlog().get("orphan")["status"] == "open"


def test_the_orchestrator_refuses_to_start_without_a_backlog(orch, sandbox):
    reason = orch.backlog_missing_reason()
    assert "lib/backlog.py" in reason
    assert "chantier D" in reason

    (orch.AUTOPORT_DIR / "lib").mkdir(parents=True, exist_ok=True)
    orch.BACKLOG_LIB.write_text("# stub\n")
    reason = orch.backlog_missing_reason()
    assert "backlog.yaml" in reason
    assert "migrate_backlog.py" in reason, "the refusal must say what to DO"

    orch.BACKLOG_PATH.write_text("version: 1\nitems: []\n")
    assert orch.backlog_missing_reason() == ""


def test_no_milestones_cursor_survives(orch):
    """`current_phase_idx` indexed a list edited underneath it."""
    src = open(orch.__file__, encoding="utf-8").read()
    assert "current_phase_idx" not in src
    assert "MILESTONES_PATH" not in src
