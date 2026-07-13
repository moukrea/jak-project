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
# Mode-2 per-frame transition telemetry (gk_android_main.cpp EVTRIAL mode 2):
# catches sub-second transitions (e.g. crate wait->die) that the 60-frame
# sampler can miss entirely when the process dies between samples.
TRANS_RE = re.compile(
    r"EVTRIAL-TRANS f=(\d+) proc='([^']*)' type='([^']*)' state '([^']*)'->'([^']*)'")
SPAWN_RE = re.compile(
    r"EVTRIAL-SPAWN f=(\d+) proc='([^']*)' type='([^']*)' state='([^']*)'")


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

    # proc -> {"type": str, "samples": [(f, state, pos_or_None)], "trans": int}
    procs = {}

    def entry(pname, tname):
        # Key on (proc, type): unnamed procs ('d??', '') otherwise collide
        # across MANY unrelated types in one bucket (fake state chains).
        e = procs.setdefault(pname + "\x00" + tname,
                             {"proc": pname, "type": tname, "samples": [],
                              "trans": 0, "spawn_f": None})
        return e

    with open(args.log, "r", errors="replace") as fh:
        for raw in fh:
            m = LINE_RE.search(raw)
            if m:
                f = int(m.group(1))
                pname, tname, state = m.group(2), m.group(3), m.group(4)
                pos = parse_pos(m.group(5))
                entry(pname, tname)["samples"].append((f, state, pos))
                continue
            m = TRANS_RE.search(raw)
            if m:
                f = int(m.group(1))
                pname, tname = m.group(2), m.group(3)
                old_st, new_st = m.group(4), m.group(5)
                e = entry(pname, tname)
                # synthesize old->new so the state chain shows the transition
                # even when the sampler never caught either endpoint
                if not e["samples"] or e["samples"][-1][1] != old_st:
                    e["samples"].append((f, old_st, None))
                e["samples"].append((f, new_st, None))
                e["trans"] += 1
                continue
            m = SPAWN_RE.search(raw)
            if m:
                f = int(m.group(1))
                pname, tname, state = m.group(2), m.group(3), m.group(4)
                e = entry(pname, tname)
                if not e["samples"]:
                    e["spawn_f"] = f
                    e["samples"].append((f, state, None))

    # A process first seen via a mode-2 SPAWN well after probe start was BORN
    # mid-trial (e.g. a level-hint contextual voice-scene spawning) — direct
    # trigger evidence even with a single sample. Probe start = earliest frame.
    min_f = min((e["samples"][0][0] for e in procs.values() if e["samples"]),
                default=0)

    rows = []
    for e in procs.values():
        pname = e["proc"]
        samples = e["samples"]
        born_late = 1 if (e["spawn_f"] is not None
                          and e["spawn_f"] >= min_f + 300) else 0
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
            "trans": e["trans"],
            "born_late": born_late,
        })

    rows.sort(key=lambda r: (r["trans"], r["born_late"], r["max_disp"]),
              reverse=True)
    for r in rows[:60]:
        arrow = "->".join(r["states"]) if r["states"] else "(none)"
        print("ACTOR proc=%s type=%s samples=%d trans=%d born=%d max_disp=%.0f states=%s" %
              (r["proc"], r["type"], r["n"], r["trans"], r["born_late"],
               r["max_disp"], arrow))

    if args.criteria:
        crits = [c for c in args.criteria.split(",") if c.strip()]
        fired = 0
        for c in crits:
            if ":" in c:
                substr, mind = c.rsplit(":", 1)
            else:
                substr, mind = c, "0"
            substr = substr.strip()
            # Modes: 'substr:state' = must show a state transition (a merely-
            # existing actor is a MISS); 'substr:birth' = must be BORN mid-
            # trial (contextual scene/hint spawn); numeric = legacy
            # (displacement >= N or any state change).
            mode = mind.strip() if mind.strip() in ("state", "birth") else "disp"
            min_disp = 0.0
            if mode == "disp":
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
                # a mode-2 TRANS or a mid-trial birth is direct evidence —
                # exempt from min-samples (a proc that dies fast, e.g. crate
                # wait->die, or a short-lived hint, has few samples)
                if r["trans"] < 1 and not r["born_late"] \
                        and r["n"] < args.min_samples:
                    continue
                if mode == "state":
                    ok = (r["state_changes"] >= 1) or (r["trans"] >= 1)
                elif mode == "birth":
                    ok = bool(r["born_late"]) or (r["trans"] >= 1)
                else:
                    ok = (r["max_disp"] >= min_disp) \
                        or (r["state_changes"] >= 1) or (r["trans"] >= 1)
                if best is None or r["max_disp"] > best["max_disp"]:
                    best = r
                if ok:
                    did_fire = True
            if did_fire:
                fired += 1
            bp = best["proc"] if best else "-"
            bd = best["max_disp"] if best else 0.0
            bk = best["state_changes"] if best else 0
            bt = best["trans"] if best else 0
            print("TRIGGER %s mode=%s min_disp=%g -> %s (best proc=%s disp=%.0f states=%d trans=%d)"
                  % (substr, mode, min_disp, "FIRED" if did_fire else "MISS",
                     bp, bd, bk, bt))
        print("VERDICT fired=%d/%d" % (fired, len(crits)))

    return 0


if __name__ == "__main__":
    sys.exit(main())
