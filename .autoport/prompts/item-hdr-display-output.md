# Sortir un vrai signal HDR sur les ecrans qui le supportent

## Defaut cite
- 2026-09-09 : « oui on doit certes trouver plus de détails dans les ombres (et aussi les lumières) mais pas tout assombrir pour autant sinon c'est un peu un… »

## Cause connue
Refus owner 09/09 sur le build 15:26 : TOUT est plus sombre, les aplats blancs (UI, sous-titres, sprite de chargement) sortent gris clair, et l'interrupteur est hors des reglages Recharged. Lecture : le blanc de reference (paper white, ceiling_x100=236 => ~203 nits sur un ecran a 480) est applique AUSSI a l'UI, qui est du contenu SDR et doit sortir au blanc SDR de l'ecran, pas en dessous ; et la scene est remappee sous son niveau SDR au lieu de ne depasser 1,0 que dans les hautes lumieres.

## Livrable
`hdr_out_defects` = 0 : (1) capacite DETECTEE et publiee ; (2) option visible seulement si un mode est annonce ; (3) vrai interrupteur, `hdr_out_forced_on` = 0, choix persistant ; (4) activee, sortie dans l'espace annonce, un seul tone map ; (5) desactivee, identique au bit a lighting-hdr ; (6) auto-config au premier demarrage. S'AJOUTENT (refus 09/09) : (7) `hdr_out_menu_parent` = eclairage — la ligne vit sous Options > Recharged > Eclairage Recharge ; (8) `hdr_out_ui_white_nits` >= le blanc SDR de l'ecran lu dans le systeme — UI, sous-titres, sprites, aplats blancs sont du contenu SDR et sortent BLANC, jamais gris ; (9) `hdr_out_darkening_pct` <= 5 — la luminance moyenne des tons moyens de la scene ne baisse pas par rapport a la sortie SDR : seules les hautes lumieres au-dela de 1,0 gagnent. ; (10) `hdr_out_peak_nits` = le pic ANNONCE par l'ecran (mMaxLuminance, 480 sur le Honor), et la courbe s'y adapte : blanc SDR ancre, hautes lumieres etendues jusqu'au pic — prouve a DEUX pics au moins (480 reel, 1000 simule par propriete de debug) avec des mesures distinctes, `hdr_out_peak_adaptive` = 1. Preuve sur le Honor.

## Preuve exigee
`hdr_out_defects == 0` dans `reports/hdr-display-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-display-output device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options : une ligne « sortie HDR » qui n'apparait QUE si l'ecran le supporte. Sur ton Honor elle doit etre la ; activee, les hautes lumieres doivent gagner en eclat sans que le reste change de teinte..

## Hors perimetre
Ne pas regresser le SDR livre. Profils HDR distincts autorises, aucune egalite numerique SDR/HDR exigee. Pas de nouveau chemin LDR demande.
