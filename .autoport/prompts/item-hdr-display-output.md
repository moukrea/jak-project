# Sortir un vrai signal HDR sur les ecrans qui le supportent

## Defaut cite
- 2026-09-10 : « PAS VALIDE DU TOUT. oui j'ai bien l'impression que le HDR s'ajuste automatiquement, mais c'est pas pour autant qu'il le fait bien [...] ca donne aussi lieu a des endroits avec des contrastes completement crames comme si… »

## Cause connue
Refus 10/09 apres test sur le Honor. L'owner decrit un filtre pose APRES le tone map SDR : pas de gain dans les ombres (la richesse n'y est plus quand on traite l'image) et des contrastes crames facon curseur photoshop pousse a fond. C'est la lecture a retenir tant qu'une mesure ne la contredit pas : la sortie HDR doit partir de la scene HDR AVANT compression SDR, pas de son resultat.

## Livrable
`hdr_out_defects` = 0. Verdicts 1-10 : voir SPEC 4.5 et l'historique de l'item. (11) SOURCE AVANT COMPRESSION (refus 10/09) : la sortie HDR consomme la scene HDR AVANT le tone map SDR. Publier l'identite du tampon lu et le nombre de compressions SDR subies par ce chemin : il doit valoir 0. Lire l'image deja compressee = DEFAUT, quel que soit le reste. (12) RICHESSE DANS LES OMBRES, mesuree sur du jeu reel : le detail distinguable sous le blanc SDR augmente franchement par rapport a OFF ; inchange = DEFAUT. (13) PAS DE CONTRASTE CRAME : publier l'excursion de saturation et de contraste par rapport a la sortie SDR sur les memes images ; un ecart au-dela du plafond declare est un DEFAUT, et les teintes restent celles attendues. (14) AMPLITUDE PILOTEE PAR LA SCENE : la marge accordee est exploitee AU MAXIMUM de ce que la scene contient — une scene lumineuse doit approcher la marge, une scene nocturne ne doit pas y etre forcee. Publier, par scene, la marge accordee, la marge utilisee et le pic de la scene. Un plafond fixe et prudent = DEFAUT. Preuve sur le Honor.

## Preuve exigee
`hdr_out_defects == 0` dans `reports/hdr-display-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-display-output device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Eclairage Recharge : la ligne « sortie HDR ». Activee sur ton Honor, les zones brillantes doivent vraiment ressortir, sans que le reste change..

## Hors perimetre
Ne pas regresser le SDR livre. Profils HDR distincts autorises, aucune egalite numerique SDR/HDR exigee. Pas de nouveau chemin LDR demande.
