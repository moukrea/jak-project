#!/usr/bin/env python3
"""Generate Gd1/projection-match.txt objectively from real GCINE-CAM logs.

D1 fix gate: at the matched-pose held beats M1/M2 the device cutscene camera
projection rows (c0.x, c1.y, c2.x) must MATCH the x86 oracle (scaling ~1.0),
with the audit's 5/3 scaling (0.80 / 1.333 / 0.80) gone, and camera POSITION
unchanged (pose_dist=0.0).

Beats are matched by camera WORLD POSITION (px,py,pz), which is identical across
backends at a held beat (the camera path matches; only the projection differed).
The "before" numbers come from the audit's pre-fix device log; "after" from the
freshly captured post-fix device log. The verdict is emitted ONLY if the after
scaling is within tolerance of 1.0 — this script never fabricates a pass.

Usage:
  gd1_projection_match.py \
      --oracle .autoport/reports/Gcine-audit/x86-cam-shots.log \
      --before .autoport/reports/Gcine-audit/arm64-cam.log \
      --after  .autoport/reports/Gd1/arm64-cam.log \
      --out    .autoport/reports/Gd1/projection-match.txt
"""
import argparse
import re
import sys

NUM = r"(-?[0-9.eE+]+)"
LINE = re.compile(
    r"GCINE-CAM f=(\d+) lvl=(\S+) "
    r"px=" + NUM + r" py=" + NUM + r" pz=" + NUM + r" "
    r"c0=" + ",".join([NUM] * 4) + r" "
    r"c1=" + ",".join([NUM] * 4) + r" "
    r"c2=" + ",".join([NUM] * 4) + r" "
    r"c3=" + ",".join([NUM] * 4)
)

# Matched-pose held beats (from Gcine-audit): camera world position + the
# canonical ORACLE frame number the audit reported (x86-cam-shots.log).
BEATS = {
    "M1": {"pos": (-542035.88, 14012.91, 1402529.75), "ora_f": 4140},
    "M2": {"pos": (-902936.81, 117739.20, 4154412.00), "ora_f": 6900},
}
# Tolerance: |scaling-1.0| <= 0.05 (5%) per the phase gate.
TOL = 0.05
# Position window (game units) that isolates a single held beat. Inter-beat
# distances are millions of units; the held beat itself is ~constant position.
POS_TOL = 200000.0


def parse(path):
    recs = []
    with open(path, errors="replace") as fh:
        for ln in fh:
            m = LINE.search(ln)
            if not m:
                continue
            g = m.groups()
            recs.append({
                "f": int(g[0]), "lvl": g[1],
                "px": float(g[2]), "py": float(g[3]), "pz": float(g[4]),
                "c0": [float(g[5]), float(g[6]), float(g[7]), float(g[8])],
                "c1": [float(g[9]), float(g[10]), float(g[11]), float(g[12])],
                "c2": [float(g[13]), float(g[14]), float(g[15]), float(g[16])],
            })
    return recs


def posdist(r, pos):
    return ((r["px"] - pos[0]) ** 2 + (r["py"] - pos[1]) ** 2 + (r["pz"] - pos[2]) ** 2) ** 0.5


def nearest(recs, pos):
    """Nearest record to pos by Euclidean distance; returns (rec, dist)."""
    best, bestd = None, None
    for r in recs:
        d = posdist(r, pos)
        if bestd is None or d < bestd:
            best, bestd = r, d
    return best, bestd


def by_frame(recs, f):
    for r in recs:
        if r["f"] == f:
            return r
    return None


def zdist(r, ref):
    """Distance over the aspect-INVARIANT projection components (z-rows).
    Same z-rows => same camera orientation => the x/y ratio is the pure aspect
    scaling, not contaminated by a rotation mismatch."""
    return (abs(r["c0"][2] - ref["c0"][2])
            + abs(r["c1"][2] - ref["c1"][2])
            + abs(r["c2"][2] - ref["c2"][2]))


def pose_match(recs, ref):
    """Among records within POS_TOL of the reference pose, pick the one whose
    orientation (z-rows) best matches the reference. Returns (rec, posdist)."""
    pos = (ref["px"], ref["py"], ref["pz"])
    cand = [(zdist(r, ref), posdist(r, pos), r) for r in recs if posdist(r, pos) <= POS_TOL]
    if not cand:
        return nearest(recs, pos)
    cand.sort(key=lambda t: (t[0], t[1]))
    return cand[0][2], cand[0][1]


def ratio(dev, ora):
    return dev / ora if ora != 0 else float("nan")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--oracle", required=True)
    ap.add_argument("--before", required=True)
    ap.add_argument("--after", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    ora = parse(a.oracle)
    bef = parse(a.before)
    aft = parse(a.after)
    if not ora:
        sys.exit(f"no GCINE-CAM records in oracle {a.oracle}")
    if not aft:
        sys.exit(f"no GCINE-CAM records in AFTER (device post-fix) log {a.after} "
                 f"— capture the device cutscene first")

    lines = []
    P = lines.append
    P("# Gd1 — D1 projection re-measurement: new-game cutscene camera vs x86 oracle")
    P("")
    P("Phase Gcine-camfov. Device Redmi eae4df44 (arm64), pkg org.opengoal.gk.jak1.")
    P("Oracle: x86 build-x86/game/gk new-game cutscene, captured at the default")
    P("640x480 window (= ASPECT_4X3 = the authored 4:3 cutscene framing).")
    P(f"  oracle log : {a.oracle}")
    P(f"  device BEFORE (pre-fix, Gcine-audit): {a.before}")
    P(f"  device AFTER  (post-fix, this phase): {a.after}")
    P("")
    P("Beats are matched by camera WORLD POSITION (px,py,pz). At a held beat the")
    P("camera path is identical across backends (pose_dist=0.0); only the")
    P("projection rows differed. The audit measured the device projection scaled")
    P("by 5/3 vs the oracle (c0.x x0.80, c1.y x1.333, c2.x x0.80) = 4:3 widescreen")
    P("(2.222) instead of the authored 4:3 (1.333). The fix forces ASPECT_4X3 +")
    P("pillarbox during cutscenes so the device projection matches the oracle.")
    P("")

    all_ok = True
    for name, spec in BEATS.items():
        pos = spec["pos"]
        # Oracle reference: the audit's canonical frame (fallback nearest pos).
        o = by_frame(ora, spec["ora_f"]) or nearest(ora, pos)[0]
        # Device frames matched by pose (position + orientation z-rows) to oracle.
        b, bd = pose_match(bef, o) if bef else (None, None)
        af, ad = pose_match(aft, o)
        P(f"== Beat {name} (lvl={o['lvl']}, pos {pos[0]:.0f},{pos[1]:.0f},{pos[2]:.0f}) ==")
        P(f"  z-anchor (aspect-invariant): oracle c0.z={o['c0'][2]:.3f} c1.z={o['c1'][2]:.3f} c2.z={o['c2'][2]:.3f}")
        P(f"  oracle x86 (f{o['f']})   : c0.x={o['c0'][0]:+.5f}  c1.y={o['c1'][1]:+.5f}  c2.x={o['c2'][0]:+.5f}")
        if b is not None:
            P(f"  device BEFORE (f{b['f']}) : c0.x={b['c0'][0]:+.5f}  c1.y={b['c1'][1]:+.5f}  c2.x={b['c2'][0]:+.5f}"
              f"   pose_dist={bd:.1f}  z[{b['c0'][2]:.1f}/{b['c1'][2]:.1f}/{b['c2'][2]:.1f}]")
            P(f"     scaling BEFORE vs oracle: c0.x x{ratio(b['c0'][0], o['c0'][0]):.3f}  "
              f"c1.y x{ratio(b['c1'][1], o['c1'][1]):.3f}  c2.x x{ratio(b['c2'][0], o['c2'][0]):.3f}")
        P(f"  device AFTER  (f{af['f']}) : c0.x={af['c0'][0]:+.5f}  c1.y={af['c1'][1]:+.5f}  c2.x={af['c2'][0]:+.5f}"
          f"   pose_dist={ad:.1f}  z[{af['c0'][2]:.1f}/{af['c1'][2]:.1f}/{af['c2'][2]:.1f}]")
        rc0 = ratio(af["c0"][0], o["c0"][0])
        rc1 = ratio(af["c1"][1], o["c1"][1])
        rc2 = ratio(af["c2"][0], o["c2"][0])
        P(f"     scaling AFTER  vs oracle: c0.x x{rc0:.3f}  c1.y x{rc1:.3f}  c2.x x{rc2:.3f}")
        # Orientation must be aligned for the ratio to be meaningful.
        zd = zdist(af, o)
        beat_ok = (abs(rc0 - 1.0) <= TOL and abs(rc1 - 1.0) <= TOL and abs(rc2 - 1.0) <= TOL
                   and ad <= 1.0 and zd <= max(50.0, 0.001 * abs(o["c0"][2])))
        P(f"     orientation z-row delta (must be ~0): {zd:.2f}")
        P(f"     -> {name} {'MATCH (projection==oracle, pose+orientation unchanged)' if beat_ok else 'MISMATCH'}")
        P("")
        all_ok = all_ok and beat_ok

    if all_ok:
        P("RESULT: D1 RESOLVED — the cutscene projection now matches the x86 oracle")
        P("(the authored 4:3 framing). The 5/3 (0.80/1.333) scaling is GONE: every")
        P(f"projection-row ratio is within +/-{int(TOL*100)}% of 1.0. Camera position is")
        P("unchanged (pose_dist=0.0). aspect now ASPECT_4X3 during the cutscene.")
    else:
        P("RESULT: D1 NOT RESOLVED — projection still diverges from the oracle or the")
        P("camera moved. See the per-beat scaling above. (No pass emitted.)")

    out = "\n".join(lines) + "\n"
    with open(a.out, "w") as fh:
        fh.write(out)
    print(out)
    sys.exit(0 if all_ok else 2)


if __name__ == "__main__":
    main()
