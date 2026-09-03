#!/usr/bin/env python3
"""probe_c59_resize_identity.py — REDIMENSIONNER UN VOLUME EST-IL INERTE SUR `meshpen`, ET DE
QUELLE MANIERE : approximativement, ou PAR IDENTITE EXACTE ?

Phase Grecharged-secondary-motion, branche physics-keira-clean, KEIRA / POITRINE SEULE.
DIRECTIVES v3fee554599

POURQUOI CET INSTRUMENT. `meshpen` publie `res = dep - feff`, ou `dep` et `feff` sortent TOUS LES
DEUX de `phys-collide-depth`, evaluee en deux points (`q` simule, `rest` pose d'auteur) contre LE
MEME volume a LA MEME frame. Le cycle 58 a etabli que cette fonction est 1-lipschitzienne, donc
`res <= |q - rest|` — une BORNE. Le cycle 57 avait auparavant depense une cuisson entiere a
redimensionner `lBooc`/`rBooc` et vu `meshpen` MONTER, sans savoir si c'etait le rayon ou le
centre qui avait agi. Une borne ne repond pas a cette question ; une IDENTITE si.

CE QU'ON TESTE, ET C'EST PLUS FORT QU'UNE BORNE :
  T1  `res` est-il INVARIANT quand le RAYON DU LIEN change (`rlink`) ?
  T2  `res` est-il INVARIANT quand le volume est GONFLE UNIFORMEMENT (ra+d, rb+d) ?
  T3  CONTROLE NEGATIF, sans lequel T1/T2 ne discriminent rien : un changement NON uniforme
      (rayon d'un seul bout, ou translation du volume) doit FAIRE BOUGER `res`.
  T4  La borne de Lipschitz est-elle ATTEINTE (rapport -> 1) ? Si oui, `res` n'est pas seulement
      MAJORE par le deplacement : il le VAUT des que le deplacement est radial.

LES TROIS QUESTIONS DE LA SPEC 7 :
  NATURE — une DIFFERENCE DE LONGUEURS en unites de jeu (4096 u = 1 m). Ni une amplitude ni une
           frequence : la question est arithmetique et se tranche sur la fonction elle-meme.
  REPERE — monde a la pose de bind du mesh LIVRE, volumes replaces par la formule du generateur,
           exactement comme `probe_c58_lipschitz.py` (dont la transcription du predicat est
           reutilisee telle quelle, sans recopie).
  ABSENT — T1/T2 lisent 0.0000 u d'ecart si l'invariance tient ; T3 doit lire un ecart NON NUL,
           sinon le banc ne sait pas distinguer l'invariance de l'aveuglement.
"""
import os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from probe_c58_lipschitz import engine_depth_vd, load_volumes, U

SEED = 20260820
NP = 20000
RLINKS = [0.0, 340.0, 431.0, 587.0, 723.0]      # 0 + les rayons de lien livres de chestL/chestR


def diffs(P, Q, v, rl, dra=0.0, drb=0.0, shift=None):
    ca = np.asarray(v['ca'], float).copy()
    cb = np.asarray(v['cb'], float).copy()
    if shift is not None:
        ca = ca + shift; cb = cb + shift
    dP, DP = engine_depth_vd(P, ca, cb, v['ra']+dra, v['rb']+drb, v['cap'], rl)
    dQ, DQ = engine_depth_vd(Q, ca, cb, v['ra']+dra, v['rb']+drb, v['cap'], rl)
    return dP - dQ, dP, dQ, DP, DQ


def main():
    rng = np.random.default_rng(SEED)
    vols = load_volumes()
    print("volumes livres : %d" % len(vols))
    worst = {'T1': (0.0, None), 'T2': (0.0, None)}
    t3_moved = 0; t3_total = 0; t3_min = 1e18; t3_max = 0.0
    t4 = 0.0; t4det = None
    npairs_clean = 0

    for v in vols:
        ext = max(np.linalg.norm(np.asarray(v['cb']) - np.asarray(v['ca'])), 1.0)
        scale = ext + 2.0*(max(v['ra'], v['rb']) + max(RLINKS))
        mid = 0.5*(np.asarray(v['ca'], float) + np.asarray(v['cb'], float))
        # ECHANTILLONNAGE CIBLE SUR L'INTERIEUR. Un tirage uniforme dans une boite de cote
        # `2*scale` place moins de 1 % des couples STRICTEMENT dans le volume, et l'invariance
        # ne se teste QUE la : dehors, la profondeur est ecretee a 0 et la difference est nulle
        # des deux cotes pour une raison qui n'a rien a voir avec la question posee.
        tt = rng.random(NP)
        axis = np.asarray(v['ca'], float)[None, :] + \
               (np.asarray(v['cb'], float) - np.asarray(v['ca'], float))[None, :]*tt[:, None]
        rr = v['ra'] + (v['rb'] - v['ra'])*tt
        w = rng.normal(size=(NP, 3)); w /= np.linalg.norm(w, axis=1)[:, None]
        rad = (rr + max(RLINKS))*rng.random(NP)**(1.0/3.0)
        P = axis + w*rad[:, None]
        step = 10.0**rng.uniform(-2.0, np.log10(max(2.0*scale, 10.0)), NP)
        u = rng.normal(size=(NP, 3)); u /= np.linalg.norm(u, axis=1)[:, None]
        Q = P + u*step[:, None]
        sep = np.linalg.norm(Q - P, axis=1)

        base = None
        for rl in RLINKS:
            d, dP, dQ, DP, DQ = diffs(P, Q, v, rl)
            # « propre » = les deux points STRICTEMENT dans le volume et hors de la coquille
            # d < 0.001, les deux seules branches ou `phys-collide-depth` n'est pas lisse.
            clean = (dP > 0) & (dQ > 0) & (DP >= 0.001) & (DQ >= 0.001)
            if base is None:
                base = (d, clean, dP, dQ, sep)
                continue
            both = clean & base[1]
            npairs_clean += int(both.sum())
            if both.any():
                e = float(np.abs(d[both] - base[0][both]).max())
                if e > worst['T1'][0]:
                    worst['T1'] = (e, dict(vol=v['name'], rl=rl))
            # T2 : gonflement UNIFORME du volume, meme rayon de lien
            for infl in (37.0, -23.0, 211.0):
                if v['ra'] + infl <= 0 or v['rb'] + infl <= 0:
                    continue
                d2, dP2, dQ2, DP2, DQ2 = diffs(P, Q, v, rl, dra=infl, drb=infl)
                c2 = clean & (dP2 > 0) & (dQ2 > 0) & (DP2 >= 0.001) & (DQ2 >= 0.001)
                if c2.any():
                    e = float(np.abs(d2[c2] - d[c2]).max())
                    if e > worst['T2'][0]:
                        worst['T2'] = (e, dict(vol=v['name'], rl=rl, infl=infl))
            # T3 : CONTROLE NEGATIF — non uniforme (un seul bout) et translation
            for tag, kw in (('ra seul', dict(dra=97.0)),
                            ('translation', dict(shift=np.array([61.0, -43.0, 29.0])))):
                d3, dP3, dQ3, DP3, DQ3 = diffs(P, Q, v, rl, **kw)
                c3 = clean & (dP3 > 0) & (dQ3 > 0) & (DP3 >= 0.001) & (DQ3 >= 0.001)
                if c3.any():
                    t3_total += 1
                    m = float(np.abs(d3[c3] - d[c3]).max())
                    if tag == 'ra seul' and not v['cap']:
                        continue          # sur une SPHERE, ra seul EST uniforme : pas un controle
                    if m > 1e-6:
                        t3_moved += 1
                        t3_max = max(t3_max, m)
                    t3_min = min(t3_min, m)
            # T4 : la borne de Lipschitz est-elle atteinte ?
            if clean.any():
                r = np.abs(d[clean])/sep[clean]
                k = int(np.argmax(r))
                if r[k] > t4:
                    t4 = float(r[k]); t4det = dict(vol=v['name'], rl=rl, sep=float(sep[clean][k]))

    print()
    print("T1  INVARIANCE PAR LE RAYON DU LIEN (`rlink` 0 / 340 / 431 / 587 / 723 u)")
    print("    ecart max sur la DIFFERENCE res = %.10f u   (%s)" % (worst['T1'][0], worst['T1'][1]))
    print("T2  INVARIANCE PAR GONFLEMENT UNIFORME DU VOLUME (+37 / -23 / +211 u)")
    print("    ecart max sur la DIFFERENCE res = %.10f u   (%s)" % (worst['T2'][0], worst['T2'][1]))
    print("T3  CONTROLE NEGATIF (non uniforme : ra seul sur capsule, translation du volume)")
    print("    %d/%d configurations ont FAIT BOUGER la difference ; ecart max atteint = %.4f u,"
          "  plus petit = %.4f u" % (t3_moved, t3_total, t3_max, t3_min))
    print("T4  BORNE DE LIPSCHITZ ATTEINTE ?  max |res| / |q - rest| = %.6f   (%s)" % (t4, t4det))
    print()
    print("couples propres comptes : %d" % npairs_clean)
    ok = (worst['T1'][0] < 1e-3) and (worst['T2'][0] < 1e-3) and t3_moved > 0
    print("VERDICT : %s" % ("IDENTITE TENUE et le banc DISCRIMINE" if ok else "REFUTEE / non discriminant"))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
