"""Objective calibration of the seamlessness thresholds.

We have no human labels for the 4002 game textures, so we manufacture ground
truth instead:

POSITIVES (provably seamless on both axes)
  Random-phase spectral synthesis of a real texture: keep |FFT| of the source,
  replace the phase with the phase of a random real image.  The inverse FFT of
  a finite spectrum is *exactly* periodic, so the result tiles perfectly, while
  keeping the source's power spectrum -- i.e. its real mix of low-frequency
  structure and pixel noise.  8-bit quantisation afterwards is pointwise and
  preserves periodicity exactly.

NEGATIVES (provably not seamless on the cropped axis)
  Synthesise the same way at width W+c, then keep only the first W columns.
  The wrap boundary now joins two lines that were c apart in the periodic
  image, so the mismatch has exactly the magnitude the texture's own
  autocorrelation gives at lag c.  Sweeping c from 1 to W/2 produces a
  difficulty ladder from "essentially invisible" to "two unrelated halves",
  and the *vertical* axis of those same samples stays a positive.

  Plus a realistic hard negative: the left half of texture A glued to the left
  half of texture B.

On top of the statistical sweep there is a small regression suite of cases that
must not break whatever the thresholds say: a checkerboard and a mortar grid
(hard-edged, exactly tiling -- the reason the rank test exists) and jak1's eight
sky textures (a blob inside a bright frame -- the reason the rank test trims a
margin at each border).

Run:  python3 calibrate.py <texture_root> [--n 120]
"""

from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from seamless import Config, classify, to_analysis_array  # noqa: E402


def random_phase_synth(rgb: np.ndarray, shape, rng) -> np.ndarray:
    """rgb: (h,w,3) float 0..255 source. Returns (H,W,3) exactly periodic."""
    H, W = shape
    src = np.asarray(
        Image.fromarray(rgb.astype(np.uint8)).resize((W, H), Image.BILINEAR), dtype=np.float64
    )
    mag = np.abs(np.fft.fft2(src, axes=(0, 1)))
    noise = rng.standard_normal((H, W))
    phase = np.angle(np.fft.fft2(noise))  # Hermitian: comes from a real image
    out = np.real(np.fft.ifft2(mag * np.exp(1j * phase)[..., None], axes=(0, 1)))
    # restore the source's level/contrast, then quantise like a real asset
    for c in range(3):
        s, d = src[..., c], out[..., c]
        if d.std() > 1e-9:
            out[..., c] = (d - d.mean()) / d.std() * max(s.std(), 1.0) + s.mean()
    return np.clip(out, 0, 255)


def gray_rgba(g: np.ndarray) -> np.ndarray:
    """(h,w) float -> analysis array of an opaque grey image."""
    rgb = np.repeat(g[..., None], 3, 2).astype(np.uint8)
    a = np.full((*g.shape, 1), 128, np.uint8)
    return arr_to_analysis(np.concatenate([rgb, a], axis=2))


def to_rgba(rgb: np.ndarray, alpha=128) -> np.ndarray:
    h, w, _ = rgb.shape
    a = np.full((h, w, 1), alpha, dtype=np.uint8)
    return np.concatenate([rgb.astype(np.uint8), a], axis=2)


def arr_to_analysis(rgba: np.ndarray) -> np.ndarray:
    return to_analysis_array(Image.fromarray(rgba))


def build_set(root: Path, n_sources: int, rng, seed_files=None):
    """Returns list of (name, analysis_array, {'h': bool|None, 'v': bool|None})."""
    files = seed_files or sorted(root.rglob("*.png"))
    big = []
    for p in files:
        with Image.open(p) as im:
            if im.width >= 64 and im.height >= 64:
                big.append(p)
    rng_py = random.Random(1234)
    srcs = rng_py.sample(big, min(n_sources, len(big)))
    samples = []
    crop_ladder = [1, 2, 3, 4, 6, 8, 16, 32]

    for i, p in enumerate(srcs):
        with Image.open(p) as im:
            rgb = np.asarray(im.convert("RGB"), dtype=np.float64)
        H = W = 64

        # --- positive: exactly periodic on both axes
        pos = random_phase_synth(rgb, (H, W), rng)
        samples.append((f"pos/{p.stem}", arr_to_analysis(to_rgba(pos)), {"h": True, "v": True}))

        # --- negatives: crop c columns off a (H, W+c) periodic image
        c = crop_ladder[i % len(crop_ladder)]
        ext = random_phase_synth(rgb, (H, W + c), rng)[:, :W]
        samples.append(
            (f"negh-c{c}/{p.stem}", arr_to_analysis(to_rgba(ext)), {"h": False, "v": True, "c": c})
        )

        # --- same thing on the other axis
        extv = random_phase_synth(rgb, (H + c, W), rng)[:H, :]
        samples.append(
            (f"negv-c{c}/{p.stem}", arr_to_analysis(to_rgba(extv)), {"h": True, "v": False, "c": c})
        )

    # --- realistic hard negatives: two unrelated real textures glued together
    for i in range(0, len(srcs) - 1, 2):
        a, b = srcs[i], srcs[i + 1]
        with Image.open(a) as im:
            ra = np.asarray(im.convert("RGBA").resize((32, 64), Image.BILINEAR))
        with Image.open(b) as im:
            rb = np.asarray(im.convert("RGBA").resize((32, 64), Image.BILINEAR))
        glued = np.concatenate([ra, rb], axis=1)
        samples.append((f"neg-glue/{a.stem}+{b.stem}", arr_to_analysis(glued), {"h": False}))

    # --- trivial positives
    flat = np.zeros((32, 32, 3), np.uint8) + 90
    samples.append(("pos/flat", arr_to_analysis(to_rgba(flat)), {"h": True, "v": True}))
    yy, xx = np.mgrid[0:64, 0:64]
    sine = (127 + 100 * np.sin(2 * np.pi * xx / 16) * np.cos(2 * np.pi * yy / 8))[..., None]
    samples.append(
        ("pos/sine", arr_to_analysis(to_rgba(np.repeat(sine, 3, 2))), {"h": True, "v": True})
    )
    checker = (((xx // 8 + yy // 8) % 2) * 255)[..., None].astype(np.uint8)
    samples.append(
        ("pos/checker", arr_to_analysis(to_rgba(np.repeat(checker, 3, 2))), {"h": True, "v": True})
    )
    # --- trivial negative: a full-frame ramp cannot wrap
    ramp = (xx * 4)[..., None].astype(np.uint8)
    samples.append(("neg/ramp-h", arr_to_analysis(to_rgba(np.repeat(ramp, 3, 2))), {"h": False, "v": True}))
    return samples


def evaluate(samples, cfg: Config):
    tp = fp = tn = fn = 0
    per_c = {}
    errors = []
    for name, arr, lab in samples:
        r = classify(arr, cfg)
        for axis in ("h", "v"):
            if lab.get(axis) is None:
                continue
            truth, pred = lab[axis], r[f"seamless_{axis}"]
            if truth and pred:
                tp += 1
            elif truth:
                fn += 1
                errors.append(("FN", name, axis, round(r[axis]["ratio"], 2)))
            elif pred:
                fp += 1
                errors.append(("FP", name, axis, round(r[axis]["ratio"], 2)))
                if "c" in lab:
                    per_c.setdefault(lab["c"], [0, 0])[0] += 1
            else:
                tn += 1
                if "c" in lab:
                    per_c.setdefault(lab["c"], [0, 0])[1] += 1
    tpr = tp / max(tp + fn, 1)
    tnr = tn / max(tn + fp, 1)
    return dict(tp=tp, fp=fp, tn=tn, fn=fn, tpr=tpr, tnr=tnr, bal=0.5 * (tpr + tnr)), per_c, errors


def regression_cases(root: Path):
    """(name, analysis array, expected {axis: seamless}) -- must hold at any
    threshold we ship."""
    yy, xx = np.mgrid[0:64, 0:64]
    cases = [
        ("checker-8px", gray_rgba((((xx // 8 + yy // 8) % 2) * 255).astype(float)),
         {"h": True, "v": True}),
    ]
    mortar = np.full((64, 64), 180.0)
    mortar[::16, :] = 60
    mortar[:, ::16] = 60
    cases.append(("mortar-grid", gray_rgba(mortar), {"h": True, "v": True}))
    for i in range(8):
        p = root / "beach-vis-alpha" / f"vil1-sky-{i:02d}.png"
        if p.exists():
            with Image.open(p) as im:
                cases.append((f"sky-{i:02d}", to_analysis_array(im), {"h": False, "v": False}))
    return cases


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", type=Path)
    ap.add_argument("--n", type=int, default=120)
    args = ap.parse_args()

    rng = np.random.default_rng(7)
    samples = build_set(args.root, args.n, rng)
    decisions = sum(1 for _, _, l in samples for a in ("h", "v") if l.get(a) is not None)
    print(f"{len(samples)} manufactured images, {decisions} labelled axis decisions\n")

    print(f"{'margin':>7}{'ratio_max':>10}{'rank_min':>9}{'balanced':>10}{'TPR':>7}{'TNR':>7}")
    grid = []
    for margin in (0.0, 0.10, 0.15, 0.20, 0.25):
        for rmax in (1.2, 1.3, 1.4, 1.5):
            for pmin in (0.04, 0.06, 0.08, 0.10, 0.12):
                cfg = Config(ratio_max=rmax, rank_min=pmin, rank_margin=margin)
                m, _, _ = evaluate(samples, cfg)
                grid.append((m["bal"], margin, rmax, pmin, m))
        b = max((g for g in grid if g[1] == margin), key=lambda g: g[0])
        print(f"{b[1]:>7.2f}{b[2]:>10.2f}{b[3]:>9.2f}{b[4]['bal']:>10.3f}"
              f"{b[4]['tpr']:>7.3f}{b[4]['tnr']:>7.3f}   <- best at this margin")

    grid.sort(key=lambda g: -g[0])
    _, margin, rmax, pmin, m = grid[0]
    ship = Config()
    print(f"\nbest on this set : margin={margin} ratio_max={rmax} rank_min={pmin} "
          f"balanced={m['bal']:.3f}")
    print(f"shipped defaults : margin={ship.rank_margin} ratio_max={ship.ratio_max} "
          f"rank_min={ship.rank_min}")

    m, per_c, errors = evaluate(samples, ship)
    print(f"\nwith the shipped defaults:")
    print(f"  exactly-periodic positives kept   {m['tp']}/{m['tp'] + m['fn']}  (TPR {m['tpr']:.3f})")
    print(f"  provably-seamed negatives caught  {m['tn']}/{m['tn'] + m['fp']}  (TNR {m['tnr']:.3f})")

    print("\nsensitivity ladder -- negative built by cropping c lines off a periodic image,")
    print("so the induced seam is exactly that texture's own mismatch at lag c:")
    print(f"{'c':>4}{'caught':>8}{'missed':>8}{'recall':>8}")
    for c in sorted(per_c):
        miss, caught = per_c[c]
        print(f"{c:>4}{caught:>8}{miss:>8}{caught / (caught + miss):>8.2f}")
    glue = [(n, a, l) for n, a, l in samples if n.startswith("neg-glue")]
    mg, _, _ = evaluate(glue, ship)
    print(f"\nunrelated halves glued together: caught {mg['tn']}/{mg['tn'] + mg['fp']}")

    print("\nregression cases:")
    bad = 0
    for name, arr, want in regression_cases(args.root):
        r = classify(arr, ship)
        got = {a: r[f"seamless_{a}"] for a in ("h", "v")}
        ok = all(got[a] == want[a] for a in want)
        bad += not ok
        print(f"  {'ok  ' if ok else 'FAIL'} {name:<14} want {want}  got {got}"
              f"  (rank h={r['h']['rank']:.2f} v={r['v']['rank']:.2f})")
    print(f"\n{'all regression cases pass' if not bad else str(bad) + ' REGRESSION FAILURES'}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
