> LIS D'ABORD `prompts/item-water-refraction-reflection-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Voir a travers l'eau, et voir le ciel dedans

## Defaut cite
- 2026-09-09 : « bah je valide, beau boulot ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. DepthCue fait deja la seule copie couleur de l'ecran, au bucket 64 apres ocean-near (SPEC 2.5) ; sur GPU a tuiles chaque copie coute deux resolves (SPEC 10). Le cube de ciel capture est la passe P3 de l'eclairage (item lighting-regimes). NOTE 09-09 (perf) : perf-fbo-passes invalide depth/stencil apres la derniere lecture : W0 se place AVANT ce point, marque par un commentaire nomme dans an […suite dans le contrat]

## Livrable
W0 avec couleur : UNE copie apres les alphas, partagee avec DepthCue (qui cesse de blitter la sienne). Refraction avec REJET des echantillons devant la surface. Reflet du cube P3 via env_specular de shade(). Echelle a 4 crans reglable : ciel / cube / planaire 1/4 sur les plans immobiles listes / SSR sur toute l'eau avec repli cube. SPEC 5.6, 6. Publie water_fresnel_max (<= plafond) et water_env_source. PREUVE : `FEATURE water-refraction-reflection armed=1 hits=<pixels d'eau refractes>` + la lign […suite dans le contrat]

## Preuve exigee
`water_scene_copies_per_frame == 1` dans `reports/water-refraction-reflection/proof.txt`.
Le proof se produit par `lib/proof_run.sh water-refraction-reflection device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la fontaine de Sandover et la mer : le fond deforme a travers l'eau, le ciel du moment reflete, et un reflet net sur les bassins immobiles.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Pas de caustiques (item 6).
