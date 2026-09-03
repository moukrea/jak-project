#!/usr/bin/env python3
"""derive_c24_breast_nodes.py — OU POSER LES DEUX MAILLONS LIBRES DE LA POITRINE.

Phase Grecharged-secondary-motion, branche physics-keira-clean, KEIRA / POITRINE SEULE.
DIRECTIVES vb249967379

RIEN N'EST CHOISI ICI. Les deux positions sortent de lignes de `SPEC-breast-softbody.md` :

  30 « Root Attachment » partitionne l'organe en cinq bandes de `r` et dit qui tient la chair
      dans chacune : Deep root 90-100 % et Rear/intermediate 55-85 % sont tenues par le THORAX,
      Mid-volume 25-55 %, Distal 5-30 % et Apex ~0 sont laissees a la chaine. La FRONTIERE que la
      spec ecrit entre le domaine du maillon proximal et celui du maillon distal est donc
      r = 0.625.
  31 « Root-to-Apex Shape Gradient » definit `r` : « r = 0 at chest attachment and r = 1 at
      distal/apex region » — la CHAIR, pas le rig.

D'ou les deux regles de placement, une par maillon :

  MAILLON PROXIMAL : mediane de MASSE de la bande Mid-volume [0.375, 0.625], c'est-a-dire au
      milieu de la chair qu'il doit piloter. C'est la derivation deja employee au cycle 23 pour la
      racine de chaine (« mediane de masse de la chair arriere ») — reutilisee, pas reinventee.
  MAILLON DISTAL : la position pour laquelle la FRONTIERE DE POSSESSION entre les deux maillons
      tombe exactement sur r = 0.625, c'est-a-dire pour laquelle le maillon distal est majoritaire
      sur EXACTEMENT la chair que la 30 lui assigne (Distal + Apex) et pas au-dela.
      Possession = `tgt(r) * q(r) = 0.5` ou `tgt = 1 - ancrage` (30) et `q` est la partition de la
      31 dans la coordonnee reparametree `u = r^grad`.

POURQUOI CE N'EST PAS CIRCULAIRE : avec `axis=flesh`, `r` est une propriete de la CHAIR le long de
l'axe de l'organe. Deplacer un joint SUR CET AXE ne change ni `r`, ni la distribution de `r`, ni
l'exposant `p` que la regle en derive. Les entrees de ce calcul sont donc invariantes sous
l'operation qu'il commande. (Verifie par le banc : `probe_c24_distal_ownership.py`.)

SORTIE : les quatre lignes `reroot` a coller dans `recharged_assets/keira-hd-inject-joints.txt`,
en metres, dans le repere du spec d'injection.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'scripts', 'shell'))

import physics_c6_volumes as c6                                        # noqa: E402
import physics_keira_gen2 as G                                         # noqa: E402
import physics_c7_reskin as RS                                         # noqa: E402

SHIPPED = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
# LE DOMAINE DOIT ETRE CELUI QUE LA REGLE VOIT, PAS CELUI DU MESH LIVRE. `anchor30` s'applique a la
# sortie des regles `transfer` qui la precedent dans `physics_reskin.txt` ; le mesh LIVRE est la
# sortie d'`anchor30` lui-meme, dont le nuage differe (77 contre 85) et dont l'exposant derive
# differe donc aussi (1.292 contre 1.175). On rejoue ici les regles amont sur l'ENTREE de la
# cuisson, et rien d'autre : c'est le meme code, la meme entree, le meme domaine.
SPEC = 'recharged_assets/keira-hd-inject-joints.txt'
# 30 : la frontiere Mid-volume / Distal. C'est une ligne de la spec, pas un seuil choisi.
R_MID_DISTAL = 0.625
R_MID_LO = 0.375
GATE, ROOT, STRONG, FRAC, GRAD = 0.05, 0.95, 0.55, 0.30, 2.00
CHAINS = (('chestL', 'lBoob', 'lBooc'), ('chestR', 'rBoob', 'rBooc'))


def _upstream_of_anchor30(inp, tmp='/tmp/c24/derive-upstream.glb'):
    """Rejoue les regles keira-hd qui PRECEDENT `anchor30`, pour retrouver son domaine exact."""
    from retarget_hd_models import read_glb, consolidate_buffers
    rules = [r for r in RS.load_cfg().get('keira-hd', []) if r['kind'] != 'anchor30']
    js, bufs = read_glb(inp)
    binc = consolidate_buffers(js, bufs)
    RS.apply_model(js, binc, rules, verbose=False)
    binc = RS.gc_glb(js, binc)
    RS.write_glb(tmp, js, binc)
    return tmp


def main():
    inp = sys.argv[1] if len(sys.argv) > 1 else '/tmp/c24/reskin-input.glb'
    src = _upstream_of_anchor30(inp) if os.path.exists(inp) else SHIPPED
    geo = c6.load_geometry(G.MODEL, glb=src)
    names, P, V, J, W = geo['names'], geo['P'], geo['V'], geo['J'], geo['W']
    idx = {n: i for i, n in enumerate(names)}

    spec = {}
    for ln in open(SPEC):
        f = ln.split()
        if len(f) == 6 and f[0] in ('chestL', 'chestR'):
            spec[f[2]] = np.array([float(x) for x in f[3:6]])
        if len(f) == 7 and f[0] == 'reroot':
            spec[f[2]] = np.array([float(x) for x in f[4:7]])

    print('DERIVATION DES DEUX MAILLONS LIBRES DE LA POITRINE — cycle 24')
    print('r = 0 attache thoracique, r = 1 apex (31) · frontiere de domaine r = 0.625 (30)')
    print('entree de la cuisson : %s   (regles amont rejouees : %s)\n' % (inp, src))
    out = []
    for tag, jb, jc in CHAINS:
        grp = [idx[jb], idx[jc]]
        per = []
        for g in grp:
            w = np.zeros(len(W))
            for c in range(J.shape[1]):
                w += np.where(J[:, c] == g, W[:, c], 0.0)
            per.append(w)
        ws = per[0] + per[1]
        vi = np.flatnonzero(ws > GATE)
        pts = np.asarray([P[g] for g in grp], dtype=float)
        ax = pts[1] - pts[0]
        blen = float(np.linalg.norm(ax))
        ax = ax / blen
        q = (V[vi] - pts[0]) @ ax
        qlo, qhi = float(q.min()), float(q.max())
        r = (q - qlo) / (qhi - qlo)
        wm = ws[vi]

        # `p` EXACTEMENT COMME LA REGLE LE DERIVE — meme fonction, pas une copie.
        plo, phi = RS._spec30_p_range(ROOT)
        cand = np.linspace(plo, phi, 2001)
        fr = np.array([float((ROOT * np.power(1.0 - r, pc) >= STRONG).mean()) for pc in cand])
        p = float(cand[int(np.argmin(np.abs(fr - FRAC)))])

        m1 = (r >= R_MID_LO) & (r < R_MID_DISTAL)
        o = np.argsort(r[m1])
        cw = np.cumsum(wm[m1][o])
        rp = float(r[m1][o][np.searchsorted(cw, cw[-1] / 2.0)])

        # frontiere de possession sur r = 0.625 :  tgt * q = 0.5  avec  q = (r^g - rp^g)/(rd^g - rp^g)
        tgt = 1.0 - ROOT * (1.0 - R_MID_DISTAL) ** p
        need = 0.5 / tgt                                     # la part que le distal doit y avoir
        up, ub = rp ** GRAD, R_MID_DISTAL ** GRAD
        if not (0.0 < need < 1.0):
            print('  !! %s: la chair a r=0.625 est trop ancree (tgt=%.3f) pour qu\'un maillon y soit'
                  ' majoritaire — aucune position ne le permet' % (tag, tgt))
            continue
        ud = up + (ub - up) / need
        rd = float(ud ** (1.0 / GRAD))

        # mediane de masse de la chair distale, publiee comme l'ALTERNATIVE mesuree
        m2 = (r >= R_MID_DISTAL)
        o2 = np.argsort(r[m2])
        cw2 = np.cumsum(wm[m2][o2])
        rd_med = float(r[m2][o2][np.searchsorted(cw2, cw2[-1] / 2.0)])

        rb0 = float((0.0 - qlo) / (qhi - qlo))
        rc0 = float((blen - qlo) / (qhi - qlo))
        print('=== %s   nuage n=%d   os %s->%s = %.1f u   p derive = %.3f' % (tag, len(vi), jb, jc,
                                                                              blen, p))
        print('    chair : r=0 a %.4f m derriere %s, r=1 a %.4f m devant %s'
              % (-qlo / 4096.0, jb, (qhi - blen) / 4096.0, jc))
        print('    positions ACTUELLES        %s r=%.3f   %s r=%.3f' % (jb, rb0, jc, rc0))
        print('    Mid-volume [%.3f,%.3f) : %d sommets, masse %.3f -> mediane de masse r=%.3f'
              % (R_MID_LO, R_MID_DISTAL, int(m1.sum()), float(wm[m1].sum()), rp))
        print('    ancrage a r=0.625 : %.3f  -> chair libre tgt=%.3f  -> le distal doit y porter'
              ' q=%.3f' % (1.0 - tgt, tgt, need))
        print('    -> %s r=%.3f (DERIVE : frontiere de possession sur r=0.625)' % (jc, rd))
        print('       [alternative mesuree, NON retenue : mediane de masse de la chair distale'
              ' r=%.3f — elle place la frontiere plus haut, donc le distal perd la bande'
              ' [0.625, %.3f] que la 30 lui assigne]' % (rd_med, rd_med))
        for jn, rv in ((jb, rp), (jc, rd)):
            t = (qlo + rv * (qhi - qlo)) / blen
            pos = spec[jb] + t * (spec[jc] - spec[jb])
            anchor = 'chest' if jn == jb else jb
            out.append('reroot  %-9s %-8s %-8s %12.6f %12.6f %12.6f'
                       % (tag, jn, anchor, pos[0], pos[1], pos[2]))
        print()
    print('LES QUATRE LIGNES A POSER (metres, repere du spec d\'injection) :')
    print('\n'.join(out))
    return 0


if __name__ == '__main__':
    sys.exit(main())
