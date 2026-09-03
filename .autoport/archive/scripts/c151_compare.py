#!/usr/bin/env python3
"""c151_compare.py — AVANT/APRES du cycle 151, une prediction par bloc.
Ecrit AVANT la fin de la course (voir git), donc aucun seuil ne peut avoir ete
choisi apres avoir vu le resultat. Lit le TABLEAU pour les verdicts et la TRACE
pour ce qui demande plus de decimales."""
import re, sys, collections

A = open(sys.argv[1], errors='ignore').read().split('\n')   # AVANT tableau
B = open(sys.argv[2], errors='ignore').read().split('\n')   # APRES tableau
TA = open(sys.argv[3], errors='ignore').read()              # AVANT trace
TB = open(sys.argv[4], errors='ignore').read()              # APRES trace

def fam(l):
    m = re.match(r'\s*([A-Z0-9-]+):', l)
    return m.group(1) if m else None

# ---- P1 : le canal de LOT B est-il PROUVE LU ? --------------------------------------------
print("== P1  CANAL fixedhz PROUVE LU (valeur DEPOSEE, pas effet) ==")
pa = set(re.findall(r'PHYSFHZ [^\n]*', TA)); pb = set(re.findall(r'PHYSFHZ [^\n]*', TB))
print("   AVANT : %s" % (sorted(pa) or "AUCUNE ligne PHYSFHZ (attendu)"))
print("   APRES : %s" % (sorted(pb) or "*** AUCUNE LIGNE — P1 REFUTEE, LOT B RETIRE ***"))
print("   PREDIT: ['PHYSFHZ lv=1 fhzmi=0 nsf=1']")
print("   -> %s" % ("TENUE" if sorted(pb) == ['PHYSFHZ lv=1 fhzmi=0 nsf=1'] else "REFUTEE"))

# ---- P2 : confinement — les familles AMONT identiques AU CARACTERE -------------------------
print("\n== P2  CONFINEMENT : familles qui DIFFERENT entre les deux tableaux ==")
ca = collections.Counter(); cb = collections.Counter()
for l in A:
    f = fam(l)
    if f: ca[(f, l)] += 1
for l in B:
    f = fam(l)
    if f: cb[(f, l)] += 1
diff = collections.Counter()
for k, n in ca.items():
    if cb.get(k, 0) != n: diff[k[0]] += 1
for k, n in cb.items():
    if ca.get(k, 0) != n: diff[k[0]] += 1
AMONT = ['ROOM-RAD-BASE','ROOM-RAD-SPLIT','ROOM-RAD-FLESH','ROOM-SPEC21','ROOM-SPEC10',
         'ROOM-ORICOM-SPEC','ROOM-ORICOM-TRL','ROOM-ORICOM-ROLE','ROOM-SPEC8-VOLUME',
         'ROOM-SPEC8-AFFINE','ROOM-SPEC37-KICK','ROOM-SPEC37-ANROT','ROOM-SPEC37-REBASE',
         'ROOM-IDLE','ROOM-SKINPEN-DETAIL','ROOM-SPEC13-VERDICT','ROOM-ORIRECT']
print("   %d famille(s) differente(s) au total." % len(diff))
for f, n in sorted(diff.items(), key=lambda x: -x[1])[:40]:
    print("      %-34s %d ligne(s)" % (f, n))
viol = [f for f in AMONT if f in diff]
print("   FAMILLES AMONT (predites IDENTIQUES AU CARACTERE) qui ont bouge : %s" % (viol or "AUCUNE"))
print("   -> %s" % ("TENUE" if not viol else "*** REFUTEE — l'attribution de P3/P4 tombe ***"))
nrow_a = sum(1 for l in A if l.startswith('row '))
nrow_b = sum(1 for l in B if l.startswith('row '))
rows_id = [l for l in A if l.startswith('row ')] == [l for l in B if l.startswith('row ')]
print("   lignes `row ` : %d -> %d, identiques au caractere : %s" % (nrow_a, nrow_b, rows_id))

# ---- P3/P4/P5 : les regimes d'apex --------------------------------------------------------
def apex(lines):
    d = {}
    for l in lines:
        m = re.match(r'ROOM-APEX-REGIME: (\w+)\s+r=\s*(\d+) (\S+)\s+apex=([0-9.]+)', l)
        if m: d[(m.group(1), int(m.group(2)))] = (m.group(3), float(m.group(4)))
    return d
aa, ab = apex(A), apex(B)
def show(rs, titre, seuil_txt):
    print("\n== %s ==" % titre)
    print("   %-8s %-3s %-14s %8s %8s %8s" % ("chaine","r","regime","AVANT","APRES","var %"))
    out = []
    for ch in ('chestL','chestR'):
        for r in rs:
            if (ch, r) in aa and (ch, r) in ab:
                n, v0 = aa[(ch, r)]; _, v1 = ab[(ch, r)]
                p = 100.0 * (v1 - v0) / v0 if v0 else 0.0
                out.append(p)
                print("   %-8s %-3d %-14s %8.4f %8.4f %+8.2f" % (ch, r, n, v0, v1, p))
    print("   seuil ecrit avant la course : %s" % seuil_txt)
    return out
p3 = show([0],  "P3  LE TEMOIN r=0 (cible pre-specifiee par le cycle 150)",
          "baisse >= 15 % sur LES DEUX ; < 5 % sur l'une = REFUTEE")
p4 = show([11,12], "P4  §19 « 30-40% B0 » — quatre cellules, toutes AU-DESSUS avant",
          "baisse >= 2 % sur les quatre")
p4b = show([13,14], "P4b §20 « apex 20-30% B0 » (meme lot, meme sens attendu)", "sens seulement")
p5 = show([3,6], "P5  §16 — LA SEULE SECTION QUI DEMANDE **PLUS** D'APEX",
          "|var| <= 10 % ; une baisse > 15 % = le lot coute une section")
print("\n   P3 -> %s" % ("TENUE" if p3 and all(x <= -15 for x in p3)
      else ("REFUTEE (contamination n'est pas la cause dominante)" if any(x > -5 for x in p3) else "PARTIELLE")))
print("   P4 -> %s" % ("TENUE" if p4 and all(x <= -2 for x in p4) else "REFUTEE / PARTIELLE"))
print("   P5 -> %s" % ("TENUE" if p5 and all(abs(x) <= 10 for x in p5)
      else ("ECHEC : une cellule de §16 perd > 15 %" if any(x < -15 for x in p5) else "HORS BANDE, a publier")))

# ---- verdicts de bande, tels que le tableau les ecrit -------------------------------------
print("\n== VERDICTS DE BANDE, TELS QUE LE TABLEAU LES ECRIT ==")
for tag, lines in (("AVANT", A), ("APRES", B)):
    c = collections.Counter()
    for l in lines:
        if l.startswith('ROOM-APEX-REGIME:'):
            for k in ('-> DANS', '-> AU-DESSUS', '-> SOUS'):
                if k in l: c[k.replace('-> ','')] += 1
    print("   %-6s %s" % (tag, dict(c)))

# ---- P6 : les TENUE ------------------------------------------------------------------------
print("\n== P6  §24 (TENUE) — six frequences, seuil +/- 0,5 % ==")
for tag, lines in (("AVANT", A), ("APRES", B)):
    for l in lines:
        if l.startswith('ROOM-SPEC24-VERDICT'): print("   %-6s %s" % (tag, l.strip()))

# ---- P7 : les gates -------------------------------------------------------------------------
print("\n== P7  GATES ==")
for tag, lines in (("AVANT", A), ("APRES", B)):
    rows = []
    for l in lines:
        if l.startswith('row '):
            d = dict(re.findall(r'(\w+)=([^\s]+)', l))
            if {'chain','drive','tipvar'} <= set(d): rows.append(d)
    if rows:
        drives = sorted({r['drive'] for r in rows})
        for ch in sorted({r['chain'] for r in rows}):
            per = {d: max(float(r['tipvar']) for r in rows if r['chain']==ch and r['drive']==d)
                   for d in drives if any(r['chain']==ch and r['drive']==d for r in rows)}
            hi, lo = max(per.values()), min(per.values())
            print("   DISCRIMINANT %-6s %-8s ecart %.1f %% (seuil 25 %%)" % (tag, ch, 100*(hi-lo)/hi))
for tag, lines in (("AVANT", A), ("APRES", B)):
    for l in lines:
        if 'SKINPEN-FLOOR' in l or l.startswith('ROOM-SKINPEN-MIRROR'):
            print("   %-6s %s" % (tag, l.strip()[:150]))
