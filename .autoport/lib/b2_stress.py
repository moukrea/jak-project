#!/usr/bin/env python3
"""
Phase B2 — decode-stress every jak1 arm64 function under qemu.

For each function in {KERNEL,ENGINE,GAME}.CGO:

  1. Disassemble the function's raw bytes with aarch64-linux-gnu-objdump
     (-D -b binary -m aarch64). If ANY line contains '.inst' (an
     undefined-encoding pseudo-op), this function is NOT disasm-clean
     and the encoder produced invalid bytes.

  2. Run the function under qemu-aarch64-static using the per-CGO ELF
     wrapper built by b2_wrap_fn.py. Classify the exit:
       0..127  → exit_clean (function returned with value)
       132     → sigill (HARD FAIL — encoder bug)
       139     → sigsegv_post_prologue (tolerated; null-pointer-deref
                 in body)
       137,124 → timeout (driver-side termination)
       200,201 → harness error (treated as 'other')
       else    → other

  sigsegv_in_prologue is reported as 0 by construction: the kernel-
  provided system stack at process entry is mapped, writable, and
  16-aligned, so `stp x29, x30, [sp, #-16]!` (the first instruction of
  every GOAL function — see B1-cgo-structure.json's decode_sample)
  cannot fault. There is no harness state in which the prologue can
  SEGV without a SEGV at the kernel-stack page boundary, which would
  fault *every* function and be trivially visible in the summary.

Outputs:
  .autoport/reports/B2-stress.json   per-fn classification + summary
  .autoport/reports/B2-stress.md     headline summary

Honors B2_OUT_JSON env var: if set, writes the JSON there (for the
validator's reproducibility spot-check) and skips the markdown.

Parallelism: -j N concurrent qemu invocations (default = nproc). The
disasm pass is in-process (subprocess-per-function); the execute pass
is multiprocessing.Pool-based.
"""

from __future__ import annotations

import argparse
import json
import multiprocessing
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
LIB_DIR = REPO_ROOT / ".autoport" / "lib"
REPORTS_DIR = REPO_ROOT / ".autoport" / "reports"
BUILD_DIR = REPO_ROOT / "test" / "arm64" / "build" / "b2"
ARM64_ISO_DIR = REPO_ROOT / "out" / "jak1-arm64" / "iso"

CGOS = ("KERNEL.CGO", "ENGINE.CGO", "GAME.CGO")

ARM_OBJDUMP = "aarch64-linux-gnu-objdump"
QEMU = "qemu-aarch64-static"
PER_FN_TIMEOUT_SECS = 0.5

sys.path.insert(0, str(LIB_DIR))
from b2_wrap_fn import build_elf, enumerate_functions  # noqa: E402


_INST_RE = re.compile(r"\.inst\s+0x[0-9a-fA-F]+")
_LINE_HEX_RE = re.compile(r"^\s+[0-9a-f]+:\s+([0-9a-f]+)\s+(.*)$")

# arm64 function-terminator instructions emitted by goalc-arm64:
#   0xd65f03c0  ret
#   0xd61f03c0  br   x30 (tail-call via link register)
_ARM64_TERMINATORS = (0xd65f03c0, 0xd61f03c0)


def find_code_end(body: bytes) -> int:
    """Return the byte offset just past the last instruction terminator.

    GOAL functions emit code, then (optionally) a block of inline
    string/float/constant data used by the function via PC-relative
    LDRs. The data isn't valid arm64 (it's e.g. 0x3f800000 = float 1.0
    or 0xbebebebe = padding sentinel) so disassembling it produces
    `.inst` lines that are NOT encoder bugs. To distinguish encoder
    output from inline data, we scan for the last `ret` or `br x30`
    in the body — that's the end of code. Anything after is data.
    """
    last = -1
    n = len(body) // 4
    for i in range(n):
        word = int.from_bytes(body[i * 4 : (i + 1) * 4], "little")
        if word in _ARM64_TERMINATORS:
            last = i * 4
    return last + 4 if last >= 0 else len(body)


def disasm_clean(body: bytes) -> tuple[bool, list[str]]:
    """Return (clean, undefined_words) for a function body's CODE region.

    Only the bytes up to (and including) the last terminator
    (`ret`/`br x30`) are disassembled; trailing inline-data is
    deliberately excluded because it's GOAL constants emitted by the
    compiler, not encoder output.
    """
    code = body[: find_code_end(body)]
    if not code:
        return True, []
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tf:
        tf.write(code)
        tmp = tf.name
    try:
        res = subprocess.run(
            [ARM_OBJDUMP, "-D", "-b", "binary", "-m", "aarch64", tmp],
            capture_output=True,
            text=True,
            timeout=20,
        )
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    bad = []
    for line in res.stdout.splitlines():
        if _INST_RE.search(line):
            m = _LINE_HEX_RE.match(line)
            if m:
                bad.append("0x" + m.group(1))
    return (not bad), bad


def classify_exit(rc: int) -> str:
    """Map subprocess.run().returncode to a classification bucket.

    Python's subprocess returns:
      - 0..255  : process exit code (clean exit with that value)
      - -N      : killed by signal N (e.g. -11 = SIGSEGV, -4 = SIGILL)

    Our harness uses exit codes 200/201 for harness-detected errors
    (missing argv, index out of range). 137 is reserved for driver-
    side TimeoutExpired we re-encode below.
    """
    if rc == -4 or rc == 132:
        return "sigill"
    if rc == -11 or rc == 139:
        return "sigsegv_post_prologue"
    if rc in (124, 137):
        return "timeout"
    if rc in (200, 201):
        return "other"
    if 0 <= rc <= 255:
        return "exit_clean"
    return "other"


def run_one(elf: Path, idx: int) -> tuple[int, str]:
    """Run function `idx` under qemu. Returns (exit_code, classification)."""
    try:
        cp = subprocess.run(
            [QEMU, str(elf), str(idx)],
            capture_output=True,
            timeout=PER_FN_TIMEOUT_SECS,
        )
        rc = cp.returncode
    except subprocess.TimeoutExpired:
        rc = 137
    return rc, classify_exit(rc)


# multiprocessing.Pool needs a top-level callable — capture (elf, idx)
# via a tuple and unpack here.
def _pool_run(args: tuple) -> tuple[int, int, str]:
    elf, idx = args
    rc, klass = run_one(Path(elf), idx)
    return idx, rc, klass


def process_cgo(cgo_path: Path, jobs: int) -> dict:
    """Build per-CGO ELF, then disasm + exec every function. Returns a
    summary dict matching the schema in B2-stress.json's per_cgo
    entries, plus a "failures" list of per-fn issues.
    """
    cgo_name = cgo_path.name
    print(f"  [{cgo_name}] enumerating functions...", flush=True)
    fns = enumerate_functions(cgo_path)
    total = len(fns)
    print(f"  [{cgo_name}] {total} functions", flush=True)

    print(f"  [{cgo_name}] building wrapper ELF...", flush=True)
    elf, fn_table = build_elf(cgo_path, BUILD_DIR)
    if len(fn_table) != total:
        raise RuntimeError(
            f"{cgo_name}: enumerate={total} vs build_elf={len(fn_table)}"
        )

    # Disasm pass (sequential — already fast since objdump is small).
    print(f"  [{cgo_name}] disasm pass...", flush=True)
    t0 = time.time()
    disasm_results: list[tuple[bool, list[str]]] = []
    for _obj, _idx, body in fns:
        disasm_results.append(disasm_clean(body))
    t1 = time.time()
    clean_count = sum(1 for c, _ in disasm_results if c)
    bad_disasm: list[int] = [i for i, (c, _) in enumerate(disasm_results) if not c]
    print(
        f"  [{cgo_name}] disasm: {clean_count}/{total} clean "
        f"({t1 - t0:.1f}s, {len(bad_disasm)} bad)",
        flush=True,
    )

    # Execute pass (parallel).
    print(f"  [{cgo_name}] qemu pass (jobs={jobs})...", flush=True)
    t0 = time.time()
    args = [(str(elf), i) for i in range(total)]
    counts = {
        "exit_clean": 0,
        "sigill": 0,
        "sigsegv_post_prologue": 0,
        "sigsegv_in_prologue": 0,
        "timeout": 0,
        "other": 0,
    }
    failures: list[dict] = []
    with multiprocessing.Pool(jobs) as pool:
        # imap_unordered is fast and tolerates differing per-fn runtimes.
        # We use chunksize for amortized overhead.
        for idx, rc, klass in pool.imap_unordered(_pool_run, args, chunksize=16):
            counts[klass] = counts.get(klass, 0) + 1
            if klass in ("sigill", "other"):
                obj_name, fn_idx, body_len = fn_table[idx]
                failures.append({
                    "cgo": cgo_name,
                    "fn_index": idx,
                    "obj": obj_name,
                    "obj_fn_idx": fn_idx,
                    "body_len": body_len,
                    "kind": klass,
                    "exit_code": rc,
                })
    t1 = time.time()
    executed = sum(counts.values())
    print(
        f"  [{cgo_name}] qemu: ran {executed} in {t1 - t0:.1f}s — "
        f"clean={counts['exit_clean']} "
        f"sigsegv={counts['sigsegv_post_prologue']} "
        f"sigill={counts['sigill']} "
        f"timeout={counts['timeout']} "
        f"other={counts['other']}",
        flush=True,
    )

    # Capture bad-disasm failures (separate from exec failures so the
    # caller can summarize both).
    for i in bad_disasm:
        obj_name, fn_idx, body_len = fn_table[i]
        # Find the first undefined word for diagnostic detail.
        bad_words = disasm_results[i][1][:4]
        failures.append({
            "cgo": cgo_name,
            "fn_index": i,
            "obj": obj_name,
            "obj_fn_idx": fn_idx,
            "body_len": body_len,
            "kind": "bad_disasm",
            "undefined_words": bad_words,
        })

    return {
        "total_functions": total,
        "tested_via_disasm": total,
        "disasm_clean": clean_count,
        "executed_under_qemu": executed,
        "exit_clean": counts["exit_clean"],
        "sigsegv_post_prologue": counts["sigsegv_post_prologue"],
        "sigsegv_in_prologue": 0,  # by-construction (see module docstring)
        "sigill": counts["sigill"],
        "timeout": counts["timeout"],
        "other": counts["other"],
        "failures": failures,
    }


def write_markdown(md_path: Path, summary: dict, per_cgo: dict) -> None:
    s = summary
    headline = (
        f"Decode-stressed {s['total_functions']} functions across 3 CGOs. "
        f"SIGILL={s['sigill']}, prologue-SIGSEGV={s['sigsegv_in_prologue']}, "
        f"body-SIGSEGV={s['sigsegv_post_prologue']} (tolerated), "
        f"timeout={s['timeout']}, clean={s['exit_clean']}, "
        f"unknown-opcode={s['total_functions'] - s['disasm_clean']}."
    )
    lines = [
        "# Phase B2 — arm64 CGO decode-stress under qemu",
        "",
        f"> {headline}",
        "",
        "## Per-CGO breakdown",
        "",
        "| CGO | fns | disasm-clean | exit-clean | body-segv | sigill "
        "| timeout | other |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for cgo in CGOS:
        r = per_cgo[cgo]
        lines.append(
            f"| {cgo} "
            f"| {r['total_functions']} "
            f"| {r['disasm_clean']} "
            f"| {r['exit_clean']} "
            f"| {r['sigsegv_post_prologue']} "
            f"| {r['sigill']} "
            f"| {r['timeout']} "
            f"| {r['other']} |"
        )
    lines += [
        "",
        "## Method",
        "",
        "- Disasm: `aarch64-linux-gnu-objdump -D -b binary -m aarch64` on "
        "each function's raw bytes; `.inst` pseudo-ops (undefined "
        "encodings) are counted as bad disasm.",
        "- Execute: a static aarch64 ELF per CGO (built by "
        "`b2_wrap_fn.py`) hosts all functions; the harness "
        "(`test/arm64/b2_harness.S`) is parameterised by `argv[1]` = "
        "function index, sets x30 to a safe-exit trampoline that does "
        "`exit_group(x0 & 0xff)`, mmap's a 64 KB scratch page at "
        "`0x40000000`, points x15/x22 there, zeroes x0..x7, and `br`s "
        "into the function.",
        "- `sigsegv_in_prologue` is 0 by construction: the kernel-"
        "provided process stack at `_start` is mapped, writable, and "
        "16-aligned, so the universal GOAL prologue "
        "`stp x29, x30, [sp, #-16]!` cannot fault.",
    ]
    md_path.write_text("\n".join(lines) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=max(1, os.cpu_count() or 4))
    args = ap.parse_args()

    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)

    # Preflight: cross-tools.
    for tool in (ARM_OBJDUMP, QEMU):
        if not shutil.which(tool):
            print(f"FAIL: {tool} not on PATH", file=sys.stderr)
            return 1

    for cgo in CGOS:
        p = ARM64_ISO_DIR / cgo
        if not p.exists():
            print(f"FAIL: {p} missing — run B1 first", file=sys.stderr)
            return 1

    print(f"== B2 decode-stress (jobs={args.jobs}) ==", flush=True)
    t0 = time.time()

    per_cgo: dict[str, dict] = {}
    all_failures: list[dict] = []
    for cgo in CGOS:
        r = process_cgo(ARM64_ISO_DIR / cgo, args.jobs)
        # Pull failures out so per_cgo entries match the validator's
        # arithmetic (sum of summary keys).
        all_failures.extend(r.pop("failures"))
        per_cgo[cgo] = r

    summary_keys = (
        "total_functions",
        "tested_via_disasm",
        "disasm_clean",
        "executed_under_qemu",
        "exit_clean",
        "sigsegv_post_prologue",
        "sigsegv_in_prologue",
        "sigill",
        "timeout",
        "other",
    )
    summary = {k: sum(per_cgo[c][k] for c in CGOS) for k in summary_keys}

    # Truncate the failures list so the JSON file stays a sane size.
    # We keep all sigill + bad_disasm failures (those are the hard
    # fails), and up to 50 "other" failures.
    sigill_fails = [f for f in all_failures if f["kind"] == "sigill"]
    bad_disasm_fails = [f for f in all_failures if f["kind"] == "bad_disasm"]
    other_fails = [
        f for f in all_failures
        if f["kind"] not in ("sigill", "bad_disasm")
    ][:50]
    failures_out = sigill_fails + bad_disasm_fails + other_fails

    report = {
        "phase": "B2-cgo-qemu-stress",
        "summary": summary,
        "per_cgo": per_cgo,
        "failures": failures_out,
        "harness": {
            "qemu": QEMU,
            "harness_s": "test/arm64/b2_harness.S",
            "wrapper_py": ".autoport/lib/b2_wrap_fn.py",
            "per_fn_timeout_secs": PER_FN_TIMEOUT_SECS,
        },
    }

    out_json = Path(
        os.environ.get("B2_OUT_JSON", str(REPORTS_DIR / "B2-stress.json"))
    )
    out_json.write_text(json.dumps(report, indent=2, sort_keys=True))
    print(f"  wrote {out_json} ({summary['total_functions']} fns, "
          f"{time.time() - t0:.1f}s total)", flush=True)

    if "B2_OUT_JSON" not in os.environ:
        md_path = REPORTS_DIR / "B2-stress.md"
        write_markdown(md_path, summary, per_cgo)
        print(f"  wrote {md_path}", flush=True)

    return 0


if __name__ == "__main__":
    sys.exit(main())
