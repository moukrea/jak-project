# Sortir un vrai signal HDR sur les ecrans qui le supportent

## Defaut cite
- 2026-09-10 : « faut aligner aux capacites device ! Voila pourquoi je trouve ca trop sombre, t'as calibre pour 1000 nits alors que le Honor expose 480 ! Faut que ca s'aligne automatiquement ! C'est debile de caler a 1000 nits pour tout… »

## Cause connue
Essai 8 : la marge est enfin accordee (ratio 3,998), ombres 17->127 et hautes lumieres 17->128. MAIS l'owner joue et trouve l'image TROP SOMBRE (10/09), alors que `hdr_out_darkening_pct` = 0. Contradiction expliquee : l'assombrissement n'est mesure que pendant l'auto-test (phases 1-4, kPhaseFrames images), pas sur le jeu qu'il parcourt. Et `hdr_out_peak_adaptive` = 0 : rien ne prouve que la COURBE prend le pic annonce (480) pour reference — `u_out_max_nits` le recoit, mais la porte ne lit qu'un nombre publie.

## Livrable
`hdr_out_defects` = 0. Verdicts 1-7 : voir SPEC 4.5. (8) `hdr_out_ui_white_nits` >= blanc SDR du systeme : UI, sous-titres, sprites BLANCS. (9) PAS D'ASSOMBRISSEMENT LA OU L'OWNER JOUE : `hdr_out_darkening_pct` <= 5 mesure sur du JEU REEL, plusieurs niveaux et plusieurs ambiances, pas seulement pendant l'auto-test ; publier le nombre d'images de jeu echantillonnees. (10) ALIGNEMENT AUTOMATIQUE AU PIC DE L'ECRAN (refus 10/09) : la courbe prend pour reference le pic ANNONCE par l'ecran, jamais une constante. Preuve par l'EFFET, pas par un nombre publie : a deux pics annonces differents (480 reel, 1000 simule), la MEME radiance d'entree doit sortir a des valeurs differentes, et a 480 l'image ne doit pas etre plus sombre qu'a 1000. `hdr_out_peak_adaptive` = 1. (11) EFFET AUX DEUX BOUTS : plus de niveaux distincts dans les ombres ET dans les hautes lumieres qu'a OFF, et luminance qui DEPASSE le blanc SDR (`hdr_out_hdr_sdr_ratio_x1000` > 1000). Identique a OFF = DEFAUT. Preuve sur le Honor.

## Preuve exigee
`hdr_out_defects == 0` dans `reports/hdr-display-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-display-output device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options : une ligne « sortie HDR » qui n'apparait QUE si l'ecran le supporte. Sur ton Honor elle doit etre la ; activee, les hautes lumieres doivent gagner en eclat sans que le reste change de teinte..

## Hors perimetre
Ne pas regresser le SDR livre. Profils HDR distincts autorises, aucune egalite numerique SDR/HDR exigee. Pas de nouveau chemin LDR demande.
