# Sortir un vrai signal HDR sur les ecrans qui le supportent

## Defaut cite
- 2026-09-07 : « Après on peut quand même avoir des adaptations différentes sur écran SDR et écran HDR, le fait de partager les altérations c'était de la supposition, je suis pas expert ! Je compte sur toi mais fais pas de la merde »
- 2026-09-09 : « sur écran HDR, on doit aussi pouvoir toggle ça à off hein ? Pour ceux qui préfèreraient la sortie SDR actuelle sur leur écran HDR par example. Comme sur certains jeux actuels qui supportent le HDR, c'est pas parce que leur écran supporte le HDR qu'ils peuvent pas activer/désactiver le HDR ! Attentio… »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Par DEFAUT le jeu sort du SDR bien tonemappe (lighting-hdr, valide le 09/09). Ce chantier ajoute la sortie HDR native vers l'ECRAN, sujet distinct du calcul HDR interne. `hdr_out_defects=N` : (1) capacite de l'ecran DETECTEE et publiee (`hdr_out_display_caps`, modes reellement annonces par le systeme, Android et bureau) ; (2) l'option n'apparait que si un mode est annonce — jamais un reglage qui ne fait rien ; (3) SUR UN ECRAN HDR, l'option reste un VRAI interrupteur : OFF = la sortie SDR actuelle, au choix du joueur, jamais force par la capacite de l'ecran (`hdr_out_forced_on` = 0) ; (4) activee, sortie dans l'espace annonce sans double compression (`hdr_out_tonemaps_applied` = 1) ; (5) desactivee, identique au bit a lighting-hdr ; (6) la detection entre dans l'auto-configuration du premier demarrage, mode retenu publie, et le choix persiste. Zero. Preuve sur un ecran HDR reel — le Honor de l'owner.

## Preuve exigee
`hdr_out_defects == 0` dans `reports/hdr-display-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-display-output device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options : une ligne « sortie HDR » qui n'apparait QUE si l'ecran le supporte. Sur ton Honor elle doit etre la ; activee, les hautes lumieres doivent gagner en eclat sans que le reste change de teinte..

## Hors perimetre
Ne pas regresser le SDR livre. Profils HDR distincts autorises, aucune egalite numerique SDR/HDR exigee. Pas de nouveau chemin LDR demande.
