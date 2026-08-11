#!/usr/bin/env python3
"""probe_keira_capsules.py — COMBIEN DE LA GEOMETRIE CHAQUE VOLUME CONTIENT-IL REELLEMENT ?

Le generateur ajuste chaque volume d'obstacle avec une MOYENNE INTER-QUARTILE de la distance
perpendiculaire a l'axe de l'os. C'est une statistique de TENDANCE CENTRALE : par construction,
la moitie des sommets sont DEHORS. Pour une epaisseur de lien (« quelle est mon epaisseur ») c'est
la bonne mesure ; pour un obstacle (« ou rien ne doit entrer ») c'est la mauvaise, et un
`meshpen = 0` contre un tel volume ne dit rien de ce que l'owner voit.

Ce script mesure, pour chaque volume du fichier livre et avec EXACTEMENT la meme selection de
sommets que le generateur, la statistique actuelle (iq) et deux statistiques de COUVERTURE (p90,
p100), plus la fraction de sommets deja dehors. Aucune conclusion ecrite ici : les nombres partent
dans le rapport.
"""
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G  # noqa: E402


def perp_stats(geo, j, a_world, b_world, thr):
    _n, _w, idx = G.influence(geo, j, thr)
    if len(idx) == 0:
        return None
    ibm = geo['ibms'][j]
    pts = G.to_bone_local(ibm, geo['V'][idx])
    a = G.to_bone_local(ibm, a_world[None, :])[0]
    b = G.to_bone_local(ibm, b_world[None, :])[0]
    axis = b - a
    n = float(np.linalg.norm(axis))
    if n < 1e-6:
        return None
    u = axis / n
    rel = pts - a
    rel = rel - np.outer(rel @ u, u)
    d = np.linalg.norm(rel, axis=1)
    lo, hi = np.percentile(d, [25.0, 75.0])
    inner = d[(d >= lo) & (d <= hi)]
    if inner.size == 0:
        inner = d
    return dict(n=len(d), iq=float(inner.mean()), p90=float(np.percentile(d, 90)),
                p95=float(np.percentile(d, 95)), p100=float(d.max()))


def pick(geo, j):
    for thr in G.FIT_STEPS:
        _n, _w, sel = G.influence(geo, j, thr)
        if len(sel) >= G.FIT_MIN_VERTS:
            return thr
    for thr in reversed(G.FIT_STEPS):
        _n, _w, sel = G.influence(geo, j, thr)
        if len(sel):
            return thr
    return None


def main():
    names, parent, _ = G.load_rig(os.path.join(REPO, G.RIG_REL))
    geo = G.load_mesh(G.MODEL)
    idx_of = {n: i for i, n in enumerate(names)}
    P = geo['P']
    txt = open(os.path.join(REPO, 'recharged_assets/physics_chains.txt'), errors='ignore').read()

    print("== CAPSULES : rayon livre (iq) contre couverture reelle ==")
    print(f"   {'volume':<26}{'nv':>5} {'livre':>7} {'iq':>7} {'p90':>7} {'p95':>7} {'p100':>7}"
          f" {'dehors@livre':>13}")
    for m in re.finditer(r'^capsule (\S+) (\S+) radius=(\d+) radius2=(\d+)', txt, re.M):
        jn, pn, r1, r2 = m.group(1), m.group(2), int(m.group(3)), int(m.group(4))
        for who, rlive, other in ((jn, r1, pn), (pn, r2, jn)):
            j, o = idx_of[who], idx_of[other]
            thr = pick(geo, j)
            if thr is None:
                continue
            s = perp_stats(geo, j, P[j], P[o], thr)
            if s is None:
                continue
            _n, _w, idx = G.influence(geo, j, thr)
            ibm = geo['ibms'][j]
            pts = G.to_bone_local(ibm, geo['V'][idx])
            a = G.to_bone_local(ibm, P[j][None, :])[0]
            b = G.to_bone_local(ibm, P[o][None, :])[0]
            u = (b - a) / np.linalg.norm(b - a)
            rel = pts - a
            rel = rel - np.outer(rel @ u, u)
            d = np.linalg.norm(rel, axis=1)
            out = float((d > rlive).mean())
            print(f"   {who+'->'+other:<26}{s['n']:>5} {rlive:>7} {s['iq']:>7.0f} {s['p90']:>7.0f}"
                  f" {s['p95']:>7.0f} {s['p100']:>7.0f} {100*out:>12.0f}%")

    print()
    print("== SPHERES : rayon livre (iq autour du centroide) contre couverture reelle ==")
    print(f"   {'volume':<16}{'nv':>5} {'livre':>7} {'iq':>7} {'p90':>7} {'p95':>7} {'p100':>7}"
          f" {'dehors@livre':>13}")
    for m in re.finditer(r'^collider (\S+) radius=(\d+)', txt, re.M):
        jn, rlive = m.group(1), int(m.group(2))
        j = idx_of.get(jn)
        if j is None:
            continue
        idx, thr = None, None
        for cand in G.FIT_STEPS:
            _n, _w, i2 = G.influence(geo, j, cand)
            idx, thr = i2, cand
            if len(i2) >= G.FIT_MIN_VERTS:
                break
        pts = G.to_bone_local(geo['ibms'][j], geo['V'][idx])
        c = pts.mean(axis=0)
        d = np.linalg.norm(pts - c, axis=1)
        lo, hi = np.percentile(d, [25.0, 75.0])
        inner = d[(d >= lo) & (d <= hi)]
        out = float((d > rlive).mean())
        print(f"   {jn:<16}{len(d):>5} {rlive:>7} {inner.mean():>7.0f}"
              f" {np.percentile(d, 90):>7.0f} {np.percentile(d, 95):>7.0f} {d.max():>7.0f}"
              f" {100*out:>12.0f}%")


if __name__ == '__main__':
    main()
