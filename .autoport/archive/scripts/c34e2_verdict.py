#!/usr/bin/env python3
"""c34e2_verdict.py — le verdict des issues K1..K9 du cycle 34 etape 2, lu sur DEUX courses.

Il ne juge rien qu'il ne lise : chaque chiffre vient d'une ligne de trace ou de tableau, citee.
AVANT  = la course sans le mur (C34E2-REF), APRES = la course courante.
"""
import re
import sys

R = '.autoport/reports/Grecharged-secondary-motion/'
def rd(p):
    return open(R + p, errors='ignore').read()

before_log, after_log = rd('keira-room-x86.C34E2-REF.log'), rd('keira-room-x86.log')
before_tab, after_tab = rd('keira-room-table.C34E2-REF.txt'), rd('keira-room-table.txt')

def flesh(tab):
    """cdd par canal, depuis ROOM-RAD-FLESH."""
    out = {}
    for m in re.finditer(r'^ROOM-RAD-FLESH: chain=(\S+)\s+drive=(\S+)\s+l=(\d)\s+cdev=(\S+)\s+'
                         r'ctg=(\S+)\s+D=(\S+)\s+cdd=([\d.]+)', tab, re.M):
        out[(m.group(1), m.group(2), int(m.group(3)))] = dict(
            cdev=float(m.group(4)), ctg=float(m.group(5)), D=float(m.group(6)),
            cdd=float(m.group(7)))
    return out

def perlink_rrm(log):
    """`rrm`/`rrr` par (chaine, pilotage, maillon), a la fenetre dont `rrr` est le plus GRAND —
       meme appariement que le tableau, sans quoi on compare deux animations."""
    best = {}
    for m in re.finditer(r'^PHYSRADL c=(\d+) d=(\d+) l=(\d+) rrm=([-\d.e+]+) rrr=([-\d.e+]+)',
                         log, re.M):
        k = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
        rrr = float(m.group(5))
        if k not in best or rrr > best[k][1]:
            best[k] = (float(m.group(4)), rrr)
    return best

def one(pat, txt, g=1, cast=float):
    m = re.search(pat, txt, re.M)
    return cast(m.group(g)) if m else None

print('=' * 96)
print('VERDICT C34E2 — LE MUR DE DEPLACEMENT DE SA SPEC 21 SUR LE POINT LIBRE')
print('=' * 96)

# ---- K1 : le mur tire, et il se chiffre -------------------------------------------------------
wn = one(r'^PHYSLIMW wall_n=([\d.e+]+) wall_sum=([\d.e+]+)', after_log)
ws = one(r'^PHYSLIMW wall_n=[\d.e+]+ wall_sum=([\d.e+]+)', after_log)
print('\nK1  LE MUR TIRE ET IL SE CHIFFRE (SPEC 7)')
print('    wall_n   = %s morsures' % ('%d' % wn if wn is not None else 'ABSENT'))
print('    wall_sum = %s unites de jeu retirees (%s B0)'
      % ('%.1f' % ws if ws is not None else 'ABSENT',
         '%.2f' % (ws / 602.0) if ws else 'n/a'))
print('    -> %s' % ('CONFIRMEE' if (wn or 0) > 0 else '**REFUTEE — le mur n\'est pas arme**'))

# ---- K2 / K3 : l'etat rentre dans sa bande, et rien n'est retire sous le genou -----------------
fb, fa = flesh(before_tab), flesh(after_tab)
print('\nK2  L\'ETAT RENTRE DANS SA BANDE (cdd <= 0.42 B0 sur les 24 canaux)')
print('    %-12s %-11s l  %8s %8s   %s' % ('chaine', 'pilotage', 'AVANT', 'APRES', 'ecart'))
over = 0
for k in sorted(fa):
    if k not in fb:
        continue
    b, a = fb[k]['cdd'], fa[k]['cdd']
    if a > 0.42:
        over += 1
    print('    %-12s %-11s %d  %8.4f %8.4f   %+6.1f %%%s'
          % (k[0], k[1], k[2], b, a, 100.0 * (a - b) / max(1e-9, b),
             '   **AU-DESSUS DE 0.42**' if a > 0.42 else ''))
print('    -> %d canal(aux) sur %d au-dessus de 0.42 B0 : %s'
      % (over, len(fa), 'CONFIRMEE' if over == 0 else '**REFUTEE**'))

print('\nK3  RIEN N\'EST RETIRE SOUS LE GENOU (0.336 B0) — LA PREDICTION QUI COMMANDE')
k3ok = True
for k in [('chestL', 'BASE-0stim', 1), ('chestR', 'BASE-0stim', 1)]:
    if k in fb and k in fa:
        d = abs(fa[k]['cdd'] - fb[k]['cdd'])
        if d > 0.002:
            k3ok = False
        print('    %-12s l=%d  cdd AVANT %.4f  APRES %.4f  |ecart| %.4f  %s'
              % (k[0], k[2], fb[k]['cdd'], fa[k]['cdd'], d,
                 'INCHANGE' if d <= 0.002 else '**MORD SOUS LE GENOU**'))
idb, ida = one(r'^ROOM-IDLE: maxdev=([\d.]+)', before_tab), one(r'^ROOM-IDLE: maxdev=([\d.]+)', after_tab)
print('    ROOM-IDLE maxdev  AVANT %.4f  APRES %.4f' % (idb, ida))
print('    -> %s' % ('CONFIRMEE' if k3ok and ida <= 0.0002 else
                     '**REFUTEE — LE MECANISME DOIT ETRE RETIRE**'))

# ---- K4 : le consommateur redevient sensible --------------------------------------------------
print('\nK4  LE CONSOMMATEUR (`*phys-rrl*` -> le tenseur) REDEVIENT SENSIBLE AU STIMULUS')
DRV = {0: 'updown', 1: 'leftright', 2: 'accel', 3: 'jerk', 4: 'tilt', 5: 'BASE-0stim'}
CH = {0: 'chestL', 1: 'chestR'}
rb, ra = perlink_rrm(before_log), perlink_rrm(after_log)
k4ok = True
for c in (0, 1):
    for tag, src in (('AVANT', rb), ('APRES', ra)):
        base = src.get((c, 5, 1))
        jerk = src.get((c, 3, 1))
        if not base or not jerk:
            continue
        span = 100.0 * abs(jerk[0] - base[0]) / max(1e-9, base[0])
        print('    %-6s %-8s l=1  rrm BASE %.4f -> jerk %.4f  ECART %5.1f %%   '
              '(rrr brut %.4f -> %.4f, %+.0f %%)'
              % (CH[c], tag, base[0], jerk[0], span, base[1], jerk[1],
                 100.0 * (jerk[1] - base[1]) / max(1e-9, base[1])))
        if tag == 'APRES' and span < 20.0:
            k4ok = False
print('    -> %s (critere : ecart APRES > 20 %%)' % ('CONFIRMEE' if k4ok else '**REFUTEE**'))

# ---- K5 / K6 / K7 / K8 -------------------------------------------------------------------------
def comex(tab):
    return dict((m.group(1), float(m.group(2))) for m in
                re.finditer(r'^ROOM-COMEX: chain=(\S+)\s+comex=([\d.]+)', tab, re.M))
def perdrive(tab):
    """le tableau PAR PILOTAGE : c'est la ou tipvar/meshpen sont resolus, pas un agregat de course."""
    out = {}
    for m in re.finditer(r'^drive=(\S+)\s+windows=(\d+)\s+tipvar_max=([\d.]+)\s+'
                         r'tipvar_min=([\d.]+)\s+rootdev_max=([\d.]+)\s+meshpen_max=([-\d.]+)', tab, re.M):
        out[m.group(1)] = dict(tv=float(m.group(3)), tvmin=float(m.group(4)),
                               rd=float(m.group(5)), mp=float(m.group(6)))
    return out

def idledev(log):
    return dict((int(m.group(1)), float(m.group(2))) for m in
                re.finditer(r'^PHYSIDLE c=(\d+) dev=([\d.]+)', log, re.M))

cb, ca = comex(before_tab), comex(after_tab)
print('\nK5  SPEC 22 — `comex` BAISSE D\'AU MOINS 5 %% (plafond dur 0.40 B0)')
k5ok = True
for ch in sorted(ca):
    d = 100.0 * (ca[ch] - cb[ch]) / max(1e-9, cb[ch])
    if d > -5.0:
        k5ok = False
    print('    %-12s AVANT %.4f B0 (x%.2f)  APRES %.4f B0 (x%.2f)   %+6.1f %%'
          % (ch, cb[ch], cb[ch] / 0.40, ca[ch], ca[ch] / 0.40, d))
print('    -> %s' % ('CONFIRMEE' if k5ok else '**REFUTEE (publiee telle quelle)**'))

pb, pa = perdrive(before_tab), perdrive(after_tab)
print('\nK6  LE MOUVEMENT DE L\'OS N\'EST PAS MUSELE (|delta tipvar| <= 10 %), PAR PILOTAGE')
k6ok = True
for d in ('updown', 'leftright', 'accel', 'jerk', 'tilt'):
    if d not in pb or d not in pa:
        continue
    r = 100.0 * (pa[d]['tv'] - pb[d]['tv']) / max(1e-9, pb[d]['tv'])
    if abs(r) > 10.0:
        k6ok = False
    print('    tipvar_max %-10s AVANT %.4f  APRES %.4f   %+6.1f %%' % (d, pb[d]['tv'], pa[d]['tv'], r))
print('    -> %s' % ('CONFIRMEE' if k6ok else '**REFUTEE — COUT DECLARE**'))

print('\nK7  AUCUNE VITESSE CREEE — `PHYSIDLE dev` en pose FIGEE (unites de jeu, cible SPEC 9 = 0)')
ib, ia = idledev(before_log), idledev(after_log)
for c in sorted(ia):
    r = 100.0 * (ia[c] - ib[c]) / max(1e-9, ib[c])
    print('    %-12s AVANT %.4f  APRES %.4f   %+6.1f %%   %s'
          % (CH.get(c, 'c%d' % c), ib[c], ia[c], r,
             'dans +-5 %' if abs(r) <= 5.0 else '**HORS +-5 %% (vers la pose d\'auteur)**'
             if ia[c] < ib[c] else '**HORS +-5 %%**'))

print('\nK8  LES COUTS, PUBLIES A LA HAUSSE COMME A LA BAISSE')
for d in ('updown', 'leftright', 'accel', 'jerk', 'tilt'):
    if d not in pb or d not in pa:
        continue
    print('    meshpen_max %-10s AVANT %.4f  APRES %.4f   %+6.1f %%'
          % (d, pb[d]['mp'], pa[d]['mp'],
             100.0 * (pa[d]['mp'] - pb[d]['mp']) / max(1e-9, abs(pb[d]['mp']))))
for name, pat in (('franchissements', r'^ROOM-SIDE: chains=\d+/\d+ crossing=(\d+)'),
                  ('stretch max', r'^ROOM-STRETCH: max=([\d.]+)')):
    b, a = one(pat, before_tab), one(pat, after_tab)
    print('    %-16s AVANT %-10s APRES %-10s %s'
          % (name, b, a,
             ('%+.1f %%' % (100.0 * (a - b) / b)) if (b not in (None, 0) and a is not None) else ''))

n = sum(1 for _ in open('goal_src/jak1/pc/jak-hd-physics.gc'))
print('\nK9  CLEAN : le moteur fait %d lignes (plafond 4800) -> %s'
      % (n, 'CONFIRMEE' if n <= 4800 else '**REFUTEE**'))
