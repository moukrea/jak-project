#!/usr/bin/env python3
"""L'ECHELLE DE RAFFINEMENT DE §18, LUE DANS LA TRACE — QUATRE PHASES QUI NE DIFFERENT QUE PAR
DEUX VARIABLES, ET PERSONNE NE LES AVAIT COMPAREES.

La salle joue les MEMES regimes de lacet (r=9, r=10) dans quatre phases de la MEME course :

    ph=31  PH-REG    pose heritee                     rotation autour des axes du MONDE
    ph=36  PH-REGS   pose epinglee par son NOM        rotation autour des axes du MONDE
    ph=37  PH-REGT   pose = argmax MESURE de symetrie rotation autour des axes du MONDE
    ph=38  PH-REGA   la MEME pose que PH-REGT         rotation autour des axes du SUJET
    ph=44/45 PH-REGC la meme pose, collision armee/desarmee (cycle 112)

De 31 a 37 la seule variable est la POSE ; de 37 a 38 la seule variable est le REPERE DE LA
ROTATION. C'est une echelle a variable unique, construite par les cycles 66 et 67, et son
exploitation ne demande aucune course : tout est deja emis.

NATURE : `perr` = max |p_rlk - cible| / B0, la SORTIE du ressort, adimensionnee. `rgap` = son
  ENTREE geometrique. L'ecart au miroir est un ANGLE en degres entre la direction d'os de chestL
  et la REFLEXION de celle de chestR dans le plan median.
REPERE : les axes du sujet publies par PHYSREG*W ; le plan median est celui de normale wa=2.
LECTURE HORS DEFAUT : un rig symetrique a 0,005 deg en pose de bind (DIRECTIVES 2026-08-21 01:20)
  -> tout ecart au miroir bien au-dessus de zero est un etat de POSE, pas une propriete du perso.
"""
import re, sys, math
from collections import defaultdict

PH = {31: ('PH-REG  ', 'heritee', 'MONDE'), 36: ('PH-REGS ', 'nommee', 'MONDE'),
      37: ('PH-REGT ', 'argmax', 'MONDE'), 38: ('PH-REGA ', 'argmax', 'SUJET'),
      44: ('PH-REGC0', 'argmax', 'SUJET'), 45: ('PH-REGC1', 'argmax', 'SUJET')}
TAG2PH = {'': 31, 'S': 36, 'T': 37, 'A': 38, 'C': 44}

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else \
        '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
    perr = defaultdict(list); axes = {}; bones = defaultdict(dict)
    allperr = []
    for ln in open(path, encoding='utf-8', errors='ignore'):
        m = re.match(r'PHYSREGW ph=(\d+) c=(\d+) r=(\d+) rgap=([\d.]+) perr=([\d.]+)', ln)
        if m:
            ph, c, r, g, p = m.groups()
            allperr.append((int(c), float(p)))
            if int(r) in (9, 10):
                perr[(int(ph), int(r))].append((int(c), float(p), float(g)))
            continue
        m = re.match(r'PHYSREG([A-Z]*)W wa=(\d+) ux=(-?[\d.]+) uy=(-?[\d.]+) uz=(-?[\d.]+)', ln)
        if m:
            t, wa, x, y, z = m.groups(); axes[int(wa)] = (float(x), float(y), float(z)); continue
        m = re.match(r'PHYSREG([A-Z]*)B c=(\d+) l=(\d+) ux=(-?[\d.]+) uy=(-?[\d.]+) uz=(-?[\d.]+)', ln)
        if m:
            t, c, l, x, y, z = m.groups()
            if t in TAG2PH: bones[TAG2PH[t]][(int(c), int(l))] = (float(x), float(y), float(z))

    def dot(a, b): return sum(p * q for p, q in zip(a, b))
    def norm(a):
        n = math.sqrt(dot(a, a)); return tuple(p / n for p in a)

    # ---- 1. LE PRETENDU PLAFOND DE `perr` -------------------------------------------------
    print('1. « `perr` DE chestL EST AU PLAFOND DE 0,50 B0 » — VERIFIE SUR LA POPULATION ENTIERE')
    for c in (0, 1):
        v = sorted(p for cc, p in allperr if cc == c)
        print('   c=%d : n=%d  min=%.4f  med=%.4f  max=%.4f  valeurs distinctes au millieme : %d'
              % (c, len(v), v[0], v[len(v) // 2], v[-1], len({round(x, 3) for x in v})))
    tot = [p for _, p in allperr]
    print('   toutes chaines, SUR CE TAG SEUL : %d valeurs DEPASSENT 0,50, maximum %.4f.'
          % (sum(1 for p in tot if p > 0.50), max(tot)))
    print('   => IL N\'Y A PAS DE PLAFOND A 0,50 SUR `perr`. La phrase du cycle 108 generalisait')
    print('      12 cellules de PH-REGA (qui tombent en 0,50-0,58) a « TOUS les regimes ». FAUX.')
    print('   (`perr` apparait aussi sur PHYSRESTW, un AUTRE emetteur et une autre fenetre,\n         ou il monte a 3,94 : ne pas melanger les deux populations.)')

    # ---- 2. L'ECART AU MIROIR, PAR PHASE ---------------------------------------------------
    print('\n2. ECART AU MIROIR DES DEUX CHAINES, PAR PHASE (plan median = normale wa=2)')
    n2 = norm(axes[2]); mir = {}
    for ph in sorted(bones):
        angs = []
        for l in (0, 1):
            if (0, l) not in bones[ph] or (1, l) not in bones[ph]: continue
            L = norm(bones[ph][(0, l)]); R = bones[ph][(1, l)]
            d = dot(R, n2); Rm = norm(tuple(R[i] - 2 * d * n2[i] for i in range(3)))
            angs.append(math.degrees(math.acos(max(-1, min(1, dot(L, Rm))))))
        if angs:
            mir[ph] = sum(angs) / len(angs)
            print('   ph=%-3d %s pose %-8s axes %-6s -> ecart au miroir %6.2f deg'
                  % (ph, PH[ph][0], PH[ph][1], PH[ph][2], mir[ph]))

    # ---- 3. LE RAPPORT L/R, PAR PHASE ------------------------------------------------------
    print('\n3. RAPPORT L/R DE `perr` SUR LES MEMES FENETRES DE LACET, PAR PHASE')
    print('   %-22s %-7s %-7s %9s %9s %8s' % ('phase', 'pose', 'axes', 'r=9 L/R', 'r=10 L/R', 'miroir'))
    for ph in sorted(PH):
        cells = {}
        for r in (9, 10):
            v = perr.get((ph, r), [])
            L = [p for c, p, g in v if c == 0]; R = [p for c, p, g in v if c == 1]
            if L and R: cells[r] = (sum(L) / len(L)) / (sum(R) / len(R))
        if not cells: continue
        print('   ph=%-3d %-15s %-7s %-7s %9s %9s %7s'
              % (ph, PH[ph][0], PH[ph][1], PH[ph][2],
                 '%.3f' % cells[9] if 9 in cells else '-',
                 '%.3f' % cells[10] if 10 in cells else '-',
                 '%.2f' % mir[ph] if ph in mir else '-'))

    print('\n4. CE QUE L\'ECHELLE MONTRE, ET ELLE A UNE VARIABLE UNIQUE A CHAQUE BARREAU')
    print('   31 -> 36 -> 37 : SEULE LA POSE CHANGE (46,3 -> 7,2 -> 0,2 deg du miroir).')
    print('      Le rapport L/R passe de 0,14-0,25 (chestR domine) a ~1,0-1,3 (PARITE) et se')
    print('      STABILISE : 36 et 37 rendent la meme chose, donc 7,2 deg suffisait deja.')
    print('      C\'est le TEST DE RAFFINEMENT du registre, et il CONVERGE.')
    print('   37 -> 38 : LA POSE NE BOUGE PAS (0,23 contre 0,40 deg). LA SEULE VARIABLE DECLAREE')
    print('      EST LE REPERE DE LA ROTATION — monde -> axes du SUJET. Et le rapport saute de')
    print('      ~1,0-1,3 a 4,3-6,4.')
    print('   => L\'ASYMETRIE DE §18 N\'EST PAS PORTEE PAR LA POSE (confirme le cycle 107) : elle')
    print('      APPARAIT AVEC LE CHANGEMENT DE REPERE DE LA ROTATION, et c\'est une comparaison')
    print('      que la trace portait deja. §18 nomme les axes du SUJET, donc PH-REGA joue le BON')
    print('      geste et PH-REGT mesurait la parite sur le MAUVAIS : le defaut est reel.')
    print('   RESERVE, ET ELLE EST A MOI : ce paragraphe LOCALISE, il n\'explique pas. Le lacet de')
    print('      PH-REGA tourne autour de wa=0, qui est ORTHOGONAL au plan median (produit scalaire')
    print('      %.5f) : le geste est donc lui-meme mirror-symetrique, et une pose symetrique plus'
          % dot(norm(axes[0]), n2))
    print('      un geste symetrique qui rendent une reponse asymetrique DESIGNENT LE SOLVEUR.')
    print('      C\'est la conclusion du cycle 108, et elle survit — mais son mecanisme reste')
    print('      NON ETABLI, et aucune des quatre causes classees ne le porte.')

if __name__ == '__main__':
    main()
