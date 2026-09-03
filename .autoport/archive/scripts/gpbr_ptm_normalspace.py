#!/usr/bin/env python3
"""gpbr_ptm_normalspace.py — phase Gpbr-per-texture-materials: measure, PER TEXTURE, which normal-map
SPACE each shipped map is authored in (OpenGL green-up vs DirectX green-down).

WHY THIS MEASUREMENT EXISTS. The phase contract names three things to instrument before touching
materials: the UV orientation, the bitangent sign, and THE NORMAL SPACE. The first two are per-face
and live in tools/tess_sign. This one is per TEXTURE, and it is the one that decides a per-texture
material parameter, so it belongs here. The engine decodes every normal map the same way —
pbr_fused.glsl: `vec3 nraw = texture(tex_PBR_N, uv).xyz * 2.0 - 1.0;` — with no per-material green
sign anywhere in the shader tree before this phase (grep for flip_y/green: zero hits that touch a
normal map). So OpenGL is ASSUMED for all of them, and an assumption is not a measurement.

WHAT IT CAN AND CANNOT DECIDE -- read this before reading a number, because the obvious reading is
the wrong one and I made it first.
  * IT CAN decide whether the seven materials are HOMOGENEOUS: do they all place their green
    channel the same way relative to their own height field? That is a comparison of materials
    against each other, so every convention that is shared by all of them cancels out.
  * IT CANNOT decide whether that shared convention matches the one the engine assumes. That is a
    GLOBAL question -- one bit for all seven -- and answering it needs the row order the loader
    uploads with AND the orientation the level's own UVs give V. Neither is recorded in these
    files, and no amount of staring at a PNG produces it. Publishing a per-texture "flipped"
    verdict off this measurement would be a false red: it would send the next cycle chasing seven
    materials for a single global bit.

NATURE / FRAME / VALUE-WHEN-THE-DEFECT-IS-ABSENT (the three questions DIRECTIVES requires of any
published quantity):
  * NATURE: two correlation coefficients, dimensionless, in [-1, 1]. Not an amplitude.
  * FRAME: image space of the material's own maps. dU is +x (column index), dV is +y (row index).
    Both maps are sampled on the same grid, so no resampling and no world units enter.
  * WHEN THE DEFECT IS ABSENT: every material shows the SAME (sign of cx, sign of cy) pair. The
    defect this instrument exists to find is a MIX -- one material shipping its green the other way
    round from its neighbour, which no global setting can repair and a per-texture normal_y can.
    A material whose pair differs from the majority is the finding; a unanimous table means the
    per-texture knob has nothing to correct today, and says so.

CAVEAT, STATED RATHER THAN HIDDEN: the correlation is only meaningful when the normal map was
actually DERIVED from the height map that ships next to it. |c| near zero for BOTH channels means
the two maps are unrelated (independently authored), and the test then says nothing — it is
reported as INDETERMINATE, never as "OpenGL by default".

Usage: python3 .autoport/gpbr_ptm_normalspace.py [--root DIR] [--out FILE]
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None


def load_gray(path):
    im = Image.open(path)
    a = np.asarray(im.convert("L"), dtype=np.float64) / 255.0
    return a


def load_rgb(path):
    im = Image.open(path)
    a = np.asarray(im.convert("RGB"), dtype=np.float64) / 255.0
    return a


def corr(a, b):
    a = a.ravel()
    b = b.ravel()
    a = a - a.mean()
    b = b - b.mean()
    da = np.sqrt((a * a).sum())
    db = np.sqrt((b * b).sum())
    if da < 1e-12 or db < 1e-12:
        return 0.0
    return float((a * b).sum() / (da * db))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="custom_assets/jak1/recharged_textures")
    ap.add_argument("--out", default=".autoport/reports/Gpbr-per-texture-materials/normal_space.txt")
    args = ap.parse_args()

    pairs = []
    for dirpath, _dirs, files in os.walk(args.root):
        for f in sorted(files):
            if f.endswith("_normal.png"):
                stem = f[: -len("_normal.png")]
                h = os.path.join(dirpath, stem + "_height.png")
                if os.path.exists(h):
                    pairs.append((stem, os.path.join(dirpath, f), h))
    pairs.sort()

    lines = []
    def emit(s=""):
        lines.append(s)
        print(s)

    emit("== PER-TEXTURE NORMAL-MAP SPACE CENSUS (phase Gpbr-per-texture-materials) ==")
    emit()
    emit("NATURE  two dimensionless correlations in [-1,1] -- NOT an amplitude.")
    emit("FRAME   the material's own image grid; dU = +x (columns), dV = +y (rows). Both maps are")
    emit("        sampled on the same grid, so no resampling and no world units enter.")
    emit("ABSENT  every material shows the SAME (sign cx, sign cy) pair. What this instrument can")
    emit("        find is a MIX -- one material placing its green channel the other way round from")
    emit("        its neighbour -- because a comparison of materials AGAINST EACH OTHER cancels")
    emit("        every convention they share. A material whose pair differs from the majority is")
    emit("        the finding; a unanimous table means a per-texture normal_y has nothing to")
    emit("        correct today.")
    emit("CANNOT  decide whether the SHARED convention is the one the engine assumes. That is one")
    emit("        GLOBAL bit, and answering it needs the loader's upload row order and the")
    emit("        orientation the level's own UVs give V -- neither is in these files. Reading a")
    emit("        per-texture 'flipped' verdict off this table would be a false red.")
    emit("        |cx| and |cy| both below 0.15 => the two maps are not derived from one another")
    emit("        and the row says INDETERMINATE rather than inventing a verdict.")
    emit()
    emit(f"{'material':<26}{'size':>12}{'cx':>9}{'cy':>9}{'class':>16}")
    classes = {}
    for stem, npath, hpath in pairs:
        nrm = load_rgb(npath)
        hgt = load_gray(hpath)
        if nrm.shape[:2] != hgt.shape[:2]:
            # resample the height to the normal's grid with nearest so no filter invents a gradient
            hgt = np.asarray(
                Image.open(hpath).convert("L").resize((nrm.shape[1], nrm.shape[0]), Image.NEAREST),
                dtype=np.float64,
            ) / 255.0
        nx = nrm[:, :, 0] * 2.0 - 1.0
        ny = nrm[:, :, 1] * 2.0 - 1.0
        # central differences, interior only (no wrap assumption: a tiled map and a clamped one
        # would disagree at the border and the border is not where the verdict lives)
        dhdu = (hgt[1:-1, 2:] - hgt[1:-1, :-2]) * 0.5
        dhdv = (hgt[2:, 1:-1] - hgt[:-2, 1:-1]) * 0.5
        cx = corr(nx[1:-1, 1:-1], -dhdu)
        cy = corr(ny[1:-1, 1:-1], -dhdv)
        if abs(cx) < 0.15 and abs(cy) < 0.15:
            cls = "INDETERMINATE"
        else:
            cls = f"({'+' if cx > 0 else '-'}{'+' if cy > 0 else '-'})"
        classes.setdefault(cls, []).append(stem)
        emit(f"{stem:<26}{f'{nrm.shape[1]}x{nrm.shape[0]}':>12}{cx:>9.4f}{cy:>9.4f}{cls:>16}")
    emit()
    graded = {k: v for k, v in classes.items() if k != "INDETERMINATE"}
    emit(f"materials measured: {len(pairs)}   distinct (sign cx, sign cy) classes: {len(graded)}")
    for k in sorted(graded):
        emit(f"   class {k}: {len(graded[k])}  {', '.join(sorted(graded[k]))}")
    emit()
    if len(graded) <= 1:
        emit("VERDICT: HOMOGENEOUS. Every material places its green channel the same way relative")
        emit("to its own height field, so there is NO per-texture mix and a per-texture normal_y")
        emit("has nothing to repair today. That is a real result and not an absence of one: it")
        emit("REMOVES 'some textures ship a flipped green' from the candidate causes of the owner's")
        emit("face-to-face inconsistency, which is what the census was run to test.")
        emit("WHAT STAYS OPEN, NAMED: whether the shared convention is the one the engine assumes")
        emit("is ONE GLOBAL BIT this instrument cannot reach (see CANNOT above). The knob now")
        emit("exists, so testing it costs one line -- `normal_y -1` in the [defaults] block of")
        emit("recharged_assets/materials.txt -- and no rebuild. It is the OWNER's eye that closes")
        emit("it, not a number of mine.")
    else:
        emit("VERDICT: MIXED. The classes above disagree, so at least one material ships its green")
        emit("channel the other way round from its neighbours. THAT is what a per-texture normal_y")
        emit("repairs, and no global setting can: set normal_y -1 on the minority class.")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"\n-> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
