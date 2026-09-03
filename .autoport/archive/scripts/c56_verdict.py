#!/usr/bin/env python3
"""c56_verdict.py — adjuge les six predictions de C56E1 sur la trace de la salle.

NATURE / REPERE : identiques a ROOM-SIGN et a c55_verdict.py — `apex` est un MAXIMUM DE FENETRE
en fraction de B0, releve en repere monde contre la pose d'auteur ; les directions d'os sont
unitaires, en repere monde. `dev` est un ANGLE en degres, defini exactement comme aux cycles
53/54/55 (reflexion dans le plan de normale `lat`, l'axe lateral du solveur lu sur PHYSAXW ax=2).
LIGNE DE BASE : `PHYSSYM3` publie la MEME grandeur sur la queue de calme, stimulus ABSENT — c'est
elle, et rien d'autre, qui donne son echelle a un ecart.

AUCUN SEUIL N'EST CHOISI ICI : les six sont recopies de .autoport/C56E1-deuxposes-prediction.txt,
grave et commite AVANT la course (md5 8128d2000ec3484fb03bcac2cb29096a, commit 72701d62f9).
"""
import re, math, sys

NEW = '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
REF = '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.C55-REF.log'

# ---- seuils, recopies de C56E1 -----------------------------------------------------------------
P1_SYM_MAX, P1_ASYM_MIN = 12.0, 60.0
P3_ASYM_MIN, P3_SYM_MAX = 2.0, 1.5
P4_SX_MIN = 0.10
P5_SYM_MAX, P5_ASYM_MIN = 0.25, 0.50
P2_ANIMLEN_ADDED = 8

L = open(NEW, encoding='utf-8', errors='ignore').read()
CH = {0: 'chestL', 1: 'chestR'}
MNAME = {0: 'lacet 90 (SPEC18 modere)', 1: 'lacet 150 (SPEC18 fort)',
         2: 'lateral +90 (SPEC12)', 3: 'lateral -90 (SPEC12)'}


def dot(a, b): return sum(x * y for x, y in zip(a, b))
def nrm(a): return math.sqrt(dot(a, a))
def mir(u, n):
    d = dot(u, n)
    return tuple(u[i] - 2 * d * n[i] for i in range(3))
def ang(a, b):
    return math.degrees(math.acos(max(-1.0, min(1.0, dot(a, b) / (nrm(a) * nrm(b))))))
def rel(a, b):
    """ecart relatif a la MOYENNE des deux — symetrique, contrairement a |a-b|/a."""
    m = 0.5 * (abs(a) + abs(b))
    return abs(a - b) / m if m > 0 else float('nan')


# ---- lecture de la trace -----------------------------------------------------------------------
ax = {}
for m in re.finditer(r'^PHYSAXW ax=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+) uz=([-\d.e+]+)', L, re.M):
    ax[int(m[1])] = (float(m[2]), float(m[3]), float(m[4]))

pose = {}                       # i -> (p, m, ai)
for m in re.finditer(r'^PHYSSYMPOSE i=(\d+) p=(\d+) m=(\d+) ai=(-?\d+)', L, re.M):
    pose[int(m[1])] = (int(m[2]), int(m[3]), int(m[4]))

bone = {}                       # (i, c, l) -> u
for m in re.finditer(r'^PHYSSYMB i=(\d+) c=(\d+) l=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+) uz=([-\d.e+]+)', L, re.M):
    bone[(int(m[1]), int(m[2]), int(m[3]))] = (float(m[4]), float(m[5]), float(m[6]))

apex, com = {}, {}
for m in re.finditer(r'^PHYSSYM i=(\d+) p=(\d+) m=(\d+) c=(\d+) apex=([-\d.e+]+) com=([-\d.e+]+)', L, re.M):
    apex[(int(m[1]), int(m[4]))] = float(m[5]); com[(int(m[1]), int(m[4]))] = float(m[6])

stim = {}
for m in re.finditer(r'^PHYSSYM2 i=(\d+) c=(\d+) ax=[-\d.e+]+ ay=[-\d.e+]+ az=[-\d.e+]+ stim=([-\d.e+]+)', L, re.M):
    stim[(int(m[1]), int(m[2]))] = float(m[3])

shp = {}                        # (i, c) -> (sx, sy, sz, det)
for m in re.finditer(r'^PHYSSYM4 i=(\d+) c=(\d+) sx=([-\d.e+]+) sy=([-\d.e+]+) sz=([-\d.e+]+) det=([-\d.e+]+)', L, re.M):
    shp[(int(m[1]), int(m[2]))] = tuple(float(m[k]) for k in (3, 4, 5, 6))

grav = {}
for m in re.finditer(r'^PHYSSYM5 i=(\d+) c=(\d+) gx=([-\d.e+]+) gy=([-\d.e+]+) gz=([-\d.e+]+)', L, re.M):
    grav[(int(m[1]), int(m[2]))] = tuple(float(m[k]) for k in (3, 4, 5))

base = {}
for m in re.finditer(r'^PHYSSYM3 i=(\d+) c=(\d+) bapex=([-\d.e+]+) bcom=([-\d.e+]+)', L, re.M):
    base[(int(m[1]), int(m[2]))] = float(m[3])

print("=" * 96)
print("C56 — ADJUDICATION DES SIX PREDICTIONS DE C56E1")
print("=" * 96)
if not pose:
    print("AUCUNE ligne PHYSSYMPOSE : la phase PH-SYM n'a pas tourne. Rien n'est adjugeable.")
    sys.exit(1)
print("cellules publiees : %d sur 8 attendues" % len(pose))

# i des cellules par (p, m)
cell = {(p, m): i for i, (p, m, _) in pose.items()}
def C(p, m): return cell.get((p, m))

# ---- P1 : les deux epingles prennent -----------------------------------------------------------
print("\n" + "-" * 96)
print("P1 — LES DEUX EPINGLES PRENNENT   (p=0 : dev <= %.0f deg   ·   p=1 : dev >= %.0f deg)"
      % (P1_SYM_MAX, P1_ASYM_MIN))
print("-" * 96)
if 2 not in ax:
    print("PHYSAXW ax=2 absent : l'axe lateral n'est pas publie, `dev` n'est pas calculable.")
    sys.exit(1)
lat = ax[2]
dev = {}
for i in sorted(pose):
    p, mm, ai = pose[i]
    row = []
    for l in (0, 1):
        if (i, 0, l) in bone and (i, 1, l) in bone:
            d = ang(mir(bone[(i, 0, l)], lat), bone[(i, 1, l)])
            dev[(i, l)] = d
            row.append("%s %6.1f deg" % (('racine', 'distal')[l], d))
    print("  i=%d  p=%d (%s)  m=%d %-24s ai=%-3d  %s"
          % (i, p, ('SYM', 'ASYM')[p], mm, MNAME.get(mm, '?'), ai, "   ".join(row)))
sym_ok = all(dev.get((C(0, m), 0), 1e9) <= P1_SYM_MAX for m in range(4) if C(0, m) is not None)
asym_ok = all(dev.get((C(1, m), 0), -1) >= P1_ASYM_MIN for m in range(4) if C(1, m) is not None)
p1 = sym_ok and asym_ok
print("\n  -> P1 %s" % ("TENUE — les deux epingles ont pris" if p1 else
      "REFUTEE — les epingles n'ont pas donne les deux poses choisies ; RIEN d'autre n'est lisible"))

# ---- P2 : le controle --------------------------------------------------------------------------
print("\n" + "-" * 96)
print("P2 — LE CONTROLE   (hors PHYSSYM* et PHYSANIMLEN : 0 ligne changee, 0 disparue ;")
print("                    exactement %d PHYSANIMLEN ajoutees)" % P2_ANIMLEN_ADDED)
print("-" * 96)
p2 = None
try:
    R = open(REF, encoding='utf-8', errors='ignore').read()
    keep = lambda t: [x for x in t.splitlines()
                      if not x.startswith('PHYSSYM') and not x.startswith('PHYSANIMLEN')]
    a, b = keep(R), keep(L)
    nal_r = len(re.findall(r'^PHYSANIMLEN ', R, re.M))
    nal_n = len(re.findall(r'^PHYSANIMLEN ', L, re.M))
    same = (a == b)
    print("  lignes hors PHYSSYM*/PHYSANIMLEN : ref %d   cette course %d" % (len(a), len(b)))
    if same:
        print("  lignes CHANGEES ou DISPARUES : 0")
    else:
        diff = [k for k in range(min(len(a), len(b))) if a[k] != b[k]]
        print("  lignes CHANGEES : %d   (delta de compte : %+d)" % (len(diff), len(b) - len(a)))
        for k in diff[:6]:
            print("     ref  : %s" % a[k][:104])
            print("     cette: %s" % b[k][:104])
    print("  PHYSANIMLEN : ref %d   cette course %d   -> %+d ajoutees" % (nal_r, nal_n, nal_n - nal_r))
    p2 = same and (nal_n - nal_r == P2_ANIMLEN_ADDED)
    print("\n  -> P2 %s" % ("TENUE — la phase est bien APPENDUE, rien d'existant n'a bouge" if p2 else
          "REFUTEE — une ligne existante a bouge ou le compte d'ajouts n'est pas celui annonce ;\n"
          "     tous les chiffres ci-dessous sont a lire avec ca en tete"))
except FileNotFoundError:
    print("  reference %s absente — controle NON FAIT (et pas 'tenu')." % REF)

# ---- le tableau brut, avant tout verdict -------------------------------------------------------
print("\n" + "-" * 96)
print("LA MESURE BRUTE, AVANT TOUT VERDICT")
print("-" * 96)
print("  %-4s %-5s %-26s %-8s %-9s %-9s %-8s %-9s" %
      ("i", "pose", "mesure", "chaine", "apex", "base", "R", "stim"))
res = {}
for mm in range(4):
    vals = [base[(C(p, mm), c)] for p in (0, 1) for c in (0, 1)
            if C(p, mm) is not None and (C(p, mm), c) in base]
    res[mm] = max(vals) if vals else float('nan')
ratio = {}
for mm in range(4):
    for p in (0, 1):
        i = C(p, mm)
        if i is None:
            continue
        aL, aR = apex.get((i, 0)), apex.get((i, 1))
        r = (max(aL, aR) / min(aL, aR)) if (aL and aR and min(aL, aR) > 0) else float('nan')
        ratio[(p, mm)] = (r, abs(aL - aR) if (aL is not None and aR is not None) else float('nan'))
        for c in (0, 1):
            print("  %-4d %-5s %-26s %-8s %-9.5f %-9.5f %-8s %-9.2f" %
                  (i, ('SYM', 'ASYM')[p], MNAME.get(mm, '?'), CH[c],
                   apex.get((i, c), float('nan')), base.get((i, c), float('nan')),
                   ("%.3f" % r) if c == 0 else "", stim.get((i, c), float('nan'))))
print("\n  plancher de resolution par mesure (max des `base` sur les 2 poses x 2 chaines) :")
for mm in range(4):
    print("     m=%d %-26s res = %.5f B0" % (mm, MNAME.get(mm, '?'), res[mm]))

# ---- P3 : SPEC 18 ------------------------------------------------------------------------------
print("\n" + "-" * 96)
print("P3 — SPEC 18, L'ECART GAUCHE/DROITE D'APEX   (ASYM : R >= %.1f sur au moins une ;"
      % P3_ASYM_MIN)
print("                                              SYM  : R <= %.1f sur les DEUX)" % P3_SYM_MAX)
print("-" * 96)
for mm in (0, 1):
    for p in (0, 1):
        if (p, mm) in ratio:
            r, d = ratio[(p, mm)]
            flag = "  NON RESOLU (|ecart| %.5f <= res %.5f)" % (d, res[mm]) if d <= res[mm] else ""
            print("  m=%d %-26s %-5s  R = %.3f%s" % (mm, MNAME[mm], ('SYM', 'ASYM')[p], r, flag))
asym_hit = any(ratio.get((1, mm), (0, 0))[0] >= P3_ASYM_MIN for mm in (0, 1))
sym_hit = all(ratio.get((0, mm), (1e9, 0))[0] <= P3_SYM_MAX for mm in (0, 1))
if not asym_hit:
    print("\n  -> P3 SANS OBJET — la jambe ASYMETRIQUE ne produit AUCUN contraste (R < %.1f partout)."
          % P3_ASYM_MIN)
    print("     Le montage apparie n'a rien a separer : ce cycle NE DIT RIEN de SPEC 18, et je ne")
    print("     lis pas la jambe symetrique toute seule. C'est la branche (b) de P3, ecrite avant.")
elif sym_hit:
    print("\n  -> P3 TENUE — la POSE porte l'ecart gauche/droite de SPEC 18.")
else:
    print("\n  -> P3 REFUTEE, ET CONTRE MOI — l'ecart SURVIT a l'epingle.")
    print("     La pose n'explique donc PAS l'asymetrie de SPEC 18 : elle est dans le solveur ou")
    print("     dans le rig, et la phrase du cycle 55 ('toutes les phases qui mesurent du")
    print("     gauche/droite doivent etre epinglees') est une generalisation abusive de ma part.")

# ---- P4 : SPEC 12 doit survivre ----------------------------------------------------------------
print("\n" + "-" * 96)
print("P4 — TEMOIN NEGATIF : SPEC 12 DOIT SURVIVRE   (SYM : ecart sx >= %.0f %% aux DEUX poles,"
      % (100 * P4_SX_MIN))
print("                                               et il S'INVERSE entre m=2 et m=3)")
print("-" * 96)
sxg = {}
for mm in (2, 3):
    for p in (0, 1):
        i = C(p, mm)
        if i is None or (i, 0) not in shp or (i, 1) not in shp:
            continue
        s0, s1 = shp[(i, 0)][0], shp[(i, 1)][0]
        sxg[(p, mm)] = s0 - s1
        g0 = grav.get((i, 0), (float('nan'),) * 3)
        print("  m=%d %-22s %-5s  sx chestL=%.5f  chestR=%.5f  ecart=%+.2f %%   (g lue : %+.4f %+.4f %+.4f)"
              % (mm, MNAME[mm], ('SYM', 'ASYM')[p], s0, s1, 100 * rel(s0, s1), g0[0], g0[1], g0[2]))
if (0, 2) in sxg and (0, 3) in sxg:
    i2, i3 = C(0, 2), C(0, 3)
    big = (rel(shp[(i2, 0)][0], shp[(i2, 1)][0]) >= P4_SX_MIN and
           rel(shp[(i3, 0)][0], shp[(i3, 1)][0]) >= P4_SX_MIN)
    inv = (sxg[(0, 2)] * sxg[(0, 3)] < 0)
    p4 = big and inv
    print("\n  amplitude >= %.0f %% aux deux poles : %s   ·   inversion de signe : %s"
          % (100 * P4_SX_MIN, "oui" if big else "NON", "oui" if inv else "NON"))
    print("  -> P4 %s" % ("TENUE — SPEC 12 survit a l'epingle : son mecanisme est de RIG, pas de pose"
          if p4 else
          "REFUTEE — SPEC 12 s'effondre AUSSI en pose symetrique.\n"
          "     Alors la pose explique TOUT, y compris le mecanisme que j'ai attribue au correctif\n"
          "     de code du cycle 50 — et une explication qui explique tout n'explique rien.\n"
          "     L'attribution du cycle 50 doit etre rouverte."))
else:
    print("\n  -> P4 NON ADJUGEABLE : PHYSSYM4 manquant sur au moins une cellule laterale.")

# ---- P5 : invariance miroir --------------------------------------------------------------------
print("\n" + "-" * 96)
print("P5 — INVARIANCE MIROIR ENTRE LES DEUX POLES   (SYM : les DEUX ecarts croises <= %.2f ;"
      % P5_SYM_MAX)
print("                                               ASYM : au moins un >= %.2f)" % P5_ASYM_MIN)
print("-" * 96)
cross = {}
for p in (0, 1):
    i2, i3 = C(p, 2), C(p, 3)
    if i2 is None or i3 is None:
        continue
    d1 = rel(apex[(i2, 0)], apex[(i3, 1)])       # chestL a +90  vs  chestR a -90
    d2 = rel(apex[(i2, 1)], apex[(i3, 0)])       # chestR a +90  vs  chestL a -90
    cross[p] = (d1, d2)
    r1 = "NON RESOLU" if abs(apex[(i2, 0)] - apex[(i3, 1)]) <= res[2] else ""
    r2 = "NON RESOLU" if abs(apex[(i2, 1)] - apex[(i3, 0)]) <= res[2] else ""
    print("  %-5s  L(+90)=%.5f vs R(-90)=%.5f -> %.3f %s" % (('SYM', 'ASYM')[p],
          apex[(i2, 0)], apex[(i3, 1)], d1, r1))
    print("         R(+90)=%.5f vs L(-90)=%.5f -> %.3f %s" % (
          apex[(i2, 1)], apex[(i3, 0)], d2, r2))
if 0 in cross and 1 in cross:
    p5 = max(cross[0]) <= P5_SYM_MAX and max(cross[1]) >= P5_ASYM_MIN
    print("\n  -> P5 %s" % ("TENUE — l'invariance miroir S'ETABLIT en pose symetrique et pas dans"
          " l'autre :\n     les chiffres bougent POUR LA RAISON GEOMETRIQUE invoquee, pas seulement en valeur"
          if p5 else
          "REFUTEE — l'invariance miroir ne s'etablit pas comme predit.\n"
          "     Un ecart qui tombe sans que le miroir s'etablisse veut dire que j'ai deplace des\n"
          "     chiffres, pas explique quoi que ce soit."))
else:
    print("\n  -> P5 NON ADJUGEABLE : une cellule laterale manque.")

# ---- P6 : resolution ---------------------------------------------------------------------------
print("\n" + "-" * 96)
print("P6 — RESOLUTION   (au moins un rapport de P3/P5 tombe SOUS son plancher et est declare")
print("                   NON RESOLU au lieu d'etre cite comme un nombre)")
print("-" * 96)
unres = []
for mm in (0, 1):
    for p in (0, 1):
        if (p, mm) in ratio and ratio[(p, mm)][1] <= res[mm]:
            unres.append("P3 m=%d %s (R=%.3f)" % (mm, ('SYM', 'ASYM')[p], ratio[(p, mm)][0]))
for p in (0, 1):
    i2, i3 = C(p, 2), C(p, 3)
    if i2 is None or i3 is None:
        continue
    if abs(apex[(i2, 0)] - apex[(i3, 1)]) <= res[2]:
        unres.append("P5 %s paire L(+90)/R(-90)" % ('SYM', 'ASYM')[p])
    if abs(apex[(i2, 1)] - apex[(i3, 0)]) <= res[2]:
        unres.append("P5 %s paire R(+90)/L(-90)" % ('SYM', 'ASYM')[p])
for u in unres:
    print("  NON RESOLU : %s" % u)
# DEFAUT DE CONCEPTION REPERE APRES LA GRAVURE DE C56E1 ET AVANT DE LIRE LA MOINDRE DONNEE.
# La queue de calme s'ouvre par un `physroom-hold`, qui ramene le sujet d'une rotation de 90 ou
# 150 deg a l'identite EN UNE FRAME. Si le rebasement de §37 n'absorbe pas ce saut, la queue ne
# mesure pas le plancher de l'instrument mais le retour de manivelle — et `res` serait alors un
# SUR-estimateur, qui declarerait « NON RESOLU » des ecarts qui sont en fait resolus.
# Ca ne peut pas fabriquer un faux positif pour P3 ni P5 (les rapports R sont calcules sans `res`),
# mais ca rendrait P6 VIDE : elle serait tenue par construction. Le test ci-dessous le dit au lieu
# de laisser P6 se declarer gagnante sur un plancher qui mesure autre chose que ce qu'il annonce.
# Ce bloc est ecrit AVANT que la course ait produit une seule ligne PHYSSYM3 ; il ne peut donc pas
# avoir ete ajuste au resultat.
_vac = []
for mm in range(4):
    _dr = [apex[(C(p, mm), c)] for p in (0, 1) for c in (0, 1)
           if C(p, mm) is not None and (C(p, mm), c) in apex]
    if _dr and res.get(mm) is not None and res[mm] >= 0.5 * (sum(_dr) / len(_dr)):
        _vac.append(mm)
if _vac:
    print("  ATTENTION — PLANCHER SUSPECT sur m=%s : `res` y vaut au moins la moitie de l'apex"
          % ",".join(str(x) for x in _vac))
    print("     PILOTE. La queue de calme s'ouvre par un retour a l'identite EN UNE FRAME depuis")
    print("     une rotation de 90-150 deg : elle mesure ce retour de manivelle, pas le plancher")
    print("     de l'instrument. Sur ces mesures P6 est VIDE — tenue par construction — et je ne")
    print("     la compte pas. Defaut de conception de MA phase, repere apres la gravure de C56E1")
    print("     et avant lecture des donnees ; a corriger au cycle suivant par un retour DOUX")
    print("     (PHYSROOM-RETF), comme `physroom-reg-drive` le fait deja entre ses fenetres.")
print("\n  -> P6 %s" % (("VIDE sur %d mesure(s), NON COMPTEE — voir l'avertissement ci-dessus"
      % len(_vac)) if _vac else
      "TENUE — %d rapport(s) sous la resolution, rapportes comme tels" % len(unres)
      if unres else
      "REFUTEE — tous les rapports sont resolus. La queue de calme ne fait pas son travail\n"
      "     (trop courte, ou elle mesure autre chose que le plancher), et je le dis au lieu de me\n"
      "     feliciter d'avoir des chiffres partout."))
print("\n" + "=" * 96)
