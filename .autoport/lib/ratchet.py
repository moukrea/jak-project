#!/usr/bin/env python3
"""Anti-regression ratchet for Grecharged-secondary-motion.

The owner's diagnosis (2026-08-07 01:00): "tu corriges un truc puis tu le fais
sauter pour corriger un autre... boucle infinie". Correct — xleg went 0 -> 50 -> 2
while crushing was being worked on, and lenmin went 0.93 -> 0.89 -> 0.68.

Nothing FORBADE regressing. This does: a candidate must not be worse than the best
tuple ever recorded on ANY metric. Trading one target for another is now rejected.
"""
import json, os, re, sys

STORE = ".autoport/ratchet-secondary-motion.json"
# name -> (higher_is_better, regex)
METRICS = {
    "restdevA": (False, r"restdevA\s*=\s*([0-9]+\.?[0-9]*)"),
    "lenmin":   (True,  r"lenmin\s*=\s*([0-9]+\.?[0-9]*)"),
    "lensim":   (True,  r"lensim\s*=\s*([0-9]+\.?[0-9]*)"),
    "xleg":     (False, r"xleg\s*=\s*([0-9]+)"),
}
TOL = 1e-6

def read(path):
    t = open(path, errors="ignore").read()
    out = {}
    for k, (hib, rx) in METRICS.items():
        v = [float(x) for x in re.findall(rx, t)]
        if v:
            out[k] = max(v) if hib is False else min(v)   # worst value seen
    return out

def main():
    report = sys.argv[1]
    cur = read(report)
    if not cur:
        print("ratchet: no metrics in report", file=sys.stderr); return 1
    best = json.load(open(STORE)) if os.path.exists(STORE) else {}
    regress = []
    for k, v in cur.items():
        if k not in best:
            continue
        hib = METRICS[k][0]
        if (hib and v < best[k] - TOL) or ((not hib) and v > best[k] + TOL):
            regress.append(f"{k}: {v} is worse than the best recorded {best[k]}")
    if regress:
        for r in regress:
            print("ratchet REGRESSION -> " + r, file=sys.stderr)
        return 1
    merged = dict(best)
    for k, v in cur.items():
        hib = METRICS[k][0]
        merged[k] = v if k not in best else (max(best[k], v) if hib else min(best[k], v))
    json.dump(merged, open(STORE, "w"), indent=2, sort_keys=True)
    print("ratchet OK: " + ", ".join(f"{k}={v}" for k, v in sorted(merged.items())))
    return 0

sys.exit(main())
