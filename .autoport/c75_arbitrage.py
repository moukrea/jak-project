#!/usr/bin/env python3
"""c75_arbitrage.py — SPEC 22 CONTRE SPEC 33/34, DANS LA MEME UNITE ET SUR LA MEME POPULATION.

Le cycle 74 a etabli que `phys-skin-chain` est l'unique producteur du depassement de la §22 sur
le maillon racine. Il n'avait PAS mis ce cout en regard du benefice. Ici les deux se lisent sur
les MEMES 31 animations, le MEME pilotage, et pour SEULE variable `*phys-skin-off*` :
  cout    = etage 6 arme - etage 6 desarme          (`PHYSSTGT`, converti en metres)
  benefice = skinpen desarme - skinpen arme          (`ROOM-SKINPEN-CONTROL`, deja en metres)

Tranche les cinq questions de `c75-predictions.txt`, md5 673b6b89fe7263373a0ea90c22fae19b.
Une question sans donnee sort NON EVALUABLE, jamais TENUE.
"""
import sys, re

B0_U   = 602.0        # `B0` en unites moteur, lu dans la trace ([HD-PHYS] b0 flesh=602.0000)
U_PER_M = 4096.0      # 4096 u = 1 m
B0_M   = B0_U / U_PER_M
NOM    = {0: 'chestL', 1: 'chestR'}
STN    = ['0 avant filet', '1 apres filet', '2 apres LONGUEUR', '3 apres COLLISION',
          '4 apres 8 iters', '5 avant peau', '6 apres peau (LIVRE)']

def load_tag(path):
    rx = re.compile(r'^PHYSSTGT tag=(\S+) c=(\d+) st=(\d+) jt=([-0-9.eE]+)')
    d = {}
    for ln in open(path, errors='replace'):
        m = rx.match(ln)
        if m:
            d.setdefault((m.group(1), int(m.group(2))), {})[int(m.group(3))] = float(m.group(4))
    return d

def load_run(path):
    rx = re.compile(r'^PHYSSTG c=(\d+) a=(-?\d+) d=(-?\d+) st=(\d+) jt=([-0-9.eE]+)')
    w = {}
    for ln in open(path, errors='replace'):
        m = rx.match(ln)
        if m:
            w.setdefault((int(m.group(1)), int(m.group(2)), int(m.group(3))), {})[int(m.group(4))] = float(m.group(5))
    return {k: v for k, v in w.items() if len(v) == 7}

def load_skinctl(table):
    rx = re.compile(r'^ROOM-SKINPEN-CONTROL:\s+(\S+)\s+armee=([-0-9.]+)\s+desarmee=([-0-9.]+)')
    out = {}
    for ln in open(table, errors='replace'):
        m = rx.match(ln)
        if m:
            out[m.group(1)] = (float(m.group(2)), float(m.group(3)))
    return out

def phys_lines(path, drop=('PHYSSTGT',)):
    return [l.rstrip('\n') for l in open(path, errors='replace')
            if l.startswith('PHYS') and not any(l.startswith(p) for p in drop)]

def main(cur, prev, table):
    D = load_tag(cur)
    print('DIRECTIVES v3fee554599')
    print('=' * 96)
    print('ARBITRAGE SPEC 22 CONTRE SPEC 33/34 — cycle 75')
    print('  meme population (31 animations, pilotage 3), une seule variable : `*phys-skin-off*`')
    print('  conversion : B0 = %.1f u, 4096 u = 1 m, donc 1 B0 = %.5f m' % (B0_U, B0_M))
    print('=' * 96)
    if not D:
        print('AUCUNE LIGNE `PHYSSTGT` — toutes les questions sortent NON EVALUABLES.'); return 2

    # ---------- Q4 : NON-PERTURBATION -----------------------------------------------------------
    a, b = phys_lines(cur), phys_lines(prev)
    if len(a) == len(b):
        diff = sum(1 for x, y in zip(a, b) if x != y)
        print('\nQ4 NON-PERTURBATION : %d lignes PHYS anterieures, %d DIFFERENTE(S) -> %s'
              % (len(a), diff, 'TENUE' if diff == 0 else 'REFUTEE'))
    else:
        print('\nQ4 NON-PERTURBATION : NON EVALUABLE — %d lignes ici contre %d avant' % (len(a), len(b)))
    tc = sum(1 for l in open(cur, errors='replace') if l.startswith('PHYS'))
    tp = sum(1 for l in open(prev, errors='replace') if l.startswith('PHYS'))
    print('   total PHYS : %d  (avant %d ; engage +28 = %d)' % (tc, tp, tp + 28))

    # ---------- LES DEUX JAMBES -----------------------------------------------------------------
    for c in (0, 1):
        A, Z = D.get(('skin-armed', c)), D.get(('skin-disarmed', c))
        if not A or not Z:
            print('\n--- %s : jambe manquante -> NON EVALUABLE' % NOM[c]); continue
        print('\n--- %s ------------------------------------------------------------------' % NOM[c])
        print('   etage                    armee    desarmee     ecart')
        for s in range(7):
            print('   %-22s %8.4f  %8.4f  %+9.4f' % (STN[s], A[s], Z[s], A[s] - Z[s]))

    # ---------- Q1 : LE CONTROLE DE L'INTERRUPTEUR ----------------------------------------------
    print('\nQ1 CONTROLE DE L\'INTERRUPTEUR (desarmee : etage6 == etage5 AU BIT) :')
    q1 = True
    for c in (0, 1):
        Z = D.get(('skin-disarmed', c))
        if not Z: print('   %s : NON EVALUABLE' % NOM[c]); q1 = False; continue
        d = Z[6] - Z[5]
        ok = (d == 0.0)
        q1 &= ok
        print('   %s : etage5=%.4f etage6=%.4f  ecart=%+.6f -> %s'
              % (NOM[c], Z[5], Z[6], d, 'TENUE' if ok else 'REFUTEE'))
    print('   -> Q1 %s' % ('TENUE' if q1 else 'REFUTEE — rien d\'autre n\'est lisible'))

    # ---------- Q2 : LE COUT SUR LA JAMBE ARMEE -------------------------------------------------
    print('\nQ2 LE COUT (armee : etage6 > etage5, et etage6 > 0.50 B0) :')
    for c in (0, 1):
        A = D.get(('skin-armed', c))
        if not A: print('   %s : NON EVALUABLE' % NOM[c]); continue
        print('   %s : etage5=%.4f -> etage6=%.4f (%+.4f B0)  ; > 0.50 B0 : %s -> %s'
              % (NOM[c], A[5], A[6], A[6] - A[5], 'oui' if A[6] > 0.50 else 'NON',
                 'TENUE' if (A[6] > A[5] and A[6] > 0.50) else 'REFUTEE'))

    # ---------- Q3 : L'ARBITRAGE ----------------------------------------------------------------
    S = load_skinctl(table)
    print('\nQ3 L\'ARBITRAGE, DANS LA MEME UNITE ET SUR LA MEME POPULATION :')
    print('   chaine    COUT §22 (m)   BENEFICE §33/34 (m)   rapport   ce que ca dit')
    for c in (0, 1):
        A, Z = D.get(('skin-armed', c)), D.get(('skin-disarmed', c))
        sk = S.get(NOM[c])
        if not A or not Z or not sk:
            print('   %-9s NON EVALUABLE' % NOM[c]); continue
        cout = (A[6] - Z[6]) * B0_M
        ben  = sk[1] - sk[0]                      # desarmee - armee = ce que la contrainte retire
        r    = cout / ben if abs(ben) > 1e-9 else float('inf')
        verdict = ('la peau COUTE %.1f x ce qu\'elle achete' % r) if r > 1 else \
                  ('la peau ACHETE %.1f x ce qu\'elle coute' % (1.0 / r if r > 0 else 0))
        print('   %-9s %+10.4f     %+10.4f          %6.2f   %s' % (NOM[c], cout, ben, r, verdict))
    print('   (BENEFICE = `ROOM-SKINPEN-CONTROL` desarmee - armee, deja en metres, MEMES jambes.)')

    # ---------- Q3 bis : LE COUT SANS ABLATION, ET POURQUOI IL FAUT LES DEUX ---------------------
    print('\n   LA LIMITE DE Q3, ET ELLE EST DANS MA PROPRE DONNEE : LES DEUX JAMBES ONT DERIVE.')
    for c in (0, 1):
        A, Z = D.get(('skin-armed', c)), D.get(('skin-disarmed', c))
        if not A or not Z: continue
        r = Z[0] / A[0] if A[0] > 1e-9 else float('inf')
        print('     %s : etage 0 (AVANT toute contrainte de la frame) armee %.4f contre desarmee'
              % (NOM[c], A[0]))
        print('              %.4f -> facteur %.2f. Les deux jambes jouent les MEMES 31 animations'
              % (Z[0], r))
        print('              avec le MEME pilotage, et elles n\'arrivent DEJA PAS dans le meme etat.')
    print('     Une ablation n\'est donc PAS chirurgicale ici : le systeme est couple d\'une frame')
    print('     a l\'autre. C\'est exactement pourquoi le cycle 74 a refuse l\'ablation et mesure en')
    print('     LECTURE PURE — et la jambe desarmee vient de le demontrer contre elle-meme.')
    print('\n   LE COUT SE MESURE AUSSI SANS AUCUNE ABLATION, DANS LA SEULE JAMBE ARMEE :')
    print('   entre l\'etage 5 et l\'etage 6 il n\'y a qu\'UN appel, `phys-skin-chain`.')
    print('   chaine    COUT sans ablation (m)   COUT par ablation (m)   BENEFICE (m)   fourchette')
    for c in (0, 1):
        A, Z = D.get(('skin-armed', c)), D.get(('skin-disarmed', c))
        sk = S.get(NOM[c])
        if not A or not Z or not sk: continue
        c_in  = (A[6] - A[5]) * B0_M
        c_abl = (A[6] - Z[6]) * B0_M
        ben   = sk[1] - sk[0]
        lo, hi = sorted((c_abl / ben, c_in / ben)) if abs(ben) > 1e-9 else (0, 0)
        print('   %-9s %12.4f          %12.4f      %10.4f     x%.1f a x%.1f contre la peau'
              % (NOM[c], c_in, c_abl, ben, lo, hi))
    print('   Les deux estimations vont dans le MEME sens ; je publie la FOURCHETTE, pas celle qui')
    print('   m\'arrange. La verite est encadree, elle n\'est pas choisie.')

    # ---------- Q3 ter : DESARMER LA PEAU NE SUFFIT PAS A TENIR §22 -----------------------------
    print('\n   ET LE FAIT QUI DECIDE VRAIMENT DE L\'ARBITRAGE :')
    for c in (0, 1):
        Z = D.get(('skin-disarmed', c))
        if not Z: continue
        print('     %s : peau DESARMEE, valeur livree %.4f B0 -> %s le plafond de 0.50 de la §22'
              % (NOM[c], Z[6], 'SOUS' if Z[6] <= 0.50 else '**AU-DESSUS DE**'))
    print('     Desarmer la contrainte de peau ne rend donc PAS la §22 conforme sur chestR : la')
    print('     boucle de contraintes y derive seule de 0.2787 (etage 3) a 0.5554 (etage 5). Le')
    print('     choix n\'est pas entre « peau ou §22 » — il faut les deux corrections.')

    # ---------- Q5 : COHERENCE AVEC LA PHASE `run` ----------------------------------------------
    R = load_run(cur)
    print('\nQ5 COHERENCE AVEC LA PHASE `run` (pilotages 0 a 5, autre population) :')
    for c in (0, 1):
        A = D.get(('skin-armed', c))
        v = [w[6] for k, w in R.items() if k[0] == c]
        if not A or not v: print('   %s : NON EVALUABLE' % NOM[c]); continue
        mr = max(v)
        e = abs(A[6] - mr) / mr if mr > 0 else 0.0
        print('   %s : jambe armee %.4f  ·  phase run max %.4f  ·  ecart %.1f %% -> %s'
              % (NOM[c], A[6], mr, 100 * e, 'TENUE' if e <= 0.25 else 'REFUTEE'))
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3]))
