#!/usr/bin/env python3
"""Ghd-skin-origin-stretch — agregation des marqueurs de course.

Publie :
  HDSTRETCH  la CIBLE de l'etirement (barycentre des os en fuite, pondere par leur nombre) et
             le verdict `est_origine` — ce qui tranche « origine du monde » contre « un lieu » ;
  HDCORREL   la regression lineaire longueur_etirement ~ distance_origine ;
  HDOK       minutes de jeu de la fenetre et nombre d'episodes.

EXCLUSION DECLAREE : un episode dont `distance_origine_m` vaut 0 est un episode ou le PILOTE
n'a pas encore de position monde (ecran-titre, avant le premier niveau). La distance a l'origine
n'y est pas definie, donc il ne peut pas entrer dans une correlation qui la prend pour abscisse.
Ces episodes sont comptes et listes a part, jamais effaces.
"""
import re
import sys


def kv(line):
    return dict(re.findall(r'(\w+)=(-?[\w.+-]+)', line))


def load(path):
    eps, hb, hb2, wall, levels = {}, {}, {}, {}, []
    for ln in open(path, errors='replace'):
        ln = ln.strip()
        for pfx, key in (('HDEPISODE ', 'ep'), ('HDEPX ', 'x'), ('HDEPY ', 'y'),
                         ('HDEPZ ', 'z'), ('HDEPW ', 'w')):
            if ln.startswith(pfx):
                d = kv(ln)
                eps.setdefault(d['id'], {})[key] = d
                if key == 'ep':
                    eps[d['id']]['raw'] = ln
        if ln.startswith('HDHB '):
            hb = kv(ln)
        elif ln.startswith('HDHB2 '):
            hb2 = kv(ln)
        elif ln.startswith('HDWALL '):
            wall = kv(ln)
        elif ln.startswith('HDLEVEL '):
            levels.append(ln.split('=', 1)[1].strip('"'))
    return eps, hb, hb2, wall, levels


def regress(xs, ys):
    n = len(xs)
    if n < 2:
        return None
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    if sxx == 0:
        return None
    a = sxy / sxx
    b = my - a * mx
    sst = sum((y - my) ** 2 for y in ys)
    sse = sum((y - (a * x + b)) ** 2 for x, y in zip(xs, ys))
    return a, b, (1.0 if sst == 0 else 1 - sse / sst)


def main():
    path = sys.argv[1]
    eps, hb, hb2, wall, levels = load(path)
    allc = sorted((v for v in eps.values() if 'ep' in v and 'x' in v),
                  key=lambda v: int(v['ep']['id']))
    placed = [v for v in allc if float(v['ep']['distance_origine_m']) > 0.5]
    unplaced = [v for v in allc if float(v['ep']['distance_origine_m']) <= 0.5]

    print(f"# source : {path}")
    print(f"# niveaux demandes : {len(levels)}   episodes complets : {len(allc)}   "
          f"dont pilote place : {len(placed)}   pilote a l'origine (exclus) : {len(unplaced)}")

    if placed:
        wsum = sum(int(v['x']['n']) for v in placed)
        cx, cy, cz = (sum(float(v['x'][f'cible_{a}']) * int(v['x']['n']) for v in placed) / wsum
                      for a in 'xyz')
        norm = (cx * cx + cy * cy + cz * cz) ** 0.5
        norig = sum(int(v['x'].get('norig', 0)) for v in placed)
        print(f"HDSTRETCH cible_x={cx:.4f} cible_y={cy:.4f} cible_z={cz:.4f} "
              f"est_origine={1 if norm < 1.0 else 0}")
        print(f"# |cible| = {norm:.6f} m ; os en fuite agreges = {wsum} ; "
              f"dont a moins de 6 m de (0,0,0) = {norig} ({100.0*norig/wsum:.1f} %)")

    for v in placed:
        print(v['raw'])
    for v in unplaced:
        print("# EXCLU (pilote sans position monde) : " + v['raw'])

    xs = [float(v['ep']['distance_origine_m']) for v in placed]
    ys = [float(v['ep']['longueur_etirement_m']) for v in placed]
    r = regress(xs, ys)
    if r:
        a, b, r2 = r
        print(f"HDCORREL n={len(xs)} pente={a:.6f} r2={r2:.6f} ordonnee={b:.6f}")
        print(f"# distances couvertes : {min(xs):.1f} m .. {max(xs):.1f} m")

    par = {}
    for v in allc:
        par.setdefault(v['ep']['modele'], []).append(v)
    for m, l in sorted(par.items()):
        vis = sum(int(v['w']['visibles']) for v in l if 'w' in v)
        img = sum(int(v['w']['images']) for v in l if 'w' in v)
        print(f"# modele {m:8s} episodes={len(l):3d} images_d_episode={img} images_visibles={vis}")

    if placed:
        du = sorted(float(v['ep']['duree_ms']) for v in placed)
        print(f"# duree_ms : min={du[0]:.1f} mediane={du[len(du)//2]:.1f} max={du[-1]:.1f}")

    mins = float(wall.get('minutes', 0))
    nep = int(hb.get('episodes', len(allc)))
    print(f"HDOK minutes_de_jeu={mins:.4f} episodes={nep}")
    print(f"# dernier battement : {hb}")
    print(f"# dernier battement2 : {hb2}")


if __name__ == '__main__':
    main()
