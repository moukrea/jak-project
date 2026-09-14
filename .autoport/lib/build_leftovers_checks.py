#!/usr/bin/env python3
"""Ten bounded, reproducible detectors for build-and-harness-leftovers.

Source baseline is the commit inherited by this attempt. Runtime-before is an
inventory captured before quarantine, not a reconstruction of old disk contents.
The original corrupt Ninja log is retained byte-for-byte in gzip form.
"""
import gzip
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile

from build_leftovers_build_checks import FILES, detect
from build_leftovers_scope_checks import run_checks
from build_orphans import inventory

ROOT = Path(__file__).resolve().parents[2]
BASELINE = "30f3a9b540881303d31f3b93862275ada159fcdc"
CAPTURE = ROOT / ".autoport/lib/census/capture-build-and-harness-leftovers"
# Literal paths also let verdict_sources.sh follow Python imports and the seven
# scripts whose names the build detector otherwise assembles dynamically.
DETECTOR_FILES = (
    ".autoport/lib/build_leftovers_build_checks.py",
    ".autoport/lib/build_leftovers_scope_checks.py",
    ".autoport/lib/build_orphans.py",
    ".autoport/lib/d1_build.sh", ".autoport/lib/d3_build.sh",
    ".autoport/lib/c2_run.sh", ".autoport/lib/c3_run.sh", ".autoport/lib/c4_run.sh",
    ".autoport/lib/qemu_repro.sh", ".autoport/lib/emitter_stress.sh",
)


def read(path, revision=None):
    if revision is None:
        return (ROOT / path).read_text()
    return subprocess.run(["git", "show", f"{revision}:{path}"], cwd=ROOT,
                          check=True, capture_output=True, text=True).stdout


def run(args, **kwargs):
    return subprocess.run(args, cwd=ROOT, text=True, capture_output=True, **kwargs)


def ignore_check(revision):
    with tempfile.TemporaryDirectory(prefix="leftovers-ignore-") as temp:
        root = Path(temp)
        run(["git", "init", "-q", str(root)], check=True)
        (root / ".gitignore").write_text(read(".gitignore", revision))
        ignored = {}
        for path in ("build-example/result.txt", "examples/build-example/result.txt"):
            result = run(["git", "-C", str(root), "check-ignore", "--no-index", path])
            if result.returncode not in (0, 1):
                raise RuntimeError(result.stderr)
            ignored[path] = int(result.returncode == 0)
        return {"defects": int(ignored["examples/build-example/result.txt"] != 0
                                or ignored["build-example/result.txt"] != 1), **ignored}


def orphan_check(revision):
    """Same door/fixture and same graph-minus-disk detector for each revision."""
    with tempfile.TemporaryDirectory(prefix="leftovers-orphans-") as temp:
        tree = Path(temp)
        obj = "game/CMakeFiles/runtime.dir/live.c.o"
        orphan = "game/CMakeFiles/runtime.dir/retired.c.o"
        (tree / obj).parent.mkdir(parents=True)
        (tree / orphan).write_bytes(b"retired object to preserve\n")
        (tree / "live.c").write_text("int main(void) { return 0; }\n")
        (tree / "build.ninja").write_text(
            "rule cc\n  command = cc -MD -MF $out.d -c $in -o $out\n"
            "  depfile = $out.d\n  deps = gcc\n  description = Building $out\n"
            "rule link\n  command = cc $in -o $out\n  description = Linking $out\n"
            f"build {obj}: cc live.c\nbuild app: link {obj}\n")
        before = inventory(tree)
        if revision:
            door = tree / "build_x86.sh"
            door.write_text(read(".autoport/lib/build_x86.sh", revision))
            (tree / "freshness.sh").write_text(read(".autoport/lib/freshness.sh", revision))
        else:
            door = ROOT / ".autoport/lib/build_x86.sh"
        built = run(["bash", str(door), "--dir", str(tree), "--target", "app", "-j", "1"])
        after = inventory(tree)
        quarantined = list((tree / ".orphan-objects").glob("*/" + orphan))
        preserved = int(len(quarantined) == 1 and
                        quarantined[0].read_bytes() == b"retired object to preserve\n")
        return {"defects": int(built.returncode != 0 or after["orphan_count"] != 0
                                or not preserved or not (tree / obj).exists()),
                "door_rc": built.returncode, "before": before["orphan_count"],
                "after": after["orphan_count"], "quarantine_preserved": preserved,
                "door_log": built.stdout + built.stderr}


def gain_check(revision):
    source = read(".autoport/lib/census/build-tree-reinvalidates-itself.sh", revision)
    # Exercise the actual gain block with identical measurements, varying only
    # the historical capture. It must use this run's bench, even when that old
    # reference is slower/faster. These are probe inputs, never claimed timings.
    start = source.index("AVMIN=-1")
    end = source.index("# CE SUR QUOI LE", start)
    block = source[start:end]
    verdicts = []
    for historical in (1, 1000):
        script = '''
set -eu
num(){ echo "$1"; }
g(){ echo 2; }
b(){ case "$1" in
bf_c_rebuild_rc|bf_c_noop_rc) echo 0;;
bf_c_gain_population_objets) echo 4;;
bf_c_rebuild_ns) echo 100000000;;
bf_c_noop_ns) echo 1000000;; *) echo -1;; esac; }
pub(){ :; }
A1S=$1; A2S=$1; P1=x; P2=x; P3=x; INV=x
''' + block + '\nprintf "%s\\n" "$D4"\n'
        result = run(["bash", "-c", script, "gain-probe", str(historical)], check=True)
        verdicts.append(int(result.stdout.strip()))
    return {"defects": int(verdicts != [0, 0]), "historical_variants_verdicts": verdicts,
            "live_reference": "bf_c_rebuild_ns" in block and "bf_c_noop_ns" in block}


def inspect_deps(raw):
    """Forensic v4 reader, not a replacement for Ninja's production loader.

    Format/checksum: https://raw.githubusercontent.com/ninja-build/ninja/v1.13.1/src/deps_log.cc
    """
    names, seen, offset, problem = [], {}, 16, None
    if raw[:16] != b"# ninjadeps\n\x04\0\0\0":
        problem = {"kind": "header", "offset": 0}
    while problem is None and offset < len(raw):
        if offset + 4 > len(raw):
            problem = {"kind": "truncated_size", "offset": offset}
            break
        size = struct.unpack_from("<I", raw, offset)[0]
        length = size & 0x7fffffff
        end = offset + 4 + length
        if length > 524287 or end > len(raw):
            problem = {"kind": "record_length", "offset": offset}
            break
        rec = raw[offset + 4:end]
        if size & 0x80000000:
            if length < 12 or length % 4:
                problem = {"kind": "deps_size", "offset": offset}
                break
            ids = struct.unpack("<" + "I" * (length // 4), rec)
            if any(i >= len(names) for i in [ids[0], *ids[3:]]):
                problem = {"kind": "deps_id", "offset": offset}
                break
        else:
            if length <= 4:
                problem = {"kind": "path_size", "offset": offset}
                break
            name = rec[:-4].rstrip(b"\0")
            stored = (~struct.unpack_from("<I", rec, length - 4)[0]) & 0xffffffff
            if stored != len(names) or name in seen:
                problem = dict(kind="path_id_or_duplicate", offset=offset, end=end,
                               stored_id=stored, expected_id=len(names), previous_id=seen.get(name),
                               path=name.decode(errors="replace"))
                break
            seen[name] = len(names)
            names.append(name)
        offset = end
    return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(), "problem": problem}


def measurements():
    before, after = {}, {}
    for revision, results in ((BASELINE, before), (None, after)):
        scope = run_checks(ROOT, revision)
        for point in (1, 2, 8):
            results[point] = scope[f"point_{point}"]
        with tempfile.TemporaryDirectory(prefix="leftovers-sources-") as temp:
            root = ROOT
            if revision:
                root = Path(temp)
                for filename in FILES:
                    if filename == ".autoport/lib/build_arm64.sh":
                        continue  # New door did not exist in the inherited commit.
                    target = root / filename
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text(read(filename, revision))
            build = detect(root)
            for point in (3, 6, 7):
                results[point] = build[f"point{point}"]
                results[point]["defects"] = results[point].pop("defect")
        results[4] = ignore_check(revision)
        results[5] = orphan_check(revision)
        results[9] = gain_check(revision)
    disk_before = json.loads((CAPTURE / "runtime-before.json").read_text())
    disk_after = inventory(ROOT / "build")
    old_deps = inspect_deps(gzip.decompress((CAPTURE / "ninja_deps.before.gz").read_bytes()))
    live_deps = inspect_deps((ROOT / "build/.ninja_deps").read_bytes())
    before[10] = {"defects": int(old_deps["problem"] is not None), **old_deps}
    after[10] = {"defects": int(live_deps["problem"] is not None), **live_deps}
    bench = run(["bash", ".autoport/lib/build_freshness_selftest.sh"])
    bench_values = dict(line.split("=", 1) for line in bench.stdout.splitlines() if "=" in line)
    return {"baseline": BASELINE, "before": before, "after": after,
            "detector_sources_sha256": hashlib.sha256(b"".join(
                (ROOT / name).read_bytes() for name in DETECTOR_FILES)).hexdigest(),
            "disk_before": disk_before, "disk_after": disk_after,
            "bench_rc": bench.returncode, "bench": bench_values,
            "bench_stderr": bench.stderr}


def publish(data):
    def pub(key, value):
        print(f"{key}={'_'.join(str(value).split())}")
    pub("bl_baseline_ref", data["baseline"])
    pub("bl_detector_sources_sha256", data["detector_sources_sha256"])
    total = 0
    for point in range(1, 11):
        old, new = data["before"][point], data["after"][point]
        reproduced = old["defects"] > 0
        defect = int(not reproduced or new["defects"] != 0)
        if point == 5:
            defect += int(not data["disk_before"]["orphan_count"] or data["disk_after"]["orphan_count"] != 0)
        if point == 9:
            bench = data["bench"]
            defect += int(data["bench_rc"] != 0 or
                          bench.get("bf_c_rebuild_rc") != "0" or bench.get("bf_c_noop_rc") != "0" or
                          int(bench.get("bf_c_gain_population_objets", -1)) <= 0 or
                          int(bench.get("bf_c_rebuild_ns", -1)) <= int(bench.get("bf_c_noop_ns", -1)) or
                          int(bench.get("bf_c_noop_ns", -1)) <= 0)
        total += defect
        pub(f"bl_before_{point}", old["defects"])
        pub(f"bl_after_{point}", new["defects"])
        pub(f"bl_defect_{point}", defect)
        status = "NON_REPRODUIT" if not reproduced else ("corrige" if defect == 0 else "reste_defaut")
        if point == 10 and reproduced:
            status = "cause_non_etablie"  # Explicit exception in the contract, never 'fixed'.
        pub(f"bl_status_{point}", status)
    pub("bl_scope_contradictions", data["after"][1]["live_contradictions_count"])
    pub("bl_scope_contradiction_ids", ",".join(c["id"] for c in data["after"][1]["live_contradictions"]) or "aucun")
    pub("bl_runtime_orphans_before", data["disk_before"]["orphan_count"])
    pub("bl_runtime_orphans_after", data["disk_after"]["orphan_count"])
    pub("bl_runtime_graph_objects", data["disk_after"]["graph_count"])
    pub("bl_gain_reference", "banc_C_cette_course_4_objets_pas_le_jeu")
    for key in ("bf_c_rebuild_ns", "bf_c_noop_ns", "bf_c_gain_population_objets"):
        pub("bl_" + key, data["bench"].get(key, -1))
    problem = data["before"][10]["problem"] or {}
    pub("bl_deps_capture_sha", data["before"][10]["sha256"])
    pub("bl_deps_live_sha", data["after"][10]["sha256"])
    pub("bl_deps_bad_offset", problem.get("offset", -1))
    pub("bl_deps_stored_id", problem.get("stored_id", -1))
    pub("bl_deps_expected_id", problem.get("expected_id", -1))
    pub("bl_origin_excluded_as_sole_cause", "simple_queue_tronquee_ne_suffit_pas_au_doublon_complet")
    pub("bl_origin_possible", "Ninja_concurrents;copie_restauration;ecriture_externe;incident_IO_non_exclu")
    pub("bl_origin_writer_identified", 0)
    pub("build_leftovers_defects", total)


if __name__ == "__main__":
    data = measurements()
    notes = ROOT / ".autoport/reports/build-and-harness-leftovers/notes"
    notes.mkdir(parents=True, exist_ok=True)
    (notes / "detectors.json").write_text(json.dumps(data, indent=2, ensure_ascii=False))
    publish(data)
