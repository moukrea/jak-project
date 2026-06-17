#!/usr/bin/env python3
"""Gcine-audit DATA diff: objective camera/cadence/transition divergence between
the x86 ORACLE GCINE-CAM log and the arm64 DEVICE GCINE-CAM log.

The GCINE-CAM line (emitted by background_common.cpp on BOTH backends) is:

  GCINE-CAM f=<frame_idx> lvl=<level> px=.. py=.. pz=.. \
    c0=a,b,c,d c1=.. c2=.. c3=.. hvdf=.. fog=..

f= is the GLOBAL renderer frame_idx (NOT comparable in absolute terms across
boots), so we re-index each stream to a CINEMATIC-RELATIVE frame: t=0 at the
first frame of a chosen anchor level. We then:

  * timeline   : per-level [first,last,count] in cinematic-relative frames
  * cuts       : frames where the camera position jumps > --cut (a hard cut /
                 transition between camera plans); the ordered cut list is the
                 cadence/transition fingerprint
  * camera diff: after aligning the two streams on the anchor, the per-relative
                 -frame camera position + orientation delta (median / p95 / max)

Usage:
  gcine_diff.py timeline LOG [--anchor LVL] [--cut UNITS]
  gcine_diff.py diff X86.log ARM.log [--anchor LVL] [--cut UNITS] [--out DIR]
"""
import argparse
import math
import re
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*m")
NUM = r"(-?[0-9.eE+]+)"
LINE = re.compile(
    r"GCINE-CAM f=(\d+) lvl=(\S+) "
    r"px=" + NUM + r" py=" + NUM + r" pz=" + NUM + r" "
    r"c0=" + ",".join([NUM] * 4) + r" "
    r"c1=" + ",".join([NUM] * 4) + r" "
    r"c2=" + ",".join([NUM] * 4) + r" "
    r"c3=" + ",".join([NUM] * 4) + r" "
    r"hvdf=" + ",".join([NUM] * 4) + r" "
    r"fog=" + ",".join([NUM] * 4)
)


def f(x):
    try:
        return float(x)
    except Exception:
        return float("nan")


class Rec:
    __slots__ = ("frame", "lvl", "pos", "cam", "hvdf", "fog")

    def __init__(self, m):
        g = m.groups()
        self.frame = int(g[0])
        self.lvl = g[1]
        self.pos = tuple(f(v) for v in g[2:5])
        self.cam = tuple(f(v) for v in g[5:21])  # 4x4 row-major (c0,c1,c2,c3)
        self.hvdf = tuple(f(v) for v in g[21:25])
        self.fog = tuple(f(v) for v in g[25:29])


def parse(path):
    recs = []
    with open(path, "r", errors="replace") as fh:
        for ln in fh:
            if "GCINE-CAM" not in ln:
                continue
            m = LINE.search(ANSI.sub("", ln))
            if m:
                recs.append(Rec(m))
    # dedupe consecutive identical frame ids (renderer can re-emit), keep last
    out = []
    seen = {}
    for r in recs:
        seen[r.frame] = r
    for k in sorted(seen):
        out.append(seen[k])
    return out


def dist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def has_nan(r):
    vals = list(r.pos) + list(r.cam) + list(r.hvdf) + list(r.fog)
    return any(math.isnan(v) or math.isinf(v) for v in vals)


def reindex(recs, anchor):
    """Return (rel_recs, anchor_frame). rel frame = frame - first-frame-at-anchor.
    If anchor not present, anchor on the first record."""
    a0 = None
    if anchor:
        for r in recs:
            if r.lvl == anchor:
                a0 = r.frame
                break
    if a0 is None:
        a0 = recs[0].frame if recs else 0
    return a0


def level_timeline(recs, a0):
    """Ordered list of (level, rel_first, rel_last, count) preserving entry order
    of distinct contiguous level segments (collapses re-entries to segments)."""
    segs = []
    cur = None
    for r in recs:
        rel = r.frame - a0
        if cur is None or cur[0] != r.lvl:
            if cur:
                segs.append((cur[0], cur[1], cur[2], cur[3]))
            cur = [r.lvl, rel, rel, 1]
        else:
            cur[2] = rel
            cur[3] += 1
    if cur:
        segs.append((cur[0], cur[1], cur[2], cur[3]))
    return segs


def find_cuts(recs, a0, cut_units):
    """Frames where camera position jumps > cut_units between consecutive recs."""
    cuts = []
    prev = None
    for r in recs:
        if prev is not None:
            d = dist(prev.pos, r.pos)
            if d > cut_units:
                cuts.append((r.frame - a0, d, prev.lvl, r.lvl))
        prev = r
    return cuts


def pct(vals, p):
    if not vals:
        return float("nan")
    s = sorted(vals)
    k = max(0, min(len(s) - 1, int(round((p / 100.0) * (len(s) - 1)))))
    return s[k]


def cmd_timeline(args):
    recs = parse(args.log)
    if not recs:
        print("NO GCINE-CAM records parsed", file=sys.stderr)
        return 1
    a0 = reindex(recs, args.anchor)
    print(f"# records={len(recs)}  abs_frame=[{recs[0].frame}..{recs[-1].frame}]  "
          f"anchor='{args.anchor}'->abs {a0} (rel 0)")
    nanc = sum(1 for r in recs if has_nan(r))
    print(f"# NaN/Inf camera records: {nanc}")
    print("## level segments (rel_first..rel_last  count)")
    for lvl, lo, hi, n in level_timeline(recs, a0):
        print(f"  {lvl:16s} rel[{lo:7d}..{hi:7d}] n={n}")
    print(f"## hard cuts (|dpos|>{args.cut})")
    for rel, d, l0, l1 in find_cuts(recs, a0, args.cut):
        tag = "" if l0 == l1 else f"  ({l0}->{l1})"
        print(f"  rel {rel:7d}  dpos={d:14.1f}{tag}")
    return 0


def cmd_diff(args):
    A = parse(args.x86)
    B = parse(args.arm)
    if not A or not B:
        print(f"parse fail: x86={len(A)} arm={len(B)}", file=sys.stderr)
        return 1
    a0 = reindex(A, args.anchor)
    b0 = reindex(B, args.anchor)
    Amap = {r.frame - a0: r for r in A}
    Bmap = {r.frame - b0: r for r in B}
    lo, hi = args.min_rel, args.max_rel
    common = [t for t in sorted(set(Amap) & set(Bmap)) if lo <= t <= hi]
    print(f"# x86 recs={len(A)} (anchor '{args.anchor}' abs {a0})  arm recs={len(B)} (anchor abs {b0})")
    print(f"# comparison restricted to cinematic-relative frame >= {lo} "
          f"(excludes non-deterministic pre-anchor title attract)")
    print(f"# common cinematic-relative frames: {len(common)} "
          f"[{common[0] if common else '-'}..{common[-1] if common else '-'}]")

    # --- camera position + orientation delta over common frames ---
    pos_d, rot_d = [], []
    worst = []
    for t in common:
        ra, rb = Amap[t], Bmap[t]
        if has_nan(ra) or has_nan(rb):
            continue
        pd = dist(ra.pos, rb.pos)
        # orientation = upper-left 3x3 of camera (c0,c1,c2 xyz); compare rows
        rd = dist(ra.cam[0:3] + ra.cam[4:7] + ra.cam[8:11],
                  rb.cam[0:3] + rb.cam[4:7] + rb.cam[8:11])
        pos_d.append(pd)
        rot_d.append(rd)
        worst.append((pd, t, ra.lvl, rb.lvl, ra.pos, rb.pos))
    print("## camera POSITION delta over common frames (game units)")
    print(f"  median={pct(pos_d,50):.1f}  p95={pct(pos_d,95):.1f}  max={max(pos_d) if pos_d else float('nan'):.1f}")
    print("## camera ORIENTATION delta (3x3 rows, unitless)")
    print(f"  median={pct(rot_d,50):.5f}  p95={pct(rot_d,95):.5f}  max={max(rot_d) if rot_d else float('nan'):.5f}")
    print("## worst-10 position-divergent frames")
    for pd, t, la, lb, pa, pb in sorted(worst, reverse=True)[:10]:
        print(f"  rel {t:7d}  dpos={pd:14.1f}  x86[{la}] arm[{lb}]")

    # --- NaN presence per stream ---
    print("## NaN/Inf camera records")
    print(f"  x86={sum(1 for r in A if has_nan(r))}  arm={sum(1 for r in B if has_nan(r))}")

    # --- level-progression / cadence: ordered scene SEGMENTS at rel>=min_rel ---
    def segs_from(recs, base):
        return [s for s in level_timeline(recs, base) if s[2] >= lo]
    segA = segs_from(A, a0)
    segB = segs_from(B, b0)
    print(f"## ordered scene SEGMENTS (rel>={lo}) — the cinematic cadence/transition fingerprint")
    print("  x86: " + " -> ".join(f"{s[0]}@{s[1]}" for s in segA))
    print("  arm: " + " -> ".join(f"{s[0]}@{s[1]}" for s in segB))
    print("## scene onset alignment (first rel-frame of each scene, post-anchor)")
    print(f"  {'scene#':>6s} {'x86_lvl':12s} {'x86@':>8s} {'arm_lvl':12s} {'arm@':>8s} {'onset_delta':>11s}")
    for idx in range(max(len(segA), len(segB))):
        sa = segA[idx] if idx < len(segA) else None
        sb = segB[idx] if idx < len(segB) else None
        la = sa[0] if sa else "-"; va = sa[1] if sa else None
        lb = sb[0] if sb else "-"; vb = sb[1] if sb else None
        dv = (vb - va) if (va is not None and vb is not None and la == lb) else None
        match = "" if (la == lb) else "  <ORDER MISMATCH>"
        print(f"  {idx:6d} {la:12s} {('-' if va is None else va):>8} {lb:12s} {('-' if vb is None else vb):>8} "
              f"{('-' if dv is None else dv):>11}{match}")

    # --- cut cadence (rel>=min_rel) ---
    cutsA = [c for c in find_cuts(A, a0, args.cut) if c[0] >= lo]
    cutsB = [c for c in find_cuts(B, b0, args.cut) if c[0] >= lo]
    print(f"## hard cuts (|dpos|>{args.cut})  x86={len(cutsA)}  arm={len(cutsB)}")
    print("  x86 cut rel-frames: " + ", ".join(str(c[0]) for c in cutsA[:40]))
    print("  arm cut rel-frames: " + ", ".join(str(c[0]) for c in cutsB[:40]))

    # --- fog + hvdf divergence over common frames (lighting/projection signal) ---
    fog_d, hvdf_d = [], []
    fog_worst = []
    for t in common:
        ra, rb = Amap[t], Bmap[t]
        if has_nan(ra) or has_nan(rb):
            continue
        fd = dist(ra.fog, rb.fog)
        hd = dist(ra.hvdf, rb.hvdf)
        fog_d.append(fd)
        hvdf_d.append(hd)
        fog_worst.append((fd, t, ra.lvl, ra.fog, rb.fog))
    if fog_d:
        print("## fog delta over common frames (params)")
        print(f"  median={pct(fog_d,50):.3f}  p95={pct(fog_d,95):.3f}  max={max(fog_d):.3f}")
        print("## hvdf (projection offset) delta over common frames")
        print(f"  median={pct(hvdf_d,50):.3f}  p95={pct(hvdf_d,95):.3f}  max={max(hvdf_d):.3f}")
        fw = max(fog_worst)
        print(f"  worst fog frame rel {fw[1]} [{fw[2]}]: x86 fog={tuple(round(v,3) for v in fw[3])} arm fog={tuple(round(v,3) for v in fw[4])}")

    # --- PER-SEGMENT local alignment: re-anchor on each common level's onset and
    #     compare the camera path WITHIN the scene (isolates camera-path bug from
    #     global cadence drift). ---
    # only records inside the cinematic window (rel>=min_rel) so the post-anchor
    # village1 (cinematic) is used, not the pre-anchor attract.
    byA = {}
    for r in A:
        t = r.frame - a0
        if t >= lo:
            byA.setdefault(r.lvl, {})[t] = r
    byB = {}
    for r in B:
        t = r.frame - b0
        if t >= lo:
            byB.setdefault(r.lvl, {})[t] = r
    print(f"## per-scene LOCAL-aligned camera position delta (rel>={lo}; scene onset re-zeroed)")
    print(f"  {'scene':12s} {'n':>6s} {'median':>10s} {'p95':>10s} {'max':>12s}")
    for lvl in [l for l in byA if l in byB and l != "title"]:
        sa = min(byA[lvl]); sb = min(byB[lvl])
        la = {k - sa: v for k, v in byA[lvl].items()}
        lb = {k - sb: v for k, v in byB[lvl].items()}
        comm = sorted(set(la) & set(lb))
        ds = [dist(la[t].pos, lb[t].pos) for t in comm if not has_nan(la[t]) and not has_nan(lb[t])]
        if ds:
            print(f"  {lvl:12s} {len(ds):6d} {pct(ds,50):10.1f} {pct(ds,95):10.1f} {max(ds):12.1f}")

    if args.out:
        import os
        os.makedirs(args.out, exist_ok=True)
        with open(os.path.join(args.out, "camdelta.csv"), "w") as fh:
            fh.write("rel_frame,dpos,drot,x86_lvl,arm_lvl\n")
            for t in common:
                ra, rb = Amap[t], Bmap[t]
                if has_nan(ra) or has_nan(rb):
                    fh.write(f"{t},nan,nan,{ra.lvl},{rb.lvl}\n")
                    continue
                pd = dist(ra.pos, rb.pos)
                rd = dist(ra.cam[0:3] + ra.cam[4:7] + ra.cam[8:11],
                          rb.cam[0:3] + rb.cam[4:7] + rb.cam[8:11])
                fh.write(f"{t},{pd:.1f},{rd:.5f},{ra.lvl},{rb.lvl}\n")
        print(f"# wrote {args.out}/camdelta.csv")
    return 0


def main(argv):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("timeline")
    t.add_argument("log")
    t.add_argument("--anchor", default="")
    t.add_argument("--cut", type=float, default=200000.0)
    d = sub.add_parser("diff")
    d.add_argument("x86")
    d.add_argument("arm")
    d.add_argument("--anchor", default="")
    d.add_argument("--cut", type=float, default=200000.0)
    d.add_argument("--min-rel", dest="min_rel", type=int, default=0)
    d.add_argument("--max-rel", dest="max_rel", type=int, default=10**9)
    d.add_argument("--out", default="")
    args = ap.parse_args(argv)
    if args.cmd == "timeline":
        return cmd_timeline(args)
    return cmd_diff(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
