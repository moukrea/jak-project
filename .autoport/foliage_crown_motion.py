#!/usr/bin/env python3
"""Grecharged-foliage-wind2 acceptance metric: palm-crown top-half inter-frame motion, OFF vs ON.

Round 1's "motion grid" was cherry-zoned (best cells only). This script measures FIXED,
pre-declared rectangles (palm-crown boxes drawn on the OFF video and applied identically to the
ON video) over the STATIC-HOLD tail of a matched-pose A/B capture, plus two anti-cherry-pick
cross-checks nobody can zone-shop:
  - TOPHALF: the entire top half of the frame (crowns + sky; sky dilutes, never inflates)
  - FULL:    the entire frame

Metric per video: mean over consecutive-frame pairs of mean(|gray[t+1]-gray[t]|) inside the ROI.
Acceptance floor (supervisor): ratio ON/OFF >= 2.0 on the crown ROIs.

Usage:
  foliage_crown_motion.py --off OFF.mp4 --on ON.mp4 \
      --rois "crownL:120,40,300,220;crownR:900,10,380,260" \
      [--tail 8] [--fps 10] [--annotate out.png]

ROIs are in source-video pixel coords (x,y,w,h). --annotate draws them on the first tail frame
of the OFF video so the report can SHOW what was measured.
"""
import argparse, json, os, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image, ImageDraw


def extract_tail_frames(video, tail_s, fps, outdir):
    os.makedirs(outdir, exist_ok=True)
    # -sseof seeks from EOF: exactly the static-hold tail, independent of boot-time offsets.
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error", "-sseof", f"-{tail_s}", "-i", video,
        "-vf", f"fps={fps}", os.path.join(outdir, "f_%04d.png"),
    ]
    subprocess.run(cmd, check=True)
    frames = sorted(os.listdir(outdir))
    if len(frames) < 4:
        sys.exit(f"FATAL: only {len(frames)} tail frames from {video}")
    return [os.path.join(outdir, f) for f in frames]


def load_gray(path):
    return np.asarray(Image.open(path).convert("L"), dtype=np.float32)


def motion(frames, rois):
    """rois: dict name -> (x, y, w, h). Returns dict name -> mean inter-frame |diff|."""
    sums = {k: 0.0 for k in rois}
    prev = load_gray(frames[0])
    n = 0
    for f in frames[1:]:
        cur = load_gray(f)
        d = np.abs(cur - prev)
        for k, (x, y, w, h) in rois.items():
            sums[k] += float(d[y:y + h, x:x + w].mean())
        prev = cur
        n += 1
    return {k: v / n for k, v in sums.items()}


def parse_rois(spec):
    rois = {}
    for part in spec.split(";"):
        part = part.strip()
        if not part:
            continue
        name, coords = part.split(":")
        x, y, w, h = (int(v) for v in coords.split(","))
        rois[name] = (x, y, w, h)
    if not rois:
        sys.exit("FATAL: no ROIs parsed")
    return rois


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--off", required=True)
    ap.add_argument("--on", required=True)
    ap.add_argument("--rois", required=True)
    ap.add_argument("--tail", type=float, default=8.0)
    ap.add_argument("--fps", type=int, default=10)
    ap.add_argument("--annotate")
    args = ap.parse_args()

    rois = parse_rois(args.rois)
    tmp = tempfile.mkdtemp(prefix="crown_motion_")
    try:
        f_off = extract_tail_frames(args.off, args.tail, args.fps, os.path.join(tmp, "off"))
        f_on = extract_tail_frames(args.on, args.tail, args.fps, os.path.join(tmp, "on"))
        n = min(len(f_off), len(f_on))
        f_off, f_on = f_off[:n], f_on[:n]

        h, w = load_gray(f_off[0]).shape
        full = dict(rois)
        full["TOPHALF"] = (0, 0, w, h // 2)
        full["FULL"] = (0, 0, w, h)

        m_off = motion(f_off, full)
        m_on = motion(f_on, full)

        out = {"frames_per_side": n, "tail_s": args.tail, "fps": args.fps,
               "video_wh": [w, h], "rois": {}, }
        crown_ratios = []
        for k in full:
            off_v, on_v = m_off[k], m_on[k]
            ratio = on_v / off_v if off_v > 1e-6 else float("inf")
            out["rois"][k] = {"box": list(full[k]), "off": round(off_v, 4),
                              "on": round(on_v, 4), "ratio": round(ratio, 3)}
            if k not in ("TOPHALF", "FULL"):
                crown_ratios.append(ratio)
        out["crown_ratio_min"] = round(min(crown_ratios), 3)
        out["crown_ratio_mean"] = round(sum(crown_ratios) / len(crown_ratios), 3)
        out["PASS_floor_2.0"] = bool(out["crown_ratio_min"] >= 2.0)
        print(json.dumps(out, indent=2))

        if args.annotate:
            img = Image.open(f_off[0]).convert("RGB")
            dr = ImageDraw.Draw(img)
            for k, (x, y, bw, bh) in rois.items():
                dr.rectangle([x, y, x + bw, y + bh], outline=(255, 0, 0), width=4)
                dr.text((x + 6, y + 6), k, fill=(255, 0, 0))
            dr.rectangle([0, 0, w - 1, h // 2], outline=(255, 255, 0), width=2)
            img.save(args.annotate)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
