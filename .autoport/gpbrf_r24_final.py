#!/usr/bin/env python3
"""gpbrf_r24_final.py — the round-24 report block, generated from the captures.

Usage: gpbrf_r24_final.py <capture-dir> [tag ...]
Emits every table the round-24 report quotes, each on one physical line (the validator greps are
line-based). Nothing here is hand-typed into the report.
"""
import sys

import numpy as np
from PIL import Image

NAMES = ["tfrag3_tess", "tfrag3", "etie_base", "tie_wind", "shrub", "hfrag",
         "merc2", "generic", "emerc", "grass"]
RGB = [(255, 255, 0), (255, 0, 0), (0, 255, 0), (0, 255, 255), (0, 0, 255), (255, 128, 0),
       (255, 0, 255), (128, 0, 255), (128, 255, 0), (0, 128, 128)]
WORLD = [1, 1, 1, 1, 1, 1, 0, 0, 0, 1]
VDESC = {"va": "sage-hut terrace (the OWNER's own vantage)",
         "vb": "hut base / stilts, near field",
         "vc": "upper warp-gate terrace, looking DOWN onto the hut roofs",
         "vd": "the stock village1-hut continue: plateau, cliff, long view"}


def blocks(x, B):
    h, w = x.shape
    h, w = h // B * B, w // B * B
    return x[:h, :w].reshape(h // B, B, w // B, B).mean(axis=(1, 3))


def rel(a, b):
    return np.abs(a - b).mean(2) / np.maximum((a.mean(2) + b.mean(2)) * 0.5, 8.0)


def analyse(d, tag):
    P = f"{d}/{tag}_"
    L = lambda n: np.asarray(Image.open(P + n + ".png").convert("RGB"), dtype=np.float32)
    on, o1, o2, sh, st = L("on"), L("off1"), L("off2"), L("sham"), L("onMAX")
    mk, pg, dg = L("mask"), L("prog"), L("diag")
    best = np.full(on.shape[:2], 1e18, np.float32)
    lab = np.full(on.shape[:2], -1, np.int16)
    for i, c in enumerate(RGB):
        q = ((pg - np.array(c, np.float32)) ** 2).sum(2)
        m = q < best
        best[m] = q[m]
        lab[m] = i
    lab[best > 48 * 48 * 3] = -1
    world = np.isin(lab, [i for i, w in enumerate(WORLD) if w])
    maps = (mk.mean(2) > 160) & world
    fl = rel(o1, o2)
    ef = np.minimum(rel(on, o1), rel(on, o2))
    sm = np.minimum(rel(sh, o1), rel(sh, o2))
    sa = np.minimum(rel(st, o1), rel(st, o2))
    thr = np.maximum(3 * fl, 0.01)
    dist = dg[:, :, 2] * 40 / 255
    B = 4
    fb, eb, sb, ab, mb, db = (blocks(fl, B), blocks(ef, B), blocks(sm, B), blocks(sa, B),
                              blocks(maps.astype(np.float32), B), blocks(dist, B))
    tb = np.maximum(3 * fb, 0.01)
    w = mb * (B * B)
    near = db < 20.0
    res = ab > tb
    sel = near & res
    n_sel = (w * sel).sum()
    return dict(
        tag=tag, v=tag[:2], tier=("tessellation" if tag.endswith("t2") else "parallax"),
        maps=int(maps.sum()), moved=int((maps & (ef > thr)).sum()),
        moved_pct=100 * float((ef[maps] > thr[maps]).mean()),
        fp=100 * float((sm[maps] > thr[maps]).mean()),
        floor=float(fl[maps].mean()), eff=float(ef[maps].mean()),
        respond=100 * float((sa[maps] > thr[maps]).mean()),
        near_share=100 * (w * near).sum() / w.sum(),
        near_res_moved=100 * (w * sel * (eb > tb)).sum() / n_sel,
        near_res_fp=100 * (w * sel * (sb > tb)).sum() / n_sel,
        dead_far=100 * float(((maps & ~(ef > thr)) & (dist > 30)).sum() / max((maps & ~(ef > thr)).sum(), 1)),
        prog={NAMES[i]: (int((lab == i).sum()), int((maps & (lab == i)).sum()),
                         int((maps & (lab == i) & (ef > thr)).sum())) for i in range(len(NAMES))},
    )


def main():
    d = sys.argv[1]
    tags = sys.argv[2:] or ["va_t2", "va_t1", "vb_t2", "vb_t1", "vc_t2", "vc_t1", "vd_t2", "vd_t1"]
    rs = []
    for t in tags:
        try:
            rs.append(analyse(d, t))
        except Exception as e:  # a pair that did not capture must be visible, not silently dropped
            print(f"[MISSING] {t}: {e}")
    print()
    print("TABLE 1 — ON-vs-OFF EFFECT, per vantage and tier. Denominator = pixels whose material has a height map.")
    print(f"{'vantage':<4}{'tier':<14}{'maps px':>10}{'moved px':>10}{'raw':>8}{'shamFP':>8}"
          f"{'floor':>9}{'effect':>9}{'effect/floor':>13}{'can respond':>13}")
    for r in rs:
        print(f"{r['v']:<4}{r['tier']:<14}{r['maps']:>10}{r['moved']:>10}{r['moved_pct']:>7.2f}%"
              f"{r['fp']:>7.2f}%{r['floor']:>9.4f}{r['eff']:>9.4f}"
              f"{r['eff']/max(r['floor'],1e-9):>12.1f}x{r['respond']:>12.2f}%")
    for t in ("tessellation", "parallax"):
        sub = [r for r in rs if r["tier"] == t]
        if not sub:
            continue
        wv = min(sub, key=lambda r: r["moved_pct"])
        print(f"  WORST vantage, {t} tier, raw over every maps-bearing pixel at any distance: "
              f"{wv['v']} at {wv['moved_pct']:.2f}% ({wv['moved']}/{wv['maps']}) - "
              + ", ".join(f"{r['v']} {r['moved_pct']:.2f}%" for r in sub))
    print()
    print("TABLE 2 — THE SAME MEASUREMENT INSIDE THE NEAR FIELD (<20 m), over the surface the saturation probe proves can respond, at 4x4 patch granularity")
    print(f"{'vantage':<4}{'tier':<14}{'near share':>12}{'MOVED':>9}{'shamFP':>9}   {'vantage description'}")
    for r in rs:
        print(f"{r['v']:<4}{r['tier']:<14}{r['near_share']:>11.2f}%{r['near_res_moved']:>8.2f}%"
              f"{r['near_res_fp']:>8.2f}%   {VDESC.get(r['v'],'')}")
    if rs:
        w = min(rs, key=lambda r: r["near_res_moved"])
        print(f"  WORST of all {len(rs)} vantage/tier pairs: {w['v']} / {w['tier']} at "
              f"{w['near_res_moved']:.2f}%, sham false-positive {w['near_res_fp']:.2f}%")
    print()
    print("TABLE 3 — PER-PROGRAM ROLL-UP over every captured vantage/tier pair (drawn px / maps-bearing px / moved px)")
    print(f"{'program':<14}{'drawn px':>12}{'maps-bearing':>14}{'moved':>11}{'% of its maps-bearing':>23}")
    agg = {}
    for r in rs:
        for k, (dr, mp, mv) in r["prog"].items():
            a = agg.setdefault(k, [0, 0, 0])
            a[0] += dr
            a[1] += mp
            a[2] += mv
    for k, a in sorted(agg.items(), key=lambda kv: -kv[1][0]):
        p = 100.0 * a[2] / a[1] if a[1] else 0.0
        print(f"{k:<14}{a[0]:>12}{a[1]:>14}{a[2]:>11}{p:>22.2f}%")


if __name__ == "__main__":
    main()
