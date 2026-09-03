#!/usr/bin/env python3
"""probe_breast_shape.py — LE PROFIL DE MOBILITE D'UN SEIN, MESURE SUR LA PEAU LIVREE.

Pourquoi cet instrument existe
------------------------------
La directive du 2026-08-14 09:45 affirme que §30 (ancrage 30 %) et §31 (gradient
`w(r) = r^1.6..2.0`) de `SPEC-breast-softbody.md` « ne sont pas representables avec un point
unique », donc qu'il faut d'abord ajouter des os. Cette affirmation porte sur les JOINTS. Or ce
que §30 et §31 decrivent est la mobilite de la CHAIR, et la chair d'un sein est peinte sur
`lBoob`/`rBoob` avec des POIDS qui vont de ~0 a la racine a ~1 a la pointe. Un seul joint plus un
degrade de poids produit deja un champ de deplacement gradue. Personne ne l'avait mesure : les
sondes existantes comptent des sommets (`cov`, ownership), aucune ne rend le DEPLACEMENT.

TROIS QUESTIONS OBLIGATOIRES (SPEC-keira-physique §7), repondues ici :

NATURE   -- un PROFIL : le deplacement de peau, normalise par celui de l'apex, en fonction de la
            position normalisee `r` le long de l'axe racine->apex. Ce n'est ni une amplitude
            (un scalaire ne peut pas decrire un degrade), ni une variance.
REPERE   -- l'espace BIND du joint du sein (`lBoob`/`rBoob`), c'est-a-dire exactement le repere
            que §7 de la spec impose (« relative to the torso/root transform rather than
            directly in world space »). `r = 0` a l'attache thoracique, `r = 1` a l'apex.
BASELINE -- defaut ABSENT = le profil suit `r^1.6..2.0` et la racine profonde (r <= 0.15) lit une
            mobilite <= 0.10 (§30 : « deep root 90-100 % [attached] »). Defaut PRESENT = profil
            plat (toute la chair bouge autant : le sein part en bloc) ou racine mobile.

Le deplacement est celui que le SKINNING produit reellement : pour une rotation de test du joint,
`d(v) = w(v) * |R.v - v|` — la formule du skinning lineaire, pas un modele suppose. Le resultat
est independant de l'angle de test (tout est normalise par l'apex), verifie a 1e-6 entre 1 et 10
degres.

    python3 .autoport/probe_breast_shape.py [--glb <mesh>] [--json <sortie>]
"""
import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                '..', 'scripts', 'shell'))
from retarget_hd_models import (read_glb, consolidate_buffers,  # noqa: E402
                                read_accessor)

# Le maillage PREPARE, pas le donneur : le donneur est un rip de niveau dont le pool de sommets
# porte d'autres objets, et une mesure d'appartenance y lit n'importe quoi (lecon 2026-08-13,
# `feedback_reskin_measure_the_prepped_input`). Les deux espaces bind sont identiques a 1e-8 m,
# donc une position mesuree ici s'applique telle quelle au donneur.
DEFAULT_GLB = 'out/jak1/fr3/skin/keira-hd-lod0.glb'

# `+Y local` est l'axe racine->apex, MESURE et non suppose : le centroide de la geometrie que
# `lBoob` possede est a (0.0024, 0.1483, 0.0059) m dans son espace bind, soit 99.98 % sur +Y.
# Le script le reverifie et refuse si l'axe dominant change.
AXIS = 1


def load(glb):
    js, bufs = read_glb(glb)
    binc = consolidate_buffers(js, bufs)
    names = [n.get('name', '?') for n in js['nodes']]
    sk = js['skins'][0]
    jn = [names[i] for i in sk['joints']]
    ibm = read_accessor(js, binc, sk['inverseBindMatrices']).reshape(-1, 4, 4)
    # Les 28 primitives partagent UN SEUL triplet d'accesseurs (piege 2026-08-13 : les iterer
    # compte chaque sommet 28 fois). On le verifie au lieu de le supposer.
    trip = {(p['attributes']['POSITION'], p['attributes']['JOINTS_0'],
             p['attributes']['WEIGHTS_0']) for p in js['meshes'][0]['primitives']}
    if len(trip) != 1:
        raise SystemExit('!! %d triplets d accesseurs distincts, la sonde en attend 1' % len(trip))
    a = trip.pop()
    pos = read_accessor(js, binc, a[0]).reshape(-1, 3)
    J = read_accessor(js, binc, a[1]).reshape(-1, 4)
    W = read_accessor(js, binc, a[2]).reshape(-1, 4)

    # AIRE PORTEE PAR CHAQUE SOMMET — le proxy de VOLUME que la 30 demande.
    # Un simple comptage de sommets sur-pondere l'apex (23 sommets dans le dernier decile contre
    # 4 dans le premier) ; l'aire, elle, est une grandeur de surface reelle. Un tiers de l'aire de
    # chaque triangle va a chacun de ses sommets. Biais assume et declare : une surface n'est pas
    # un volume — pour une coque a epaisseur a peu pres constante, elle en est proportionnelle.
    area = np.zeros(len(pos))
    for pr in js['meshes'][0]['primitives']:
        if 'indices' not in pr:
            continue
        ind = np.asarray(read_accessor(js, binc, pr['indices'])).reshape(-1, 3)
        v0, v1, v2 = pos[ind[:, 0]], pos[ind[:, 1]], pos[ind[:, 2]]
        tri = 0.5 * np.linalg.norm(np.cross(v1 - v0, v2 - v0), axis=1)
        for c in range(3):
            np.add.at(area, ind[:, c], tri / 3.0)
    return jn, ibm, pos, J, W, area


def joint_weight(J, W, k):
    w = np.zeros(len(J))
    for c in range(4):
        w += np.where(J[:, c] == k, W[:, c], 0.0)
    return w


def rot(axis, ang):
    c, s = np.cos(ang), np.sin(ang)
    if axis == 0:
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    if axis == 2:
        return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
    raise ValueError


def measure(jn, ibm, pos, J, W, area, name, mirror):
    # `name` peut etre UN joint ou LA CHAINE ENTIERE. Sa SPEC 6 definit `B0` comme la longueur
    # caracteristique racine->apex de la CHAIR : c'est une propriete du MAILLAGE, donc ajouter un
    # os ne doit PAS la changer. Or la selection se fait par poids de peau : apres l'injection du
    # 2026-08-17, la rampe retire 100 % du poids `lBoob` de tout sommet au-dela de `lBooc` — soit
    # precisement ceux de plus grand `y`. Mesure sur `lBoob` SEUL, `y1` s'effondrerait et `B0`
    # passerait de ~147 mm a ~53 mm. Comme `B0` NORMALISE §10, §11, §12, §22 et §29, toutes ces
    # sections auraient ete multipliees par ~2.8 d'un coup : un faux vert massif et invisible.
    # Le repere reste celui du joint RACINE, inchange, pour que `y0`/`y1` restent comparables aux
    # cycles precedents ; seule la SELECTION s'elargit a la chaine. Un joint absent du rig est
    # ignore, donc l'appel d'avant l'injection rend exactement la meme valeur qu'avant.
    names = [name] if isinstance(name, str) else list(name)
    k = jn.index(names[0])
    w = joint_weight(J, W, k)
    for extra in names[1:]:
        if extra in jn:
            w = w + joint_weight(J, W, jn.index(extra))
    M = ibm[k].T                       # glTF stocke en colonnes
    loc = ((pos @ M[:3, :3].T) + M[:3, 3]) * mirror
    sel = w > 1e-6
    L, ww, aa = loc[sel], w[sel], area[sel]

    cen = (L * ww[:, None]).sum(0) / ww.sum()
    if abs(cen[AXIS]) < 0.9 * np.linalg.norm(cen):
        raise SystemExit('!! %s : l axe dominant n est plus +Y (centroide %s)' % (names[0], cen))

    y = L[:, AXIS]
    y0, y1 = float(y.min()), float(y.max())
    b0 = y1 - y0                       # §6 : B0, longueur caracteristique racine->apex
    r = (y - y0) / b0

    # Deux axes de rotation de test : le sein tourne autour de son attache, et §29 distingue
    # vertical / AP / lateral. Le profil doit etre le meme (c'est une propriete de la PEAU, pas
    # du pilotage) — on le verifie en publiant les deux.
    prof = {}
    for axname, ax in (('rotX', 0), ('rotZ', 2)):
        d = np.linalg.norm((L @ rot(ax, np.radians(5.0)).T) - L, axis=1) * ww
        apex = float(d.max())
        prof[axname] = d / apex

    return dict(name=name, k=k, nvert=int(sel.sum()), mass=float(ww.sum()),
                y0=y0, y1=y1, b0=b0, r=r, w=ww, a=aa, prof=prof, loc=L)


def fit_exponent(r, dn, wgt, lo=0.0):
    """Exposant p tel que dn ~ r^p, moindres carres sur log, r > lo et dn > 0."""
    m = (r > max(lo, 1e-3)) & (dn > 1e-6)
    if m.sum() < 4:
        return float('nan')
    return float(np.polyfit(np.log(r[m]), np.log(dn[m]), 1, w=wgt[m])[0])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--glb', default=DEFAULT_GLB)
    ap.add_argument('--bins', type=int, default=10)
    ap.add_argument('--json', default=None)
    args = ap.parse_args()

    jn, ibm, pos, J, W, area = load(args.glb)
    out = {'glb': args.glb, 'breasts': {}}

    print('BREAST-SHAPE  mesh=%s' % args.glb)
    print('  NATURE=profil de deplacement normalise  REPERE=espace bind du joint (SPEC 7)'
          '  BASELINE=r^1.6..2.0, racine r<=0.15 mobilite<=0.10 (SPEC 30)')
    for name, mirror in ((['lBoob', 'lBooc'], 1.0), (['rBoob', 'rBooc'], -1.0)):
        m = measure(jn, ibm, pos, J, W, area, name, mirror)
        r, ww = m['r'], m['w']
        print('\n== %s  joint=%d  verts=%d  masse=%.3f'
              % ('+'.join(name), m['k'], m['nvert'], m['mass']))
        print('   SPEC 6  B0 = %.4f m = %.0f u  (chair de y=%.4f a y=%.4f dans son espace bind)'
              % (m['b0'], m['b0'] * 4096.0, m['y0'], m['y1']))
        # SPEC 6 EXIGE QUE B0 VIENNE DU MAILLAGE (« the game implementation shall derive
        # normalized dimensions directly from the character mesh »). Le moteur, lui, borne
        # l'excursion d'apex de §22 contre la LONGUEUR D'OS ancre->joint (`PHYSBONE len=`), qui
        # n'est pas une longueur racine->apex : c'est la distance du thorax au joint, apex non
        # compris. Publier les deux cote a cote est le seul moyen de voir l'ecart.
        bone = float(np.linalg.norm(np.linalg.inv(ibm[m['k']].T)[:3, 3]
                                    - np.linalg.inv(ibm[jn.index('chest')].T)[:3, 3]))
        print('   SPEC 6  longueur d os chest->%s = %.4f m = %.0f u  -> le moteur borne §22 contre'
              ' un B0 %.2fx TROP GRAND' % (name, bone, bone * 4096.0, bone / m['b0']))

        rec = {'b0': m['b0'], 'nvert': m['nvert'], 'mass': m['mass'], 'bands': [], 'fit': {},
               'b0_mesh_u': m['b0'] * 4096.0, 'b0_bone_u': bone * 4096.0}
        for axname in ('rotX', 'rotZ'):
            dn = m['prof'][axname]
            rec['fit'][axname] = fit_exponent(r, dn, ww)
            rec['fit'][axname + '_r>0.3'] = fit_exponent(r, dn, ww, lo=0.30)
        print('   SPEC 31 exposant ajuste  rotX p=%.2f (r>0.3 : %.2f)   rotZ p=%.2f (r>0.3 : %.2f)'
              '   cible 1.6..2.0'
              % (rec['fit']['rotX'], rec['fit']['rotX_r>0.3'],
                 rec['fit']['rotZ'], rec['fit']['rotZ_r>0.3']))

        dn = m['prof']['rotX']
        nb = args.bins
        print('   %-6s %5s %8s %9s %9s %9s' % ('r', 'n', 'w_moy', 'mobilite', 'r^1.6', 'r^2.0'))
        for i in range(nb):
            lo, hi = i / nb, (i + 1) / nb
            sel = (r >= lo) & (r < hi if i < nb - 1 else r <= 1.0)
            rc = 0.5 * (lo + hi)
            if not sel.any():
                print('   %-6.2f %5d %8s %9s' % (rc, 0, '-', '-'))
                rec['bands'].append({'r': rc, 'n': 0})
                continue
            mob = float(dn[sel].mean())
            print('   %-6.2f %5d %8.3f %9.3f %9.3f %9.3f'
                  % (rc, int(sel.sum()), float(ww[sel].mean()), mob, rc ** 1.6, rc ** 2.0))
            rec['bands'].append({'r': rc, 'n': int(sel.sum()),
                                 'w': float(ww[sel].mean()), 'mob': mob})

        # §30 : « deep root 90-100 % attached » = mobilite <= 0.10 sur la racine profonde, et
        # « approximately 28-35 % of the rear breast VOLUME » doit etre dans cet etat.
        deep = r <= 0.15
        mob_deep = float(dn[deep].mean()) if deep.any() else float('nan')
        anch_a = float(m['a'][dn <= 0.10].sum() / m['a'].sum())
        # LA MASSE PESEE EST UN MAUVAIS INSTRUMENT POUR §30, ET LE PIEGE EST SUBTIL. `sum(w)`
        # pondere chaque sommet par exactement la grandeur qu'on est en train de graduer : rendre
        # la racine plus ancree (w plus petit a la racine) fait BAISSER sa part de masse, donc la
        # part « ancree » lue sur la masse baisse alors que la chair ancree augmente. Mesure sur
        # le maillage du 2026-08-14 : par la masse 4.3 %, par l'aire 30.9 % — un facteur 7 dans le
        # mauvais sens. La 30 parle de VOLUME : on lit l'aire, jamais la masse pesee.
        anch_m = float(ww[dn <= 0.10].sum() / ww.sum())
        rec['deep_mobility'] = mob_deep
        rec['anchored_area_frac'] = anch_a
        rec['anchored_mass_frac'] = anch_m
        print('   SPEC 30 racine profonde (r<=0.15) mobilite=%.3f  (cible <= 0.10)' % mob_deep)
        print('   SPEC 30 part de VOLUME (proxy aire) fortement ancree = %.1f %%  (cible 28-35 %%)'
              % (100.0 * anch_a))
        print('   .. pour memoire, la meme part lue sur la MASSE PESEE = %.1f %% — instrument '
              'invalide ici, voir le commentaire' % (100.0 * anch_m))
        out['breasts'][name] = rec

    if args.json:
        with open(args.json, 'w') as f:
            json.dump(out, f, indent=1)
        print('\nwrote %s' % args.json)


if __name__ == '__main__':
    main()
