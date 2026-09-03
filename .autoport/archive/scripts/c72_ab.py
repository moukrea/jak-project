#!/usr/bin/env python3
"""c72_ab.py — LA PAIRE APPARIEE DU CYCLE 72, evaluee contre les predictions ecrites d'avance.

    python3 .autoport/c72_ab.py <logA> <tableA> <logB> <tableB>

Ce script ne DECIDE rien : il repond, une par une, aux lignes de
`.autoport/reports/Grecharged-secondary-motion/c72-predictions.txt`
(md5 baab55be4a0e763f8c7772f990324e5c), et il ecrit TENUE / REFUTEE a cote de chacune.

NATURE des grandeurs comparees : toutes sont deja publiees par le moteur ou par
`physics_room_table.py` ; ce fichier n'en fabrique aucune. REPERE : celui que chaque ligne declare
la ou elle est produite. LIGNE DE BASE : la jambe ARMEE, qui est l'etat d'avant ce cycle.

POURQUOI UNE PAIRE ET PAS UNE COURSE. La salle est deterministe au bit (cycle 32, re-mesure au
cycle 71 : 0 ligne differente sur 43 254). Deux courses successives dont une seule chose change
donnent donc une attribution exacte — c'est la seule raison pour laquelle un `diff` de traces vaut
ici une mesure.
"""
import re
import sys


def rd(p):
    return open(p, errors='ignore').read()


def physlines(t):
    return [l for l in t.splitlines() if l.startswith('PHYS')]


def lim4(t):
    m = re.search(r'^PHYSLIM4 sat_n=([-\d.e+]+) sat_sum=([-\d.e+]+) stif_n=([-\d.e+]+)', t, re.M)
    return tuple(float(x) for x in m.groups()) if m else (None, None, None)


def tbl_axfit(t):
    """Les 18 lignes des trois impulsions isolees + les 6 du canal radial (3 axes x 2 chaines),
    cle -> f. Ma prediction ecrite disait « les 2 lignes du canal radial » : c'est FAUX, il y en a
    6 (le tableau en publie 3 par chaine). Le domaine du temoin est donc PLUS grand que ce que
    j'avais engage, pas plus petit — je le corrige ici plutot que de laisser le compte mentir."""
    d = {}
    # `:\s*\*?\s*` et pas `:\*?` — DEFAUT ATTRAPE PAR LE TEST A-CONTRE-A : les lignes NON etoilees
    # portent une espace apres le deux-points, donc seules les 6 etoilees etaient chargees et les
    # 12 autres disparaissaient EN SILENCE. Le temoin le plus fort du cycle aurait porte sur un
    # tiers de son domaine sans que rien ne le dise (`series-conflates-links`, encore).
    for m in re.finditer(r'^ROOM-AXFIT:\s*\*?\s*(\w+)\s+(\S+)\s+(\w+)\s+\d+\s+([\d.]+)', t, re.M):
        d['AXFIT %s %s %s' % (m.group(1), m.group(2), m.group(3))] = float(m.group(4))
    for m in re.finditer(r'^ROOM-AXFIT-RAD: chain=(\S+)\s+ax=(\w+).*?f=([\d.]+)', t, re.M):
        d['AXFIT-RAD %s %s' % (m.group(1), m.group(2))] = float(m.group(3))
    return d


def tbl_temoin(t):
    d = {}
    for m in re.finditer(r'^ROOM-REGLIM-TEMOIN: (\S+)\s+r=0 AUCUN PILOTAGE\s+perr=([\d.]+)', t, re.M):
        d[m.group(1)] = float(m.group(2))
    return d


def tbl_idle(t):
    m = re.search(r'^ROOM-IDLE: maxdev=([\d.]+)', t, re.M)
    return float(m.group(1)) if m else None


def tbl_perr(t):
    """cle (phase, chaine, r, occurrence) -> perr. Toutes les occurrences, jamais ecrasees."""
    d, seen = {}, {}
    for m in re.finditer(r'^ROOM-REGLIM: (\S+)\s+(\S+)\s+(\d+)\s+\S+\s+[\d.]+\s+([\d.]+)', t, re.M):
        k = (m.group(1), m.group(2), int(m.group(3)))
        seen[k] = seen.get(k, 0) + 1
        d[k + (seen[k],)] = float(m.group(4))
    return d


def tbl_apex(t):
    d = {}
    for m in re.finditer(r'^ROOM-REGB-APEX: (\S+)\s+(\d+)\s+(\S+)\s+([\d.]+)', t, re.M):
        d[(m.group(1), int(m.group(2)))] = float(m.group(4))
    return d


def tbl_drives(t):
    d = {}
    for m in re.finditer(r'^drive=(\w+)\s+windows=\d+\s+tipvar_max=([\d.]+) tipvar_min=([\d.]+)'
                         r' rootdev_max=([\d.]+) meshpen_max=([\d.]+)', t, re.M):
        d[m.group(1)] = tuple(float(x) for x in m.groups()[1:])
    return d


def geo(t):
    return [l for l in t.splitlines()
            if l.startswith(('PHYSBONE ', 'PHYSCHAIN ', 'PHYSJOINT '))]


def verdict(ok):
    return 'TENUE   ' if ok else 'REFUTEE '


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    la, ta, lb, tb = (rd(p) for p in sys.argv[1:5])
    REF = rd('.autoport/reports/Grecharged-secondary-motion/keira-room-x86.c71-ARMED.log')
    out = []
    A = out.append

    A('C72 — PAIRE APPARIEE, mur de force de §21 ARME (jambe A) contre DESARME (jambe B)')
    A('predictions : c72-predictions.txt md5 baab55be4a0e763f8c7772f990324e5c')
    A('')

    # ---- A1 : l'interrupteur arme est-il inerte ? ----------------------------------------------
    pr, pa = physlines(REF), physlines(la)
    n = min(len(pr), len(pa))
    diff = sum(1 for i in range(n) if pr[i] != pa[i])
    first = next((i for i in range(n) if pr[i] != pa[i]), None)
    A('A1  %s jambe A contre la reference c71 : %d lignes PHYS communes, %d DIFFERENTES'
      % (verdict(diff == 0 and len(pr) == len(pa)), n, diff))
    A('      (ref %d lignes, A %d lignes)%s'
      % (len(pr), len(pa),
         '' if first is None else '  premiere divergence a l\'index %d :\n      ref: %s\n      A  : %s'
         % (first, pr[first][:110], pa[first][:110])))
    if diff or len(pr) != len(pa):
        A('      >>> L\'INTERRUPTEUR ARME N\'EST PAS INERTE. Toute conclusion de la jambe B est NULLE.')
    A('')

    # ---- B1..B3 : les compteurs du limiteur ----------------------------------------------------
    sa, sma, sta = lim4(la)
    sb, smb, stb = lim4(lb)
    A('B1  %s stif_n  A=%.0f  B=%.0f   (engage : B = 0 EXACTEMENT)' % (verdict(stb == 0.0), sta, stb))
    A('B2  %s sat_n   A=%.0f  B=%.0f   (engage : B >= 45000, et surtout B > A)'
      % (verdict(sb is not None and sb >= 45000.0), sa, sb))
    A('B3  %s sat_sum A=%.0f  B=%.0f   (engage : B > A)'
      % (verdict(smb is not None and smb > sma), sma, smb))
    A('')

    # ---- W1 W2 W5 : les temoins --------------------------------------------------------------
    t1a, t1b = tbl_temoin(ta), tbl_temoin(tb)
    ok1 = bool(t1a) and all(abs(t1b.get(k, 9.9) - v) <= 0.010 for k, v in t1a.items())
    A('W1  %s temoin r=0 (AUCUN pilotage), engage |delta| <= 0.010 B0' % verdict(ok1))
    for k in sorted(t1a):
        A('      %-8s A=%.4f  B=%.4f  delta=%+.4f' % (k, t1a[k], t1b.get(k, float('nan')),
                                                      t1b.get(k, float('nan')) - t1a[k]))
    ia, ib = tbl_idle(ta), tbl_idle(tb)
    A('W2  %s ROOM-IDLE maxdev  A=%.4f  B=%.4f   (engage : B <= 0.001)'
      % (verdict(ib is not None and ib <= 0.001), ia if ia is not None else float('nan'),
         ib if ib is not None else float('nan')))
    ga, gb = geo(la), geo(lb)
    A('W5  %s lignes de GEOMETRIE (PHYSBONE/PHYSCHAIN/PHYSJOINT) : A=%d B=%d, %s'
      % (verdict(ga == gb), len(ga), len(gb), 'identiques' if ga == gb else 'DIFFERENTES'))
    A('')

    # ---- W3 W4 : les impulsions isolees, declarees « bande LINEAIRE » par le tableau -----------
    fa, fb = tbl_axfit(ta), tbl_axfit(tb)
    keys = sorted(set(fa) | set(fb))
    bad = [k for k in keys if abs(fb.get(k, 9.9) - fa.get(k, -9.9)) > 0.005]
    A('W3/W4 %s ROOM-AXFIT + ROOM-AXFIT-RAD : %d lignes, %d au-dela de 0.005 Hz'
      % (verdict(not bad and len(keys) == 24), len(keys), len(bad)))
    for k in keys:
        d = fb.get(k, float('nan')) - fa.get(k, float('nan'))
        A('      %-26s A=%6.3f  B=%6.3f  delta=%+.3f Hz%s'
          % (k, fa.get(k, float('nan')), fb.get(k, float('nan')), d, '   <-- BOUGE' if k in bad else ''))
    A('')

    # ---- B4 : la distribution de perr ----------------------------------------------------------
    pa_, pb_ = tbl_perr(ta), tbl_perr(tb)
    KN, FRZ = 0.42, 0.4992
    ka = sum(1 for v in pa_.values() if v > FRZ)
    kb = sum(1 for v in pb_.values() if v > FRZ)
    A('B4  %s fenetres avec perr > 0.4992 B0 : A=%d/%d  B=%d/%d   (engage : B > A)'
      % (verdict(kb > ka), ka, len(pa_), kb, len(pb_)))
    A('      au-dessus du genou 0.42 B0 : A=%d  B=%d'
      % (sum(1 for v in pa_.values() if v > KN), sum(1 for v in pb_.values() if v > KN)))
    com = sorted(set(pa_) & set(pb_))
    if com:
        dl = [(pb_[k] - pa_[k], k) for k in com]
        dl.sort()
        A('      %d cles communes · perr median A=%.4f B=%.4f · delta min %+.4f (%s) max %+.4f (%s)'
          % (len(com), sorted(pa_[k] for k in com)[len(com) // 2],
             sorted(pb_[k] for k in com)[len(com) // 2],
             dl[0][0], dl[0][1], dl[-1][0], dl[-1][1]))
        A('      cles communes INCHANGEES au 1e-4 pres : %d / %d'
          % (sum(1 for d, _ in dl if abs(d) < 1e-4), len(com)))
    A('')

    # ---- B5 : l'apex ---------------------------------------------------------------------------
    xa, xb = tbl_apex(ta), tbl_apex(tb)
    mxa = max(xa.values()) if xa else float('nan')
    mxb = max(xb.values()) if xb else float('nan')
    A('B5  %s apex max des fenetres PH-REGB : A=%.4f B0  B=%.4f B0   (engage : A < B < 0.70)'
      % (verdict(mxb > mxa and mxb < 0.70), mxa, mxb))
    for k in sorted(set(xa) & set(xb)):
        A('      %-8s r=%d  A=%.4f  B=%.4f  delta=%+.4f' % (k[0], k[1], xa[k], xb[k], xb[k] - xa[k]))
    A('')

    # ---- B6 B7 : mouvement et penetration ------------------------------------------------------
    da, db = tbl_drives(ta), tbl_drives(tb)
    up = sum(1 for k in da if k in db and db[k][0] > da[k][0])
    A('B6  %s tipvar_max monte sur %d des %d pilotages' % (verdict(up >= len(da) - 1), up, len(da)))
    for k in sorted(da):
        if k in db:
            A('      drive=%-10s tipvar_max A=%.4f B=%.4f (%+.1f %%) · meshpen_max A=%.4f B=%.4f'
              % (k, da[k][0], db[k][0], 100.0 * (db[k][0] / da[k][0] - 1.0) if da[k][0] else 0.0,
                 da[k][3], db[k][3]))
    pna = max((v[3] for v in da.values()), default=float('nan'))
    pnb = max((v[3] for v in db.values()), default=float('nan'))
    A('B7  %s meshpen max (DIAGNOSTIC, jamais un verdict) A=%.4f m  B=%.4f m   (engage : B > A)'
      % (verdict(pnb > pna), pna, pnb))
    A('')

    # ---- ou les deux courses divergent-elles pour la premiere fois ? ---------------------------
    pb2 = physlines(lb)
    n2 = min(len(pa), len(pb2))
    f2 = next((i for i in range(n2) if pa[i] != pb2[i]), None)
    same = sum(1 for i in range(n2) if pa[i] == pb2[i])
    A('AB  divergence A/B : %d lignes PHYS communes, %d identiques (%.1f %%)'
      % (n2, same, 100.0 * same / max(1, n2)))
    if f2 is not None:
        A('      premiere divergence a l\'index %d :' % f2)
        A('      A: %s' % pa[f2][:120])
        A('      B: %s' % pb2[f2][:120])

    print('\n'.join(out))


main()
