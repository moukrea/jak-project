#!/usr/bin/env python3
"""Phase A1 — deterministic classifier for the AArch64 IR emitter.

Reads ``goalc/compiler/IR.cpp`` and classifies every
``IR_<name>::do_codegen_arm64`` function body as ``real`` or ``stub``.

A body is ``real`` iff it emits at least one non-NOP AArch64 instruction.
Concretely the body must contain *either*

  - a call to ``emitter::IGen::ARM64::<fn>`` where ``<fn>`` is not the
    literal ``nop`` (any ARM64 IGen encoder counts), or
  - a call to ``emitter::InstructionARM64(<imm>)`` where ``<imm>`` is not
    the NOP encoding ``0xd503201fu`` (case-insensitive on the ``u`` /
    ``U`` suffix and on the hex digits).

Otherwise the body is ``stub``.  The intent is that an empty body, a
body that only ``(void)``-casts its parameters, or a body that only
emits ``nop`` placeholders all classify as ``stub``.

The script is invoked by ``.autoport/validators/phase-A1-emitter-
enumerate.sh`` and must be **deterministic**: the validator runs it
twice and compares ``sha256sum`` outputs.  Sorting keys + a fixed JSON
shape gives that guarantee.

Output: a JSON object printed to stdout, e.g.::

    {"IR_Return": "real", "IR_VFMath3Asm": "stub", ...}
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


# Anchored at line start; we accept any return type prefix that begins
# with "void".  The class name we capture is whatever follows ``IR_``
# (the prefix is preserved in the output so downstream consumers can
# match against IR.h declarations).
_FUNC_RE = re.compile(
    r"^void\s+(IR_[A-Za-z0-9_]+)::do_codegen_arm64\s*\(",
    re.MULTILINE,
)

# An emit call we consider "real" must:
#   - reference ``emitter::IGen::ARM64::<fn>`` where ``<fn>`` is any
#     identifier other than ``nop``, OR
#   - reference ``emitter::InstructionARM64(<imm>)`` where ``<imm>`` is
#     a hex literal that is **not** the NOP encoding ``0xd503201fu``.
#
# We deliberately ignore comments: the regex matches the call shape,
# and the body-extractor below strips ``//`` line comments and ``/*
# */`` block comments before scanning.

_REAL_IGEN_RE = re.compile(
    r"emitter::IGen::ARM64::([A-Za-z_][A-Za-z0-9_]*)\s*\(",
)

_INSTR_RE = re.compile(
    r"emitter::InstructionARM64\s*\(\s*(0x[0-9A-Fa-f]+)\s*[uU]?\s*[,\)]",
)

_NOP_ENCODING = 0xD503201F  # AArch64 ``nop``


def _strip_comments(src: str) -> str:
    """Remove ``//`` and ``/* */`` comments — purely textual."""

    # Block comments first so we don't get confused by ``//`` inside them.
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.DOTALL)
    # Line comments.
    src = re.sub(r"//[^\n]*", "", src)
    return src


def _extract_body(text: str, header_start: int) -> str | None:
    """Return the function body (between matched ``{`` ``}``) starting at
    ``header_start``.  Returns ``None`` if no opening brace is found."""

    open_idx = text.find("{", header_start)
    if open_idx < 0:
        return None
    depth = 0
    i = open_idx
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[open_idx + 1 : i]
        i += 1
    return None


def _body_is_real(body: str) -> bool:
    """Return True if the body emits at least one non-NOP arm64 instr."""

    stripped = _strip_comments(body)

    for m in _REAL_IGEN_RE.finditer(stripped):
        if m.group(1) != "nop":
            return True

    for m in _INSTR_RE.finditer(stripped):
        try:
            value = int(m.group(1), 16)
        except ValueError:  # pragma: no cover — regex constrains to hex
            continue
        if value != _NOP_ENCODING:
            return True

    return False


def classify(ir_cpp_path: Path) -> dict[str, str]:
    text = ir_cpp_path.read_text(encoding="utf-8", errors="replace")
    result: dict[str, str] = {}

    for m in _FUNC_RE.finditer(text):
        cls = m.group(1)
        body = _extract_body(text, m.end())
        if body is None:
            # Unbalanced braces — treat as stub for safety; the
            # validator's spot-check will surface the real issue.
            result[cls] = "stub"
            continue
        result[cls] = "real" if _body_is_real(body) else "stub"

    return result


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(
            "usage: classify_ir_arm64.py <path-to-IR.cpp>",
            file=sys.stderr,
        )
        return 2

    ir_cpp = Path(argv[1])
    if not ir_cpp.is_file():
        print(f"file not found: {ir_cpp}", file=sys.stderr)
        return 2

    classification = classify(ir_cpp)
    # Sort keys for determinism + stable output across two runs.
    sys.stdout.write(json.dumps(classification, sort_keys=True, indent=2))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
