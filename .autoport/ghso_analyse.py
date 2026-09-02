#!/usr/bin/env python3
"""Ghd-skin-origin-stretch — agregation des marqueurs d'UNE jambe de course.

Publie :
  HDSTRETCH  la CIBLE de l'etirement (barycentre des os en fuite, pondere par leur nombre) et le
             verdict `est_origine` — ce qui tranche « origine du monde » contre « un lieu » ;
  HDCORREL   la regression lineaire longueur_etirement ~ distance_origine ;
  HDANIM     l'etat du SEUL terme variable du reciblage, `M_eichar_anim[e]`, releve au pic de
             chaque episode : combien d'episodes lisent une matrice pilote NULLE ;
  HDSPLIT    dechirures vers l'ORIGINE contre dechirures AILLEURS, fermetures forcees, serie max ;
  HDOK       minutes de la fenetre et nombre d'episodes.

ABSCISSE. `distance_origine_m` est desormais |root trans| du pilote — la position du PROCESS. La
version precedente lisait |draw origin|, qui est RECOPIE d'un os du squelette
(process-drawable.gc:245), c'est-a-dire de la grandeur meme que le defaut annule : elle rendait 0
pendant chaque episode et vidait la correlation de ses points. Les deux valeurs sont publiees cote
a cote (`HDEPV dessin_m=... racine_m=...`) : leur ECART est une lecture directe du defaut.

EXCLUSION DECLAREE : un episode dont `distance_origine_m` vaut 0 est un episode ou le pilote n'a
pas encore de position monde (ecran-titre, avant le premier niveau). Ces episodes sont comptes et
listes a part, jamais effaces.
"""
import re
import sys


def kv(line):
    return dict(re.findall(r'(\w+)=(-?[\w.+-]+)', line))


def load(path):
    """Ne lit QUE les marqueurs postérieurs au dernier `HDRESET` : c'est lui qui ouvre la fenetre
    de mesure. Les episodes d'avant (ecran-titre, amorce) portent des identifiants qui se
    REPETENT apres la remise a zero — les melanger ecrasait silencieusement des lignes."""
    eps, hb, hb2, hb3, wall, levels, drv = {}, {}, {}, {}, {}, [], []
    raw = open(path, errors='replace').read().split('\n')
    if any(l.startswith('HDRESET') for l in raw):
        i = max(n for n, l in enumerate(raw) if l.startswith('HDRESET'))
        raw = raw[i:]
    for ln in raw:
        ln = ln.strip()
        for pfx, key in (('HDEPISODE ', 'ep'), ('HDEPX ', 'x'), ('HDEPY ', 'y'),
                         ('HDEPZ ', 'z'), ('HDEPW ', 'w'), ('HDEPV ', 'v')):
            if ln.startswith(pfx):
                d = kv(ln)
                eps.setdefault(d['id'], {})[key] = d
                if key == 'ep':
                    eps[d['id']]['raw'] = ln
        if ln.startswith('HDHB '):
            hb = kv(ln)
        elif ln.startswith('HDHB2 '):
            hb2 = kv(ln)
        elif ln.startswith('HDHB3 '):
            hb3 = kv(ln)
        elif ln.startswith('HDWALL '):
            wall = kv(ln)
        elif ln.startswith('HDDRV '):
            drv.append(kv(ln))
        elif ln.startswith('HDLEVEL '):
            levels.append(ln.split('=', 1)[1].strip('"'))
    return eps, hb, hb2, hb3, wall, levels, drv


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
    eps, hb, hb2, hb3, wall, levels, drv = load(path)
    allc = sorted((v for v in eps.values() if 'ep' in v and 'x' in v),
                  key=lambda v: int(v['ep']['id']))
    placed = [v for v in allc if float(v['ep']['distance_origine_m']) > 0.5]
    unplaced = [v for v in allc if float(v['ep']['distance_origine_m']) <= 0.5]

    print(f"# source : {path}   arme={hb2.get('arme', '?')}")
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
              f"dont a moins de 6 m de (0,0,0) = {norig} ({100.0 * norig / wsum:.1f} %)")

    for v in placed:
        print(v['raw'])
        if 'v' in v:
            print("#   " + f"HDEPV dessin_m={v['v']['dessin_m']} racine_m={v['v']['racine_m']}"
                  + f" etal_pilote_m={v['v'].get('etal_pilote_m')}"
                  + f"  arow={v.get('z', {}).get('arow', '?')} atrans={v.get('z', {}).get('atrans', '?')}"
                  + f"  norig={v['x'].get('norig')}/{v['x'].get('n')}"
                  + f"  force={v.get('w', {}).get('force', '?')}")
    for v in unplaced:
        print("# EXCLU (pilote sans position monde) : " + v['raw'])

    xs = [float(v['ep']['distance_origine_m']) for v in placed]
    ys = [float(v['ep']['longueur_etirement_m']) for v in placed]
    r = regress(xs, ys)
    if r:
        a, b, r2 = r
        print(f"HDCORREL n={len(xs)} pente={a:.6f} r2={r2:.6f} ordonnee={b:.6f}")
        print(f"# distances couvertes : {min(xs):.1f} m .. {max(xs):.1f} m")

    # HDANIM : l'etat de M_eichar_anim[e], LE seul terme variable de la formule de reciblage.
    nul = sum(1 for v in allc if 'z' in v and abs(float(v['z']['arow'])) < 1e-3
              and abs(float(v['z']['atrans'])) < 1e-3)
    vivante = len([v for v in allc if 'z' in v]) - nul
    osnuls = max((int(d['osnuls']) for d in drv), default=-1)
    lus = max((int(d['lus']) for d in drv), default=-1)
    print(f"HDANIM episodes={len(allc)} matrice_pilote_nulle={nul} matrice_pilote_vivante={vivante} "
          f"osnuls_max={osnuls} joints_hd_lisant_un_os_non_ecrit_max={lus}")

    par = {}
    for v in allc:
        par.setdefault(v['ep']['modele'], []).append(v)
    for m, l in sorted(par.items()):
        vis = sum(int(v['w']['visibles']) for v in l if 'w' in v)
        img = sum(int(v['w']['images']) for v in l if 'w' in v)
        print(f"# modele {m:8s} episodes={len(l):3d} images_d_episode={img} images_visibles={vis}")

    if placed:
        du = sorted(float(v['ep']['duree_ms']) for v in placed)
        print(f"# duree_ms : min={du[0]:.1f} mediane={du[len(du) // 2]:.1f} max={du[-1]:.1f}")

    print(f"HDSPLIT origine={hb3.get('origine', '?')} autres={hb3.get('autres', '?')} "
          f"forcees={hb3.get('forcees', '?')} runmax={hb3.get('runmax', '?')} "
          f"images_pilote_sans_pose={hb3.get('sansposeimages', '?')}")
    print(f"HDOCC images_recibles={hb.get('fills', '?')} images_avec_occasion={hb.get('gardeimages', '?')} "
          f"joints_refuses={hb.get('gardejoints', '?')} occasions_joints={hb2.get('occjoints', '?')} "
          f"occasions_racine={hb2.get('occracine', '?')} "
          f"images_dechirees={hb2.get('imagesdechirees', hb2.get('deplaces', '?'))}")

    mins = float(wall.get('minutes', 0))
    nep = int(hb.get('episodes', len(allc)))
    print(f"HDOK minutes_de_jeu={mins:.4f} episodes={nep}")
    print(f"# dernier battement : {hb}")
    print(f"# dernier battement2 : {hb2}")
    print(f"# dernier battement3 : {hb3}")


if __name__ == '__main__':
    main()
