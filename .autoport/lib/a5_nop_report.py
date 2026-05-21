#!/usr/bin/env python3
"""Phase A5 — post-emit NOP counter for arm64 GOAL CGOs.

The A4 emitter encoded GOAL symbol-table accesses as a single
``LDR/STR Wt, [X14, #imm12_scaled4]`` instruction with the imm12 field
zeroed at emit time. The runtime klink dispatcher (game/kernel/common/
klink.cpp::klink_arm64_patch_pc_rel) computed each symbol's offset from
s7 and wrote the imm12, but when ``(sym_host - s7_host) > 4095 * scale``
it silently substituted the AArch64 NOP encoding (0xD503201F) so the
access no-op'd instead of corrupting s7's fixed slots. The C4 boot
histogram reported 691 such NOP'd sites across KERNEL.CGO at runtime.

A5 closes the gap by replacing every sym-mem access with a 3-instruction
far-reloc sequence (ADRP X16 + ADD X16 + LDR/STR Wt, [X16, #0]) inside
the emitter. ADRP's ±4 GB range is ample for any address pair within
the GOAL heap, so the runtime never hits the NOP-fallback path.

This script verifies the fix offline by scanning each regenerated arm64
CGO's main-code segments for the pre-A5 sym-mem encoding pattern. After
A5, the per-CGO count should be zero across KERNEL/ENGINE/GAME — any
non-zero count would indicate a sym-mem call site the emitter did not
expand.

Detection: instruction word matches ``(enc & 0xFFC003E0) ∈ {
  0xB94001C0,  // LDR Wt, [X14, #imm12]
  0xB98001C0,  // LDRSW Xt, [X14, #imm12]
  0xB90001C0,  // STR Wt, [X14, #imm12]
}``. The 0xFFC003E0 mask covers the top opcode bits and the Rn=14 field;
imm12 and Rt are not constrained. Other producers of LDR/STR Rn=X14 do
not exist in the goalc-arm64 emitter (Register.cpp's allocation order
caps at id 9 / R10), so any matching word inside a code segment is
unambiguously a leftover sym-mem call site the A5 expansion missed.

Usage:
  a5_nop_report.py <out.txt> <CGO1> [<CGO2> ...]

Output format (consumed by phase-A5 validator):
  CGO_NAME: <n> NOPs
  ...
  TOTAL_NOPS: <sum>
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

DGO_HDR = 64
OBJ_HDR = 64

# Sym-mem LDR/STR with Rn=X14. Mask covers top opcode bits 31..22 plus
# Rn bits 9..5; imm12 (bits 21..10) and Rt (bits 4..0) are free.
SYMMEM_MASK = 0xFFC003E0
SYMMEM_PATTERNS = (
    0xB94001C0,  # LDR Wt, [X14, #imm12*4]
    0xB98001C0,  # LDRSW Xt, [X14, #imm12*4]
    0xB90001C0,  # STR Wt, [X14, #imm12*4]
)


def u32(b: bytes, o: int) -> int:
    return struct.unpack_from("<I", b, o)[0]


def iter_object_bodies(cgo_path: Path):
    """Yield (obj_name, body_bytes) for each .o packed inside the CGO/DGO."""
    data = cgo_path.read_bytes()
    if len(data) < DGO_HDR:
        return
    obj_count = u32(data, 0)
    cur = DGO_HDR
    for _ in range(obj_count):
        if cur + OBJ_HDR > len(data):
            break
        obj_size = u32(data, cur)
        obj_name_raw = data[cur + 4 : cur + OBJ_HDR]
        obj_name = obj_name_raw.split(b"\x00", 1)[0].decode("ascii", "replace")
        body_off = cur + OBJ_HDR
        body_end = body_off + obj_size
        if body_end > len(data):
            break
        yield obj_name, data[body_off:body_end]
        # CGOs pad each object body to 16-byte alignment.
        cur = body_off + ((obj_size + 15) & ~15)


def count_symmem_in_object(body: bytes) -> int:
    """Scan a v3 .o file's code segments for the pre-A5 sym-mem pattern.

    Returns the count of matching 4-byte words. Returns 0 if the body
    isn't a v3 OpenGOAL object.
    """
    if len(body) < 68 or body[:4] != b"GOAL":
        return 0
    link_block_length = u32(body, 64)
    # SizeOffsetTable: link_seg[3] @ off 16, code_seg[3] @ off 40, both pairs
    # of (offset, size) u32s.
    total = 0
    for seg_idx in range(3):
        code_off = u32(body, 40 + seg_idx * 8)
        code_sz = u32(body, 40 + seg_idx * 8 + 4)
        if code_sz == 0:
            continue
        abs_start = link_block_length + code_off
        abs_end = abs_start + code_sz
        if abs_end > len(body):
            continue
        seg = body[abs_start:abs_end]
        # Scan 4-byte aligned words.
        # AArch64 instructions are always 4-byte aligned; static data inside
        # the same segment may be arbitrarily aligned, so we'd over-count
        # there. In practice the v3 main segment alternates function bodies
        # (instructions) and static data; the LINK_TYPE_PTR("function")
        # records the start of each function body, but for the purpose of
        # this offline NOP audit we scan all aligned u32s in the segment
        # — a coincidental data-word matching the pattern in static data is
        # not an executable NOP and so is a benign false positive. After A5
        # the count should be zero anyway, so any non-zero is a real flag.
        word_count = len(seg) // 4
        for w_idx in range(word_count):
            enc = u32(seg, w_idx * 4)
            if (enc & SYMMEM_MASK) in SYMMEM_PATTERNS:
                total += 1
    return total


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(
            "usage: a5_nop_report.py <out.txt> <CGO1> [<CGO2> ...]",
            file=sys.stderr,
        )
        return 2

    out_path = Path(argv[1])
    cgo_paths = [Path(p) for p in argv[2:]]
    lines = []
    total = 0
    for cgo_path in cgo_paths:
        if not cgo_path.is_file():
            print(f"a5_nop_report: missing {cgo_path}", file=sys.stderr)
            return 2
        per_cgo = 0
        for _obj_name, body in iter_object_bodies(cgo_path):
            per_cgo += count_symmem_in_object(body)
        lines.append(f"{cgo_path.name}: {per_cgo} NOPs")
        total += per_cgo

    lines.append(f"TOTAL_NOPS: {total}")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    # Also echo to stdout for human inspection.
    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
