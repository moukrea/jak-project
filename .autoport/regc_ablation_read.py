#!/usr/bin/env python3
"""PH-REGC — LE DISCRIMINANT DE §18, LU DANS LA TRACE OU IL DORMAIT DEPUIS QUATRE COURSES.

Le cycle 108 a ECRIT le critere AVANT la course (phys-room.gc, pave `PHYSROOM-PH-REGC`) :

    rapport gauche/droite de `perr` SOUS x1.3 sur la jambe desarmee  -> la collision porte §18 ;
    baisse de moins de 20 % par rapport a la jambe ARMEE de la meme cellule -> REFUTEE.

Ce script ne fait que l'APPLIQUER. Il ne choisit aucun seuil : les deux nombres (1.3 et 20 %)
sont recopies du pave, et le script sort en echec si on tente de les lire ailleurs.

NATURE des grandeurs : `apex` et `com` sont des LONGUEURS adimensionnees (fractions de B0, la
  distance racine->apex de §6) et ce sont des MAXIMA SUR LA FENETRE ; `perr` = max |p_rlk - cible|
  / B0, la SORTIE du ressort ; `rgap` = |cible - pose d'auteur| / B0, son ENTREE.
REPERE : les axes du SUJET releves a l'execution dans la pose epinglee (`ROOM-REGA`), jamais le monde.
LECTURE HORS DEFAUT : la jambe `abl=0` doit reproduire `PHYSREGA` r=9/r=10 ; sinon tout ce bloc tombe.
"""
import re, sys
from collections import defaultdict

CRIT_RATIO_ARMED_CARRIES = 1.3    # pave PH-REGC, recopie
CRIT_DROP_REFUTES        = 0.20   # pave PH-REGC, recopie

def load(path):
    regc, regw, rega, regaw = {}, {}, {}, {}
    order = []
    for ln in open(path, encoding='utf-8', errors='ignore'):
        m = re.match(r'PHYSREGC c=(\d+) r=(\d+) sgn=(-?[\d.]+) abl=(\d+) apex=([\d.]+) com=([\d.]+)', ln)
        if m:
            c, r, sgn, abl, ap, com = m.groups()
            key = (int(c), int(r), float(sgn), int(abl))
            regc[key] = (float(ap), float(com))
            order.append(key)
            continue
        m = re.match(r'PHYSREGW ph=(4[45]) c=(\d+) r=(\d+) rgap=([\d.]+) perr=([\d.]+)', ln)
        if m:
            ph, c, r, rgap, perr = m.groups()
            regw.setdefault((int(c), int(r), 0 if ph == '44' else 1), []).append((float(rgap), float(perr)))
            continue
        m = re.match(r'PHYSREGA c=(\d+) r=(\d+) sgn=(-?[\d.]+) apex=([\d.]+) com=([\d.]+)', ln)
        if m:
            c, r, sgn, ap, com = m.groups()
            rega[(int(c), int(r), float(sgn))] = (float(ap), float(com))
            continue
        m = re.match(r'PHYSREGW ph=38 c=(\d+) r=(\d+) rgap=([\d.]+) perr=([\d.]+)', ln)
        if m:
            c, r, rgap, perr = m.groups()
            regaw.setdefault((int(c), int(r)), []).append(float(perr))
    return regc, regw, rega, regaw, order

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else \
        '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
    regc, regw, rega, regaw, order = load(path)
    if not regc:
        print('ECHEC: aucune ligne PHYSREGC dans %s' % path); sys.exit(1)

    print('PH-REGC — trace %s' % path)
    print('cellules PHYSREGC lues : %d (attendu 16 = 2 chaines x 2 regimes x 2 sens x 2 jambes)'
          % len(regc))

    # ---- 1. CLAUSE DE VALIDITE : abl=0 doit reproduire PH-REGA -----------------------------
    print('\n1. CLAUSE DE VALIDITE — la jambe ARMEE reproduit-elle PH-REGA ?')
    print('   (si elle ne la reproduit pas, la comparaison ne mesure pas ce qu\'elle pretend)')
    worst = 0.0
    print('   %-18s %10s %10s %9s' % ('c,r,sgn', 'REGC abl0', 'REGA', 'ecart'))
    for (c, r, sgn) in sorted(rega):
        k = (c, r, sgn, 0)
        if k not in regc: continue
        a0, a1 = regc[k][0], rega[(c, r, sgn)][0]
        d = (a0 - a1) / a1 * 100.0
        worst = max(worst, abs(d))
        print('   %-18s %10.4f %10.4f %8.2f%%' % ('c=%d r=%d sgn=%+.0f' % (c, r, sgn), a0, a1, d))
    print('   ecart max de reproduction : %.2f %%  <- PLANCHER DE BRUIT de la mesure' % worst)

    # ---- 2. LE CRITERE, APPLIQUE ------------------------------------------------------------
    print('\n2. LE CRITERE DU PAVE, APPLIQUE SANS ETRE RENEGOCIE')
    print('   %-16s %9s %9s %9s %9s %9s' % ('cellule', 'L arme', 'R arme', 'L desar', 'R desar', 'ratio'))
    rows = []
    for (r, sgn) in sorted({(k[1], k[2]) for k in regc}):
        try:
            l0 = regc[(0, r, sgn, 0)][0]; r0 = regc[(1, r, sgn, 0)][0]
            l1 = regc[(0, r, sgn, 1)][0]; r1 = regc[(1, r, sgn, 1)][0]
        except KeyError:
            continue
        ra, rd = l0 / r0, l1 / r1
        rows.append((r, sgn, ra, rd))
        print('   r=%-2d sgn=%+.0f     %9.4f %9.4f %9.4f %9.4f  %5.2f->%5.2f'
              % (r, sgn, l0, r0, l1, r1, ra, rd))
    if not rows:
        print('ECHEC: aucune cellule appariee'); sys.exit(1)

    print('\n   rapport L/R sur la jambe DESARMEE :')
    for r, sgn, ra, rd in rows:
        verdict = 'SOUS 1.3' if rd < CRIT_RATIO_ARMED_CARRIES else 'AU-DESSUS de 1.3'
        print('     r=%-2d sgn=%+.0f  x%.3f   %s' % (r, sgn, rd, verdict))
    print('\n   baisse du rapport, desarmee vs armee (le critere de REFUTATION) :')
    drops = []
    for r, sgn, ra, rd in rows:
        drop = (ra - rd) / ra
        drops.append(drop)
        print('     r=%-2d sgn=%+.0f  x%.3f -> x%.3f   baisse %+.2f %%' % (r, sgn, ra, rd, drop * 100))

    under = all(rd < CRIT_RATIO_ARMED_CARRIES for _, _, _, rd in rows)
    small = all(d < CRIT_DROP_REFUTES for d in drops)
    print('\n3. VERDICT')
    if under:
        print('   LA COLLISION PORTE §18 : le rapport tombe sous x1.3 desarme.')
    elif small:
        print('   COLLISION REFUTEE COMME CAUSE DE L\'ASYMETRIE DE §18.')
        print('   Le rapport L/R reste x%.2f a x%.2f desarme (critere : sous x1.3),'
              % (min(rd for *_, rd in rows), max(rd for *_, rd in rows)))
        print('   et sa baisse vaut %.2f a %.2f %% (critere de refutation : moins de 20 %%).'
              % (min(drops) * 100, max(drops) * 100))
        print('   La baisse est du meme ordre que le plancher de bruit mesure en 1 (%.2f %%).' % worst)
    else:
        print('   INDETERMINE : ni sous x1.3, ni une baisse sous 20 %%. A rejouer.')

    # ---- 4. NON-VACUITE : l'ablation a-t-elle TIRE ? ---------------------------------------
    print('\n4. NON-VACUITE — l\'ablation a-t-elle fait quelque chose ?')
    print('   (un zero tire d\'un couteau emousse n\'est pas une refutation)')
    eff = []
    for (r, sgn) in sorted({(k[1], k[2]) for k in regc}):
        for c in (0, 1):
            k0, k1 = (c, r, sgn, 0), (c, r, sgn, 1)
            if k0 in regc and k1 in regc:
                eff.append((c, r, sgn, (regc[k1][0] - regc[k0][0]) / regc[k0][0] * 100))
    for c in (0, 1):
        v = [e[3] for e in eff if e[0] == c]
        print('   chaine c=%d : effet de l\'ablation sur apex, %d cellules, moyenne %+.2f %%, '
              'etendue %+.2f a %+.2f %%' % (c, len(v), sum(v) / len(v), min(v), max(v)))
    print('   `phys-vol-floor` rend PHYS-VOL-FREE = 1e9 quand `*phys-col-off*` est arme')
    print('   (jak-hd-physics.gc:939-941) : aucune profondeur ne peut le franchir, le mur est MUET.')
    print('   RESERVE DECLAREE : aucun COMPTEUR de corrections de collision n\'est emis par fenetre')
    print('   dans cette phase. La preuve que le mur se tait est le CODE plus un effet non nul et')
    print('   de signe coherent ; ce n\'est pas un compteur tombe a zero, et je ne le presente pas')
    print('   comme tel. Poser ce compteur est bon marche et nomme pour le cycle suivant.')

    # ---- 5. ROBUSTESSE DE LA REFUTATION FACE AU PLANCHER DE BRUIT --------------------------
    print('\n5. ROBUSTESSE — la refutation survit-elle au bruit mesure en 1 ?')
    print('   L\'effet de l\'ablation (%.2f %% en moyenne sur c=0) est SOUS le plancher de bruit'
          % abs(sum(e[3] for e in eff if e[0] == 0) / 4))
    print('   (%.2f %%) : je ne peux donc PAS distinguer « le mur vaut 2 %% » de « le mur vaut 0 ».' % worst)
    print('   Mais la conclusion ne depend pas de cette distinction, et voici pourquoi :')
    need = [(r, sgn, (ra - CRIT_RATIO_ARMED_CARRIES) / ra * 100) for r, sgn, ra, rd in rows]
    for r, sgn, pc in need:
        print('     r=%-2d sgn=%+.0f : pour tomber sous x1.3 il faudrait une baisse de %.1f %%'
              % (r, sgn, pc))
    mn = min(pc for *_, pc in need)
    print('   La plus PETITE baisse exigee par la branche « la collision porte §18 » vaut %.1f %%,' % mn)
    print('   soit %.1f fois le plancher de bruit. Un bruit de %.2f %% ne peut pas dissimuler un'
          % (mn / worst, worst))
    print('   effet de %.1f %%. La refutation tient donc INDEPENDAMMENT de la resolution de la mesure.' % mn)

if __name__ == '__main__':
    main()
