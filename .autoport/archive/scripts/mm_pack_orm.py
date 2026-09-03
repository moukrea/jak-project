#!/usr/bin/env python3
"""Grecharged-materials-modern-parity — ORM packer.

Packs a material's Occlusion / Roughness / Metallic into ONE RGB png, the glTF layout
the loader unpacks into three GL_R8 planes (LoaderStages.cpp, "ORM unpack"). One file
instead of three; 3 bytes per texel of VRAM instead of 12.

The catch this tool exists to solve: NONE of the seven bundled village materials ships an
_ao map, which is exactly why the fused shader's own comment says an _ao-driven ambient
occlusion "left them flat". So there is no occlusion channel to pack — it has to be BAKED,
and the height map is the right source because ambient occlusion from a height field is a
standard authoring-tool operation, not an invention: a texel sitting below its surroundings
sees less of the sky.

The bake is HORIZON-BASED (the offline cousin of HBAO): for each of N compass directions,
march M steps out along the height field and keep the steepest rise; the occluded fraction
of the hemisphere is the mean of sin(horizon elevation) over the directions. Heights are
read in the material's own normalised space (the same p2..p98 robust range the runtime's
hnorm() uses) so a map that only spans 0.30..0.48 does not bake a flat grey.

Usage:
    mm_pack_orm.py <material-dir> [--metal 0.0] [--depth 0.06] [--dirs 16] [--steps 12]

<material-dir> is a directory named after the material, e.g.
    custom_assets/jak1/recharged_textures/village1-vis-tfrag/vil1-sages-stonewall-01
Writes <mat>_orm.png next to the inputs and prints the size arithmetic.

NOTE ON SHIPPING: keep the existing _roughness.png. With MODERN MATERIALS off the loader
does not probe for _orm at all, so a material whose roughness lived only in the packed file
would silently lose it in the OFF path — and OFF must stay bit-identical to the accepted
look. Removing the unpacked files is only safe for a material that is modern-only.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image


def load_gray(path: Path) -> np.ndarray | None:
    if not path.is_file():
        return None
    return np.asarray(Image.open(path).convert("L"), dtype=np.float32) / 255.0


def robust_normalise(h: np.ndarray) -> np.ndarray:
    """Recentre + refill 0..1 on the p2..p98 range — the same transform hnorm() applies at
    runtime, so the bake sees the height field the shader sees."""
    p2, p98 = np.percentile(h, 2.0), np.percentile(h, 98.0)
    half = max((p98 - p2) * 0.5, 1e-4)
    return np.clip((h - h.mean()) * (0.5 / half) + 0.5, 0.0, 1.0)


def bake_ao(h: np.ndarray, depth: float, n_dirs: int, n_steps: int) -> np.ndarray:
    """Horizon-based ambient occlusion over a tiling height field.

    depth = the height field's peak-to-peak amplitude expressed as a fraction of the texture
    width, which is what turns a unitless 0..1 map into a slope. 0.06 is a plausible relief
    for these materials; larger = deeper crevices = darker AO.
    """
    hh, ww = h.shape
    scale = depth * ww  # height units -> pixel units, so a slope is rise/run in one space
    occ = np.zeros_like(h)
    for d in range(n_dirs):
        a = 2.0 * np.pi * d / n_dirs
        dx, dy = np.cos(a), np.sin(a)
        max_slope = np.zeros_like(h)
        for s in range(1, n_steps + 1):
            # np.roll wraps, which is correct: these textures tile.
            ox, oy = int(round(dx * s)), int(round(dy * s))
            if ox == 0 and oy == 0:
                continue
            sample = np.roll(np.roll(h, -oy, axis=0), -ox, axis=1)
            run = float(np.hypot(ox, oy))
            max_slope = np.maximum(max_slope, (sample - h) * scale / run)
        # horizon elevation angle -> the share of that direction's sky it blocks
        occ += max_slope / np.sqrt(max_slope * max_slope + 1.0)
    occ /= n_dirs
    return np.clip(1.0 - occ, 0.0, 1.0)


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if not a.startswith("--")]
    opts = {}
    for a in argv[1:]:
        if a.startswith("--"):
            k, _, v = a[2:].partition("=")
            opts[k] = v
    if not args:
        sys.stderr.write(__doc__ or "")
        return 2
    mat_dir = Path(args[0]).resolve()
    name = mat_dir.name
    # 0.015 = the height field's peak-to-peak is ~1.5% of the texture width. Measured against the
    # village set that lands AO at a mean of ~0.9 with real crevices in the mortar lines; the 0.06
    # first tried was 122 px of relief on a 2048 px stone wall and baked a mean of 0.70, i.e. a
    # material uniformly darkened by a third, which is a tint and not an occlusion.
    depth = float(opts.get("depth", 0.015))
    n_dirs = int(opts.get("dirs", 16))
    n_steps = int(opts.get("steps", 12))
    metal_const = float(opts.get("metal", 0.0))

    height = load_gray(mat_dir / f"{name}_height.png")
    rough = load_gray(mat_dir / f"{name}_roughness.png")
    ao_in = load_gray(mat_dir / f"{name}_ao.png")
    metal_in = load_gray(mat_dir / f"{name}_metallic.png")
    if rough is None:
        sys.stderr.write(f"[orm] {name}: no _roughness.png — nothing to pack\n")
        return 1

    if ao_in is not None:
        ao = ao_in
        ao_src = "authored _ao.png"
    elif height is not None:
        ao = bake_ao(robust_normalise(height), depth, n_dirs, n_steps)
        ao_src = f"BAKED from _height.png (horizon-based, {n_dirs} dirs x {n_steps} steps, depth={depth})"
    else:
        ao = np.ones_like(rough)
        ao_src = "neutral (no height, no ao)"

    metal = metal_in if metal_in is not None else np.full_like(rough, metal_const)
    metal_src = "authored _metallic.png" if metal_in is not None else f"constant {metal_const}"

    if ao.shape != rough.shape:
        ao = np.asarray(
            Image.fromarray((ao * 255).astype(np.uint8)).resize(
                (rough.shape[1], rough.shape[0]), Image.LANCZOS),
            dtype=np.float32) / 255.0

    rgb = np.stack([ao, rough, metal], axis=-1)
    out_path = mat_dir / f"{name}_orm.png"
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), mode="RGB").save(
        out_path, optimize=True)

    texels = rough.shape[0] * rough.shape[1]
    packed_bytes = out_path.stat().st_size

    # APPLES TO APPLES. Comparing the packed file against whatever unpacked files happen to exist
    # today is not a measurement — this material ships roughness only, so it would flatter the pack
    # by pretending the AO and metallic channels were free. Write the true unpacked EQUIVALENT of
    # what we just packed, measure it, delete it.
    import tempfile
    unpacked_bytes = 0
    with tempfile.TemporaryDirectory() as td:
        for chan, arr in (("ao", ao), ("roughness", rough), ("metallic", metal)):
            p = Path(td) / f"{chan}.png"
            Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), mode="L").save(
                p, optimize=True)
            unpacked_bytes += p.stat().st_size

    print(f"[orm] {name} {rough.shape[1]}x{rough.shape[0]}")
    print(f"[orm]   R occlusion : {ao_src}  (mean {ao.mean():.3f}, min {ao.min():.3f})")
    print(f"[orm]   G roughness : authored _roughness.png (mean {rough.mean():.3f})")
    print(f"[orm]   B metallic  : {metal_src}")
    print(f"[orm]   wrote {out_path} ({packed_bytes/1024:.1f} KiB)")
    print(f"[orm]   ON DISK  : 1 file {packed_bytes/1024:.1f} KiB packed vs 3 files "
          f"{unpacked_bytes/1024:.1f} KiB unpacked-equivalent "
          f"({packed_bytes/max(unpacked_bytes,1):.2f}x)")
    print(f"[orm]   IN VRAM  : 3 x GL_R8 {texels*3/1048576:.2f} MiB packed vs "
          f"3 x GL_RGBA8 {texels*12/1048576:.2f} MiB unpacked (4.00x)")
    if packed_bytes > unpacked_bytes:
        print("[orm]   NOTE: packed is LARGER on disk. Expected and worth saying out loud: PNG "
              "filters predict each row from the previous one, and three UNCORRELATED channels "
              "interleaved in RGB defeat that, while three separate greyscale images each "
              "compress on their own statistics. The win ORM actually buys here is VRAM (4x) and "
              "file count (1 vs 3), not bytes on disk.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
