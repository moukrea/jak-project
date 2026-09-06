# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-06 : « J'ai l'impression que même avec le Real Time lighting à off on a quand même les blancs brûlés, est ce que tu passe bien par ce paramètre pour gate nos effets ou tu les code en dur en remplaçant le vanilla, alors que la SPEC stipule qu'on peut rester au rendu d'origine si on le veut »

## Cause connue
Blancs brules signales par l'owner sur la config PAR DEFAUT (master ON, eclairage temps reel OFF). Mecanisme complet, verifie ligne a ligne : SPEC-refonte-lumiere.md §8 item 2. En un mot : les composites C et E gardent leur propre exposition et leur propre pow(1/2.2) (shade.glsl:679-703, 740-744), le RGBA16F a retire le plafond qui masquait le depassement, et tonemap.frag en rajoute un second etage. La preuve de lighting-unify montre que seuls C et E dessinent par defaut (A=0 B=0 C=304192 E=3191131).

## Livrable
La courbe de compression vers SDR doit PRESERVER LE DETAIL. Le moteur emet `hdr_tonemap_defects=N`, somme de six verdicts publies aussi separement, mesures sur le jeu de reference ORIGINE-LUMIERE (la config que l'owner joue) : (1) part de pixels satures <= celle de l'ORIGINE ; (2) contraste local du decile le plus lumineux >= 95 % de la reference ; (3) courbe monotone sans coude ; (4) master eteint => sortie identique au bit a ORIGINE-TOTAL ; (5) le jeu ORIGINE-LUMIERE existe et sert de base aux verdicts 1-3 ; (6) `tonemap_sites` = 1 dans les TROIS configurations, pas seulement eclairage temps reel allume. Zero. Detail et arbitrage C/E : SPEC §8 item 2 et §4.5.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
La sortie HDR vers un ecran compatible appartient a hdr-display-output. La regle des deux origines et la hierarchie des interrupteurs : SPEC §0.2, §1.1, §6.2.
