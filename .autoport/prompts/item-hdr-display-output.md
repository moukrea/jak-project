# Sortir un vrai signal HDR sur les ecrans qui le supportent

## Defaut cite
- 2026-09-07 : « Je sais pas ce que ça change pour notre plan de refonte et sa spec... Ça doit bien changer des trucs non ? Tu peux y réfléchir un peu et pas juste consigner ça dans une footnote je sais pas trop où ? »
- 2026-09-07 : « Après on peut quand même avoir des adaptations différentes sur écran SDR et écran HDR, le fait de partager les altérations c'était de la supposition, je suis pas expert ! Je compte sur toi mais fais pas de la merde »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
SDR par defaut ; sortie HDR optionnelle si capacites reelles detectees, publiees et integrees a auto-configuration. Option visible seulement sur ecran compatible. SPEC §4.5 : base de rendu HDR, direction artistique coherente ; profils/LUT par niveau et ajustements SDR/HDR distincts autorises selon mesures. Ne jamais repartir du SDR ni reutiliser sa compression pour HDR. Adapter luminance/gamut/encodage aux capacites ecran, sans double compression. hdr_out_defects compte : detection/option incorrecte, profil incorrect pour le niveau/mode selectionne, ecretage intermediaire SDR, transformation sortie multiple, mauvaise adaptation ecran, regression SDR au retour OFF. Publier profil applique, domaine/plage avant sortie et mode sortie ; verifier valeurs >1 preservees avant adaptation. Comparaison retour SDR dans conditions equivalentes, sans campagne de frame exacte. Mesures via proof_run.sh/generic sur ecran HDR reel accessible, aucun support deduit du nom appareil. Mesurer cout GPU si disponible, sinon non mesure. Zero defaut, aucune validation visuelle inventee.

## Preuve exigee
`hdr_out_defects == 0` dans `reports/hdr-display-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-display-output device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options : une ligne « sortie HDR » qui n'apparait QUE si l'ecran le supporte. Sur ton Honor elle doit etre la ; activee, les hautes lumieres doivent gagner en eclat sans que le reste change de teinte..

## Hors perimetre
Ne pas regresser le SDR livre. Profils HDR distincts autorises, aucune egalite numerique SDR/HDR exigee. Pas de nouveau chemin LDR demande.
