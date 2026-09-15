"""Garde de production et rejeu du banc synthétique livré, sans appareil."""
from pathlib import Path
import subprocess
import shutil

import pytest

from shrub_contact_contract_fixture import SOURCE

ROOT = Path(__file__).resolve().parents[3]


def test_delivered_sources():
    from shrub_contact_local import check_sources
    assert check_sources(ROOT) == []


@pytest.mark.parametrize("relative,before,after", [
    ("background/Shrub.cpp", "if (trunk) {", "if (false) {"),
    ("background/Shrub.cpp", "carried ? si.contact_pin_y : si.base_y",
     "carried ? si.base_y : si.base_y"),
    ("shaders/shrub.vert", "if (!carried || dy > 0.0)", "if (true)"),
    ("shaders/tie_sway.glsl", "max(0.0, original.y - attachment.x)",
     "original.y - anchor.y"),
    ("background/foliage_wind.cpp",
     "target.si->contact_pin_y = std::max(target.si->contact_pin_y, ymax->second)",
     "target.si->contact_pin_y = target.si->base_y"),
])
def test_production_regression_rejected(tmp_path, relative, before, after):
    from shrub_contact_local import check_sources
    # Only source copies change; no shader mutation reaches the owner or the live tree.
    prefix = Path("game/graphics/opengl_renderer")
    paths = ["background/Shrub.cpp", "background/Tie3.cpp", "background/foliage_wind.cpp",
             "loader/LoaderStages.cpp", "loader/Loader.cpp",
             "shaders/shrub.vert", "shaders/tie_sway.glsl"]
    for path in paths:
        target = tmp_path / prefix / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / prefix / path, target)
    target = tmp_path / prefix / relative
    original = target.read_text()
    assert before in original
    # Keep the removed text in a comment: comments must never rescue the guard.
    target.write_text(original.replace(before, after, 1) + "\n/* " + before + " */\n")
    defects = check_sources(tmp_path)
    assert defects, (relative, before)
    print(f"mutation={relative}:{before} rejected={len(defects)}")


def test_existing_contract(tmp_path):
    source = tmp_path / "contract.cpp"
    binary = tmp_path / "contract"
    source.write_text(SOURCE)
    build = subprocess.run([
        "c++", "-std=c++17", "-O0", "-UNDEBUG", "-I.", "-Ithird-party",
        "-Ithird-party/fmt/include", "-Ithird-party/SDL/include",
        "-Ithird-party/glad/include", str(source), "-o", str(binary),
    ], cwd=ROOT, text=True, capture_output=True, timeout=60)
    assert build.returncode == 0, build.stdout + build.stderr
    run = subprocess.run([str(binary)], text=True, capture_output=True, timeout=10)
    assert run.returncode == 0, run.stdout + run.stderr
    assert "case=trunk_motion expected=1 observed=1" in run.stdout
    assert "case=junction_motion expected=1 observed=1" in run.stdout
    assert "case=immobile expected=1 observed=1" in run.stdout
    print(run.stdout)
