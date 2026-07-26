#!/usr/bin/env python3
"""Grecharged-pbr-realtime-fusion ROUND 22 — shader `#include` expander (reference impl).

This is the PYTHON MIRROR of Shader.cpp's `expand_includes()`. It exists for two
reasons:

  1. THE BYTE-IDENTITY PROOF. Round 22 lifts ~1000 lines of the fused rt+pbr path
     out of tfrag3.frag into shared chunks (pbr_uniforms.glsl / pbr_helpers.glsl /
     pbr_fused.glsl) so shrub / tie_wind / etie_base can run the SAME code instead
     of a fourth copy. The owner has already validated tfrag3's look this round
     ("ça correspond vraiment"), so the extraction has to be a provable NO-OP:

         python3 .autoport/gpbrf_r22_include_expand.py \
             game/graphics/opengl_renderer/shaders/tfrag3.frag > /tmp/expanded.frag
         diff /tmp/expanded.frag /tmp/tfrag3.frag.orig     # must print NOTHING

  2. The GLSL compile gate (.autoport/gpbrf_r22_glslcheck.sh) needs the expanded
     text before it can hand a stage to glslc.

BECAUSE of (1), a chunk file's text is emitted VERBATIM — a chunk may not carry a
doc header of its own, or tfrag3.frag's expansion would no longer be byte-identical
to the pre-extraction file. The per-chunk "names that must be in scope" contract is
therefore documented at each CONSUMER's adapter preamble (search for
"PBR FUSED CHUNK CONTRACT" in shrub.frag / tie_wind.frag / etie_base.frag) rather
than inside pbr_fused.glsl.

For the record, the contract of pbr_fused.glsl is:

  varyings / uniforms (declared by the shader, or by pbr_uniforms.glsl):
    fragment_color (vec4)   the baked per-vertex TOD colour
    tex_coord      (vec3)   .xy = the BASE COLOUR uv; every PBR map rides this uv
    v_fringe_rel   (vec3)   camera-relative world position, METRES
    v_tangent      (vec4)   xyz = world tangent, w = handedness. (0,0,0,*) => the
                            chunk falls back to the CONTINUOUS normal-derived basis
                            (frisvad_basis / stable_frame) — never a screen-space
                            derivative frame.
    color          (out vec4)  written by the chunk (rgb only)
    tex_T0         (sampler2D) the albedo the draw is binding

  locals the enclosing scope MUST define before the include:
    N        (vec3)  smooth, outward-aligned world normal of this fragment
    Vv       (vec3)  surface -> camera, unit
    L        (vec3)  surface -> yellow sun, unit  (== normalize(u_rt_sun_dir))
    sun_occ  (float) yellow-sun cast-shadow visibility, 1 = lit
    moon_occ (float) green-sun cast-shadow visibility, 1 = lit
    T0       (vec4)  texture(tex_T0, tex_coord.xy) — the un-offset base sample
    f_disp_cover (float) set to 1.0 by the chunk where displacement really ran

  helper functions that must already be declared (pbr_helpers.glsl + the shader's
  own rt block): stable_frame, frisvad_basis, hnorm, pom_depth_uv, rt_amb_eval,
  pbr_micro_shadow, pbr_cavity, rt_sh_ambient, rt_ibl_ambient.

Usage:
    gpbrf_r22_include_expand.py <shader-file> [chunk-dir] [--check <reference>]

`chunk-dir` defaults to the shader file's own directory (that is also how the
desktop runtime resolves a chunk: file_util path {shader_folder, name}).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

MAX_DEPTH = 4

# Same shape Shader.cpp accepts: optional leading whitespace, #include, a
# double-quoted chunk name, nothing else but whitespace on the line.
_INCLUDE = re.compile(r'^[ \t]*#include[ \t]*"([^"]+)"[ \t]*$')


def expand(src: str, chunk_dir: Path, depth: int = 0) -> str:
    if "#include" not in src:
        return src
    if depth > MAX_DEPTH:
        sys.stderr.write(
            f"[include] ERROR: #include nesting deeper than {MAX_DEPTH} — giving up\n")
        return src
    out = []
    missing = False
    for line in src.splitlines(keepends=True):
        m = _INCLUDE.match(line.rstrip("\r\n"))
        if not m:
            out.append(line)
            continue
        name = m.group(1)
        path = chunk_dir / name
        if not path.is_file():
            sys.stderr.write(
                f"[include] ERROR: shader chunk '{name}' NOT FOUND under {chunk_dir} — "
                f"leaving the directive in place so the compile fails loudly\n")
            missing = True
            out.append(line)
            continue
        out.append(expand(path.read_text(encoding="utf-8"), chunk_dir, depth + 1))
    if missing:
        # Mirrors Shader.cpp: a missing chunk returns the source UNCHANGED so the
        # raw #include survives into the compiler (hard, unmissable error).
        return src
    return "".join(out)


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:]]
    ref = None
    if "--check" in args:
        i = args.index("--check")
        ref = Path(args[i + 1])
        del args[i:i + 2]
    if not args:
        sys.stderr.write(__doc__ or "")
        return 2
    src_path = Path(args[0]).resolve()
    chunk_dir = Path(args[1]).resolve() if len(args) > 1 else src_path.parent
    text = expand(src_path.read_text(encoding="utf-8"), chunk_dir)
    if ref is None:
        sys.stdout.write(text)
        return 0
    reference = ref.read_text(encoding="utf-8")
    if text == reference:
        sys.stdout.write(f"IDENTICAL: expanded {src_path.name} == {ref}\n")
        return 0
    import difflib
    sys.stdout.write(f"DIFFERS: expanded {src_path.name} != {ref}\n")
    for d in difflib.unified_diff(reference.splitlines(keepends=True),
                                  text.splitlines(keepends=True),
                                  fromfile=str(ref), tofile=f"expanded:{src_path.name}"):
        sys.stdout.write(d)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
