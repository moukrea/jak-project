#!/usr/bin/env python3
"""C80c — L'ENTREE DU SOLVEUR, MESUREE SUR UN JOINT QUE LA PHYSIQUE N'ECRIT PAS.

`chest` est le PARENT des deux racines de chaine (`lBoob <- chest <- main`, rig livre) et il
n'est simule par RIEN : sa matrice ecrite est la pose d'AUTEUR, image par image. C'est donc
l'ENTREE du solveur, sans le lissage de l'integrateur — ce qui manquait au test du cycle 80b.

NATURE : une acceleration, u/frame^2 (11.162 = 1 g), par DIFFERENCE SECONDE de la position monde
  du joint : a(t) = p(t+1) - 2 p(t) + p(t-1).
REPERE : le MONDE (celui de `PHYSJTW row=3`).
POPULATION : les frames de la sous-fenetre de LIGNE DE BASE (aucun pilotage de salle), par
  animation. Ce n'est PAS un maximum : la distribution entiere est publiee, et la FORME du pic
  aussi, parce que c'est elle qui discrimine.
LECTURE QUAND LE DEFAUT EST ABSENT : sur un personnage immobile, `chest` rend 0 partout.

LES DEUX HYPOTHESES, ET CE QUI LES SEPARE MAINTENANT SANS RESERVE :
  (a) GESTE REEL     -> le pic dure plusieurs frames ; voisin/maximum eleve.
  (b) A-COUP DE POSE -> le pic est isole sur UNE frame ; voisin/maximum petit.
Sur `chest` il n'y a AUCUN integrateur entre la donnee d'animation et le chiffre : la reserve du
cycle 80b (« un ressort lisse sa sortie, donc une forme soutenue ne prouve pas une entree
soutenue ») ne s'applique plus.

ET LA DECOMPOSITION QUI MANQUAIT : `main` est la racine du personnage. `chest - main` isole
l'ARTICULATION DU TORSE du deplacement d'ENSEMBLE.
"""
import re
import numpy as np

LOG = '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
txt = open(LOG, errors='ignore').read()
JN = {0: 'lBoob', 1: 'lBooc', 2: 'rBoob', 3: 'rBooc', 4: 'chest', 5: 'main'}
G = 11.162

pos, key = {}, {}
for m in re.finditer(r'^PHYSJTW k=(\d+) j=(\d+) row=3 x=([-\d.e+]+) y=([-\d.e+]+) z=([-\d.e+]+)', txt, re.M):
    pos[(int(m.group(1)), int(m.group(2)))] = np.array([float(m.group(i)) for i in (3, 4, 5)])
for m in re.finditer(r'^PHYSJTWK k=(\d+) a=(\d+) d=(\d+) f=([-\d.e+]+)', txt, re.M):
    key[int(m.group(1))] = (int(m.group(2)), int(m.group(3)), float(m.group(4)))

print('DIRECTIVES v3fee554599')
names = sorted({j for (_k, j) in pos})
print('== joints publies : %s ==' % ', '.join(JN.get(j, '?') for j in names))
if 4 not in names or 5 not in names:
    print('   **`chest` ou `main` ABSENT — la course ne porte pas l\'emetteur etendu.**')
    raise SystemExit(2)

byanim = {}
for k, (a, d, f) in key.items():
    byanim.setdefault(a, []).append((k, f))

def accs(ks, ji, sub=None):
    P = [pos.get((k, ji)) for k in ks]
    if any(p is None for p in P) or len(P) < 5:
        return None
    P = np.array(P)
    if sub is not None:
        Q = [pos.get((k, sub)) for k in ks]
        if any(q is None for q in Q):
            return None
        P = P - np.array(Q)
    A = P[2:] - 2 * P[1:-1] + P[:-2]
    return np.linalg.norm(A, axis=1)

rows = []
for a in sorted(byanim):
    ks = [k for k, _f in sorted(byanim[a])]
    r = {}
    for lbl, ji, sub in (('chest', 4, None), ('main', 5, None), ('chest-main', 4, 5)):
        n = accs(ks, ji, sub)
        if n is None or n.max() <= 1e-12:
            r[lbl] = None; continue
        i = int(n.argmax()); nb = []
        if i - 1 >= 0: nb.append(n[i - 1])
        if i + 1 < len(n): nb.append(n[i + 1])
        r[lbl] = (float(n.max()), float(np.median(n)), float(max(nb) / n.max()) if nb else np.nan)
    rows.append((a, r))

print()
print('== L\'ACCELERATION DE L\'ANCRE `chest` — LA POSE D\'AUTEUR, SANS PHYSIQUE ==')
for lbl in ('chest', 'main', 'chest-main'):
    v = np.array([r[lbl] for _a, r in rows if r[lbl] is not None])
    if not len(v):
        continue
    print('   %-11s |a| max : p50 %7.2f u/f2 (%5.2f g) · p95 %7.2f (%5.2f g) · MAX %7.2f (%5.2f g)'
          % (lbl, np.percentile(v[:,0],50), np.percentile(v[:,0],50)/G,
             np.percentile(v[:,0],95), np.percentile(v[:,0],95)/G, v[:,0].max(), v[:,0].max()/G))
    print('   %-11s |a| median de fenetre : p50 %7.2f u/f2 (%5.2f g)'
          % ('', np.percentile(v[:,1],50), np.percentile(v[:,1],50)/G))
    print('   %-11s VOISIN/MAXIMUM : p05 %.3f · p25 %.3f · **p50 %.3f** · p75 %.3f · p95 %.3f'
          % ('', *[np.percentile(v[:,2],q) for q in (5,25,50,75,95)]))
    print()

v = np.array([r['chest'] for _a, r in rows if r['chest'] is not None])
med = float(np.percentile(v[:,2], 50))
print('== VERDICT SUR L\'ENTREE, SANS RESERVE D\'INTEGRATEUR ==')
if med < 0.25:
    print('   voisin/max median = %.3f -> **LE PIC EST ISOLE SUR UNE FRAME.**' % med)
    print('   HYPOTHESE (b) : la POSE D\'AUTEUR saute. C\'est un defaut d\'echantillonnage, donc')
    print('   A NOUS, et la bande de §22 redevient atteignable une fois `a_torso` correctement')
    print('   alimente.')
elif med > 0.5:
    print('   voisin/max median = %.3f -> **LE PIC EST SOUTENU SUR PLUSIEURS FRAMES.**' % med)
    print('   HYPOTHESE (a) : ce sont de VRAIES accelerations de torse dans les animations')
    print('   d\'origine. La physique fait alors ce qu\'il faut, et c\'est la bande de §22 qui est')
    print('   inatteignable tant que ces animations sont jouees telles quelles. **C\'EST UN APPEL')
    print('   DE L\'OWNER, PAS UN DEFAUT DE SOLVEUR.**')
else:
    print('   voisin/max median = %.3f : NI ISOLE NI SOUTENU. **NON CONCLUANT.**' % med)

print()
print('== L\'ENTREE CONTRE CE QUE LA SPEC ENVISAGE ==')
print('   geste le plus dur nomme par la spec (§16, reception dure) : 34.74 u/f2 = 3.11 g')
n_over = sum(1 for _a, r in rows if r['chest'] and r['chest'][0] > 34.74)
print('   animations dont l\'ancre depasse ce geste : **%d / %d**' % (n_over, len(rows)))
print()
print('== LES DIX ANIMATIONS OU L\'ANCRE ACCELERE LE PLUS ==')
rows2 = sorted([r for r in rows if r[1]['chest']], key=lambda x: -x[1]['chest'][0])
print('   %-5s %12s %8s %11s %13s %11s' % ('anim', 'chest max', 'en g', 'voisin/max', 'chest-main max', 'part torse'))
for a, r in rows2[:10]:
    c = r['chest']; cm = r['chest-main']
    print('   a=%-3d %12.2f %8.2f %11.3f %13s %11s'
          % (a, c[0], c[0]/G, c[2],
             ('%.2f' % cm[0]) if cm else '-',
             ('%.0f %%' % (100*cm[0]/c[0])) if cm else '-'))
