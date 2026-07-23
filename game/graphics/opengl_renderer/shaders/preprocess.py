#!/usr/bin/env python3
"""
Phase D2 (autoport): GLES 3.20 shader preprocessor.

The desktop renderer is GL 4.1 core (every shader starts with
`#version 410 core`). Adreno / Mali Android contexts give us GLES 3.20.
This script transforms each desktop `*.vert` / `*.frag` source into the
GLES variant. The desktop sources are the single source of truth — no
inline `#ifdef`s in the .vert/.frag files.

History: phase 21 attempted a regex-based int->float promotion pass to
patch the relative strictness of GLES vs desktop GLSL. The regex pass
was unsound: it broke `>> 7` on uint (LHS of bitshift must be int),
`!= 0` after `& mask` (uint comparison), `mod(uint, uint)`, and many
other places where the int literal was actually correct. The
supervisor-D2 redesign moves the strictness fix into the upstream
desktop sources: every shader is now written in a way that compiles
cleanly under both desktop GLSL 4.10 core AND GLES 3.20. The
preprocessor stays thin — it does only the structural transforms
that the source can't express portably:

    1. Strip any header comment that precedes the first `#version`
       directive (GLES requires `#version` to be the literal first
       statement; the desktop GLSL spec is permissive).
    2. Replace the `#version 410 core` line with `#version 320 es`
       plus the default precision qualifier block GLES requires.
    3. Leave the per-game template tokens (HEIGHT_SCALE,
       SCISSOR_HEIGHT, SCISSOR_ADJUST) verbatim; Shader.cpp
       substitutes them at runtime per GameVersion on Android exactly
       like it does on desktop.
    4. `sampler1D` does not exist in GLES (1D textures are not in the
       ES feature set). Rewrite each `uniform sampler1D <name>;` to
       `uniform sampler2D <name>;` and adjust every
       `texelFetch(<name>, idx, lod)` call site to `texelFetch(<name>,
       ivec2(idx, 0), lod)`. The runtime is expected to upload the
       backing texture as an Nx1 GL_TEXTURE_2D under GLES; that's a
       D3 concern (texture pipeline), not D2.
    5. Strip the `noperspective` interpolation qualifier — it requires
       NV_shader_noperspective_interpolation in GLES (Adreno 6xx does
       not expose it). Falling back to smooth perspective-correct
       interpolation is a visible but bounded artifact for the sky
       shader only; the desktop and Android renderers will look
       identical for everything else.

Anything beyond these structural transforms must be in the upstream
shader source. That keeps the preprocessor auditable and prevents the
phase 21 cheat (regex pass that quietly mutated semantics).

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


_VERSION_LINE = re.compile(
    r"^[ \t]*#version[^\n]*\n",
    re.MULTILINE,
)

_UNIFORM_SAMPLER1D = re.compile(
    r"\buniform\s+sampler1D\s+(\w+)\s*;",
)

_SAMPLER1D_TYPE = re.compile(r"\bsampler1D\b")

_NOPERSPECTIVE = re.compile(r"\bnoperspective\b\s*")


def _strip_leading_to_version(src: str) -> str:
    """GLES 3.20 requires `#version` to be the first non-empty content
    in the file. Strip any leading whitespace, line comments, and block
    comments that precede it. Returns the source from `#version`
    onwards; if no `#version` line exists we return the input unchanged
    (preprocess.py is not the place to invent one)."""
    m = _VERSION_LINE.search(src)
    if not m:
        return src
    return src[m.start():]


def _rewrite_sampler1d(src: str) -> str:
    """Rewrite `uniform sampler1D foo;` to `uniform sampler2D foo;` and
    every matching `texelFetch(foo, idx, lod)` to
    `texelFetch(foo, ivec2(idx, 0), lod)`. We only rewrite texelFetch
    calls whose first argument is a known sampler1D name; this avoids
    accidentally rewriting calls that target genuine sampler2D
    uniforms with the same shape."""
    names = _UNIFORM_SAMPLER1D.findall(src)
    if not names:
        return src
    # Rewrite the type declaration.
    src = _SAMPLER1D_TYPE.sub("sampler2D", src)
    # Rewrite each call site. The idx argument may be a simple
    # identifier or a complex expression (function call, arithmetic).
    # We tolerate commas inside parens / function calls by parsing
    # the call site manually rather than via regex backreference.
    for name in names:
        src = _rewrite_texel_fetch_for(src, name)
    return src


def _rewrite_texel_fetch_for(src: str, sampler_name: str) -> str:
    """Find every `texelFetch(sampler_name, IDX, LOD)` and rewrite to
    `texelFetch(sampler_name, ivec2(IDX, 0), LOD)`. IDX is whatever lives
    between the first and second top-level comma; LOD is whatever lives
    between the second top-level comma and the matching `)`."""
    out = []
    i = 0
    # Precompute a regex that matches `texelFetch(<sampler_name>` so we
    # can locate every call site cheaply, then balance parens manually.
    head = re.compile(
        r"\btexelFetch\s*\(\s*" + re.escape(sampler_name) + r"\s*,"
    )
    while True:
        m = head.search(src, i)
        if not m:
            out.append(src[i:])
            break
        # Emit everything up to and including the first comma after the
        # sampler name (kept verbatim).
        out.append(src[i:m.end()])
        # We now stand inside the parens, just past the first comma.
        # Walk forward to find the top-level comma separating IDX from
        # LOD, then find the matching close paren.
        j = m.end()
        depth = 1
        idx_start = j
        idx_end = None
        lod_start = None
        lod_end = None
        while j < len(src):
            c = src[j]
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    lod_end = j
                    break
            elif c == ',' and depth == 1:
                if idx_end is None:
                    idx_end = j
                    lod_start = j + 1
                # Further commas are inside a nested expression — not
                # valid for a 3-arg texelFetch, but we ignore them.
            j += 1
        if idx_end is None or lod_end is None:
            # Malformed; bail out without rewriting this call.
            out.append(src[m.end():j + 1])
            i = j + 1
            continue
        idx_expr = src[idx_start:idx_end].strip()
        lod_expr = src[lod_start:lod_end].strip()
        out.append(f" ivec2({idx_expr}, 0), {lod_expr})")
        i = lod_end + 1
    return "".join(out)


def _strip_noperspective(src: str) -> str:
    """GLES 3.20 has no `noperspective` qualifier (the
    NV_shader_noperspective_interpolation extension is not present on
    Adreno 6xx, our target GPU). Stripping it falls back to smooth
    perspective-correct interpolation, which only affects the sky
    shader's tex_coord and is visually indistinguishable for the
    bounded UV range the sky pass uses."""
    return _NOPERSPECTIVE.sub("", src)


def to_gles(src: str, stage: str | None = None) -> str:
    """Return the GLES 3.20 form of one desktop GLSL shader source.

    The transforms applied here are structural only. Numeric semantics
    are preserved verbatim — if the source compiles under desktop
    GLSL 4.10 core, the GLES variant must compile under GLES 3.20 and
    behave identically modulo the documented sampler1D and
    noperspective workarounds. Anything stricter (uint vs int literal
    typing, float vs int literal in float contexts) is fixed in the
    upstream source, not here.
    """
    # 1. Strip any leading comments / blank lines so #version is first.
    src = _strip_leading_to_version(src)

    # 2. Replace the version directive with the GLES header. The tessellation stages
    #    (.tesc/.tese) need the GL_EXT_tessellation_shader extension enabled right after
    #    #version; ": enable" (not "require") so a core-3.2 compiler that already knows the
    #    stages natively only warns instead of erroring on the unknown extension.
    if stage in ("tesc", "tese"):
        header = GLES_HEADER.replace(
            "#version 320 es\n",
            "#version 320 es\n#extension GL_EXT_tessellation_shader : enable\n",
            1,
        )
    else:
        header = GLES_HEADER
    src = _VERSION_LINE.sub(header, src, count=1)

    # 3. The HEIGHT_SCALE / SCISSOR_HEIGHT / SCISSOR_ADJUST template
    #    tokens are left verbatim: they are per-game (jak1 448-line vs
    #    jak2 416-line), so Shader.cpp substitutes them at runtime on
    #    Android exactly like desktop (baking jak1 values stretched all
    #    jak2 geometry ~1.85x vertically).

    # 4. sampler1D → sampler2D, fixup matching texelFetch call sites.
    src = _rewrite_sampler1d(src)

    # 5. Drop noperspective qualifier.
    src = _strip_noperspective(src)

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
    """Return a sorted list of (name, vert_path, frag_path, tesc_path, tese_path)
    for every shader in src_dir. A shader must have at least a .vert AND a .frag,
    OR (REOPEN #3 tessellation) a .vert with a matching .tesc + .tese (a tess group,
    which has no .frag of its own — it reuses another shader's fragment source at
    link time). tesc_path/tese_path are None when absent. Partial sets are skipped
    with a warning rather than failing the build."""
    verts = {p.stem: p for p in src_dir.glob("*.vert")}
    frags = {p.stem: p for p in src_dir.glob("*.frag")}
    tescs = {p.stem: p for p in src_dir.glob("*.tesc")}
    teses = {p.stem: p for p in src_dir.glob("*.tese")}

    # A name is valid if it has (vert + frag) or (vert + tesc + tese).
    names = set()
    for name, vp in verts.items():
        has_frag = name in frags
        has_tess = name in tescs and name in teses
        if has_frag or has_tess:
            names.add(name)
        else:
            sys.stderr.write(
                f"preprocess.py: orphan shader (vert without frag/tess pair): {name}\n"
            )
    # frags with no matching vert are orphans (except when they are reused as a tess
    # group's fragment source — those still get emitted here via their own vert pair).
    for name in frags:
        if name not in verts:
            sys.stderr.write(f"preprocess.py: orphan shader (frag without vert): {name}\n")

    out = []
    for name in sorted(names):
        out.append((
            name,
            verts[name],
            frags.get(name),
            tescs.get(name),
            teses.get(name),
        ))
    return out


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
        "// Phase D2 (autoport): GLES 3.20 variants of every desktop shader.",
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
        "  // REOPEN #3 TESSELLATION: empty for non-tess shaders. A tess group carries its",
        "  // vert/tesc/tese here and reuses another shader's frag_src at link time.",
        "  std::string_view tesc_src;",
        "  std::string_view tese_src;",
        "};",
        "",
        "inline constexpr ShaderSource kShaders[] = {",
    ]

    for name, vert_path, frag_path, tesc_path, tese_path in pairs:
        vert_src = to_gles(vert_path.read_text(encoding="utf-8"))
        (out_dir / f"{name}.android.vert").write_text(vert_src, encoding="utf-8")

        if frag_path is not None:
            frag_src = to_gles(frag_path.read_text(encoding="utf-8"))
            (out_dir / f"{name}.android.frag").write_text(frag_src, encoding="utf-8")
        else:
            frag_src = ""

        if tesc_path is not None and tese_path is not None:
            tesc_src = to_gles(tesc_path.read_text(encoding="utf-8"), stage="tesc")
            tese_src = to_gles(tese_path.read_text(encoding="utf-8"), stage="tese")
            (out_dir / f"{name}.android.tesc").write_text(tesc_src, encoding="utf-8")
            (out_dir / f"{name}.android.tese").write_text(tese_src, encoding="utf-8")
        else:
            tesc_src = ""
            tese_src = ""

        blob_lines.append(
            "    {"
            f'\n        "{name}",'
            f"\n        {c_string_literal(vert_src)},"
            f"\n        {c_string_literal(frag_src)},"
            f"\n        {c_string_literal(tesc_src)},"
            f"\n        {c_string_literal(tese_src)}"
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
