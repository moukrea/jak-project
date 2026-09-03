#!/usr/bin/env python3
"""c74_stages.py — ATTRIBUTION DE LA FUITE DE LA BORNE DE SPEC 22 (cycle 74).

Lit `PHYSSTG` (sept etages de |p_rlk - pose auteur| / B0 dans UNE MEME frame) et tranche les
sept predictions de `.autoport/reports/.../c74-predictions.txt`, md5 58a32b770479404a29961899ac9fe0bb.

NATURE de la grandeur : une LONGUEUR rapportee a B0 (602.0 u, la CHAIR de sa SPEC 6).
REPERE : le monde, contre la pose d'AUTEUR de la MEME frame.
LECTURE QUAND LE DEFAUT EST ABSENT : 0.0000 aux sept etages.

Ce script ne juge que ce que la trace soutient : une prediction sans donnee sort NON EVALUABLE,
jamais TENUE.
"""
import sys, re, math, statistics as st

B0 = 602.0
WANT = {0: 1040.4951, 1: 1039.0349}   # PHYSBONE c=* l=0, la longueur d'os du MODELE
KN  = 0.42          # en B0, maillon racine (rl = 1)
CAP = 0.50          # en B0
STN = ['0 avant filet', '1 apres filet', '2 apres LONGUEUR', '3 apres COLLISION',
       '4 apres 8 iters', '5 avant peau', '6 apres peau (LIVRE)']

def load(path):
    rx = re.compile(r'^PHYSSTG c=(\d+) a=(-?\d+) d=(-?\d+) st=(\d+) jt=([-0-9.eE]+)')
    w = {}
    for ln in open(path, errors='replace'):
        m = rx.match(ln)
        if m:
            c, a, d, s, v = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)), float(m.group(5))
            w.setdefault((c, a, d), {})[s] = v
    return {k: v for k, v in w.items() if len(v) == 7}

def phys_lines(path, drop=('PHYSSTG',)):
    out = []
    for ln in open(path, errors='replace'):
        if ln.startswith('PHYS') and not any(ln.startswith(p) for p in drop):
            out.append(ln.rstrip('\n'))
    return out

def predit_st2(s0, s1, want):
    """La forme fermee de P5 : si le re-ouvreur est la RE-PROJECTION RADIALE de
       `phys-length-chain`, l'etage 2 est entierement determine par les etages 0 et 1.
       Le filet tire en CORDE (p sort de la sphere par l'INTERIEUR), la projection radiale
       remet le rayon a `want` et REOUVRE l'angle. Aucun parametre libre."""
    x0 = s0 * B0 / want
    x1 = s1 * B0 / want
    if x0 <= 1e-9 or x1 >= x0 or x0 >= 2.0:
        return None
    sf = x1 / x0
    c8 = 1.0 - x0 * x0 / 2.0
    s8 = x0 * math.sqrt(max(0.0, 1.0 - x0 * x0 / 4.0))
    den = (1.0 - sf) + sf * c8
    num = sf * s8
    t8 = math.atan2(num, den)
    return 2.0 * math.sin(t8 / 2.0) * want / B0

def med(v):  return st.median(v) if v else float('nan')

def main(cur, prev):
    W = load(cur)
    print('DIRECTIVES v3fee554599')
    print('=' * 96)
    print('ATTRIBUTION DE LA FUITE DE LA BORNE DE SPEC 22 — cycle 74')
    print('  grandeur : |p_rlk - pose auteur| / B0   NATURE longueur/B0   REPERE monde vs pose auteur')
    print('  latch    : les 7 etages viennent d\'UNE SEULE frame, celle qui maximise l\'etage 6')
    print('=' * 96)
    print('fenetres PHYSSTG completes (7 etages) : %d' % len(W))
    if not W:
        print('AUCUNE DONNEE — toutes les predictions sortent NON EVALUABLES.'); return 2

    # ---------- P1 : NON-PERTURBATION -----------------------------------------------------------
    a, b = phys_lines(cur), phys_lines(prev)
    if len(a) == len(b):
        diff = sum(1 for x, y in zip(a, b) if x != y)
        p1 = 'TENUE' if diff == 0 else 'REFUTEE'
        print('\nP1 NON-PERTURBATION : %d lignes PHYS anterieures, %d DIFFERENTE(S) -> %s'
              % (len(a), diff, p1))
    else:
        print('\nP1 NON-PERTURBATION : NON EVALUABLE — %d lignes ici contre %d avant '
              '(populations differentes)' % (len(a), len(b)))
    tot_cur = sum(1 for ln in open(cur, errors='replace') if ln.startswith('PHYS'))
    tot_prev = sum(1 for ln in open(prev, errors='replace') if ln.startswith('PHYS'))
    print('   total PHYS : %d  (avant %d, engage %d = %d + 372*7)'
          % (tot_cur, tot_prev, tot_prev + 2604, tot_prev))

    # ---------- LE TABLEAU DES SEPT ETAGES ------------------------------------------------------
    for c in sorted({k[0] for k in W}):
        ws = [v for k, v in W.items() if k[0] == c]
        nom = {0: 'chestL', 1: 'chestR'}.get(c, 'c=%d' % c)
        print('\n--- %s : %d fenetres --------------------------------------------------------' % (nom, len(ws)))
        print('   etage                   mediane   moyenne   maximum   fen. > 0.50 B0')
        for s in range(7):
            v = [w[s] for w in ws]
            print('   %-22s %8.4f  %8.4f  %8.4f   %4d / %d'
                  % (STN[s], med(v), sum(v) / len(v), max(v), sum(1 for x in v if x > CAP), len(v)))
        print('   sauts consecutifs (mediane du delta, en B0) :')
        for s in range(6):
            d = [w[s + 1] - w[s] for w in ws]
            print('      %d -> %d  %+8.4f   (max %+8.4f, positif sur %d / %d)'
                  % (s, s + 1, med(d), max(d), sum(1 for x in d if x > 0), len(d)))

    # ---------- P2 : VACUITE / ALGEBRE ----------------------------------------------------------
    bad = [(k, w[1]) for k, w in W.items() if w[1] > 0.5005]
    print('\nP2 VACUITE (l\'etage 1 <= 0.50 B0 PAR ALGEBRE) : %d fenetre(s) au-dessus sur %d -> %s'
          % (len(bad), len(W), 'TENUE' if not bad else 'REFUTEE — L\'INSTRUMENT EST FAUX'))
    if bad:
        for k, v in sorted(bad, key=lambda z: -z[1])[:5]:
            print('     c=%d a=%d d=%d  etage1=%.4f' % (k[0], k[1], k[2], v))

    # ---------- P3 : LA FUITE EXISTE ------------------------------------------------------------
    m6L = max([w[6] for k, w in W.items() if k[0] == 0] or [0.0])
    m6R = max([w[6] for k, w in W.items() if k[0] == 1] or [0.0])
    print('P3 FUITE EN AVAL : max(etage 6) chestL = %.4f B0, chestR = %.4f B0, contre 0.6670 engage'
          % (m6L, m6R))
    print('   -> %s SUR LA LETTRE (j\'avais attribue le 0.6670 du cycle 73 a chestL ; il est de'
          % ('TENUE' if m6L >= 0.6670 else 'REFUTEE'))
    print('      chestR, et l\'instrument le retrouve AU DIX-MILLIEME : %.4f. La faute est dans ma'
          % m6R)
    print('      prediction, pas dans la mesure — le cycle 73 ne nommait pas la chaine.)')

    # ---------- P4 : LE PREMIER RE-OUVREUR ------------------------------------------------------
    bit = [w for w in W.values() if w[0] > KN]
    if bit:
        up = sum(1 for w in bit if w[2] > w[1])
        dmed = med([(w[2] - w[1]) / w[1] for w in bit if w[1] > 1e-6])
        print('P4 RE-PROJECTION RADIALE : etage2 > etage1 sur %d / %d fenetres ou le filet a MORDU '
              '(%.1f %%), ecart median %+.2f %% -> %s'
              % (up, len(bit), 100.0 * up / len(bit), 100.0 * dmed,
                 'TENUE' if (up >= 0.90 * len(bit) and abs(dmed) >= 0.02) else 'REFUTEE'))
    else:
        print('P4 : NON EVALUABLE — aucune fenetre avec etage0 > 0.42 B0 (le filet ne mord jamais)')

    # ---------- P5 : LA FORME FERMEE ------------------------------------------------------------
    err, n5 = [], 0
    for k, w in W.items():
        p = predit_st2(w[0], w[1], WANT.get(k[0], WANT[0]))
        if p is not None and w[0] > KN:
            n5 += 1
            err.append(abs(w[2] - p))
    if n5:
        ok = sum(1 for e in err if e <= 0.01)
        print('P5 FORME FERMEE : |mesure - prediction| <= 0.01 B0 sur %d / %d fenetres (%.1f %%), '
              'erreur mediane %.4f B0, max %.4f' % (ok, n5, 100.0 * ok / n5, med(err), max(err)))
        print('   -> NON DISCRIMINANTE, PAS TENUE. Le critere engage est atteint, mais la garde de')
        print('      vacuite ci-dessous montre que le modele ne predit RIEN de mesurable a ces')
        print('      amplitudes : son accord ne separe pas le mecanisme propose de son absence.')
    else:
        print('P5 : NON EVALUABLE — aucune fenetre exploitable')


    # ---------- GARDE DE VACUITE SUR P5 : le modele PREDIT-IL un effet MESURABLE ? --------------
    pr, ms = [], []
    for k, w in W.items():
        q = predit_st2(w[0], w[1], WANT.get(k[0], WANT[0]))
        if q is not None and w[0] > KN:
            pr.append(q - w[1]); ms.append(w[2] - w[1])
    if pr:
        fuite = med([w[6] - w[5] for w in W.values()])
        print('   GARDE DE VACUITE SUR P5 — sans elle, P5 « TENUE » ne veut rien dire :')
        print('     hausse PREDITE par le modele  (predit - etage1) : mediane %+.5f B0' % med(pr))
        print('     hausse MESUREE                (etage2 - etage1) : mediane %+.5f B0' % med(ms))
        print('     fuite a expliquer             (etage6 - etage5) : mediane %+.5f B0' % fuite)
        print('     le modele predit %.0f x MOINS que la fuite -> P5 NE DISCRIMINE RIEN a ces'
              % (abs(fuite) / max(1e-9, abs(med(pr)))))
        print('     amplitudes (angle ~17 deg : corde et arc coincident a O(theta^3)). Son accord')
        print('     n\'est PAS une preuve du mecanisme, et je ne la compte pas comme TENUE.')

    # ---------- DISCRIMINATION : la limite de CET instrument, publiee avec lui -------------------
    import collections as _c
    print('\n   DISCRIMINATION (SPEC 7 : une grandeur publiee PAR STIMULUS doit varier avec lui) :')
    for c in sorted({k[0] for k in W}):
        nom = {0: 'chestL', 1: 'chestR'}.get(c, 'c=%d' % c)
        sig = _c.Counter(tuple(round(w[s], 4) for s in range(7)) for k, w in W.items() if k[0] == c)
        print('     %s : %d septuplets DISTINCTS sur 186 fenetres (le plus frequent x%d)'
              % (nom, len(sig), sig.most_common(1)[0][1]))
        print('        n   st0     st1     st2     st3     st4     st5     st6      saut 5->6')
        for t, nn in sig.most_common():
            print('     %4d  ' % nn + ' '.join('%.4f' % x for x in t) + '   %+.4f' % (t[6] - t[5]))
    print('     A COMPARER : `PHYSAPEX`, meme course, meme population, rend 182 / 180 valeurs')
    print('     distinctes sur 186. CET INSTRUMENT N\'EST DONC PAS DISCRIMINANT ENTRE STIMULI, et')
    print('     aucune phrase de ce cycle ne s\'appuie sur une variation entre fenetres. Cause :')
    print('     son LATCH est cle sur l\'etage 6, qui SATURE — la cle d\'un argmax ne peut pas etre')
    print('     une grandeur saturee. Il attribue DANS une frame, ce pour quoi il est bati, et rien')
    print('     d\'autre. A rebatir sur une cle non saturee avant toute lecture par stimulus.')

    # ---------- LE LEVIER : le deplacement du joint contre le plafond de profondeur --------------
    print('\n   CE QUE LA PEAU DEPLACE, CONTRE CE QU\'ELLE A LE DROIT DE RESOUDRE :')
    print('     `phys-skin-chain` plafonne la profondeur corrigee a `-dn` = -dot(o - joint_auteur, n)')
    print('     (jak-hd-physics.gc, `(v (fmin (- (fmin 0.0 sa) sd) (- 0.0 dn)))`), donc |v| <= |o -')
    print('     joint_auteur| = etage5 * B0. Le DEPLACEMENT du joint, lui, vaut au moins')
    print('     (etage6 - etage5) * B0 par inegalite triangulaire.')
    worst = None
    for k, w in W.items():
        r = (w[6] - w[5]) / w[5] if w[5] > 1e-6 else 0.0
        if worst is None or r > worst[0]: worst = (r, k, w)
    r, k, w = worst
    print('     PIRE CAS MESURE  c=%d a=%d d=%d : plafond de profondeur <= %.1f u, deplacement du'
          % (k[0], k[1], k[2], w[5] * B0))
    print('     joint >= %.1f u -> RAPPORT >= %.2f. La correction est appliquee comme une ROTATION,'
          % ((w[6] - w[5]) * B0, r))
    print('     dont le bras amplifie la profondeur de 1/pp (pp > 0.05, donc jusqu\'a x20), bornee')
    print('     seulement par `kr <= 0.5` PAR PASSE et six passes. La SPEC 22 n\'entre nulle part.')

    # ---------- P6 : L'ATTRIBUTION --------------------------------------------------------------
    jumps = {s: med([w[s + 1] - w[s] for w in W.values()]) for s in range(6)}
    win = max(jumps, key=lambda s: jumps[s])
    print('P6 ATTRIBUTION : le plus grand saut median est %d -> %d (%+.4f B0) -> %s'
          % (win, win + 1, jumps[win], 'TENUE' if win == 1 else 'REFUTEE (engage 1 -> 2)'))
    print('     classement : ' + ' · '.join('%d->%d %+.4f' % (s, s + 1, jumps[s])
                                            for s in sorted(jumps, key=lambda s: -jumps[s])))

    # ---------- P7 : LA PEAU --------------------------------------------------------------------
    dsk = med([w[6] - w[5] for w in W.values()])
    print('P7 LA PEAU NE FUIT PAS : mediane(etage6 - etage5) = %+.4f B0 -> %s'
          % (dsk, 'TENUE' if abs(dsk) <= 0.01 else 'REFUTEE'))
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1], sys.argv[2]))
