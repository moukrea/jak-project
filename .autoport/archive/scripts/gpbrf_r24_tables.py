#!/usr/bin/env python3
"""gpbrf_r24_tables.py — turn the round-24 *_moved.json files into the report's tables.

Usage: gpbrf_r24_tables.py <dir> [<dir> ...]
Prints, on ONE physical line each (the validator greps are line-based):
  * the per-(vantage,tier) coverage table
  * the WORST vantage per tier
  * the per-program roll-up
"""
import glob
import json
import sys

VLABEL = {
    "va": "va sage-hut terrace (the OWNER's vantage)",
    "vb": "vb hut base / stilts, near field",
    "vc": "vc upper warp-gate terrace, looking DOWN on the roofs",
    "vd": "vd stock village1-hut continue: plateau + cliff, long view",
    "ve": "ve village core grass, 184 m from va",
}

rows = []
for d in sys.argv[1:]:
    for f in sorted(glob.glob(d + "/*_moved.json")):
        rows.append(json.load(open(f)))
if not rows:
    sys.exit("no *_moved.json found")

print("VANTAGE / TIER COVERAGE — %% of MAPS-BEARING pixels that ACTUALLY MOVED (ON vs OFF)")
print(f"{'vantage':<10}{'tier':<14}{'maps px':>10}{'moved px':>10}{'moved %':>9}{'false-pos':>10}"
      f"{'floor rel':>11}{'effect rel':>11}{'effect/floor':>13}")
for r in sorted(rows, key=lambda x: (x["tier"], x["label"])):
    ratio = r["eff_rel_mean"] / max(r["floor_rel_mean"], 1e-9)
    print(f"{r['label']:<10}{r['tier']:<14}{r['maps_px']:>10}{r['moved_px']:>10}"
          f"{r['moved_pct']:>8.2f}%{r['false_positive_pct']:>9.2f}%{r['floor_rel_mean']:>11.4f}"
          f"{r['eff_rel_mean']:>11.4f}{ratio:>12.1f}x")
print()
for t in ("tessellation", "parallax"):
    rs = [r for r in rows if r["tier"] == t]
    if not rs:
        continue
    w = min(rs, key=lambda x: x["moved_pct"])
    allv = ", ".join(f"{x['label']} {x['moved_pct']:.2f}%" for x in sorted(rs, key=lambda y: y["label"]))
    print(f"WORST vantage, {t} tier: {w['label']} at {w['moved_pct']:.2f}% of maps-bearing pixels "
          f"actually moved ({w['moved_px']}/{w['maps_px']}) - all vantages: {allv}")
print()
print("PER-PROGRAM ROLL-UP over every captured (vantage, tier) pair")
print(f"{'program':<14}{'drawn px':>12}{'maps px':>11}{'moved px':>11}{'% of maps':>11}{'tessCm':>9}{'pomCm':>9}")
agg = {}
for r in rows:
    for p in r["programs"]:
        a = agg.setdefault(p["program"], dict(drawn=0, maps=0, moved=0, tc=0.0, pc=0.0, n=0))
        a["drawn"] += p["drawn"]
        a["maps"] += p["maps"]
        a["moved"] += p["moved"]
        a["tc"] += p["tess_cm"] * p["maps"]
        a["pc"] += p["pom_cm"] * p["maps"]
        a["n"] += 1
for k, a in sorted(agg.items(), key=lambda kv: -kv[1]["drawn"]):
    mp = 100.0 * a["moved"] / a["maps"] if a["maps"] else 0.0
    tc = a["tc"] / a["maps"] if a["maps"] else 0.0
    pc = a["pc"] / a["maps"] if a["maps"] else 0.0
    print(f"{k:<14}{a['drawn']:>12}{a['maps']:>11}{a['moved']:>11}{mp:>10.2f}%{tc:>9.3f}{pc:>9.3f}")
