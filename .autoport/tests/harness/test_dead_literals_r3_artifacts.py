"""Isolated byte-level checks; no production preprocessor is executed here."""

import hashlib
import json
from pathlib import Path

import pytest

from dead_literals_r3_artifacts import BLOB, compare_outputs, source_inventory


ARTIFACTS = {
    "tiny.android.vert": b"#version 320 es\nvoid main() { gl_Position = vec4(0.0); }\n",
    "tiny.android.frag": b"#version 320 es\nprecision highp float;\nout vec4 c;\nvoid main() { c = vec4(1.0); }\n",
    "shared.glsl": b"float shared_value() { return 1.0; }\n",
    BLOB: b"#pragma once\nnamespace gk_android_shaders { const char* chunk = \"float shared_value() { return 1.0; }\"; }\n",
}


@pytest.fixture
def outputs(tmp_path):
    before, after = tmp_path / "before", tmp_path / "after"
    for directory in (before, after):
        directory.mkdir()
        for name, data in ARTIFACTS.items():
            (directory / name).write_bytes(data)
    return before, after, sorted(ARTIFACTS)


def test_equal_outputs_measure_real_bytes(outputs):
    result = compare_outputs(*outputs)
    assert result["defects"] == result["divergences"] == 0
    assert result["issues"] == []
    assert result["files"] == len(ARTIFACTS)
    assert result["bytes"] == sum(map(len, ARTIFACTS.values()))
    assert result["sha256"] == hashlib.sha256(result["manifest"].encode()).hexdigest()
    rows = [json.loads(line) for line in result["manifest"].splitlines()]
    assert [row["name"] for row in rows] == sorted(ARTIFACTS)
    for row in rows:
        assert row["before"] == row["after"] == {
            "bytes": len(ARTIFACTS[row["name"]]),
            "sha256": hashlib.sha256(ARTIFACTS[row["name"]]).hexdigest(),
        }


@pytest.mark.parametrize("name", ARTIFACTS)
def test_each_category_changed_same_length_is_red(outputs, name):
    before, after, expected = outputs
    data = (after / name).read_bytes()
    (after / name).write_bytes(bytes([data[0] ^ 1]) + data[1:])
    result = compare_outputs(before, after, expected)
    assert result["divergences"] == result["defects"] == 1
    assert result["files"] == len(expected)


@pytest.mark.parametrize("name", ARTIFACTS)
@pytest.mark.parametrize("arm", [0, 1, "both"])
def test_missing_output_in_either_or_both_arms_is_red(outputs, name, arm):
    for directory in outputs[:2] if arm == "both" else [outputs[arm]]:
        (directory / name).unlink()
    result = compare_outputs(*outputs)
    assert result["defects"] == (2 if arm == "both" else 1)
    assert result["divergences"] == 0
    assert result["files"] == len(ARTIFACTS) - 1


@pytest.mark.parametrize("name", ARTIFACTS)
def test_empty_output_is_red(outputs, name):
    for directory in outputs[:2]:
        (directory / name).write_bytes(b"")
    result = compare_outputs(*outputs)
    assert result["defects"] == 2
    assert result["divergences"] == 0


def test_read_error_does_not_hide_later_divergence(outputs, monkeypatch):
    before, after, expected = outputs
    read_bytes = Path.read_bytes
    bad = before / "shared.glsl"

    def read(path):
        if path == bad:
            raise PermissionError("simulated denied read")
        return read_bytes(path)

    monkeypatch.setattr(Path, "read_bytes", read)
    (after / "tiny.android.vert").write_bytes(b"changed")
    result = compare_outputs(before, after, expected)
    assert result["defects"] == 2
    assert result["divergences"] == 1
    assert result["files"] == len(expected) - 1
    assert "PermissionError" in result["manifest"]


def test_non_file_output_is_red_and_other_pairs_are_counted(outputs):
    path = outputs[1] / "shared.glsl"
    path.unlink()
    path.mkdir()
    result = compare_outputs(*outputs)
    assert result["defects"] == 1
    assert result["files"] == len(ARTIFACTS) - 1
    assert result["bytes"] == sum(len(data) for name, data in ARTIFACTS.items()
                                    if name != path.name)


@pytest.mark.parametrize("expected", [[], [BLOB], ["shared.glsl"],
                                      ["tiny.android.vert"],
                                      [BLOB, "shared.glsl"],
                                      [BLOB, "tiny.android.vert"],
                                      ["shared.glsl", "tiny.android.vert"]])
def test_incomplete_expected_population_is_red(outputs, expected):
    assert compare_outputs(*outputs[:2], expected)["defects"] > 0


def test_no_bytes_compared_never_green(outputs):
    for directory in outputs[:2]:
        for name in ARTIFACTS:
            (directory / name).write_bytes(b"")
    result = compare_outputs(*outputs)
    assert result["bytes"] == 0
    assert result["defects"] > 0
    assert "no bytes compared" in result["issues"]


def test_only_dead_residue_removed_is_green(outputs):
    (outputs[0] / "dead.android.frag").write_bytes(b"dead shader")
    (outputs[0] / "dead.glsl").write_bytes(b"dead chunk")
    assert compare_outputs(*outputs)["defects"] == 0


def sources(tmp_path):
    directory = tmp_path / "sources"
    directory.mkdir()
    (directory / "shared.glsl").write_bytes(ARTIFACTS["shared.glsl"])
    (directory / "tiny.vert").write_bytes(b"#version 410 core\nvoid main() {}\n")
    return directory


def test_source_inventory_includes_orphans_all_stages_and_exact_content(tmp_path):
    directory = sources(tmp_path)
    for suffix in (".frag", ".tesc", ".tese"):
        (directory / f"orphan{suffix}").write_bytes(b"#version 410 core\nvoid main() {}\r\n")
    (directory / "ignored.txt").write_bytes(b"ignored")
    (directory / "nested").mkdir()
    (directory / "nested" / "ignored.vert").write_bytes(b"ignored")
    first = source_inventory(directory)
    assert first["sha256"] == hashlib.sha256(first["manifest"].encode()).hexdigest()
    assert first["expected"] == sorted([BLOB, "shared.glsl", "tiny.android.vert",
                                         "orphan.android.frag", "orphan.android.tesc",
                                         "orphan.android.tese"])
    assert first["files"] == 5
    assert first["bytes"] == sum(path.stat().st_size for path in directory.iterdir()
                                  if path.suffix in {".glsl", ".vert", ".frag", ".tesc", ".tese"})
    rows = [json.loads(line) for line in first["manifest"].splitlines()]
    for row in rows:
        assert row["sha256"] == hashlib.sha256((directory / row["name"]).read_bytes()).hexdigest()
    (directory / "tiny.vert").write_bytes(b"#version 410 core\nvoid main() { }\n")
    second = source_inventory(directory)
    assert first["sha256"] != second["sha256"]
    assert first["expected"] == second["expected"]


@pytest.mark.parametrize("kind", ["absent", "empty_dir", "no_chunk", "no_stage", "empty_file", "directory"])
def test_unusable_sources_raise(tmp_path, kind):
    directory = tmp_path / "absent" if kind == "absent" else sources(tmp_path)
    if kind in {"empty_dir", "no_chunk"}:
        (directory / "shared.glsl").unlink()
    if kind in {"empty_dir", "no_stage"}:
        (directory / "tiny.vert").unlink()
    if kind == "empty_file":
        (directory / "tiny.vert").write_bytes(b"")
    if kind == "directory":
        (directory / "bad.frag").mkdir()
    with pytest.raises((OSError, ValueError)):
        source_inventory(directory)


def test_unreadable_source_raises(tmp_path, monkeypatch):
    directory = sources(tmp_path)

    def denied(path):
        raise PermissionError("simulated unreadable source")

    monkeypatch.setattr(Path, "read_bytes", denied)
    with pytest.raises(PermissionError):
        source_inventory(directory)


def test_source_inventory_detects_producer_omission_in_both_arms(tmp_path, outputs):
    directory = sources(tmp_path)
    (directory / "orphan.tesc").write_bytes(b"#version 410 core\nvoid main() {}\n")
    expected = source_inventory(directory)["expected"]
    result = compare_outputs(*outputs[:2], expected)
    assert result["defects"] == 2
    assert any("orphan.android.tesc" in issue for issue in result["issues"])
