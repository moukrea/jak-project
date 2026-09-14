"""Chemins réellement créés par pytest, tempfile et mktemp, via les lanceurs livrés."""
import json
from pathlib import Path
import subprocess

import pytest
import suite_gate as SG


def seed(root, manifest):
    suite = root / ".autoport/tests/harness"
    suite.mkdir(parents=True)
    (suite / "ECHECS-ATTENDUS.yaml").write_text("attendus: []\n")
    (suite / "test_paths.py").write_text('''import json, os, subprocess, tempfile
from pathlib import Path
def test_paths(tmp_path):
    with tempfile.NamedTemporaryFile() as f:
        shell = subprocess.check_output(["bash", "-c", "mktemp"], text=True).strip()
        paths = [str(tmp_path), f.name, shell, os.environ["TMPDIR"]]
        assert all(Path(p).exists() for p in paths)
        with open(%r, "a") as out:
            out.write(json.dumps(paths) + "\\n")
        Path(shell).unlink()
''' % str(manifest))
    for args in (("init", "-q"), ("add", "."),
                 ("-c", "user.name=bench", "-c", "user.email=bench@example.invalid",
                  "commit", "-qm", "temporary bench")):
        subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)
    return ".autoport/tests/harness/test_paths.py::test_paths"


def check_paths(manifest, count, record_property):
    rows = [json.loads(line) for line in manifest.read_text().splitlines()]
    assert len(rows) == count
    record_property("created_paths", json.dumps(rows))
    for paths in rows:
        assert len(paths) == 4
        for path in paths:
            resolved = Path(path).resolve()
            assert not resolved.is_relative_to("/tmp"), path
            assert "suite-pytest-" in path, path
            assert not resolved.exists(), "le lanceur doit nettoyer ses temporaires"


@pytest.mark.parametrize("inherited", [None, "/tmp", "/nonexistent/suite-tmp"])
def test_suite_paths(tmp_path, monkeypatch, record_property, inherited):
    if inherited is None:
        monkeypatch.delenv("TMPDIR", raising=False)
    else:
        monkeypatch.setenv("TMPDIR", inherited)
    manifest = tmp_path / "paths.jsonl"
    root = tmp_path / "repo"
    seed(root, manifest)
    result = SG.judge(root, root / ".autoport", record=False)
    assert result["verdict"] == "pass", result
    assert result["collected"] == 1
    check_paths(manifest, 1, record_property)


def test_replay_paths(tmp_path, monkeypatch, record_property):
    monkeypatch.setenv("TMPDIR", "/tmp")
    manifest = tmp_path / "paths.jsonl"
    root = tmp_path / "repo"
    node = seed(root, manifest)
    result, info = SG.replay(str(root), ["HEAD", "HEAD~0"], [node])
    assert info["ran"] == 1 and info["error"] == "-", info
    assert all(result[ref][node] == "passed" for ref in result), result
    assert not Path(info["worktree"]).is_relative_to("/tmp")
    assert not Path(info["worktree"]).exists()
    record_property("worktree", info["worktree"])
    check_paths(manifest, 2, record_property)


@pytest.mark.parametrize("launcher", ["suite", "replay"])
def test_unavailable_is_infrastructure(tmp_path, monkeypatch, record_property, launcher):
    root = tmp_path / "repo"
    node = seed(root, tmp_path / "unused.jsonl")
    fake_home = tmp_path / "home"
    fake_home.mkdir()
    (fake_home / ".cache").write_text("un fichier interdit la creation du repertoire")
    monkeypatch.setenv("HOME", str(fake_home))
    if launcher == "suite":
        result = SG.judge(root, root / ".autoport", record=False)
        assert result["verdict"] == "refuse" and result["ran"] == 0
        assert result["refused_for"] == ["suite-temporaire-indisponible"]
        error = result["reason"]
    else:
        result, info = SG.replay(str(root), ["HEAD"], [node])
        assert info["ran"] == 0 and result == {"HEAD": {}}
        error = info["error"]
    assert "suite-temporaire-indisponible" in error
    assert "aucun verdict sur le code du jeu" in error
    assert str(fake_home) in error
    record_property("infrastructure_refusal", error)


def test_cache_symlink_into_tmp_refused(tmp_path, monkeypatch):
    fake_home = tmp_path / "home"
    fake_home.mkdir()
    (fake_home / ".cache").symlink_to("/tmp", target_is_directory=True)
    monkeypatch.setenv("HOME", str(fake_home))
    with pytest.raises(SG.SuiteTemporaryUnavailable, match="sous /tmp"):
        with SG.suite_temporary("unused-"):
            pytest.fail("un alias de /tmp ne doit pas passer")


def test_cleanup_on_exception():
    with pytest.raises(RuntimeError):
        with SG.suite_temporary("suite-test-") as path:
            assert Path(path).is_dir()
            raise RuntimeError("fin du banc")
    assert not Path(path).exists()


def test_replay_unavailable_does_not_accuse_work(tmp_path, monkeypatch):
    root = tmp_path / "repo"
    seed(root, tmp_path / "paths.jsonl")
    test = root / ".autoport/tests/harness/test_paths.py"
    with test.open("a") as out:
        out.write("    assert False, 'rouge a classer'\n")
    original = SG.suite_temporary

    def unavailable(prefix):
        if prefix == "suite-replay-":
            raise SG.SuiteTemporaryUnavailable(
                "suite-temporaire-indisponible: banc indisponible; aucun verdict sur le code du jeu")
        return original(prefix)

    monkeypatch.setattr(SG, "suite_temporary", unavailable)
    result = SG.judge(root, root / ".autoport", record=False)
    assert result["verdict"] == "refuse"
    assert result["failed"] == 1
    assert result["refused_for"] == ["suite-temporaire-indisponible"]
    assert "ce travail-ci" not in result["reason"]
    assert result["unwaived_new"] == -1


def test_replay_stops_on_unavailable_storage(tmp_path, monkeypatch):
    root = tmp_path / "repo"
    node = seed(root, tmp_path / "unused.jsonl")

    def unavailable(*args):
        raise SG.SuiteTemporaryUnavailable("suite-temporaire-indisponible: quota du banc")

    monkeypatch.setattr(SG, "_run_pytest", unavailable)
    result, info = SG.replay(str(root), ["HEAD", "revision-inexistante"], [node])
    assert info["ran"] == 0
    assert info["error"].startswith("suite-temporaire-indisponible:")
    assert result["revision-inexistante"] == {}
    assert not Path(info["worktree"]).exists()


def test_replay_cleans_when_git_cleanup_raises(tmp_path, monkeypatch):
    root = tmp_path / "repo"
    node = seed(root, tmp_path / "paths.jsonl")
    original = subprocess.run

    def fail_cleanup(command, **kwargs):
        if command[3:5] == ["worktree", "remove"]:
            raise subprocess.TimeoutExpired(command, 120)
        return original(command, **kwargs)

    monkeypatch.setattr(subprocess, "run", fail_cleanup)
    _, info = SG.replay(str(root), ["HEAD"], [node])
    assert "nettoyage worktree" in info["error"]
    assert not Path(info["worktree"]).exists()
    listing = original(["git", "-C", str(root), "worktree", "list", "--porcelain"],
                       check=True, capture_output=True, text=True).stdout
    assert info["worktree"] not in listing
