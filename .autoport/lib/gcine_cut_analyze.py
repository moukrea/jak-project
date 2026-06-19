#!/usr/bin/env python3
"""Gcine-cut CUT-vs-INTERP analyzer (deterministic camera-plan transition diff).

Consumes per-frame camera state from gcine_cut_capture.sh (x86, listener probe):
  CAMCUT f=<t> rst=<int> iv=<float> is=<float> ns=<int>
  CAMPOS f=<t> px=<float> py=<float> pz=<float>
and/or the renderer GCINE-CAM log (x86 + device):
  GCINE-CAM f=<idx> lvl=<lvl> px=.. py=.. pz=.. c0=.. ...

Mechanic (cam-master.gc:632/680/711, cam-combiner.gc:20-22,106-213):
  cam-master 'change-state param1 = blend duration.
    param1 == 0  -> CUT  : (-> *math-camera* reset)=1, slaves swapped instantly =>
                   the camera world position JUMPS in one frame, with num-slaves
                   staying 1 (no two-slave blend).
    param1 != 0  -> INTERP: 'set-interpolation, interp-step=5/param1, num-slaves=2,
                   interp-val ramps 0->1 over ~1/interp-step frames => the camera
                   position MOVES smoothly (no one-frame jump).
The 'reset' flag is cleared by cam-update before a listener-spawned probe can read
it, so the robust, cross-version CUT signal is: a large ONE-FRAME camera-position
JUMP that is NOT inside a num-slaves>=2 interpolation episode. An INTERP is a
contiguous num-slaves>=2 / interp-val-ramping episode (smooth motion). The owner's
bug = a transition that CUTS on the original shows up as an INTERP (smooth pan).

The ordered (CUT|INTERP) list is the cinematic's transition FINGERPRINT. Frame ids
are NOT comparable across boots, so we diff by the ordered fingerprint (counts +
order), never by absolute frame.

Usage:
  gcine_cut_analyze.py fingerprint DUMP [--jump U] [--label NAME]
  gcine_cut_analyze.py diff A.dump B.dump [--jump U] [--a NAME] [--b NAME]
"""
import argparse
import math
import re
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*m")
N = r"([-0-9.eEnafiNAF+]+)"
RE_CUT = re.compile(r"CAMCUT f=(\d+) rst=(-?\d+) iv=" + N + r" is=" + N + r" ns=(-?\d+)")
RE_POS = re.compile(r"CAMPOS f=(\d+) px=" + N + r" py=" + N + r" pz=" + N)
RE_GC = re.compile(r"GCINE-CAM f=(\d+) lvl=(\S+) px=" + N + r" py=" + N + r" pz=" + N)


def ff(x):
    try:
        return float(x)
    except Exception:
        return float("nan")


def parse(path):
    """Return ordered list of frame dicts {f,rst,iv,istep,ns,pos,lvl}.
    Accepts CAMCUT+CAMPOS (probe) and/or GCINE-CAM (renderer) lines."""
    rows = {}
    for ln in open(path, "r", errors="replace"):
        ln = ANSI.sub("", ln)
        m = RE_CUT.search(ln)
        if m:
            f = int(m.group(1))
            r = rows.setdefault(f, dict(f=f))
            r.update(rst=int(m.group(2)), iv=ff(m.group(3)), istep=ff(m.group(4)), ns=int(m.group(5)))
            continue
        m = RE_POS.search(ln)
        if m:
            f = int(m.group(1))
            rows.setdefault(f, dict(f=f))["pos"] = (ff(m.group(2)), ff(m.group(3)), ff(m.group(4)))
            continue
        m = RE_GC.search(ln)
        if m:
            f = int(m.group(1))
            r = rows.setdefault(f, dict(f=f))
            r["lvl"] = m.group(2)
            r["pos"] = (ff(m.group(3)), ff(m.group(4)), ff(m.group(5)))
    out = [rows[f] for f in sorted(rows) if rows[f].get("pos")]
    # drop frames whose ns reads are obviously garbage transient (huge)
    for r in out:
        if r.get("ns", 1) > 1000 or r.get("ns", 1) < 0:
            r["ns"] = 1
    return out


def dist(a, b):
    if not a or not b:
        return 0.0
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def interp_episodes(frames):
    """Contiguous runs where num-slaves>=2 (an active two-slave blend = smooth pan)."""
    eps = []
    s = None
    for i, r in enumerate(frames):
        if r.get("ns", 1) >= 2:
            if s is None:
                s = i
            e = i
        else:
            if s is not None:
                eps.append((s, e))
                s = None
    if s is not None:
        eps.append((s, e))
    return eps


def fingerprint(frames, jump_units):
    """Ordered list of transition events: CUT (one-frame jump, not in a blend) or
    INTERP (num-slaves>=2 ramp episode)."""
    eps = interp_episodes(frames)
    in_ep = [False] * len(frames)
    for s, e in eps:
        for i in range(max(0, s - 1), min(len(frames), e + 2)):
            in_ep[i] = True
    events = []
    # interp episodes
    for s, e in eps:
        ivs = [frames[i].get("iv", float("nan")) for i in range(s, e + 1)]
        events.append(dict(kind="INTERP", at=frames[s]["f"], idx=s,
                           length=e - s + 1, istep=frames[s].get("istep", float("nan")),
                           span=(min(v for v in ivs if v == v) if any(v == v for v in ivs) else float("nan"),
                                 max(v for v in ivs if v == v) if any(v == v for v in ivs) else float("nan"))))
    # hard cuts = big one-frame jumps not inside an interp episode
    for i in range(1, len(frames)):
        d = dist(frames[i - 1].get("pos"), frames[i].get("pos"))
        if d > jump_units and not in_ep[i]:
            events.append(dict(kind="CUT", at=frames[i]["f"], idx=i, dpos=d,
                               ns=frames[i].get("ns", 1), iv=frames[i].get("iv", float("nan"))))
    events.sort(key=lambda e: e["idx"])
    return events, eps


def fmt_ev(e):
    if e["kind"] == "CUT":
        return f"CUT    @f={e['at']:>9d} dpos={e.get('dpos',0):12.1f} ns={e.get('ns','?')}"
    return f"INTERP @f={e['at']:>9d} len={e['length']:>3d}f istep={e.get('istep',float('nan')):.4f} iv[{e['span'][0]:.2f}..{e['span'][1]:.2f}]"


def summarize(frames, label):
    ivs = [r["iv"] for r in frames if "iv" in r]
    iss = [r["istep"] for r in frames if "istep" in r]
    lvls = sorted(set(r["lvl"] for r in frames if "lvl" in r))
    print(f"# {label}: {len(frames)} frames [f={frames[0]['f']}..{frames[-1]['f']}]"
          + (f" iv[{min(ivs):.3f}..{max(ivs):.3f}]" if ivs else "")
          + (f" maxistep={max(iss):.3f}" if iss else "")
          + (f" levels={lvls}" if lvls else ""))


def cmd_fingerprint(args):
    frames = parse(args.dump)
    if not frames:
        print("NO records parsed", file=sys.stderr)
        return 1
    summarize(frames, args.label or args.dump)
    ev, eps = fingerprint(frames, args.jump)
    ncut = sum(1 for e in ev if e["kind"] == "CUT")
    nint = sum(1 for e in ev if e["kind"] == "INTERP")
    print(f"# transitions: {len(ev)}  CUT={ncut}  INTERP={nint}  (jump>{args.jump:.0f})")
    for e in ev:
        print("  " + fmt_ev(e))
    return 0


def analyze_pair(a_dump, b_dump, jump):
    FA, FB = parse(a_dump), parse(b_dump)
    EA, _ = fingerprint(FA, jump)
    EB, _ = fingerprint(FB, jump)
    return FA, FB, EA, EB


def cmd_diff(args):
    FA, FB, EA, EB = analyze_pair(args.a_dump, args.b_dump, args.jump)
    summarize(FA, args.a)
    summarize(FB, args.b)
    seqA = [e["kind"][0] for e in EA]
    seqB = [e["kind"][0] for e in EB]
    cutA = seqA.count("C"); cutB = seqB.count("C")
    intA = seqA.count("I"); intB = seqB.count("I")
    print(f"# {args.a} fingerprint ({len(EA)}): {' '.join(seqA)}")
    print(f"# {args.b} fingerprint ({len(EB)}): {' '.join(seqB)}")
    print(f"# {args.a}: CUT={cutA} INTERP={intA}")
    print(f"# {args.b}: CUT={cutB} INTERP={intB}")
    # order-aligned compare
    mism = sum(1 for i in range(max(len(seqA), len(seqB)))
               if (seqA[i] if i < len(seqA) else None) != (seqB[i] if i < len(seqB) else None))
    print(f"# order-aligned mismatches: {mism}")
    # verdict: cut counts equal (within tol) and order matches => MATCH
    cut_ok = abs(cutA - cutB) <= args.tol
    order_ok = mism <= args.tol
    verdict = "MATCH" if (cut_ok and order_ok) else "MISMATCH"
    print(f"# VERDICT: {verdict} (cut Δ={abs(cutA-cutB)} tol={args.tol}, order-mismatch={mism})")
    return verdict, cutA, cutB, intA, intB, mism


def pos_transitions(frames, motion_floor=8000.0, big=300000.0, gap=4, cut_len=2):
    """Position-only big-move transition detector for GCINE-CAM streams (x86 + device,
    which lack num-slaves). A maximal run of camera motion (per-frame |dpos|>motion_floor,
    bounded by <gap stationary frames) with total displacement>big is a CUT if it
    completes in <=cut_len frames (one instantaneous jump) else an INTERP (a multi-frame
    glide). This is exactly the owner's cut-vs-interp signal: a big position CUT on the
    original showing up as a multi-frame INTERP on the device is the bug."""
    ev = []
    n = len(frames)
    i = 1
    while i < n:
        d = dist(frames[i - 1].get("pos"), frames[i].get("pos"))
        if d <= motion_floor:
            i += 1
            continue
        s = i
        total = 0.0
        peak = 0.0
        quiet = 0
        last = i
        while i < n:
            d = dist(frames[i - 1].get("pos"), frames[i].get("pos"))
            if d > motion_floor:
                total += d
                peak = max(peak, d)
                last = i
                quiet = 0
            else:
                quiet += 1
                if quiet >= gap:
                    break
            i += 1
        length = last - s + 1
        if total > big:
            kind = "CUT" if length <= cut_len else "INTERP"
            ev.append(dict(kind=kind, at=frames[s]["f"], end=frames[last]["f"],
                           length=length, total=total, peak=peak,
                           lvl=frames[s].get("lvl", "")))
    return ev


def cmd_posfp(args):
    frames = parse(args.dump)
    if not frames:
        print("NO records parsed", file=sys.stderr)
        return 1
    summarize(frames, args.label or args.dump)
    ev = pos_transitions(frames, big=args.big)
    ncut = sum(1 for e in ev if e["kind"] == "CUT")
    nint = sum(1 for e in ev if e["kind"] == "INTERP")
    print(f"# big-move transitions: CUT={ncut}  INTERP={nint}  (motion>8000, total>{args.big:.0f}, cut<=2f)")
    for e in ev:
        print(f"  {e['kind']:6s} f={e['at']:>6d}..{e['end']:<6d} lvl={e['lvl']:9s} "
              f"len={e['length']:>3d}f total={e['total']:12.1f} peak={e['peak']:12.1f}")
    return 0


def main(argv):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    pf = sub.add_parser("posfp")
    pf.add_argument("dump")
    pf.add_argument("--big", type=float, default=300000.0)
    pf.add_argument("--label", default="")
    fp = sub.add_parser("fingerprint")
    fp.add_argument("dump")
    fp.add_argument("--jump", type=float, default=200000.0)
    fp.add_argument("--label", default="")
    d = sub.add_parser("diff")
    d.add_argument("a_dump")
    d.add_argument("b_dump")
    d.add_argument("--jump", type=float, default=200000.0)
    d.add_argument("--tol", type=int, default=1)
    d.add_argument("--a", default="A")
    d.add_argument("--b", default="B")
    args = ap.parse_args(argv)
    if args.cmd == "posfp":
        return cmd_posfp(args)
    if args.cmd == "fingerprint":
        return cmd_fingerprint(args)
    cmd_diff(args)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
