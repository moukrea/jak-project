# Sortir un vrai signal HDR sur les ecrans qui le supportent

## Defaut cite
- 2026-09-06 : « Mhhhh ça change effectivement l'image, les blancs sont brûlés ! Mon Honor supporte le HDR, ça l'exploite pas ! Et quand ça supporte par le HDR ça devrait être... Tonemappé je crois qu'on dit ? Vers du SDR pour les écrans qui ne sont pas HDR, en gros par défaut ça devrait être tonemappé en SDR (de la meilleure façon possible pour pas écraser les détails de trop) sauf quand on active le HDR (une opt… »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Par DEFAUT le jeu sort du SDR bien tonemappe (c'est lighting-hdr). Ce chantier ajoute la sortie HDR native quand l'ecran la supporte. Le moteur emet `hdr_out_defects=N` :
  (1) la capacite de l'ecran est DETECTEE et publiee (`hdr_out_display_caps` : les modes reellement annonces par le systeme, Android comme bureau) ;
  (2) l'option n'existe dans le menu que si un mode est annonce — jamais un reglage qui ne fait rien ;
  (3) activee, la chaine sort dans l'espace annonce, sans double compression : `hdr_out_tonemaps_applied` = 1, jamais 2 ;
  (4) desactivee, la sortie est identique au bit a celle de lighting-hdr ;
  (5) la detection entre dans l'auto-configuration du premier demarrage, avec le mode retenu publie.
Zero. Preuve sur un ecran HDR reel — l'appareil de l'owner est le seul qu'on connaisse.

## Preuve exigee
`hdr_out_defects == 0` dans `reports/hdr-display-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-display-output device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options : une ligne « sortie HDR » qui n'apparait QUE si l'ecran le supporte. Sur ton Honor elle doit etre la ; activee, les hautes lumieres doivent gagner en eclat sans que le reste change de teinte..

## Hors perimetre
Ne touche pas a la courbe de compression SDR : c'est lighting-hdr.
