#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CYCLE 119 — CLASSER LA FILE DE LA DIRECTIVE DU 2026-08-22 23:00, PAR PREUVE.
DIRECTIVES vd9e8b66782

Le cycle 118b a laisse la file a 21 cles en declarant que 21 est un MAJORANT : « les bornes
SCALAIRES sont de la MEME nature que les 14 — mais un scalaire ne se prouve pas par un tuple,
et 0.50 apparait 67 fois dans l'instrument ». Ce script fournit les preuves qui manquaient.
Aucune n'est un jugement : chacune est une propriete VERIFIABLE du document, de l'arithmetique,
ou de la source de l'instrument. FAIL-CLOSED : sans preuve, une cle reste `CANAL ABSENT`.

  P-PROSE      la valeur de la cle apparait dans la PROSE de sa section comme le nominal (ou le
               bord) d'une PLAGE, et le NOM de la cle n'est PAS sur cette ligne. Discriminant
               teste dans les deux sens : les cles que le document NOMME sur sa ligne de prose
               (SupineProjectionScale, HangingLengthScale...) sont exactement celles qui sont
               deja cablees comme entrees. Une valeur ecrite sans son nom est une REPONSE
               ATTENDUE ; une valeur ecrite avec son nom est un REGLAGE que le document pose.
  P-GROUPE     la cle est sous `# DYNAMIC RESPONSE`, en-tete ECRIT PAR L'OWNER et IDENTIQUE
               entre les deux presets : le groupe des reponses attendues par regime.
  P-APPROX     la ligne porte `≈` et non `=`, sur LES DEUX presets : le document marque
               lui-meme la grandeur comme derivee.
  P-IDENTITE   la valeur se recalcule depuis d'autres cles, ET l'ecrit du document est le
               resultat ARRONDI A SA PROPRE PRECISION. Verifie sur LES DEUX presets : deux
               points independants, pas une coincidence de cadrage.
  P-DOUBLON    meme valeur qu'une cle DEJA CABLEE, sur LES DEUX presets.
  P-INSTRUMENT la valeur est un litteral de `physics_room_table.py`, sur une ligne de CODE, a
               +-3 lignes d'une citation du § DE LA CLE (la section est deduite du NOM pour le
               groupe DYNAMIC RESPONSE : Jump->14, Landing->16, LinearAccel->17, Yaw->18).

BLOC B — LA MEME PREUVE, RETOURNEE SUR LES CLES DEJA CABLEES. Une cle a la fois LUE PAR LE
SOLVEUR et SEUIL DE VERDICT dans l'instrument republie sa cible : c'est la definition que la
directive du 2026-08-22 22:50 donne de `TAUTOLOGIQUE`. Le cycle 109b a annonce que descendre
les constantes du moteur vers le fichier faisait disparaitre la tautologie « par construction ».
Ce bloc teste cette affirmation au lieu de la reprendre.
"""
import re, math, hashlib, os
from collections import Counter

SPEC  = 'SPEC-breast-softbody.md'
INSTR = '.autoport/physics_room_table.py'
KMACH = 'game/kernel/jak1/kmachine.cpp'
CHAN  = '.autoport/reports/Grecharged-secondary-motion/preset-channels.md'
md5 = lambda p: hashlib.md5(open(p,'rb').read()).hexdigest()[:12]
lines = open(SPEC, encoding='utf-8').read().split('\n')

# ------------------------------------------------------------------ presets
def parse_block(a, b):
    out, group = {}, None
    for n in range(a, b+1):
        s = lines[n-1].strip()
        if s.startswith('#'):
            g = s.lstrip('#').strip()
            if g and set(g) - set('= '):
                group = g
            continue
        m = re.match(r'^([A-Za-z]\w+)\s+([=≈]|>=)\s*(.+)$', s)
        if not m: continue
        name, sign, rest = m.groups()
        toks = re.findall(r'\d+(?:\.\d+)?', rest)
        out[name] = dict(sign=sign, raw=rest, line=n, group=group,
                         rng=('–' in rest), nums=[float(t) for t in toks],
                         txt=[t for t in toks])
    return out

def expand(d):
    o = {}
    for k, v in d.items():
        if v['rng'] and len(v['nums']) >= 2:
            o[k+'Lo'] = dict(v, val=v['nums'][0], wtxt=v['txt'][0])
            o[k+'Hi'] = dict(v, val=v['nums'][1], wtxt=v['txt'][1])
        elif v['nums']:
            o[k] = dict(v, val=v['nums'][0], wtxt=v['txt'][0])
        else:
            o[k] = dict(v, val=None, wtxt='')
    return o

KE, MA = expand(parse_block(449, 553)), expand(parse_block(921, 1025))
PK = {k: v['val'] for k, v in KE.items() if v['val'] is not None}
PM = {k: v['val'] for k, v in MA.items() if v['val'] is not None}

# ------------------------------------------------------------------ cles cablees
km  = open(KMACH, encoding='utf-8').read()
blk = km.split('static const char* kPhysPresetKeys[] = {')[1].split('\n};')[0]
WIRED = re.findall(r'"([A-Za-z]\w+)"', blk)

# ------------------------------------------------------------------ section de chaque cle
sec_of, cur = {}, None
for n, L in enumerate(lines, 1):
    m = re.match(r'^## (\d+)\.', L)
    if m: cur = int(m.group(1))
    sec_of[n] = cur
GROUP_SEC = {'MORPHOLOGY':[5,6],'PRIMARY DYNAMICS':[24,25,26],'SUPINE EQUILIBRIUM':[10],
             'HANGING EQUILIBRIUM':[11],'SIDE-GRAVITY EQUILIBRIUM':[12],
             'DYNAMIC RESPONSE':[14,16,17,18],'SOFT LIMITS':[22],'ANISOTROPY':[29],
             'ATTACHMENT':[30,31],'COLLISION':[33,34],'GARMENT':[7],
             'SECONDARY TISSUE MODE':[36],'EFFECTIVE PRIMARY VERTICAL SPRING':[24,28],
             'SOLVER':[37]}
REGIME = [('Jump',14), ('Landing',16), ('LinearAccel',17), ('Yaw',18)]
def secs_of(k):
    g = KE[k]['group']
    if g == 'DYNAMIC RESPONSE':
        for tag, s in REGIME:
            if tag in k: return [s]
    return GROUP_SEC.get(g, [])

# ------------------------------------------------------------------ P-PROSE
PROSE_END = 448
def prose_hit(k):
    """la valeur dans la prose de la section de la cle, sur une ligne de PLAGE, nom present ?"""
    base = re.sub(r'(Lo|Hi)$', '', k)
    v = PK.get(k)
    if v is None: return None
    targets = secs_of(k)
    cand = []
    pcts = {('%g' % (v*100)), ('%g' % v), KE[k]['wtxt']}
    for n in list(range(1, PROSE_END)) + list(range(556, 920)):
        if sec_of[n] not in targets: continue
        L = lines[n-1]
        if not any(re.search(r'(?<![\d.])' + re.escape(p) + r'(?![\d])', L) for p in pcts):
            continue
        pct = any(re.search(r'(?<![\d.])' + re.escape(q) + r'\s*%', L) for q in pcts)
        cand.append(dict(line=n, txt=L.strip(), named=(base in L), pct=pct,
                         rng=bool(re.search(r'\d\s*(–|—|-|to)\s*[−–+-]?\s*\d', L))))
    named = [c for c in cand if c['named']]
    if named: return named[0]            # le document NOMME la cle : c'est un REGLAGE qu'il pose
    cand = [c for c in cand if c['rng']]  # sinon il faut une PLAGE : une reponse attendue
    if not cand: return None
    for c in cand:                       # preferer la ligne ou la valeur est le NOMINAL
        if any(re.search(r'(nominal|=)\s*~?\s*' + re.escape(p) + r'%?', c['txt'])
               for p in pcts): return c
    return cand[0]

# ------------------------------------------------------------------ P-INSTRUMENT
ins = open(INSTR, encoding='utf-8').read().split('\n')

# LE LITTERAL DOIT ETRE DU CODE, PAS DE LA PROSE. `physics_room_table.py` IMPRIME son rapport
# avec `A('...')` et des docstrings : un nombre ecrit LA est du TEXTE de rapport, jamais un
# seuil. Sans ce filtre le test rend 19 tautologies dont la plupart sont des phrases.
# On retire donc (a) les blocs entre triples quotes, (b) les commentaires, (c) TOUT contenu
# entre guillemets. Ce qui reste est du code executable.
_TQ = re.compile(r'"""|\'\'\'')
_STR = re.compile(r'"(?:[^"\\\\]|\\\\.)*"|\'(?:[^\'\\\\]|\\\\.)*\'')
CODE, _in = [], False
for L in ins:
    q = len(_TQ.findall(L))
    if _in:
        CODE.append('')
        if q % 2: _in = False
        continue
    if q % 2:
        CODE.append(_STR.sub('', L.split(_TQ.search(L).group(0))[0].split('#')[0])); _in = True
        continue
    CODE.append(_STR.sub('', L.split('#')[0]))

def instrument_sites(v, secs, name=None):
    pats = {('%g' % v)} | {('%.*f' % (d, v)) for d in (2, 3, 4)}
    hits = []
    for i, L in enumerate(ins):
        code = CODE[i]
        if not code.strip(): continue
        if not any(re.search(r'(?<![\d.])' + re.escape(p) + r'(?![\d])', code) for p in pats):
            continue
        win = '\n'.join(ins[max(0, i-3):i+4])
        if name and name in win:
            hits.append((i+1, 'NOM', L.strip()[:100])); continue
        for s in secs:
            if re.search(r'§\s*' + str(s) + r'\b', win) or re.search(r"'%d'" % s, win):
                hits.append((i+1, s, L.strip()[:100])); break
    return hits

# ------------------------------------------------------------------ P-IDENTITE
def bounce(z): return math.exp(-math.pi*z/math.sqrt(1-z*z))
def kstiff(p): return p['MassPerBreast']*(2*math.pi*p['GlobalFrequencyVertical'])**2
IDENT = {
 'VerticalEffectiveMass':      ('MassPerBreast', lambda p: p['MassPerBreast']),
 'VerticalEffectiveStiffness': ('MassPerBreast x (2.pi.GlobalFrequencyVertical)^2', kstiff),
 'VerticalEffectiveDamping':   ('2.GlobalDampingRatio.sqrt(k.m)',
     lambda p: 2*p['GlobalDampingRatio']*math.sqrt(kstiff(p)*p['MassPerBreast'])),
 'FirstBounceRatio':           ('exp(-pi.z/sqrt(1-z^2)), z = GlobalDampingRatio',
     lambda p: bounce(p['GlobalDampingRatio'])),
 'NominalVolumePerBreast':     ('MassPerBreast / densite (§5 l.104 : 0,93-0,98, nominal 0,95)',
     lambda p: p['MassPerBreast']/0.95),
 'GlobalFrequencyAP':          ('GlobalFrequencyVertical / sqrt(APCompliance)  [§24 contre §29]',
     lambda p: p['GlobalFrequencyVertical']/math.sqrt(p['APCompliance'])),
 'GlobalFrequencyLateral':     ('GlobalFrequencyVertical / sqrt(LateralCompliance)  [§24 contre §29]',
     lambda p: p['GlobalFrequencyVertical']/math.sqrt(p['LateralCompliance'])),
}
def written_prec(txt):
    return len(txt.split('.')[1]) if '.' in txt else 0
def round_match(k, calc, d):
    """le document ecrit-il EXACTEMENT l'arrondi du calcul, a sa propre precision ?"""
    return ('%.*f' % (written_prec(d[k]['wtxt']), calc)).rstrip() == \
           ('%.*f' % (written_prec(d[k]['wtxt']), d[k]['val']))

# ------------------------------------------------------------------ etat courant (118b)
CUR = {}
for L in open(CHAN, encoding='utf-8'):
    m = re.match(r'^\|\s*`([A-Za-z]\w+)`\s*\|[^|]*\|[^|]*\|\s*(oui|non)\s*\|\s*\*\*([^*]+)\*\*', L)
    if m: CUR[m.group(1)] = dict(etat=m.group(3).strip(), differe=(m.group(2) == 'oui'))
QUEUE = sorted(k for k, v in CUR.items() if v['etat'] == 'CANAL ABSENT' and v['differe'])

print('CYCLE 119 — CLASSEMENT DE LA FILE DE LA DIRECTIVE DU 2026-08-22 23:00, PAR PREUVE')
print('DIRECTIVES vd9e8b66782\n')
print('PROVENANCE — ce tableau decrit CES fichiers-la, et l\'empreinte le prouve :')
for p in (SPEC, INSTR, KMACH, CHAN):
    print('  %-28s %s' % (os.path.basename(p), md5(p)))
print('  cles du preset : KEIRA %d · MAIA %d   ·   cablees (kPhysPresetKeys) : %d'
      % (len(KE), len(MA), len(WIRED)))
print('\nFILE LAISSEE PAR LE CYCLE 118b : %d cles `CANAL ABSENT` dont la valeur DIFFERE,'
      ' declaree MAJORANT.\n' % len(QUEUE))

def analyse(k):
    pr, secs = [], secs_of(k)
    ph = prose_hit(k)
    if ph and not ph['named']:
        pr.append(('P-PROSE', 'la valeur est ecrite dans la prose de §%d (l.%d) comme le nominal '
                   'ou le bord d\'une PLAGE, SANS le nom de la cle : « %s »'
                   % (sec_of[ph['line']], ph['line'], ph['txt'][:88])))
    elif ph and ph['named']:
        pr.append(('P-PROSE-NOMMEE', 'la prose de §%d (l.%d) NOMME la cle sur la ligne : « %s » '
                   '-> le document la pose comme REGLAGE'
                   % (sec_of[ph['line']], ph['line'], ph['txt'][:88])))
    if KE[k]['group'] == 'DYNAMIC RESPONSE':
        pr.append(('P-GROUPE', 'sous `# DYNAMIC RESPONSE` (KEIRA l.488, MAIA l.960), en-tete de '
                   'l\'owner identique dans les deux presets : les reponses attendues par regime'))
    if KE[k]['sign'] == '≈' and MA[k]['sign'] == '≈':
        pr.append(('P-APPROX', 'le document ecrit `≈` et non `=` sur LES DEUX presets '
                   '(KEIRA l.%d, MAIA l.%d)' % (KE[k]['line'], MA[k]['line'])))
    if k in IDENT:
        expr, f = IDENT[k]
        rk, rm = f(PK), f(PM)
        ek, em = abs(rk-PK[k])/abs(PK[k]), abs(rm-PM[k])/abs(PM[k])
        exact = round_match(k, rk, KE) and round_match(k, rm, MA)
        pr.append(('P-IDENTITE' if exact else 'P-IDENTITE(ecart)',
                   '%s -> KEIRA %.4f contre %s ecrit (%.2f %%) · MAIA %.4f contre %s ecrit (%.2f %%)%s'
                   % (expr, rk, KE[k]['wtxt'], 100*ek, rm, MA[k]['wtxt'], 100*em,
                      '  [l\'ecrit EST l\'arrondi du calcul a la precision du document]' if exact else '')))
    for w in WIRED:
        if w != k and w in PK and w in PM and abs(PK[w]-PK[k]) < 1e-12 and abs(PM[w]-PM[k]) < 1e-12:
            pr.append(('P-DOUBLON', 'meme valeur que `%s` (DEJA CABLEE) sur LES DEUX presets : '
                       '%.4g / %.4g' % (w, PK[k], PM[k]))); break
    h = instrument_sites(PK[k], secs) if PK.get(k) is not None else []
    if h:
        n, s, t = h[0]
        pr.append(('P-INSTRUMENT', 'litteral %g sur une ligne de CODE de physics_room_table.py:%d, '
                   'dans la fenetre d\'une citation de §%d — %s   [%d site(s)]'
                   % (PK[k], n, s, t, len(h))))
    return pr

ORD = ['P-PROSE','P-PROSE-NOMMEE','P-GROUPE','P-APPROX','P-IDENTITE','P-IDENTITE(ecart)',
       'P-DOUBLON','P-INSTRUMENT']
def klass(pr):
    t = [x for x, _ in pr]
    if 'P-IDENTITE' in t:                        return 'REDONDANTE (identite exacte)'
    if 'P-PROSE' in t or 'P-GROUPE' in t:        return 'CIBLE DE VERDICT (reponse attendue)'
    if 'P-INSTRUMENT' in t:                      return 'CIBLE DE VERDICT (instrument)'
    if 'P-APPROX' in t or 'P-DOUBLON' in t:      return 'REDONDANTE (marquee par le document)'
    if 'P-PROSE-NOMMEE' in t:                    return 'BOUTON (le document le NOMME sur sa ligne)'
    if 'P-IDENTITE(ecart)' in t:                 return 'SUR-DETERMINEE (a arbitrer)'
    return 'CANAL ABSENT'

RES = {}
for k in QUEUE:
    pr = analyse(k); RES[k] = pr
    print('%-30s %-8.4g %-8.4g [%s]' % (k, PK.get(k, float('nan')), PM.get(k, float('nan')),
                                        KE[k]['group']))
    if not pr: print('    AUCUNE PREUVE -> reste CANAL ABSENT (fail-closed)')
    for t, d in sorted(pr, key=lambda x: ORD.index(x[0]) if x[0] in ORD else 99):
        print('    %-18s %s' % (t, d))
    print('    => %s\n' % klass(pr))

c = Counter(klass(RES[k]) for k in QUEUE)
print('-'*98)
print('LA FILE, APRES PREUVE :')
for kk, v in sorted(c.items(), key=lambda x: -x[1]): print('   %-42s %2d' % (kk, v))
rest = [k for k in QUEUE if klass(RES[k]) == 'CANAL ABSENT']
print('   VRAIE FILE : %s' % (', '.join(rest) if rest else 'AUCUNE'))

# ================================================================================================
# BLOC B — LA MEME PREUVE, RETOURNEE SUR LES CLES DEJA CABLEES
# ================================================================================================
print()
print('='*98)
print('BLOC B — LES 24 CANAUX DEJA CABLES, PASSES AUX MEMES PREUVES')
print('='*98)
print("""
Le cycle 109b a annonce que descendre les constantes du moteur vers le fichier livre faisait
disparaitre la tautologie « par construction ». Ce bloc le TESTE. Deux marqueurs, tous deux
mecaniques :

  (T1) la cle est LUE PAR LE SOLVEUR **et** son litteral est un SEUIL DE VERDICT de
       `physics_room_table.py`, avec le NOM DE LA CLE dans la fenetre de 3 lignes (preuve
       FORTE, sans homonyme). Ce qui est mesure est alors le RESIDU de notre propre entree.
       LE MOT `TAUTOLOGIQUE` N'EST PAS POSE POUR AUTANT : la directive du 22:50 le reserve a
       une mesure qui NE PEUT PAS echouer, et `.autoport/c119_mirror_margin.py` mesure que
       1 cellule sur 12 ECHOUE. Le mot pose est `MIROIR`, et la marge est publiee.
       Une citation de § SEULE ne suffit pas : elle est publiee comme `candidat`, jamais
       comme verdict — `0.50` apparait des dizaines de fois dans l'instrument.
  (T2) le document ecrit la valeur comme le NOMINAL D'UNE PLAGE **sans nommer la cle** sur la
       ligne — c'est-a-dire comme une REPONSE ATTENDUE — et nous la DONNONS au solveur. La
       reponse est alors imposee, pas produite.

Deplacer le nombre du moteur vers le fichier ne change ni l'un ni l'autre : c'est une propriete
du COUPLE (entree du solveur, seuil de l'instrument), pas du lieu ou le nombre est ecrit.
""")
SEC_W = {}
for L in blk.split('\n'):
    m = re.search(r'"([A-Za-z]\w+)",\s*//\s*\d+\s+section (\d+)', L)
    if m: SEC_W[m.group(1)] = int(m.group(2))

rows = []
for w in WIRED:
    if w.startswith('Derived'): continue
    s = SEC_W.get(w)
    if s is None or w not in PK: 
        rows.append((w, s, [], [], None, 'NON EVALUABLE (cle derivee ou absente du document)'))
        continue
    hits = instrument_sites(PK[w], [s], name=w)
    fort = [h for h in hits if h[1]=='NOM']
    ph = prose_hit(w) if w in KE else None
    t1 = bool(fort)
    t2 = bool(ph and not ph['named'] and ph.get('pct'))
    if t1 and t2: v = 'MIROIR (T1) + DEFORMATION IMPOSEE (T2)'
    elif t1:      v = 'MIROIR (bande centree sur l\'entree) (T1)'
    elif t2:      v = 'DEFORMATION IMPOSEE (T2)'
    else:         v = 'SAIN'
    rows.append((w, s, hits, fort, ph, v))

for w, s, hits, fort, ph, v in rows:
    print('%-30s §%-4s %-8.4g %s' % (w, s if s else '?', PK.get(w, float('nan')), v))
    for tag, hh in (('T1-FORT ', fort), ('candidat', [h for h in hits if h[1] != 'NOM'])):
        if not hh: continue
        n, ss, t = hh[0]
        print('      %s  physics_room_table.py:%d (%s) — %s   [%d site(s)]'
              % (tag, n, ('le NOM de la cle est dans la fenetre' if ss=='NOM' else '§%s seule, HOMONYME POSSIBLE' % ss), t, len(hh)))
    if ph:
        tg = ('T2 ' if (not ph['named'] and ph.get('pct')) else
              ('--(nommee)' if ph['named'] else '--(sans %)'))
        print('      %s  prose §%d l.%d : « %s »'
              % (tg, sec_of[ph['line']], ph['line'], ph['txt'][:84]))
print()
cb = Counter(v for *_ , v in rows)
for kk, n in sorted(cb.items(), key=lambda x: -x[1]): print('   %-42s %2d' % (kk, n))
