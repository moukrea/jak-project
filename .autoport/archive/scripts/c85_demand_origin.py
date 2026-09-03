#!/usr/bin/env python3
"""
DIRECTIVES v3fee554599 — cycle 85. SECTION NOMMEE : SPEC 22, et SPEC 21 qui porte le mur de force.
Trace ARCHIVEE. Zero build, zero course neuve, zero ligne de moteur.

LA QUESTION, PUBLIEE D'AVANCE PAR LE CYCLE 84 : la demande brute du joint racine (etage 0 de
`PHYSSTGW`, mediane 0,80 B0, maximum 5,08 B0) vient-elle du RESSORT, de la GRAVITE, ou de
l'accumulation de vitesse ? Le cycle 84 proposait trois compteurs neufs dans la boucle de
sous-pas. **Ils existent deja** : `PHYSRESTW` publie depuis le cycle 33 la decomposition exacte
de l'ecart en une part STATIQUE et une part DYNAMIQUE (phys-room.gc:1641-1649) :

    rgap = |cible de repos du ressort - pose d'auteur| / B0   AUCUNE dynamique n'y entre
    perr = |position simulee      - cible de repos|   / B0   la part que la dynamique produit

C'est exactement la separation demandee, et elle evite d'ajouter une ligne au moteur (plafond
CLEAN a 4800 lignes, moteur a 4799).

NATURE     : trois LONGUEURS rapportees a B0 (602 u), chacune un MAXIMUM DE FENETRE
             (`jak-hd-physics.gc:2884-2885` pour `perr` ; tranche 23-42 remise a zero par
             `phys-comexw-reset!`, donc portee FENETRE — la meme que `PHYSSTGW`).
REPERE     : le monde, meme frame, meme attache, meme longueur d'os.
POPULATION : 186 fenetres par chaine.
PIEGE DECLARE : `stage0`, `perr` et `rgap` sont TROIS MAXIMA INDEPENDANTS, potentiellement pris
             sur trois frames differentes. L'inegalite triangulaire ne s'applique donc PAS terme a
             terme : ce qui suit est une comparaison d'ORDRE DE GRANDEUR et de CORRELATION, jamais
             une identite. C'est le piege `RAD-FLESH-IPAIR` du cycle 34, et je le nomme au lieu de
             l'ignorer.
ABSENT     : `rgap` = 0.0000 si la cible de repos EST la pose d'auteur ; `perr` = 0.0000 a
             l'equilibre du ressort.
"""
import re, math, sys, statistics as st
L = sys.argv[1] if len(sys.argv) > 1 else \
    '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.c81-armed.log'
B0 = 602.0
# cycle 71, mesure : le mur de force gele son numerateur des `perr >= kn + 0.99*cpp`
KN, CPP = 0.42, 0.08
FREEZE = KN + 0.99*CPP          # 0.4992 B0

rxw = re.compile(r'^PHYSSTGW c=(\d+) a=(\d+) d=(\d+) st=(\d+) jt=([-\d.]+)')
rxr = re.compile(r'^PHYSRESTW c=(\d+) a=(\d+) d=(\d+) rgap=([-\d.]+) perr=([-\d.]+)')
rxs = re.compile(r'^PHYSSTR c=(\d+) a=(\d+) d=(\d+) el=([-\d.]+) gn=([-\d.]+) tf=([-\d.]+)')
rxa = re.compile(r'^PHYSACC c=(\d+) a=(\d+) d=(\d+) acc=([-\d.]+)')
rxp = re.compile(r'^PHYSAPEX c=(\d+) a=(\d+) d=(\d+) apex=([-\d.]+)')
SW, RW, SR, AC, AP = {}, {}, {}, {}, {}
for line in open(L, errors='replace'):
    if   line.startswith('PHYSSTGW c='):
        m = rxw.match(line); SW[(int(m.group(1)),int(m.group(2)),int(m.group(3)),int(m.group(4)))] = float(m.group(5))
    elif line.startswith('PHYSRESTW c='):
        m = rxr.match(line); RW[(int(m.group(1)),int(m.group(2)),int(m.group(3)))] = (float(m.group(4)), float(m.group(5)))
    elif line.startswith('PHYSSTR c='):
        m = rxs.match(line); SR[(int(m.group(1)),int(m.group(2)),int(m.group(3)))] = (float(m.group(4)), float(m.group(5)), float(m.group(6)))
    elif line.startswith('PHYSACC c='):
        m = rxa.match(line); AC[(int(m.group(1)),int(m.group(2)),int(m.group(3)))] = float(m.group(4))
    elif line.startswith('PHYSAPEX c='):
        m = rxp.match(line); AP[(int(m.group(1)),int(m.group(2)),int(m.group(3)))] = float(m.group(4))

def pear(x, y):
    n = len(x); mx, my = sum(x)/n, sum(y)/n
    sx = math.sqrt(sum((v-mx)**2 for v in x)); sy = math.sqrt(sum((v-my)**2 for v in y))
    return sum((x[i]-mx)*(y[i]-my) for i in range(n))/(sx*sy) if sx > 0 and sy > 0 else float('nan')
def spear(x, y):
    def rk(v):
        s = sorted(range(len(v)), key=lambda i: v[i]); r = [0.0]*len(v)
        for p, i in enumerate(s): r[i] = float(p)
        return r
    return pear(rk(x), rk(y))
def q(v, p): s = sorted(v); return s[int(p*(len(s)-1))]

print(f"trace : {L}")
print(f"PHYSRESTW {len(RW)} · PHYSSTR {len(SR)} · PHYSSTGW {len(SW)} · PHYSACC {len(AC)}")
print(f"seuils du mur de force (cycle 71) : genou {KN:.4f} B0 · gel {FREEZE:.4f} B0")

for c in (0, 1):
    nm = 'chestL' if c == 0 else 'chestR'
    ks = sorted(k for k in RW if k[0] == c)
    rg = [RW[k][0] for k in ks]; pe = [RW[k][1] for k in ks]
    s0 = [SW[(k[0],k[1],k[2],0)] for k in ks]
    s6 = [SW[(k[0],k[1],k[2],6)] for k in ks]
    gn = [SR[k][1] for k in ks]; tf = [SR[k][2] for k in ks]
    gt = [gn[i]*tf[i] for i in range(len(ks))]
    ac = [AC[k] for k in ks]; ap = [AP[k] for k in ks]
    n = len(ks)
    print("\n" + "=" * 100)
    print(f"== {nm}   {n} fenetres")
    print(f"   {'grandeur':<34} {'min':>9} {'p05':>9} {'med':>9} {'p95':>9} {'max':>9}")
    for lab, v in (('rgap  cible de repos vs auteur', rg), ('perr  simule vs cible de repos', pe),
                   ('etage 0  demande brute', s0), ('etage 6  valeur livree', s6),
                   ('gn*tf  gravite tangentielle', gt)):
        print(f"   {lab:<34} {min(v):9.4f} {q(v,.05):9.4f} {st.median(v):9.4f} {q(v,.95):9.4f} {max(v):9.4f}")
    print(f"\n   QUI PILOTE LA DEMANDE BRUTE (etage 0) ?   Pearson / Spearman sur {n} fenetres")
    for lab, v in (('perr   (ecart au ressort)', pe), ('rgap   (decalage statique)', rg),
                   ('gn*tf  (gravite tangent.)', gt), ('acc    (stimulus recu)', ac)):
        print(f"      {lab:<28} {pear(v, s0):+7.3f} / {spear(v, s0):+7.3f}")
    print(f"   rapport etage0 / perr : med {st.median(s0[i]/pe[i] for i in range(n) if pe[i] > 0):.3f}"
          f"   (1.0 = la demande EST l'ecart au ressort)")
    lin = sum(1 for v in pe if v <= KN); kne = sum(1 for v in pe if KN < v < FREEZE)
    frz = sum(1 for v in pe if v >= FREEZE)
    print(f"\n   REGIME DU MUR DE FORCE §21 sur SA PROPRE ENTREE `perr` (classement du cycle 71) :")
    print(f"      LINEAIRE (perr <= {KN:.2f} B0)          {lin:3d}/{n}  ({100*lin/n:5.1f} %)")
    print(f"      GENOU    ({KN:.2f} < perr < {FREEZE:.4f})     {kne:3d}/{n}  ({100*kne/n:5.1f} %)")
    print(f"      GELE     (perr >= {FREEZE:.4f} B0)      {frz:3d}/{n}  ({100*frz/n:5.1f} %)")
    print(f"      -> dans la zone GELEE le module de la force est CONSTANT : la demande n'y depend")
    print(f"         plus de son erreur, et c'est la que vit {100*frz/n:.1f} % des fenetres.")
    # temoin : la fenetre SANS pilotage
    kb = [(c, a, 5) for a in range(31) if (c, a, 5) in RW]
    peb = [RW[k][1] for k in kb]; s0b = [SW[(k[0],k[1],k[2],0)] for k in kb]
    frzb = sum(1 for v in peb if v >= FREEZE)
    print(f"\n   TEMOIN — les 31 fenetres SANS PILOTAGE (d=5), ou le ressort doit dominer :")
    print(f"      perr    med {st.median(peb):.4f}  max {max(peb):.4f} B0   GELEES {frzb}/{len(kb)}")
    print(f"      etage 0 med {st.median(s0b):.4f}  max {max(s0b):.4f} B0")
