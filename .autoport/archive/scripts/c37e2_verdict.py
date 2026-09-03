#!/usr/bin/env python3
"""C37E2 — LES SPHERES PROXIMALES SONT-ELLES DU TRAVAIL REDONDANT ?

Verdict des predictions gravees dans `C37E2-proxsphere-prediction.txt`
(md5 071f1a7bb54e5f806b3d618ba79ffc42), commit 204fed43be — avant la moindre ligne de l'ablation.

usage : c37e2_verdict.py <log-de-la-course> <log-de-reference-C37E1>
"""
import re, sys

AFT, REF = sys.argv[1], sys.argv[2]
CH = {0: 'chestL', 1: 'chestR'}
UNITS = 4096.0
# references gravees, course C37E1
SLAST_RATIO_REF = {0: 0.2127, 1: 0.2165}

def read(p):
    return open(p, 'rb').read().decode('utf-8', 'replace')

txt, ref = read(AFT), read(REF)
out = []
A = out.append

def pen(tag, t):
    m = re.search(r'^PHYSPROX tag=%s maxpen=([-\d.e+]+)' % tag, t, re.M)
    return float(m.group(1)) if m else None

def per(tag, t):
    d = {}
    for m in re.finditer(r'^PHYSPROXC tag=%s c=(\d+) npush=([-\d.e+]+) psum=([-\d.e+]+)'
                         r' slast=([-\d.e+]+)' % tag, t, re.M):
        d[int(m.group(1))] = dict(npush=float(m.group(2)), psum=float(m.group(3)),
                                  slast=float(m.group(4)))
    return d

A('=' * 96)
A('VERDICT C37E2 — LES SPHERES PROXIMALES SONT-ELLES DU TRAVAIL REDONDANT ?')
A('=' * 96)
A('course    : %s' % AFT)
A('reference : %s' % REF)
A('')

pd, pa = pen('prox-disarmed', txt), pen('prox-armed', txt)
dd, da = per('prox-disarmed', txt), per('prox-armed', txt)
if pd is None or pa is None or not dd or not da:
    A('FAIL: la trace ne porte pas les DEUX jambes de l\'ablation.')
    A('      prox-disarmed maxpen=%s · prox-armed maxpen=%s · lignes par chaine %d / %d'
      % (pd, pa, len(dd), len(da)))
    print('\n'.join(out)); sys.exit(1)

A('-- LES DEUX JAMBES, COTE A COTE ------------------------------------------------------------')
A('   grandeur                     DESARMEE (livree)      ARMEE (proximales retirees)     ecart')
A('   maxpen (u)                        %10.4f              %10.4f          %+7.1f %%'
  % (pd, pa, 100.0 * (pa - pd) / pd if pd else 0))
A('   maxpen (m)                        %10.4f              %10.4f' % (pd / UNITS, pa / UNITS))
for c in sorted(dd):
    if c not in da:
        continue
    A('   %-8s npush                    %10.0f              %10.0f          %+7.1f %%'
      % (CH.get(c, c), dd[c]['npush'], da[c]['npush'],
         100.0 * (da[c]['npush'] - dd[c]['npush']) / dd[c]['npush'] if dd[c]['npush'] else 0))
    A('   %-8s psum (u)                 %10.1f              %10.1f          %+7.1f %%'
      % (CH.get(c, c), dd[c]['psum'], da[c]['psum'],
         100.0 * (da[c]['psum'] - dd[c]['psum']) / dd[c]['psum'] if dd[c]['psum'] else 0))
    r0 = dd[c]['slast'] / dd[c]['psum'] if dd[c]['psum'] else 0
    r1 = da[c]['slast'] / da[c]['psum'] if da[c]['psum'] else 0
    A('   %-8s slast/psum                   %.4f                  %.4f          %+7.1f %%'
      % (CH.get(c, c), r0, r1, 100.0 * (r1 - r0) / r0 if r0 else 0))
A('')

def verdict(name, title, ok, det):
    A('%-4s %s' % (name, title))
    for x in det:
        A('     ' + x)
    A('     -> %s' % ('CONFIRMEE' if ok else '**REFUTEE**'))
    A('')
    return ok

res = {}

# ---- T0 : la branche desarmee est bien la course precedente ----
det = []
det.append('CRITERE : lignes `PHYS` hors marqueurs neufs et hors les deux jambes, 0 differente.')
NEW = ('PHYSPROX', 'PHYSPROXC')
def phys(t):
    return [l for l in t.split('\n') if l.startswith('PHYS')
            and not any(l.startswith(d) for d in NEW)
            and 'prox-disarmed' not in l and 'prox-armed' not in l]
la, lb = phys(txt), phys(ref)
diff = sum(1 for x, y in zip(la, lb) if x != y) + abs(len(la) - len(lb))
det.append('%d lignes comparees (reference : %d), **%d differente(s)**' % (len(la), len(lb), diff))
det.append('Les deux jambes de l\'ablation sont des phases NEUVES ajoutees APRES la mesure : elles')
det.append('n\'ecrivent dans aucune fenetre existante, et l\'interrupteur revient a zero a la sortie.')
res['T0'] = verdict('T0', "L'INTERRUPTEUR EST A ZERO EN LIVRAISON", diff == 0, det)

# ---- T1 : le controle positif de l'ablation ----
det, ok = [], True
det.append('CRITERE : arme, `npush` BAISSE d\'au moins 15 %% sur les deux chaines.')
det.append('GRAVE : baisse de 25 %% a 55 %% (deux volumes sur 3.16 et 3.98 par balayage).')
det.append('C\'est le CONTROLE POSITIF de l\'ablation : sans lui, un T2 vert serait un zero de')
det.append('domaine vide — et ce cycle vient d\'en retirer six.')
for c in sorted(dd):
    if c not in da:
        continue
    d0, d1 = dd[c]['npush'], da[c]['npush']
    ch = 100.0 * (d1 - d0) / d0 if d0 else 0
    det.append('%-8s npush %10.0f -> %10.0f  = **%+.1f %%**' % (CH.get(c, c), d0, d1, ch))
    if not ch <= -15.0:
        ok = False
det.append('valeur gravee (-25 a -55 %%) : ' + ', '.join(
    '%s %s' % (CH.get(c, c),
               'oui' if -55.0 <= (100.0 * (da[c]['npush'] - dd[c]['npush']) / dd[c]['npush']) <= -25.0
               else 'NON')
    for c in sorted(dd) if c in da and dd[c]['npush']))
res['T1'] = verdict('T1', "LE CONTROLE TIRE VRAIMENT — LE DOMAINE N'EST PAS VIDE", ok, det)

if not res['T1']:
    A('T2 ET T3 NE SONT PAS EVALUES.')
    A('     T1 est le controle positif de l\'ablation et il a echoue : l\'interrupteur n\'a pas')
    A('     desarme ce que je croyais, ou les spheres proximales ne poussaient deja pas. Publier un')
    A('     verdict sur T2 ou T3 dans ces conditions serait exactement le zero de domaine vide que')
    A('     la table de branches gravee m\'interdit. Le predicat `phys-col-prox?` est a re-verifier.')
    A('')
else:
    det, ok = [], True
    det.append('CRITERE : arme, `maxpen` <= 1.10x sa valeur desarmee. GRAVE : entre 0.95x et 1.05x.')
    det.append('C\'EST LA PREDICTION QUI COMPTE : si la proximale ne couvre aucun sommet que la')
    det.append('distale ne couvre deja, la retirer ne peut pas laisser passer de chair.')
    r = pa / pd if pd else 0
    det.append('maxpen %10.4f u -> %10.4f u = **%.4fx**   (%.4f m -> %.4f m)'
               % (pd, pa, r, pd / UNITS, pa / UNITS))
    ok = r <= 1.10
    det.append('valeur gravee (0.95..1.05x) : %s' % ('tenue' if 0.95 <= r <= 1.05 else 'MANQUEE'))
    res['T2'] = verdict('T2', "LA SPHERE PROXIMALE EST DU TRAVAIL REDONDANT", ok, det)

    det, ok = [], True
    det.append('CRITERE : arme, `slast/psum` baisse d\'au moins 20 %% relatifs. DONNEE A 50/50.')
    for c in sorted(dd):
        if c not in da:
            continue
        r0 = dd[c]['slast'] / dd[c]['psum'] if dd[c]['psum'] else 0
        r1 = da[c]['slast'] / da[c]['psum'] if da[c]['psum'] else 0
        ch = 100.0 * (r1 - r0) / r0 if r0 else 0
        det.append('%-8s slast/psum %.4f -> %.4f = **%+.1f %%**  (reference C37E1 agregee : %.4f)'
                   % (CH.get(c, c), r0, r1, ch, SLAST_RATIO_REF.get(c, float('nan'))))
        if not ch <= -20.0:
            ok = False
    res['T3'] = verdict('T3', "LA BOUCLE SE RAPPROCHE DE LA CONVERGENCE", ok, det)

A('-- LA TABLE DE BRANCHES GRAVEE, APPLIQUEE ---------------------------------------------------')
if not res.get('T0'):
    A('   T0 CASSEE -> la branche desarmee n\'est pas la course precedente : les deux jambes ne')
    A('   comparent plus rien, et je le dis avant tout autre chiffre.')
elif not res.get('T1'):
    A('   T1 REFUTEE -> aucun verdict sur T2 ni T3 (voir ci-dessus). Le predicat est a re-verifier.')
elif res.get('T2') and res.get('T3'):
    A('   T1 + T2 + T3 tenues -> la sphere proximale est du travail REDONDANT prouve a l\'execution,')
    A('   ET elle entretient la non-convergence. Le chantier suivant est de la retirer ou de la')
    A('   redimensionner POUR DE BON — question a l\'owner, son rayon est SA surcharge.')
elif res.get('T2'):
    A('   T2 tenue, T3 REFUTEE -> la sphere proximale est du travail redondant, mais ce n\'est PAS')
    A('   elle qui entretient la non-convergence. Les suspects restants sont les volumes du BUSTE et')
    A('   ceux du debardeur (40.0 %% / 28.9 %% des corrections, SPEC 35).')
else:
    A('   T2 REFUTEE -> la sphere proximale n\'est PAS redondante comme OBSTACLE malgre le')
    A('   recouvrement de sommets. La mesure d\'ensemble du cycle 35 (« l\'union = la distale seule »)')
    A('   ne suffit donc pas a decider d\'un volume de collision, et je publie cette limite de mon')
    A('   propre instrument.')
A('')
A('PHYSEND : %s' % ('oui' if 'PHYSEND' in txt else 'NON — course tronquee'))
A('=' * 96)
print('\n'.join(out))
