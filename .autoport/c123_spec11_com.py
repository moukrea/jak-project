#!/usr/bin/env python3
"""c123_spec11_com.py — LA CLAUSE DE COM DE SA 11, LUE SUR LE CENTRE DE MASSE.

DIRECTIVES vd9e8b66782 — perimetre Grecharged-secondary-motion, poitrine de Keira.

POURQUOI CE SCRIPT EXISTE.
La directive du 2026-08-23 16:00 pose en PRIORITE 1 : « les 6 miroirs (echelles de forme de §10 et
§11) : leur verdict doit se mesurer contre une grandeur INDEPENDANTE de l'entree du solveur, ou la
section repasse NON ETABLI ». §10 a deja sa route independante (`ROOM-SPEC10`, ses deux clauses de
COM). §11 ne l'avait pas : sa cellule PRONE est calculee par le meme bloc mais publiee
`DIAGNOSTIC — sans bande`, alors que sa prose lui donne une bande :

    l.178  « Static COM displacement: 20-28% B0, nominal 24% B0, upper static target 30% B0 »

CE QUE CE SCRIPT MESURE, ET SOUS QUELLE FORME.
  NATURE  : une LONGUEUR (norme d'un deplacement soutenu), en fraction de B0. Pas une variance.
            Le choix de la NORME n'est pas un gout : les deux clauses de §10 NOMMENT une direction
            (« toward thorax », « outward »), donc s'y lisent en PROJECTION ; la clause de §11 n'en
            nomme AUCUNE, donc s'y lit en NORME. Une projection lirait une clause non
            directionnelle comme une borne inferieure.
  REPERE  : la base de l'ANCRE (e0,e1,e2), celle de `PHYSORICOML` et de `PHYSDFMA` — le meme
            repere que `_spec10_block`, dont ce calcul est le PORTAGE et non une seconde version.
  BASE    : i=0 est la pose debout d'auteur, ou sa 9 exige 0.0000 ; elle est MESUREE ici.
  DEUX TERMES, PUBLIES SEPAREMENT : le SQUELETTIQUE (somme telescopique des `ldb`, ponderee par la
            masse) et le TENSORIEL (`L . (D - I)`, convention du moteur, cf. jak-hd-physics.gc:3922).

INDEPENDANCE DE L'ENTREE DU SOLVEUR — c'est la raison d'etre du cycle.
  `HangingCOMDisplacement` (0.24 chez Keira, 0.33 chez Maia) est `CANAL ABSENT` : aucun lecteur.
  La bande 0.20-0.28 B0 n'est donc centree sur AUCUN nombre donne au solveur, contrairement aux
  trois echelles de forme dont la bande est construite autour de la valeur injectee.

Usage : python3 .autoport/c123_spec11_com.py [log]
"""
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LOG = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    HERE, 'reports/Grecharged-secondary-motion/keira-room-x86.log')
MASS = os.path.join(HERE, 'reports/Grecharged-secondary-motion/breast-com-mass.json')

txt = open(LOG, encoding='utf-8', errors='replace').read()

# ---- noms de chaine ---------------------------------------------------------------------------
# MEME SOURCE QUE `physics_room_table.py:3931` : le fichier de donnees, dans l'ordre ou il
# declare les chaines — c'est l'ordre que le magasin C++ sert au moteur.
names = {}
for i, ln in enumerate(l for l in open(os.path.join(ROOT, 'recharged_assets/physics_chains.txt'),
                                       errors='ignore') if re.match(r'chain (\S+) ', l)):
    names[i] = re.match(r'chain (\S+) ', ln).group(1)

# ---- increments par maillon, en base d'ancre ----------------------------------------------------
ldb = {}
for m in re.finditer(r'^PHYSORICOML c=(\d+) i=(\d+) l=(\d+) dv=([-\d.e+]+)'
                     r' dap=([-\d.e+]+) dlat=([-\d.e+]+)', txt, re.M):
    # L'ORDRE COMPTE, et il est celui que `_spec10_block` a MESURE (physics_room_table.py:2699) :
    # `PHYSORICOML` publie dv/dap/dlat, qui sont les composantes sur les lignes rv=1/rap=2/rlat=0.
    # Le vecteur en base (e0,e1,e2) est donc `(dlat, dv, dap)`. Le prendre dans l'ordre publie
    # rend une projection FAUSSE d'un facteur 2,6 — verifie sur cette trace avant correction.
    ldb[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = (
        float(m.group(6)), float(m.group(4)), float(m.group(5)))

# ---- tenseur de deformation --------------------------------------------------------------------
dfma = {}
for m in re.finditer(r'^PHYSDFMA c=(\d+) i=(\d+) r=(\d+) m0=([-\d.e+]+) m1=([-\d.e+]+)'
                     r' m2=([-\d.e+]+)', txt, re.M):
    dfma.setdefault((int(m.group(1)), int(m.group(2))), [None] * 3)[int(m.group(3))] = [
        float(m.group(4)), float(m.group(5)), float(m.group(6))]
dfma = {k: v for k, v in dfma.items() if all(r is not None for r in v)}

# ---- deplacement d'APEX (pour la confrontation avec la borne superieure) -----------------------
com = {}
for m in re.finditer(r'^PHYSORICOM c=(\d+) i=(\d+) tx=([-\d.e+]+) ty=([-\d.e+]+) tz=([-\d.e+]+)',
                     txt, re.M):
    com[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)),
                                               float(m.group(5)))

# ---- B0 -----------------------------------------------------------------------------------------
b0 = {}
for m in re.finditer(r'^\[HD-PHYS\] b0 c=(\d+) flesh=([-\d.e+]+)', txt, re.M):
    b0[int(m.group(1))] = float(m.group(2))

# ---- role des cellules, DERIVE DE LA GRAVITE MESUREE (jamais d'une etiquette) -------------------
# PRONE = la cellule dont la gravite pointe vers l'AVANT du buste (+ saillie). On lit `PHYSORI4`,
# la meme source que `_ori_role_block`, et on exige que le maximum soit NET.
ori4 = {}
for m in re.finditer(r'^PHYSORI4 c=(\d+) i=(\d+) r0=([-\d.e+]+) r1=([-\d.e+]+) r2=([-\d.e+]+)',
                     txt, re.M):
    ori4[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)),
                                                float(m.group(5)))
# LE SENS DE LA LIGNE 2 EST MESURE SUR L'ANATOMIE, JAMAIS SUPPOSE : un sein FAIT SAILLIE, donc
# l'os de racine a une composante avant/arriere non nulle et son SIGNE dit ou pointe la ligne 2.
# Portage de `_ori_zsense` (physics_room_table.py:672). Sans lui, `argmax r2` designe SUPINE au
# lieu de PRONE — les deux cellules sont exactement opposees, et l'erreur est silencieuse.
_roots = {}
for m in re.finditer(r'^PHYSURST c=(\d+) l=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+)'
                     r' uz=([-\d.e+]+)', txt, re.M):
    if int(m.group(2)) == 0:
        _roots[int(m.group(1))] = float(m.group(5))
ZS = None
if _roots and min(abs(x) for x in _roots.values()) >= 0.03:
    _sg = {1 if x > 0 else -1 for x in _roots.values()}
    if len(_sg) == 1:
        ZS = float(next(iter(_sg)))

mass = json.load(open(MASS))
chains = sorted({c for (c, _i, _l) in ldb})

print('DIRECTIVES vd9e8b66782')
print('c123 — SPEC 11 : LA CLAUSE DE COM, LUE SUR LE CENTRE DE MASSE ET NON SUR L\'APEX')
print('source : %s' % os.path.relpath(LOG, ROOT))
print('bande citee VERBATIM : l.178 « Static COM displacement: 20-28%% B0, nominal 24%% B0,'
      ' upper static target 30%% B0 »')
print('')

# La cellule PRONE : gz maximal (l'axe 2 de PHYSORI4 est l'axe de saillie, cf. ROOM-ORIROLE-SENS).
IPRO = {}
for c in chains:
    cand = {i: v for (cc, i), v in ori4.items() if cc == c}
    if not cand:
        continue
    # PRONE = la gravite pointe vers l'AVANT du buste : composante `r2 * zs` maximale.
    best = max(cand, key=lambda i: cand[i][2] * ZS)
    vals = sorted((cand[i][2] * ZS for i in cand), reverse=True)
    IPRO[c] = (best, cand[best][2] * ZS, vals[1] if len(vals) > 1 else -9.0)

def cum(c, i, j):
    acc = [0.0, 0.0, 0.0]
    for l in range(j + 1):
        v = ldb.get((c, i, l))
        if v is None:
            return None
        for k in range(3):
            acc[k] += v[k]
    return acc

def com_vec(c, i, d):
    """Le deplacement de COM d'une frontiere d'organe : squelettique + tensoriel, en base d'ancre.
    PORTAGE EXACT de `_spec10_block` (physics_room_table.py:2925-2945) : meme ponderation, meme
    convention de multiplication du tenseur. Deux versions d'un meme calcul derivent ; celle-ci
    ne diverge pas, elle recopie."""
    d0, d1 = cum(c, i, 0), cum(c, i, 1)
    if d0 is None or d1 is None or (c, i) not in dfma:
        return None
    D = dfma[(c, i)]
    W, n, L = d['W'], float(d['n']), d['L']
    sk = [(W[0] * d0[k] + W[1] * d1[k]) / n for k in range(3)]
    tn = [sum((D[a][j] - (1.0 if a == j else 0.0)) * L[a] for a in range(3)) / n
          for j in range(3)]
    return sk, tn, [sk[k] + tn[k] for k in range(3)]

# ---- LES CELLULES A BANDE NON DIRECTIONNELLE ----------------------------------------------------
# Le choix de la NORME se decide clause par clause, sur le TEXTE de la clause :
#   §10 l.168/169 nomment une direction (« toward thorax », « outward ») -> PROJECTION (deja
#        publiee par ROOM-SPEC10, inchangee).
#   §11 l.178 « Static COM displacement: 20-28% B0 »        -> aucune direction nommee -> NORME
#   §12 l.192 « Global lateral COM response: 15-24% B0 »    -> aucune direction nommee -> NORME
# Le mot « Global » de §12 interdit meme explicitement de la lire sur un seul axe.
BANDES = {'PRONE': ('§11', 0.20, 0.28, 0.30, 'l.178 « Static COM displacement: 20-28% B0,'
                    ' nominal 24% B0, upper static target 30% B0 »'),
          'ROULIS': ('§12', 0.15, 0.24, None,
                     'l.192 « Global lateral COM response: 15-24% B0, nominal 19% »')}

def role_of(i, gvec):
    """Le role d'une cellule, DERIVE DE LA GRAVITE MESUREE. Meme test que `_ori_role_block` :
    la direction canonique la plus proche, avec une marge exigee sur la deuxieme."""
    gl, gd, gf = gvec[0], gvec[1], gvec[2] * ZS
    n = math.sqrt(gl * gl + gd * gd + gf * gf)
    if n < 0.5:
        return None, 0.0, 0.0
    gl, gd, gf = gl / n, gd / n, gf / n
    canon = (('DEBOUT', (0.0, 1.0, 0.0)), ('PRONE', (0.0, 0.0, 1.0)), ('SUPINE', (0.0, 0.0, -1.0)),
             ('ROULIS+90', (1.0, 0.0, 0.0)), ('ROULIS-90', (-1.0, 0.0, 0.0)),
             ('ROULIS+45', (0.7071, 0.7071, 0.0)), ('ROULIS-45', (-0.7071, 0.7071, 0.0)),
             ('AVANT45', (0.0, 0.7071, 0.7071)), ('ARRIERE45', (0.0, 0.7071, -0.7071)))
    sc = sorted((math.degrees(math.acos(max(-1.0, min(1.0, gl * v[0] + gd * v[1] + gf * v[2])))),
                 lab) for lab, v in canon)
    if sc[0][0] > 25.0 or (sc[1][0] - sc[0][0]) < 15.0:
        return None, sc[0][0], sc[1][0] - sc[0][0]
    return sc[0][1], sc[0][0], sc[1][0] - sc[0][0]

if ZS is None:
    print('SENS DE L\'AXE AVANT/ARRIERE NON RESOLU (PHYSURST) — aucun verdict publie.')
    sys.exit(0)
print('SENS DE LA LIGNE 2 DE L\'ANCRE, MESURE SUR L\'ANATOMIE (PHYSURST, os de racine) : zs=%+.0f'
      % ZS)
print('CANAL : `HangingCOMDisplacement`, `SideGravityCOM`, `SupineCOMDepth`, `SupineCOMLateral`')
print('  sont ABSENTS de `kPhysPresetKeys` (game/kernel/jak1/kmachine.cpp:1970-2022) : le solveur')
print('  ne les recoit PAS. La bande n\'est donc centree sur AUCUN nombre injecte — c\'est ce qui')
print('  distingue cette clause des six echelles de forme, dont la bande entoure l\'entree.')
print('')

for c in chains:
    nm = names.get(c, 'c%d' % c)
    rec = mass['chains'][nm]
    bb = b0.get(c, 602.0)
    ax = {k: [float(x) for x in rec['axes'][k]] for k in ('out', 'up', 'fwd')}
    thx = [-v for v in ax['fwd']]
    dot = lambda a, b: sum(a[k] * b[k] for k in range(3))

    # --- controle de montage, EN VECTEUR : meme test que _spec10_block (seuil declare 5 %) ------
    ctrl = {}
    for i in sorted({ii for (cc, ii, _l) in ldb if cc == c}):
        if (c, i, 0) not in ldb or (c, i, 1) not in ldb or (c, i) not in com:
            continue
        s_ = [ldb[(c, i, 0)][k] + ldb[(c, i, 1)][k] for k in range(3)]
        t_ = list(com[(c, i)])
        ns = math.sqrt(sum(x * x for x in s_)); nt = math.sqrt(sum(x * x for x in t_))
        den = max(ns, nt)
        if i != 0 and den > 1e-9:
            ctrl[i] = 100.0 * math.sqrt(sum((s_[k] - t_[k]) ** 2 for k in range(3))) / den

    r0 = com_vec(c, 0, rec['defs'][0])
    print('%-8s LIGNE DE BASE i=0 (pose debout d\'auteur, §9 exige 0.0000) : |d| = %.5f B0'
          % (nm, math.sqrt(sum(x * x for x in r0[2])) / bb if r0 else float('nan')))
    print('%-8s cellule                    frontiere |  |d|/B0 |  thorax  sortant     haut |'
          '  squel.    tens.' % nm)
    verdicts = {}
    for (cc, i), g in sorted(ori4.items()):
        if cc != c:
            continue
        lab, ecart, marge = role_of(i, g)
        if lab is None:
            continue
        fam = 'PRONE' if lab == 'PRONE' else ('ROULIS' if lab.startswith('ROULIS') and
                                              lab.endswith('90') else None)
        rows = []
        for d in rec['defs']:
            r = com_vec(c, i, d)
            if r is None:
                continue
            sk, tn, v = r
            rows.append(dict(cut=d['cut'], n=math.sqrt(sum(x * x for x in v)) / bb,
                             th=dot(v, thx) / bb, ou=dot(v, ax['out']) / bb, up=dot(v, ax['up']) / bb,
                             nsk=math.sqrt(sum(x * x for x in sk)) / bb,
                             ntn=math.sqrt(sum(x * x for x in tn)) / bb,
                             sk=sk, v=v))
        if not rows:
            continue
        tag = ('%s %s' % (BANDES[fam][0], lab)) if fam else ('%-4s %s' % ('--', lab))
        for r in rows:
            print('%-8s %-26s w>%.2f | %7.4f | %7.4f %8.4f %8.4f | %7.4f %8.4f  %s'
                  % (nm, tag, r['cut'], r['n'], r['th'], r['ou'], r['up'], r['nsk'], r['ntn'],
                     'CELLULE DU VERDICT' if fam else 'DIAGNOSTIC — clause directionnelle ou sans bande'))
        if not fam:
            continue
        sec, lo, hi, upper, cite = BANDES[fam]
        vals = [r['n'] for r in rows]
        spread = (max(vals) - min(vals)) / max(abs(v) for v in vals) * 100.0
        e = ctrl.get(i, 0.0) / 100.0
        lo_b = min(r['n'] - e * r['nsk'] for r in rows)
        hi_b = max(r['n'] + e * r['nsk'] for r in rows)
        vd = sorted({('SOUS' if v < lo else ('DANS' if v <= hi else 'AU-DESSUS'))
                     for v in vals + [lo_b, hi_b]})
        dom = abs(rows[0]['th']) / max(rows[0]['n'], 1e-12)
        print('%-8s   %s %s' % (nm, sec, cite))
        print('%-8s   part de l\'axe THORAX dans la norme (w>0.00) %.3f · SORTANT %.3f · HAUT %.3f'
              % (nm, dom, abs(rows[0]['ou']) / rows[0]['n'], abs(rows[0]['up']) / rows[0]['n']))
        print('%-8s   raffinement %.1f %% %s · montage %.2f %% -> pire cas [%.4f ; %.4f]'
              % (nm, spread, '(<=30 % OK)' if spread <= 30.0 else '(>30 % REJETE)',
                 ctrl.get(i, 0.0), lo_b, hi_b))
        if spread > 30.0:
            v_ = 'NON ETABLIE (raffinement)'
        elif len(vd) == 1:
            v_ = vd[0]
        else:
            v_ = 'INDETERMINEE — ' + '/'.join(vd)
        extra = ''
        if upper is not None:
            extra = ' · cible statique haute %.2f : %s' % (
                upper, 'FRANCHIE' if max(vals) > upper else 'non franchie')
        print('%-8s   VERDICT DE LA CLAUSE %s : %s%s' % (nm, sec, v_, extra))
        verdicts[(sec, i)] = v_
        t = com.get((c, i))
        if t:
            rr = None
            nt_ = math.sqrt(sum(x * x for x in t)) / bb
            print('%-8s   CONFRONTATION avec la BORNE SUPERIEURE d\'apex publiee par'
                  ' ROOM-ORICOM-SPEC : |t| seul = %.4f B0' % (nm, nt_))
    print('')
