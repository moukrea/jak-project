"""Seamlessness (tileability) analysis for game textures.

The question answered per texture and per axis is: if this image is repeated
(GL_REPEAT / UV wrap) along that axis, does the wrap boundary show a seam?

Method
------
A seam is visible when the discontinuity introduced at the wrap boundary is
*unlike* the discontinuities that already exist everywhere else in the image.
So we never ask "is the left column equal to the right column" (which is wrong:
a tiling texture must *continue*, not repeat).  Instead, for a given axis we
measure the mean absolute step across every boundary between two adjacent
lines, and compare the step at the wrap boundary against the distribution of
the interior steps.

  e_k     = mean |X[k+1] - X[k]|   over the line and over channels, k interior
  e_seam  = mean |X[0]   - X[N-1]|
  ref     = median(e_k)            robust: one hard interior edge does not
                                   move it
  ratio   = e_seam / ref           scale-free "how many times rougher is the
                                   seam than a typical step"
  rank    = fraction of interior steps that are >= e_seam, counted only
            outside a margin at each border (see below)

The verdict needs *both* statistics, because each one alone has a failure the
other covers:

  * ratio alone rejects a legitimate 8-pixel checkerboard.  Most of its
    interior steps are 0 (inside a tile), so the median is 0 and the wrap
    step -- a perfectly normal tile edge -- scores an infinite ratio.  Its
    rank is 7/63 = 0.11, which is what tells us the wrap is just another tile
    edge.
  * rank alone rejects a flat image with imperceptible noise, where the seam
    is the largest step (rank 0) while being 1.05x a typical one.

The rank reference deliberately ignores the boundaries within `rank_margin` of
each border.  Those are the seam's own neighbourhood: an image with a bright
frame or a ramp running into its edge produces both a mismatched wrap *and* the
steep steps beside it, so counting them would let the artefact acquit itself.
Measured on jak1's sky textures (a blob inside a bright frame), the untrimmed
rank called 4 of 8 seamless with rank 0.26-0.32; trimming 20% at each end drops
them all to rank 0.00 while a checkerboard keeps 0.14 and a mortar grid 0.16,
because those repeat across the whole image instead of hugging its border.

  seamless  <=>  e_seam <= abs_floor  or  ratio <= ratio_max  or  rank >= rank_min

Channels are premultiplied RGB plus alpha, so RGB garbage under transparent
pixels cannot fabricate a seam.  PS2 alpha is 0..128, normalised accordingly.

Thresholds are not guesses; calibrate.py fits them against manufactured ground
truth (random-phase spectral synthesis is exactly periodic, so it is a provable
positive; the same synthesis cropped by c lines is a provable negative).  At
the shipped values the detector keeps 96.7% of provably-seamless images, and
rejects 88.4% of provably-seamed ones -- 100% (61/61) of the realistic case of
two unrelated textures glued together.

Box-downsampling the image before measuring (scales 2, 4, 8) was tried on the
theory that pixel noise can hide a low-frequency mismatch across the wrap.  The
calibration set refutes it: on a periodic image tilted by a non-periodic ramp,
scale 1 catches 36/40 where scale 8 catches 29/40, and adding coarse scales to
the verdict only cost true positives.  `scales` stays configurable so that
measurement can be reproduced, but the default is scale 1 alone.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import random
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path

import numpy as np
from PIL import Image

# --------------------------------------------------------------------------
# tuning
# --------------------------------------------------------------------------


@dataclass
class Config:
    # a seam whose mean channel step is below this is invisible no matter what
    # the rest of the image does.  0.008 ~= 2.7 levels of 8-bit.
    abs_floor: float = 0.008
    # the seam may be at most this many times rougher than a typical interior
    # boundary before it needs the rank test to acquit it.
    ratio_max: float = 1.3
    # ...or at least this fraction of interior boundaries must be as rough as
    # the seam.  A checkerboard scores 0.14 and a mortar grid 0.16, so 0.10
    # keeps hard-edged tiling patterns while rejecting border artefacts.
    rank_min: float = 0.10
    # fraction of the interior boundaries trimmed from each end before the rank
    # is computed, so that the seam's own neighbourhood cannot vouch for it.
    rank_margin: float = 0.20
    # the two border lines must carry at least this share of a typical line's
    # own variation.  Below it the border is a dead margin: the wrap has no
    # step because there is nothing there, not because the content continues.
    border_activity_min: float = 0.35
    # the statistic is bimodal -- a spike at 0 (matted sprites) and a mode at
    # 1.0 (real tiling) -- but ~14% of verdicts land in the valley between
    # them, where a roof tile (0.27) is indistinguishable from an eye sprite
    # (0.28).  A verdict decided inside this band is reported low confidence
    # rather than dressed up as clean.
    border_ambiguous: tuple = (0.05, 0.55)
    # extra strictness, off by default: robust z-score of the seam within the
    # interior distribution.
    z_max: float = 8.0
    strict: bool = False
    # box-downsampling scales to test.  Measured to be worse than (1,); kept
    # configurable only so the measurement can be reproduced.
    scales: tuple = (1,)
    # a scale is only usable if it leaves at least this many lines on the
    # tested axis (i.e. that many minus one interior boundaries).
    min_lines: int = 8
    # below this many lines even at scale 1 the statistics are degenerate; we
    # still answer, but flag it.
    degenerate_lines: int = 8
    # image is "constant" if its total per-channel spread is under this
    constant_eps: float = 0.008


EPS = 1e-4  # ~1/40 of an 8-bit level; keeps ratios finite on flat images


# --------------------------------------------------------------------------
# core measurement
# --------------------------------------------------------------------------


def to_analysis_array(im: Image.Image, ps2_alpha: bool = True) -> np.ndarray:
    """RGBA image -> float32 (H, W, 4) with premultiplied RGB and alpha in 0..1."""
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    arr = np.asarray(im, dtype=np.float32)
    rgb = arr[..., :3] / 255.0
    a = arr[..., 3] / (128.0 if ps2_alpha else 255.0)
    np.clip(a, 0.0, 1.0, out=a)
    return np.concatenate([rgb * a[..., None], a[..., None]], axis=2)


def box_down(x: np.ndarray, s: int) -> np.ndarray:
    if s == 1:
        return x
    h, w, c = x.shape
    return x.reshape(h // s, s, w // s, s, c).mean(axis=(1, 3))


def line_activity(x: np.ndarray, axis: int) -> np.ndarray:
    """How much each line varies *along itself*, one value per line.

    A texture meant to repeat has structure running through its border.  A
    sprite matted into a flat or transparent surround has none: its border
    lines are dead, which is why its wrap shows no step.  Comparing the two
    border lines against a typical line separates "the content continues
    across the wrap" from "there is nothing at the wrap to mismatch".
    """
    if axis == 1:  # lines are columns; vary down them
        return np.abs(np.diff(x, axis=0)).mean(axis=(0, 2))
    return np.abs(np.diff(x, axis=1)).mean(axis=(1, 2))


def rank_pool(interior: np.ndarray, margin: float) -> np.ndarray:
    """Interior steps with the seam's own neighbourhood trimmed off both ends."""
    n = interior.size
    m = max(1, int(round(margin * n))) if margin > 0 else 0
    return interior[m : n - m] if n - 2 * m >= 3 else interior


def boundary_energies(x: np.ndarray, axis: int):
    """Steps between adjacent lines along `axis`, plus the wrap step.

    axis=0 -> lines are rows, this measures VERTICAL tiling.
    axis=1 -> lines are columns, this measures HORIZONTAL tiling.
    """
    if axis == 1:
        x = np.swapaxes(x, 0, 1)
    interior = np.abs(np.diff(x, axis=0)).mean(axis=(1, 2))
    seam = float(np.abs(x[0] - x[-1]).mean())
    return interior, seam


@dataclass
class ScaleResult:
    scale: int
    n_lines: int
    e_seam: float
    ref: float
    ratio: float
    z: float
    rank: float
    passed: bool


@dataclass
class AxisResult:
    seamless: bool
    ratio: float  # worst (largest) ratio over scales
    e_seam: float  # at scale 1
    ref: float  # at scale 1
    rank: float  # at scale 1
    z: float  # worst over scales
    border_activity: float
    reason: str
    scales: list = field(default_factory=list)


def border_activity(x: np.ndarray, axis: int) -> float:
    """Mean activity of the two border lines over a typical line's activity."""
    act = line_activity(x, axis)
    if act.size < 3:
        return 1.0
    typical = float(np.median(act))
    border = float(0.5 * (act[0] + act[-1]))
    return (border + EPS) / (typical + EPS)


def analyse_axis(x: np.ndarray, axis: int, cfg: Config) -> AxisResult:
    n_full = x.shape[axis]
    usable = [
        s
        for s in cfg.scales
        if s <= min(x.shape[0], x.shape[1])
        and x.shape[0] % s == 0
        and x.shape[1] % s == 0
        and (n_full // s) >= cfg.min_lines
    ]
    if not usable:
        usable = [1]

    results: list[ScaleResult] = []
    for s in usable:
        xs = box_down(x, s)
        interior, e_seam = boundary_energies(xs, axis)
        if interior.size == 0:  # 1-line image along this axis
            results.append(ScaleResult(s, xs.shape[axis], e_seam, 0.0, 1.0, 0.0, 1.0, True))
            continue
        ref = float(np.median(interior))
        mad = float(np.median(np.abs(interior - ref)))
        sigma = 1.4826 * mad
        ratio = (e_seam + EPS) / (ref + EPS)
        z = (e_seam - ref) / (sigma + cfg.abs_floor)
        rank = float(np.mean(rank_pool(interior, cfg.rank_margin) >= e_seam))
        ok = e_seam <= cfg.abs_floor or ratio <= cfg.ratio_max or rank >= cfg.rank_min
        if ok and cfg.strict and e_seam > cfg.abs_floor:
            ok = z <= cfg.z_max
        results.append(ScaleResult(s, xs.shape[axis], e_seam, ref, ratio, z, rank, ok))

    # the seam is measured across `axis`; the border lines that must carry
    # content are the lines of that same axis
    bact = border_activity(x, axis)
    alive = bact >= cfg.border_activity_min

    seamless = all(r.passed for r in results) and alive
    worst = max(results, key=lambda r: r.ratio)
    s1 = results[0]
    if not alive and all(r.passed for r in results):
        reason = f"dead-border ({bact:.2f} of a typical line's variation)"
    elif seamless and s1.e_seam <= cfg.abs_floor:
        reason = "flat-seam"
    elif seamless and s1.ratio <= cfg.ratio_max:
        reason = "step-typical"
    elif seamless:
        reason = f"step-common ({s1.rank * 100:.0f}% of interior steps as rough)"
    else:
        reason = f"step-{worst.ratio:.1f}x-typical"
    return AxisResult(
        seamless=seamless,
        border_activity=float(bact),
        ratio=float(worst.ratio),
        e_seam=float(s1.e_seam),
        ref=float(s1.ref),
        rank=float(s1.rank),
        z=float(max(r.z for r in results)),
        reason=reason,
        scales=[asdict(r) for r in results],
    )


def classify(x: np.ndarray, cfg: Config) -> dict:
    h, w, _ = x.shape
    spread = float(np.ptp(x.reshape(-1, x.shape[2]), axis=0).max())
    flags = []
    if spread <= cfg.constant_eps:
        flags.append("constant")
    if min(h, w) < cfg.degenerate_lines:
        flags.append("degenerate-size")
    if x[..., 3].max() <= 1e-6:
        flags.append("fully-transparent")

    res_h = analyse_axis(x, 1, cfg)  # columns -> horizontal tiling
    res_v = analyse_axis(x, 0, cfg)  # rows    -> vertical tiling

    lo, hi = cfg.border_ambiguous
    marginal = False
    for axis, res in (("h", res_h), ("v", res_v)):
        # only matters where the seam itself was clean: otherwise the border
        # activity did not decide anything
        if "step-" in res.reason or "dead-border" in res.reason or res.seamless:
            if lo <= res.border_activity <= hi and "step-" not in res.reason:
                flags.append(f"border-marginal-{axis}")
                marginal = True

    # a border made only of fully transparent pixels tiles trivially; say so
    if x[:, 0, 3].max() <= 1e-6 and x[:, -1, 3].max() <= 1e-6:
        flags.append("transparent-border-h")
    if x[0, :, 3].max() <= 1e-6 and x[-1, :, 3].max() <= 1e-6:
        flags.append("transparent-border-v")

    if res_h.seamless and res_v.seamless:
        klass = "both"
    elif res_h.seamless:
        klass = "horizontal"
    elif res_v.seamless:
        klass = "vertical"
    else:
        klass = "none"

    # confidence is about how many interior boundaries the statistics had: a
    # 4-pixel-wide texture offers 3 of them, which is not a distribution.
    small = min(h, w)
    if small < cfg.degenerate_lines or marginal:
        confidence = "low"
    elif small < 2 * cfg.degenerate_lines:
        confidence = "medium"
    else:
        confidence = "high"

    return {
        "width": w,
        "height": h,
        "class": klass,
        "seamless_h": res_h.seamless,
        "seamless_v": res_v.seamless,
        "h": asdict(res_h),
        "v": asdict(res_v),
        "flags": flags,
        "confidence": confidence,
    }


def analyse_file(path: Path, cfg: Config, ps2_alpha: bool = True) -> dict:
    with Image.open(path) as im:
        x = to_analysis_array(im, ps2_alpha)
    return classify(x, cfg)
