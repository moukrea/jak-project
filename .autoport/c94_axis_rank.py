#!/usr/bin/env python3
"""c94_axis_rank.py — SPEC 24 : DE COMBIEN DE DEGRES DE LIBERTE L'OBSERVABLE DISPOSE-T-ELLE ?

Phase Grecharged-secondary-motion, branche physics-keira-clean. Cycle 94 (2026-08-22).

CE QUE CE FICHIER TRANCHE, ET POURQUOI IL EXISTE
------------------------------------------------
Le cycle 93b a remonte que §24, §25, §26 et §27 sont bloquees sur UN SEUL fait et pas quatre :
`ROOM-AXSEL` montre qu'aucune des six impulsions isolees ne fait dominer l'axe qu'elle pousse
(22 a 43 %). La cause est restee « inconnue » depuis le cycle 8. Ce script la mesure.

Sa §24 (l.325-329, verbatim) assigne UNE frequence a CHACUNE de trois DIRECTIONS :

    Vertical    = 2.30 Hz     (range 2.1-2.5 Hz)
    Front/Back  = 2.50 Hz     (range 2.3-2.7 Hz)
    Lateral     = 2.65 Hz     (range 2.4-2.9 Hz)
    **Vertical motion is intentionally the slowest.**

Trois frequences par direction exigent trois degres de liberte SEPARABLES dans la grandeur qui
porte le verdict. Ce script demande a la trace combien il y en a, et si les directions propres
sont celles que la section nomme.

NATURE / REPERE / LIGNE DE BASE (les trois questions de SPEC 7, pour chaque grandeur publiee)
  RANG-PLAN    : NATURE  une part d'ENERGIE, sans dimension (valeur propre de la covariance 3x3
                         de la serie, rapportee a la trace), et un ANGLE en degres.
                 REPERE  le triedre de l'ancre (SPEC 7), ordre (v, ap, lat).
                 LIGNE DE BASE  une serie qui porte vraiment trois degres de liberte rend une
                         3e valeur propre du meme ordre que les deux autres. 0 % = deux DDL.
  CTRL-CINEM   : NATURE  un ANGLE en degres entre deux DIRECTIONS unitaires.
                 REPERE  idem.  AUCUN PARAMETRE AJUSTE : la direction predite est la projection
                         tangentielle de l'axe pousse sur le plan perpendiculaire a l'os, donc
                         de la cinematique pure — la contrainte de longueur et rien d'autre.
                 LIGNE DE BASE  0 deg = la reponse est exactement ou la cinematique la met.
                 CE QUI DISCRIMINE : les trois axes passent par le MEME calcul. Si l'un tombe a
                         1 deg et les deux autres a 50, l'ecart n'est pas imputable a l'instrument.
  ANISO-LIVREE : NATURE  un rapport de FREQUENCES, sans dimension.
                 REPERE  idem.  AUCUN AJUSTEMENT : calcule des compliances que le moteur PUBLIE
                         (`PHYSAXISS`) et de l'axe d'os MESURE, par P K P.
                 LIGNE DE BASE  1.0000 = trois axes confondus, anisotropie qui n'arrive pas.

CE QUE CE N'EST PAS : une frequence. Ce script ne publie aucun `f`. Il dit seulement de combien
de degres de liberte, et de quelles DIRECTIONS, une frequence pourrait etre tiree.
"""
import re
import sys

import numpy as np

AXN = {0: 'v', 1: 'ap', 2: 'lat'}
# Compliances que le moteur PUBLIE (`PHYSAXISS c=.. sv=.. sap=.. slat=..`), base de ROLE.
# Elles ne sont pas choisies ici : elles sont relues de la trace, et ce defaut n'est qu'un repli.
KDEF = (1.0, 1.1111, 1.2195)


def load(txt):
    """Les deux lignes d'une meme fenetre, PAR MAILLON. `l` est dans la cle, et c'est le point.

    Le lecteur `ldb_axsel.load()` capturait `l` sans le mettre dans la cle : les deux maillons
    ecrivaient dans la meme case et le distal ecrasait la racine. Ici la cle est (c, l, ax).
    """
    S = {}
    for m in re.finditer(r'^PHYSRINGBX c=(\d+) f=(\d+) l=(\d+) ax=(\d+) v=([-\d.e+]+)', txt, re.M):
        S.setdefault((int(m.group(1)), int(m.group(3)), int(m.group(4))), {}) \
         .setdefault(int(m.group(2)), [0.0, 0.0, 0.0])[0] = float(m.group(5))
    for m in re.finditer(r'^PHYSRINGBX2 c=(\d+) f=(\d+) ax=(\d+) l=(\d+)'
                         r' ap=([-\d.e+]+) lat=([-\d.e+]+)', txt, re.M):
        d = S.setdefault((int(m.group(1)), int(m.group(4)), int(m.group(3))), {}) \
             .setdefault(int(m.group(2)), [0.0, 0.0, 0.0])
        d[1] = float(m.group(5))
        d[2] = float(m.group(6))
    return S



def radial(txt):
    C = {}
    for m in re.finditer(r'^PHYSRINGCX c=(\d+) f=(\d+) l=(\d+) ax=(\d+) v=([-\d.e+]+)', txt, re.M):
        C.setdefault((int(m.group(1)), int(m.group(3)), int(m.group(4))), {}) \
         [int(m.group(2))] = float(m.group(5))
    return C

def compliances(txt):
    out = {}
    for m in re.finditer(r'^PHYSAXISS c=(\d+) sv=([-\d.e+]+) sap=([-\d.e+]+) slat=([-\d.e+]+)',
                         txt, re.M):
        out[int(m.group(1))] = (float(m.group(2)), float(m.group(3)), float(m.group(4)))
    return out


def bone_axis(S, c):
    """L'axe de l'os DANS LE TRIEDRE, tire de la serie elle-meme et de rien d'autre.

    C'est la direction que la trajectoire du joint ne visite pas : le 3e vecteur propre de la
    covariance, moyenne sur les trois fenetres et les deux maillons, signe fixe par la composante
    verticale (l'os pointe vers le haut du torse). On ne le prend PAS dans `ROOM-AXPLANE` : cette
    ligne-la sort d'un ajusteur, et une grandeur qui va porter un verdict se re-derive par un
    chemin qui ne partage pas son operateur (DIRECTIVES 2026-08-21 18:40).
    """
    acc = np.zeros((3, 3))
    for l in (0, 1):
        for ax in (0, 1, 2):
            d = S.get((c, l, ax))
            if not d:
                continue
            X = np.array([d[f] for f in sorted(d)])[:30]   # les 30 premieres frames
            Xc = X - X.mean(0)
            w, Q = np.linalg.eigh(Xc.T @ Xc / len(Xc))
            u = Q[:, np.argsort(w)[0]]
            if u[0] < 0:
                u = -u
            acc += np.outer(u, u)
    w, Q = np.linalg.eigh(acc)
    b = Q[:, np.argmax(w)]
    return b / np.linalg.norm(b) * (1.0 if b[0] >= 0 else -1.0)


def main(path):
    txt = open(path, errors='replace').read()
    S = load(txt)
    CS = compliances(txt)
    names = {0: 'chestL', 1: 'chestR'}
    A = print
    if not S:
        A('C94-RANK: ABSENT (aucune ligne PHYSRINGBX — phases AXV/AXB/AXL non jouees)')
        return 0

    A('== C94 — SPEC 24 : COMBIEN DE DEGRES DE LIBERTE, ET DANS QUELLES DIRECTIONS ? ==')
    A('   Trace : %s' % path)
    A('')
    A('-- C94-RANG-PLAN : la trajectoire du joint est-elle PLANE, et si oui de quelle normale ? --')
    A('   30 PREMIERES frames de chaque fenetre : si le plan n\'apparaissait qu\'ensuite, ce serait')
    A('   une decroissance, pas une contrainte. `w3` = part d\'energie de la 3e direction propre.')
    for c in sorted(names):
        b = bone_axis(S, c)
        A('   C94-BONE: chain=%-8s axe d\'os (re-derive de la serie, pas de ROOM-AXPLANE) ='
          ' (%+.4f,%+.4f,%+.4f)' % (names[c], b[0], b[1], b[2]))
        for l in (0, 1):
            for ax in (0, 1, 2):
                d = S.get((c, l, ax))
                if not d:
                    continue
                X = np.array([d[f] for f in sorted(d)])[:30]
                Xc = X - X.mean(0)
                w, Q = np.linalg.eigh(Xc.T @ Xc / len(Xc))
                o = np.argsort(w)[::-1]
                u3 = Q[:, o[2]]
                ang = np.degrees(np.arccos(min(1.0, abs(float(u3 @ b)))))
                A('   C94-RANG-PLAN: chain=%-8s l=%d excite=%-3s  w1=%6.2f%% w2=%5.2f%% w3=%5.2f%%'
                  '   angle(3e direction, os)=%5.1f deg'
                  % (names[c], l, AXN[ax], 100 * w[o[0]] / w.sum(), 100 * w[o[1]] / w.sum(),
                     100 * w[o[2]] / w.sum(), ang))
    A('')
    A('-- C94-CTRL-CINEM : CONTROLE A PRIORI, ZERO PARAMETRE AJUSTE ------------------------------')
    A('   Sous contrainte de longueur DURE le joint vit sur une sphere : la seule part d\'une')
    A('   poussee qui peut le deplacer est sa projection TANGENTIELLE. La direction de reponse est')
    A('   donc PREDITE par la geometrie seule. Les trois axes passent par le meme calcul : c\'est')
    A('   ce qui rend l\'ecart entre eux imputable au solveur et non a l\'instrument.')
    for c in sorted(names):
        b = bone_axis(S, c)
        for l in (0, 1):
            for ax in (0, 1, 2):
                d = S.get((c, l, ax))
                if not d:
                    continue
                u = np.zeros(3)
                u[ax] = 1.0
                pred = u - float(u @ b) * b
                pred = pred / np.linalg.norm(pred)
                X = np.array([d[f] for f in sorted(d)])
                Xc = X - X.mean(0)
                w, Q = np.linalg.eigh(Xc.T @ Xc / len(Xc))
                mes = Q[:, np.argmax(w)]
                dot = abs(float(mes @ pred))
                A('   C94-CTRL-CINEM: chain=%-8s l=%d excite=%-3s  predite=(%+.4f,%+.4f,%+.4f)'
                  '  mesuree=(%+.4f,%+.4f,%+.4f)  ecart=%5.1f deg'
                  % (names[c], l, AXN[ax], pred[0], pred[1], pred[2],
                     mes[0], mes[1], mes[2], np.degrees(np.arccos(min(1.0, dot)))))
    A('')
    A('-- C94-MEMEDIR : les fenetres `ap` et `lat` rendent-elles DEUX directions, ou UNE ? -------')
    A('   Deux frequences par direction exigent deux directions. |cos| entre les directions de')
    A('   reponse dominantes des trois fenetres, par maillon.')
    for c in sorted(names):
        for l in (0, 1):
            U = {}
            for ax in (0, 1, 2):
                d = S.get((c, l, ax))
                if not d:
                    continue
                X = np.array([d[f] for f in sorted(d)])
                Xc = X - X.mean(0)
                w, Q = np.linalg.eigh(Xc.T @ Xc / len(Xc))
                U[ax] = Q[:, np.argmax(w)]
            if len(U) == 3:
                A('   C94-MEMEDIR: chain=%-8s l=%d  |cos(v,ap)|=%.4f  |cos(v,lat)|=%.4f'
                  '  |cos(ap,lat)|=%.4f  -> ap/lat a %.1f deg l\'une de l\'autre'
                  % (names[c], l, abs(float(U[0] @ U[1])), abs(float(U[0] @ U[2])),
                     abs(float(U[1] @ U[2])),
                     np.degrees(np.arccos(min(1.0, abs(float(U[1] @ U[2])))))))
    A('')
    A('-- C94-ANISO-LIVREE : quelle anisotropie SURVIT a la contrainte de longueur ? -------------')
    A('   Le solveur projette la force sur le triedre et applique une raideur par ligne')
    A('   (jak-hd-physics.gc:2950-2952 et 2991-3000). La contrainte de longueur restreint ensuite')
    A('   le mouvement au plan perpendiculaire a l\'os. La raideur EFFECTIVE dans ce plan est donc')
    A('   P K P, et ses deux valeurs propres non nulles donnent le rapport de frequences que le')
    A('   joint peut REELLEMENT porter. Sa §24 demande f_lat/f_ap = 2.65/2.50 = 1.0600.')
    for c in sorted(names):
        sv, sap, slat = CS.get(c, KDEF)
        b = bone_axis(S, c)
        P = np.eye(3) - np.outer(b, b)
        K = np.diag([sv, sap, slat])
        w, Q = np.linalg.eigh(P @ K @ P)
        o = np.argsort(w)
        k0, k1 = float(w[o[1]]), float(w[o[2]])
        A('   C94-ANISO-LIVREE: chain=%-8s  K publiee (sv,sap,slat)=(%.4f,%.4f,%.4f)'
          % (names[c], sv, sap, slat))
        A('   C94-ANISO-LIVREE: chain=%-8s  P K P -> k_plan = %.5f / %.5f  (la 3e = %.2e, c\'est'
          ' l\'os)  rapport de frequences = %.4f  contre 1.0600 exige par SPEC 24 -> %.1f %% de'
          ' l\'anisotropie demandee'
          % (names[c], k0, k1, float(w[o[0]]), (k1 / k0) ** 0.5,
             100.0 * ((k1 / k0) ** 0.5 - 1.0) / 0.0600))
        A('   C94-ANISO-LIVREE: chain=%-8s  sv=%.4f est ANNULEE par le projecteur : la raideur'
          ' VERTICALE ne participe pas a la reponse dans le plan.' % (names[c], sv))
    A('')
    A('-- C94-RAD-PLAT : le canal RADIAL, celui du mode VERTICAL de sa §24 --------------------')
    A('   `ROOM-AXFIT-RAD` ajuste CE MEME canal dans les TROIS fenetres et publie trois')
    A('   frequences : chestL 2.320 / 2.355 / 2.550, chestR 2.415 / 2.460 / 2.705. Un mode propre')
    A('   n\'a QU\'UNE frequence. On publie donc l\'AMPLITUDE des trois fenetres a cote, parce que')
    A('   c\'est elle qui dit si l\'ecart est une non-linearite ou une contamination.')
    A('   NATURE : un deplacement radial rapporte a B0 (§6), sans dimension. REPERE : l\'axe de')
    A('   l\'os. LIGNE DE BASE : 0.0 a la pose d\'auteur.')
    C = radial(txt)
    for c in sorted(names):
        for l in (0, 1):
            cells, pks = [], []
            for ax in (0, 1, 2):
                d = C.get((c, l, ax))
                if not d:
                    continue
                y = np.array([d[f] for f in sorted(d)])
                pk = float(np.abs(y).max())
                pks.append(pk)
                cells.append('%s rms=%.5f pic=%.5f' % (AXN[ax], float(np.sqrt((y * y).mean())), pk))
            if not cells:
                continue
            A('   C94-RAD-PLAT: chain=%-8s l=%d  %s' % (names[c], l, '  |  '.join(cells)))
            if len(pks) == 3:
                sp = 100.0 * (max(pks) - min(pks)) / max(pks)
                A('   C94-RAD-PLAT: chain=%-8s l=%d  etalement des trois PICS = %.1f %%'
                  '   %s' % (names[c], l, sp,
                             'PLAT : la sortie ne suit pas la fenetre -> canal SATURE, aucune'
                             ' frequence n\'en est tirable' if sp < 10.0 else
                             'la sortie suit la fenetre'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1
                  else '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'))
