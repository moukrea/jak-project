#!/usr/bin/env python3
"""c131_anchor_size_closed_form.py — LA TAILLE DU DEPLACEMENT D'ANCRAGE, EN FORME CLOSE.

CE N'EST PAS UNE MESURE. C'est une derivation algebrique a partir de nombres DEJA PUBLIES, et
elle sert de PREDICTION a la mesure directe (`.autoport/c131_anchor_dof.py`). Les deux doivent
tomber au meme endroit ; si elles divergent, c'est la forme close qui a tort, et on le publie.

NATURE   : une LONGUEUR, exprimee en fraction de B0 (602 u) pour §11 et de W0 (776,06 u) pour §10,
           puis convertie en centimetres (4096 u = 1 m) parce qu'un chiffre en unites moteur
           n'est verifiable par personne.
REPERE   : la base de l'ANCRE, celle de `PHYSORICOML` / `PHYSDFMA` / `breast-com-mass.json`.
HORS DEF.: un deplacement d'ancrage NUL rend exactement les chiffres publies aujourd'hui.

L'ALGEBRE, en une ligne. Si la deformation `D` est appliquee autour d'un point `a` au lieu du
joint, chaque sommet pilote par ce joint recoit l'offset CONSTANT `a.(I - D)`. Donc :
  * apex - racine = (apex - racine).D  : la LONGUEUR est invariante en `a` ;
  * le centroide se deplace de `a.(I - D)` : le COM, lui, CHANGE.
L'ancrage est donc un second degre de liberte EXACT pour §11, et sa composante LATERALE agit de
la meme facon sur la clause « Outward COM migration » de §10.
"""
U_PAR_M = 4096.0
B0, W0 = 602.0, 776.0637359619141

def cm(u):
    return u / U_PAR_M * 100.0

print('C131-CF: B0 = %.1f u = %.2f cm   ·   W0 = %.2f u = %.2f cm' % (B0, cm(B0), W0, cm(W0)))
print('C131-CF: ' + '=' * 96)
print('C131-CF: §11 — « Static COM displacement: 20-28% B0 » au point de fonctionnement le PLUS')
print('C131-CF:       FAVORABLE admissible : longueur livree exactement au plafond de 1,26.')
print('C131-CF:       Interpolation a DEUX POINTS entre le moteur livre et le lot c128 archive,')
print('C131-CF:       sur les instruments ARBITRES des deux clauses (deciles / masse d aire).')
# (commande, longueur deciles, COM masse d'aire) aux deux points archives
PTS = {'chestL': ((1.2195, 1.3363, 0.2011), (1.1290, 1.2512, 0.1615)),
       'chestR': ((1.2125, 1.3183, 0.2117), (1.1129, 1.2350, 0.1700))}
PLAFOND_L, PLANCHER_COM = 1.26, 0.20
for ch, (A, B) in PTS.items():
    (cA, lA, mA), (cB, lB, mB) = A, B
    f = (PLAFOND_L - lB) / (lA - lB)            # fraction du segment B->A
    cmd = cB + f * (cA - cB)
    com = mB + f * (mA - mB)
    deficit = PLANCHER_COM - com
    lam = cmd - 1.0                              # (D - I) le long de l axe de longueur
    a = deficit / lam                            # en B0
    print('C131-CF:   %-7s commande %.4f  ->  COM %.4f B0  ·  deficit %.4f B0 (%.1f %% du plancher)'
          % (ch, cmd, com, deficit, deficit / PLANCHER_COM * 100.0))
    print('C131-CF:   %-7s ancrage exige : %.4f B0 = %.1f u = %.2f cm  (proximal, le long de racine->apex)'
          % ('', a, a * B0, cm(a * B0)))
print('C131-CF: ' + '-' * 96)
print('C131-CF: §10 — « Outward COM migration per breast: 4-10% W0 ». MEME degre de liberte, sur')
print('C131-CF:       sa composante LATERALE. Budget publie par `ROOM-SPEC10` (w>0.00, % W0) :')
LW = 1.23 - 1.0                                  # SupineWidthScale - 1
SPEC10 = {'chestL': (-1.283, +2.906, -0.825, +0.797),
          'chestR': (-3.824, +2.379, -2.299, -3.744)}
for ch, (sk, diag, cis, tot) in SPEC10.items():
    besoin = 4.00 - tot
    a = besoin / LW / 100.0                      # en W0
    print('C131-CF:   %-7s squel. %+0.3f + diagonal %+0.3f + cisaillement %+0.3f = %+0.3f  (plancher +4.00)'
          % (ch, sk, diag, cis, tot))
    print('C131-CF:   %-7s il manque %+0.3f %%W0 -> ancrage lateral %.4f W0 = %.1f u = %.2f cm'
          % ('', besoin, a, a * W0, cm(a * W0)))
print('C131-CF: ' + '-' * 96)
print('C131-CF: RESERVE, PUBLIEE AVEC LE CHIFFRE ET NON EN NOTE DE BAS DE PAGE :')
print('C131-CF:   (1) §11 est mesure directement par c131_anchor_dof.py ; §10 ne l est PAS ici —')
print('C131-CF:       sa ligne est une EXTRAPOLATION du meme mecanisme, pas une mesure ;')
print('C131-CF:   (2) sur chestR, §10 demande un ancrage lateral d un TIERS de la largeur de')
print('C131-CF:       l organe ET porte un terme SQUELETTIQUE de -3,824 %W0 que l ancrage ne')
print('C131-CF:       touche pas. L ancrage ne ferme donc PAS §10 sur chestR a lui seul ;')
print('C131-CF:   (3) l invariance de longueur est EXACTE pour une peau pilotee par UNE matrice ;')
print('C131-CF:       la chaine en porte DEUX, melangees par les poids. C est la mesure directe')
print('C131-CF:       qui doit dire de combien elle est brisee, et son falsificateur est 0,5 %.')
