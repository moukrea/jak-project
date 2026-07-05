#!/usr/bin/env python3
"""Gperf-particles2 correctness inspector.

Detects the two v5 owner regressions in a directory of extracted video frames:

  (A) GEOMETRY POP  — geometry present in frame K-1 and K+1 but TORN/ABSENT in K
      (the GOAL/GL overlap race: merc-mod / texanim read live EE memory the next
      GOAL frame is stomping). A pop is a TRANSIENT REVERTING outlier: a region
      differs a lot from BOTH neighbours while the two neighbours are similar.
      Smooth motion does NOT revert (diff accumulates), so it is rejected.

  (B) TOD PALETTE FLICKER — trees/terrain tint OSCILLATES day/night frame-to-frame
      (the tod-pingpong bug: samples the previous ping-pong buffer under a moving
      clock). A flicker is a HIGH-FREQUENCY, SPATIALLY-COHERENT luma/colour
      oscillation (sawtooth). A smooth day->night RAMP (the correct build with a
      fast clock) is monotone/low-2nd-derivative, so it is rejected.

The point of this tool is to be RUN FIRST on a KNOWN-BAD capture (overlap on /
pingpong on) and PROVEN to fire, then on the clean build and shown to stay quiet.
If it can't see the bug on the bad build, it is worthless (that is the exact step
the v5 validation skipped).

Usage:
  inspect.py <frames_dir> [--label NAME] [--grid 12] [--start N] [--end N]
             [--json OUT.json] [--dump-worst DIR]

Prints POP and FLICKER scores + the raw components so thresholds can be calibrated
against the known-bad control. Exit code is always 0 (this is a measurement tool,
the caller compares scores across builds).
"""
import argparse, glob, json, os, sys
import numpy as np
from PIL import Image


def load_frames(d, start, end, maxdim=0):
    paths = sorted(glob.glob(os.path.join(d, "*.png")))
    if not paths:
        paths = sorted(glob.glob(os.path.join(d, "*.jpg")))
    paths = paths[start:end]
    if len(paths) < 5:
        sys.exit(f"[inspect] need >=5 frames in {d}, found {len(paths)}")
    imgs = []
    for p in paths:
        im = Image.open(p).convert("RGB")
        # OOM guard: stacking thousands of 2400x1080 float32 frames blows RAM. The
        # FLICKER/POP metrics are tile-mean-based (resolution-invariant, verified: full
        # vs 3x-downscaled agree to 3 decimals); downscale the long edge to maxdim so a
        # full-clip run fits in memory. temporal_energy shifts ~5-10% (per-pixel) but
        # is only compared like-for-like across configs. maxdim<=0 disables.
        if maxdim and max(im.size) > maxdim:
            s = maxdim / float(max(im.size))
            im = im.resize((max(1, round(im.size[0] * s)), max(1, round(im.size[1] * s))),
                           Image.BILINEAR)
        imgs.append(np.asarray(im, dtype=np.float32))
    # frames may vary by 1px; crop to common min size
    h = min(a.shape[0] for a in imgs)
    w = min(a.shape[1] for a in imgs)
    arr = np.stack([a[:h, :w, :] for a in imgs], axis=0)  # (T,H,W,3)
    return paths, arr


def dedup_frames(paths, arr, eps=0.4):
    """Drop consecutive near-identical frames. screenrecord samples at the panel
    refresh, so when the game renders < 60fps it captures DUPLICATES; dropping them
    recovers the true unique-render-frame sequence, making every metric independent
    of the (build-dependent) fps. eps is mean abs pixel diff below which a frame is
    a duplicate of its predecessor."""
    keep = [0]
    for k in range(1, arr.shape[0]):
        if np.abs(arr[k] - arr[keep[-1]]).mean() > eps:
            keep.append(k)
    return [paths[i] for i in keep], arr[keep], len(arr) - len(keep)


def temporal_energy(arr):
    """Raw mean frame-to-frame abs diff (a build-agnostic churn measure). With the
    SAME deterministic input clip, motion is identical across builds, so an ELEVATED
    value vs the clean build isolates pop/tear churn even if it does not cleanly
    revert."""
    d = np.abs(np.diff(arr, axis=0)).mean()
    return round(float(d), 3)


def autocrop_letterbox(arr):
    """Drop rows/cols that are ~black across ALL frames (aspect letterbox)."""
    lum = arr.mean(axis=(0, 3))  # (H,W) mean luma over time+channels
    rows = np.where(lum.mean(axis=1) > 8.0)[0]
    cols = np.where(lum.mean(axis=0) > 8.0)[0]
    if len(rows) < 8 or len(cols) < 8:
        return arr, (0, arr.shape[1], 0, arr.shape[2])
    r0, r1, c0, c1 = rows[0], rows[-1] + 1, cols[0], cols[-1] + 1
    return arr[:, r0:r1, c0:c1, :], (r0, r1, c0, c1)


def tile_means(arr, grid):
    """Per-frame, per-tile mean RGB. Returns (T, gy, gx, 3)."""
    T, H, W, _ = arr.shape
    gy = gx = grid
    ys = np.linspace(0, H, gy + 1).astype(int)
    xs = np.linspace(0, W, gx + 1).astype(int)
    out = np.zeros((T, gy, gx, 3), np.float32)
    for i in range(gy):
        for j in range(gx):
            out[:, i, j, :] = arr[:, ys[i]:ys[i + 1], xs[j]:xs[j + 1], :].mean(axis=(1, 2))
    return out


def flicker_metrics(arr):
    """Global TOD-oscillation detector.

    A correct fast day->night is a smooth ramp: the per-frame mean luma changes
    with (mostly) CONSISTENT sign. The pingpong bug makes it a SAWTOOTH: the
    per-frame delta ALTERNATES sign nearly every frame, coherently across the
    whole terrain. We measure:
      - sawtooth energy = RMS of the 2nd-difference (deviation from the straight
        line through the two neighbours), as % of the frame luma range.
      - sign-flip rate  = fraction of interior frames where the luma delta flips
        sign with meaningful magnitude (a ramp ~0, a sawtooth ~1).
      - tile phase coherence = do tiles oscillate IN PHASE? (global palette
        flicker => yes; random motion => no).
    """
    L = arr.mean(axis=(1, 2, 3))  # (T,) whole-frame mean luma
    T = len(L)
    d = np.diff(L)                              # first difference
    hp = L[1:-1] - 0.5 * (L[:-2] + L[2:])       # 2nd difference / sawtooth comp
    luma_range = max(1.0, L.max() - L.min())
    saw_energy = float(np.sqrt(np.mean(hp ** 2)) / luma_range * 100.0)  # % of range
    # sign-flip rate over deltas with magnitude above a small noise floor
    eps = 0.15  # luma units; below this is noise
    sig = np.abs(d) > eps
    flips = 0
    pairs = 0
    for k in range(1, len(d)):
        if sig[k] and sig[k - 1]:
            pairs += 1
            if np.sign(d[k]) != np.sign(d[k - 1]):
                flips += 1
    flip_rate = float(flips / pairs) if pairs else 0.0

    # tile phase coherence: sign of each tile's 2nd-difference vs the global one
    tm = tile_means(arr, 8).mean(axis=3)  # (T,gy,gx) tile luma
    thp = tm[1:-1] - 0.5 * (tm[:-2] + tm[2:])  # (T-2,gy,gx)
    gsign = np.sign(hp)[:, None, None]
    tsign = np.sign(thp)
    # only count tiles/frames where BOTH global and tile oscillation is non-trivial
    mask = (np.abs(hp)[:, None, None] > 0.2) & (np.abs(thp) > 0.2)
    if mask.sum() > 0:
        coherence = float(((tsign == gsign) & mask).sum() / mask.sum())
    else:
        coherence = 0.0
    return {
        "saw_energy_pct": round(saw_energy, 3),
        "flip_rate": round(flip_rate, 3),
        "phase_coherence": round(coherence, 3),
        "luma_range": round(float(luma_range), 2),
        "luma_min": round(float(L.min()), 2),
        "luma_max": round(float(L.max()), 2),
        "L": [round(float(x), 2) for x in L],
    }


def pop_metrics(arr, grid, dump_worst=None, paths=None):
    """Geometry-pop detector via TRANSIENT REVERTING tile outliers.

    For each interior frame K and tile t:
      a = |tile(K-1) - tile(K)|   b = |tile(K) - tile(K+1)|   c = |tile(K-1) - tile(K+1)|
    A pop tile satisfies min(a,b) large AND c small: frame K differs from BOTH
    neighbours which are themselves similar => a transient blip that REVERTED.
    Smooth motion gives c ~ a+b (accumulation), so revert = min(a,b) - c is small.
    """
    tm = tile_means(arr, grid)  # (T,gy,gx,3)
    a = np.abs(tm[1:-1] - tm[:-2]).mean(axis=3)   # (T-2,gy,gx)
    b = np.abs(tm[1:-1] - tm[2:]).mean(axis=3)
    c = np.abs(tm[:-2] - tm[2:]).mean(axis=3)
    revert = np.minimum(a, b) - c                 # >0 => transient/reverting
    # a real pop needs both a meaningful transient AND a clean revert
    TRANS = 12.0   # min(a,b) threshold in luma units (a torn/absent region)
    REVERT = 8.0   # revert margin
    pop_mask = (np.minimum(a, b) > TRANS) & (revert > REVERT)
    per_frame = pop_mask.reshape(pop_mask.shape[0], -1).sum(axis=1)  # (T-2,)
    pop_events = int(pop_mask.sum())
    pop_frames = int((per_frame > 0).sum())
    worst = int(np.argmax(per_frame)) if len(per_frame) else 0
    worst_count = int(per_frame[worst]) if len(per_frame) else 0
    # strongest single reverting tile (for reporting magnitude)
    strongest = float(revert.max()) if revert.size else 0.0

    if dump_worst and paths is not None and worst_count > 0:
        os.makedirs(dump_worst, exist_ok=True)
        # worst is an index into interior frames -> actual frame index worst+1
        for off, tag in ((0, "prev"), (1, "pop"), (2, "next")):
            fi = worst + off
            if fi < len(paths):
                Image.open(paths[fi]).save(os.path.join(dump_worst, f"worst_{tag}_{fi}.png"))
    return {
        "pop_events": pop_events,
        "pop_frames": pop_frames,
        "worst_frame": worst + 1,
        "worst_tile_count": worst_count,
        "strongest_revert": round(strongest, 2),
        "per_frame_max": int(per_frame.max()) if len(per_frame) else 0,
        "grid": grid,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("frames_dir")
    ap.add_argument("--label", default="")
    ap.add_argument("--grid", type=int, default=12)
    ap.add_argument("--start", type=int, default=0)
    ap.add_argument("--end", type=int, default=None)
    ap.add_argument("--json", default=None)
    ap.add_argument("--dump-worst", default=None)
    ap.add_argument("--no-dedup", action="store_true")
    ap.add_argument("--maxdim", type=int, default=900,
                    help="downscale long edge to this on load (OOM guard); 0 disables")
    args = ap.parse_args()

    paths, arr = load_frames(args.frames_dir, args.start, args.end, args.maxdim)
    n_raw = arr.shape[0]
    dropped = 0
    if not args.no_dedup:
        paths, arr, dropped = dedup_frames(paths, arr)
    arr, crop = autocrop_letterbox(arr)
    flick = flicker_metrics(arr)
    pop = pop_metrics(arr, args.grid, args.dump_worst, paths)
    tenergy = temporal_energy(arr)
    out = {
        "label": args.label,
        "frames_dir": args.frames_dir,
        "n_raw": n_raw,
        "n_dedup_dropped": dropped,
        "n_frames": arr.shape[0],
        "crop": list(crop),
        "temporal_energy": tenergy,
        "flicker": flick,
        "pop": pop,
    }
    Lseries = flick.pop("L")  # keep out of stdout, huge
    print(f"=== inspect: {args.label or args.frames_dir}  ({arr.shape[0]} unique frames, "
          f"{dropped} dup dropped, viewport {arr.shape[2]}x{arr.shape[1]}) ===")
    print(f"  TEMPORAL churn (mean frame diff) = {tenergy}")
    print(f"  FLICKER  saw_energy={flick['saw_energy_pct']}%  flip_rate={flick['flip_rate']}  "
          f"phase_coherence={flick['phase_coherence']}  (luma {flick['luma_min']}..{flick['luma_max']})")
    print(f"  POP      events={pop['pop_events']}  frames_with_pop={pop['pop_frames']}  "
          f"worst_frame={pop['worst_frame']}(x{pop['worst_tile_count']})  "
          f"strongest_revert={pop['strongest_revert']}")
    if args.json:
        out["flicker"]["L"] = Lseries

        def _native(o):  # numpy int64/float64 aren't JSON-serializable
            if isinstance(o, np.integer):
                return int(o)
            if isinstance(o, np.floating):
                return float(o)
            if isinstance(o, np.ndarray):
                return o.tolist()
            raise TypeError(f"not serializable: {type(o)}")

        with open(args.json, "w") as f:
            json.dump(out, f, indent=2, default=_native)
        print(f"  wrote {args.json}")


if __name__ == "__main__":
    main()
