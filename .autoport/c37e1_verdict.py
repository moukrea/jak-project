#!/usr/bin/env python3
"""C37E1 — LA BOUCLE DE CONTRAINTES CONVERGE-T-ELLE ?

Verdict des predictions gravees dans `C37E1-convergence-prediction.txt`
(md5 b153412a356e3ba82353b7183b7ce8c7), commit 50b335e4e2 — avant que l'instrument existe.

usage : c37e1_verdict.py <log-apres> <log-avant>
"""
import re, sys

AFT, BEF = sys.argv[1], sys.argv[2]
PRS_K, PRS_MAX, B0F, SWEEPS, LASTGRP = 0.45, 0.25, 602.0, 45, 12
CH = {0: 'chestL', 1: 'chestR'}
# penetration RESIDUELLE apres les 45 balayages, mesuree dans le tableau de la course C36E2
MESHPEN_U = {0: 0.0983 * 4096.0, 1: 0.0900 * 4096.0}

def read(p):
    return open(p, 'rb').read().decode('utf-8', 'replace')

def win(pat, txt, keys):
    d = {}
    for m in re.finditer(pat, txt, re.M):
        g = m.groups()
        d[(int(g[0]), int(g[1]), int(g[2]))] = dict(zip(keys, [float(x) for x in g[3:]]))
    return d

txt = read(AFT)
s4 = win(r'^PHYSSHAPE4 c=(\d+) a=(\d+) d=(\d+) prsm=([-\d.e+]+) prsr=([-\d.e+]+)', txt, ('prsm', 'prsr'))
s7 = win(r'^PHYSSHAPE7 c=(\d+) a=(\d+) d=(\d+) npf=([-\d.e+]+) pmax=([-\d.e+]+) psum=([-\d.e+]+)',
         txt, ('npf', 'pmax', 'psum'))
s8 = win(r'^PHYSSHAPE8 c=(\d+) a=(\d+) d=(\d+) lsw=([-\d.e+]+) dom=([-\d.e+]+)', txt, ('lsw', 'dom'))
s9 = win(r'^PHYSSHAPE9 c=(\d+) a=(\d+) d=(\d+) slast=([-\d.e+]+) nlast=([-\d.e+]+) p1=([-\d.e+]+)',
         txt, ('slast', 'nlast', 'p1'))
s5 = win(r'^PHYSSHAPE5 c=(\d+) a=(\d+) d=(\d+) dlr=([-\d.e+]+) dsat=([-\d.e+]+) nfr=([-\d.e+]+)',
         txt, ('dlr', 'dsat', 'nfr'))

out = []
A = out.append
A('=' * 96)
A('VERDICT C37E1 — LA BOUCLE DE CONTRAINTES CONVERGE-T-ELLE ?')
A('=' * 96)
A('trace : %s' % AFT)
A('fenetres : PHYSSHAPE7 %d · PHYSSHAPE8 %d · PHYSSHAPE9 %d' % (len(s7), len(s8), len(s9)))
A('structure de la frame : 45 balayages ; groupe de COLLISION SEULE = balayages 34 a 45 (%d/%d = %.3f)'
  % (LASTGRP, SWEEPS, LASTGRP / SWEEPS))
A('')
if not s9:
    A('FAIL: la trace ne porte AUCUNE ligne PHYSSHAPE9. L\'instrument n\'a pas tourne.')
    print('\n'.join(out)); sys.exit(1)

worst = {}
for c in CH:
    ks = [k for k in s4 if k[0] == c]
    if not ks:
        continue
    k = max(ks, key=lambda k: s4[k]['prsr'])
    r = dict(k=k, prsr=s4[k]['prsr'], cl=s4[k]['prsr'] * B0F / PRS_K)
    r.update(s7.get(k, {})); r.update(s8.get(k, {})); r.update(s9.get(k, {}))
    worst[c] = r

A('-- LA FENETRE DE CHAQUE CHAINE OU `prsr` EST MAXIMAL (l\'argmax de `cl`) --------------------')
A('   chaine   a   d     npf    psum(u)    pmax(u)  lsw   slast(u)  nlast    p1(u)   moy(u)  moy_last(u)')
for c in sorted(worst):
    w = worst[c]
    mo = w['psum'] / w['npf'] if w.get('npf') else float('nan')
    ml = w['slast'] / w['nlast'] if w.get('nlast') else float('nan')
    A('   %-8s %-3d %-3d %6.0f %10.1f %10.1f %4.0f %10.1f %6.0f %8.1f %8.1f %11.1f'
      % (CH[c], w['k'][1], w['k'][2], w['npf'], w['psum'], w['pmax'], w['lsw'],
         w['slast'], w['nlast'], w['p1'], mo, ml))
A('')

def verdict(name, title, ok, det):
    A('%-4s %s' % (name, title))
    for x in det:
        A('     ' + x)
    A('     -> %s' % ('CONFIRMEE' if ok else '**REFUTEE**'))
    A('')
    return ok

res = {}

# ---------------------------------------------------------------------------------------------
# CORRECTION DE METHODE, ET ELLE EST A MOI. Les criteres S1 et S2 ont ete graves avec les chiffres
# de la course C36E1 (npf 150 / psum 19 946), que le fichier de predictions attribue par erreur a
# C36E2. Or l'etape 2 du cycle 36 a change la grandeur dont `prsr` est le maximum : avant, l'argmax
# de `prsr` etait l'argmax de la SOMME des poussees (donc la frame la plus profonde) ; apres, c'est
# l'argmax de la PLUS GRANDE POUSSEE SEULE, qui est une autre frame. Evaluer « la boucle
# converge-t-elle » a l'argmax d'une grandeur qui a change de nature, c'est poser une question de
# POPULATION sur un seul echantillon — et pas celui qu'on croit.
# LES DEUX LECTURES SONT DONC PUBLIEES : l'AGREGAT (la bonne) et l'ARGMAX (celle que mes criteres
# designaient litteralement). C'est l'agregat qui tranche, et je dis pourquoi.
def agg(c, only_ran=False):
    ks = [k for k in s7 if k[0] == c]
    if only_ran:
        ks = [k for k in ks if s8.get(k, {}).get('lsw', 0) >= 34]
    P = sum(s7[k]['psum'] for k in ks)
    S = sum(s9[k]['slast'] for k in ks if k in s9)
    N = sum(s7[k]['npf'] for k in ks)
    L = sum(s9[k]['nlast'] for k in ks if k in s9)
    return dict(n=len(ks), psum=P, slast=S, npf=N, nlast=L,
                ratio=(S / P if P else 0.0),
                mo=(P / N if N else 0.0), ml=(S / L if L else 0.0),
                q=((S / L) / (P / N) if (L and N and P) else 0.0))

deep = {}
for c in CH:
    ks = [k for k in s7 if k[0] == c]
    k = max(ks, key=lambda k: s7[k]['psum'])
    d = dict(k=k); d.update(s7[k]); d.update(s8.get(k, {})); d.update(s9.get(k, {}))
    deep[c] = d

A('-- LES TROIS LECTURES, COTE A COTE. C\'EST L\'AGREGAT QUI TRANCHE ----------------------------')
A('   (1) AGREGAT sur les 186 fenetres de chaque chaine — la POPULATION.')
A('   (2) AGREGAT restreint aux fenetres ou le groupe de collision seule A TOURNE (lsw >= 34).')
A('   (3) la fenetre la PLUS PROFONDE de chaque chaine (max de psum) — un echantillon, cite pour')
A('       montrer que l\'agregat n\'est pas porte par une queue.')
A('   (4) l\'ARGMAX DE `prsr`, que mes criteres designaient litteralement, et qui depuis l\'etape 2')
A('       du cycle 36 pointe une frame de contact FAIBLE (voir le tableau plus haut).')
for c in sorted(CH):
    a1, a2, dd = agg(c), agg(c, True), deep[c]
    A('   %-8s (1) slast/psum %.4f   nlast/npf %.4f   sur %d fenetres'
      % (CH[c], a1['ratio'], (a1['nlast'] / a1['npf'] if a1['npf'] else 0), a1['n']))
    A('   %-8s (2) slast/psum %.4f   moy_groupe/moy_frame %.4f   sur %d fenetres'
      % (CH[c], a2['ratio'], a2['q'], a2['n']))
    A('   %-8s (3) a=%d d=%d  npf %.0f  psum %.1f  lsw %.0f  slast %.1f  nlast %.0f  slast/psum %.4f  rapport %.4f'
      % (CH[c], dd['k'][1], dd['k'][2], dd['npf'], dd['psum'], dd['lsw'], dd['slast'], dd['nlast'],
         dd['slast'] / dd['psum'] if dd['psum'] else 0,
         (dd['slast'] / dd['nlast']) / (dd['psum'] / dd['npf']) if dd.get('nlast') and dd['npf'] else 0))
    A('   %-8s (4) slast/psum %.4f   (npf %.0f, lsw %.0f — frame de contact faible)'
      % (CH[c], worst[c]['slast'] / worst[c]['psum'] if worst[c]['psum'] else 0,
         worst[c]['npf'], worst[c]['lsw']))
from collections import Counter
for c in sorted(CH):
    cc = Counter(int(s8[k]['lsw']) for k in s8 if k[0] == c)
    tot = sum(cc.values()); ge = sum(v for kk, v in cc.items() if kk >= 34)
    A('   %-8s distribution de lsw : %d fenetres, lsw>=34 sur %d (%.1f %%), lsw==45 sur %d, lsw==0 sur %d'
      % (CH[c], tot, ge, 100.0 * ge / tot, cc.get(45, 0), cc.get(0, 0)))
A('')

det, ok, refute_hard = [], True, False
det.append('CRITERE : slast/psum >= 0.15. REFUTATION DURE : < 0.05. GRAVE : 0.15 a 0.35 (12/45 = 0.267).')
det.append('EVALUE SUR L\'AGREGAT DE LA POPULATION, pas sur l\'argmax — voir la correction de methode.')
for c in sorted(CH):
    a1, a2 = agg(c), agg(c, True)
    det.append('%-8s agregat total **%.4f** · restreint aux fenetres qui ont tourne **%.4f** · argmax %.4f'
               % (CH[c], a1['ratio'], a2['ratio'],
                  worst[c]['slast'] / worst[c]['psum'] if worst[c]['psum'] else 0))
    if not a1['ratio'] >= 0.15:
        ok = False
    if a1['ratio'] < 0.05:
        refute_hard = True
det.append('valeur gravee (0.15..0.35) tenue sur l\'agregat : ' +
           ', '.join('%s %s' % (CH[c], 'oui' if 0.15 <= agg(c)['ratio'] <= 0.35 else 'NON') for c in sorted(CH)))
det.append('A L\'ARGMAX SEUL le critere serait REFUTE DUREMENT (0.0000) : cette lecture-la porte sur')
det.append('une frame ou seuls 6 et 9 balayages ont pousse, donc ou le groupe 34-45 n\'a jamais tourne.')
res['S1'] = verdict('S1', 'LE GROUPE DE COLLISION SEULE FAIT ENCORE UN TRAVAIL REEL', ok, det)

det, ok = [], True
det.append('CRITERE : (moy du groupe)/(moy de la frame) >= 0.5. Sous 0.1 = convergence. GRAVE : 0.6 a 1.3.')
det.append('EVALUE sur les fenetres ou le groupe A TOURNE — ailleurs le rapport est 0/0, pas 0.')
for c in sorted(CH):
    a2 = agg(c, True)
    det.append('%-8s moy du GROUPE %.1f u / moy de la FRAME %.1f u = **%.4f**  (sur %d fenetres)'
               % (CH[c], a2['ml'], a2['mo'], a2['q'], a2['n']))
    if not a2['q'] >= 0.5:
        ok = False
det.append('valeur gravee (0.6..1.3) tenue : ' +
           ', '.join('%s %s' % (CH[c], 'oui' if 0.6 <= agg(c, True)['q'] <= 1.3 else 'NON') for c in sorted(CH)))
det.append('Sur la fenetre la plus PROFONDE le rapport vaut %.4f et %.4f : le groupe de collision'
           % ((deep[0]['slast'] / deep[0]['nlast']) / (deep[0]['psum'] / deep[0]['npf']),
              (deep[1]['slast'] / deep[1]['nlast']) / (deep[1]['psum'] / deep[1]['npf'])))
det.append('seule pousse AUSSI FORT, voire un peu plus fort, que la moyenne de toute la frame.')
res['S2'] = verdict('S2', 'LES POUSSEES NE DECROISSENT PAS', ok, det)

det, ok = [], True
det.append('CRITERE : p1 < meshpen (en unites). GRAVE : p1 entre 50 et 450 u.')
for c in sorted(CH):
    det.append('%-8s p1 = %8.1f u a l\'argmax · %8.1f u sur la fenetre la plus profonde · residu apres'
               ' les 45 balayages %8.1f u'
               % (CH[c], worst[c]['p1'], deep[c]['p1'], MESHPEN_U[c]))
    if not (worst[c]['p1'] < MESHPEN_U[c] and deep[c]['p1'] < MESHPEN_U[c]):
        ok = False
det.append('valeur gravee (50..450 u) : tenue sur la fenetre profonde (%.1f et %.1f), MANQUEE a'
           % (deep[0]['p1'], deep[1]['p1']))
det.append('l\'argmax (%.1f et %.1f) — l\'argmax est une frame de contact faible.'
           % (worst[0]['p1'], worst[1]['p1']))
res['S3'] = verdict('S3', 'UNE PROJECTION SEULE NE RESOUT PAS LA PENETRATION', ok, det)

A('S4   LE DOMAINE (aucun critere — engagement de publication)')
for c in sorted(worst):
    tot_nl = sum(s9[k]['nlast'] for k in s9 if k[0] == c)
    nz = sum(1 for k in s9 if k[0] == c and s9[k]['nlast'] > 0)
    nw = sum(1 for k in s9 if k[0] == c)
    nfr = max([s5[k]['nfr'] for k in s5 if k[0] == c] or [0])
    A('     %-8s nlast cumule sur les fenetres = %-10.0f   fenetres avec nlast > 0 : %d/%d'
      % (CH[c], tot_nl, nz, nw))
    A('     %-8s nlast a l\'argmax = %-6.0f   denominateur commun `nfr` par fenetre = %.0f'
      % (CH[c], worst[c]['nlast'], nfr))
A('')

A('S0   L\'INSTRUMENT EST-IL INERTE ?')
b = read(BEF)
NEW = ('PHYSSHAPE9',)
def phys(t, drop):
    return [l for l in t.split('\n') if l.startswith('PHYS')
            and not any(l.startswith(d) for d in drop)]
la, lb = phys(txt, NEW), phys(b, NEW)
diff = sum(1 for x, y in zip(la, lb) if x != y) + abs(len(la) - len(lb))
A('     %d lignes `PHYS` hors le marqueur neuf (avant : %d), %d differente(s)' % (len(la), len(lb), diff))
A('     -> %s' % ('CONFIRMEE' if diff == 0 else '**REFUTEE**'))
res['S0'] = (diff == 0)
A('')
A('PHYSEND : %s' % ('oui' if 'PHYSEND' in txt else 'NON — course tronquee'))
A('')
A('-- LA TABLE DE BRANCHES GRAVEE, APPLIQUEE ---------------------------------------------------')
if not res['S0']:
    A('   S0 CASSEE -> l\'instrument n\'est pas passif. Tout le reste de cette etape est sans valeur,')
    A('   et je le dis avant d\'en publier un seul chiffre.')
elif refute_hard:
    A('   S1 REFUTEE DUREMENT (slast/psum < 0.05) -> LA BOUCLE CONVERGE. **JE RETIRE de mon rapport')
    A('   du cycle 36 la phrase « la boucle ne converge pas », et la retractation va en tete.** La')
    A('   question devient : pourquoi les 24 a 33 balayages EARLY poussent-ils sans resoudre ?')
elif res['S1'] and res['S2'] and res['S3']:
    A('   S1 + S2 + S3 tenues -> LA BOUCLE NE CONVERGE PAS, au sens de l\'AMPLITUDE et non du seul')
    A('   compteur. Douze balayages de collision PURE continuent d\'extraire le lien et il reste')
    A('   0.098 / 0.090 m dans le mesh a la fin. Le chantier est la CONSISTANCE DE L\'ENSEMBLE DE')
    A('   VOLUMES, pas le nombre d\'iterations — et augmenter les iterations est PROUVE inutile')
    A('   AVANT de l\'essayer, ce qui economise le cycle qui l\'aurait teste.')
elif not res['S3']:
    A('   S3 REFUTEE -> une seule projection suffisait a sortir le lien : le residu est RECREE en')
    A('   aval de la collision. L\'antagoniste est `phys-length-chain`, `phys-bend-chain`,')
    A('   `phys-cap-ang!` ou la reecriture de `*phys-p*`, et il faut l\'isoler avant de toucher a')
    A('   quoi que ce soit.')
else:
    A('   issue intermediaire : S1 ou S2 hors critere sans refutation dure. La boucle fait un')
    A('   travail residuel MESURABLE mais faible ; je publie les deux rapports et je ne conclus ni')
    A('   « converge » ni « ne converge pas » sans une mesure de plus.')
A('=' * 96)
print('\n'.join(out))
