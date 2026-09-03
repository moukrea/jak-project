#!/usr/bin/env python3
"""probe_head_volume_selfinclusion.py — LE VOLUME DE TETE EST-IL AJUSTE SUR LES CHEVEUX
QU'IL DOIT REPOUSSER ?

Question, posee par une mesure de la salle et non par une intuition : `backhair` et `lbang`
sont en contact 17893 frames sur 17893 — 100 % — quand `earL` en compte 25 et `lmidhair` 609.
Une chaine qui ne quitte JAMAIS un volume n'est plus gouvernee par sa dynamique, et c'est ce
que la course du 2026-08-12 a mesure : multiplier par 1.89 la reponse du ressort de `backhair`
deplace son angle de 0.1 %.

NATURE de la grandeur : une DISTANCE PERPENDICULAIRE a l'axe d'une capsule, en unites de jeu
(4096 = 1 m). REPERE : l'espace de bind de l'os, exactement celui de `fit_radius` du generateur.
CE QU'ELLE VAUT QUAND LE DEFAUT EST ABSENT : le rayon ajuste sur la peau seule et le rayon
ajuste sur peau+cheveux sont EGAUX — le volume ne contient alors rien qu'il doive repousser.

Ce script ne modifie rien et ne genere rien. Il imprime des nombres.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import physics_keira_gen2 as g            # noqa: E402  (le generateur EST la source des methodes)

# Les joints qui portent des cheveux. Une chaine de cheveux ne doit pas etre un obstacle pour
# elle-meme, ni gonfler l'obstacle cense la contenir.
HAIR = ("backhair", "bang", "midhair")


def is_hair(name):
    n = name.lower()
    return any(h in n for h in HAIR)


def perp(geo, j, a, b, idx):
    """distances perpendiculaires a l'axe a->b, pour les sommets `idx`, dans le repere de l'os."""
    ibm = geo["ibms"][j]
    P = g.to_bone_local(ibm, geo["V"][idx])
    A = g.to_bone_local(ibm, np.array([a]))[0]
    B = g.to_bone_local(ibm, np.array([b]))[0]
    ax = B - A
    L = float(np.linalg.norm(ax))
    if L < 1e-6:
        return np.linalg.norm(P - A, axis=1)
    u = ax / L
    d = P - A
    t = d @ u
    return np.linalg.norm(d - np.outer(t, u), axis=1)


def main():
    geo = g.load_mesh(g.MODEL)
    names = geo["names"]
    idx_of = {n: i for i, n in enumerate(names)}
    J, W = geo["J"], geo["W"]

    hair_j = {i for i, n in enumerate(names) if is_hair(n)}
    print("joints de cheveux :", ", ".join(sorted(names[i] for i in hair_j)))

    # un sommet est « de cheveux » des qu'il porte un poids non negligeable sur un joint de cheveux
    hair_vert = np.zeros(len(W), dtype=bool)
    for c in range(J.shape[1]):
        for j in hair_j:
            hair_vert |= (J[:, c] == j) & (W[:, c] > 0.05)
    print("sommets portant du poids de cheveux : %d / %d" % (int(hair_vert.sum()), len(W)))

    print("\n%-18s %8s %8s %8s   %8s %8s   %s"
          % ("capsule", "livre", "n_tot", "n_chev", "r_peau", "ecart", "part de cheveux"))
    for a_name, b_name in (("head", "neck"), ("neck", "chest"), ("chest", "main")):
        if a_name not in idx_of or b_name not in idx_of:
            continue
        j, p = idx_of[a_name], idx_of[b_name]
        a, b = geo["P"][j], geo["P"][p]
        r_livre, thr, n = g.fit_radius(geo, j, a, b)
        # meme selection que le generateur, puis la MEME statistique sans les sommets de cheveux
        _c, _w, idx = g.influence(geo, j, thr)
        if len(idx) == 0:
            continue
        d_all = perp(geo, j, a, b, idx)
        skin = idx[~hair_vert[idx]]
        if len(skin) == 0:
            print("  %-16s tous ses sommets sont des cheveux" % ("%s->%s" % (a_name, b_name)))
            continue
        d_skin = perp(geo, j, a, b, skin)

        def iq(d):
            lo, hi = np.percentile(d, 25), np.percentile(d, 75)
            m = (d >= lo) & (d <= hi)
            return float(d[m].mean()) if m.any() else float(d.mean())

        r_skin = iq(d_skin)
        print("%-18s %8d %8d %8d   %8.0f %7.0f%%   %.0f %% des sommets"
              % ("%s->%s" % (a_name, b_name), r_livre, len(idx), len(idx) - len(skin),
                 r_skin, 100.0 * (r_livre - r_skin) / max(1.0, r_livre),
                 100.0 * (len(idx) - len(skin)) / len(idx)))

    # Et la question qui decide : la racine de chaque chaine de cheveux est-elle DANS la capsule
    # de tete telle qu'elle est livree ?
    print("\nprofondeur de la RACINE de chaque chaine de cheveux dans la capsule `head->neck`")
    print("livree (rayon 915 u au bout `head`) — positif = DEDANS :")
    j, p = idx_of["head"], idx_of["neck"]
    a, b = geo["P"][j], geo["P"][p]
    for root in ("backHair1", "Lbanga", "Rbanga", "Lmidhaira", "Rmidhaira", "lEara"):
        if root not in idx_of:
            continue
        rp = geo["P"][idx_of[root]]
        # distance perpendiculaire du POINT (pas d'un sommet) a l'axe, en monde
        ax = b - a
        L = float(np.linalg.norm(ax))
        u = ax / L if L > 1e-6 else ax
        v = rp - a
        t = float(v @ u)
        perp_d = float(np.linalg.norm(v - t * u))
        print("   %-11s distance a l'axe %6.0f u   ->  %s de %.0f u"
              % (root, perp_d, "DEDANS" if perp_d < 915 else "dehors", abs(915 - perp_d)))

    # LA PORTEE. Le maillon 0 est verrouille (rootlock) : le maillon libre PIVOTE autour de la
    # racine, donc la distance a l'axe qu'il peut atteindre vaut au plus racine + longueur d'os.
    # Si ce maximum reste sous le rayon de la capsule, la pointe ne peut JAMAIS en sortir — ce
    # n'est pas un reglage, c'est de la geometrie.
    print("\nPORTEE : la pointe peut-elle seulement SORTIR de la capsule `head->neck` ?")
    for root, tip, bone in (("backHair1", "backHair2", 0.1041),
                            ("Lbanga", "Lbangc", 0.0962 + 0.1914),
                            ("Lmidhaira", "Lmidhairb", 0.2349)):
        if root not in idx_of:
            continue
        rp = geo["P"][idx_of[root]]
        ax = b - a
        u = ax / float(np.linalg.norm(ax))
        v = rp - a
        perp_d = float(np.linalg.norm(v - float(v @ u) * u))
        reach = perp_d + bone * 4096.0
        print("   %-11s racine %4.0f u + os %4.0f u = portee %4.0f u   contre rayon 915  -> %s"
              % (root, perp_d, bone * 4096.0, reach,
                 "SORT" if reach > 915 else "NE SORT JAMAIS"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
