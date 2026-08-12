#!/usr/bin/env python3
"""probe_capsule_cover.py — MESURER avant de decider : que vaut une capsule qui COUVRE ?

Contexte, en une phrase. `.autoport/physics_keira_gen2.py` porte depuis le 2026-08-11 la regle
« un obstacle doit CONTENIR la geometrie qu'il represente » (COVER_PCT = 95), et cette regle n'a
ete branchee que sur les SPHERES (`blob_centre_radius`, ligne 354 : `np.percentile(d, COVER_PCT)`).
Les CAPSULES sont restees sur `iq_perp_radius` (ligne 311-315), une moyenne inter-quartile, donc
une tendance CENTRALE : par construction la moitie de la surface est dehors. Mesure de
.autoport/probe_keira_capsules.py sur les volumes LIVRES :

    capsules : rayon livre == iq,  42 a 58 % des sommets DEHORS
    spheres  : rayon livre == p95,  0 a  8 % des sommets dehors

Ce script ne modifie rien. Il repond a la seule question qui decide de la FORME du correctif :
un p95 pose tel quel sur une capsule ballonne-t-il ? `iq_perp_radius` prend la distance
perpendiculaire de TOUS les sommets du joint, y compris ceux qui se projettent HORS du segment :
le pied deborde de l'axe du tibia, le buste deborde de l'axe epaule->buste. Le p95 y mesurerait
alors la longueur d'une AUTRE partie, pas une epaisseur.

Trois variantes chiffrees cote a cote, sur le MEME echantillon de sommets que le generateur :

    iq        ce qui est livre aujourd'hui : moyenne inter-quartile, tous sommets
    p95       la regle des spheres appliquee telle quelle : p95, tous sommets
    p95span   p95 restreint aux sommets qui se projettent DANS le segment (t dans [0,1]) et du
              cote de l'extremite ajustee (t <= 0.5). Ce qui deborde des bouts est couvert par la
              capsule voisine ou par la sphere du joint, pas par l'epaisseur de CE segment.

NATURE / REPERE / LECTURE QUAND LE DEFAUT EST ABSENT (SPEC 7, avant de publier un chiffre) :
  * NATURE  : une FRACTION de surface et une DISTANCE, pas une amplitude ni une frequence.
              L'owner decrit « ca passe au travers » : une geometrie qui sort d'un volume. Ca se
              mesure en % de sommets dehors et en unites de depassement.
  * REPERE  : la pose BIND du mesh skinne, en unites de jeu (4096 u = 1 m), dans l'espace bind du
              joint ajuste — le meme que le generateur. Aucune position simulee n'entre ici : on
              mesure la FORME des obstacles, pas leur mouvement.
  * LECTURE QUAND LE DEFAUT EST ABSENT : 0 % dehors. La colonne `deh@livre` est donc directement
              comparable a la cible, et sa valeur d'aujourd'hui (~50 %) EST le defaut.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G  # noqa: E402

COVER = G.COVER_PCT
RIG = os.path.join(REPO, 'recharged_assets/hd_anim/keira-hd-k2e.json')
GLB = os.path.join(REPO, 'decompiler_out/jak2/levels/lintcstb/keira-highres-lod0.glb')
CHAINS = os.path.join(REPO, 'recharged_assets/physics_chains.txt')


def sample(geo, j):
    """Le MEME echantillon de sommets que `fit_radius` : premier seuil de l'echelle qui atteint
    FIT_MIN_VERTS, sinon le plus lache qui ait au moins un sommet."""
    for thr in G.FIT_STEPS:
        _n, _w, idx = G.influence(geo, j, thr)
        if len(idx) >= G.FIT_MIN_VERTS:
            return idx, thr
    for thr in reversed(G.FIT_STEPS):
        _n, _w, idx = G.influence(geo, j, thr)
        if len(idx) > 0:
            return idx, thr
    return np.array([], dtype=int), None


def perp_and_t(geo, j, a_world, b_world, idx):
    """(distance perpendiculaire a l'axe a->b, parametre de projection t) dans l'espace bind de j."""
    ibm = geo['ibms'][j]
    pts = G.to_bone_local(ibm, geo['V'][idx])
    a = G.to_bone_local(ibm, a_world[None, :])[0]
    b = G.to_bone_local(ibm, b_world[None, :])[0]
    axis = b - a
    n = float(np.linalg.norm(axis))
    if n < 1e-6:
        return None, None
    u = axis / n
    rel = pts - a
    t = (rel @ u) / n
    perp = np.linalg.norm(rel - np.outer(rel @ u, u), axis=1)
    return perp, t


def variants(perp, t):
    lo, hi = np.percentile(perp, [G.IQ_LO, G.IQ_HI])
    inner = perp[(perp >= lo) & (perp <= hi)]
    if inner.size == 0:
        inner = perp
    iq = float(inner.mean())
    p95 = float(np.percentile(perp, COVER))
    m = (t >= 0.0) & (t <= 1.0)
    used = 'segment'
    if m.sum() < G.FIT_MIN_VERTS:
        # AUCUNE geometrie de ce joint ne se projette DANS le segment : la distance
        # perpendiculaire y mesure la longueur d'une AUTRE partie (le pied hors de l'axe du
        # tibia, le buste hors de l'axe epaule->buste), pas une epaisseur. On ne ballonne pas
        # sur une mesure qui ne mesure pas ce qu'on croit : la valeur livree ne change pas.
        return iq, p95, iq, 0, 'hors-axe'
    p95span = float(np.percentile(perp[m], COVER))
    return iq, p95, p95span, int(m.sum()), used


def main():
    names, parent, _d = G.load_rig(RIG)
    geo = G.load_mesh(G.MODEL)
    idx_of = {n: i for i, n in enumerate(names)}
    P = geo['P']

    caps = []
    for raw in open(CHAINS, errors='ignore'):
        p = raw.split()
        if len(p) >= 5 and p[0] == 'capsule':
            caps.append((p[1], p[2], int(p[3].split('=')[1]), int(p[4].split('=')[1])))

    print("== CAPSULES : le rayon LIVRE contre les deux formes de couverture ==")
    print("   `deh@X` = fraction des sommets de CE joint hors d'un volume de rayon X.")
    print(f"   {'extremite de capsule':<26}{'nv':>5}{'livre':>7}{'iq':>6}{'p95':>7}{'p95span':>9}"
          f"{'band':>9}{'deh@livre':>11}{'deh@span':>10}")
    out = {}
    for jn, pn, r1, r2 in caps:
        j, p = idx_of.get(jn), idx_of.get(pn)
        if j is None or p is None:
            continue
        for (jj, pp, rlive, label) in ((j, p, r1, f'{jn}->{pn}'), (p, j, r2, f'{pn}->{jn}')):
            idx, _thr = sample(geo, jj)
            if len(idx) == 0:
                continue
            perp, t = perp_and_t(geo, jj, P[jj], P[pp], idx)
            if perp is None:
                continue
            iq, p95, p95span, nband, used = variants(perp, t)
            out[label] = (rlive, iq, p95, p95span)
            print(f"   {label:<26}{len(idx):>5}{rlive:>7}{iq:>6.0f}{p95:>7.0f}{p95span:>9.0f}"
                  f"{used:>9}{100*float((perp > rlive).mean()):>10.0f}%"
                  f"{100*float((perp > p95span).mean()):>9.0f}%")

    print()
    print("== LES QUATRE SITES QUE L'OWNER DECRIT ==")
    for label in ('chest->main', 'main->chest', 'hips->main',
                  'Lknee->Lankle', 'Lankle->Lknee', 'Rknee->Rankle', 'Rankle->Rknee'):
        if label in out:
            rlive, iq, p95, p95span = out[label]
            print(f"   {label:<20} livre={rlive:<6} p95span={p95span:<7.0f} "
                  f"gain={p95span - rlive:+.0f} u ({(p95span - rlive) / 4096:+.3f} m)")
    return out


if __name__ == '__main__':
    main()
