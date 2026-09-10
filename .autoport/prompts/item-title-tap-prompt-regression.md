# Au titre, l'invite dit « touche l'ecran » quand il y a un ecran tactile

## Defaut cite
- 2026-09-11 : « TERMINÉ, MAIS RÉGRESSÉ! SUR ANDROID (AVEC TACTILE, SUR SHIELD ON DEVRAIT AVOIR « Appuie sur start ») ON A « Appuie sur start » AU LIEU DE « Appuie sur start ou touche l'écran » »

## Cause connue
Owner 11/09, en validant title-tap : « TERMINÉ, MAIS RÉGRESSÉ ! SUR ANDROID (AVEC TACTILE, SUR SHIELD ON DEVRAIT AVOIR « Appuie sur start ») ON A « Appuie sur start » AU LIEU DE « Appuie sur start ou touche l'écran » ». L'invite est donc choisie sans lire la presence d'un ecran tactile.

## Livrable
`title_prompt_wrong` = 0 : l'invite de l'ecran-titre est choisie sur la PRESENCE d'un ecran tactile, pas sur la plateforme. Tactile present : « Appuie sur start ou touche l'écran ». Absent (SHIELD, PC a la manette) : « Appuie sur start ». Publier, pour la course, le fait tactile lu par le moteur ET l'identifiant de la chaine affichee : ils doivent concorder. Verifier dans chaque langue installee.

## Preuve exigee
`title_prompt_wrong == 0` dans `reports/title-tap-prompt-regression/proof.txt`.
Le proof se produit par `lib/proof_run.sh title-tap-prompt-regression device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : l'ecran-titre sur ton telephone : « Appuie sur start ou touche l'écran ».

## Hors perimetre
Ne pas retoucher le comportement du tap lui-meme, seulement le texte affiche.
