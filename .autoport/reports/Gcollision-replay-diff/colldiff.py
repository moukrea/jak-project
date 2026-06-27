#!/usr/bin/env python3
# Gcollision-replay-diff: compare two per-logic-frame collision-state traces
# (x86 oracle vs arm64 device) produced by the pad_replay state-dump hook.
# Trace line format:  ci frame=<N> <byte> <byte> ...   (172 bytes)
# Finds the FIRST logic frame whose collision state diverges, and names the field.
import sys, struct

# field layout in the dumped buffer (offset, length, name, kind)
FIELDS = [
    (0,   16, "trans",             "vec"),
    (16,  16, "quat",              "vec"),
    (32,  16, "transv",            "vec"),
    (48,  16, "rotv",              "vec"),
    (64,   8, "status",            "u64"),
    (72,  16, "local-normal",      "vec"),
    (88,  16, "surface-normal",    "vec"),
    (104, 16, "poly-normal",       "vec"),
    (120, 16, "ground-poly-normal","vec"),
    (136, 16, "ground-touch-point","vec"),
    (152,  4, "ground-impact-vel", "f32"),
    (156,  4, "surface-angle",     "f32"),
    (160,  4, "poly-angle",        "f32"),
    (164,  4, "touch-angle",       "f32"),
    (168,  4, "coverage",          "f32"),
]

def load(path):
    out = {}
    with open(path, "r", errors="replace") as f:
        for ln in f:
            if not ln.startswith("ci frame="):
                continue
            sp = ln.split()
            try:
                fr = int(sp[1].split("=")[1])
            except Exception:
                continue
            try:
                b = bytes(int(x, 16) for x in sp[2:])
            except Exception:
                continue
            out[fr] = b
    return out

def fmt_field(b, off, length, kind):
    chunk = b[off:off+length]
    if kind == "vec":
        fs = struct.unpack("<4f", chunk)
        return "[" + ", ".join(f"{x:.5g}" for x in fs) + "]"
    if kind == "f32":
        return f"{struct.unpack('<f', chunk)[0]:.6g}"
    if kind == "u64":
        return "0x" + chunk[::-1].hex()
    return chunk.hex()

def which_fields_differ(a, b):
    diffs = []
    for off, length, name, kind in FIELDS:
        if a[off:off+length] != b[off:off+length]:
            diffs.append((off, length, name, kind))
    return diffs

def main():
    if len(sys.argv) < 3:
        print("usage: colldiff.py X86.trace ARM.trace"); sys.exit(2)
    x = load(sys.argv[1]); a = load(sys.argv[2])
    common = sorted(set(x) & set(a))
    print(f"x86 frames={len(x)}  arm frames={len(a)}  common={len(common)}")
    if not common:
        print("NO COMMON FRAMES"); sys.exit(1)
    print(f"common range: {common[0]}..{common[-1]}")
    first = None
    n_match = 0
    for fr in common:
        if x[fr] == a[fr]:
            n_match += 1
        else:
            first = fr
            break
    if first is None:
        print(f"RESULT: IDENTICAL over all {len(common)} common frames (no divergence)")
        return
    print(f"RESULT: FIRST DIVERGENCE at logic frame {first}  ({n_match} frames matched before it)")
    diffs = which_fields_differ(x[first], a[first])
    print(f"  diverging fields at frame {first}: {', '.join(d[2] for d in diffs)}")
    for off, length, name, kind in diffs:
        print(f"    {name:20s} x86={fmt_field(x[first],off,length,kind)}")
        print(f"    {'':20s} arm={fmt_field(a[first],off,length,kind)}")
    # context: show the diverging field's trajectory a few frames before/after
    show = [f for f in common if first-3 <= f <= first+3]
    pf = diffs[0]
    print(f"\n  context for first-diverging field '{pf[2]}' (frames {show[0]}..{show[-1]}):")
    for fr in show:
        mark = " <-- FIRST DIFF" if fr == first else ""
        print(f"    frame {fr}: x86={fmt_field(x[fr],pf[0],pf[1],pf[3])} "
              f"arm={fmt_field(a[fr],pf[0],pf[1],pf[3])}{mark}")
    # how many of the remaining common frames differ (divergence breadth)
    ndiff = sum(1 for fr in common if x[fr] != a[fr])
    print(f"\n  total diverging common frames: {ndiff}/{len(common)}")

if __name__ == "__main__":
    main()
