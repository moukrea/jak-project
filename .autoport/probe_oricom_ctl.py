#!/usr/bin/env python3
"""probe_oricom_ctl.py — SPEC 12 LATERAL : QUEL MECANISME TIENT LE POLE MEDIAL ?

POURQUOI CETTE SONDE EXISTE. Le cycle 27 a mesure, sur le COM exact, que sa SPEC 12 est SOUS sa
bande d'UN POLE PAR SEIN, en miroir :

    chestL  §12 lateral i=2  0.0807   cible 0.19  bande 0.15-0.24   SOUS
    chestR  §12 lateral i=4  0.0283   cible 0.19  bande 0.15-0.24   SOUS

et il a conclu, mot pour mot : « Le defaut est donc DIRECTIONNEL et en MIROIR, ce qui exclut un
simple manque d'amplitude : chaque sein repond quand la gravite tire d'un cote et pas quand elle
tire de l'autre. C'est le prochain chantier de physique. » Il l'a laisse SANS CAUSE.

L'appareil qui existe pour attribuer une cause est le balayage a SIX passes de `PHYSROOM-PH-ORI`
(k=0 reference, puis un mecanisme desarme par passe : k=1 LONGUEUR, k=2 COTE, k=3 CONE, k=4 MUR DE
COLLISION, k=5 BORNE §22 DU CANAL RADIAL — cette derniere ajoutee au cycle 28). Il ne publiait que `PHYSORICTL`, c'est-a-dire l'APEX — et l'apex est AVEUGLE a ce
defaut : sur les deux poles lateraux de `chestL` il rend 0.34999 / 0.34112 (2.6 % d'ecart) la ou le
COM exact rend 0.0807 / 0.1862 (facteur 2.31). L'ablation ne pouvait donc pas voir le defaut
qu'elle est faite pour attribuer, et ses quatre verdicts « SYMETRISE — CE MECANISME EST LA CAUSE »
sont vacuous : la reference est DEJA symetrique sur cette grandeur-la.

`phys-room.gc` emet depuis ce cycle `PHYSCTLDF` et `PHYSCTLML` — les DEUX entrees du COM exact, sur
les SIX passes, par les MEMES accesseurs que `PHYSDFMA` / `PHYSORICOML`. Cette sonde les compose.

LES TROIS QUESTIONS (SPEC 7), repondues avant le chiffre :
  NATURE  : un DEPLACEMENT SOUTENU du centroide de l'organe, en B0 — la grandeur que ses §10/§11/
            §12 nomment. Pas une variance, pas une amplitude.
  REPERE  : la base de l'ANCRE (`chest`), exactement celle de `probe_oricom_exact.py` dont la
            composition est reprise ligne pour ligne (skel telescopique + tenseur x levier).
  ABSENT  : l'orientation i=0 est la pose debout d'auteur, ou sa §9 exige 0.0000 — publiee comme
            ligne de base sur CHAQUE passe, parce qu'un controle qui deplacerait la ligne de base
            rendrait toutes ses cellules incomparables a la reference.

LE CONTROLE INTERNE, ET IL EST OBLIGATOIRE : la passe k=0 de `PHYSCTLDF`/`PHYSCTLML` doit
reproduire `PHYSDFMA`/`PHYSORICOML` AU BIT PRES. Memes accesseurs, meme frame, meme fenetre. Si
l'ecart n'est pas nul, l'emission neuve ne mesure pas la meme chose que l'ancienne et TOUT ce qui
suit est a jeter — la sonde le dit et sort.

MESH : celui du PACK LIVRE (`out/jak1/fr3/skin/keira-hd-lod0.glb`), jamais le rip du donneur ni le
`-donor-injected.glb` intermediaire (piege `reskin-measure-the-prepped-input`).

Usage :  python3 .autoport/probe_oricom_ctl.py [<log>] [<glb>]
"""
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_oricom_exact as EX

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPDIR = os.path.join(REPO, '.autoport/reports/Grecharged-secondary-motion')
LOG = os.path.join(REPDIR, 'keira-room-x86.log')
GLB = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
B0 = 602.0
CUTS = EX.CUTS
CH = EX.CH
PASS = {0: 'k=0 reference', 1: 'k=1 LONGUEUR off', 2: 'k=2 COTE off',
        3: 'k=3 CONE off', 4: 'k=4 MUR COLLISION off', 5: 'k=5 BORNE RADIALE off'}
# les deux poles lateraux de sa §12, et les deux orientations de §10/§11 pour le contexte
LAT = (2, 4)
BAND12 = (0.19, 0.15, 0.24)

OUT = []


def A(s=''):
    OUT.append(s)
    print(s)


def parse_ctl(txt):
    """`kr = 10*k + r` et `kl = 10*k + l` — decodage EXPLICITE et VERIFIE (un indice compose mal
    relu est un piege deja paye sur ce dossier : on refuse tout r >= 3 / l >= 4 au lieu de le
    ranger silencieusement quelque part)."""
    G = lambda p: re.findall(p, txt, re.M)
    rows, ldb = {}, {}
    bad = []
    for c, kr, i, m0, m1, m2 in G(r'^PHYSCTLDF c=(\d+) kr=(\d+) i=(\d+) m0=([-\d.e+]+)'
                                  r' m1=([-\d.e+]+) m2=([-\d.e+]+)'):
        k, r = divmod(int(kr), 10)
        if r >= 3 or k >= 6:
            bad.append(('DF', kr))
            continue
        rows.setdefault((int(c), k, int(i)), {})[r] = [float(m0), float(m1), float(m2)]
    for c, kl, i, dv, dap, dlat in G(r'^PHYSCTLML c=(\d+) kl=(\d+) i=(\d+) dv=([-\d.e+]+)'
                                     r' dap=([-\d.e+]+) dlat=([-\d.e+]+)'):
        k, l = divmod(int(kl), 10)
        if l >= 4 or k >= 6:
            bad.append(('ML', kl))
            continue
        # (dv, dap, dlat) sont les composantes sur les lignes (rv=1, rap=2, rlat=0) de l'ancre :
        # le vecteur en base (e0,e1,e2) est donc (dlat, dv, dap). Identique a probe_oricom_exact.
        ldb[(int(c), k, int(i), l)] = np.array([float(dlat), float(dv), float(dap)])
    D = {key: np.array([v[0], v[1], v[2]]) for key, v in rows.items() if len(v) == 3}
    return D, ldb, bad


def com(D, ldb, g, c, k, i, cut):
    """La composition de `probe_oricom_exact.py`, reprise sans une variante : skel telescopique
    + tenseur applique au levier geometrique. `d_j` est un CUMUL au parent, donc d1 = d0 + ldb1."""
    gg = g[cut]
    d0 = ldb[(c, k, i, 0)]
    d1 = d0 + ldb[(c, k, i, 1)]
    sk = (gg['W'][0] * d0 + gg['W'][1] * d1) / gg['n']
    # CONVENTION DU MOTEUR : `jak-hd-physics.gc:3922` applique l'offset en VECTEUR-LIGNE
    # (`r_j = SOMME_i o_i . bm[i][j]`) et le tenseur multiplie A DROITE (`matrix*! tmp bm dfm`).
    # La contribution tensorielle est donc `L . (D - I)`, PAS `(D - I) . L`. `D` est symetrique
    # a 0.032 pres (controle de `ROOM-SPEC12`), donc l'ecart vaut ~0.5 % — on prend quand meme
    # la convention du moteur, pour que sonde et tableau ne divergent jamais.
    tn = gg['L'] @ (D[(c, k, i)] - np.eye(3)) / gg['n']
    return float(np.linalg.norm(sk + tn) / B0)


def main():
    log = sys.argv[1] if len(sys.argv) > 1 else LOG
    glb = sys.argv[2] if len(sys.argv) > 2 else GLB
    txt = open(log, errors='ignore').read()

    D, ldb, bad = parse_ctl(txt)
    A('SPEC 12 LATERAL — LE POLE MEDIAL, MECANISME PAR MECANISME')
    A('log  : %s' % os.path.relpath(log, REPO))
    A('mesh : %s' % glb)
    A('lignes lues : PHYSCTLDF %d matrices · PHYSCTLML %d vecteurs%s'
      % (len(D), len(ldb), '' if not bad else '  · %d INDICES REFUSES %s' % (len(bad), bad[:4])))
    if not D or not ldb:
        A('ABSENT : cette course precede l\'emission de PHYSCTLDF/PHYSCTLML. Rien a composer.')
        return 2
    A('')

    # ---- LE CONTROLE INTERNE, AVANT TOUTE LECTURE ----------------------------------------------
    d0 = EX.parse(txt)
    d0 = EX.parse_extra(txt, d0)
    worst_df, worst_ml = 0.0, 0.0
    nref = 0
    for (c, k, i), M in D.items():
        if k != 0:
            continue
        if (c, i) in d0['dfma']:
            worst_df = max(worst_df, float(np.abs(M - d0['dfma'][(c, i)]).max()))
            nref += 1
    for (c, k, i, l), v in ldb.items():
        if k != 0:
            continue
        if (c, i, l) in d0['ldb']:
            worst_ml = max(worst_ml, float(np.abs(v - d0['ldb'][(c, i, l)]).max()))
    A('-- CONTROLE INTERNE : LA PASSE k=0 CONTRE LES EMETTEURS DE REFERENCE ---------------------')
    A('   `PHYSCTLDF`/`PHYSCTLML` a k=0 doivent reproduire `PHYSDFMA`/`PHYSORICOML` au bit pres :')
    A('   memes accesseurs, meme frame, meme fenetre. Un ecart non nul voudrait dire que la mesure')
    A('   neuve ne mesure pas la meme chose que l\'ancienne, et le reste serait a jeter.')
    A('   ecart max sur la matrice   : %.3e   (%d orientations x chaines confrontees)'
      % (worst_df, nref))
    A('   ecart max sur les maillons : %.3e' % worst_ml)
    if nref == 0:
        A('   VERDICT : IMPOSSIBLE — aucune ligne de reference a confronter.')
        return 2
    if max(worst_df, worst_ml) > 0.0:
        A('   VERDICT : ECART NON NUL — l\'emission neuve diverge de la reference. LECTURE ARRETEE.')
        return 1
    A('   VERDICT : IDENTIQUE. La passe k=0 est la reference, les autres sont comparables a elle.')
    A('')

    g = EX.geometry(glb)
    if g is None:
        A('mesh introuvable : %s' % glb)
        return 2

    # ---- LA LIGNE DE BASE DE CHAQUE PASSE ------------------------------------------------------
    A('-- LIGNE DE BASE : i=0, LA POSE DEBOUT D\'AUTEUR, OU SA §9 EXIGE 0.0000 -------------------')
    A('   Publiee POUR CHAQUE PASSE : un controle qui deplacerait la ligne de base rendrait ses')
    A('   cellules incomparables a la reference, et l\'attribution serait fausse sans le dire.')
    for c in sorted(CH):
        row = []
        for k in sorted(PASS):
            if (c, k, 0) in D:
                row.append('%s %.4f' % (('k%d' % k), com(D, ldb, g[c], c, k, 0, 0.05)))
        A('   %-8s %s' % (CH[c][0], '  ·  '.join(row)))
    A('')

    # ---- LE CORPS DE L'EXPERIENCE --------------------------------------------------------------
    tgt, lo, hi = BAND12
    A('-- SPEC 12 : LES DEUX POLES LATERAUX, PASSE PAR PASSE (COM exact, B0, cut w>=0.05) -------')
    A('   i=2 : g = (-0.998, 0, +0.065) — gravite vers -X.   i=4 : g = (+0.998, 0, -0.065).')
    A('   `lBoob` est en +X, `rBoob` en -X : le pole MEDIAL de chestL est i=2, celui de chestR')
    A('   est i=4. Ce sont EXACTEMENT les deux cellules SOUS leur bande. Le rapport `med/lat` est')
    A('   le nombre qui porte le defaut : a 1.00 les deux poles repondent pareil, sous 1.00 le')
    A('   pole medial repond moins. Un mecanisme qui le ramene vers 1.00 est la cause.')
    A('')
    A('   %-8s %-22s %9s %9s %9s   %s' % ('chaine', 'passe', 'medial', 'lateral', 'med/lat',
                                          'verdict du pole medial'))
    res = {}
    for c in sorted(CH):
        med, lat = (2, 4) if c == 0 else (4, 2)
        for k in sorted(PASS):
            if (c, k, med) not in D or (c, k, lat) not in D:
                continue
            vm = com(D, ldb, g[c], c, k, med, 0.05)
            vl = com(D, ldb, g[c], c, k, lat, 0.05)
            ratio = vm / vl if vl > 0 else float('nan')
            vd = 'SOUS' if vm < lo else ('DANS' if vm <= hi else 'AU-DESSUS')
            res[(c, k)] = (vm, vl, ratio, vd)
            A('   %-8s %-22s %9.4f %9.4f %9.3f   %s'
              % (CH[c][0] if k == 0 else '', PASS[k], vm, vl, ratio, vd))
        A('')

    # ---- L'ATTRIBUTION, ET ELLE EST ECRITE COMME UNE REGLE, PAS COMME UNE IMPRESSION -----------
    A('-- ATTRIBUTION -------------------------------------------------------------------------')
    A('   REGLE, posee AVANT de lire : un mecanisme est designe CAUSE de ce defaut si son')
    A('   desarmement (a) fait entrer le pole medial dans sa bande [%.2f, %.2f], ou (b) ramene le'
      % (lo, hi))
    A('   rapport med/lat a au moins 0.80 alors que la reference est sous 0.60. Un mecanisme qui')
    A('   ne bouge ni l\'un ni l\'autre est EXONERE — et c\'est un resultat, pas une absence.')
    A('')
    for c in sorted(CH):
        if (c, 0) not in res:
            continue
        r0 = res[(c, 0)]
        A('   %s — reference : medial %.4f (%s), rapport %.3f'
          % (CH[c][0], r0[0], r0[3], r0[2]))
        for k in sorted(PASS):
            if k == 0 or (c, k) not in res:
                continue
            vm, vl, ratio, vd = res[(c, k)]
            gain_band = (vd != 'SOUS' and r0[3] == 'SOUS')
            gain_ratio = (ratio >= 0.80 and r0[2] < 0.60)
            tag = ('CAUSE' if (gain_band or gain_ratio) else 'exonere')
            A('     %-22s medial %.4f (%s)  rapport %.3f  ->  %s   [medial x%.2f]'
              % (PASS[k], vm, vd, ratio, tag, (vm / r0[0]) if r0[0] > 0 else float('nan')))
        A('')

    dest = os.path.join(REPDIR, 'C28-oricom-ctl.txt')
    open(dest, 'w').write('\n'.join(OUT) + '\n')
    A('ecrit : %s' % os.path.relpath(dest, REPO))
    return 0


if __name__ == '__main__':
    sys.exit(main())
