#!/usr/bin/env python3
# c146_ceiling.py — LE PLAFOND D'ORGANE D'UNE DEFORMATION LINEAIRE PAR MAILLON, SOUS LE PLAFOND
# LOCAL DE SA §22. Aucune mesure neuve : tout vient de la trace de la course du cycle 145 et du
# fichier de chaines LIVRE. Le calcul est celui de NOTE-585 (identite du melange) et de NOTE-586
# (le plafond porte sur ce que la chair RECOIT).
#
#   organe = 1 + SOMME(comw) . (D - 1)                      [NOTE-585, verifie a ~1 % sur 5 cellules]
#   le maillon le plus charge recoit  1 + gmx . (D - 1)     [NOTE-586]
#   sa §22 l.303 : cette grandeur RECUE est bornee par `AbsoluteStretchClamp` = 0.25
# donc :
#   organe - 1  <=  cws . asc / gmx
# et reciproquement, la part de chair a piloter pour atteindre une cible d'organe `T` :
#   cws  >=  (T - 1) . gmx / asc
#
# NATURE : rapports sans dimension (echelles d'organe). REPERE : l'axe `out` de §10, celui du
# tri par decile de `ROOM-SPEC1011-LIVREE`. LECTURE HORS DEFAUT : a asc = 0 le plafond disparait
# et l'inegalite devient vide — c'est le controle negatif gratuit.
CH = [
    # nom      cws     gmx      source de cws/gmx = PHYSGRADSET de la course du c145
    ("chestL", 0.5720, 1.1035),
    ("chestR", 0.5450, 1.1128),
]
ASC = 0.25            # `AbsoluteStretchClamp`, physics_chains.txt:111/214, SPEC l.509
BANDE = (1.18, 1.28)  # §10 l.166 « Width: +18 to +28%, nominal +23% »
NOM   = 1.23          # `SupineWidthScale`
# ce que la course a REELLEMENT livre, `ROOM-SPEC1011-LIVREE` (table du c145, l.4553 / l.4565)
LIVRE = {"chestL": 1.1229, "chestR": 1.1308}

print("== PLAFOND D'ORGANE SOUS LE PLAFOND LOCAL DE §22 (asc = %.2f) ==" % ASC)
for nom, cws, gmx in CH:
    ceil_local = ASC / gmx                     # commande maximale admissible (NOTE-586)
    ceil_org   = 1.0 + cws * ceil_local        # organe maximal atteignable
    print("%-7s cws=%.4f gmx=%.4f | commande max %.4f | ORGANE MAX %.4f | livre %.4f | plancher de bande %.2f"
          % (nom, cws, gmx, 1.0 + ceil_local, ceil_org, LIVRE[nom], BANDE[0]))
    print("        deficit contre le PLANCHER de la bande : %+.4f d'organe (le plafond est %s)"
          % (ceil_org - BANDE[0], "SOUS" if ceil_org < BANDE[0] else "au-dessus"))
    for lbl, T in (("plancher 1.18", BANDE[0]), ("nominal 1.23", NOM), ("plafond 1.28", BANDE[1])):
        need = (T - 1.0) * gmx / ASC
        verdict = "IMPOSSIBLE POUR TOUT RIG (cws <= 1 par definition)" if need > 1.0 else "exige un repesage"
        print("        pour atteindre %-13s il faut cws >= %.4f  -> %s" % (lbl, need, verdict))
    # et le meme calcul avec un profil PLAT (gmx = 1), c'est-a-dire en renoncant au gradient de §31
    print("        profil PLAT (gmx=1, §31 abandonnee) : organe max %.4f — %s le plancher"
          % (1.0 + cws * ASC, "toujours SOUS" if 1.0 + cws * ASC < BANDE[0] else "atteint"))
print()
print("§30 l.386 `StrongRootFraction = 0.30` borne la part ANCREE a 0.30, donc cws <= 0.70.")
for nom, cws, gmx in CH:
    print("  %-7s a cws = 0.70 (la valeur que §30 autorise au mieux) : organe max %.4f -> %s"
          % (nom, 1.0 + 0.70 * ASC / gmx,
             "DANS" if 1.0 + 0.70 * ASC / gmx >= BANDE[0] else "ENCORE SOUS le plancher 1.18"))
