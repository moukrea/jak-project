#!/usr/bin/env python3
"""hd_check_joint_counts.py — `*hd-joint-counts*` must equal the k2e array sizes.

WHY. The HD joint count lives in FOUR places per character: the three artefacts regenerated
together (`<char>-ag.go`, `<char>-k2e.json`, the four `*<char>-hd-*` arrays in jak-hd.gc) and one
that is NOT — `*hd-joint-counts*`, a hand-written list of eleven integers. `init-jak-hd` reads it
into `hd-joints`, which BOUNDS the retargeting loop.

Measured 2026-08-13: keira-hd went to 100 joints everywhere except here (left at 95). Joints 95..99
were never written, their bone matrices stayed uninitialised, and the engine reported
`PHYSBONE c=2 l=2 len=NaN` — degenerate link, `amp=0.0000`. Five freshly injected bones existed in
the art-group, in the mesh, in the k2e table, and resolved by name into their chains, and did not
move. Nothing in the tree compared the two numbers.

Owner's rule: when a loss repeats, make it impossible at the point of production, not detectable at
the point of control. This is the cheap half — the comparison nobody was making. Run it after any
rig change; exit 1 on a mismatch.
"""
import re
import sys

GC = 'goal_src/jak1/pc/jak-hd.gc'

# The `*hd-ag-names*` order IS the entry order of `*hd-joint-counts*`.
def main():
    src = open(GC, errors='ignore').read()

    m = re.search(r"\(define \*hd-ag-names\*.*?\)\)", src, re.S)
    if not m:
        print("FAIL: *hd-ag-names* not found"); return 1
    names = re.findall(r'"([^"]+)"', m.group(0))

    m = re.search(r"\(define \*hd-joint-counts\* \(new 'static 'array int32 (\d+)([^)]*)\)\)", src)
    if not m:
        print("FAIL: *hd-joint-counts* not found"); return 1
    declared_n = int(m.group(1))
    counts = [int(x) for x in m.group(2).split()]

    bad = []
    if len(names) != declared_n or len(counts) != declared_n:
        bad.append("array sizes disagree: %d names, %d counts, declared %d"
                   % (len(names), len(counts), declared_n))

    for i, nm in enumerate(names):
        # jak-hd's table predates the generalisation and is *jak-hd->eichar-joint*; every later
        # character uses *<char>->driver-joint*. Match the shape, not one spelling.
        a = re.search(r"\(define \*%s->\w+-joint\* \(new 'static 'array uint8 (\d+)"
                      % re.escape(nm), src)
        if not a:
            bad.append("%-10s no *%s->…-joint* array" % (nm, nm)); continue
        want = int(a.group(1))
        got = counts[i] if i < len(counts) else None
        flag = "OK " if got == want else "!! "
        print("%s%-10s entry %-2d  k2e array %-4d  *hd-joint-counts* %s" % (flag, nm, i, want, got))
        if got != want:
            bad.append("%s: k2e array is %d but *hd-joint-counts* says %s — the retargeting loop "
                       "would %s joints" % (nm, want, got,
                                            "skip" if (got or 0) < want else "run past"))

    if bad:
        print("\n[hd-joint-counts FAIL]")
        for b in bad:
            print("  " + b)
        print("  `init-jak-hd` bounds the retarget loop with this number. Too small and the tail")
        print("  joints keep uninitialised bone matrices (PHYSBONE len=NaN, amp=0).")
        return 1
    print("\n[hd-joint-counts PASS] %d characters, every count matches its k2e array" % len(names))
    return 0


if __name__ == '__main__':
    sys.exit(main())
