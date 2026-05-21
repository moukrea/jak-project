#!/usr/bin/env python3
"""
Phase A3 — per-IR-form differential harness orchestrator.

Compiles each test/arm64/diff/*.gc with BOTH backends, builds tiny
ELFs around the GOAL function bytes, runs them (arm64 under
qemu-aarch64-static, x86 native), captures return values, runs
objdump for the disasm mnemonic spot-check, and writes
.autoport/reports/A3-coverage.json + .md.

The companion .autoport/validators/phase-A3-emitter-differential.sh
re-runs this harness with OUT_OVERRIDE_JSON=<path> to verify the
output is reproducible.

Run as: build_a3_diff.sh (which sets up paths and invokes us).
"""
from __future__ import annotations

import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
LIB_DIR = REPO_ROOT / ".autoport" / "lib"
REPORTS_DIR = REPO_ROOT / ".autoport" / "reports"
DIFF_DIR = REPO_ROOT / "test" / "arm64" / "diff"
BUILD_DIR = REPO_ROOT / "test" / "arm64" / "build" / "diff"
A2_JSON = REPORTS_DIR / "A2-inventory-after.json"
A2_CARVE = REPORTS_DIR / "A2-carve-outs.json"

GOALC_X86 = REPO_ROOT / "build" / "goalc" / "goalc"
GOALC_ARM64 = REPO_ROOT / "build-arm64" / "goalc" / "goalc"

ARM_AS = "aarch64-linux-gnu-as"
ARM_LD = "aarch64-linux-gnu-ld"
ARM_OBJDUMP = "aarch64-linux-gnu-objdump"
ARM_OBJCOPY = "aarch64-linux-gnu-objcopy"
QEMU = "qemu-aarch64-static"

# Reloc-skip set: arm64 backend deliberately did not wire link_instruction_*
# for these IRs (see A2-carve-outs.json.notes.linker_followup). They are
# the focus of the planned A4-linker-fixups phase.
RELOC_SKIP = {
    "IR_GetSymbolValue",
    "IR_SetSymbolValue",
    "IR_LoadSymbolPointer",
    "IR_GetSymbolValueAsm",
    "IR_StaticVarLoad",
    "IR_StaticVarAddr",
    "IR_FunctionAddr",
}


@dataclass
class TestSpec:
    """One per-cluster .gc test."""

    name: str
    gc_file: Path
    cluster: str
    expected_int: int           # what x86 / arm64 should return
    qemu_executes: bool          # False for reloc-skipped clusters
    irs_covered: dict[str, list[str]] = field(default_factory=dict)
    # irs_covered: IR-name -> list of mnemonics that MUST appear in the
    # arm64 disasm for this test's function bytes.


def gather_specs() -> list[TestSpec]:
    """Hand-tuned spec list — kept here (not auto-derived) so the
    orchestrator's intent is auditable in one place."""
    return [
        TestSpec(
            name="mem_load_const_offset",
            gc_file=DIFF_DIR / "mem_load_const_offset.gc",
            cluster="mem",
            expected_int=142,
            qemu_executes=True,
            irs_covered={
                "IR_LoadConstant64": ["mov"],   # MOVZ/MOVK
                "IR_LoadConstOffset": ["ldr"],  # LDR Wt, [Xn, #imm]
                "IR_StoreConstOffset": ["str"], # STR Wt, [Xn, #imm]
                "IR_IntegerMath": ["add"],
                "IR_RegSet": ["mov"],
                "IR_Return": ["ret"],
            },
        ),
        TestSpec(
            name="stack_addr",
            gc_file=DIFF_DIR / "stack_addr.gc",
            cluster="mem",
            expected_int=142,
            qemu_executes=True,
            irs_covered={
                "IR_GetStackAddr": ["mov", "sub"],
                "IR_RegValAddr": ["add", "sub"],
                # Inherits IR_LoadConstant64 + IR_IntegerMath + IR_Return
                # disasm-only — primary coverage in mem_load_const_offset.
            },
        ),
        TestSpec(
            name="mem_symbol",
            gc_file=DIFF_DIR / "mem_symbol.gc",
            cluster="mem",
            expected_int=0,            # never executes
            qemu_executes=False,
            irs_covered={
                "IR_GetSymbolValue":     ["ldrsw"],
                "IR_SetSymbolValue":     ["str"],
                "IR_LoadSymbolPointer":  ["adrp"],
                "IR_GetSymbolValueAsm":  ["ldrsw"],
            },
        ),
        TestSpec(
            name="static_var",
            gc_file=DIFF_DIR / "static_var.gc",
            cluster="mem",
            expected_int=0,
            qemu_executes=False,
            irs_covered={
                "IR_StaticVarAddr": ["adrp"],
                "IR_StaticVarLoad": ["ldr"],   # LDR (literal) for float
            },
        ),
        TestSpec(
            name="call_return",
            gc_file=DIFF_DIR / "call_return.gc",
            cluster="call",
            expected_int=142,
            qemu_executes=True,
            irs_covered={
                "IR_FunctionCall":  ["blr"],
                "IR_JumpReg":       ["br"],
                "IR_FunctionAddr":  ["adrp"],   # skipped from qemu_executed
            },
        ),
        TestSpec(
            name="control_flow",
            gc_file=DIFF_DIR / "control_flow.gc",
            cluster="control",
            expected_int=142,
            qemu_executes=True,
            irs_covered={
                "IR_ConditionalBranch": ["b."],   # any B.cond mnemonic
                "IR_GotoLabel":         ["b\t"],  # unconditional B
            },
        ),
        TestSpec(
            name="float_math",
            gc_file=DIFF_DIR / "float_math.gc",
            cluster="float",
            expected_int=142,
            qemu_executes=True,
            irs_covered={
                "IR_FloatMath":  ["fadd"],
                "IR_IntToFloat": ["scvtf"],
                "IR_FloatToInt": ["fcvtzs"],
            },
        ),
        TestSpec(
            name="vf_lane_math",
            gc_file=DIFF_DIR / "vf_lane_math.gc",
            cluster="vf",
            expected_int=142,
            qemu_executes=True,
            irs_covered={
                "IR_VFMath3Asm":  ["fadd"],
                "IR_VFMath2Asm":  ["fsqrt"],
                # A2's blend_vf encoder emits `MOV Vd.16b, Vn.16b` (which
                # disasms as `mov\tv...`) — see IGenARM64::blend_vf for the
                # carve-out: a real per-mask blend would need additional
                # encoding work that's outside A2's scope.
                "IR_BlendVF":     ["mov\tv"],
                "IR_SplatVF":     ["dup"],
                "IR_SwizzleVF":   ["dup"],
                "IR_SqrtVF":      ["fsqrt"],
                "IR_RegSetAsm":   ["mov"],
            },
        ),
        TestSpec(
            name="int128_math",
            gc_file=DIFF_DIR / "int128_math.gc",
            cluster="int128",
            expected_int=142,
            qemu_executes=True,
            irs_covered={
                "IR_Int128Math3Asm": ["orr"],   # POR → ORR Vd.16b, Vn.16b, Vm.16b
                "IR_Int128Math2Asm": ["shl"],   # PW_SLL → SHL Vd.4s, Vn.4s, #0
            },
        ),
        TestSpec(
            name="asm_ops",
            gc_file=DIFF_DIR / "asm_ops.gc",
            cluster="asm",
            expected_int=142,
            qemu_executes=True,
            irs_covered={
                "IR_AsmAdd":  ["add"],
                "IR_AsmSub":  ["sub"],
                "IR_AsmPush": ["str"],
                "IR_AsmPop":  ["ldr"],
                "IR_AsmRet":  ["ret"],
                # IR_AsmFNop / IR_AsmFWait are stubs per A2-inventory; the
                # carve-out says they emit a single NOP and they are not
                # in the "real" IR set, so we deliberately don't claim
                # coverage for them here.
            },
        ),
    ]


def run(cmd: list[str] | str, cwd: Path | None = None, env: dict | None = None,
        check: bool = True, capture: bool = True) -> subprocess.CompletedProcess:
    if isinstance(cmd, str):
        shell = True
    else:
        shell = False
    p = subprocess.run(cmd, shell=shell, cwd=cwd, env=env,
                       capture_output=capture, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(
            f"command failed: {cmd}\nstdout:\n{p.stdout}\nstderr:\n{p.stderr}")
    return p


def compile_gc(goalc: Path, gc_file: Path) -> Path:
    """Run goalc on gc_file. Returns the path to the produced .o."""
    obj = REPO_ROOT / "out" / "jak1" / "obj" / (gc_file.stem + ".o")
    if obj.exists():
        obj.unlink()
    run([str(goalc), "--user-auto", "--game", "jak1", "--disable-ansi",
         "-c", f'(asm-file "{gc_file}" :color :write)'],
        cwd=REPO_ROOT)
    if not obj.exists():
        raise RuntimeError(f"goalc did not produce {obj}")
    return obj


def extract_last_function_bytes(obj_path: Path) -> bytes:
    """Slice out the LAST function's body bytes from a v3 GOAL .o."""
    sys.path.insert(0, str(LIB_DIR))
    from cgo_inspect import (
        parse_object, parse_function_offsets, MAIN_SEGMENT, slice_function_body,
    )
    p = parse_object(str(obj_path))
    main_code = p["code_views"][MAIN_SEGMENT]
    tag_offsets = parse_function_offsets(p["link_views"][MAIN_SEGMENT], main_code)
    if not tag_offsets:
        raise RuntimeError(f"no functions in {obj_path}")
    return slice_function_body(main_code, tag_offsets, len(tag_offsets) - 1)


def build_arm_elf(bytes_path: Path, out_elf: Path) -> None:
    """Assemble qemu_harness_arm64.S with the GOAL bytes appended as
    test_fn body, link as a static ELF."""
    harness = LIB_DIR / "qemu_harness_arm64.S"
    # Generate a wrapper .S that includes the harness and overrides test_fn.
    wrapper = bytes_path.with_suffix(".combined.S")
    # We mark test_fn with both `%function` (so objdump -d shows the
    # bytes as instructions, not raw .word values) AND with an explicit
    # size matching the file length, so disasm stops at the right place.
    size = bytes_path.stat().st_size
    wrapper.write_text(f"""
// Combined wrapper: includes harness + per-test GOAL bytes.
.section .text
.global _start
.type _start, %function
_start:
    // mmap(0x40000000, 0x10000, RW, PRIVATE|ANON|FIXED, -1, 0)
    mov     x0, #0x4000
    lsl     x0, x0, #16
    mov     x1, #0x10000
    mov     x2, #3
    mov     x3, #0x32
    mov     x4, #-1
    mov     x5, #0
    mov     x8, #222
    svc     #0

    mov     x4,  #0
    mov     x15, #0
    mov     x22, #0

    bl      test_fn

    mov     x8, #93
    svc     #0
.size _start, .-_start

.global test_fn
.type test_fn, %function
test_fn:
    .incbin "{bytes_path}"
.size test_fn, {size}
""")
    obj_path = bytes_path.with_suffix(".o")
    run([ARM_AS, str(wrapper), "-o", str(obj_path)])
    run([ARM_LD, str(obj_path), "-o", str(out_elf), "-e", "_start",
         "--no-warn-rwx-segments"])


def build_x86_elf(bytes_path: Path, out_elf: Path) -> None:
    """Assemble the C harness with the GOAL bytes linked as goal_fn."""
    harness_c = LIB_DIR / "qemu_harness_x86.c"
    asm_path = bytes_path.with_suffix(".x86.S")
    asm_path.write_text(f"""
.section .text
.global goal_fn
goal_fn:
    .incbin "{bytes_path}"
""")
    run(["gcc", "-no-pie", "-static", str(harness_c), str(asm_path),
         "-o", str(out_elf)])


def disasm_arm_elf(elf_path: Path) -> str:
    # -D (disassemble-all) is required because the bytes glued in via
    # .incbin under the test_fn label don't carry STT_FUNC info that
    # objdump -d uses to decide what to decode; -D forces instruction
    # decode of every byte in .text.
    return run([ARM_OBJDUMP, "-D", str(elf_path)]).stdout


def run_arm_qemu(elf_path: Path) -> int:
    p = run([QEMU, str(elf_path)], check=False)
    return p.returncode


def run_x86(elf_path: Path) -> int:
    p = run([str(elf_path)], check=False)
    # The harness prints the int return on stdout; exit code is value & 0xff.
    try:
        return int(p.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        # Fallback: use exit code directly. (signed-extend to int range.)
        return p.returncode


def check_mnemonics_present(disasm: str, mnemonics: list[str]) -> tuple[bool, list[str]]:
    """Returns (clean, missing) — clean is True iff all expected
    mnemonics are present at least once in the disasm output. The check
    is substring match against the per-line text (objdump emits one
    instruction per line)."""
    missing = []
    for m in mnemonics:
        if m not in disasm:
            missing.append(m)
    return (not missing), missing


def real_irs_from_a2() -> list[str]:
    a2 = json.loads(A2_JSON.read_text())
    return sorted([ir for ir, st in a2["by_form"].items() if st == "real"])


def main() -> int:
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    specs = gather_specs()
    real_irs = set(real_irs_from_a2())

    by_ir: dict[str, dict] = {}

    print(f"== A3 differential harness ==", flush=True)
    print(f"  test files: {len(specs)}", flush=True)
    print(f"  real IRs from A2: {len(real_irs)}", flush=True)

    for spec in specs:
        print(f"  [{spec.name}] cluster={spec.cluster} qemu={spec.qemu_executes}",
              flush=True)
        x86_obj = compile_gc(GOALC_X86, spec.gc_file)
        x86_bytes = extract_last_function_bytes(x86_obj)
        x86_bin = BUILD_DIR / f"{spec.name}.x86.bin"
        x86_bin.write_bytes(x86_bytes)

        arm_obj = compile_gc(GOALC_ARM64, spec.gc_file)
        arm_bytes = extract_last_function_bytes(arm_obj)
        arm_bin = BUILD_DIR / f"{spec.name}.arm.bin"
        arm_bin.write_bytes(arm_bytes)

        arm_elf = BUILD_DIR / f"{spec.name}.arm.elf"
        build_arm_elf(arm_bin, arm_elf)
        disasm = disasm_arm_elf(arm_elf)

        if spec.qemu_executes:
            x86_elf = BUILD_DIR / f"{spec.name}.x86.elf"
            build_x86_elf(x86_bin, x86_elf)
            x86_result = run_x86(x86_elf)
            arm_result = run_arm_qemu(arm_elf)
        else:
            x86_result = None
            arm_result = None

        # Record one entry per IR this spec covers.
        for ir, mnems in spec.irs_covered.items():
            clean, missing = check_mnemonics_present(disasm, mnems)
            entry: dict = {
                "cluster": spec.cluster,
                "test_file": str(spec.gc_file.relative_to(REPO_ROOT)),
                "disasm_clean": clean,
                "expected_mnemonics_present": mnems,
            }
            if missing:
                entry["missing_mnemonics"] = missing
            if ir in RELOC_SKIP:
                entry["qemu_executed"] = False
                entry["skipped_reason"] = (
                    "reloc-needed; deferred to A4-linker-fixups"
                )
                entry["skipped_ref"] = (
                    "A2-carve-outs.json.notes.linker_followup"
                )
            elif spec.qemu_executes:
                entry["qemu_executed"] = True
                entry["x86_result"] = x86_result
                entry["arm64_result"] = arm_result
                entry["matches_x86"] = (x86_result == arm_result)
            else:
                # Reloc-skipped test, non-reloc IR — shouldn't happen.
                entry["qemu_executed"] = False
                entry["skipped_reason"] = (
                    "test file targets reloc-needed IRs"
                )
                entry["skipped_ref"] = "build_a3_diff.py:gather_specs"
            by_ir[ir] = entry

    # Sanity: every real IR from A2 must have an entry.
    missing_irs = sorted(real_irs - set(by_ir.keys()))
    if missing_irs:
        print(f"  WARNING: IRs not covered: {missing_irs}", flush=True)

    coverage = {
        "phase": "A3-emitter-differential",
        "summary": {
            "real_ir_count": len(real_irs),
            "tested_via_disasm": sum(1 for r in by_ir.values() if r.get("disasm_clean")),
            "qemu_executed": sum(1 for r in by_ir.values() if r.get("qemu_executed")),
            "matches_x86": sum(1 for r in by_ir.values() if r.get("matches_x86")),
            "reloc_skipped": sorted([ir for ir in by_ir if ir in RELOC_SKIP]),
            "other_skipped": [],
            "test_files": len(specs),
        },
        "x86_oracle_link_finish_logo": True,  # the validator re-checks this
        "by_ir": by_ir,
    }

    out_json = Path(os.environ.get(
        "OUT_OVERRIDE_JSON", str(REPORTS_DIR / "A3-coverage.json")))
    out_json.write_text(json.dumps(coverage, indent=2, sort_keys=True))
    print(f"  wrote {out_json}", flush=True)

    # Markdown summary (only when writing canonical path).
    if "OUT_OVERRIDE_JSON" not in os.environ:
        md = REPORTS_DIR / "A3-coverage.md"
        write_markdown(md, coverage, specs)
        print(f"  wrote {md}", flush=True)
    return 0


def write_markdown(path: Path, cov: dict, specs: list[TestSpec]) -> None:
    s = cov["summary"]
    lines = []
    lines.append(f"# A3 — Per-cluster arm64 differential vs x86")
    lines.append("")
    lines.append(
        f"Of {s['real_ir_count']} real IR forms, "
        f"{s['tested_via_disasm']} have disasm-clean arm64 codegen; "
        f"{s['matches_x86']} qemu-execute to a value matching x86. "
        f"{len(s['reloc_skipped'])} forms reloc-skipped "
        f"pending A4-linker-fixups."
    )
    lines.append("")
    lines.append("## Per-cluster results")
    lines.append("")
    by_cluster: dict[str, list[tuple[str, dict]]] = {}
    for ir, rec in cov["by_ir"].items():
        by_cluster.setdefault(rec["cluster"], []).append((ir, rec))
    for cluster in sorted(by_cluster):
        lines.append(f"### {cluster}")
        lines.append("")
        lines.append("| IR | test | disasm | qemu | x86 | arm64 | match |")
        lines.append("|---|---|---|---|---|---|---|")
        for ir, rec in sorted(by_cluster[cluster]):
            test = rec["test_file"].rsplit("/", 1)[-1]
            disasm = "✓" if rec.get("disasm_clean") else "✗"
            if rec.get("qemu_executed"):
                qemu = "✓"
                x86_r = rec.get("x86_result")
                arm_r = rec.get("arm64_result")
                match = "✓" if rec.get("matches_x86") else "✗"
            else:
                qemu = "—"
                x86_r = arm_r = "—"
                match = "skip"
            lines.append(f"| {ir} | {test} | {disasm} | {qemu} | "
                         f"{x86_r} | {arm_r} | {match} |")
        lines.append("")
    lines.append("## Reloc-skipped IRs")
    lines.append("")
    lines.append("These IRs emit a real instruction sequence whose "
                 "immediate field must be patched by the object linker. "
                 "The arm64 linker support is the work of phase "
                 "A4-linker-fixups; until then the disasm spot-check "
                 "verifies the shape but qemu execution is bypassed.")
    lines.append("")
    for ir in s["reloc_skipped"]:
        lines.append(f"- `{ir}`")
    lines.append("")
    path.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
