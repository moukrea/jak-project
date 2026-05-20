#!/usr/bin/env python3
"""
Phase 21 (autoport): GLES 3.20 shader preprocessor.

The desktop renderer is GL 4.1 core (every shader starts with
`#version 410 core`). Adreno / Mali Android contexts give us GLES 3.20.
This script transforms each desktop `*.vert` / `*.frag` source into the
GLES variant in a way that keeps the desktop source the single source of
truth — no inline `#ifdef`s in the .vert/.frag files.

The transform:
    1. Replace `#version 410 core` with `#version 320 es`.
    2. Inject default precision qualifiers (GLES has no implicit default
       for `float` in fragment shaders, and none for ints / int samplers
       in vertex shaders either).
    3. Substitute the jak1 template tokens (HEIGHT_SCALE, SCISSOR_HEIGHT,
       SCISSOR_ADJUST) the same way Shader.cpp's regex_replace does at
       runtime on desktop, so the Android-side runtime can compile the
       output directly without re-doing the substitution.

Outputs:
    <out_dir>/<name>.android.vert
    <out_dir>/<name>.android.frag    (one per source)
    <out_dir>/shaders_android_blob.h (a generated C header that lists
                                      every preprocessed shader as a
                                      pair of constexpr `string_view`s,
                                      ready to be #included by the
                                      Android boot path)

Usage:
    preprocess.py <shaders_src_dir> <out_dir>
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

# Match the values Shader.cpp picks for Jak1. Phase 21 boots jak1 only;
# phases 22+ will need a per-game variant if/when we wire jak2/jak3.
JAK1_HEIGHT_SCALE = "1.0"
JAK1_SCISSOR_HEIGHT = "448.0"
JAK1_SCISSOR_ADJUST = "(512.0 / 448.0)"

# GLES 3.20 wants precision qualifiers up front. `highp` for everything
# we care about — Adreno 6xx / Mali G7x handle it without falling back
# to slower paths, and using `mediump` here would silently quantise the
# game's worldspace math.
GLES_HEADER = """#version 320 es
precision highp float;
precision highp int;
precision highp sampler2D;
precision highp sampler3D;
precision highp sampler2DArray;
precision highp samplerCube;
precision highp isampler2D;
precision highp usampler2D;
"""


def to_gles(src: str) -> str:
    """Return the GLES 3.20 form of one desktop GLSL shader source."""
    # 1. Replace the first `#version ...` line with the GLES header.
    #    Some sources have a leading `//` comment before #version; we
    #    only touch the version line itself, leaving comments alone.
    src = re.sub(
        r"^[ \t]*#version[^\n]*\n",
        GLES_HEADER,
        src,
        count=1,
        flags=re.MULTILINE,
    )

    # 2. Substitute the template tokens that desktop's Shader.cpp would
    #    fill in at runtime via std::regex_replace.
    src = src.replace("SCISSOR_ADJUST", JAK1_SCISSOR_ADJUST)
    src = src.replace("SCISSOR_HEIGHT", JAK1_SCISSOR_HEIGHT)
    src = src.replace("HEIGHT_SCALE", JAK1_HEIGHT_SCALE)

    # 3. Phase 29 (autoport): promote bare integer literals used in `*` /
    #    `/` arithmetic to float literals. Desktop GLSL (#version 410)
    #    silently promotes `float * int_literal` to `float * float`;
    #    GLES 3.20 strict-mode (Adreno) rejects the same expression with
    #    `wrong operand types ... 'float' ... 'const int'`. Patterns
    #    affected: `* 32`, `* 16`, `* 64`, `* 2`, `/ 16`, etc. — anywhere
    #    a vertex shader scales a float coordinate by an int literal.
    #    We skip integer-only operators (`&`, `|`, `^`, `<<`, `>>`, `%`)
    #    so bit ops like `gl_VertexID & 1` remain valid. The negative
    #    lookahead `(?![\d.uU])` keeps `* 1u`, `* 1.5`, `* 100` (when
    #    immediately followed by another digit, i.e. `* 1000`) intact.
    # `*`, `/`, `*=`, `/=`, `+=`, `-=` with zero-or-more whitespace
    # before the int (tight `*2` and roomy `* 2` are equally common in
    # jak1 shaders). The `+=`/`-=` cases catch lines like
    # `transformed.z -= 1` in shadow2.vert.
    src = re.sub(r"(\*=?|/=?|\+=|-=)(\s*)(\d+)(?![\d\.uU])", r"\1\2\3.0", src)

    # Binary `-` and `+` between a float left-hand and an int literal
    # right-hand. Two variants: tight (`2.0-1`, `.w-1`) and loose
    # (`2.0 - 1`, `.w  - 1`). Both must skip unary `-1` in `vec4(-1, …)`,
    # so we require a non-paren/non-comma/non-space char immediately
    # before the operator (tight) or before the leading whitespace (loose).
    src = re.sub(r"(?<=[\w\])])([-+])(\s*)(\d+)(?![\d\.uU])", r"\1\2\3.0", src)
    src = re.sub(r"([\w\])])(\s+)([-+])(\s*)(\d+)(?![\d\.uU])",
                 r"\1\2\3\4\5.0", src)

    # `<int>`, `<= <int>`, `> <int>`, `>= <int>` comparisons: most appear
    # in `coord.x < 0` / `frag.a <= 0` style float predicates. Promote
    # the literal so GLES strict doesn't reject the comparison.
    src = re.sub(r"([<>]=?)(\s*)(\d+)(?![\d\.uU])", r"\1\2\3.0", src)

    # Promote bare `<int>` literals that appear as the LEFT operand of a
    # `-` or `+` (e.g. `255 - position_in.w`), or that appear inside a
    # negated paren `-(\d+)` or scalar paren `(\d+)`. The lookbehind
    # restricts us to contexts that originate at an expression boundary
    # (`=`, `,`, `(`, whitespace) so we don't touch `int idx = 255` etc.
    src = re.sub(r"(?<=[=,(\s])(\d+)(\s*[-+]\s*)(?=[A-Za-z_(])", r"\1.0\2", src)

    # Numerics inside paren-only scalar expressions like `(8388608)` or
    # `(256)` used as divisor/subtrahend in float math. We rewrite the
    # bare integer to a float literal so `transformed.z /= (8388608)`
    # becomes `... /= (8388608.0)`.
    src = re.sub(r"\((\d+)\)", r"(\1.0)", src)

    # Assignment-to-float-builtin patterns. `gl_FragDepth = 1;` is
    # `float = int` which Adreno strict rejects. We patch the two
    # known-shadowed lvalues; anything else we miss falls back to the
    # shader's own author writing `.0`.
    src = re.sub(r"(gl_FragDepth\s*=\s*)(\d+)(?![\d\.uU])", r"\1\2.0", src)

    # 4. gl_FragDepth in GLES 3.x is built in — no extension required.
    #    No transformation needed; left as a note for future readers.

    return src


def c_string_literal(s: str) -> str:
    """Quote a string as a C raw literal so we can embed it verbatim in
    a header. Using R"GLSL(...)GLSL" lets us preserve newlines / quotes
    in the shader source without escaping. The delimiter is chosen so it
    cannot collide with anything in real shader text."""
    delim = "AUTOPORTGLES"
    assert delim not in s, "delimiter collision in shader source"
    return f'R"{delim}({s}){delim}"'


def discover_shaders(src_dir: Path):
    """Return a sorted list of (name, vert_path, frag_path) for every
    shader pair in src_dir. A shader pair must have both .vert and .frag
    — partial sets are skipped with a warning rather than failing the
    build (a one-off broken pair shouldn't gate the whole port)."""
    verts = {p.stem: p for p in src_dir.glob("*.vert")}
    frags = {p.stem: p for p in src_dir.glob("*.frag")}
    common = sorted(set(verts) & set(frags))
    orphans = sorted((set(verts) ^ set(frags)))
    for o in orphans:
        sys.stderr.write(f"preprocess.py: orphan shader (missing pair): {o}\n")
    return [(name, verts[name], frags[name]) for name in common]


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        sys.stderr.write("usage: preprocess.py <shaders_src_dir> <out_dir>\n")
        return 2

    src_dir = Path(argv[1]).resolve()
    out_dir = Path(argv[2]).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    pairs = discover_shaders(src_dir)
    if not pairs:
        sys.stderr.write(f"preprocess.py: no shaders found under {src_dir}\n")
        return 1

    # Emit individual files (per-shader on disk) so a future phase that
    # wants file-based shader loading already has them. Also collect
    # everything into a single header for direct embedding.
    blob_lines = [
        "// Auto-generated by preprocess.py — DO NOT EDIT.",
        "// Phase 21 (autoport): GLES 3.20 variants of every desktop shader.",
        "#pragma once",
        "",
        "#include <string_view>",
        "",
        "namespace gk_android_shaders {",
        "",
        "struct ShaderSource {",
        "  std::string_view name;",
        "  std::string_view vert_src;",
        "  std::string_view frag_src;",
        "};",
        "",
        "inline constexpr ShaderSource kShaders[] = {",
    ]

    for name, vert_path, frag_path in pairs:
        vert_src = to_gles(vert_path.read_text(encoding="utf-8"))
        frag_src = to_gles(frag_path.read_text(encoding="utf-8"))

        (out_dir / f"{name}.android.vert").write_text(vert_src, encoding="utf-8")
        (out_dir / f"{name}.android.frag").write_text(frag_src, encoding="utf-8")

        blob_lines.append(
            "    {"
            f'\n        "{name}",'
            f"\n        {c_string_literal(vert_src)},"
            f"\n        {c_string_literal(frag_src)}"
            "\n    },"
        )

    blob_lines.append("};")
    blob_lines.append("")
    blob_lines.append("inline constexpr int kShaderCount = "
                      f"sizeof(kShaders) / sizeof(kShaders[0]);")
    blob_lines.append("")
    blob_lines.append("}  // namespace gk_android_shaders")
    blob_lines.append("")

    (out_dir / "shaders_android_blob.h").write_text(
        "\n".join(blob_lines), encoding="utf-8"
    )

    sys.stdout.write(
        f"preprocess.py: emitted {len(pairs)} shader pairs + blob header to "
        f"{out_dir}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
