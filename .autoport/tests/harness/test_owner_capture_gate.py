"""GATE CAPTURE : un chantier visible ne part au test de l'owner que si son ticket porte une capture.

Les cas du contrat de `harness-owner-test-requires-a-capture` (issues a/b/c de l'owner, 22/09), joues
contre le VRAI `close_gate` et le VRAI `linear_sync.post_comment` (seul Linear est simule).
"""
import json
import time
from datetime import datetime

import pytest

ID = "capture-bench"


@pytest.fixture()
def gate(orch, sandbox, monkeypatch):
    monkeypatch.setattr(orch, "_reread_item", lambda iid, fallback: fallback)
    monkeypatch.setattr(orch, "foreign_dirty_engine_paths", lambda paths: [])
    monkeypatch.setattr(orch, "load_quarantine", lambda: {})
    monkeypatch.setattr(orch.suite_gate, "judge", lambda *a, **k: dict(
        verdict="pass", collected=1, failed=0, unwaived=0, duration_s=0, budget_s=240,
        registry_sha="banc", registry_entries=0, self_added=0, over_budget=0))
    # La porte CLOSE-GATE/directives a ses propres bancs (test_directives.py, census) :
    # ici, comme la suite, elle est tenue ouverte.
    import directives as _dv
    monkeypatch.setattr(_dv, "report_verdict", lambda *a, **k: (True, "banc"))
    ap = orch.AUTOPORT_DIR
    since = time.time() - 60

    def close(**item):
        it = dict(id=ID, no_code=True, device=False, owner_test=True,
                  where="Le coeur du HUD en bas a gauche")
        it.update(item)
        return orch.close_gate(it, since=since)

    def post(body, at, capture_failed=""):
        orch.owner_capture.record(ap, ID, body, issue_id="iss", comment_id="c",
                                  capture_failed=capture_failed, when=at)

    def publish(when):
        (ap / ".published_build_info.txt").write_text(
            "TAG: abc123-def456      (a comparer)\n"
            f"date: {datetime.fromtimestamp(when).astimezone().isoformat(timespec='seconds')}"
            "     commit: abc123 build AUTOMATIQUE\n")

    return dict(close=close, post=post, publish=publish, since=since, ap=ap)


def test_visible_without_image_is_refused_with_the_reason(gate):
    gate["post"]("Le coeur est pret, va voir", gate["since"] + 5)
    status, reason = gate["close"]()
    assert status == "fail"
    assert reason.startswith("CLOSE-GATE/capture")
    assert "AUCUNE image" in reason and "--attach" in reason and "--no-capture" in reason


def test_visible_with_image_posted_during_the_attempt_passes(gate):
    gate["post"]("Voici la zone\n\n![hud.png](https://uploads.linear.app/x/hud.png)",
                 gate["since"] + 5)
    assert gate["close"]() == ("awaiting-owner", "")


def test_image_of_a_previous_attempt_does_not_count(gate):
    gate["post"]("![old.png](https://uploads.linear.app/x/old.png)", gate["since"] - 3600)
    status, reason = gate["close"]()
    assert status == "fail" and "CLOSE-GATE/capture" in reason


@pytest.mark.parametrize("where", ["Rien a installer : chantier du harnais",
                                   "Rien à regarder en jeu : preuve machine"])
def test_nothing_to_see_passes_without_image(gate, where):
    assert gate["close"](where=where) == ("awaiting-owner", "")


def test_impossible_capture_with_a_build_delivered_passes(gate):
    gate["publish"](gate["since"] + 30)
    gate["post"]("Regarde le coeur en bas a gauche", gate["since"] + 40,
                 capture_failed="le telephone est verrouille")
    assert gate["close"]() == ("awaiting-owner", "")


def test_impossible_capture_without_a_fresh_build_is_refused(gate):
    gate["publish"](gate["since"] - 86400)
    gate["post"]("Regarde le coeur", gate["since"] + 40, capture_failed="ecran noir")
    status, reason = gate["close"]()
    assert status == "fail" and "AUCUN build publie" in reason


def test_post_comment_writes_the_ledger_at_the_point_of_production(gate, monkeypatch):
    import linear_sync as LS  # noqa: PLC0415
    monkeypatch.setattr(LS, "HOME", gate["ap"])
    monkeypatch.setitem(LS._CTX, "mp", {ID: {"issue_id": "iss-1", "identifier": "JAK-1"}})

    class FakeLinear:
        def q(self, query, **v):
            assert "comment { id }" in query
            return {"commentCreate": {"success": True, "comment": {"id": "cmt-9"}}}

    LS.post_comment(FakeLinear(), "iss-1", "zone\n\n![a.png](https://uploads.linear.app/a.png)")
    rows = [json.loads(l) for l in (gate["ap"] / "logs" / "linear_comments.jsonl")
            .read_text().splitlines()]
    assert rows[-1]["item"] == ID and rows[-1]["image"] is True
    assert rows[-1]["comment_id"] == "cmt-9"
    assert gate["close"]() == ("awaiting-owner", "")


# ------------------------------------------------ INVISIBLE-CAPTURE/ (harness-invisible-item-comment-has-no-capture-boilerplate)
import sys as _sys  # noqa: E402
from pathlib import Path as _P  # noqa: E402
_sys.path.insert(0, str(_P(__file__).resolve().parents[2] / "lib"))
import owner_capture as oc  # noqa: E402
_INV = {"id": "h-invisible", "feature": "ne parle jamais de capture ni de build a tester", "owner_test": False}
_VIS = {"id": "g-visible", "feature": "herbe", "owner_test": True, "where": "Sandover"}


def test_invisible_refuses_no_capture_image_and_boilerplate():
    assert "INVISIBLE-CAPTURE" in oc.invisible_comment_refusal(_INV, "ok", (), "rien a l'ecran")
    assert "shot.png" in oc.invisible_comment_refusal(_INV, "ok", ("/tmp/shot.png",), "")
    assert oc.invisible_comment_refusal(_INV, "Capture impossible : x. Build a tester : y", (), "")
    assert oc.invisible_comment_refusal(_INV, "ok", ("/tmp/journal.txt",), "") == ""
    # le titre de l'item, cite par le harnais, n'est pas « parler de capture »
    assert oc.invisible_comment_refusal(_INV, "Critère : « ne parle jamais de capture ni de build a tester »", (), "") == ""


def test_visible_is_never_refused_here():
    assert oc.invisible_comment_refusal(_VIS, "Capture impossible", ("/tmp/shot.png",), "ecran") == ""


def test_scrub_removes_image_and_capture_lines_only_on_invisible():
    body = "Essai 2 : porte tenue.\nCapture impossible : x. Build a tester : y\n![a.png](https://u/a.png)"
    out, n = oc.scrub_invisible(_INV, body)
    assert out == "Essai 2 : porte tenue." and n == 2
    assert oc.scrub_invisible(_VIS, body) == (body, 0)
    # par phrase : le reste de la ligne relayee survit
    out, n = oc.scrub_invisible(_INV, "**Ce que dit l'agent** : Porte tenue. Pas de capture : rien a voir. Reste : rien.")
    assert out == "**Ce que dit l'agent** : Porte tenue. Reste : rien." and n == 1
