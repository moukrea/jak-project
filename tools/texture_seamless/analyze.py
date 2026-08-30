#!/usr/bin/env python3
"""Classify every texture under a directory as seamless horizontally, vertically,
both, or neither.  See seamless.py for the method and calibrate.py for how the
thresholds were fitted.

  python3 tools/texture_seamless/analyze.py extracted_textures/jak1 \
      -o extracted_textures/jak1-seamless.csv --json extracted_textures/jak1-seamless.json

The input layout is the decompiler's texture dump, <root>/<tpage>/<texture>.png,
which is also the layout custom_assets/<game>/texture_replacements uses, so the
`path` column drops straight into a replacement folder.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import random
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from seamless import Config, analyse_file, classify, to_analysis_array  # noqa: E402

_CFG = Config()


def _work(args):
    path, root = args
    try:
        r = analyse_file(Path(path), _CFG)
    except Exception as e:  # a texture we cannot read is reported, not skipped
        return {"path": str(Path(path).relative_to(root)), "error": str(e)}
    rel = Path(path).relative_to(root)
    r["path"] = str(rel)
    r["tpage"] = rel.parts[0] if len(rel.parts) > 1 else ""
    r["name"] = rel.stem
    return r


def run(root: Path, jobs: int):
    files = sorted(str(p) for p in root.rglob("*.png"))
    if not files:
        sys.exit(f"no .png under {root}")
    payload = [(f, root) for f in files]
    if jobs > 1:
        with ProcessPoolExecutor(max_workers=jobs) as ex:
            results = list(ex.map(_work, payload, chunksize=32))
    else:
        results = [_work(p) for p in payload]
    return results


CSV_COLS = [
    "path", "tpage", "name", "width", "height", "class",
    "seamless_h", "seamless_v", "confidence", "flags",
    "h_step", "h_typical_step", "h_ratio", "h_rank", "h_reason",
    "v_step", "v_typical_step", "v_ratio", "v_rank", "v_reason",
]


def to_row(r):
    if "error" in r:
        return {"path": r["path"], "class": "ERROR", "flags": r["error"]}
    row = {
        "path": r["path"], "tpage": r["tpage"], "name": r["name"],
        "width": r["width"], "height": r["height"], "class": r["class"],
        "seamless_h": int(r["seamless_h"]), "seamless_v": int(r["seamless_v"]),
        "confidence": r["confidence"], "flags": "|".join(r["flags"]),
    }
    for a in ("h", "v"):
        d = r[a]
        row[f"{a}_step"] = f"{d['e_seam']:.5f}"
        row[f"{a}_typical_step"] = f"{d['ref']:.5f}"
        row[f"{a}_ratio"] = f"{d['ratio']:.3f}"
        row[f"{a}_rank"] = f"{d['rank']:.3f}"
        row[f"{a}_reason"] = d["reason"]
    return row


def summarise(results):
    n = len(results)
    ok = [r for r in results if "error" not in r]
    by_class = {}
    for r in ok:
        by_class[r["class"]] = by_class.get(r["class"], 0) + 1
    print(f"\n{len(ok)} textures analysed" + (f" ({n - len(ok)} unreadable)" if n > len(ok) else ""))
    print(f"\n{'verdict':<12}{'count':>7}{'share':>8}")
    for k in ("both", "horizontal", "vertical", "none"):
        c = by_class.get(k, 0)
        print(f"{k:<12}{c:>7}{c / max(len(ok), 1) * 100:>7.1f}%")

    lowc = sum(1 for r in ok if r["confidence"] == "low")
    print(f"\nlow confidence (tiny axis, or verdict decided in the ambiguous border band): {lowc}"
          f" ({lowc / max(len(ok), 1) * 100:.1f}%)")
    for flag in ("constant", "fully-transparent", "transparent-border-h", "transparent-border-v"):
        c = sum(1 for r in ok if flag in r["flags"])
        if c:
            print(f"  flagged {flag:<24} {c}")

    print(f"\n{'tpage':<28}{'n':>5}{'both':>7}{'horiz':>7}{'vert':>7}{'none':>7}"
          f"   (10 most tileable, >=20 textures)")
    per = {}
    for r in ok:
        d = per.setdefault(r["tpage"], {"n": 0, "both": 0, "horizontal": 0, "vertical": 0, "none": 0})
        d["n"] += 1
        d[r["class"]] += 1
    big = [(k, v) for k, v in per.items() if v["n"] >= 20]
    big.sort(key=lambda kv: -kv[1]["both"] / kv[1]["n"])
    for k, v in big[:10]:
        print(f"{k:<28}{v['n']:>5}{v['both']:>7}{v['horizontal']:>7}{v['vertical']:>7}{v['none']:>7}")


def invariance_check(root: Path, results, n: int, seed: int = 0):
    """A truly seamless texture stays seamless when rolled: rolling only moves
    which line the wrap falls on, and every line of a tiling texture is an
    equally valid wrap point.  Any disagreement is this detector contradicting
    itself on the same image, so the rate is a direct stability measurement.

    The converse is not a defect and is not tested: rolling a *seamed* texture
    moves its discontinuity into the interior and genuinely leaves a clean wrap.
    """
    rng = random.Random(seed)
    cand = [r for r in results if "error" not in r and (r["seamless_h"] or r["seamless_v"])
            and min(r["width"], r["height"]) >= 16]
    cand = rng.sample(cand, min(n, len(cand)))
    disagree = {"h": 0, "v": 0}
    tot = {"h": 0, "v": 0}
    for r in cand:
        with Image.open(root / r["path"]) as im:
            x = to_analysis_array(im)
        for axis, key in ((1, "h"), (0, "v")):
            if not r[f"seamless_{key}"]:
                continue
            tot[key] += 1
            shift = rng.randrange(1, x.shape[axis])
            rolled = np.roll(x, shift, axis=axis)
            if not classify(rolled, _CFG)[f"seamless_{key}"]:
                disagree[key] += 1
    print(f"\nroll-invariance on {len(cand)} textures called seamless:")
    for key in ("h", "v"):
        if tot[key]:
            print(f"  {key}: {tot[key] - disagree[key]}/{tot[key]} still seamless after a random "
                  f"roll ({disagree[key] / tot[key] * 100:.1f}% self-contradiction)")


def contact_sheet(root: Path, results, out: Path, per_class: int = 12, seed: int = 0):
    """2x2 tilings of a random sample per verdict, so the call can be eyeballed."""
    rng = random.Random(seed)
    cell = 128
    groups = {}
    for r in results:
        if "error" in r or min(r["width"], r["height"]) < 16:
            continue
        groups.setdefault(r["class"], []).append(r)
    order = [k for k in ("both", "horizontal", "vertical", "none") if k in groups]
    cols = per_class
    sheet = Image.new("RGBA", (cols * cell, len(order) * cell), (24, 24, 28, 255))
    for row, k in enumerate(order):
        for col, r in enumerate(rng.sample(groups[k], min(cols, len(groups[k])))):
            with Image.open(root / r["path"]) as im:
                im = im.convert("RGBA")
                t = Image.new("RGBA", (im.width * 2, im.height * 2))
                for dy in (0, im.height):
                    for dx in (0, im.width):
                        t.paste(im, (dx, dy))
                sheet.paste(t.resize((cell, cell), Image.NEAREST), (col * cell, row * cell))
    sheet.convert("RGB").save(out)
    print(f"\ncontact sheet ({' / '.join(order)}, one row each, each cell tiled 2x2) -> {out}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", type=Path, help="directory of textures (<tpage>/<name>.png)")
    ap.add_argument("-o", "--csv", type=Path)
    ap.add_argument("--json", type=Path)
    ap.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    ap.add_argument("--ratio-max", type=float, help="override the calibrated ratio threshold")
    ap.add_argument("--rank-min", type=float, help="override the calibrated rank threshold")
    ap.add_argument("--strict", action="store_true", help="also require a low robust z-score")
    ap.add_argument("--verify-invariance", type=int, metavar="N", default=0,
                    help="re-classify N seamless textures after a random roll")
    ap.add_argument("--contact-sheet", type=Path, metavar="PNG")
    args = ap.parse_args()

    global _CFG
    _CFG = Config(
        ratio_max=args.ratio_max if args.ratio_max is not None else Config.ratio_max,
        rank_min=args.rank_min if args.rank_min is not None else Config.rank_min,
        strict=args.strict,
    )

    results = run(args.root, args.jobs)

    if args.csv:
        args.csv.parent.mkdir(parents=True, exist_ok=True)
        with open(args.csv, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=CSV_COLS, extrasaction="ignore")
            w.writeheader()
            for r in results:
                w.writerow(to_row(r))
        print(f"csv  -> {args.csv}")
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        with open(args.json, "w") as f:
            json.dump(results, f, indent=1)
        print(f"json -> {args.json}")

    summarise(results)
    if args.verify_invariance:
        invariance_check(args.root, results, args.verify_invariance)
    if args.contact_sheet:
        contact_sheet(args.root, results, args.contact_sheet)


if __name__ == "__main__":
    main()
