#!/usr/bin/env python3
"""Join per-frame spool anim-frame (af) with camera world position (pos) from a
mixed GCINE-CAM + GCINE-SPOOL log (x86 stdout or device logcat). Walks the log in
emission order, tracking the latest GCINE-SPOOL af/part, and for each GCINE-CAM
line emits: <af> <part> <px> <py> <pz>. This lets us compare the camera path at
MATCHED anim-frame across boots (af is boot-invariant; frame ids are not)."""
import re, sys

RE_CAM = re.compile(r"GCINE-CAM f=(\d+) lvl=(\S+) px=([-0-9.]+) py=([-0-9.]+) pz=([-0-9.]+)")
RE_SP = re.compile(r"GCINE-SPOOL strpos=(-?\d+) af=([-0-9.]+) part=(\d+)")

def main(path, af_lo=None, af_hi=None, step=1):
    af = -1.0; part = -1; strpos = 0
    rows = []
    for ln in open(path, "r", errors="replace"):
        m = RE_SP.search(ln)
        if m:
            strpos = int(m.group(1)); af = float(m.group(2)); part = int(m.group(3))
            continue
        m = RE_CAM.search(ln)
        if m:
            f = int(m.group(1)); lvl = m.group(2)
            px, py, pz = float(m.group(3)), float(m.group(4)), float(m.group(5))
            rows.append((af, part, lvl, px, py, pz, f))
    # dedup by af bucket (rounded) to keep it readable, keep last pos seen at each af
    out = []
    last_af = None
    for r in rows:
        afr = r[0]
        if af_lo is not None and (afr < af_lo or afr > af_hi):
            continue
        out.append(r)
    for i, r in enumerate(out):
        if i % step != 0:
            continue
        af_, part_, lvl_, px, py, pz, f = r
        print(f"af={af_:9.2f} part={part_:2d} lvl={lvl_:8s} px={px:12.1f} py={py:11.1f} pz={pz:12.1f}")

if __name__ == "__main__":
    path = sys.argv[1]
    lo = float(sys.argv[2]) if len(sys.argv) > 2 else None
    hi = float(sys.argv[3]) if len(sys.argv) > 3 else None
    step = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    main(path, lo, hi, step)
