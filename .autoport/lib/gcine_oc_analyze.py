#!/usr/bin/env python3
"""Gcine-cut OTHERCAM cut/interp analyzer for the lean GCINE-OC / GCINE-JC / GCINE-SP
dumps (x86 gk log AND device routed logcat).

GCINE-OC ct=<int> cji=<int> s1=#t|#f wx=<f> wy=<f> wz=<f>   (othercam world pos, every 16f)
GCINE-JC ct=<int> joint="<name>" movie?=...                 (each (joint ..) spool cmd FIRED)
GCINE-SP ct=<int> strpos=<int> af=<f> part=<int>            (spool anim-frame timeline, every 16f)
GCINE-GUARD ...                                              (spike-clamp fired; MUST be 0 on x86)

The cinematic camera follows an animated joint of the othercam; the spool command
list switches the followed joint via (joint "camera")/(joint "cameraB") at authored
aframes. Switching the joint = a one-frame camera-position CUT (a discrete shot
change). Between switches the joint animates (smooth within-shot motion).

The BUG (arm64): an af-SPIKE fires every joint command at once, so the camera ends
on the final joint and then that joint's animation GLIDES with NO further switches
-> one long continuous pan where the original has several discrete cuts.

Signals (deterministic, frame-id-independent):
  * JC-firing-spread  : are the joint commands fired across many frames (1 per ct,
                        correct) or collapsed into a single ct (the spike bug)?
  * af-spike count    : GCINE-SP af samples with af>5000 (a bad ja-aframe-num read).
  * OC pos fingerprint: per-(every-16f) camera-pos transitions; CUT = a big jump that
                        completes in <=2 samples, GLIDE = a big move spread over >2
                        samples. cji-transition annotated.

Usage:
  gcine_oc_analyze.py report  LOG [--label NAME]
  gcine_oc_analyze.py diff    X86LOG DEVLOG [--a NAME] [--b NAME]
"""
import argparse, math, re, sys

ANSI = re.compile(r"\x1b\[[0-9;]*m")
F = r"([-0-9.eE+]+)"
RE_OC = re.compile(r"GCINE-OC ct=(\d+) cji=(-?\d+) s1=(#[tf]) wx=" + F + r" wy=" + F + r" wz=" + F)
RE_JC = re.compile(r'GCINE-JC ct=(\d+) joint="([^"]*)"')
RE_SP = re.compile(r"GCINE-SP ct=(\d+) strpos=(-?\d+) af=" + F + r" part=(-?\d+)")


def ff(x):
    try: return float(x)
    except Exception: return float("nan")


def parse_oc(path):
    """Ordered, de-duplicated OC samples. The device logcat can contain >1 capture
    pass; we keep the SINGLE longest run of strictly increasing ct (one playthrough)."""
    rows = []
    for ln in open(path, "r", errors="replace"):
        m = RE_OC.search(ANSI.sub("", ln))
        if m:
            rows.append(dict(ct=int(m.group(1)), cji=int(m.group(2)), s1=m.group(3),
                             pos=(ff(m.group(4)), ff(m.group(5)), ff(m.group(6)))))
    # split into monotonic-ct runs, keep the longest
    runs, cur = [], []
    for r in rows:
        if cur and r["ct"] <= cur[-1]["ct"]:
            runs.append(cur); cur = []
        cur.append(r)
    if cur: runs.append(cur)
    return max(runs, key=len) if runs else []


def parse_jc(path):
    out = []
    for ln in open(path, "r", errors="replace"):
        m = RE_JC.search(ANSI.sub("", ln))
        if m: out.append((int(m.group(1)), m.group(2)))
    return out


def parse_sp(path):
    out = []
    for ln in open(path, "r", errors="replace"):
        m = RE_SP.search(ANSI.sub("", ln))
        if m: out.append(dict(ct=int(m.group(1)), strpos=int(m.group(2)),
                              af=ff(m.group(3)), part=int(m.group(4))))
    return out


def dist(a, b):
    if not a or not b: return 0.0
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def transitions(rows, motion=8000.0, big=120000.0, gap=2, cut_len=2):
    """Big-move transitions in the OC pos stream. A maximal motion run (per-step
    |dpos|>motion, bounded by <gap quiet steps) with total>big is a CUT if it
    completes in <=cut_len samples (instant jump) else a GLIDE/INTERP (multi-sample
    pan). cji_change = did the followed joint switch during the run."""
    ev = []; n = len(rows); i = 1
    while i < n:
        if dist(rows[i-1]["pos"], rows[i]["pos"]) <= motion:
            i += 1; continue
        s = i; total = peak = 0.0; quiet = 0; last = i
        cji_set = set([rows[i-1]["cji"], rows[i]["cji"]])
        while i < n:
            d = dist(rows[i-1]["pos"], rows[i]["pos"])
            if d > motion:
                total += d; peak = max(peak, d); last = i; quiet = 0
                cji_set.add(rows[i]["cji"])
            else:
                quiet += 1
                if quiet >= gap: break
            i += 1
        length = last - s + 1
        if total > big:
            # CUT = one dominant instantaneous jump (peak carries most of the motion),
            # even if minor camera drift follows. GLIDE = motion spread across many
            # samples with NO single dominant jump (a continuous pan = the bug).
            dominant = peak >= 0.6 * total
            kind = "CUT" if (length <= cut_len or dominant) else "GLIDE"
            ev.append(dict(kind=kind, at=rows[s]["ct"], end=rows[last]["ct"], length=length,
                           total=total, peak=peak, ratio=peak / total if total else 0.0,
                           cji_from=rows[s-1]["cji"], cji_to=rows[last]["cji"],
                           cji_switch=len(cji_set) > 1))
    return ev


def report(path, label):
    oc = parse_oc(path); jc = parse_jc(path); sp = parse_sp(path)
    print(f"## {label}")
    if not oc:
        print("  (no GCINE-OC rows)");
    else:
        cjis = sorted(set(r["cji"] for r in oc))
        print(f"  OC samples: {len(oc)}  ct[{oc[0]['ct']}..{oc[-1]['ct']}]  cji seen: {cjis}")
    # af spike
    spike = [s for s in sp if s["af"] > 5000.0]
    maxaf = max((s["af"] for s in sp), default=0.0)
    print(f"  SP samples: {len(sp)}  max af={maxaf:.1f}  af-SPIKE(>5000) count: {len(spike)}")
    if spike:
        print(f"    first spike: ct={spike[0]['ct']} af={spike[0]['af']:.1f} part={spike[0]['part']} strpos={spike[0]['strpos']}")
    # JC spread
    if jc:
        cts = [c for c, _ in jc]
        uniq = sorted(set(cts))
        print(f"  JC cmds: {len(jc)}  distinct ct: {len(uniq)} {uniq}")
        collapsed = len(uniq) <= 1 and len(jc) > 2
        print(f"  JC firing: {'COLLAPSED (all at one ct = the bug)' if collapsed else 'spread across frames (ok)'}")
    else:
        print("  JC cmds: 0 (joint commands not captured in window)")
    guard = sum(1 for ln in open(path, errors='replace') if 'GCINE-GUARD ' in ln)
    print(f"  GCINE-GUARD fired: {guard}")
    # OC pos fingerprint
    ev = transitions(oc)
    ncut = sum(1 for e in ev if e["kind"] == "CUT"); ngl = sum(1 for e in ev if e["kind"] == "GLIDE")
    print(f"  OC pos transitions: CUT={ncut}  GLIDE={ngl}  (motion>8000,total>120000,cut<=2 samples)")
    for e in ev:
        sw = "joint-switch" if e["cji_switch"] else "SAME-joint"
        print(f"    {e['kind']:5s} ct={e['at']:>7d}..{e['end']:<7d} len={e['length']:>3d} "
              f"total={e['total']:11.1f} peak={e['peak']:11.1f} pk/tot={e.get('ratio',0):.2f} "
              f"cji {e['cji_from']}->{e['cji_to']} [{sw}]")
    return dict(oc=oc, jc=jc, sp=sp, ev=ev, ncut=ncut, ngl=ngl, spike=len(spike), guard=guard)


def main(argv):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("report"); r.add_argument("log"); r.add_argument("--label", default="")
    d = sub.add_parser("diff"); d.add_argument("a_log"); d.add_argument("b_log")
    d.add_argument("--a", default="x86"); d.add_argument("--b", default="device")
    args = ap.parse_args(argv)
    if args.cmd == "report":
        report(args.log, args.label or args.log); return 0
    A = report(args.a_log, args.a); print(); B = report(args.b_log, args.b); print()
    print("## DIFF")
    print(f"  {args.a}: CUT={A['ncut']} GLIDE={A['ngl']} af-spike={A['spike']} guard={A['guard']}")
    print(f"  {args.b}: CUT={B['ncut']} GLIDE={B['ngl']} af-spike={B['spike']} guard={B['guard']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
