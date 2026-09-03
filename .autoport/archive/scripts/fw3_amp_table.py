#!/usr/bin/env python3
"""fw3_amp_table.py — DIRECTIVES vd9e8b66782 · Grecharged-foliage-wind3, defaut D3.

La brise AJOUTEE se lit comme la difference en QUADRATURE entre le cisaillement APPLIQUE et le
cisaillement du jeu (`applied_rms` et `stock_rms` de la meme ligne d'audit) : les deux termes sont
des oscillateurs independants, donc leurs RMS s'ajoutent en carre. Publie aussi la conversion en
METRES, qui est ce que l'oeil voit : le cisaillement est SANS DIMENSION et deplace un sommet de
`cisaillement x (sa hauteur au-dessus de l'origine de l'instance)`.

Hauteurs d'auteur (recensement complet, tie-census-full.txt) :
  palm-01.mb  23.91 m  (le plus haut de jak1)   palm-02.mb  17.52 m
"""
import re, sys, math

H_TALL = 23.91  # palm-01.mb

def rows(p):
    pal = '-'
    for l in open(p, errors='replace'):
        m = re.search(r'FW3PALIER fps=(\d+)', l)
        if m:
            pal = m.group(1); continue
        if 'shear-audit' not in l:
            continue
        kv = dict(re.findall(r'(\w+)=([-\d.]+)', l))
        lm = re.search(r'lev=(\S+)', l)
        kv['lev'] = lm.group(1) if lm else '?'
        kv['pal'] = pal
        yield kv

def show(p, label):
    print(f"\n=== {label} ===")
    print(f"{'pal':>4} {'lev':>9} {'fps':>6} {'on':>3} {'stock':>8} {'applied':>8} "
          f"{'AJOUTE':>8} {'m/palm01':>9} {'d_stock':>9} {'d_appl':>9} {'rap_mot':>8}")
    agg = {}
    for k in rows(p):
        s = float(k.get('stock_rms', 0)); a = float(k.get('applied_rms', 0))
        add = math.sqrt(max(0.0, a * a - s * s))
        ds = float(k.get('dstock_rms', 0)); da = float(k.get('dapplied_rms', 0))
        print(f"{k['pal']:>4} {k['lev']:>9} {float(k.get('fps',0)):>6.2f} {k.get('on','-'):>3} "
              f"{s:>8.5f} {a:>8.5f} {add:>8.5f} {add*H_TALL:>9.3f} {ds:>9.6f} {da:>9.6f} "
              f"{(da/ds if ds>0 else 0):>8.2f}")
        if k['pal'] != '-':
            agg.setdefault(k['lev'], []).append(add)
    if agg:
        print("\n  moyenne du cisaillement AJOUTE par niveau (fenetres des paliers seulement) :")
        for lev, v in sorted(agg.items()):
            m = sum(v) / len(v)
            print(f"    {lev:<10} ajoute_rms={m:.5f}  = {m*H_TALL:.3f} m de couronne sur palm-01 "
                  f"({len(v)} fenetres)")

if __name__ == '__main__':
    for p in sys.argv[1:]:
        show(p, p)
