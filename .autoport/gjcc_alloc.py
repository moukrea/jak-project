#!/usr/bin/env python3
"""gjcc_alloc.py — Gjak1-crate-collision : le TRIPLET exige par le contrat de phase.

Pour CHAQUE caisse nee : son IDENTITE, si sa FORME DE COLLISION a ete allouee et
enregistree, et l'OCCUPATION DU POOL a cet instant. C'est ce triplet qui departage
« budget epuise » / « course d'initialisation » / « allocation qui echoue en silence ».
"""
import re, sys, collections
def kv(l): return dict(re.findall(r'(\w+)=(#?[-\w.,/]+)', l))
txt = open(sys.argv[1], errors='replace').read()
# le GJCC-SUM d'un scan est imprime APRES ses lignes GJCC-CRATE : on tamponne le scan
# et on lui rattache SON PROPRE resume, pas celui du scan precedent.
per = collections.OrderedDict()
pending = []
for line in txt.splitlines():
    if 'GJCC-CRATE' in line:
        d = kv(line)
        if d.get('live') == '1' and int(d.get('tag', 0)) < 900:
            pending.append(d)
    elif 'GJCC-SUM' in line:
        cur = kv(line)
        for d in pending:
            per.setdefault(d['aid'], (d, cur))
        pending = []
rows = []
for aid, (d, s) in sorted(per.items(), key=lambda x: int(x[0])):
    ok = (d['rp'] == '1' and d['mesh'] == '1' and d['onlist'] == '1'
          and d['as'] not in ('#x0', '0') and d['with'] not in ('#x0', '0'))
    rows.append((aid, d, s, ok))
nb_ok = sum(1 for r in rows if r[3])
peak = max((int(s['uhbp'].split(',')[0]) for _, _, s, _ in rows if 'uhbp' in s), default=-1)
cap  = next((int(s['uhbp'].split('/')[-1]) for _, _, s, _ in rows if 'uhbp' in s), -1)
ccp  = max((int(s.get('ccprims', 0)) for _, _, s, _ in rows), default=-1)
print("CRATEALLOC caisses=%d forme_allouee=%d forme_absente=%d pool_uhbp_pic=%d/%d "
      "pool_collide_cache_prims_pic=%d/100 nocon=%d"
      % (len(rows), nb_ok, len(rows) - nb_ok, peak, cap, ccp,
         len(re.findall(r'GJCC-NOCON', txt))))
print()
print("%-8s %-9s %-3s %-5s %-7s %-8s %-8s  %s" %
      ("aid", "look", "rp", "mesh", "onlist", "as", "with", "pool uhbp/hbp/hbo (parcouru,champ/capacite)"))
for aid, d, s, ok in rows:
    print("%-8s %-9s %-3s %-5s %-7s %-8s %-8s  %s %s %s%s" %
          (aid, d.get('look'), d['rp'], d['mesh'], d['onlist'], d['as'], d['with'],
           s.get('uhbp', '?'), s.get('hbp', '?'), s.get('hbo', '?'),
           "" if ok else "   <<< FORME ABSENTE"))
