#!/usr/bin/env python3
"""
CYCLE 116 — ARBITRAGE DE PRIORITE : le correctif de REPERE vaut-il ses 216 sites ?

Le bloc D nomme comme « correctif de fond » le passage a une integration dans un repere LOCAL a
l'attache. Avant de l'engager il faut le CHIFFRER contre ce qu'il achete, dans la MEME unite que
les depassements encore ouverts — sinon c'est un chantier choisi par elegance et pas par mesure.

NATURE / REPERE : toutes les grandeurs ci-dessous sont des LONGUEURS rapportees a B0 (SPEC 6,
602 u = 14,70 cm), en repere MONDE, converties en millimetres pour la comparaison.
"""
import re, sys, math

B0_U   = 602.0
U_PER_M = 4096.0
def mm(b0): return b0 * B0_U / U_PER_M * 1000.0

TBL = ".autoport/reports/Grecharged-secondary-motion/keira-room-table.txt"
t = open(TBL, errors='ignore').read()

print("="*96)
print("CE QUE LE CORRECTIF DE REPERE ACHETE, CONTRE CE QUI RESTE OUVERT")
print("="*96)
print(f"\nB0 = {B0_U:.0f} u = {B0_U/U_PER_M*1000:.2f} mm  (SPEC 6)\n")

print("-- 1. CE QUE LA QUANTIFICATION COUTE ENCORE, APRES LA SOMMATION COMPENSEE --")
qn = math.sqrt(0.0625**2 + 0.015625**2 + 0.0625**2)   # norme d'un pas, mesure au bloc C
print(f"   residu de parcage mesure au bloc D : 0,00 a 1,44 pas de flottant")
print(f"   un pas (259 m de l'origine)        : {qn:.4f} u = {qn/U_PER_M*1000:.4f} mm")
print(f"   => residu residuel                 : 0,0000 a {1.44*qn/U_PER_M*1000:.4f} mm")
for m_ in (256, 512, 1024):
    b = math.floor(math.log2(m_*U_PER_M)); s = 2.0**(b-23)
    q = math.sqrt(3)*s
    print(f"   ailleurs dans le niveau, a {m_:5d} m : un pas = {q:.4f} u = {q/U_PER_M*1000:.4f} mm"
          f"  -> residu <= {1.44*q/U_PER_M*1000:.4f} mm")

print("\n-- 2. CE QUI RESTE OUVERT, DANS LA MEME UNITE --")
# `ROOM-COMEX-MAX2` est EXCLU D'OFFICE, et ce n'est pas un choix de commodite : l'arbitrage du
# 2026-08-19 23:50 a etabli que ce chiffre est un MAXIMUM SUR DEUX ECHANTILLONS quand la 22 nomme
# une MOYENNE PONDEREE PAR LA MASSE, et que le publier comme verdict est un FAUX ROUGE. La ligne
# porte elle-meme la mention `[MAX SUR 2 CENTROIDES, PAS LE COM]`. Le prendre ici pour dimensionner
# un chantier serait ressusciter le facteur x2,22 que ce meme arbitrage a retire.
rows = []
for m in re.finditer(r'ROOM-APEX-RATIO: (\w+)\s+r=\s*(\d+) (\S+)\s+apex=([0-9.]+)', t):
    if m.group(3) != 'base':
        rows.append((f"{m.group(1)} apex r={m.group(2)} {m.group(3)}", float(m.group(4)), 0.42, 0.50))
seen=set(); uniq=[]
for r in rows:
    if r[0] not in seen: seen.add(r[0]); uniq.append(r)
print(f"   {'cellule':34s} {'mesure':>9s} {'bande':>13s} {'depassement':>13s}")
worst=0.0
for nm, v, lo, hi in uniq:
    over = v - hi
    if over > worst: worst = over
    flag = f"{mm(over):+9.2f} mm" if over>0 else "      DANS  "
    print(f"   {nm:34s} {v:9.4f} {f'{lo}-{hi}':>13s} {flag:>13s}")
print(f"\n   pire depassement encore ouvert : {worst:.4f} B0 = **{mm(worst):.1f} mm**")

print("\n-- 3. L'ARBITRAGE, ET IL EST ARITHMETIQUE --")
best = 1.44*qn/U_PER_M*1000
print(f"   le correctif de REPERE achete au plus            : {best:.4f} mm")
print(f"   le depassement d'apex encore ouvert vaut         : {mm(worst):.1f} mm")
print(f"   RAPPORT                                          : x{mm(worst)/best:.0f}")
print("   => il faudrait toucher 216 sites du coeur du solveur, a 4800/4800 lignes, pour gagner")
print("      moins d'un millieme de ce qui manque. LE CORRECTIF DE REPERE N'EST PAS LE PROCHAIN")
print("      CHANTIER — il reste NOMME et ouvert, il n'est pas prioritaire.")
