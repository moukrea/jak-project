"""Tests de `lib/backlog.py` et de la CLI `autoport`.

Aucun test ne touche le vrai `backlog.yaml` en ecriture : tout ce qui ecrit vit dans
`tmp_path`. Le seul acces au vrai fichier est une lecture, pour verifier que la migration
produit un backlog coherent.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

AUTOPORT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(AUTOPORT))
sys.path.insert(0, str(AUTOPORT / "lib"))

import backlog as bl  # noqa: E402


# ---------------------------------------------------------------------------- fixtures
def _item(iid, **kw):
    it = {
        "id": iid, "feature": "feature %s" % iid, "status": "open", "priority": 50,
        "owner_feedback": [], "gate": None, "game": "jak1", "max_turns": 100,
        "max_retries": 3, "depends_on": [], "history": ["G" + iid], "prompt": None,
        "owner_ok": None,
    }
    it.update(kw)
    return it


def _write(path, items, version=1):
    path.write_text(yaml.safe_dump({"version": version, "items": items},
                                   allow_unicode=True, sort_keys=False), encoding="utf-8")
    return path


@pytest.fixture()
def bpath(tmp_path):
    return tmp_path / "backlog.yaml"


# ---------------------------------------------------------------------------- chargement
def test_load_reads_items_and_version(bpath):
    _write(bpath, [_item("a"), _item("b", status="validated",
                                     owner_ok={"date": "2026-09-01", "text": "ok"})])
    b = bl.load(bpath)
    assert b.version == 1
    assert [it["id"] for it in b.items] == ["a", "b"]
    assert b.get("b")["status"] == "validated"
    assert b.get("inconnu") is None


def test_load_rejects_a_file_that_is_not_a_backlog(tmp_path):
    p = tmp_path / "nope.yaml"
    p.write_text("juste: du texte\n", encoding="utf-8")
    with pytest.raises(bl.BacklogError):
        bl.load(p)


def test_real_backlog_is_loadable_and_covers_every_phase():
    """Le backlog livre se charge, n'a pas de doublon, et couvre les 278 anciennes phases."""
    b = bl.load()
    ids = [it["id"] for it in b.items]
    assert len(ids) == len(set(ids))
    hist = [h for it in b.items for h in (it.get("history") or [])]
    assert len(hist) == len(set(hist)), "une ancienne phase apparait dans deux items"
    milestones = yaml.safe_load((AUTOPORT / "milestones.yaml").read_text(encoding="utf-8"))
    phases = {p["id"] for p in milestones["phases"]}
    assert phases <= set(hist), "phases perdues : %s" % sorted(phases - set(hist))


# ---------------------------------------------------------------------------- next_open
def test_next_open_takes_the_smallest_priority(bpath):
    _write(bpath, [_item("gros", priority=90), _item("urgent", priority=10)])
    assert bl.load(bpath).next_open()["id"] == "urgent"


def test_next_open_skips_an_item_whose_dependency_is_not_validated(bpath):
    _write(bpath, [
        _item("suite", priority=10, depends_on=["prealable"]),
        _item("autre", priority=20),
        _item("prealable", priority=30, status="to-test", where="ici"),
    ])
    assert bl.load(bpath).next_open()["id"] == "autre"


def test_next_open_takes_it_once_the_dependency_is_validated(bpath):
    _write(bpath, [
        _item("suite", priority=10, depends_on=["prealable"]),
        _item("autre", priority=20),
        _item("prealable", priority=30, status="validated",
              owner_ok={"date": "2026-09-01", "text": "c'est bon"}),
    ])
    assert bl.load(bpath).next_open()["id"] == "suite"


def test_next_open_ignores_a_dependency_that_does_not_exist(bpath):
    _write(bpath, [_item("suite", priority=10, depends_on=["fantome"])])
    assert bl.load(bpath).next_open() is None


def test_next_open_returns_none_when_nothing_is_open(bpath):
    _write(bpath, [_item("a", status="to-test", where="ici"),
                   _item("b", status="archived")])
    assert bl.load(bpath).next_open() is None


# ---------------------------------------------------------------------------- ecriture
def test_set_status_writes_atomically_and_leaves_no_temp_file(bpath):
    _write(bpath, [_item("a")])
    b = bl.load(bpath)
    b.set_status("a", "in-progress")
    assert yaml.safe_load(bpath.read_text(encoding="utf-8"))["items"][0]["status"] == "in-progress"
    leftovers = [p for p in bpath.parent.iterdir() if p.name.startswith(".backlog-")]
    assert leftovers == []


def test_set_status_rereads_the_file_before_writing(bpath):
    """Le voisin a ecrit entre notre `load` et notre `set_status` : on ne l'ecrase pas."""
    _write(bpath, [_item("a"), _item("b")])
    mine = bl.load(bpath)
    neighbour = bl.load(bpath)
    neighbour.set_status("b", "to-test", where="dans le menu")
    mine.set_status("a", "in-progress")
    on_disk = {it["id"]: it for it in
               yaml.safe_load(bpath.read_text(encoding="utf-8"))["items"]}
    assert on_disk["a"]["status"] == "in-progress"
    assert on_disk["b"]["status"] == "to-test", "l'ecriture du voisin a ete perdue"


def test_two_processes_writing_at_once_keep_both_changes(bpath, tmp_path):
    _write(bpath, [_item("i%d" % i) for i in range(12)])
    script = tmp_path / "writer.py"
    script.write_text(
        "import sys\n"
        "sys.path.insert(0, %r)\n" % str(AUTOPORT / "lib") +
        "import backlog as bl\n"
        "b = bl.load(sys.argv[1])\n"
        "for i in range(int(sys.argv[2]), 12, 2):\n"
        "    b.set_status('i%d' % i, 'to-test', where='ici')\n",
        encoding="utf-8")
    procs = [subprocess.Popen([sys.executable, str(script), str(bpath), str(k)])
             for k in (0, 1)]
    for p in procs:
        assert p.wait(timeout=120) == 0
    items = yaml.safe_load(bpath.read_text(encoding="utf-8"))["items"]
    assert len(items) == 12
    assert all(it["status"] == "to-test" for it in items), \
        "une des deux ecritures concurrentes a ete perdue"


def test_set_status_refuses_an_unknown_status_and_an_unknown_item(bpath):
    _write(bpath, [_item("a")])
    b = bl.load(bpath)
    with pytest.raises(bl.BacklogError):
        b.set_status("a", "presque-fini")
    with pytest.raises(bl.BacklogError):
        b.set_status("fantome", "open")


def test_set_status_refuses_blocked_without_a_reason(bpath):
    _write(bpath, [_item("a")])
    with pytest.raises(bl.BacklogError):
        bl.load(bpath).set_status("a", "blocked")


def test_validate_records_the_owner_sentence_and_the_build(bpath):
    _write(bpath, [_item("a")])
    b = bl.load(bpath)
    it = b.validate("a", "les caisses sont réparées", date="2026-09-01", sha="deadbeefdeadbeef")
    assert it["status"] == "validated"
    assert it["owner_ok"] == {"date": "2026-09-01", "text": "les caisses sont réparées",
                              "build_sha": "deadbeefdeadbeef"}
    assert it["owner_feedback"][-1]["text"] == "les caisses sont réparées"
    assert it["priority"] is None


# ---------------------------------------------------------------------------- lint
def test_lint_is_quiet_on_a_healthy_backlog(bpath):
    _write(bpath, [
        _item("a", status="to-test", where="dans le menu"),
        _item("b", status="validated", owner_ok={"date": "2026-09-01", "text": "ok"}),
        _item("c", device=True, gate={"key": "k", "op": "==", "value": 0}),
    ])
    assert bl.load(bpath).lint() == []


@pytest.mark.parametrize("items, needle", [
    ([_item("a", device=True)], "device: true sans gate"),
    ([_item("a", status="to-test")], "ou regarder"),
    ([_item("a", status="to-test", where="   ")], "ou regarder"),
    ([_item("a", status="blocked")], "block_reason"),
    ([_item("a", depends_on=["fantome"])], "n'existe pas"),
    ([_item("a"), _item("a")], "id en double"),
    ([_item("a", status="validated")], "sans owner_ok"),
    ([_item("a", status="presque")], "statut inconnu"),
    ([_item("a", feature="")], "libelle"),
    ([_item("a", device=True, gate={"key": "k", "op": "~=", "value": 0})], "operateur inconnu"),
    ([_item("a", device=True, gate={"key": "k"})], "gate mal forme"),
])
def test_lint_catches_each_case(bpath, items, needle):
    _write(bpath, items)
    problems = bl.load(bpath).lint()
    assert any(needle in p for p in problems), problems


def test_lint_accepts_a_blocked_item_that_says_why(bpath):
    _write(bpath, [_item("a", status="blocked", block_reason="l'owner a demande de parquer")])
    assert bl.load(bpath).lint() == []


def test_real_backlog_only_fails_lint_on_missing_gates():
    """Le backlog livre ne doit avoir qu'une seule famille de reproche : les gates a ecrire."""
    problems = bl.load().lint()
    assert all("device: true sans gate" in p for p in problems), problems


# ---------------------------------------------------------------------------- rapport
def test_status_report_never_shows_a_validated_item(bpath):
    _write(bpath, [
        _item("valide", status="validated", feature="La police Urbanist",
              owner_ok={"date": "2026-09-03", "text": "c'est reglé"}),
        _item("atester", status="to-test", feature="Les sous-titres",
              where="pendant une cinematique", build="build du 3 septembre"),
    ])
    text = bl.load(bpath).status_report()
    assert "La police Urbanist" not in text
    assert "Les sous-titres" in text


def test_status_report_has_the_three_blocks_and_omits_the_empty_ones(bpath):
    _write(bpath, [_item("encours", status="in-progress", feature="Les PNJ qui clignotent")])
    text = bl.load(bpath).status_report()
    assert text.startswith("## En cours")
    assert "Les PNJ qui clignotent" in text
    assert "## A tester" not in text
    assert "## Bloque" not in text


def test_status_report_names_the_next_subject_when_nothing_is_in_progress(bpath):
    _write(bpath, [_item("suivant", feature="La brise dans les arbres", priority=5)])
    text = bl.load(bpath).status_report()
    assert "Rien en cours" in text and "La brise dans les arbres" in text


def test_status_report_tells_where_to_look_and_which_build(bpath):
    _write(bpath, [_item("a", status="to-test", feature="Le saut de cinematique",
                         where="maintiens Cercle", build="v9 APK", delivered="2026-09-02")])
    text = bl.load(bpath).status_report()
    assert "Le saut de cinematique" in text
    assert "v9 APK" in text
    assert "maintiens Cercle" in text


def test_status_report_says_why_an_item_is_blocked(bpath):
    _write(bpath, [_item("a", status="blocked", feature="Jak II",
                         block_reason="l'owner a demandé de parquer jak2")])
    text = bl.load(bpath).status_report()
    assert "## Bloque" in text and "parquer jak2" in text


def test_status_report_changed_only_is_silent_the_second_time(bpath, tmp_path, monkeypatch):
    monkeypatch.setattr(bl, "DIGEST_MEMO", str(tmp_path / "memo"))
    _write(bpath, [_item("a", status="to-test", feature="Les caisses", where="Geyser Rock",
                         delivered="2026-09-02")])
    b = bl.load(bpath)
    assert "Les caisses" in b.status_report(changed_only=True)
    assert bl.load(bpath).status_report(changed_only=True) == ""
    b.set_status("a", "to-test", feature="Les caisses de Geyser Rock")
    assert "Les caisses de Geyser Rock" in bl.load(bpath).status_report(changed_only=True)


def test_status_report_changed_only_ignores_the_debt(bpath, tmp_path, monkeypatch):
    """La dette ne bouge pas d'elle-meme : elle ne doit pas reveiller un digest."""
    monkeypatch.setattr(bl, "DIGEST_MEMO", str(tmp_path / "memo"))
    _write(bpath, [
        _item("neuf", status="to-test", feature="Le saut de cinematique", where="Cercle",
              delivered="2026-09-02"),
        _item("vieux", status="to-test", feature="Le vieux menu", where="ailleurs",
              delivered="2026-07-01"),
    ])
    assert "Le saut de cinematique" in bl.load(bpath).status_report(changed_only=True)
    bl.load(bpath).set_status("vieux", "to-test", feature="Le tres vieux menu")
    assert bl.load(bpath).status_report(changed_only=True) == ""


def test_status_report_of_the_real_backlog_is_french_and_has_no_commit_noise():
    text = bl.load().status_report()
    assert "## A tester" in text
    for noise in ("commit", "validator", "attempt", "WIP", "sha=", "[autoport/"):
        assert noise not in text, noise
    validated = [it["feature"] for it in bl.load().items if it["status"] == "validated"]
    for feature in validated:
        assert feature not in text, "une feature validee est re-listee : %s" % feature


# ---------------------------------------------------------------------------- prompts
def test_render_prompt_has_the_five_sections_and_the_owner_words(bpath):
    _write(bpath, [_item("a", feature="Les PNJ qui clignotent",
                         owner_feedback=[{"date": "2026-09-03", "text": "c'est toujours pété"}],
                         gate={"key": "npc_culled_in_frustum", "op": "==", "value": 0},
                         device=True)])
    text = bl.render_prompt(bl.load(bpath).get("a"))
    for section in ("## Defaut cite", "## Cause connue", "## Livrable",
                    "## Preuve exigee", "## Hors perimetre"):
        assert section in text
    assert "c'est toujours pété" in text
    assert "npc_culled_in_frustum == 0" in text
    assert "lib/proof_run.sh a device" in text


def test_render_prompt_stays_under_the_ceiling_by_trimming_quotes(bpath):
    long_fb = [{"date": "2026-09-0%d" % i, "text": "x" * 900} for i in range(1, 6)]
    _write(bpath, [_item("a", owner_feedback=long_fb)])
    text = bl.render_prompt(bl.load(bpath).get("a"))
    assert len(text.encode("utf-8")) <= bl.PROMPT_MAX


def test_render_prompt_fails_loudly_when_it_cannot_fit(bpath):
    _write(bpath, [_item("a", known_cause="y" * 4000)])
    with pytest.raises(bl.BacklogError):
        bl.render_prompt(bl.load(bpath).get("a"))


def test_every_open_item_of_the_real_backlog_has_a_prompt_on_disk():
    for it in bl.load().items:
        if it["status"] != "open":
            continue
        assert it.get("prompt"), it["id"]
        path = AUTOPORT / it["prompt"]
        assert path.exists(), path
        assert path.stat().st_size <= bl.PROMPT_MAX


# ---------------------------------------------------------------------------- CLI
def _cli(bpath, *args):
    return subprocess.run([sys.executable, str(AUTOPORT / "autoport"),
                           "--file", str(bpath)] + list(args),
                          capture_output=True, text=True, timeout=120)


def test_cli_next_show_set_ok_and_lint(bpath):
    _write(bpath, [_item("a", feature="Les caisses", priority=1)])
    assert _cli(bpath, "next").stdout.strip() == "a"
    assert "Les caisses" in _cli(bpath, "show", "a").stdout
    assert _cli(bpath, "set", "a", "in-progress").returncode == 0
    r = _cli(bpath, "ok", "a", "les caisses sont réparées")
    assert r.returncode == 0 and "valide par l'owner" in r.stdout
    assert yaml.safe_load(bpath.read_text(encoding="utf-8"))["items"][0]["owner_ok"]["text"] \
        == "les caisses sont réparées"
    assert _cli(bpath, "lint").returncode == 0


def test_cli_status_json_only_lists_actionable_items(bpath):
    _write(bpath, [_item("a", status="archived"),
                   _item("b", status="to-test", where="ici"),
                   _item("c", status="validated", owner_ok={"date": "x", "text": "y"})])
    data = json.loads(_cli(bpath, "status", "--json").stdout)
    assert [it["id"] for it in data] == ["b"]


def test_cli_set_blocked_records_the_reason(bpath):
    _write(bpath, [_item("a")])
    r = _cli(bpath, "set", "a", "blocked", "--reason", "l'owner a demandé de parquer")
    assert r.returncode == 0
    assert yaml.safe_load(bpath.read_text(encoding="utf-8"))["items"][0]["block_reason"] \
        == "l'owner a demandé de parquer"


def test_cli_lint_exits_nonzero_on_a_broken_backlog(bpath):
    _write(bpath, [_item("a", status="to-test")])
    r = _cli(bpath, "lint")
    assert r.returncode == 1 and "ou regarder" in r.stdout


def test_cli_show_unknown_item_exits_nonzero(bpath):
    _write(bpath, [_item("a")])
    assert _cli(bpath, "show", "fantome").returncode == 1


# ---------------------------------------------------------------------------- migration
def test_migration_is_replayable_and_byte_identical(tmp_path):
    """Rejouer la migration sur les memes sources doit redonner le meme fichier."""
    out = tmp_path / "backlog.yaml"
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    for _ in range(2):
        r = subprocess.run([sys.executable, str(AUTOPORT / "tools" / "migrate_backlog.py"),
                            "--out", str(out)], capture_output=True, text=True,
                           timeout=600, env=env)
        assert r.returncode == 0, r.stderr
    first = out.read_bytes()
    subprocess.run([sys.executable, str(AUTOPORT / "tools" / "migrate_backlog.py"),
                    "--out", str(out)], capture_output=True, text=True, timeout=600, env=env)
    assert out.read_bytes() == first
    doc = yaml.safe_load(out.read_text(encoding="utf-8"))
    assert doc["version"] == 1 and len(doc["items"]) > 100


def test_migration_does_not_touch_its_sources(tmp_path):
    sources = [AUTOPORT / "milestones.yaml", AUTOPORT / "state.json"]
    before = [p.read_bytes() for p in sources]
    subprocess.run([sys.executable, str(AUTOPORT / "tools" / "migrate_backlog.py"),
                    "--out", str(tmp_path / "b.yaml")], capture_output=True, timeout=600)
    assert [p.read_bytes() for p in sources] == before


def test_cli_reopening_an_item_regenerates_its_prompt(bpath):
    """Rouvrir = regenerer le prompt depuis l'item ; c'est ce qui remplace les clones `-2`."""
    (bpath.parent / "prompts").mkdir()
    _write(bpath, [_item("a", status="validated", feature="Les PNJ qui clignotent",
                         owner_ok={"date": "2026-09-01", "text": "ok"},
                         owner_feedback=[{"date": "2026-09-03", "text": "c'est toujours pété"}])])
    r = _cli(bpath, "set", "a", "open")
    assert r.returncode == 0, r.stderr
    generated = bpath.parent / "prompts" / "item-a.md"
    assert generated.exists()
    text = generated.read_text(encoding="utf-8")
    assert "c'est toujours pété" in text and "## Livrable" in text
    assert yaml.safe_load(bpath.read_text(encoding="utf-8"))["items"][0]["prompt"] \
        == "prompts/item-a.md"


# ------------------------------------------------------- dette, portee du lint, budgets
def test_status_report_splits_what_is_testable_now_from_the_debt(bpath):
    _write(bpath, [
        _item("neuf", status="to-test", feature="Le saut de cinematique",
              where="maintiens Cercle", build=bl.CURRENT_BUILD, delivered="2026-09-02"),
        _item("vieux", status="to-test", feature="Le choix de la resolution",
              where="Options > Graphismes", build="build du 2026-06-30, remplace depuis",
              delivered="2026-06-30"),
    ])
    text = bl.load(bpath).status_report()
    a_tester = text.split("## Dette a trier")[0]
    dette = text.split("## Dette a trier")[1]
    assert "Le saut de cinematique" in a_tester and "maintiens Cercle" in a_tester
    assert "Le choix de la resolution" in dette
    assert "Options > Graphismes" not in dette, "la dette ne porte pas « ou regarder »"
    assert "(livre le 2026-06-30)" in dette


def test_status_report_all_details_the_debt(bpath):
    _write(bpath, [_item("vieux", status="to-test", feature="Le choix de la resolution",
                         where="Options > Graphismes", delivered="2026-06-30")])
    assert "Options > Graphismes" not in bl.load(bpath).status_report()
    assert "Options > Graphismes" in bl.load(bpath).status_report(show_all=True)


def test_status_report_names_the_build_only_when_it_is_not_the_current_one(bpath):
    _write(bpath, [
        _item("a", status="to-test", feature="A", where="ici", build=bl.CURRENT_BUILD,
              delivered="2026-09-02"),
        _item("b", status="to-test", feature="B", where="la", build="v9 APK",
              delivered="2026-09-01"),
    ])
    text = bl.load(bpath).status_report()
    assert text.count("Build : ") == 1 and "Build : v9 APK" in text


def test_status_report_omits_the_debt_block_when_there_is_none(bpath):
    _write(bpath, [_item("a", status="to-test", feature="A", where="ici",
                         delivered="2026-09-02")])
    assert "## Dette a trier" not in bl.load(bpath).status_report()


@pytest.mark.parametrize("status", ["to-test", "validated", "archived"])
def test_lint_does_not_complain_about_a_gate_on_an_item_that_will_not_run(bpath, status):
    extra = {"owner_ok": {"date": "2026-09-01", "text": "ok"}} if status == "validated" else {}
    extra.update({"where": "ici"} if status == "to-test" else {})
    _write(bpath, [_item("a", status=status, device=True, gate=None, **extra)])
    assert bl.load(bpath).lint() == []


@pytest.mark.parametrize("status", ["open", "blocked"])
def test_lint_still_complains_about_a_gate_on_an_item_the_orchestrator_can_take(bpath, status):
    extra = {"block_reason": "parce que"} if status == "blocked" else {}
    _write(bpath, [_item("a", status=status, device=True, gate=None, **extra)])
    assert any("device: true sans gate" in p for p in bl.load(bpath).lint())


def test_lint_refuses_a_budget_above_the_default_without_a_written_reason(bpath):
    _write(bpath, [_item("a", max_turns=3000, max_retries=60)])
    problems = bl.load(bpath).lint()
    assert any("max_turns 3000" in p for p in problems)
    assert any("max_retries 60" in p for p in problems)


def test_lint_accepts_a_budget_above_the_default_when_notes_say_why(bpath):
    _write(bpath, [_item("a", max_turns=3000, max_retries=60,
                         notes="budget : recensement exhaustif de 172 matieres")])
    assert bl.load(bpath).lint() == []


def test_the_real_backlog_carries_sane_budgets():
    for it in bl.load().items:
        note = it.get("notes") or ""
        if bl.BUDGET_NOTE not in note:
            assert it["max_turns"] <= bl.DEFAULT_MAX_TURNS, it["id"]
            assert it["max_retries"] <= bl.DEFAULT_MAX_RETRIES, it["id"]


def test_cli_status_all_flag(bpath):
    _write(bpath, [_item("vieux", status="to-test", feature="Le vieux menu",
                         where="Options > Graphismes", delivered="2026-06-30")])
    assert "Options > Graphismes" not in _cli(bpath, "status").stdout
    assert "Options > Graphismes" in _cli(bpath, "status", "--all").stdout
