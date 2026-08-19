#!/usr/bin/env python3
"""C36E2 — LA PRESSION DE CONTACT DEVIENT UNE INTENSITE (SPEC 23).

Verdict des predictions gravees dans `C36E2-intensity-prediction.txt`
(md5 e71a32e37e4b7eb6a922c0d5e72dc622), commit 2e7ea82c50 — avant la moindre ligne du mecanisme.

usage : c36e2_verdict.py <log-apres> <log-avant>
"""
import re, sys

AFT, BEF = sys.argv[1], sys.argv[2]
PRS_MAX, B0F = 0.25, 602.0
CH = {0: 'chestL', 1: 'chestR'}
DRIVE = {0: 'updown', 1: 'leftright', 2: 'accel', 3: 'jerk', 4: 'tilt', 5: 'BASE-0stim'}
# references gravees (cycle 35 etape 3 pour psat/nfr, cycle 35 etape 2 pour |dp|)
PSAT_REF = {0: 37.0, 1: 28.7}
DP_REF = 0.2614

def read(p):
    return open(p, 'rb').read().decode('utf-8', 'replace')

def win(pat, txt, keys):
    d = {}
    for m in re.finditer(pat, txt, re.M):
        g = m.groups()
        d[(int(g[0]), int(g[1]), int(g[2]))] = dict(zip(keys, [float(x) for x in g[3:]]))
    return d

P4 = r'^PHYSSHAPE4 c=(\d+) a=(\d+) d=(\d+) prsm=([-\d.e+]+) prsr=([-\d.e+]+)'
P5 = r'^PHYSSHAPE5 c=(\d+) a=(\d+) d=(\d+) dlr=([-\d.e+]+) dsat=([-\d.e+]+) nfr=([-\d.e+]+)'
P6 = r'^PHYSSHAPE6 c=(\d+) a=(\d+) d=(\d+) psat=([-\d.e+]+)'
P7 = r'^PHYSSHAPE7 c=(\d+) a=(\d+) d=(\d+) npf=([-\d.e+]+) pmax=([-\d.e+]+) psum=([-\d.e+]+)'
P8 = r'^PHYSSHAPE8 c=(\d+) a=(\d+) d=(\d+) lsw=([-\d.e+]+) dom=([-\d.e+]+)'
CD = r'^PHYSCOMD c=(\d+) a=(\d+) d=(\d+) tp=([-\d.e+]+) rp=([-\d.e+]+) dp=([-\d.e+]+)'
CW = r'^PHYSCOMW c=(\d+) a=(\d+) d=(\d+) comex=([-\d.e+]+)'
RW = r'^PHYSROW k=(\d+) amp=([-\d.e+]+) root=([-\d.e+]+) pen=([-\d.e+]+) jump=([-\d.e+]+)'

def load(p):
    t = read(p)
    return dict(txt=t,
                s4=win(P4, t, ('prsm', 'prsr')), s5=win(P5, t, ('dlr', 'dsat', 'nfr')),
                s6=win(P6, t, ('psat',)), s7=win(P7, t, ('npf', 'pmax', 'psum')),
                s8=win(P8, t, ('lsw', 'dom')), cd=win(CD, t, ('tp', 'rp', 'dp')),
                cw=win(CW, t, ('comex',)))

A_, B_ = load(AFT), load(BEF)
out = []
A = out.append

A('=' * 96)
A("VERDICT C36E2 — LA PRESSION DE CONTACT DEVIENT UNE INTENSITE (SPEC 23)")
A('=' * 96)
A('APRES : %s   (%d fenetres PHYSSHAPE4)' % (AFT, len(A_['s4'])))
A('AVANT : %s   (%d fenetres PHYSSHAPE4)' % (BEF, len(B_['s4'])))
A('')

def mx(d, c, k):
    v = [r[k] for kk, r in d.items() if kk[0] == c and k in r]
    return max(v) if v else float('nan')

def verdict(name, title, ok, det):
    A('%-4s %s' % (name, title))
    for x in det:
        A('     ' + x)
    A('     -> %s' % ('CONFIRMEE' if ok else '**REFUTEE**'))
    A('')
    return ok

res = {}

# ---- R0 : le canal d'ETIREMENT est intact ----
det, ok = [], True
det.append('CRITERE : `dlr` max et `nfr` max identiques a 4 decimales sur les deux chaines.')
for c in CH:
    da, db = mx(A_['s5'], c, 'dlr'), mx(B_['s5'], c, 'dlr')
    na, nb = mx(A_['s5'], c, 'nfr'), mx(B_['s5'], c, 'nfr')
    det.append('%-8s dlr max %.4f -> %.4f   |   nfr max %.0f -> %.0f' % (CH[c], db, da, nb, na))
    if round(da, 4) != round(db, 4) or round(na, 4) != round(nb, 4):
        ok = False
res['R0'] = verdict('R0', "LE CHANGEMENT EST CONFINE AU CANAL DE PRESSION", ok, det)

# ---- R1 : prsr <= 5.0 ----
det, ok = [], True
det.append('CRITERE : `prsr` max <= 5.0 sur les deux chaines. ESTIMATION GRAVEE : 0.4507 / 0.3803.')
GRAV = {0: 0.4507, 1: 0.3803}
for c in CH:
    a, b = mx(A_['s4'], c, 'prsr'), mx(B_['s4'], c, 'prsr')
    det.append('%-8s prsr max %9.4f (%.2fx) -> %9.4f (%.2fx)   estimation gravee %.4f  ecart %+.1f %%'
               % (CH[c], b, b / PRS_MAX, a, a / PRS_MAX, GRAV[c],
                  100.0 * (a - GRAV[c]) / GRAV[c] if GRAV[c] else 0))
    if not a <= 5.0:
        ok = False
res['R1'] = verdict('R1', "L'ENTREE TOMBE DE 53-61x A MOINS DE 5x", ok, det)

# ---- R2 : psat/nfr <= 10 % ----
det, ok = [], True
det.append('CRITERE : psat/nfr <= 10 %% sur les deux chaines. ESTIMATION GRAVEE : 2 %% a 8 %%.')
det.append('psat et nfr sont cumules sur TOUTES les fenetres — meme denominateur des deux cotes.')
for c in CH:
    for tag, D in (('AVANT', B_), ('APRES', A_)):
        ps = sum(r['psat'] for k, r in D['s6'].items() if k[0] == c)
        nf = sum(r['nfr'] for k, r in D['s5'].items() if k[0] == c)
        pct = 100.0 * ps / nf if nf else float('nan')
        det.append('%-8s %s  psat=%-12.0f nfr=%-12.0f  %6.2f %%' % (CH[c], tag, ps, nf, pct))
        if tag == 'APRES' and not pct <= 10.0:
            ok = False
    det.append('%-8s reference gravee du cycle 35 etape 3 : %.1f %%' % (CH[c], PSAT_REF[c]))
res['R2'] = verdict('R2', "L'ECRETAGE S'EFFONDRE", ok, det)

# ---- R3 : le canal devient discriminant ----
det, ok = [], True
det.append('CRITERE (a) au moins une fenetre avec prsm < 0.2500 STRICTEMENT, sur chaque chaine ;')
det.append('CRITERE (b) etendue relative de `prsm` max entre les six pilotages >= 25 %% sur au')
det.append('            moins une chaine (seuil du contrat SPEC 7). Aujourd\'hui elle vaut 0 %%.')
oka, spans = True, {}
for c in CH:
    for tag, D in (('AVANT', B_), ('APRES', A_)):
        w = {k: r for k, r in D['s4'].items() if k[0] == c}
        below = sum(1 for r in w.values() if r['prsm'] < 0.25 - 1e-9)
        bydr = {}
        for k, r in w.items():
            bydr[k[2]] = max(bydr.get(k[2], 0.0), r['prsm'])
        hi, lo = (max(bydr.values()), min(bydr.values())) if bydr else (0, 0)
        span = 100.0 * (hi - lo) / hi if hi else 0.0
        if tag == 'APRES':
            spans[c] = span
            if below == 0:
                oka = False
        det.append('%-8s %s  prsm < 0.2500 sur %3d/%d fenetres   par pilotage : %s   etendue %5.1f %%'
                   % (CH[c], tag, below, len(w),
                      ' '.join('%s=%.4f' % (DRIVE.get(d, d), v) for d, v in sorted(bydr.items())),
                      span))
okb = any(v >= 25.0 for v in spans.values())
det.append('(a) %s   (b) %s  (etendue max mesuree %.1f %%)'
           % ('tenue' if oka else '**CASSEE**', 'tenue' if okb else '**CASSEE**',
              max(spans.values()) if spans else 0))
res['R3'] = verdict('R3', "LE CANAL DEVIENT DISCRIMINANT", oka and okb, det)

# ---- R4 : le tenseur pese moins, MAIS PAS TROP ----
det, ok = [], True
det.append('CRITERE BILATERAL : moyenne |dp| en baisse de 20 %% a 60 %%. Plus de 60 %% = ECHEC')
det.append('(canal eteint, « ballons durs » que l\'owner a refuses le 2026-08-11 21:20).')
for tag, D in (('AVANT', B_), ('APRES', A_)):
    vals = [abs(r['dp']) / B0F for r in D['cd'].values()]
    tp = [abs(r['tp']) / B0F for r in D['cd'].values()]
    rp = [abs(r['rp']) / B0F for r in D['cd'].values()]
    det.append('%s  moyennes en B0 sur %d fenetres :  |tp| %.4f   |rp| %.4f   |dp| %.4f'
               % (tag, len(vals), sum(tp) / len(tp), sum(rp) / len(rp), sum(vals) / len(vals)))
dpa = sum(abs(r['dp']) / B0F for r in A_['cd'].values()) / max(1, len(A_['cd']))
dpb = sum(abs(r['dp']) / B0F for r in B_['cd'].values()) / max(1, len(B_['cd']))
drop = 100.0 * (dpb - dpa) / dpb if dpb else 0
det.append('|dp| %.4f -> %.4f B0 = %+.1f %%   (reference gravee du cycle 35 : %.4f B0)'
           % (dpb, dpa, -drop, DP_REF))
ok = 20.0 <= drop <= 60.0
if drop > 60.0:
    det.append('**PLUS DE 60 %% : c\'est un ECHEC declare d\'avance, pas un succes.**')
res['R4'] = verdict('R4', "LE TENSEUR PESE MOINS DANS SA SPEC 22 — MAIS PAS TROP", ok, det)

# ---- R5 : le mouvement subtil ----
det, ok = [], True
det.append('CRITERE : `tipvar` max sur `tilt` (d=4) et `updown` (d=0), les deux chaines, +-15 %%.')
# `tipvar` vit dans PHYSROW, dont la cle k encode (chaine, animation, pilotage) : la salle publie
# `PHYSKEY maxanim= drives=` pour la decoder. Meme decodage que physics_room_table.py:1444-1447.
def rowsk(t):
    kk = re.search(r'^PHYSKEY maxanim=(\d+) drives=(\d+)', t, re.M)
    if not kk:
        return []
    ma, nd = int(kk.group(1)), int(kk.group(2))
    o = []
    for a, b, c2, d, e, f in re.findall(
            r'^PHYSROW k=(\d+) amp=([-\d.e+]+) root=([-\d.e+]+) pen=([-\d.e+]+)'
            r' jump=([-\d.e+]+) ns=([-\d.e+]+)', t, re.M):
        k = int(a)
        o.append(dict(c=k // (nd * ma), ai=(k // nd) % ma, dr=k % nd,
                      amp=float(b) / 4096.0, root=float(c2) / 4096.0,
                      pen=float(d) / 4096.0, jump=float(e) / 4096.0))
    return o
rka, rkb = rowsk(A_['txt']), rowsk(B_['txt'])
if rka and rkb:
    for c in CH:
        for d in (0, 4):
            va = max([r['amp'] for r in rka if r['c'] == c and r['dr'] == d] or [0])
            vb = max([r['amp'] for r in rkb if r['c'] == c and r['dr'] == d] or [0])
            ch = 100.0 * (va - vb) / vb if vb else 0
            det.append('%-8s %-10s tipvar max %.4f -> %.4f  (%+.1f %%)' % (CH[c], DRIVE[d], vb, va, ch))
            if abs(ch) > 15.0:
                ok = False
else:
    det.append('PHYSKEY ou PHYSROW absent — non evalue.')
    ok = False
res['R5'] = verdict('R5', "LE MOUVEMENT SUBTIL N'EST PAS MUSELE", ok, det)

# ---- R6 : les couts, dans les deux sens ----
A('R6   LES COUTS, DANS LES DEUX SENS (aucun critere : engagement de publication)')
def rows(t):
    return [dict(k=int(a), amp=float(b), root=float(c), pen=float(d), jump=float(e))
            for a, b, c, d, e in re.findall(RW, t, re.M)]
ra, rb = rows(A_['txt']), rows(B_['txt'])
for key, lab in (('pen', 'meshpen'), ('root', 'rootdev'), ('jump', 'pire saut'), ('amp', 'tipvar')):
    va = max(r[key] for r in ra) if ra else 0
    vb = max(r[key] for r in rb) if rb else 0
    A('     %-12s max (u) %10.4f -> %10.4f   (%+.1f %%)   = %.4f m -> %.4f m'
      % (lab, vb, va, 100.0 * (va - vb) / vb if vb else 0, vb / 4096.0, va / 4096.0))
for c in CH:
    ca, cb = mx(A_['cw'], c, 'comex'), mx(B_['cw'], c, 'comex')
    ma = [r['comex'] for k, r in A_['cw'].items() if k[0] == c]
    mb = [r['comex'] for k, r in B_['cw'].items() if k[0] == c]
    A('     %-8s comex max %.4f -> %.4f B0 (%+.1f %%)   moyenne %.4f -> %.4f B0 (%+.1f %%)'
      % (CH[c], cb, ca, 100.0 * (ca - cb) / cb if cb else 0,
         sum(mb) / len(mb), sum(ma) / len(ma),
         100.0 * (sum(ma) / len(ma) - sum(mb) / len(mb)) / (sum(mb) / len(mb))))
for c in CH:
    la, lb = mx(A_['s8'], c, 'lsw'), mx(B_['s8'], c, 'lsw')
    A('     %-8s lsw max %.0f -> %.0f  (la NON-CONVERGENCE n\'est PAS traitee ici, et ne doit pas'
      ' bouger)' % (CH[c], lb, la))
for mk in ('ROOM-IDLE', 'PHYSIDLE'):
    for tag, D in (('AVANT', B_), ('APRES', A_)):
        ls = [l for l in D['txt'].split('\n') if l.startswith(mk)]
        if ls:
            A('     %-9s %s : %s' % (mk, tag, ' | '.join(ls[:2])[:150]))
A('')
A('PHYSEND : APRES %s · AVANT %s'
  % ('oui' if 'PHYSEND' in A_['txt'] else 'NON', 'oui' if 'PHYSEND' in B_['txt'] else 'NON'))
A('')
A('-- LA TABLE DE BRANCHES GRAVEE, APPLIQUEE ---------------------------------------------------')
if res.get('R1') and res.get('R2') and res.get('R3') and res.get('R4'):
    A('   le canal de PRESSION de sa SPEC 23 est REPARE : une intensite bornee par un garde-fou au')
    A('   lieu d\'un chemin de corrections ecrete en permanence. Chantier suivant : la NON-CONVERGENCE.')
else:
    if res.get('R1') and res.get('R2') and not res.get('R3'):
        A('   R3 CASSEE alors que R1 et R2 tiennent -> ce n\'etait PAS le plafond qui rendait le canal')
        A('   aveugle : la grandeur elle-meme ne depend pas du stimulus. JE N\'ANNONCE PAS §23 REPAREE,')
        A('   et le prochain travail est de mesurer de quoi `pmax` depend.')
    if not res.get('R4'):
        A('   R4 hors bande -> soit le tenseur ne tirait pas sa deformation de la pression (baisse')
        A('   < 20 %%), soit JE VIENS D\'ETEINDRE LE CANAL (baisse > 60 %%), ce qui est un ECHEC declare')
        A('   d\'avance. Voir le chiffre ci-dessus, il tranche lequel des deux.')
    if not res.get('R1'):
        A('   R1 CASSEE -> `pmax` est lui aussi enorme : une seule poussee suffit a exploser le')
        A('   plafond, donc H-DEEP est partiellement vraie contre le verdict de l\'etape 1.')
A('=' * 96)
print('\n'.join(out))
