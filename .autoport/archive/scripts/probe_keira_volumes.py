#!/usr/bin/env python3
"""probe_keira_volumes.py — MESURER, avant de decider.

Ce script ne genere rien et ne modifie rien. Il repond, avec des nombres tires du mesh skinne et du
rig, aux trois questions ouvertes par le retour de l'owner du 2026-08-11 21:15 :

  1. `pant-calf` — ou est REELLEMENT la geometrie de LpantFlap/RpantFlap ? Le moteur la re-assied
     18101 fois par course sur `porteur + direction_d_os x rayon`, une position INVENTEE ; si le
     centroide mesure de ses sommets tombe ailleurs, la re-assise est la cause du « pantacourt qui
     s'arrete aux genoux ».
  2. `goggles-chest` — quelle est la vraie etendue du sein ? Le collider vaut 183 u autour d'un
     centroide a 662 u du joint. Si les sommets s'etendent bien au-dela de 183 u, les lunettes
     passent DANS le sein visible tout en restant hors du volume declare, et meshpen=0 est un vrai
     zero sur un mauvais volume.
  3. `straps-elastic` — quel joint porte l'elastique orange du bas du crop top, et quel volume le
     couvre aujourd'hui ?

Sortie : un tableau. Aucune conclusion n'est ecrite ici — les nombres vont dans le rapport.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G  # noqa: E402

UNITS = G.UNITS


def spread(pts, c):
    d = np.linalg.norm(pts - c, axis=1)
    return dict(n=len(d), mean=float(d.mean()), p50=float(np.percentile(d, 50)),
                p75=float(np.percentile(d, 75)), p90=float(np.percentile(d, 90)),
                p100=float(d.max()),
                iq=float(d[(d >= np.percentile(d, 25)) & (d <= np.percentile(d, 75))].mean()))


def main():
    names, parent, _ = G.load_rig(os.path.join(REPO, G.RIG_REL))
    geo = G.load_mesh(G.MODEL)
    idx_of = {n: i for i, n in enumerate(names)}
    P = geo['P']

    print("== 1. LES JOINTS DE CHAINE : OU EST LEUR GEOMETRIE, ET OU EST LEUR JOINT ==")
    print("   dist(joint,porteur) = longueur d'os telle que le RIG la donne (bind).")
    print("   centroide = moyenne des sommets que le joint possede, en MONDE bind.")
    print("   |c-joint| = de combien la geometrie est decalee de son propre joint.")
    print("   |c-porteur| = ou la geometrie est reellement, vue du porteur.")
    print(f"   {'joint':<16}{'porteur':<12}{'nv':>4} {'bone_u':>9} {'|c-j|':>9} {'|c-p|':>9}"
          f" {'iq':>7} {'p90':>7} {'p100':>7}")
    interest = ['LpantFlap', 'RpantFlap', 'lBoob', 'rBoob', 'lKneeFlap', 'rKneeFlap',
                'lBotStrap', 'lBotStrap2', 'rBotStrap', 'rBotStrap2',
                'lTopStrap', 'lTopStrap2', 'rTopStrap', 'rTopStrap2',
                'gogglesBase', 'gogglesMid', 'lEara', 'lEarb', 'Lbanga', 'Lbangb', 'Lbangc',
                'LtoeStrap', 'Lanklestrap', 'LfootFlaps', 'RfootFlaps']
    for jn in interest:
        j = idx_of.get(jn)
        if j is None:
            print(f"   {jn:<16}ABSENT DU RIG")
            continue
        p = parent[j]
        pn = names[p] if p >= 0 else '-'
        bone = float(np.linalg.norm(P[j] - P[p])) if p >= 0 else 0.0
        best = None
        for thr in (0.5, 0.25, 0.05):
            _n, _w, sel = G.influence(geo, j, thr)
            if len(sel) >= 8:
                best = (thr, sel)
                break
        if best is None:
            for thr in (0.05, 0.25, 0.5):
                _n, _w, sel = G.influence(geo, j, thr)
                if len(sel):
                    best = (thr, sel)
                    break
        if best is None:
            print(f"   {jn:<16}{pn:<12}{0:>4} {bone:>9.0f}   (aucun sommet)")
            continue
        thr, sel = best
        pts = geo['V'][sel]
        c = pts.mean(axis=0)
        s = spread(pts, c)
        dcj = float(np.linalg.norm(c - P[j]))
        dcp = float(np.linalg.norm(c - P[p])) if p >= 0 else 0.0
        print(f"   {jn:<16}{pn:<12}{s['n']:>4} {bone:>9.0f} {dcj:>9.0f} {dcp:>9.0f}"
              f" {s['iq']:>7.0f} {s['p90']:>7.0f} {s['p100']:>7.0f}   @w>{thr}")

    print()
    print("== 2. LA GEOMETRIE DU SEIN, PAR SEUIL DE POIDS ==")
    print("   le collider actuel est ajuste a w>0.25 (34 sommets) : rayon iq=183.")
    for jn in ('lBoob', 'rBoob'):
        j = idx_of[jn]
        for thr in (0.5, 0.25, 0.05, 0.01):
            _n, _w, sel = G.influence(geo, j, thr)
            if len(sel) == 0:
                continue
            pts = geo['V'][sel]
            c = pts.mean(axis=0)
            s = spread(pts, c)
            print(f"   {jn} w>{thr:<5} nv={s['n']:>4} |c-joint|={np.linalg.norm(c-P[j]):>6.0f}"
                  f"  iq={s['iq']:>6.0f} p50={s['p50']:>6.0f} p90={s['p90']:>6.0f}"
                  f" max={s['p100']:>6.0f}")

    print()
    print("== 3. QUI PORTE LE BAS DU CROP TOP / L'ELASTIQUE ? ==")
    print("   Pour chaque joint du TRONC, l'etendue verticale (axe bind Y) des sommets qu'il")
    print("   possede et leur rayon horizontal max : l'ourlet d'un crop top est un ANNEAU, donc un")
    print("   grand rayon horizontal a une hauteur precise, la ou la capsule du tronc est fine.")
    for jn in ('chest', 'main', 'hips', 'neck'):
        j = idx_of.get(jn)
        if j is None:
            continue
        for thr in (0.5, 0.25, 0.05):
            _n, _w, sel = G.influence(geo, j, thr)
            if len(sel) < 8:
                continue
            pts = geo['V'][sel]
            c = pts.mean(axis=0)
            s = spread(pts, c)
            print(f"   {jn:<7} w>{thr:<5} nv={s['n']:>5} |c-joint|={np.linalg.norm(c-P[j]):>6.0f}"
                  f"  iq={s['iq']:>6.0f} p90={s['p90']:>6.0f} max={s['p100']:>6.0f}"
                  f"  joint=({P[j][0]:.0f},{P[j][1]:.0f},{P[j][2]:.0f})")
            break

    print()
    print("== 4. LES CAPSULES DE JAMBE CONTRE LA GEOMETRIE DU PANTACOURT ==")
    print("   distance du centroide du pan a l'AXE de la capsule du mollet, et le rayon de la")
    print("   capsule a cet endroit : si la distance est INFERIEURE au rayon, le pan est DANS la")
    print("   jambe des la pose bind, et aucun solveur ne l'en sortira.")
    for flap, knee, ankle, r_knee, r_ankle in (('LpantFlap', 'Lknee', 'Lankle', 329.0, 411.0),
                                               ('RpantFlap', 'Rknee', 'Rankle', 326.0, 398.0)):
        j = idx_of.get(flap)
        if j is None:
            continue
        for thr in (0.5, 0.25, 0.05):
            _n, _w, sel = G.influence(geo, j, thr)
            if len(sel) >= 8:
                break
        pts = geo['V'][sel]
        c = pts.mean(axis=0)
        a, b = P[idx_of[knee]], P[idx_of[ankle]]
        ab = b - a
        t = float(np.clip(np.dot(c - a, ab) / np.dot(ab, ab), 0.0, 1.0))
        foot = a + t * ab
        d = float(np.linalg.norm(c - foot))
        rr = r_knee + (r_ankle - r_knee) * t
        print(f"   {flap:<10} centroide a t={t:.2f} le long de {knee}->{ankle},"
              f" distance a l'axe = {d:.0f} u, rayon de capsule la = {rr:.0f} u"
              f"  -> {'DEDANS' if d < rr else 'dehors'}")
        # et le joint lui-meme ?
        dj = float(np.linalg.norm(P[j] - a))
        print(f"              le JOINT {flap} est a {dj:.0f} u de {knee}"
              f" ({dj/UNITS:.2f} m) — pose bind")


if __name__ == '__main__':
    main()
