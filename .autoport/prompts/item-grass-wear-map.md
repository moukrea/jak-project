# L'herbe est usee la ou l'on passe : carte de frequentation cuite, par taches irregulieres, jamais un masque net, et aucune orbe cachee

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
SPEC herbe §12, qu'aucun item ne portait (audit superviseur 17/09). Donnees disponibles hors ligne : 1 233 orbes, 26 cellules posees + 28 declarees, 110 mouches, 553 acteurs a champ `path`, collision par triangle, praticabilite pat.mode==0. Le maillage de navigation N'EST PAS exporte (extract_actors.cpp:97) : ne pas le supposer. CE TRAVAIL REPREND LE SPIKE OWNER DU 12/07 `.autoport/prompts/phase-Grecharged-grass-wear.md` (architecture en quatre couches, QUATORZE criteres d'acceptation) : il se reprend, il ne se refait pas.

## Livrable
`grass_wear_defects` = 0, somme de termes publies SEPAREMENT.

1. LA CARTE EST CUITE HORS LIGNE : union PROBABILISTE de quatre couches (taches irregulieres autour des collectibles, couloirs le long des trajectoires `path`, transformee de distance depuis les entrees/sorties de zone, bruit coherent). Publier par niveau la part de chaque couche et l'histogramme des valeurs : jamais binaire (au moins 8 niveaux de valeur occupes a plus de 1 % chacun).

2. PLANCHER DE LISIBILITE : aucun collectible masque par l'herbe. Publier le nombre de collectibles dont la couverture d'herbe dans un rayon donne depasse le plancher : 0, sur un denominateur non nul.

3. LES QUATORZE CRITERES DU SPIKE : chacun repris tel quel, un terme par critere, mesure ou compte comme defaut.

4. RIEN A L'EXECUTION : la carte est une donnee lue au chargement ; publier le cout par image de son application (bras ON/OFF, meme vantage, >= 300 images) : ecart nul dans le bruit.

PREUVE : `FEATURE grass-wear-map armed=1 hits=<instances d'herbe attenuees par la carte>` + la ligne `grass_wear_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`grass_wear_defects == 0` dans `reports/grass-wear-map/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-wear-map device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : A Sandover et dans la jungle, une fois l'herbe posee : l'herbe est usee le long des trajets frequentes et autour des orbes, par taches irregulieres, jamais un masque net ; aucune orbe n'est cachee par l'herbe..

## Hors perimetre
Pas de simulation a l'execution, pas de maillage de navigation. Tout ce qui n'est pas cet item.
