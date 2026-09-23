"""Journal des gestes etrangers et `code_scope: a-cadrer` (harness-owner-gesture-not-imputed-to-running-item)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AP = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, AP)

from lib import backlog as B  # noqa: E402


def _write(path, items):
    B._atomic_write(str(path), B._dump({"version": 1, "items": items}))


def test_a_cadrer_holds_the_item_out_of_the_queue_until_framed(tmp_path):
    p = tmp_path / "backlog.yaml"
    _write(p, [{"id": "owner-x", "status": "open", "priority": 1, "code_scope": "a-cadrer",
                "prompt": "prompts/owner-x.md"}])
    assert B.awaiting_framing(B.load(str(p)).get("owner-x"))
    assert B.load(str(p)).next_open() is None          # une consigne seule ne suffit pas
    B.load(str(p)).set_scope("owner-x", "harnais")
    assert B.load(str(p)).next_open()["id"] == "owner-x"


def test_only_foreign_authors_are_journaled(tmp_path):
    p = tmp_path / "backlog.yaml"
    _write(p, [{"id": "a", "status": "open", "priority": 1}])
    bl = B.load(str(p))
    bl.set_status("a", "blocked", block_reason="essai")          # auteur None : l'essai
    assert B.read_gestures(str(p)) == []
    bl = B.load(str(p))
    bl.author = "superviseur"
    bl.set_status("a", "open")
    g = B.read_gestures(str(p))
    assert [e["author"] for e in g] == ["superviseur"]
    assert g[0]["items"][0]["before"]["status"] == "blocked"
    assert g[0]["items"][0]["after"]["status"] == "open"


def test_apply_gestures_is_field_level_and_reversible():
    doc = {"version": 1, "items": [{"id": "run", "status": "in-progress", "retries": 1}]}
    gestes = [{"author": "linear_sync", "items": [
        {"id": "owner-y", "before": None, "after": {"id": "owner-y", "status": "open"}},
        {"id": "run", "before": {"id": "run", "status": "in-progress", "notes": ""},
         "after": {"id": "run", "status": "in-progress", "notes": "owner"}}]}]
    avec, n = B.apply_gestures(doc, gestes)
    assert n == 2 and [it["id"] for it in avec["items"]] == ["run", "owner-y"]
    assert avec["items"][0]["notes"] == "owner" and avec["items"][0]["retries"] == 1
    sans, _ = B.apply_gestures(avec, gestes, reverse=True)
    assert [it["id"] for it in sans["items"]] == ["run"]
    assert sans["items"][0] == {"id": "run", "status": "in-progress", "retries": 1, "notes": ""}
    assert doc["items"] == [{"id": "run", "status": "in-progress", "retries": 1}]   # intact
