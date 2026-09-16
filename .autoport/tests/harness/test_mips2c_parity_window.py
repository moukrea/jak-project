"""Exercise the production parity window without building or launching the game."""

import json
from pathlib import Path
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[3]

PREAMBLE = r'''
#include <cstdint>
#include <iostream>
#include <map>
#include <string>
#include "game/mips2c/vu_simd_state.h"
#define AUTOPORT_FEATURE_SITE(item)
namespace autoport_proof {
std::map<std::string, uint64_t> values;
bool refset_present = true;
uint64_t refset_diff = 0, hits = 0;
bool armed_for(const char*) { return true; }
bool feature_is(const char*) { return true; }
bool read_uint(const char*, uint64_t& value) {
  value = refset_diff;
  return refset_present;
}
void publish(const char* key, uint64_t value) { values[key] = value; }
void note_hit_for(const char*) { ++hits; }
}
'''

DRIVER = r'''
using namespace Mips2C::vu_simd;
void step(unsigned mask, uint64_t mismatches = 0) {
  for (unsigned i = 0; i < 3; ++i) {
    auto kernel = static_cast<Kernel>(i);
    if ((mask & (1u << i)) && settings(kernel).verify) {
      record(kernel, 1, mismatches);
    }
  }
  frame_boundary();
}
void snapshot(const char* label) {
  std::cout << "{\"label\":\"" << label << "\",\"verify\":"
            << settings(Kernel::Collide).verify << ",\"hits\":" << autoport_proof::hits;
  for (const auto& [key, value] : autoport_proof::values) {
    std::cout << ",\"" << key << "\":" << value;
  }
  std::cout << "}\n";
}
int main(int argc, char** argv) {
  if (argc != 2) return 2;
  const std::string scenario = argv[1];
  if (scenario == "sparse") {
    step(7);
    for (int i = 0; i < 599; ++i) step(2);
    snapshot("sparse");
  } else if (scenario == "inactive" || scenario == "missing") {
    for (int i = 0; i < 600; ++i) step(scenario == "inactive" ? 0 : 3);
    snapshot("final");
  } else {
    autoport_proof::refset_present = scenario != "refset_absent";
    autoport_proof::refset_diff = scenario == "refset_nonzero" ? 233 : 0;
    for (int i = 0; i < 599; ++i) step(7, scenario == "mismatch" && i == 0 ? 1 : 0);
    // Publication occurs every 60 boundaries. Flush with no new comparisons.
    step(0);
    snapshot("599");
    step(7);
    for (int i = 0; i < 59; ++i) step(0);
    snapshot("600");
    for (int i = 0; i < 60; ++i) step(7);
    snapshot("after_oracle_off");
  }
}
'''


@pytest.fixture(scope="module")
def parity_executable(tmp_path_factory):
    source = (ROOT / "game/system/perf_instruments.cpp").read_text()
    start = source.index("namespace Mips2C::vu_simd {")
    closing = "}  // namespace Mips2C::vu_simd"
    end = source.index(closing, start) + len(closing)
    work = tmp_path_factory.mktemp("mips2c-parity")
    cpp = work / "parity.cpp"
    executable = work / "parity"
    cpp.write_text(PREAMBLE + source[start:end] + DRIVER)
    subprocess.run(
        ["c++", "-std=c++17", "-Wall", "-Wextra", "-Werror", "-I", str(ROOT),
         str(cpp), "-o", str(executable)],
        check=True, capture_output=True, text=True,
    )
    return executable


def run_scenario(executable, scenario):
    result = subprocess.run([str(executable), scenario], check=True, capture_output=True, text=True)
    print(f"scenario={scenario}\n{result.stdout}", end="")
    return [json.loads(line) for line in result.stdout.splitlines()]


def test_sparse_frames_do_not_exhaust_oracle(parity_executable):
    row, = run_scenario(parity_executable, "sparse")
    assert row["mips2c_parity_frames"] == 1
    assert row["mips2c_warmup_frames"] == 599
    assert row["mips2c_collide_frames"] == row["mips2c_particles_frames"] == 1
    assert row["mips2c_joints_frames"] == row["hits"] == 600
    assert row["verify"] == 1
    assert row["mips2c_parity_defects"] > 0


@pytest.mark.parametrize("scenario,active,warmup,missing", [
    ("inactive", 0, 0, 3), ("missing", 600, 600, 1),
])
def test_unqualified_frames(parity_executable, scenario, active, warmup, missing):
    row, = run_scenario(parity_executable, scenario)
    assert row["mips2c_parity_frames"] == 0
    assert row["mips2c_warmup_frames"] == warmup
    assert row["hits"] == active
    assert row["mips2c_missing_kernels"] == missing
    assert row["verify"] == row["mips2c_parity_incomplete"] == 1
    assert row["mips2c_parity_defects"] > 0


@pytest.mark.parametrize("scenario,gate,bit_defects,present", [
    ("complete", 0, 0, 1), ("mismatch", 3, 3, 1),
    ("refset_absent", 1, 0, 0), ("refset_nonzero", 1, 0, 1),
])
def test_qualified_window_and_persistent_gate(parity_executable, scenario, gate, bit_defects, present):
    before, complete, later = run_scenario(parity_executable, scenario)
    assert before["mips2c_parity_frames"] == 599
    assert before["verify"] == before["mips2c_parity_incomplete"] == 1
    assert before["mips2c_parity_defects"] > 0
    for row in (complete, later):
        assert row["mips2c_parity_frames"] == row["hits"] == 600
        assert row["mips2c_warmup_frames"] == row["verify"] == 0
        assert row["mips2c_missing_kernels"] == 0
        assert row["mips2c_bit_defects"] == bit_defects
        assert row["mips2c_refset_present"] == present
        assert row["mips2c_parity_incomplete"] == (not present)
        assert row["mips2c_parity_defects"] == gate
        for kernel in ("collide", "joints", "particles"):
            assert row[f"mips2c_{kernel}_frames"] == 600
            assert row[f"mips2c_{kernel}_compared_ops"] == 600
