#!/usr/bin/env python3
"""C36E1 — LA NATURE DE L'ENTREE DE PRESSION DU TENSEUR (SPEC 23).

Lit la trace de la course et rend le verdict des predictions gravees dans
`.autoport/reports/Grecharged-secondary-motion/C36E1-pressure-nature-prediction.txt`
(md5 e1113259ddc2a314a78e6b774d9d6590), commit 585f19b1f2.

Ce script ne CHOISIT rien : chaque prediction porte son critere chiffre, ecrit avant la mesure,
et le verdict est une comparaison. Les valeurs gravees d'avance sont rappelees a cote de la mesure
pour que l'ecart soit lisible sans aller chercher le fichier.
"""
import re, sys, hashlib, os

AFT = sys.argv[1]
BEF = sys.argv[2] if len(sys.argv) > 2 else None

PRS_K, PRS_MAX, B0F, SWEEPS = 0.45, 0.25, 602.0, 45
CH = {0: 'chestL', 1: 'chestR'}
# mesures du cycle 35, citees comme reference (rapport du 19/08 08:56)
C35 = {0: dict(prsr=13.3807, meshpen_m=0.0952), 1: dict(prsr=15.2761, meshpen_m=0.0913)}

def read(p):
    with open(p, 'rb') as f:
        return f.read().decode('utf-8', 'replace')

txt = read(AFT)
out = []
A = out.append

def win(pat, txt, keys):
    """toutes les fenetres publiees pour un marqueur, indexees par (c, a, d)"""
    d = {}
    for m in re.finditer(pat, txt, re.M):
        g = m.groups()
        d[(int(g[0]), int(g[1]), int(g[2]))] = dict(zip(keys, [float(x) for x in g[3:]]))
    return d

s7 = win(r'^PHYSSHAPE7 c=(\d+) a=(\d+) d=(\d+) npf=([-\d.e+]+) pmax=([-\d.e+]+) psum=([-\d.e+]+)',
         txt, ('npf', 'pmax', 'psum'))
s8 = win(r'^PHYSSHAPE8 c=(\d+) a=(\d+) d=(\d+) lsw=([-\d.e+]+) dom=([-\d.e+]+)',
         txt, ('lsw', 'dom'))
s4 = win(r'^PHYSSHAPE4 c=(\d+) a=(\d+) d=(\d+) prsm=([-\d.e+]+) prsr=([-\d.e+]+)',
         txt, ('prsm', 'prsr'))
s5 = win(r'^PHYSSHAPE5 c=(\d+) a=(\d+) d=(\d+) dlr=([-\d.e+]+) dsat=([-\d.e+]+) nfr=([-\d.e+]+)',
         txt, ('dlr', 'dsat', 'nfr'))

A('=' * 96)
A('VERDICT C36E1 — LA NATURE DE L\'ENTREE DE PRESSION DU TENSEUR (SPEC 23)')
A('=' * 96)
A('trace : %s' % AFT)
A('fenetres : PHYSSHAPE7 %d · PHYSSHAPE8 %d · PHYSSHAPE4 %d · PHYSSHAPE5 %d'
  % (len(s7), len(s8), len(s4), len(s5)))
A('constantes livrees : PHYS-PRS-K = %.2f · PHYS-PRS-MAX = %.2f · b0f = %.1f u · balayages/frame = %d'
  % (PRS_K, PRS_MAX, B0F, SWEEPS))
A('')

if not s7:
    A('FAIL: la trace ne porte AUCUNE ligne PHYSSHAPE7. L\'instrument n\'a pas tourne.')
    print('\n'.join(out)); sys.exit(1)

# ---- pour chaque chaine, la fenetre ou `prsr` est maximal : c'est la fenetre de l'argmax de cl ---
worst = {}
for c in CH:
    ks = [k for k in s4 if k[0] == c]
    if not ks:
        continue
    k = max(ks, key=lambda k: s4[k]['prsr'])
    prsr = s4[k]['prsr']
    cl = prsr * B0F / PRS_K
    r7 = s7.get(k, {})
    r8 = s8.get(k, {})
    worst[c] = dict(k=k, prsr=prsr, cl=cl, **r7, **r8)

A('-- LA FENETRE DE CHAQUE CHAINE OU `prsr` EST MAXIMAL (donc l\'argmax de `cl`) ----------------')
A('   `cl` est RECALCULE depuis `prsr` par l\'identite du moteur : cl = prsr * b0f / PHYS-PRS-K.')
A('   chaine   a   d      prsr    x plafond        cl (u)      cl (m)     npf     pmax(u)    psum(u)  lsw    dom')
for c in sorted(worst):
    w = worst[c]
    A('   %-8s %-3d %-3d %9.4f  %8.2fx  %11.1f  %8.3f  %6.0f  %10.1f %10.1f  %4.0f %6.0f'
      % (CH[c], w['k'][1], w['k'][2], w['prsr'], w['prsr'] / PRS_MAX, w['cl'], w['cl'] / 4096.0,
         w.get('npf', -1), w.get('pmax', -1), w.get('psum', -1), w.get('lsw', -1), w.get('dom', -1)))
A('')

def verdict(name, title, ok, detail):
    A('%-4s %s' % (name, title))
    for d in detail:
        A('     ' + d)
    A('     -> %s' % ('CONFIRMEE' if ok else '**REFUTEE**'))
    A('')
    return ok

res = {}

# ---------------- P1 : npf >= 20 sur les deux chaines ----------------
det, ok1 = [], True
det.append('CRITERE GRAVE : npf >= 20 sur LES DEUX chaines. VALEUR GRAVEE : entre 30 et 90.')
for c in sorted(worst):
    n = worst[c].get('npf', -1)
    det.append('%-8s npf = %-8.0f  (cl/meshpen du cycle 35 = %.1f, balayages = %d)'
               % (CH[c], n, (C35[c]['prsr'] * B0F / PRS_K) / (C35[c]['meshpen_m'] * 4096.0), SWEEPS))
    if not n >= 20:
        ok1 = False
det.append('valeur gravee tenue (30..90) : ' +
           ', '.join('%s %s' % (CH[c], 'oui' if 30 <= worst[c].get('npf', -1) <= 90 else 'NON')
                     for c in sorted(worst)))
res['P1'] = verdict('P1', 'LA NATURE DE `cl` EST UNE SOMME, PAS UNE PROFONDEUR', ok1, det)

# ---------------- P2 : pmax <= 0.25 * cl ----------------
det, ok2 = [], True
det.append('CRITERE GRAVE : pmax <= 0.25 * cl sur les deux chaines. VALEUR GRAVEE : 200..900 u.')
for c in sorted(worst):
    w = worst[c]
    pm, cl = w.get('pmax', -1), w['cl']
    det.append('%-8s pmax = %-9.1f u   0.25*cl = %-9.1f u   pmax/cl = %.4f   (meshpen c35 = %.1f u)'
               % (CH[c], pm, 0.25 * cl, pm / cl if cl else -1, C35[c]['meshpen_m'] * 4096.0))
    if not pm <= 0.25 * cl:
        ok2 = False
det.append('valeur gravee tenue (200..900 u) : ' +
           ', '.join('%s %s' % (CH[c], 'oui' if 200 <= worst[c].get('pmax', -1) <= 900 else 'NON')
                     for c in sorted(worst)))
res['P2'] = verdict('P2', 'UN EVENEMENT SEUL EST DE L\'ORDRE DE LA PENETRATION, PAS DE `cl`', ok2, det)

# ---------------- P3 : psum / cl <= 2.0 ----------------
det, ok3 = [], True
det.append('CRITERE GRAVE : psum / cl <= 2.0 sur les deux chaines. Donnee a 60/40 dans le contrat.')
det.append('psum est la somme des MODULES, cl le module de la somme VECTORIELLE : leur rapport EST')
det.append('la mesure de l\'annulation entre poussees. > 3 = ping-pong entre volumes.')
for c in sorted(worst):
    w = worst[c]
    ps, cl = w.get('psum', -1), w['cl']
    det.append('%-8s psum = %-11.1f u   cl = %-11.1f u   psum/cl = %.4f' % (CH[c], ps, cl, ps / cl if cl else -1))
    if not (cl and ps / cl <= 2.0):
        ok3 = False
res['P3'] = verdict('P3', 'LES POUSSEES VONT DANS LE MEME SENS — REPETITION, PAS PING-PONG', ok3, det)

# ---------------- P4 : lsw >= 40 ----------------
det, ok4 = [], True
det.append('CRITERE GRAVE : lsw >= 40 sur les deux chaines (sur %d balayages).' % SWEEPS)
for c in sorted(worst):
    l = worst[c].get('lsw', -1)
    det.append('%-8s lsw = %-5.0f / %d' % (CH[c], l, SWEEPS))
    if not l >= 40:
        ok4 = False
res['P4'] = verdict('P4', 'LA BOUCLE DE CONTRAINTES NE CONVERGE PAS', ok4, det)

# ---------------- P5 : le domaine, sans critere ----------------
A('P5   LE DOMAINE (aucun critere — engagement de publication)')
for c in sorted(worst):
    nfr = None
    ks = [k for k in s5 if k[0] == c]
    if ks:
        nfr = max(s5[k]['nfr'] for k in ks)
    dom_tot = sum(s8[k]['dom'] for k in s8 if k[0] == c)
    A('     %-8s frames avec une poussee sur le maillon pointe, cumulees sur toutes les fenetres :'
      ' %-12.0f' % (CH[c], dom_tot))
    A('     %-8s max de `nfr` (denominateur commun publie) sur une fenetre : %s'
      % (CH[c], ('%.0f' % nfr) if nfr is not None else 'non publie'))
A('')

# ---------------- l'arbitrage des trois hypotheses, ecrit d'avance ----------------
A('-- LES TROIS HYPOTHESES GRAVEES, ARBITREES PAR LES CRITERES CI-DESSUS ------------------------')
if not res['P1']:
    A('   H-DEEP : npf est petit -> le contact est REELLEMENT profond, `pr0` a 61x est une vraie')
    A('            mesure, et le remede de NATURE est ABANDONNE (table de branches, cas 3).')
elif not res['P3']:
    A('   H-PING : psum >> cl -> deux volumes se disputent le lien. La cause CANDIDATE annoncee par')
    A('            le cycle 35 (les deux volumes redondants) est la BONNE, et mon classement etait')
    A('            faux : le point 2 du plan passe devant le point 1 (table de branches, cas 2).')
else:
    A('   H-REP  : npf grand, psum ~ cl -> la MEME poussee est repetee a chaque balayage. `cl` est')
    A('            une LONGUEUR DE CHEMIN de corrections, pas une profondeur : la NATURE de')
    A('            l\'entree est fausse (table de branches, cas 1).')
    if not res['P4']:
        A('   RESERVE : P4 casse (lsw < 40) — la boucle converge, donc le rapport 46-55 n\'est PAS')
        A('            explique en entier par la repetition. Je le publie comme incomplet.')
A('')

# ---------------- P0 : inertie de l'instrument ----------------
A('P0   L\'INSTRUMENT EST-IL INERTE ?')
if not BEF:
    A('     pas de trace AVANT fournie — non evalue.')
else:
    b = read(BEF)
    NEW = ('PHYSSHAPE7', 'PHYSSHAPE8')
    # lignes exclues : les marqueurs neufs, et les six lignes dont un champ SANS ECRIVAIN est retire
    CHANGED = ('PHYSDIAG ', 'PHYSDIAG7 ', 'PHYSORICTL3 ', 'PHYSLIM ', 'PHYSLIM2 ', 'PHYSLIM3 ')
    def phys(t, drop):
        return [l for l in t.split('\n')
                if l.startswith('PHYS') and not any(l.startswith(d) for d in drop)]
    la = phys(txt, NEW + CHANGED)
    lb = phys(b, NEW + CHANGED)
    diff = sum(1 for x, y in zip(la, lb) if x != y) + abs(len(la) - len(lb))
    A('     %d lignes `PHYS` hors marqueurs neufs et hors les 6 lignes dont un champ sans ecrivain'
      % len(la))
    A('     est retire, %d differente(s) de la reference' % diff)
    # et la preuve separee : les deux lignes ou seul un champ part doivent coincider champ par champ
    def strip_field(lines, field):
        return [re.sub(r' %s=[-\d.e+]+' % field, '', l) for l in lines]
    for mk, fld in (('PHYSDIAG ', 'retreat'), ('PHYSORICTL3 ', 'retreat'), ('PHYSLIM ', None)):
        sa = [l for l in txt.split('\n') if l.startswith(mk)]
        sb = [l for l in b.split('\n') if l.startswith(mk)]
        if fld:
            sb2 = strip_field(sb, fld)
        else:
            sb2 = [re.sub(r'retreat_n=[-\d.e+]+ retreat_sum=[-\d.e+]+ ', '', l) for l in sb]
        d2 = sum(1 for x, y in zip(sa, sb2) if x != y) + abs(len(sa) - len(sb2))
        A('     %-13s prive du champ retire : %d ligne(s) contre %d, %d differente(s)'
          % (mk.strip(), len(sa), len(sb2), d2))
    A('     -> %s' % ('CONFIRMEE' if diff == 0 else '**REFUTEE**'))
A('')
A('PHYSEND : %s' % ('oui' if 'PHYSEND' in txt else 'NON — course tronquee'))
A('=' * 96)
print('\n'.join(out))
