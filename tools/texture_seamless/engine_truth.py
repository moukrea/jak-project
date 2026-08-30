#!/usr/bin/env python3
"""Merge the engine's own answer to "is this texture meant to repeat" with the
image-based estimate, and report how far apart they are.

The engine answer comes from extract_draw_modes.sh, which dumps one row per
draw: the texture bound, the GS wrap bits, and the UV range of that draw's
vertices.  Two increasingly strict readings are computed per axis:

  repeat  the draw binds the texture with CLAMP off.  Necessary, not
          sufficient: a draw can be in REPEAT mode with UVs that never leave
          [0, 1], in which case no wrap boundary is ever sampled.
  tiled   the drawn UV range actually crosses an integer boundary in its
          interior.  This is the wrap seam being put on screen, which is the
          thing a remade texture has to survive.  A draw running exactly 0..1
          does not count: it shows the texture once.

Textures never drawn through the level pipeline (HUD, fonts, sprite banks) have
no engine row at all; for those the image estimate is all there is, and the
`source` column says so.

  python3 tools/texture_seamless/engine_truth.py \
      extracted_textures/jak1-draw-modes extracted_textures/jak1-seamless.csv \
      -o extracted_textures/jak1-tiling.csv
"""

from __future__ import annotations

import argparse
import collections
import csv
import glob
import math
from pathlib import Path


def crosses(lo: float, hi: float, eps: float = 1e-3) -> bool:
    """Does the drawn UV range actually put a wrap boundary on screen?

    The epsilon matters: a draw whose UVs run exactly 0..1 samples the texture
    once and touches the wrap only at the very edge, which is the canonical
    "one full texture, no repeat".  Without the epsilon floor(0) != floor(1)
    calls that a repeat, and every character eye in the game comes back tiling.
    """
    if (hi - lo) > 1.0 + eps:
        return True
    return math.floor(hi - eps) > math.floor(lo + eps)


def load_engine(draw_modes_dir: Path):
    agg = collections.defaultdict(
        lambda: {
            "n": 0, "rs": 0, "rt": 0, "xs": 0, "xt": 0,
            "span_s": 0.0, "span_t": 0.0, "kinds": set(), "levels": set(),
        }
    )
    n_rows = 0
    for f in sorted(glob.glob(str(draw_modes_dir / "*-draw-modes.csv"))):
        with open(f) as fh:
            for r in csv.DictReader(fh):
                n_rows += 1
                a = agg[(r["tpage"], r["texture"])]
                a["n"] += 1
                rs, rt = int(r["repeat_s"]), int(r["repeat_t"])
                a["rs"] += rs
                a["rt"] += rt
                a["kinds"].add(r["kind"])
                a["levels"].add(r["level"])
                if not int(r["verts"]):
                    continue
                smin, smax = float(r["s_min"]), float(r["s_max"])
                tmin, tmax = float(r["t_min"]), float(r["t_max"])
                if rs and crosses(smin, smax):
                    a["xs"] += 1
                if rt and crosses(tmin, tmax):
                    a["xt"] += 1
                a["span_s"] = max(a["span_s"], smax - smin)
                a["span_t"] = max(a["span_t"], tmax - tmin)
    return agg, n_rows


def klass(h: bool, v: bool) -> str:
    return "both" if h and v else "horizontal" if h else "vertical" if v else "none"


COLS = [
    "path", "tpage", "name", "width", "height",
    "verdict", "source", "repeats_h", "repeats_v",
    "max_tiles_h", "max_tiles_v", "draws_tiled_h", "draws_tiled_v",
    "n_draws", "draw_kinds", "levels",
    "engine_repeat_h", "engine_repeat_v", "engine_tiled_h", "engine_tiled_v",
    "image_class", "image_seamless_h", "image_seamless_v", "image_confidence", "image_flags",
]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("draw_modes", type=Path, help="directory of *-draw-modes.csv")
    ap.add_argument("image_csv", type=Path, help="report from analyze.py")
    ap.add_argument("-o", "--out", type=Path, required=True)
    args = ap.parse_args()

    eng, n_rows = load_engine(args.draw_modes)
    with open(args.image_csv) as fh:
        img = list(csv.DictReader(fh))
    by_key = {(r["tpage"], r["name"]): r for r in img}

    out = []
    for r in img:
        k = (r["tpage"], r["name"])
        a = eng.get(k)
        row = {
            "path": r["path"], "tpage": r["tpage"], "name": r["name"],
            "width": r["width"], "height": r["height"],
            "image_class": r["class"], "image_seamless_h": r["seamless_h"],
            "image_seamless_v": r["seamless_v"], "image_confidence": r["confidence"],
            "image_flags": r["flags"],
        }
        if a:
            th, tv = a["xs"] > 0, a["xt"] > 0
            row.update({
                "verdict": klass(th, tv), "source": "engine",
                "repeats_h": int(th), "repeats_v": int(tv),
                "max_tiles_h": f"{a['span_s']:.2f}", "max_tiles_v": f"{a['span_t']:.2f}",
                "draws_tiled_h": a["xs"], "draws_tiled_v": a["xt"],
                "n_draws": a["n"], "draw_kinds": "|".join(sorted(a["kinds"])),
                "levels": "|".join(sorted(a["levels"])),
                "engine_repeat_h": int(a["rs"] > 0), "engine_repeat_v": int(a["rt"] > 0),
                "engine_tiled_h": int(th), "engine_tiled_v": int(tv),
            })
        else:
            row.update({
                "verdict": r["class"], "source": "image",
                "repeats_h": r["seamless_h"], "repeats_v": r["seamless_v"],
                "max_tiles_h": "", "max_tiles_v": "",
                "draws_tiled_h": "", "draws_tiled_v": "", "n_draws": 0,
                "draw_kinds": "", "levels": "",
                "engine_repeat_h": "", "engine_repeat_v": "",
                "engine_tiled_h": "", "engine_tiled_v": "",
            })
        out.append(row)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with open(args.out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=COLS, extrasaction="ignore")
        w.writeheader()
        w.writerows(out)
    print(f"csv -> {args.out}")

    covered = [r for r in out if r["source"] == "engine"]
    print(f"\n{n_rows} draws over {len(eng)} textures; {len(covered)}/{len(out)} textures "
          f"are drawn through the level pipeline, {len(out) - len(covered)} are not "
          f"(HUD, fonts, sprite banks) and keep the image estimate")

    print(f"\n{'verdict':<12}{'REPEAT bit set':>18}{'seam actually drawn':>22}{'image estimate':>17}")
    cf = collections.Counter(klass(eng[(r['tpage'], r['name'])]["rs"] > 0,
                                   eng[(r['tpage'], r['name'])]["rt"] > 0) for r in covered)
    ct = collections.Counter(r["verdict"] for r in covered)
    ci = collections.Counter(r["image_class"] for r in covered)
    for k in ("both", "horizontal", "vertical", "none"):
        n = len(covered)
        print(f"{k:<12}{cf[k]:>8} ({cf[k]/n*100:>4.1f}%){ct[k]:>12} ({ct[k]/n*100:>4.1f}%)"
              f"{ci[k]:>9} ({ci[k]/n*100:>4.1f}%)")

    print("\nhow well the image estimate reproduces the engine, per axis:")
    for axis, ek, ik in (("horizontal", "engine_tiled_h", "image_seamless_h"),
                         ("vertical", "engine_tiled_v", "image_seamless_v")):
        tp = fp = tn = fn = 0
        for r in covered:
            t, p = r[ek] == 1, r[ik] == "1"
            tp += t and p
            fn += t and not p
            fp += (not t) and p
            tn += (not t) and not p
        tot = tp + fp + tn + fn
        print(f"  {axis:<11} agreement {(tp+tn)/tot*100:>5.1f}%   "
              f"recall {tp/max(tp+fn,1)*100:>5.1f}%   specificity {tn/max(tn+fp,1)*100:>5.1f}%"
              f"   (TP {tp}  FN {fn}  TN {tn}  FP {fp})")
    same = sum(1 for r in covered if r["verdict"] == r["image_class"])
    print(f"  full class agreement {same}/{len(covered)} = {same/len(covered)*100:.1f}%")

    print("\nmost repeated textures (max tiles across one draw):")
    top = sorted(covered, key=lambda r: -max(float(r["max_tiles_h"]), float(r["max_tiles_v"])))[:8]
    for r in top:
        print(f"  {r['path']:<46} {r['max_tiles_h']:>7} x {r['max_tiles_v']:>7}  {r['draw_kinds']}")


if __name__ == "__main__":
    main()
