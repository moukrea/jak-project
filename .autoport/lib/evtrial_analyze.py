#!/usr/bin/env python3
# evtrial_analyze.py — Phase Gjak1-intermittent-events analyzer.
# Parses GK-DIAG EVTRIAL telemetry lines out of a device logcat and reports,
# per GOAL actor (process name), how much its root moved and whether its state
# machine ever advanced across the trial. Optional --criteria turns that into a
# textual PASS/MISS verdict for named actors (e.g. an enemy that should chase,
# a platform that should translate, a cutscene actor that should spawn/run).
# stdlib only.
import argparse
import math
import re
import sys

# Lines may carry a logcat threadtime prefix — search, don't anchor.
LINE_RE = re.compile(
    r"EVTRIAL f=(\d+) proc='([^']*)' type='([^']*)' state='([^']*)' pos=\(([^)]*)\)")


def parse_pos(s):
    """Return (x,y,z) floats when the pos field is three finite floats, else None."""
    if s.strip() == "na":
        return None
    parts = s.split()
    if len(parts) != 3:
        return None
    try:
        return tuple(float(p) for p in parts)
    except ValueError:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--criteria", default="")
    ap.add_argument("--min-samples", type=int, default=3)
    args = ap.parse_args()

    # proc -> {"type": str, "samples": [(f, state, pos_or_None)]}
    procs = {}
    with open(args.log, "r", errors="replace") as fh:
        for raw in fh:
            m = LINE_RE.search(raw)
            if not m:
                continue
            f = int(m.group(1))
            pname, tname, state = m.group(2), m.group(3), m.group(4)
            pos = parse_pos(m.group(5))
            e = procs.setdefault(pname, {"type": tname, "samples": []})
            # keep last-seen type (they should be stable per proc)
            e["type"] = tname
            e["samples"].append((f, state, pos))

    rows = []
    for pname, e in procs.items():
        samples = e["samples"]
        n = len(samples)
        # distinct states in order of first appearance
        states = []
        for _, st, _ in samples:
            if not states or states[-1] != st:
                states.append(st)
        distinct = []
        for st in states:
            if st not in distinct:
                distinct.append(st)
        # max displacement from the first plausible pos
        base = None
        max_disp = 0.0
        for _, _, pos in samples:
            if pos is None:
                continue
            if base is None:
                base = pos
                continue
            d = math.dist(base, pos)
            if d > max_disp:
                max_disp = d
        # consecutive-sample state transitions
        state_changes = 0
        prev = None
        for _, st, _ in samples:
            if prev is not None and st != prev:
                state_changes += 1
            prev = st
        rows.append({
            "proc": pname,
            "type": e["type"],
            "n": n,
            "max_disp": max_disp,
            "states": states,
            "distinct": distinct,
            "state_changes": state_changes,
        })

    rows.sort(key=lambda r: r["max_disp"], reverse=True)
    for r in rows[:60]:
        arrow = "->".join(r["states"]) if r["states"] else "(none)"
        print("ACTOR proc=%s type=%s samples=%d max_disp=%.0f states=%s" %
              (r["proc"], r["type"], r["n"], r["max_disp"], arrow))

    if args.criteria:
        crits = [c for c in args.criteria.split(",") if c.strip()]
        fired = 0
        for c in crits:
            if ":" in c:
                substr, mind = c.rsplit(":", 1)
            else:
                substr, mind = c, "0"
            substr = substr.strip()
            try:
                min_disp = float(mind)
            except ValueError:
                min_disp = 0.0
            # candidates: proc whose name OR type contains substr
            cand = [r for r in rows
                    if substr in r["proc"] or substr in r["type"]]
            best = None
            did_fire = False
            for r in cand:
                if r["n"] < args.min_samples:
                    continue
                ok = (r["max_disp"] >= min_disp) or (r["state_changes"] >= 1)
                if best is None or r["max_disp"] > best["max_disp"]:
                    best = r
                if ok:
                    did_fire = True
            if did_fire:
                fired += 1
            bp = best["proc"] if best else "-"
            bd = best["max_disp"] if best else 0.0
            bk = best["state_changes"] if best else 0
            print("TRIGGER %s min_disp=%g -> %s (best proc=%s disp=%.0f states=%d)"
                  % (substr, min_disp, "FIRED" if did_fire else "MISS", bp, bd, bk))
        print("VERDICT fired=%d/%d" % (fired, len(crits)))

    return 0


if __name__ == "__main__":
    sys.exit(main())
