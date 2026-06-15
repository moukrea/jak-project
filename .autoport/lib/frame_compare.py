#!/usr/bin/env python3
"""Objective pixel-compare gate for the OpenGOAL -> Android port.

Compares a CANDIDATE frame (e.g. an Android device screencap) against a GOLDEN
frame captured from the pristine upstream desktop build. Goldens and device
frames will never be byte-identical (desktop GL vs Adreno GLES, different
resolutions, sub-pixel rasterization), so this is a tolerant structural+color
diff, NOT an exact match:

  metric = fraction of pixels whose per-channel delta exceeds --threshold,
           after resizing the candidate to the golden's resolution.

  MATCH    (exit 0) when that fraction <= --tolerance
  MISMATCH (exit 1) when it is greater, or on a load/usage error.

It ALWAYS tries to write a diff image (red where pixels differ) for the
supervisor to eyeball, but writing the diff can never change the exit code:
the gate's verdict depends only on the metric.

Usage:
  frame_compare.py GOLDEN CANDIDATE [--tolerance F] [--threshold N]
                   [--diff OUT.png] [--no-diff] [--quiet]

Designed so the bare two-arg form (GOLDEN CANDIDATE) works with sane defaults:
identical images -> MATCH, golden-vs-black -> MISMATCH.
"""

import argparse
import os
import sys
import tempfile

try:
    from PIL import Image, ImageChops
except Exception as e:  # pragma: no cover - environment guard
    sys.stderr.write(f"frame_compare: Pillow (PIL) is required: {e}\n")
    sys.exit(2)


def load_rgb(path):
    img = Image.open(path)
    img.load()
    if img.mode != "RGB":
        img = img.convert("RGB")
    return img


def max_channel_delta(diff_rgb):
    """Per-pixel max(|dR|,|dG|,|dB|) as an 'L' image."""
    r, g, b = diff_rgb.split()
    return ImageChops.lighter(ImageChops.lighter(r, g), b)


def rmse_from_diff(diff_rgb):
    """RMSE over all channels, computed from the difference histogram."""
    hist = diff_rgb.histogram()  # 256 (R) + 256 (G) + 256 (B)
    total = 0
    sq = 0
    for ch in range(3):
        base = ch * 256
        for v in range(256):
            c = hist[base + v]
            if c:
                total += c
                sq += c * (v * v)
    if total == 0:
        return 0.0
    return (sq / total) ** 0.5


def write_diff_image(golden, candidate_resized, mask_l, threshold, out_path):
    """Best-effort red-highlight diff. Returns the path written or None.

    Never raises: callers must not let diff-writing affect the verdict.
    """
    try:
        # Mask: 255 where this pixel differs beyond threshold, else 0.
        mask = mask_l.point(lambda v: 255 if v > threshold else 0)
        # Base: dimmed grayscale of the golden so highlights stand out.
        base = golden.convert("L").point(lambda v: v // 2).convert("RGB")
        red = Image.new("RGB", golden.size, (255, 0, 0))
        composed = Image.composite(red, base, mask)
        composed.save(out_path)
        return out_path
    except Exception as e:
        sys.stderr.write(f"frame_compare: warning: could not write diff image: {e}\n")
        return None


def default_diff_path(candidate_path):
    d = os.path.dirname(os.path.abspath(candidate_path))
    stem = os.path.splitext(os.path.basename(candidate_path))[0]
    cand = os.path.join(d, stem + ".diff.png")
    if os.access(d, os.W_OK):
        return cand
    # Candidate dir not writable -> fall back to a temp file.
    return os.path.join(tempfile.gettempdir(), stem + ".diff.png")


def main(argv):
    ap = argparse.ArgumentParser(description="Objective pixel-compare gate (golden vs candidate).")
    ap.add_argument("golden", help="reference PNG captured from the pristine build")
    ap.add_argument("candidate", help="PNG to test (e.g. device screencap)")
    ap.add_argument("--tolerance", type=float, default=0.02,
                    help="max fraction of differing pixels for a MATCH (default 0.02 = 2%%)")
    ap.add_argument("--threshold", type=int, default=24,
                    help="per-channel delta (0-255) above which a pixel counts as different (default 24)")
    ap.add_argument("--diff", default=None, help="diff-image output path (default: next to candidate)")
    ap.add_argument("--no-diff", action="store_true", help="do not write a diff image")
    ap.add_argument("--quiet", action="store_true", help="suppress the human-readable summary line")
    ap.add_argument("--ignore-rect", action="append", default=[], metavar="X,Y,W,H",
                    help="rectangle in GOLDEN pixel coords to EXCLUDE from the metric (repeatable); "
                         "use to mask the phone's on-screen touch overlay that the desktop golden lacks")
    args = ap.parse_args(argv)

    # --- Load (a load failure is a MISMATCH, not a crash) ---
    try:
        golden = load_rgb(args.golden)
        candidate = load_rgb(args.candidate)
    except Exception as e:
        sys.stderr.write(f"frame_compare: MISMATCH (could not load images): {e}\n")
        return 1

    # --- Normalize to a common resolution (the golden's) ---
    if candidate.size != golden.size:
        candidate_n = candidate.resize(golden.size, Image.LANCZOS)
    else:
        candidate_n = candidate

    # --- Metric: fraction of pixels over the per-channel threshold ---
    diff = ImageChops.difference(golden, candidate_n)
    mask_l = max_channel_delta(diff)

    # --- Optional: EXCLUDE masked rectangles (e.g. the phone's touch overlay) ---
    # The rects are in golden pixel coords. We zero the per-pixel delta inside
    # them so they never count as "over", AND subtract their pixel count from the
    # denominator so the fraction is taken over the VISIBLE (unmasked) area only.
    ignored_px = 0
    if args.ignore_rect:
        from PIL import ImageDraw
        gw, gh = golden.size
        cover = Image.new("L", golden.size, 0)
        drw = ImageDraw.Draw(cover)
        for spec in args.ignore_rect:
            try:
                x, y, w, h = (int(v.strip()) for v in spec.split(","))
            except Exception:
                sys.stderr.write(f"frame_compare: bad --ignore-rect '{spec}' (want X,Y,W,H)\n")
                return 2
            x0, y0 = max(0, x), max(0, y)
            x1, y1 = min(gw, x + w), min(gh, y + h)
            if x1 > x0 and y1 > y0:
                drw.rectangle([x0, y0, x1 - 1, y1 - 1], fill=255)
        ignored_px = sum(cover.histogram()[1:])  # any nonzero value = covered pixel
        if ignored_px:
            mask_l = Image.composite(Image.new("L", golden.size, 0), mask_l, cover)

    hist = mask_l.histogram()  # 256 bins of per-pixel max-delta
    total = sum(hist)
    total_eff = total - ignored_px  # denominator over unmasked pixels only
    over = sum(hist[args.threshold + 1:]) if args.threshold < 255 else 0
    frac = (over / total_eff) if total_eff else 0.0
    rmse = rmse_from_diff(diff)

    is_match = frac <= args.tolerance

    # --- Always (best-effort) write a diff image; never affects the verdict ---
    diff_written = None
    if not args.no_diff:
        out = args.diff if args.diff else default_diff_path(args.candidate)
        diff_written = write_diff_image(golden, candidate_n, mask_l, args.threshold, out)

    if not args.quiet:
        verdict = "MATCH" if is_match else "MISMATCH"
        gw, gh = golden.size
        cw, ch = candidate.size
        line = (f"{verdict}  diff_frac={frac:.5f} (tol={args.tolerance:.5f})  "
                f"rmse={rmse:.2f}  thr={args.threshold}  "
                f"golden={gw}x{gh} candidate={cw}x{ch}")
        if ignored_px:
            line += f"  masked_px={ignored_px} ({len(args.ignore_rect)} rect)"
        if diff_written:
            line += f"  diff={diff_written}"
        print(line)

    return 0 if is_match else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
