#!/usr/bin/env python3
"""c40e3_impossible.py — AUCUNE VALEUR DE LA BORNE NE PEUT TENIR LES DEUX LIGNES DE SA SPEC 22.

NATURE  : une ARITHMETIQUE de dimensionnement (longueurs, sans dynamique). Elle ne mesure pas un
          comportement : elle montre ce que la geometrie livree REND POSSIBLE.
REPERE  : unites de jeu, pose de BIND pour les longueurs, course livree pour les elongations.
ABSENT  : si le segment de chair simule couvrait l'organe, les deux lignes seraient compatibles et
          ce script rendrait « aucune contradiction ».
"""
BL_SEG   = {'chestL': 140.4225, 'chestR': 144.2315}    # PHYSBONE l=1, lBoob->lBooc
BL_LEV   = {'chestL': 1040.5006, 'chestR': 1039.0379}  # PHYSBONE l=0, chest->lBoob (LEVIER)
B0_DECL  = 602.0                                       # b0= dans physics_chains.txt (sa SPEC 6)
B0_MES   = {'chestL': 734.21, 'chestR': 766.60}        # racine->apex mesure sur le mesh livre
DELIV    = {'chestL': 179.7, 'chestR': 174.8}          # rrm moyen (u), canal radial du maillon de chair
CLAMP    = 0.25                                        # SPEC 22 AbsoluteStretchClamp
COMCAP   = 0.40                                        # SPEC 22 HardMaxCOMDisplacement, en B0

print('LA CONTRADICTION DE DIMENSIONNEMENT, EN TROIS LIGNES PAR SEIN')
print('NATURE arithmetique de longueurs · REPERE pose de BIND + course livree · ABSENT aucune contradiction')
print()
for c in ('chestL', 'chestR'):
    seg, lev, b0m, dl = BL_SEG[c], BL_LEV[c], B0_MES[c], DELIV[c]
    print('=== %s' % c)
    print('  levier chest->lBoob (AUCUNE chair)            %8.1f u   = %.2f B0' % (lev, lev / B0_DECL))
    print('  SEUL segment de chair simule lBoob->lBooc     %8.1f u   = %.2f B0' % (seg, seg / B0_DECL))
    print('  organe, racine->apex mesure sur le mesh       %8.1f u   (declare %.0f)' % (b0m, B0_DECL))
    print('  -> le segment couvre %.1f %% de l\'organe' % (100.0 * seg / b0m))
    print()
    print('  CE QUE SA SPEC 22 AUTORISE, LES DEUX LIGNES :')
    org_max = CLAMP * b0m
    loc_max = CLAMP * seg
    print('    elongation de tissu de l\'ORGANE   <= 25 %% de %7.1f =  %7.1f u' % (b0m, org_max))
    print('    deformation LOCALE du segment     <= 25 %% de %7.1f =  %7.1f u' % (seg, loc_max))
    print('    le moteur route TOUTE l\'elongation de l\'organe PAR ce segment.')
    print('    -> pour livrer %7.1f u a %.0f %% de deformation locale, il faudrait un segment de'
          % (org_max, 100 * CLAMP))
    print('       %7.1f u. Il en fait %7.1f. **FACTEUR MANQUANT x%.2f**'
          % (org_max / CLAMP, seg, (org_max / CLAMP) / seg))
    print()
    print('  ET CE QUE LE MOTEUR LIVRE AUJOURD\'HUI :')
    print('    elongation livree                      %7.1f u' % dl)
    print('      / organe %7.1f  = %6.1f %%   (bande de sa SPEC 22 : 21-25 %% exceptionnel)'
          % (b0m, 100 * dl / b0m))
    print('      / segment %7.1f = %6.1f %%   **x%.1f la clef de 25 %%**'
          % (seg, 100 * dl / seg, (dl / seg) / CLAMP))
    print()
    print('  LES DEUX SEULS CHOIX QU\'UNE BORNE OFFRE, ET ILS SONT TOUS LES DEUX FAUX :')
    print('    borne en ORGANE  (0.25*%.0f = %6.1f u) -> deformation locale %6.1f %%  (x%.1f la clef)'
          % (b0m, org_max, 100 * org_max / seg, (org_max / seg) / CLAMP))
    print('    borne en SEGMENT (0.25*%.1f = %6.1f u) -> elongation d\'organe %6.2f %%  (plancher'
          ' de la bande courante 5 %%: %s)'
          % (seg, loc_max, 100 * loc_max / b0m,
             'TENU' if 100 * loc_max / b0m >= 5.0 else '**SOUS LE PLANCHER**'))
    print('    borne actuelle   (0.40*%.0f = %6.1f u) -> %6.1f %% de la longueur du segment'
          % (B0_DECL, COMCAP * B0_DECL, 100 * COMCAP * B0_DECL / seg))
    print()
print('CE QUE CETTE ARITHMETIQUE PROUVE, ET CE QU\'ELLE NE PROUVE PAS')
print('  PROUVE : avec le segment livre, aucune valeur de la borne ne tient a la fois la ligne')
print('           « elongation de tissu 21-25 %% » et la ligne « deformation locale <= 25 %% ».')
print('           Le choix est entre violer la seconde d\'un facteur ~5 (etat actuel) et tomber')
print('           sous le plancher de la premiere. C\'est un defaut de GEOMETRIE, pas de reglage.')
print('  NE PROUVE PAS : que rallonger le segment suffirait. Ca rend seulement les deux lignes')
print('           compatibles ; le reste (SPEC 24, SPEC 33, la penetration) se re-mesure apres.')
