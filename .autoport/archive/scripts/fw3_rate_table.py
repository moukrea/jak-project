#!/usr/bin/env python3
"""fw3_rate_table.py — DIRECTIVES vd9e8b66782 · Grecharged-foliage-wind3.
Cadence du vent (`wind-time` par seconde REELLE) et etat du ressort, par palier de cadence
d'affichage, lus sur les fenetres d'audit du renderer."""
import re, sys, collections

def rate(p, label):
    print(f"\n=== {label} ===")
    print(f"{'palier':>7} {'lev':>9} {'fps':>7} {'ticks':>6} {'dwt':>6} {'dt(s)':>7} "
          f"{'ticks/s':>8} {'raw_rms':>8} {'satfrac':>8} {'bend_rms':>9} {'mot/img':>9}")
    pal = '-'
    prev = collections.defaultdict(lambda: None)
    for l in open(p, errors='replace'):
        m = re.search(r'FW3PALIER fps=(\d+)', l)
        if m:
            pal = m.group(1); continue
        if 'shear-audit' not in l:
            continue
        ts = re.match(r'\[(\d+):(\d+):(\d+)\]', l)
        if not ts:
            continue
        kv = dict(re.findall(r'(\w+)=([-\d.]+)', l))
        lm = re.search(r'lev=(\S+)', l)
        lev = lm.group(1) if lm else '?'
        t = int(ts.group(1)) * 60 + int(ts.group(2)) + int(ts.group(3)) / 1000
        wt = int(kv.get('wind_time', 0))
        pv = prev[lev]
        if pv:
            dt = t - pv[0]; dwt = wt - pv[1]
            if 0.5 < dt < 60:
                print(f"{pal:>7} {lev:>9} {float(kv.get('fps',0)):>7.2f} {kv.get('rate_ticks','-'):>6} "
                      f"{dwt:>6} {dt:>7.2f} {dwt/dt:>8.2f} {kv.get('raw_rms','-'):>8} "
                      f"{kv.get('satfrac','-'):>8} {kv.get('stock_rms','-'):>9} {kv.get('dstock_rms','-'):>9}")
        prev[lev] = (t, wt)

if __name__ == '__main__':
    for p in sys.argv[1:]:
        rate(p, p)
