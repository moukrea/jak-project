"""What the orchestrator commits, and one full turn of the loop.

`git add -A` staged the WHOLE tree in every worker checkpoint, so everything the
supervisor wrote while a worker ran — journal, directives, milestones — landed
inside the worker's commit and its trace became invisible in the history. The
orchestrator now stages exactly the dirty paths, minus the harness's own state.
"""
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest
import yaml

# L'AUTORITE DE NOMMAGE des fichiers d'une course : la preuve d'un item est du TRAVAIL, pas de
# l'etat de harnais. Un nom reecrit ici ferait passer l'assertion sur un chemin que plus personne
# n'ecrit, et la liste d'exclusion pourrait avaler la vraie preuve sans que le test bronche.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
import impossible as NOMS  # noqa: E402

from test_selection import FAKE_BACKLOG, _items


def _git(root, *args):
    return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True)


@pytest.fixture()
def repo(orch, sandbox):
    root = sandbox
    _git(root, "init", "-q", "-b", "main")
    _git(root, "config", "user.email", "t@t")
    _git(root, "config", "user.name", "t")
    (root / "seed.txt").write_text("seed\n")
    _git(root, "add", "seed.txt")
    _git(root, "commit", "-qm", "seed")
    return root


def test_harness_state_is_never_part_of_a_worker_commit(orch, repo):
    (repo / "game" ).mkdir()
    (repo / "game" / "fix.cpp").write_text("// the worker's work\n")
    (orch.AUTOPORT_DIR / "DIRECTIVES.md").write_text("the supervisor narrowed the scope\n")
    orch.STATE_PATH.write_text('{"version": 0}')
    (orch.AUTOPORT_DIR / "logs" / "noise.log").write_text("orchestrator chatter\n")

    paths = orch.worker_paths()
    assert "game/fix.cpp" in paths
    for harness in (".autoport/DIRECTIVES.md", ".autoport/state.json",
                    ".autoport/logs/noise.log"):
        assert harness not in paths, f"{harness} belongs to the supervisor, not the worker"

    assert orch.git_commit_paths("demo", "WIP", paths) is True
    show = _git(repo, "show", "--name-only", "--format=", "HEAD").stdout.split()
    assert show == ["game/fix.cpp"]

    still_dirty = _git(repo, "status", "--porcelain", "-uall").stdout
    assert "DIRECTIVES.md" in still_dirty, \
        "the supervisor's edit must survive the worker's commit, uncommitted"


def test_an_item_with_the_right_carries_directives_in_its_checkpoint(orch, monkeypatch):
    """harness-directives-promises-are-implemented : DIRECTIVES.md suit le checkpoint de l'item
    qui en a le DROIT declare (`harness_writes`), et de lui seul ; state.json jamais."""
    monkeypatch.setattr(orch, "dirty_paths", lambda *a, **k: [
        ".autoport/DIRECTIVES.md", ".autoport/state.json", "game/x.cpp"])
    right = {"id": "x", "harness_writes": [".autoport/DIRECTIVES.md", ".autoport/state.json"]}
    paths = orch.worker_paths(right)
    assert ".autoport/DIRECTIVES.md" in paths and "game/x.cpp" in paths
    assert ".autoport/state.json" not in paths
    assert ".autoport/DIRECTIVES.md" not in orch.worker_paths()


def test_nothing_to_commit_is_not_an_error(orch, repo):
    assert orch.git_commit_paths("demo", "WIP", []) is False
    assert orch.git_commit_paths("demo", "WIP", ["does/not/exist"]) is False


def test_renames_are_staged_on_both_sides(orch, repo):
    (repo / "a.txt").write_text("x\n")
    _git(repo, "add", "a.txt")
    _git(repo, "commit", "-qm", "a")
    _git(repo, "mv", "a.txt", "b.txt")
    paths = orch.worker_paths()
    assert {"a.txt", "b.txt"} <= set(paths)


def test_the_exclusion_list_is_prefix_aware(orch):
    for harness in (".autoport/state.json", ".autoport/backlog.yaml",
                    ".autoport/.orchestrator.lock", ".autoport/logs/x/y.jsonl",
                    ".autoport/owner-ok/an-item", ".autoport/.phase-claim.an-item",
                    ".autoport/prompts/item-x.md", ".autoport/archive/journal-05.md"):
        assert orch._is_harness_state(harness), harness
    for work in ("game/fix.cpp", "goal_src/jak1/pc/phys-room.gc",
                 ".autoport/reports/demo/" + NOMS.arm_name("proof", ""), ".autoport/validators/generic.sh",
                 ".autoport/lib/proof_run.sh"):
        assert not orch._is_harness_state(work), work


# ---------------------------------------------------------------------------
# One full turn: select -> in-progress -> attempt -> verdict, no cursor at all.
# ---------------------------------------------------------------------------

def test_a_full_turn_marks_in_progress_then_records_the_verdict(orch, repo, monkeypatch):
    import sys
    from test_attempt import _fake_claude, _WORKS_THEN_EXITS

    lib = orch.AUTOPORT_DIR / "lib"
    lib.mkdir(parents=True, exist_ok=True)
    (lib / "backlog.py").write_text(textwrap.dedent(FAKE_BACKLOG))
    monkeypatch.setenv("FAKE_BACKLOG_PATH", str(orch.BACKLOG_PATH))
    monkeypatch.delitem(sys.modules, "backlog", raising=False)
    orch.BACKLOG_PATH.write_text(yaml.safe_dump(
        {"version": 1, "items": _items({"id": "demo", "max_retries": 1})},
        allow_unicode=True))

    (orch.AUTOPORT_DIR / "prompts").mkdir(parents=True, exist_ok=True)
    (orch.AUTOPORT_DIR / "prompts" / "item-demo.md").write_text("Fais la chose.\n")
    orch.GENERIC_VALIDATOR.write_text(
        "#!/usr/bin/env bash\necho \"[$AUTOPORT_PHASE_ID FAIL] pas prouvé\"\nexit 1\n")
    orch.GENERIC_VALIDATOR.chmod(0o755)

    creds = orch.AUTOPORT_DIR / "creds.json"
    creds.write_text("{}")
    monkeypatch.setattr(orch, "CREDENTIALS_PATH", creds)

    monkeypatch.setattr(orch, "build_instructions", lambda item, seq: "prompt\n")
    monkeypatch.setattr(orch, "READ_POLL_SEC", 0.2)
    _fake_claude(orch, _WORKS_THEN_EXITS)

    assert orch.main([]) == 0

    # the fake backlog records every set_status call (it survives the reload
    # the orchestrator does at each turn, which a monkeypatched class does not)
    calls = (orch.BACKLOG_PATH.parent / (orch.BACKLOG_PATH.name + ".calls")).read_text()
    assert "demo in-progress" in calls, "an item must be claimed while it runs"
    assert calls.strip().splitlines()[-1] == "demo blocked", \
        "and the claim must be replaced by a verdict at the end of the attempt"
    final = orch.load_backlog().get("demo")
    assert final["status"] == "blocked"
    assert "max_retries" in final["block_reason"]
    assert orch.load_state()["retries"]["demo"] == 1

    # the validator ran once, under the orchestrator, with the item id exported
    vlog = (orch.LOG_ROOT / "demo" / "validator-001.txt").read_text()
    assert "[demo FAIL]" in vlog


def test_the_shield_prohibition_refuses_the_start(orch, sandbox, monkeypatch):
    """Owner, 2026-08-30: « Interdit de toucher a la SHIELD a nouveau. Assures toi
    que vraiment rien n'y touche. » The check used to live in preflight, where it
    broke the module's contract (adb, not "under a second") and finally killed it.
    Here it is what it should be: a refusal to start, evaluated once."""
    creds = orch.AUTOPORT_DIR / "creds.json"
    creds.write_text("{}")
    monkeypatch.setattr(orch, "CREDENTIALS_PATH", creds)
    (orch.AUTOPORT_DIR / "lib").mkdir(parents=True, exist_ok=True)
    orch.BACKLOG_LIB.write_text("# stub\n")
    orch.BACKLOG_PATH.write_text("version: 1\nitems: []\n")
    orch.GENERIC_VALIDATOR.write_text("#!/usr/bin/env bash\nexit 0\n")

    orch.SHIELD_GUARD.write_text(
        "#!/usr/bin/env bash\necho '[SHIELD-GUARD FAIL] elle est branchee' >&2\nexit 1\n")
    assert "SHIELD" in orch._startup_refusals()

    orch.SHIELD_GUARD.write_text("#!/usr/bin/env bash\nexit 0\n")
    assert orch._startup_refusals() == ""


def test_le_frein_pause_est_celui_du_depot_pilote(orch, repo, monkeypatch):
    """Le `PAUSE` que le tour lit est celui du depot qu'il PILOTE, pas celui du fichier source.

    LE DEFAUT, mesure le 2026-09-16. `main()` lisait
    `Path(__file__).resolve().parent / "PAUSE"` : le VRAI `.autoport/`, quoi que
    `conftest.py` ait repointe. Un `touch .autoport/PAUSE` de l'owner — pose a 19:22 ce
    jour-la — arretait donc le tour du BANC : `set_status` n'etait jamais appele et
    `test_a_full_turn_marks_in_progress_then_records_the_verdict` mourait sur un
    `FileNotFoundError` de `backlog.yaml.calls`. Verifie sur quatre jambes, dans deux
    worktrees jetables : sans PAUSE il passe, avec PAUSE il echoue — A L'IDENTIQUE a
    79854ea0e5 et a ca49b3b059, qui ne porte pas une ligne de l'item accuse.

    CE QUE CA COUTAIT. La porte de fermeture rejoue un rouge a la base DANS UN WORKTREE,
    ou `PAUSE` — gitignore — n'existe jamais : vert a la base, rouge a HEAD, elle impute
    le rouge au travail juge. Un essai perdu pour un fichier de l'owner.

    CE TEST-CI EST LA JAMBE QUI FALSIFIE. Il pose le frein dans le bac a sable et exige
    que le tour s'arrete. Sous l'ancien code, ce frein-la est INVISIBLE — le tour part,
    reclame l'item, et l'assertion tombe. Il ne touche pas au vrai arbre : c'est
    precisement ce qu'on vient de rendre impossible.
    """
    import sys
    from test_attempt import _fake_claude, _WORKS_THEN_EXITS

    lib = orch.AUTOPORT_DIR / "lib"
    lib.mkdir(parents=True, exist_ok=True)
    (lib / "backlog.py").write_text(textwrap.dedent(FAKE_BACKLOG))
    monkeypatch.setenv("FAKE_BACKLOG_PATH", str(orch.BACKLOG_PATH))
    monkeypatch.delitem(sys.modules, "backlog", raising=False)
    orch.BACKLOG_PATH.write_text(yaml.safe_dump(
        {"version": 1, "items": _items({"id": "demo", "max_retries": 1})},
        allow_unicode=True))

    (orch.AUTOPORT_DIR / "prompts").mkdir(parents=True, exist_ok=True)
    (orch.AUTOPORT_DIR / "prompts" / "item-demo.md").write_text("Fais la chose.\n")
    orch.GENERIC_VALIDATOR.write_text("#!/usr/bin/env bash\nexit 0\n")
    orch.GENERIC_VALIDATOR.chmod(0o755)

    creds = orch.AUTOPORT_DIR / "creds.json"
    creds.write_text("{}")
    monkeypatch.setattr(orch, "CREDENTIALS_PATH", creds)
    monkeypatch.setattr(orch, "build_instructions", lambda item, seq: "prompt\n")
    monkeypatch.setattr(orch, "READ_POLL_SEC", 0.2)
    _fake_claude(orch, _WORKS_THEN_EXITS)

    # LE FREIN, DANS LE BAC A SABLE — nulle part ailleurs.
    (orch.AUTOPORT_DIR / "PAUSE").write_text("frein de l'owner\n")

    assert orch.main([]) == 0, "un frein pose n'est pas une erreur : le tour s'arrete, il ne casse pas"

    calls = orch.BACKLOG_PATH.parent / (orch.BACKLOG_PATH.name + ".calls")
    assert not calls.exists(), (
        "le frein du depot pilote a ete IGNORE : le tour a reclame un item malgre "
        f".autoport/PAUSE dans le bac a sable ({calls.read_text() if calls.exists() else ''})")
    assert orch.load_backlog().get("demo")["status"] == "open", \
        "l'item doit rester intact : le frein arrete AVANT la selection"
