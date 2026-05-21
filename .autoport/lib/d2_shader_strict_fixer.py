#!/usr/bin/env python3
"""
Phase D2 helper — iteratively patch desktop GLSL shaders so that the
GLES-preprocessed variants compile cleanly under glslc.

The desktop shaders under game/graphics/opengl_renderer/shaders/ are
the single source of truth. Desktop GLSL 4.10 core silently coerces
between int and float in most arithmetic contexts; GLES 3.20 does not.
Phase 21 attempted to fix this with a regex pass inside preprocess.py;
that pass broke bitshift / bitwise / array-index ops because it had
no context. The supervisor-D2 redesign moves the strictness fix into
the *source* shaders, where it's a no-op for desktop GLSL but
necessary for GLES.

This tool:

  1. Runs preprocess.py on every shader pair.
  2. Compiles each preprocessed shader with glslc (NDK r27c, opengl
     target, spv1.0 — matches the validator).
  3. For each compile error it can classify, applies a *minimal*
     fix to the upstream .vert/.frag and re-runs.
  4. Repeats until no errors, or until a pass makes no progress
     (then exits 1 so the operator can see what was left).

The set of fixes is intentionally narrow — every fix is a single
literal-suffix change that desktop GLSL accepts unchanged:

  - `pow(x, N)` → `pow(x, N.0)`         (matches the float, float pow overload)
  - `clamp(a, N, ...)` and 3rd arg     → same
  - `mod(a, N)`                        → same
  - `<float_expr> OP <int_literal>`    → `<float_expr> OP <int_literal>.0`
    for OP in `+ - * / < > <= >= == !=` (the error is on this line)
  - `<int_literal> OP <float_expr>`    → `<int_literal>.0 OP ...`
  - `<float_var> = <int_literal>`      → `<float_var> = <int_literal>.0`
  - `<uint_var> == <int_literal>`      → `<uint_var> == <int_literal>u`
  - `<uint_var> != <int_literal>`      → same
  - `<uint_var> OP <int_literal>`      → same for `<` `>` `<=` `>=` `+` `-` `*` `/`

The fixer NEVER touches int literals that are:
  - operands of bitwise ops (`<<` `>>` `&` `|` `^` `%`)
  - inside array indices (`arr[N]`)
  - inside int/uint type declarations
  - hex literals (`0xFFu`)
  - already float (`1.0`, `1e5`) or already u-suffixed

When all classifiable errors are fixed and glslc still complains, the
fixer prints the unresolved errors and exits 1. The operator can then
hand-fix those specific lines and re-run.

Usage:
    d2_shader_strict_fixer.py [shader_src_dir]

Defaults shader_src_dir to game/graphics/opengl_renderer/shaders/.
Environment variables:
  GLSLC          Path to glslc (default: $ANDROID_NDK_HOME/shader-tools/linux-x86_64/glslc).
  D2_MAX_ITERS   Max iterations (default: 8). 1 iteration = 1 preprocess
                 + 1 compile-all + 1 fix-all pass.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SHADER_DIR = REPO_ROOT / "game" / "graphics" / "opengl_renderer" / "shaders"

GLSLC = os.environ.get(
    "GLSLC",
    str(Path.home() / "Android" / "android-ndk-r27c" / "shader-tools"
        / "linux-x86_64" / "glslc"),
)

MAX_ITERS = int(os.environ.get("D2_MAX_ITERS", "8"))


# ---------- Error classification ----------

# Match a glslc/glslang error line of the form
#   <file>:<line>: error: <message>
ERR_LINE_RE = re.compile(r"^[^:]*:(\d+):\s*error:\s*(.+)$")
ERR_HEAD_RE = re.compile(r"^[^:]+:\s*error:\s*(.+)$")  # head-of-file errors


def parse_errors(stderr: str) -> list[tuple[int, str]]:
    """Return a list of (android_line, classified_kind) errors that we
    know how to fix. Errors we don't recognise are surfaced separately
    via the unclassified count from compile_all."""
    out = []
    for line in stderr.splitlines():
        m = ERR_LINE_RE.match(line)
        if not m:
            continue
        line_no = int(m.group(1))
        msg = m.group(2)

        kind = classify(msg)
        if kind:
            out.append((line_no, kind))
    return out


def classify(msg: str) -> Optional[str]:
    """Map a glslc error message to one of our fix kinds, or None.

    glslang formats type qualifiers with a leading space:
      `right operand of type ' const int'` (note the leading space).
    Match accordingly."""
    # Function overload misses on pow/mod/clamp/min/max are all
    # "int literal passed to a float-only signature" in our codebase.
    for builtin in ("pow", "mod", "clamp", "min", "max", "smoothstep"):
        if f"'{builtin}' : no matching overloaded function found" in msg:
            return "int_to_float"

    has_const_int = "const int" in msg
    has_const_float = "const float" in msg
    has_uint = "uint" in msg

    # Assignment of int literal to a float / vec / out float / etc.
    if "'assign' :" in msg and has_const_int and "float" in msg:
        return "int_to_float"

    # Comparison / arithmetic with uint LHS and int literal RHS.
    if has_uint and has_const_int:
        return "uint_op_int"

    # Comparison / arithmetic with float LHS and int literal RHS, or
    # vice versa. We match on the operator and the int-literal hint.
    if has_const_int:
        for op in ("'+'", "'-'", "'*'", "'/'", "'<'", "'>'",
                   "'<='", "'>='", "'=='", "'!='"):
            if op in msg:
                return "int_to_float"

    # Mirror case: float literal where uint was expected (rare).
    if has_uint and has_const_float:
        return "uint_op_int_rhs_float"

    return None


# ---------- Source patching ----------

# Bitwise / shift / modulo: int literals on EITHER side must stay int.
# We mark every int literal touching one of these operators as "skip".
# Use lookbehind/lookahead to avoid mis-classifying `&&` / `||` (logical
# ops, not bitwise) as if they were bitwise — otherwise expressions like
# `pSkip != 0 && ...` get the `0` incorrectly marked as a shift operand.
_BIT_OP = (
    r"(?:<<|>>"
    r"|(?<![&])&(?![&])"
    r"|(?<![|])\|(?![|])"
    r"|\^|%)"
)
BITWISE_RHS = re.compile(_BIT_OP + r"\s*(\d+)\b")
BITWISE_LHS = re.compile(r"\b(\d+)\s*" + _BIT_OP)

# Array indices: arr[N], mat[N][M]
ARRAY_IDX = re.compile(r"\[\s*(\d+)\s*\]")

# Hex literals like 0xFFu, 0x1f, 0X3
HEX_LITERAL = re.compile(r"\b0[xX][0-9a-fA-F]+[uUlL]*\b")

# Bare int literal: not preceded by digit/dot/letter/_, not followed by
# digit/dot/letter/_ (so we skip `1.0`, `10ull`, `0xf`, `tex_T10`).
BARE_INT = re.compile(r"(?<![\.0-9A-Za-z_])(\d+)(?![\.0-9A-Za-z_])")


def _skip_spans(line: str) -> list[tuple[int, int]]:
    """Spans (start, end) inside `line` where bare int literals must
    NOT be promoted."""
    spans: list[tuple[int, int]] = []
    for m in BITWISE_RHS.finditer(line):
        spans.append((m.start(2), m.end(2)))
    for m in BITWISE_LHS.finditer(line):
        spans.append((m.start(1), m.end(1)))
    for m in ARRAY_IDX.finditer(line):
        spans.append((m.start(1), m.end(1)))
    for m in HEX_LITERAL.finditer(line):
        spans.append((m.start(), m.end()))
    # int / uint declaration's INITIALIZER literal: `int N = 5` →
    # don't promote the `5`. We mark only the literal directly following
    # the `=`, not the rest of the line — otherwise function bodies like
    # `bool f(uint a, uint b) { return (a & b) != 0; }` lose the ability
    # to fix the `0` after `!=`.
    for m in re.finditer(
        r"\b(?:int|uint|ivec\d|uvec\d)\s+\w+\s*=\s*(\d+)\b", line
    ):
        spans.append((m.start(1), m.end(1)))
    # Function-parameter list `(int x, uint y)` — parameters are typed
    # via the keyword and don't take literals; nothing to skip here.
    # Array sizes are already covered by ARRAY_IDX.
    return spans


def _in_skip_span(pos: int, spans: list[tuple[int, int]]) -> bool:
    for s, e in spans:
        if s <= pos < e:
            return True
    return False


def patch_int_to_float(line: str) -> str:
    """Promote bare int literals on this line to float, except those in
    bitwise / index / declaration contexts."""
    spans = _skip_spans(line)
    out: list[str] = []
    last = 0
    for m in BARE_INT.finditer(line):
        if _in_skip_span(m.start(), spans):
            continue
        out.append(line[last:m.start()])
        out.append(m.group(1) + ".0")
        last = m.end()
    out.append(line[last:])
    new = "".join(out)
    return new


def patch_int_to_uint(line: str) -> str:
    """Suffix bare int literals on this line with `u`, except those in
    bitshift-amount / index / declaration contexts."""
    spans = _skip_spans(line)
    out: list[str] = []
    last = 0
    for m in BARE_INT.finditer(line):
        if _in_skip_span(m.start(), spans):
            continue
        out.append(line[last:m.start()])
        out.append(m.group(1) + "u")
        last = m.end()
    out.append(line[last:])
    return "".join(out)


# ---------- Preprocess + compile pipeline ----------

def load_preprocessor(shader_dir: Path):
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "preprocess_d2", shader_dir / "preprocess.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def offset_for(desktop_src: str) -> int:
    """Lines added by preprocess. GLES header is 9 lines; preprocess
    strips K leading lines (before #version) and replaces 1 line of
    #version. So new lines = 9 - 1 - K = 8 - K. Android line N maps to
    desktop line N - (8 - K) = N - 8 + K."""
    lines = desktop_src.split("\n")
    for i, ln in enumerate(lines):
        if re.match(r"\s*#version\b", ln):
            return 8 - i  # K = i (0-based index of #version line)
    return 8


def discover_pairs(shader_dir: Path) -> list[tuple[str, Path, Path]]:
    verts = {p.stem: p for p in shader_dir.glob("*.vert")}
    frags = {p.stem: p for p in shader_dir.glob("*.frag")}
    common = sorted(set(verts) & set(frags))
    return [(n, verts[n], frags[n]) for n in common]


def compile_one(android_path: Path, stage: str) -> tuple[int, str]:
    res = subprocess.run(
        [GLSLC,
         "-fauto-map-locations", "-fauto-bind-uniforms",
         f"-fshader-stage={stage}",
         "--target-env=opengl", "--target-spv=spv1.0",
         "-o", "/dev/null",
         str(android_path)],
        capture_output=True, text=True,
    )
    return res.returncode, res.stderr


def run_pass(shader_dir: Path, pp_mod, work_dir: Path) -> tuple[int, int, list[str]]:
    """Run preprocess + compile across every shader. Apply patches.
    Returns (errors_remaining, patches_applied, unclassified_messages)."""
    pairs = discover_pairs(shader_dir)
    errors_remaining = 0
    patches_applied = 0
    unclassified: list[str] = []

    for name, vert_path, frag_path in pairs:
        for kind, src_path, stage in (("vert", vert_path, "vert"),
                                      ("frag", frag_path, "frag")):
            desktop_src = src_path.read_text(encoding="utf-8")
            android_src = pp_mod.to_gles(desktop_src)
            android_path = work_dir / f"{name}.{kind}"
            android_path.write_text(android_src, encoding="utf-8")

            rc, err = compile_one(android_path, stage)
            if rc == 0:
                continue

            offset = offset_for(desktop_src)
            errs = parse_errors(err)
            if not errs:
                # Surface only the head error to keep noise down.
                unclassified.append(f"{name}.{kind}: {err.splitlines()[0] if err else 'unknown'}")
                errors_remaining += 1
                continue

            # Group by desktop line; apply at most one patch kind per
            # line per pass.
            new_lines = desktop_src.split("\n")
            applied_for_file = 0
            patched_line_indices: set[int] = set()
            for android_line, kind_ in errs:
                desktop_line = android_line - offset
                if desktop_line < 1 or desktop_line > len(new_lines):
                    continue
                idx = desktop_line - 1
                if idx in patched_line_indices:
                    continue
                old = new_lines[idx]
                if kind_ == "int_to_float":
                    new = patch_int_to_float(old)
                elif kind_ == "uint_op_int":
                    new = patch_int_to_uint(old)
                else:
                    new = old
                if new != old:
                    new_lines[idx] = new
                    patched_line_indices.add(idx)
                    applied_for_file += 1
            if applied_for_file > 0:
                src_path.write_text("\n".join(new_lines), encoding="utf-8")
                patches_applied += applied_for_file
            errors_remaining += len(errs)

    return errors_remaining, patches_applied, unclassified


def main(argv: list[str]) -> int:
    if len(argv) > 1:
        shader_dir = Path(argv[1]).resolve()
    else:
        shader_dir = DEFAULT_SHADER_DIR
    if not shader_dir.is_dir():
        sys.stderr.write(f"shader dir not found: {shader_dir}\n")
        return 2
    if not Path(GLSLC).is_file():
        sys.stderr.write(f"glslc not found at {GLSLC}\n")
        return 2

    pp_mod = load_preprocessor(shader_dir)
    work_dir = Path(tempfile.mkdtemp(prefix="d2-fixer-"))

    for i in range(MAX_ITERS):
        errs, patches, unclassified = run_pass(shader_dir, pp_mod, work_dir)
        sys.stdout.write(
            f"iter {i + 1}: errors={errs}, patches_applied={patches}, "
            f"unclassified={len(unclassified)}\n"
        )
        if errs == 0:
            sys.stdout.write("all shaders compile cleanly.\n")
            return 0
        if patches == 0:
            sys.stdout.write("no further patches possible; remaining issues:\n")
            for u in unclassified[:30]:
                sys.stdout.write(f"  {u}\n")
            return 1

    sys.stdout.write(f"did not converge in {MAX_ITERS} iterations.\n")
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
