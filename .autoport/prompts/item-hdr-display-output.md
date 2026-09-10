# Sortir un vrai signal HDR sur les ecrans qui le supportent

## Defaut cite
- 2026-09-10 : « le dernier build je trouve pas trop sombre, mais on retombe sur le quasi 0 diff entre off vs on... je trouve pas ca plus riche, ou vraiment… »

## Cause connue
Refus 10/09 sur l'essai vert : l'owner ne voit « quasi 0 diff » ON/OFF. Les chiffres le confirment quand on lit les BONNES colonnes : marge accordee 2,251 mais `hdr_out_hl_max_x1000` = 1445 — les hautes lumieres ne montent qu'a 1,44x le blanc SDR, on n'utilise meme pas la marge obtenue. Les compteurs de NIVEAUX (17->128) montaient, eux : compter des paliers distincts n'est pas mesurer une amplitude, c'est un miroir. Second grief : la courbe est STATIQUE, la meme partout, alors que le HDR moderne (Dolby Vision, HDR10+) suit le contenu. Voir aussi recharged-gating-real : si OFF n'eteint pas vraiment, l'ecart ON/OFF est nul par construction.

## Livrable
`hdr_out_defects` = 0. Verdicts 1-8 : voir SPEC 4.5. (9) Pas d'assombrissement mesure sur du JEU REEL, plusieurs niveaux et ambiances, nombre d'images publie. (10) La courbe prend pour reference le pic ANNONCE, prouve par l'EFFET : a deux pics annonces, la meme radiance sort a des valeurs differentes, et a 480 l'image n'est pas plus sombre qu'a 1000. (11) AMPLITUDE, PAS COMPTAGE (refus 10/09) : `hdr_out_hl_max_x1000` doit atteindre une fraction majoritaire de la marge REELLEMENT accordee (`hdr_out_ratio_max_x1000`) sur du jeu reel — 1445 pour 2251 accordes est un DEFAUT. Un compteur de niveaux distincts ne vaut plus verdict a lui seul. (12) COURBE DYNAMIQUE (refus 10/09) : elle suit le contenu dans le temps, facon Dolby Vision / HDR10+, jamais un reglage unique applique partout. Publier la SERIE des parametres effectifs sur un parcours traversant plein jour, interieur sombre et grotte : ils doivent CHANGER, et la transition etre lissee (aucun pompage visible). Une courbe constante = DEFAUT. Preuve sur le Honor.

## Preuve exigee
`hdr_out_defects == 0` dans `reports/hdr-display-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-display-output device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options : une ligne « sortie HDR » qui n'apparait QUE si l'ecran le supporte. Sur ton Honor elle doit etre la ; activee, les hautes lumieres doivent gagner en eclat sans que le reste change de teinte..

## Hors perimetre
Ne pas regresser le SDR livre. Profils HDR distincts autorises, aucune egalite numerique SDR/HDR exigee. Pas de nouveau chemin LDR demande.
