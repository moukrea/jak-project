#!/usr/bin/env python3
"""
Phase A4 — Python port of the runtime linker for AArch64 GOAL objects.

Walks a v3 .o file's main-segment link table and rewrites the immediate
fields of arm64 instructions in place, using a deterministic synthetic
symbol table and a known runtime base address for the embedded main-code
blob. This replaces the kernel klink.cpp path for differential testing:
we do not depend on the desktop GOAL runtime to validate the encoder's
fix-up plumbing.

The patcher mirrors the semantics of:
  ObjectGenerator::handle_temp_instr_sym_links  (LINK_SYMBOL_OFFSET)
  ObjectGenerator::emit_link_rip                 (LINK_DISTANCE_TO_OTHER_SEG_32)
  ObjectGenerator::emit_link_ptr                 (LINK_PTR)

For each link record:

  LINK_SYMBOL_OFFSET (kind=1): the recorded offset points at the start of an
    arm64 instruction (handle_temp_instr_sym_links sets offset_in_instruction=0
    in arm64 mode). The instruction word is one of:
      - LDR/STR/LDRSW Wt unsigned offset (imm12 scaled by 4) — used for
        IR_SetSymbolValue / IR_GetSymbolValue / IR_GetSymbolValueAsm.
        We rewrite imm12 = (symoff >> 2).
      - ADRP Xd — used as the first half of the IR_LoadSymbolPointer
        ADRP+ADD pair. We rewrite imm21 = (sym_abs_page - patch_pc_page) / 4096.
      - ADD Xd, Xn, #imm12 — second half of the same pair. We rewrite imm12 =
        sym_abs_addr & 0xfff.

  LINK_DISTANCE_TO_OTHER_SEG_32 (kind=4): the recorded patch_loc points at the
    start of an arm64 instruction. The target absolute address is
    (target_segment_base_addr + target_offset). Encodings:
      - ADRP — for IR_StaticVarAddr / IR_FunctionAddr's first half.
      - ADD imm12 — for those same forms' second half.
      - LDR-literal (imm19, S/Q variants) — for IR_StaticVarLoad. We rewrite
        imm19 = (target_pc - patch_pc) / 4.

  LINK_PTR (kind=5): a 32-bit absolute pointer write at patch_loc, same as
    x86 (the pointer field is not encoded into an instruction).
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, field
from typing import Dict, List

LINK_TABLE_END = 0
LINK_SYMBOL_OFFSET = 1
LINK_TYPE_PTR = 2
LINK_DISTANCE_TO_OTHER_SEG_64 = 3
LINK_DISTANCE_TO_OTHER_SEG_32 = 4
LINK_PTR = 5

# Anchor offsets used by the harness. Any symbol that appears in a link
# table for which we don't have a pinned offset is auto-assigned starting
# at AUTO_BASE on first encounter and grows in 8-byte strides.
SYM_OFFSET_PINNED: Dict[str, int] = {
    # Symbols whose value is read/written by the IR_*SymbolValue test.
    "*probe-foo*": 0x80,
    "*probe-bar*": 0x88,
    # Symbol whose pointer is used by the IR_LoadSymbolPointer test. The
    # offset 42 (= 0x2A) means symtab_base + 42, so the low byte of the
    # materialised pointer is 0x2A regardless of symtab_base alignment;
    # the test masks with 0xff to get a deterministic 42.
    "tag42": 42,
}
SYM_AUTO_BASE = 0x200
SYM_AUTO_STRIDE = 8


@dataclass
class SymTabLayout:
    """Synthetic symbol table layout shared by x86 and arm64 patchers."""

    base_addr: int
    pinned: Dict[str, int] = field(default_factory=lambda: dict(SYM_OFFSET_PINNED))
    auto_next: int = SYM_AUTO_BASE

    def offset_for(self, name: str) -> int:
        if name in self.pinned:
            return self.pinned[name]
        if name not in self.pinned:
            self.pinned[name] = self.auto_next
            self.auto_next += SYM_AUTO_STRIDE
        return self.pinned[name]

    def abs_addr(self, name: str) -> int:
        return self.base_addr + self.offset_for(name)


def _set_bits(word: int, mask: int, value: int) -> int:
    return (word & ~mask) | (value & mask)


def _patch_ldr_str_imm12(word: int, scale_log2: int, byte_offset: int) -> int:
    """LDR/STR <Wt|Xt|Wt>, [Xn, #imm] unsigned-offset; imm12 is bits 21..10."""
    imm12 = (byte_offset >> scale_log2) & 0xFFF
    return _set_bits(word, 0x3FFC00, imm12 << 10)


def _patch_adrp(word: int, target_addr: int, patch_pc: int) -> int:
    """ADRP imm21 picks the page-offset (4 KiB) between target and patch_pc.

    Encoding: bits 30..29 = immlo, bits 23..5 = immhi; result =
    (PC[63:12] + sign_extend(imm21:000000000000)) so the page diff is in
    units of 4 KiB pages.
    """
    target_page = target_addr & ~0xFFF
    patch_page = patch_pc & ~0xFFF
    page_diff_bytes = target_page - patch_page
    # page_diff is in bytes; imm21 is in pages.
    imm21 = (page_diff_bytes >> 12) & 0x1FFFFF
    immlo = imm21 & 0x3
    immhi = (imm21 >> 2) & 0x7FFFF
    word = _set_bits(word, 0x60000000, immlo << 29)
    word = _set_bits(word, 0x00FFFFE0, immhi << 5)
    return word


def _patch_add_imm12(word: int, target_addr: int) -> int:
    """ADD Xd, Xn, #imm12 (no shift). Encodes the within-page byte offset."""
    imm12 = target_addr & 0xFFF
    return _set_bits(word, 0x3FFC00, imm12 << 10)


def _patch_ldr_literal(word: int, target_pc: int, patch_pc: int) -> int:
    """LDR (literal) Wt/Xt/St/Qt — imm19 is bits 23..5, scaled by 4 (signed)."""
    delta_words = (target_pc - patch_pc) // 4
    imm19 = delta_words & 0x7FFFF
    return _set_bits(word, 0x00FFFFE0, imm19 << 5)


# Opcode masks/values for the instruction encodings we recognise.
LDR_W_UO = (0xFFC00000, 0xB9400000)
STR_W_UO = (0xFFC00000, 0xB9000000)
LDRSW_X_UO = (0xFFC00000, 0xB9800000)
LDR_X_UO = (0xFFC00000, 0xF9400000)
STR_X_UO = (0xFFC00000, 0xF9000000)
ADRP = (0x9F000000, 0x90000000)
ADR = (0x9F000000, 0x10000000)
ADD_X_IMM12 = (0xFF800000, 0x91000000)
SUB_X_IMM12 = (0xFF800000, 0xD1000000)
LDR_LITERAL_W = (0xFF000000, 0x18000000)
LDR_LITERAL_X = (0xFF000000, 0x58000000)
LDR_LITERAL_S = (0xFF000000, 0x1C000000)
LDR_LITERAL_Q = (0xFF000000, 0x9C000000)
LDR_LITERAL_D = (0xFF000000, 0x5C000000)


def _opcode_matches(word: int, mask_value):
    mask, value = mask_value
    return (word & mask) == value


def _patch_sym(buf: bytearray, offset: int, sym_off: int, sym_abs_addr: int,
               patch_pc: int) -> str:
    """Patch a single LINK_SYMBOL_OFFSET site. Returns a short kind tag for
    diagnostics. Raises if the instruction word isn't a recognised encoding."""
    word = struct.unpack_from("<I", buf, offset)[0]
    if _opcode_matches(word, LDR_W_UO):
        new = _patch_ldr_str_imm12(word, 2, sym_off)
        kind = "LDR-W-imm12"
    elif _opcode_matches(word, STR_W_UO):
        new = _patch_ldr_str_imm12(word, 2, sym_off)
        kind = "STR-W-imm12"
    elif _opcode_matches(word, LDRSW_X_UO):
        new = _patch_ldr_str_imm12(word, 2, sym_off)
        kind = "LDRSW-X-imm12"
    elif _opcode_matches(word, LDR_X_UO):
        new = _patch_ldr_str_imm12(word, 3, sym_off)
        kind = "LDR-X-imm12"
    elif _opcode_matches(word, STR_X_UO):
        new = _patch_ldr_str_imm12(word, 3, sym_off)
        kind = "STR-X-imm12"
    elif _opcode_matches(word, ADRP):
        new = _patch_adrp(word, sym_abs_addr, patch_pc)
        kind = "ADRP"
    elif _opcode_matches(word, ADD_X_IMM12):
        new = _patch_add_imm12(word, sym_abs_addr)
        kind = "ADD-imm12"
    else:
        raise RuntimeError(
            f"unhandled sym-offset encoding 0x{word:08x} at offset 0x{offset:x}"
        )
    struct.pack_into("<I", buf, offset, new)
    return kind


def _patch_distance(buf: bytearray, patch_loc: int, source_offset: int,
                    target_offset: int, segment_base_addr: int) -> str:
    """Patch a LINK_DISTANCE_TO_OTHER_SEG_32 site for arm64. The instruction
    at patch_loc is one of ADRP / ADD-imm12 / LDR-literal."""
    word = struct.unpack_from("<I", buf, patch_loc)[0]
    target_addr = segment_base_addr + target_offset
    patch_pc = segment_base_addr + source_offset
    if _opcode_matches(word, ADRP):
        new = _patch_adrp(word, target_addr, patch_pc)
        kind = "ADRP"
    elif _opcode_matches(word, ADD_X_IMM12):
        new = _patch_add_imm12(word, target_addr)
        kind = "ADD-imm12"
    elif _opcode_matches(word, LDR_LITERAL_S):
        new = _patch_ldr_literal(word, target_addr, patch_pc)
        kind = "LDR-literal-S"
    elif _opcode_matches(word, LDR_LITERAL_W):
        new = _patch_ldr_literal(word, target_addr, patch_pc)
        kind = "LDR-literal-W"
    elif _opcode_matches(word, LDR_LITERAL_X):
        new = _patch_ldr_literal(word, target_addr, patch_pc)
        kind = "LDR-literal-X"
    elif _opcode_matches(word, LDR_LITERAL_D):
        new = _patch_ldr_literal(word, target_addr, patch_pc)
        kind = "LDR-literal-D"
    elif _opcode_matches(word, LDR_LITERAL_Q):
        new = _patch_ldr_literal(word, target_addr, patch_pc)
        kind = "LDR-literal-Q"
    else:
        raise RuntimeError(
            f"unhandled distance encoding 0x{word:08x} at offset 0x{patch_loc:x}"
        )
    struct.pack_into("<I", buf, patch_loc, new)
    return kind


def _read_cstr(buf: bytes, off: int) -> tuple[str, int]:
    end = buf.index(b"\x00", off)
    return buf[off:end].decode("utf-8", errors="replace"), end + 1


@dataclass
class PatchTrace:
    """Per-record diagnostic record produced by apply_arm64_patches."""

    kind: str
    name: str
    offset: int
    encoding: str
    word_before: int
    word_after: int
    extra: Dict[str, int] = field(default_factory=dict)


def apply_arm64_patches(main_code: bytes, link_table: bytes,
                        sym_layout: SymTabLayout,
                        segment_base_addr: int,
                        function_offsets_in_segment: List[int],
                        external_function_addrs: Dict[str, int] | None = None
                        ) -> tuple[bytes, List[PatchTrace]]:
    """Apply all arm64 fix-ups to main_code, in place semantics.

    Args:
      main_code: bytes of the main code segment (function tags + bodies +
                 statics). Will be returned with patches applied.
      link_table: raw bytes of the main segment's link table.
      sym_layout: synthetic symtab layout to resolve symbol names against.
      segment_base_addr: the absolute virtual address at which main_code will
                         live at runtime (for PC-relative ADRP/LDR-literal).
      function_offsets_in_segment: ordered list of byte offsets of each
                                   function's tag (0xae) within main_code.
                                   Used internally if we ever need to resolve
                                   cross-function references in the same .o.

    Returns: (patched_main_code, traces).
    """
    buf = bytearray(main_code)
    traces: List[PatchTrace] = []
    pos = 0
    while pos < len(link_table):
        kind = link_table[pos]
        pos += 1
        if kind == LINK_TABLE_END:
            break
        elif kind == LINK_SYMBOL_OFFSET:
            name, pos = _read_cstr(link_table, pos)
            count = struct.unpack_from("<I", link_table, pos)[0]
            pos += 4
            sym_off = sym_layout.offset_for(name)
            sym_abs = sym_layout.abs_addr(name)
            for _ in range(count):
                instr_offset = struct.unpack_from("<I", link_table, pos)[0]
                pos += 4
                word_before = struct.unpack_from("<I", buf, instr_offset)[0]
                patch_pc = segment_base_addr + instr_offset
                enc_kind = _patch_sym(buf, instr_offset, sym_off, sym_abs, patch_pc)
                word_after = struct.unpack_from("<I", buf, instr_offset)[0]
                traces.append(PatchTrace(
                    kind="LINK_SYMBOL_OFFSET",
                    name=name, offset=instr_offset, encoding=enc_kind,
                    word_before=word_before, word_after=word_after,
                    extra={"sym_off": sym_off, "sym_abs_addr": sym_abs,
                           "patch_pc": patch_pc},
                ))
        elif kind == LINK_TYPE_PTR:
            _, pos = _read_cstr(link_table, pos)
            pos += 1  # method-count u8
            count = struct.unpack_from("<I", link_table, pos)[0]
            pos += 4 + 4 * count
        elif kind == LINK_DISTANCE_TO_OTHER_SEG_64:
            # u8 target_seg + 3 * u32 — we don't expect this for our tests.
            pos += 1 + 12
        elif kind == LINK_DISTANCE_TO_OTHER_SEG_32:
            target_seg = link_table[pos]; pos += 1
            mine_offset = struct.unpack_from("<I", link_table, pos)[0]; pos += 4
            target_offset = struct.unpack_from("<I", link_table, pos)[0]; pos += 4
            patch_loc = struct.unpack_from("<I", link_table, pos)[0]; pos += 4
            if target_seg != 0:
                # Only main-segment intra-object references are supported by
                # the harness; debug/top-level cross-seg refs would need a
                # separate layout. Skip silently for now.
                traces.append(PatchTrace(
                    kind="LINK_DISTANCE_TO_OTHER_SEG_32_SKIP",
                    name=f"target_seg={target_seg}",
                    offset=patch_loc, encoding="skip",
                    word_before=0, word_after=0,
                ))
                continue
            word_before = struct.unpack_from("<I", buf, patch_loc)[0]
            enc_kind = _patch_distance(buf, patch_loc, mine_offset,
                                       target_offset, segment_base_addr)
            word_after = struct.unpack_from("<I", buf, patch_loc)[0]
            traces.append(PatchTrace(
                kind="LINK_DISTANCE_TO_OTHER_SEG_32",
                name=f"target_off=0x{target_offset:x}", offset=patch_loc,
                encoding=enc_kind, word_before=word_before, word_after=word_after,
                extra={"mine_offset": mine_offset, "target_offset": target_offset,
                       "target_addr": segment_base_addr + target_offset,
                       "patch_pc": segment_base_addr + mine_offset},
            ))
        elif kind == LINK_PTR:
            patch_loc = struct.unpack_from("<I", link_table, pos)[0]; pos += 4
            patch_value = struct.unpack_from("<I", link_table, pos)[0]; pos += 4
            abs_value = (segment_base_addr + patch_value) & 0xFFFFFFFF
            word_before = struct.unpack_from("<I", buf, patch_loc)[0]
            struct.pack_into("<I", buf, patch_loc, abs_value)
            traces.append(PatchTrace(
                kind="LINK_PTR", name=f"patch_value=0x{patch_value:x}",
                offset=patch_loc, encoding="abs-u32",
                word_before=word_before, word_after=abs_value,
            ))
        else:
            raise RuntimeError(f"unknown link kind {kind} at table offset {pos-1}")
    return bytes(buf), traces


def apply_x86_patches(main_code: bytes, link_table: bytes,
                      sym_layout: SymTabLayout,
                      segment_base_addr: int) -> tuple[bytes, List[PatchTrace]]:
    """Apply x86 fix-ups to main_code. Mirrors the kernel's symlink_v3 /
    cross_seg_dist_link_v3 / ptr_link_v3 functions (game/kernel/jak1/klink.cpp)
    for byte-for-byte comparison with the arm64 path.

    Strategy:
      - LINK_SYMBOL_OFFSET: read the existing s32 at the offset. If it's -1,
        write the symbol's absolute address (sym_addr_v3); otherwise write
        the symbol-table-relative offset (sym_offset_v3).
      - LINK_DISTANCE_TO_OTHER_SEG_32: write s32 = (target - source_rip).
      - LINK_PTR: write u32 = absolute pointer.
    """
    buf = bytearray(main_code)
    traces: List[PatchTrace] = []
    pos = 0
    while pos < len(link_table):
        kind = link_table[pos]; pos += 1
        if kind == LINK_TABLE_END:
            break
        elif kind == LINK_SYMBOL_OFFSET:
            name, pos = _read_cstr(link_table, pos)
            count = struct.unpack_from("<I", link_table, pos)[0]
            pos += 4
            sym_off = sym_layout.offset_for(name)
            sym_abs = sym_layout.abs_addr(name)
            for _ in range(count):
                instr_offset = struct.unpack_from("<I", link_table, pos)[0]
                pos += 4
                existing = struct.unpack_from("<i", buf, instr_offset)[0]
                if existing == -1:
                    value = sym_abs & 0xFFFFFFFF
                    enc_kind = "abs-u32"
                else:
                    value = sym_off & 0xFFFFFFFF
                    enc_kind = "sym-rel-s32"
                word_before = struct.unpack_from("<I", buf, instr_offset)[0]
                struct.pack_into("<I", buf, instr_offset, value)
                traces.append(PatchTrace(
                    kind="LINK_SYMBOL_OFFSET", name=name, offset=instr_offset,
                    encoding=enc_kind, word_before=word_before, word_after=value,
                ))
        elif kind == LINK_TYPE_PTR:
            _, pos = _read_cstr(link_table, pos)
            pos += 1
            count = struct.unpack_from("<I", link_table, pos)[0]
            pos += 4 + 4 * count
        elif kind == LINK_DISTANCE_TO_OTHER_SEG_64:
            pos += 1 + 12
        elif kind == LINK_DISTANCE_TO_OTHER_SEG_32:
            target_seg = link_table[pos]; pos += 1
            mine_offset = struct.unpack_from("<I", link_table, pos)[0]; pos += 4
            target_offset = struct.unpack_from("<I", link_table, pos)[0]; pos += 4
            patch_loc = struct.unpack_from("<I", link_table, pos)[0]; pos += 4
            if target_seg != 0:
                continue
            mine_addr = segment_base_addr + mine_offset
            target_addr = segment_base_addr + target_offset
            diff = (target_addr - mine_addr) & 0xFFFFFFFF
            word_before = struct.unpack_from("<I", buf, patch_loc)[0]
            struct.pack_into("<I", buf, patch_loc, diff)
            traces.append(PatchTrace(
                kind="LINK_DISTANCE_TO_OTHER_SEG_32", name="rip-rel",
                offset=patch_loc, encoding="s32",
                word_before=word_before, word_after=diff,
            ))
        elif kind == LINK_PTR:
            patch_loc = struct.unpack_from("<I", link_table, pos)[0]; pos += 4
            patch_value = struct.unpack_from("<I", link_table, pos)[0]; pos += 4
            abs_value = (segment_base_addr + patch_value) & 0xFFFFFFFF
            word_before = struct.unpack_from("<I", buf, patch_loc)[0]
            struct.pack_into("<I", buf, patch_loc, abs_value)
            traces.append(PatchTrace(
                kind="LINK_PTR", name="static-ptr", offset=patch_loc,
                encoding="abs-u32", word_before=word_before, word_after=abs_value,
            ))
        else:
            raise RuntimeError(f"unknown link kind {kind}")
    return bytes(buf), traces
