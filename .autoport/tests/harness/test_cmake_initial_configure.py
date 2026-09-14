"""Exercise the real pre-tool guard; never run CMake or touch a device."""
import json
from pathlib import Path
import shlex
import subprocess

import pytest

HOOK = Path(__file__).resolve().parents[2] / "hooks" / "pre-tool.sh"


def guard(command):
    return subprocess.run(
        ["bash", str(HOOK)], input=json.dumps({"tool_name": "Bash",
        "tool_input": {"command": command}}), text=True, capture_output=True
    ).returncode


@pytest.fixture
def checkout(tmp_path):
    source = tmp_path / "reference with spaces"
    source.mkdir()
    (source / "CMakeLists.txt").write_text("project(reference)\n")
    return source, source / "build-android"


@pytest.mark.parametrize("existing_empty", [False, True])
@pytest.mark.parametrize("joined", [False, True])
def test_first_configuration_allowed(checkout, existing_empty, joined):
    source, build = checkout
    if existing_empty:
        build.mkdir()
    separator = "" if joined else " "
    command = (f"cmake -S{separator}{shlex.quote(str(source))} "
               f"-B{separator}{shlex.quote(str(build))} -G Ninja "
               "-DCMAKE_BUILD_TYPE=RelWithDebInfo -DANDROID_ABI=arm64-v8a")
    assert guard(command) == 0
    assert build.exists() == existing_empty


@pytest.mark.parametrize("contents", ["CMakeCache.txt", ".ninja_deps", "objects"])
@pytest.mark.parametrize("alias", [False, True])
def test_existing_build_protected(checkout, contents, alias):
    source, build = checkout
    build.mkdir()
    (build / contents).write_text("existing build\n")
    target = build
    if alias:
        target = source / "alias"
        target.symlink_to(build, target_is_directory=True)
    assert guard(f"cmake -S {shlex.quote(str(source))} -B {shlex.quote(str(target))}") == 2
    assert (build / contents).read_text() == "existing build\n"


@pytest.mark.parametrize("suffix", [
    "-B build", "-Bbuild", "-B=build", "-B $BUILD_DIR", "-B /tmp/x --preset other",
    "-B /tmp/x -B /tmp/y", "-B /tmp/x && true", "-B /tmp/x > /tmp/log",
])
def test_ambiguous_or_relative_commands_stay_blocked(checkout, suffix):
    source, _ = checkout
    assert guard(f"cmake -S {shlex.quote(str(source))} {suffix}") == 2


def test_missing_source_and_in_source_build_blocked(checkout):
    source, build = checkout
    assert guard(f"cmake -B {shlex.quote(str(build))}") == 2
    assert guard(f"cmake -S {shlex.quote(str(source))} -B {shlex.quote(str(source))}") == 2


def test_other_build_guards_unchanged():
    assert guard("cmake --build build") == 2
    assert guard("ninja -C build gk") == 2
    assert guard("cmake --build build-android --target gk") == 0
