#!/usr/bin/env python3
"""gpbrf_r21_metrics.py — ROUND 21 metrics: displacement DELTA + ALIGNMENT CORRELATION.

Two numbers per cell per band.

(a) DISPLACEMENT DELTA vs the OFF cell
    mean |luma delta| / 255 and the % of band pixels whose |delta| exceeds 2/255. This says
    "something moved", nothing more. The OFF2 repeat of OFF gives the same two numbers for a cell
    that is IDENTICAL by construction, i.e. the capture's own noise floor (follow-cam drift,
    animation, the video encoder). A delta only means anything above that floor.

(b) ALIGNMENT CORRELATION — the round's headline
    The OFF frame IS the checker albedo (testpattern 1 paints base + height + normal + roughness
    from the same synthetic checker, so its light squares are exactly the raised ones). For each
    displacement cell take the per-pixel SIGNED delta d = cell - OFF, and compute the Pearson
    correlation r between the OFF luma and d over the band, each mean-subtracted:

        r = cov(off, d) / (std(off) * std(d))

    A height field IN PHASE with the albedo shades the raised (light) squares systematically
    differently from the sunken (dark) ones, so |r| is clearly non-zero. A height field sampled in
    an UNRELATED coordinate system scatters its shading across light and dark squares alike and
    r ~ 0. The sign of r is not a quality judgement (it depends on which way the light falls on a
    raised block); the MAGNITUDE, against the OFF2 floor, is the measurement.

CONDITIONING (identical for every cell, inherited from r19/r20 the hard way):
  * temporal MEDIAN over the ~12 frames of each 4 s capture — a single still cannot measure this at
    ~10 fps with a live follow-camera and a video encoder in the path;
  * temporal STATIC MASK: a pixel whose temporal std exceeds STD_MAX in ANY cell is dropped, so
    NPC animation, the flag, water and cloud scroll cannot contribute;
  * near-black pixels (letterbox / sky-black) dropped.

BANDS (fractions of the frame, this vantage = village1-hut, 2400x1080):
  GROUND = the checkerboard plaza in front of Jak, right of the ocean columns.
  WALL   = the hut's vertical walls (the upper checkered strip + the interior back wall).
Both are written out as an overlay PNG so the reader can see exactly what was measured.

Usage: gpbrf_r21_metrics.py <device-dir> [--ground r0,r1,c0,c1] [--wall r0,r1,c0,c1]
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

FPS = 3
STD_MAX = 4.0        # 0-255 levels of temporal std above which a pixel is "animated"
CHANGED_EPS = 2.0    # 0-255 levels; the task's "changed by more than 2/255"
BLACK_EPS = 6.0

CELLS = ["OFF", "T_ALIGNED", "T_LEGACY", "P_NEW", "P_LEGACY", "OFF2"]
REF = "OFF"
FLOOR_CELL = "OFF2"

# BANDS, chosen from THIS boot's OFF frame (the vantage the follow-cam settled to is not the same
# one r20's boot C got: r20 C looked down on the checker PLAZA, this boot looks up at the hut).
#   WALL   = the hut's vertical checkered wall, near head-on. This is the surface the owner's
#            "plat sur les murs aussi" complaint is about.
#   HORIZ  = the hut's large near-horizontal checkered roof dome. AT THIS VANTAGE THERE IS NO
#            near-field horizontal GROUND surface carrying PBR maps in frame (the wooden deck Jak
#            stands on has no PBR material — it never shows the test checker), so HORIZ is the
#            honest stand-in for the "ground band" r20 used, and it is a ROOF, not ground.
#   TERRAIN= the dark terrain/foliage shelf below the hut; reported for completeness, it is mostly
#            unlit foliage and carries little signal either way.
# The right half of the frame is SKY + OCEAN: the OFF-vs-OFF2 repeat there measures 10-32/255 of
# cloud and water scroll, i.e. pure noise, so no band reaches past col 0.40.
BANDS = {
    "WALL":    (0.31, 0.47, 0.20, 0.36),
    "HORIZ":   (0.04, 0.19, 0.00, 0.33),
    "TERRAIN": (0.60, 0.95, 0.00, 0.20),
}


def frames_of(base):
    """Every frame's Rec.709 luma from <base>.mp4, as a (n, h, w) stack."""
    mp4 = base + ".mp4"
    if not os.path.exists(mp4) or os.path.getsize(mp4) < 20000:
        return None
    with tempfile.TemporaryDirectory() as td:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp4,
                        "-vf", f"fps={FPS}", os.path.join(td, "f_%03d.png")], check=False)
        fs = sorted(f for f in os.listdir(td) if f.endswith(".png"))
        if len(fs) < 3:
            return None
        arr = []
        for f in fs:
            a = np.asarray(Image.open(os.path.join(td, f)).convert("RGB"), dtype=np.float64)
            arr.append(0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2])
    return np.stack(arr, axis=0)


class Cell:
    def __init__(self, d, name):
        st = frames_of(os.path.join(d, name))
        self.name = name
        self.ok = st is not None
        self.n = 0 if st is None else st.shape[0]
        if self.ok:
            self.med = np.median(st, axis=0)
            self.std = st.std(axis=0)


def box(shape, b):
    h, w = shape
    r0, r1, c0, c1 = b
    return slice(int(h * r0), int(h * r1)), slice(int(w * c0), int(w * c1))


def main():
    global CELLS, REF, FLOOR_CELL
    d = sys.argv[1]
    for i, a in enumerate(sys.argv):
        if a == "--cells":
            CELLS = sys.argv[i + 1].split(",")
            REF = CELLS[0]
            FLOOR_CELL = CELLS[-1]
        if a == "--ground":
            BANDS["GROUND"] = tuple(float(x) for x in sys.argv[i + 1].split(","))
        if a == "--wall":
            BANDS["WALL"] = tuple(float(x) for x in sys.argv[i + 1].split(","))

    cells = {}
    for c in CELLS:
        cell = Cell(d, c)
        cells[c] = cell
        print(f"cell {c:10s} {'OK' if cell.ok else 'MISSING'}  frames={cell.n}")
    missing = [c for c in CELLS if not cells[c].ok]
    if REF in missing:
        print(f"FATAL: reference cell {REF} missing — no metric can be computed")
        return 1
    present = [c for c in CELLS if cells[c].ok]
    shapes = {cells[c].med.shape for c in present}
    if len(shapes) != 1:
        print(f"FATAL: shape mismatch {shapes}")
        return 1
    shape = shapes.pop()
    print(f"\nframe shape {shape[1]}x{shape[0]}   cells present: {', '.join(present)}")
    if missing:
        print(f"CELLS MISSING (not substituted, not estimated): {', '.join(missing)}")

    # band overlay, for the record
    ref_png = os.path.join(d, REF + ".png")
    if os.path.exists(ref_png):
        ov = Image.open(ref_png).convert("RGB")
        px = np.asarray(ov).copy()
        for bn, col in (("WALL", (255, 0, 0)), ("HORIZ", (0, 255, 0)), ("TERRAIN", (0, 128, 255))):
            rs, cs = box(shape, BANDS[bn])
            for t in range(6):
                px[rs.start + t, cs] = col
                px[rs.stop - 1 - t, cs] = col
                px[rs, cs.start + t] = col
                px[rs, cs.stop - 1 - t] = col
        Image.fromarray(px).save(os.path.join(d, "bands_overlay.png"))
        print(f"band overlay -> {os.path.join(d, 'bands_overlay.png')}  (RED=WALL GREEN=HORIZ BLUE=TERRAIN)")

    print("\nBANDS (row_lo,row_hi,col_lo,col_hi as frame fractions):")
    for bn, b in BANDS.items():
        rs, cs = box(shape, b)
        print(f"  {bn:7s} {b}  -> rows [{rs.start},{rs.stop}) cols [{cs.start},{cs.stop})"
              f"  = {(rs.stop-rs.start)*(cs.stop-cs.start)} px")

    rows = []
    for bn, b in BANDS.items():
        rs, cs = box(shape, b)
        # static mask over every present cell
        mask = np.ones((rs.stop - rs.start, cs.stop - cs.start), dtype=bool)
        for c in present:
            mask &= cells[c].std[rs, cs] <= STD_MAX
            mask &= cells[c].med[rs, cs] > BLACK_EPS
        npx = int(mask.sum())
        off = cells[REF].med[rs, cs]
        offm = off[mask]
        print(f"\n=== BAND {bn}: {npx} usable px of {mask.size} "
              f"({100.0*npx/mask.size:.1f}% survive the static+black mask); "
              f"OFF band mean luma {offm.mean():.2f} std {offm.std():.2f}")
        for c in CELLS:
            if c == REF or c in missing:
                continue
            dl = cells[c].med[rs, cs][mask] - offm
            mean_abs = float(np.abs(dl).mean())
            pct_ch = 100.0 * float((np.abs(dl) > CHANGED_EPS).mean())
            so, sd = offm.std(), dl.std()
            r = float(((offm - offm.mean()) * (dl - dl.mean())).mean() / (so * sd)) \
                if so > 1e-9 and sd > 1e-9 else float("nan")
            rows.append((bn, c, mean_abs, mean_abs / 255.0, pct_ch, r, npx))
            print(f"  {c:10s} mean|dL| = {mean_abs:7.3f}/255 = {mean_abs/255.0:.5f}   "
                  f"changed>2/255 = {pct_ch:6.2f}%   Pearson r(OFF, delta) = {r:+.4f}")

    print("\n" + "=" * 108)
    print("R21 SUMMARY TABLE")
    print(f"{'band':7s} {'cell':10s} {'mean|dL|/255':>13s} {'%px>2/255':>10s} {'r(OFF,delta)':>13s}  note")
    print("-" * 108)
    for bn, c, ma, man, pc, r, npx in rows:
        note = f"NOISE FLOOR ({REF} repeat)" if c == FLOOR_CELL else ""
        print(f"{bn:7s} {c:10s} {man:13.5f} {pc:10.2f} {r:+13.4f}  {note}")
    print("-" * 108)
    # ratios against the floor, if the floor cell captured
    fl = {bn: (ma, pc, r) for bn, c, ma, man, pc, r, npx in rows if c == FLOOR_CELL}
    if fl:
        print("\nSIGNAL / NOISE-FLOOR ratio (mean|dL| of the cell divided by the OFF-vs-OFF2 mean|dL|):")
        for bn, c, ma, man, pc, r, npx in rows:
            if c == FLOOR_CELL:
                continue
            f = fl.get(bn, (None,))[0]
            if f and f > 1e-9:
                print(f"  {bn:7s} {c:10s} {ma / f:6.2f}x")
    else:
        print("\nNO NOISE FLOOR: the reference-repeat cell did not capture, so none of the deltas above "
              "has a floor to be judged against.")
    print("\nKEY PAIRS asked for by the round:")
    for bn in BANDS:
        pairs = [(a_, b_) for a_, b_ in (("T_ALIGNED", "T_LEGACY"), ("P_NEW", "P_LEGACY"),
                                        ("PP_NEW", "PP_LEGACY")) if a_ in CELLS and b_ in CELLS]
        for a_, b_ in pairs:
            ra = next((r for x, c, _, _, _, r, _ in rows if x == bn and c == a_), None)
            rb = next((r for x, c, _, _, _, r, _ in rows if x == bn and c == b_), None)
            ma = next((m for x, c, m, _, _, _, _ in rows if x == bn and c == a_), None)
            mb = next((m for x, c, m, _, _, _, _ in rows if x == bn and c == b_), None)
            if ra is None or rb is None:
                print(f"  {bn:7s} {a_} vs {b_}: INCOMPLETE (a cell is missing)")
                continue
            print(f"  {bn:7s} {a_:10s} r={ra:+.4f} |dL|={ma:.3f}   vs   "
                  f"{b_:10s} r={rb:+.4f} |dL|={mb:.3f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
