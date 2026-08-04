#!/usr/bin/env python3
"""Gtouch-longjump-regression: decode a pad_replay v2 record (pad_demo.inputs)
and print the cpad state around every L1/R1 press edge, plus computed
stick0-speed (pad.gc:363-367 formula, deadzone 0.3 default).

PS2 button0 bits (active-high): L1=10 R1=11 X=14 L2=8 R2=9.
Record: 64-byte header <8sIIIIq32s then 6-byte records <HBBBB (button0,lx,ly,rx,ry).
Gap-filled frames written as exact-neutral {0,127,127,127,127} by the recorder
when the logic frame skips — flagged 'gapfill?' in output.

Usage: gtlj_decode_record.py FILE [deadzone]
"""
import math
import struct
import sys

DEADZONE = float(sys.argv[2]) if len(sys.argv) > 2 else 0.3


def speed(lx, ly):
    fx = 0.0078125 * (lx - 128)
    fy = 0.0078125 * (127 - ly)
    s = min(1.0, math.hypot(fx, fy))
    return 0.0 if s < DEADZONE else s


def main():
    data = open(sys.argv[1], "rb").read()
    magic, ver, rsz, seed, res, anchor, note = struct.unpack_from("<8sIIIIq32s", data, 0)
    print(f"header: magic={magic} ver={ver} rsz={rsz} seed={seed} anchor={anchor}")
    recs = []
    off = 64
    while off + 6 <= len(data):
        recs.append(struct.unpack_from("<HBBBB", data, off))
        off += 6
    print(f"{len(recs)} records")
    prev_b = 0
    edges = []
    for i, (b, lx, ly, rx, ry) in enumerate(recs):
        newly = b & ~prev_b
        if newly & ((1 << 10) | (1 << 11)):
            edges.append(i)
        prev_b = b
    print(f"L1/R1 press edges at frames: {edges}")
    for e in edges:
        print(f"--- edge @ {e} ---")
        for i in range(max(0, e - 6), min(len(recs), e + 20)):
            b, lx, ly, rx, ry = recs[i]
            names = []
            for bit, nm in ((10, "L1"), (11, "R1"), (8, "L2"), (9, "R2"),
                            (14, "X")):
                if b & (1 << bit):
                    names.append(nm)
            gap = (b == 0 and lx == 127 and ly == 127 and rx == 127 and ry == 127)
            sp = speed(lx, ly)
            mark = " <== EDGE" if i == e else ""
            print(f"  f{i}: b=0x{b:04x} [{','.join(names) or '-'}] "
                  f"lx={lx} ly={ly} speed={sp:.3f}"
                  f"{' gapfill?' if gap else ''}{mark}")


if __name__ == "__main__":
    main()
