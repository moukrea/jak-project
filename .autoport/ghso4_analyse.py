#!/usr/bin/env python3
"""Ghd-skin-origin-stretch cycle 4 — resume d'une jambe (x86 ou appareil) a partir de ses marqueurs.

Lit un fichier de marqueurs (HDHB*, HDSKIN, HDSKINEV, HDNANSRC*, HDWALL, HDFINITEARM) et publie
les DEUX instruments cote a cote :
  - GOAL (squelette)      : HDHB7 nanimgs/nanm* ; HDHB8 glued/bind/point/stale/passed/singep
  - Merc2 (consommation)  : HDSKIN hd_frames / hd_bad_frames / hd_nan_bones / hd_far_bones / missing
puis une ligne HDSTALE au format de la porte, sur le compte de CONSOMMATION (ce que le GPU lit).
usage : ghso4_analyse.py <marqueurs> <bras> <plateforme> [minutes]
"""
import re
import sys


def kv(line):
    return dict(re.findall(r'(\w+)=([^\s]+)', line))


def last(lines, prefix):
    sel = [l for l in lines if l.startswith(prefix + ' ')]
    return kv(sel[-1]) if sel else {}


def main():
    path, bras, plat = sys.argv[1], sys.argv[2], sys.argv[3]
    minutes = float(sys.argv[4]) if len(sys.argv) > 4 else None
    lines = [l.rstrip('\n') for l in open(path, errors='replace')]
    hb7 = last(lines, 'HDHB7')
    hb8 = last(lines, 'HDHB8')
    hb4 = last(lines, 'HDHB4')
    hb = last(lines, 'HDHB')
    sk = last(lines, 'HDSKIN')
    wall = last(lines, 'HDWALL')
    farm = last(lines, 'HDFINITEARM')
    if minutes is None:
        minutes = float(wall.get('minutes', 0)) if wall else 0.0
    nansrc = [kv(l) for l in lines if l.startswith('HDNANSRC2 ')]
    anims = {}
    for d in nansrc:
        a = d.get('anim', '?')
        anims[a] = anims.get(a, 0) + 1
    ev = [kv(l) for l in lines if l.startswith('HDSKINEV ')]
    ev_hd = [d for d in ev if d.get('hd') == '1']
    models = {}
    for d in ev_hd:
        models[d['model']] = models.get(d['model'], 0) + 1
    print(f"# jambe {path}  bras={bras} plateforme={plat} minutes={minutes:.4f}  "
          f"filet={farm.get('value', hb7.get('farme', '?'))}")
    print(f"# GOAL  : images_recibl={hb.get('fills','?')} nanimgs={hb7.get('nanimgs','?')} "
          f"nanm0={hb7.get('nanm0','?')} nanm3={hb7.get('nanm3','?')} nanm1={hb7.get('nanm1','?')} "
          f"nanglue={hb7.get('nanglue','?')} | glued={hb8.get('glued','?')} bind={hb8.get('bind','?')} "
          f"point={hb8.get('point','?')} stale={hb8.get('stale','?')} passed={hb8.get('passed','?')} "
          f"singep={hb8.get('singep','?')} | HDHB4 nanimages={hb4.get('nanimages','?')} nanmax={hb4.get('nanmax','?')}")
    print(f"# MERC2 : frames={sk.get('frames','?')} bad_frames={sk.get('bad_frames','?')} "
          f"hd_frames={sk.get('hd_frames','?')} hd_bad_frames={sk.get('hd_bad_frames','?')} "
          f"hd_nan_bones={sk.get('hd_nan_bones','?')} hd_far_bones={sk.get('hd_far_bones','?')} "
          f"missing={sk.get('missing','?')} repaired={sk.get('repaired','?')} worst_m={sk.get('worst_m','?')}")
    if anims:
        print("# HDNANSRC par animation du pilote : " +
              ' '.join(f"{a}={n}" for a, n in sorted(anims.items(), key=lambda x: -x[1])))
    if models:
        print("# HDSKINEV (HD) par modele : " + ' '.join(f"{m}={n}" for m, n in models.items()))
    hdf = int(sk.get('hd_frames', 0) or 0)
    hdb = int(sk.get('hd_bad_frames', 0) or 0)
    print(f"HDSTALE bras={bras} plateforme={plat} minutes={minutes:.4f} images={hdf} "
          f"images_avec_matrice_perimee={hdb} joints_touches={int(sk.get('hd_nan_bones',0) or 0)+int(sk.get('hd_far_bones',0) or 0)} "
          f"nan={sk.get('hd_nan_bones','0')} loin={sk.get('hd_far_bones','0')} manquants={sk.get('missing','0')} "
          f"repares={sk.get('repaired','0')} goal_nanimgs={hb7.get('nanimgs','0')} goal_passed={hb8.get('passed','0')} "
          f"modeles={','.join(models) if models else 'aucun'}")


if __name__ == '__main__':
    main()
