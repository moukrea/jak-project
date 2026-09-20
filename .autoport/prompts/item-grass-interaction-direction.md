> LIS D'ABORD `prompts/item-grass-interaction-direction-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'herbe se couche dans la direction du pas, au lieu de s'ecraser en rond

## Defaut cite
- 2026-09-20 : « Alors j'ai l'impression que c'est toujours très fake et pas… »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 11. Le systeme est plus riche que l'owner ne le croit — Jak, une trainee de quatre echantillons espaces de 0,15 s, la prise de rebord, huit acteurs ecrasables et huit occultants, montee 0,25 s, descente 0,6 s, pierres tombales de 8 s — mais la FORME reste un disque. La direction du deplacement est connue par la trainee et n'est JAMAIS utilisee comme vecteur. PIEGE MATERIEL A RECONDUIRE : sur A […suite dans le contrat]

## Livrable
`grass_interaction_defects` = 0, somme de termes publies SEPAREMENT.
1. LA FLEXION SUIT LE MOUVEMENT : publier l'angle entre la direction de flexion moyenne et la direction de deplacement, sur une traversee scriptee, sous un plafond declare. Aujourd'hui cet angle est aleatoire par construction.
2. LE DEGAGEMENT LATERAL EXISTE : publier l'ecart entre la flexion au centre du contact et celle sur ses bords. Un ecart nul veut dire qu'on ecrase encore en rond.
3. RIEN NE REGRESSE DE L'ACQUIS : le rel […suite dans le contrat]

## Preuve exigee
`grass_interaction_defects == 0` dans `reports/grass-interaction-direction/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-interaction-direction device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Niveau d'entrainement, dans l'herbe. Quatre oui/non : (1) l'herbe se couche-t-elle la ou le corps de Jak passe REELLEMENT (pieds, jambes, et le bras sur un coup de poing, la roue sur un spin), et pas dans un disque ou un cone devant lui ? (2) quand il saute, l'herbe se releve-t-elle progressivement (ressort), et a l'atterrissage se couche-t-elle avec une transition, sans passer d'un etat a l'autre d'un coup ? (3) un spin couche l'herbe en couronne autour de lui, un coup de poing en avant la couche devant le bras ? (4) l'ensemble a-t-il l'air vrai ou fake ?.

## Hors perimetre
Ne change pas la portee ni le nombre d'interacteurs des paliers bas, qui gardent la loi radiale actuelle en repli. Tout ce qui n'est pas cet item.
