#!/usr/bin/env python3
"""Grecharged-hd-eye-scale ROUND 3 — summarise one gk log (or a routed logcat) from the per-frame
[eyeorb-f] trace, per model.

THE THREE QUESTIONS, for every number published here (SPEC section 7):

  s_globe / s_orbit — NATURE: two SCALE FACTORS, published side by side on the same frame, because
        `owner-defects.txt` says in as many words that publishing only one of the two makes a gap
        between them indistinguishable from a successful correction.
        FRAME: both are least-squares uniform scales about THE SAME origin, the eyeball's own bind
        centroid, so the ratio between them is meaningful and every motion of the head cancels.
        DEFECT ABSENT: both exactly 0 (no blerc displacement, no scaling).

  ratio  — s_orbit / s_globe. This IS the definition of the coupling: damping a coupled pair may
        not change it. A ratio that moves is the defect. Round 2 divided s_globe by k and left
        s_orbit alone, so its ratio moves by exactly 1/k.

  seam   — NATURE: a DISTANCE that opens. "Les yeux flottent dans le vide" is the eyeball coming
        loose from the hole it sits in, not an amplitude.
        FRAME: minimum vertex-to-vertex distance between the eyeball cloud and the socket rim OF
        THE SAME MODEL, read on the very vertices the GPU is about to draw.
        DEFECT ABSENT: seam_bind, the same distance with zero blerc displacement.
        PREDICTION (not a ratio to a moving baseline): scaling a coupled pair by k moves its seam
        by k, so seam must land on seam_bind + k (seam_raw - seam_bind). err_out is the miss of
        the fix; err_half is the miss of round 2, measured on the SAME frame.

usage: hdeye_orbit_summary.py <log> [<log> ...]
"""
import re
import sys

GEOM = re.compile(r'\[eyeorb\] geom verts=(\d+) rim=(\S+) r0=([\d.]+) r1=([\d.]+) '
                  r'bind_seam=([\d.-]+)/([\d.-]+) ok=(\d+) meas=(\d+)')
FRAME = re.compile(
    r'\[eyeorb-f\] n=(\d+) model=(\S+) k=([\d.eE+-]+) orbit=([\d.eE+-]+) '
    r'sg_raw=([\d.eE+-]+) sg_out=([\d.eE+-]+) so_raw=([\d.eE+-]+) so_out=([\d.eE+-]+) '
    r'seam_bind=([\d.eE+-]+) seam_raw=([\d.eE+-]+) seam_half=([\d.eE+-]+) seam_out=([\d.eE+-]+)')


def summarise(path):
    st, geom = {}, []
    with open(path, errors='ignore') as fh:
        for line in fh:
            g = GEOM.search(line)
            if g:
                geom.append(g.group(0).split('] ', 1)[1])
                continue
            m = FRAME.search(line)
            if not m:
                continue
            (_, name, k, orb, sg_raw, sg_out, so_raw, so_out,
             sb, sr, sh, so) = m.groups()
            k, orb = float(k), float(orb)
            sg_raw, sg_out = float(sg_raw), float(sg_out)
            so_raw, so_out = float(so_raw), float(so_out)
            sb, sr, sh, so_ = float(sb), float(sr), float(sh), float(so)
            s = st.setdefault(name, dict(frames=0, damped=0, k_min=1.0, seam_bind=sb,
                                         orbit=orb, ratio_raw=[], ratio_out=[],
                                         sg_raw=-1e30, sg_out=-1e30,
                                         so_raw=-1e30, so_out=-1e30,
                                         err_half=0.0, err_out=0.0,
                                         seam_half=0.0, seam_out=0.0))
            s['frames'] += 1
            s['orbit'] = orb
            s['seam_bind'] = sb
            if k < 0.9999:
                s['damped'] += 1
            s['k_min'] = min(s['k_min'], k)
            s['sg_raw'] = max(s['sg_raw'], sg_raw)
            s['sg_out'] = max(s['sg_out'], sg_out)
            s['so_raw'] = max(s['so_raw'], so_raw)
            s['so_out'] = max(s['so_out'], so_out)
            if abs(sg_raw) > 1e-3 and abs(sg_out) > 1e-6:
                s['ratio_raw'].append(so_raw / sg_raw)
                s['ratio_out'].append(so_out / sg_out)
            pred = sb + k * (sr - sb)
            s['err_half'] = max(s['err_half'], abs(sh - pred))
            s['err_out'] = max(s['err_out'], abs(so_ - pred))
            s['seam_half'] = max(s['seam_half'], sh)
            s['seam_out'] = max(s['seam_out'], so_)
    return geom, st


def mean(v):
    return sum(v) / len(v) if v else float('nan')


def main():
    for path in sys.argv[1:]:
        geom, st = summarise(path)
        print(f'--- {path}')
        for g in sorted(set(geom)):
            print(f'    {g}')
        if not st:
            print('    NO per-frame [eyeorb-f] line (OG_EYEGAP_TRACE=1 set? a model with an eye '
                  'PAIR and a sibling blerc effect rendered?)')
        for name in sorted(st):
            s = st[name]
            print(f'    model={name} frames={s["frames"]} damped={s["damped"]} '
                  f'k_min={s["k_min"]:.4f} orbit={s["orbit"]:.2f} seam_bind={s["seam_bind"]:.3f}')
            print(f'        factors : s_globe raw_max={s["sg_raw"]:.4f} -> out_max={s["sg_out"]:.4f}'
                  f'   s_orbit raw_max={s["so_raw"]:.4f} -> out_max={s["so_out"]:.4f}')
            print(f'        coupling: ratio s_orbit/s_globe  raw={mean(s["ratio_raw"]):.4f} '
                  f'-> out={mean(s["ratio_out"]):.4f}  (unchanged = still coupled)')
            print(f'        seam    : worst |seam - predicted|  round2(socket free)='
                  f'{s["err_half"]:.3f}   round3(socket coupled)={s["err_out"]:.3f}   '
                  f'seam_max half={s["seam_half"]:.3f} out={s["seam_out"]:.3f}')


if __name__ == '__main__':
    main()
