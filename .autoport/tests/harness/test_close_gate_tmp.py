"""Temporaires des acquis : vrais enfants, fermeture et fichiers jetables uniquement."""
import json
import os
from pathlib import Path
import shlex
import sys

import pytest


@pytest.fixture(params=["absent", "polluted"])
def acquis_bench(request, orch, sandbox, monkeypatch):
    home = sandbox / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    for name in ("TMPDIR", "TMP", "TEMP"):
        monkeypatch.delenv(name, raising=False)
    if request.param == "polluted":
        monkeypatch.setenv("TMPDIR", "/tmp")
        monkeypatch.setenv("TMP", "/tmp/acquis-polluted-tmp")
        monkeypatch.setenv("TEMP", "/tmp/acquis-polluted-temp")
    monkeypatch.setattr(orch, "_reread_item", lambda iid, fallback: fallback)
    monkeypatch.setattr(orch, "foreign_dirty_engine_paths", lambda paths: [])
    monkeypatch.setattr(orch, "load_quarantine", lambda: {})
    suite_calls = []

    def suite_pass(*args, **kwargs):
        suite_calls.append((args, kwargs))
        return dict(verdict="pass", collected=1, failed=0, unwaived=0,
                    duration_s=0, budget_s=240, registry_sha="banc",
                    registry_entries=0, self_added=0, over_budget=0)

    monkeypatch.setattr(orch.suite_gate, "judge", suite_pass)
    acquis = sandbox / ".autoport" / "acquis"
    acquis.mkdir()
    journal = sandbox / "acquis.jsonl"
    observer = sandbox / "observe.py"
    observer.write_text('''import json, os, pathlib, sys, tempfile
role, journal, script = sys.argv[1:4]
if role == "python":
    fd, path = tempfile.mkstemp()
    with os.fdopen(fd, "w") as f:
        f.write("acquis-written\\n")
else:
    path = sys.argv[4]
p = pathlib.Path(path)
assert p.read_text() == "acquis-written\\n"
with open(journal, "a") as f:
    f.write(json.dumps(dict(role=role, script=script, path=str(p.resolve()),
                           env={k: os.environ.get(k) for k in ("TMPDIR", "TMP", "TEMP")},
                           content=p.read_text())) + "\\n")
''')
    python = shlex.quote(sys.executable)
    observe = shlex.quote(str(observer))
    records = shlex.quote(str(journal))
    for name in ("a.sh", "b.sh", "c.sh"):
        (acquis / name).write_text(f'''#!/bin/bash
set -eu
test "$#" = 1 && test -z "$1"
p=$(mktemp)
printf 'acquis-written\\n' > "$p"
{python} {observe} shell {records} {name} "$p"
bash -c 'set -eu; p=$(mktemp); printf "acquis-written\\n" > "$p"; "$1" "$2" child "$3" "$4" "$p"' bash {python} {observe} {records} {name}
{python} {observe} python {records} {name}
''')
    # La bibliothèque n'est jamais une garde exécutable, même en balayage complet.
    (acquis / "_lib.sh").write_text("exit 93\n")
    return dict(home=home, journal=journal, acquis=acquis,
                rotation=sandbox / ".autoport" / ".acquis_rotation",
                suite_calls=suite_calls,
                parent={k: os.environ.get(k) for k in ("TMPDIR", "TMP", "TEMP")})


def check_created(bench, expected, record_property):
    rows = [json.loads(line) for line in bench["journal"].read_text().splitlines()]
    assert [(row["script"], row["role"]) for row in rows] == [
        (name, role) for name in expected for role in ("shell", "child", "python")]
    paths = [row["path"] for row in rows]
    assert len(set(paths)) == len(paths)
    roots = set()
    for row in rows:
        path = Path(row["path"])
        env = row["env"]
        assert env["TMPDIR"] == env["TMP"] == env["TEMP"]
        root = Path(env["TMPDIR"]).resolve()
        assert root.name.startswith("suite-acquis-")
        assert not root.is_relative_to(Path("/tmp"))
        assert path.is_relative_to(root)
        assert row["content"] == "acquis-written\n"
        assert not path.exists()
        assert not root.exists()
        roots.add(root)
    assert len(roots) == 1
    assert {k: os.environ.get(k) for k in ("TMPDIR", "TMP", "TEMP")} == bench["parent"]
    record_property("acquis_created_paths", json.dumps(paths))


@pytest.mark.parametrize("mode,initial,owner_test,expected,rotation", [
    ("initial", None, False, ["a.sh", "b.sh", "c.sh"], "0 0\n"),
    ("rotation", "4 1\n", False, ["b.sh"], "5 2\n"),
    ("periodic", "4 3\n", False, ["a.sh", "b.sh", "c.sh"], "4 0\n"),
    ("owner", "4 1\n", True, ["a.sh", "b.sh", "c.sh"], "4 0\n"),
])
def test_acquis_temporaries(orch, acquis_bench, record_property,
                           mode, initial, owner_test, expected, rotation):
    bench = acquis_bench
    if initial is not None:
        bench["rotation"].write_text(initial)
    # `where` « rien a regarder » : ce banc juge les acquis, pas la capture que GATE CAPTURE exige
    # d'un chantier visible (`test_owner_capture_gate.py`).
    result = orch.close_gate(dict(id="tmp-bench", no_code=True, device=False,
                                 owner_test=owner_test, where="rien a regarder en jeu : banc"))
    assert result == (("awaiting-owner", "") if owner_test else ("pass", ""))
    assert len(bench["suite_calls"]) == 1
    assert bench["rotation"].read_text() == rotation
    check_created(bench, expected, record_property)
    record_property("acquis_rotation", json.dumps(dict(
        mode=mode, before=initial, after=rotation, executed=expected)))


def test_acquis_red_refuses_and_stops(orch, acquis_bench, record_property):
    bench = acquis_bench
    bench["rotation"].write_text("4 1\n")
    with (bench["acquis"] / "a.sh").open("a") as script:
        script.write("echo acquis-red-exit-37 >&2\nexit 37\n")
    status, reason = orch.close_gate(dict(id="tmp-bench", no_code=True,
                                         device=False, owner_test=True))
    assert status == "fail"
    assert "CLOSE-GATE/acquis: a.sh" in reason
    assert "acquis-red-exit-37" in reason
    assert not bench["suite_calls"]
    assert bench["rotation"].read_text() == "4 0\n"
    check_created(bench, ["a.sh"], record_property)
    record_property("acquis_red_refusal", reason)


def test_acquis_unavailable_does_not_advance_rotation(orch, acquis_bench, record_property):
    bench = acquis_bench
    (bench["home"] / ".cache").write_text("not a directory\n")
    bench["rotation"].write_text("4 1\n")
    status, reason = orch.close_gate(dict(id="tmp-bench", no_code=True,
                                         device=False, owner_test=False))
    assert status == "fail"
    assert "CLOSE-GATE/acquis-temporaire-indisponible" in reason
    assert "suite-temporaire-indisponible" in reason
    assert "aucun verdict sur le code du jeu" in reason
    assert "ACQUIS VALIDÉ PAR L'OWNER" not in reason
    assert not bench["journal"].exists()
    assert not bench["suite_calls"]
    assert bench["rotation"].read_text() == "4 1\n"
    record_property("acquis_unavailable_refusal", reason)
