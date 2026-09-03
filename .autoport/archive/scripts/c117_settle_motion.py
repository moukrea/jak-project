#!/usr/bin/env python3
"""
CYCLE 117 — §27 LU SUR LE MOUVEMENT, PAS SUR LA DISTANCE A LA POSE D'AUTEUR.
DIRECTIVES vd9e8b66782 · predictions : .autoport/c117-predictions.txt (md5 3fdc01109393667bdf1234b0603ff82e)

NATURE / REPERE. Les series sont `PHYSRINGAN` / `PHYSRINGAN2` : DEVIATION ANGULAIRE du maillon
RELATIVEMENT A SON PARENT (repere de l'ancre), une valeur par frame, sur les fenetres a entree
propre PH-AXC. Ce ne sont ni des positions monde ni des variances.

CE QUI CHANGE, ET POURQUOI CE N'EST PAS UN ASSOUPLISSEMENT. §27 nomme un MOUVEMENT
(« essentially stationary »). L'instrument lit la DISTANCE A LA POSE D'AUTEUR : une chaine garee
a un decalage CONSTANT est immobile et il la declare « sonne encore ». Le cycle 113 a deja
reattribue ce decalage a §2 / §9 (« restored exactly »), mais l'instrument n'a jamais suivi. On
retranche donc le terme CONSTANT — la moyenne des 30 dernieres frames, deja publiee colonne
`offset` — et on refait la MEME recherche. Aucun parametre libre : les quatre niveaux restent
derives de §24 (f = 2.30 Hz) et §25 (zeta = 0.35).

LES DEUX LECTURES SONT PUBLIEES COTE A COTE. L'ancienne n'est pas retiree.
"""
import re, sys, math

LOG = sys.argv[1] if len(sys.argv) > 1 else \
    ".autoport/reports/Grecharged-secondary-motion/keira-room-x86.log"
NAMES = {0: 'chestL', 1: 'chestR'}
AXC3 = {0: 'v', 1: 'ap', 2: 'lat'}
F24, Z25 = 2.30, 0.35
ZW = Z25 * 2.0 * math.pi * F24
ST = [('reponse visible dominante', 0.3, 0.6), ('mouvement secondaire', 0.6, 1.2),
      ('mostly settled', 1.0, 1.5), ('essentially stationary', 1.3, 1.7)]

txt = open(LOG, errors='ignore').read()
ansl = {}
for m in re.finditer(r'^PHYSRINGAN c=(\d+) f=(\d+) l=(\d+) ax=(\d+) v=([-\d.e+]+)', txt, re.M):
    ansl.setdefault((int(m.group(4)), int(m.group(1)), 'v'), {}) \
        .setdefault(int(m.group(3)), []).append((int(m.group(2)), float(m.group(5))))
for m in re.finditer(r'^PHYSRINGAN2 c=(\d+) f=(\d+) ax=(\d+) l=(\d+) ap=([-\d.e+]+) lat=([-\d.e+]+)',
                     txt, re.M):
    for ai, gi in (('ap', 5), ('lat', 6)):
        ansl.setdefault((int(m.group(3)), int(m.group(1)), ai), {}) \
            .setdefault(int(m.group(4)), []).append((int(m.group(2)), float(m.group(gi))))


def cross(v, thr):
    """DERNIER instant ou |v| depasse thr ; None = jamais redescendu sur la fenetre."""
    for i in range(len(v) - 1, -1, -1):
        if abs(v[i]) > thr:
            return (i + 1) / 60.0 if i + 1 < len(v) else None
    return 0.0


rows = []
for (k, c, ax) in sorted(ansl):
    if AXC3[k] != ax:
        continue
    for l in sorted(ansl[(k, c, ax)]):
        v = [x for _f, x in sorted(ansl[(k, c, ax)][l])]
        if len(v) < 40:
            continue
        a0 = max(abs(x) for x in v[:5]) or 1e-12
        tl = v[-30:]
        mo = sum(tl) / 30.0
        sd = (sum((x - mo) ** 2 for x in tl) / 30.0) ** 0.5
        vd = [x - mo for x in v]                      # <- LE SEUL CHANGEMENT
        old, new = [], []
        for _n, t0, t1 in ST:
            thr = math.exp(-ZW * t0) * a0
            old.append(cross(v, thr))
            new.append(cross(vd, thr))
        rows.append(dict(ch=NAMES.get(c, 'c%d' % c), l=l, ax=ax, a0=a0, mo=mo, sd=sd,
                         old=old, new=new, n=len(v)))

W = len(rows)
print("=" * 108)
print("CYCLE 117 — §27 : LECTURE SUR LE DECALAGE (ancienne) CONTRE LECTURE SUR LE MOUVEMENT (neuve)")
print("=" * 108)
print(f"   f = {F24} Hz (§24) · zeta = {Z25} (§25) · zeta.w = {ZW:.4f} /s · tau = {1/ZW:.4f} s")
for nm, t0, t1 in ST:
    print(f"   niveau d'entree « {nm:26s} » ({t0}-{t1} s) = {100*math.exp(-ZW*t0):8.4f} % de a0")
print()


def fmt(t, t0, t1, n, sd, a0, lvl):
    nf = '~' if sd > lvl * a0 else ''
    if t is None:
        return '>%.2f%s' % (n / 60.0, nf)
    return '%.3f%s%s' % (t, '' if t0 <= t <= t1 else '!', nf)


print(f"{'serie':16s} {'off/a0 %':>8s} {'sd/a0 %':>8s} | "
      + " ".join(f"{'e'+str(i+1)+' ANC':>11s} {'e'+str(i+1)+' NEUF':>11s}" for i in range(4)))
for r in rows:
    cells = []
    for i, (nm, t0, t1) in enumerate(ST):
        lvl = math.exp(-ZW * t0)
        cells.append('%11s %11s' % (fmt(r['old'][i], t0, t1, r['n'], r['sd'], r['a0'], lvl),
                                    fmt(r['new'][i], t0, t1, r['n'], r['sd'], r['a0'], lvl)))
    print(f"{r['ch']+' l'+str(r['l'])+' '+r['ax']:16s} {100*abs(r['mo'])/r['a0']:8.3f} "
          f"{100*r['sd']/r['a0']:8.4f} | " + " ".join(cells))

print()
print("-- LES PREDICTIONS, CONFRONTEES --")
i4 = 3
reach_new = [r for r in rows if r['new'][i4] is not None]
band_new = [r for r in reach_new if ST[i4][1] <= r['new'][i4] <= ST[i4][2]]
reach_old = [r for r in rows if r['old'][i4] is not None]
band_old = [r for r in reach_old if ST[i4][1] <= r['old'][i4] <= ST[i4][2]]
print(f"P1  etape 4 atteinte : ANCIENNE {len(reach_old)}/{W}  ->  NEUVE {len(reach_new)}/{W}"
      f"   (predit >= 8)   {'TENUE' if len(reach_new) >= 8 else 'REFUTEE'}")
print(f"P2  ... et DANS 1.3-1.7 s : ANCIENNE {len(band_old)}/{W}  ->  NEUVE {len(band_new)}/{W}")
early = [r for r in reach_new if r['new'][i4] < ST[i4][1]]
print(f"    dont TROP TOT (< 1.3 s) : {len(early)}/{len(reach_new)}"
      f"   (predit : la plupart)   {'TENUE' if len(early) > len(reach_new)/2 else 'REFUTEE'}")
for i in (0, 1, 2):
    moved = [r for r in rows
             if (r['old'][i] is None) != (r['new'][i] is None)
             or (r['old'][i] is not None and r['new'][i] is not None
                 and abs(r['old'][i] - r['new'][i]) > 2 / 60.0)]
    tag = 'P3' if i == 0 else '  '
    print(f"{tag}  etape {i+1} : {len(moved)}/{W} serie(s) bougent de plus de 2 frames"
          f"   {'-> FALSIFICATEUR TIRE' if len(moved) > 2 else ''}")
nl = [r for r in rows if r['sd'] > math.exp(-ZW * ST[i4][1]) * r['a0']]
print(f"P4  illisibles a l'etape 4 (sigma30 > niveau) : {len(nl)}/{W}  "
      + " · ".join(f"{r['ch']} l{r['l']} {r['ax']} ({100*r['sd']/r['a0']:.4f} %)" for r in nl))

# ------------------------------------------------------------------------------------------------
# BLOC C — CE QUE LES QUATRE FRANCHISSEMENTS DISENT DE L'ENVELOPPE, PAR MAILLON.
#
# Si l'enveloppe est une exponentielle unique `a0.e^{-t/tau}`, alors le franchissement du niveau
# `L_i` tombe a `t_i = tau . ln(1/L_i)` EXACTEMENT, donc les quatre rapports `t_i / ln(1/L_i)`
# doivent rendre LE MEME tau. Leur DISPERSION est donc un test de la forme du modele, pas un
# reglage : elle ne contient aucun parametre libre et elle ne peut pas etre ajustee.
# NATURE / REPERE : identique au bloc B (deviation angulaire relative au parent, repere de l'ancre).
# ------------------------------------------------------------------------------------------------
print()
print("-- BLOC C — tau IMPLIQUE PAR CHAQUE FRANCHISSEMENT (lecture MOUVEMENT), PAR MAILLON --")
print(f"   tau de sa spec (§24 f={F24} Hz, §25 zeta={Z25}) = {1/ZW:.4f} s")
print(f"   {'serie':16s} " + " ".join(f"{'tau(e'+str(i+1)+')':>9s}" for i in range(4))
      + f"  {'p50':>8s} {'etendue':>9s}  forme")
per_link = {}
for r in rows:
    taus = []
    for i, (nm, t0, t1) in enumerate(ST):
        t = r['new'][i]
        if t is None or t == 0.0:
            taus.append(None); continue
        taus.append(t / math.log(1.0 / math.exp(-ZW * t0)))
    ok = [x for x in taus if x is not None]
    if not ok:
        continue
    ok_s = sorted(ok)
    p50 = ok_s[len(ok_s) // 2] if len(ok_s) % 2 else 0.5 * (ok_s[len(ok_s)//2 - 1] + ok_s[len(ok_s)//2])
    spread = max(ok) / min(ok)
    forme = ('EXPONENTIELLE UNIQUE' if spread < 1.35 else
             'PAS UNE EXPONENTIELLE UNIQUE (x%.2f entre ses propres etapes)' % spread)
    per_link.setdefault(r['l'], []).append(p50)
    print(f"   {r['ch']+' l'+str(r['l'])+' '+r['ax']:16s} "
          + " ".join(('%9.4f' % x) if x is not None else '        -' for x in taus)
          + f"  {p50:8.4f} {spread:8.2f}x  {forme}")
print()
for l in sorted(per_link):
    v = sorted(per_link[l])
    med = v[len(v)//2] if len(v) % 2 else 0.5*(v[len(v)//2-1]+v[len(v)//2])
    print(f"   maillon l={l} : tau median {med:.4f} s  = x{med*ZW:.2f} le tau de sa spec"
          f"   (min {min(v):.4f}, max {max(v):.4f}, n={len(v)})")
print()
print("   §24 et §25 sont ajustees sur `l=0` UNIQUEMENT (`physics_room_table.py`, filtre")
print("   `if int(m.group(3)) != 0: continue` sur PHYSRINGAX/AX2 — choix DECLARE : « le mode")
print("   primaire de §28 »). Le commentaire de collecte de §27 dit, lui, que le distal « en porte")
print("   cinq a dix fois plus, et c'est lui qu'on voit ». Les deux affirmations sont ici mesurees.")
