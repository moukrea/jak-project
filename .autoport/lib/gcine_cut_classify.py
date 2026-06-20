#!/usr/bin/env python3
"""Gcine-cut classifier: deterministic CUT-vs-INTERPOLATE fingerprint of the
cinematic camera, from the per-frame GCINE-CAM camera-DATA log (the same log
gcine_diff.py reads). Extends the Gcine-audit tooling for phase Gcine-cut.

The owner's defect: at a shot/plan boundary the camera should CUT (the camera
position JUMPS instantaneously to the next shot) but on arm64 it INTERPOLATES
(the position MOVES smoothly toward the next shot over many frames). This is
alignment-robust: it does NOT try to match frame i of run A to frame i of run B
(the two runs are paced differently). Instead it classifies, PER FRAME, the
instantaneous camera motion:

  velocity = |pos[i] - pos[i-1]| / (frame[i] - frame[i-1])

  CUT      velocity  > --cut          (a shot change: instantaneous jump)
  MOVING   --move    < velocity <= --cut   (a continuous pan / interpolation)
  STATIC   velocity <= --move         (a held shot)

A CUT-style sequence (the authored cinematic) = a handful of big CUT spikes
separated by mostly-STATIC held shots. An INTERPOLATED sequence (the bug) = far
fewer CUTs and a much larger MOVING fraction (the camera is always gliding). So
the per-scene (#cuts, moving%) pair IS the cut/interp fingerprint, comparable
across two differently-paced runs without frame alignment.

Usage:
  gcine_cut_classify.py one  LOG [--anchor LVL] [--min-rel N] [--cut U] [--move U]
  gcine_cut_classify.py cmp  ORIG.log TEST.log [--anchor LVL] [--min-rel N]
                              [--cut U] [--move U] [--label-a NAME] [--label-b NAME]
"""
import argparse
import math
import re
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*m")
NUM = r"(-?[0-9.eE+]+)"
LINE = re.compile(
    r"GCINE-CAM f=(\d+) lvl=(\S+) "
    r"px=" + NUM + r" py=" + NUM + r" pz=" + NUM
)


def f(x):
    try:
        return float(x)
    except Exception:
        return float("nan")


class Rec:
    __slots__ = ("frame", "lvl", "pos")

    def __init__(self, m):
        g = m.groups()
        self.frame = int(g[0])
        self.lvl = g[1]
        self.pos = (f(g[2]), f(g[3]), f(g[4]))


def parse(path):
    seen = {}
    with open(path, "r", errors="replace") as fh:
        for ln in fh:
            if "GCINE-CAM" not in ln:
                continue
            m = LINE.search(ANSI.sub("", ln))
            if m:
                r = Rec(m)
                seen[r.frame] = r  # last write wins for a dup frame id
    return [seen[k] for k in sorted(seen)]


def dist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def nan(r):
    return any(math.isnan(v) or math.isinf(v) for v in r.pos)


def anchor_frame(recs, anchor):
    if anchor:
        for r in recs:
            if r.lvl == anchor:
                return r.frame
    return recs[0].frame if recs else 0


def classify(recs, a0, lo, cut, move):
    """Return per-scene dict: lvl -> {cuts:[rel...], n_cut, n_move, n_static,
    n, move_pct} plus the global cut rel-frame list, restricted to rel>=lo."""
    scenes = {}
    cuts = []
    prev = None
    for r in recs:
        rel = r.frame - a0
        if prev is not None and not nan(r) and not nan(prev) and rel >= lo:
            gap = max(1, r.frame - prev.frame)
            vel = dist(prev.pos, r.pos) / gap
            s = scenes.setdefault(r.lvl, {"cuts": [], "n_cut": 0, "n_move": 0,
                                          "n_static": 0, "n": 0})
            s["n"] += 1
            if vel > cut:
                s["n_cut"] += 1
                s["cuts"].append(rel)
                cuts.append((rel, vel, prev.lvl, r.lvl))
            elif vel > move:
                s["n_move"] += 1
            else:
                s["n_static"] += 1
        prev = r
    for s in scenes.values():
        s["move_pct"] = (100.0 * s["n_move"] / s["n"]) if s["n"] else 0.0
    return scenes, cuts


def report_one(label, recs, a0, lo, cut, move, out):
    scenes, cuts = classify(recs, a0, lo, cut, move)
    tot_cut = sum(s["n_cut"] for s in scenes.values())
    tot_move = sum(s["n_move"] for s in scenes.values())
    tot_n = sum(s["n"] for s in scenes.values())
    mp = (100.0 * tot_move / tot_n) if tot_n else 0.0
    out.append(f"### {label}: total CUTs={tot_cut}  moving%={mp:.1f}  (frames analysed={tot_n}, rel>={lo})")
    out.append(f"  {'scene':12s} {'frames':>7s} {'CUTs':>5s} {'moving%':>8s} {'static%':>8s}")
    for lvl in scenes:
        s = scenes[lvl]
        if s["n"] == 0:
            continue
        sp = 100.0 * s["n_static"] / s["n"]
        out.append(f"  {lvl:12s} {s['n']:7d} {s['n_cut']:5d} {s['move_pct']:8.1f} {sp:8.1f}")
    cf = [c[0] for c in cuts]
    out.append("  cut rel-frames: " + (", ".join(str(x) for x in cf[:60]) if cf else "(none)"))
    return tot_cut, mp, scenes, cuts


def cmd_one(a):
    recs = parse(a.log)
    if not recs:
        print("NO GCINE-CAM records", file=sys.stderr)
        return 1
    a0 = anchor_frame(recs, a.anchor)
    out = [f"# gcine_cut_classify ONE  cut={a.cut} move={a.move} anchor={a.anchor!r}->{a0}"]
    report_one(a.label_a or a.log, recs, a0, a.min_rel, a.cut, a.move, out)
    print("\n".join(out))
    return 0


def cmd_cmp(a):
    A = parse(a.orig)
    B = parse(a.test)
    if not A or not B:
        print(f"parse fail: orig={len(A)} test={len(B)}", file=sys.stderr)
        return 1
    a0 = anchor_frame(A, a.anchor)
    b0 = anchor_frame(B, a.anchor)
    out = [f"# gcine_cut_classify CMP  cut={a.cut} move={a.move} anchor={a.anchor!r}",
           f"#   orig anchor abs={a0}  test anchor abs={b0}  (rel>={a.min_rel})", ""]
    la = a.label_a or "ORIG"
    lb = a.label_b or "TEST"
    ca, mpa, _, _ = report_one(la, A, a0, a.min_rel, a.cut, a.move, out)
    out.append("")
    cb, mpb, _, _ = report_one(lb, B, b0, a.min_rel, a.cut, a.move, out)
    out.append("")
    # verdict: the bug = test has materially FEWER cuts AND a higher moving%
    out.append("## VERDICT")
    out.append(f"  {la}: cuts={ca} moving%={mpa:.1f}")
    out.append(f"  {lb}: cuts={cb} moving%={mpb:.1f}")
    cut_ratio = (cb / ca) if ca else float("nan")
    out.append(f"  cut-count ratio {lb}/{la} = {cut_ratio:.2f}  (1.0 = same cadence; <1 = {lb} skips cuts)")
    out.append(f"  moving%% delta = {mpb - mpa:+.1f}  (>0 = {lb} pans more / interpolates)")
    print("\n".join(out))
    return 0


def main(argv):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("one", "cmp"):
        p = sub.add_parser(name)
        if name == "one":
            p.add_argument("log")
        else:
            p.add_argument("orig")
            p.add_argument("test")
        p.add_argument("--anchor", default="misty")
        p.add_argument("--min-rel", dest="min_rel", type=int, default=0)
        p.add_argument("--cut", type=float, default=200000.0)
        p.add_argument("--move", type=float, default=2000.0)
        p.add_argument("--label-a", dest="label_a", default="")
        p.add_argument("--label-b", dest="label_b", default="")
    a = ap.parse_args(argv)
    return cmd_one(a) if a.cmd == "one" else cmd_cmp(a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
