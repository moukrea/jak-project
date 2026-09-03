#!/usr/bin/env python3
"""c113_spec24_spec29.py — LA « SUR-DETERMINATION » DE SA SPEC MORD-ELLE SUR KEIRA ?

Le cycle 111 a ecrit, et le cycle 112 l'a remonte a l'owner comme une question ouverte :
  « LE MOTEUR TIENT §29 ET RATE §24, ET IL NE PEUT PAS FAIRE LES DEUX [...] l'ecart §24 vs §29
    est du MEME signe et de la meme taille chez Maia (+5,4 % / +6,5 %) : le conflit est dans le
    DOCUMENT, pas dans notre moteur. »

Le calcul du cycle 111 est JUSTE et il est reproduit ci-dessous. Ce qu'il n'a pas fait, c'est le
seul test qui decide si le conflit BLOQUE : §24 ne donne pas que des nominaux, elle donne des
PLAGES. La question n'est donc pas « les deux nominaux coincident-ils » (ils ne coincident pas)
mais « la frequence que §29 impose tombe-t-elle dans la PLAGE de §24 ».

Aucune valeur n'est retapee : tout est lu dans SPEC-breast-softbody.md avec son numero de ligne.
NATURE : des frequences propres (Hz) et des rapports sans dimension.
"""
import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(REPO, 'SPEC-breast-softbody.md')
NUM = r'[-+]?[0-9]*\.?[0-9]+'
L = open(SPEC, encoding='utf-8').read().split('\n')

# Les deux personnages sont deux moities du document ; la seconde commence a « # MAIA ACHERON ».
_cut = next(i for i, s in enumerate(L) if s.startswith('# MAIA ACHERON'))


def grab(lo, hi, header, keys):
    """Lit un bloc `## nn.` entre les bornes et rend {cle: (valeur, plage|None, ligne)}."""
    i = next(j for j in range(lo, hi) if L[j].startswith(header))
    out = {}
    for j in range(i + 1, hi):
        if L[j].startswith('## '):
            break
        m = re.match(r'^\s{2,}([A-Za-z][A-Za-z/]*)\s*=?\s*(%s)\b' % NUM, L[j])
        if not m:
            continue
        k = m.group(1).lower().replace('/', '')
        r = re.search(r'range\s*(%s)\s*[-\u2013]\s*(%s)' % (NUM, NUM), L[j])
        out[k] = (float(m.group(2)), (float(r.group(1)), float(r.group(2))) if r else None, j + 1)
    return {k: v for k, v in out.items() if any(k.startswith(x) for x in keys)}


AX = (('frontback', 'ap'), ('lateral', 'lat'))
print('DIRECTIVES vd9e8b66782')
print('=' * 96)
verdicts = {}
for who, lo, hi in (('KEIRA HAGAI', 0, _cut), ('MAIA ACHERON', _cut, len(L))):
    f24 = grab(lo, hi, '## 24.', ('vertical', 'frontback', 'lateral'))
    a29 = grab(lo, hi, '## 29.', ('vertical', 'frontback', 'lateral', 'torsional'))
    fv = f24['vertical'][0]
    print('\n%s   (§24 l.%d  ·  §29 l.%d)' % (who, f24['vertical'][2], a29['vertical'][2]))
    print('  f_v nominal = %.2f Hz  (plage %s)' % (fv, f24['vertical'][1]))
    print('  %-10s %-8s %-9s %-9s %-11s %-16s %s'
          % ('axe', 'C(§29)', 'f nom §24', 'plage §24', 'f de §29', 'ecart au nom.', 'verdict PLAGE'))
    ok = True
    for k29, short in AX:
        c = a29[k29][0]
        fn, rng, _ln = f24[k29]
        fd = fv / (c ** 0.5)                      # k = k_v / C  =>  f = f_v / sqrt(C)
        inb = rng is not None and rng[0] <= fd <= rng[1]
        ok = ok and inb
        print('  %-10s %-8.2f %-9.2f %-9s %-9.4f %-16s %s'
              % (short, c, fn, '%.1f-%.1f' % rng if rng else 'n/a', fd,
                 '%+.2f %%' % (100.0 * (fd - fn) / fn), 'DANS' if inb else 'HORS'))
    verdicts[who] = ok
    print('  ->  la derivation par §29 %s les plages de §24 pour ce personnage.'
          % ('TIENT' if ok else 'SORT DE'))

print('\n' + '=' * 96)
print('CE QUE CA TRANCHE :')
print('  * KEIRA (le perimetre) : %s' % ('les deux axes tombent DANS les plages de sa §24 — la'
      ' sur-determination du document NE BLOQUE PAS.' if verdicts['KEIRA HAGAI']
      else 'au moins un axe SORT — le conflit bloque.'))
print('  * MAIA (hors perimetre, vecteur de test) : %s' % ('idem.' if verdicts['MAIA ACHERON']
      else 'au moins un axe SORT de sa plage. C est LA que la sur-determination mord,'
      ' et c est la seule raison de la remonter a l owner.'))
print('  * La regle « f = f_v / sqrt(C) » n est donc PAS une lecture universelle du document :')
print('    elle marche sur un personnage et pas sur l autre. §24 et §29 sont deux exigences')
print('    INDEPENDANTES, pas l une derivee de l autre.')
