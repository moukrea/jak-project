#!/usr/bin/env python3
"""fw3_audit_table.py — DIRECTIVES vd9e8b66782 · phase Grecharged-foliage-wind3.

Met en table les lignes `[foliage-wind] shear-audit` d'une course, decoupees par les marqueurs
`FW3PALIER fps=N` du pilote. Ne calcule rien que la ligne d'audit ne publie pas, SAUF
`dmotion/s` quand la ligne est anterieure a l'ajout du champ (compatibilite avec les journaux
du round 3).
"""
import re, sys

FIELDS = ('fps','rate_ticks','raw_rms','raw_peak','satfrac','stock_rms','stock_peak',
          'dstock_rms','dstock_peak','applied_rms','dapplied_rms','dmotion_per_s','wind_time','frames')

def rows(path):
    palier = None
    out = []
    for line in open(path, errors='replace'):
        m = re.search(r'FW3PALIER fps=(\d+)', line)
        if m:
            palier = m.group(1); continue
        if 'shear-audit' not in line:
            continue
        kv = dict(re.findall(r'(\w+)=([-\d.]+)', line))
        lev = re.search(r'lev=(\S+)', line)
        kv['lev'] = lev.group(1) if lev else '?'
        kv['palier'] = palier or '-'
        out.append(kv)
    return out

def show(path, label):
    rs = rows(path)
    if not rs:
        print(f"{label}: AUCUNE fenetre d'audit"); return
    print(f"\n=== {label} — {len(rs)} fenetres ===")
    hdr = ['pal','lev','fps','ticks','raw_rms','satfrac','bend_rms','mot/img','mot/s','on']
    print(('{:>4} {:>9} {:>6} {:>5} {:>8} {:>8} {:>9} {:>9} {:>9} {:>3}').format(*hdr))
    for k in rs:
        fps = float(k.get('fps', 0))
        dm = k.get('dmotion_per_s')
        dmv = float(dm) if dm is not None else float(k.get('dstock_rms', 0)) * fps
        print(('{:>4} {:>9} {:>6.2f} {:>5} {:>8} {:>8} {:>9} {:>9} {:>9.5f} {:>3}').format(
            k['palier'], k['lev'], fps, k.get('rate_ticks','-'),
            k.get('raw_rms','-'), k.get('satfrac','-'), k.get('stock_rms','-'),
            k.get('dstock_rms','-'), dmv, k.get('on','-')))

if __name__ == '__main__':
    for p in sys.argv[1:]:
        show(p, p)
