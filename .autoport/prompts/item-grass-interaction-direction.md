> LIS D'ABORD `prompts/item-grass-interaction-direction-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'herbe se couche dans la direction du pas, au lieu de s'ecraser en rond

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 11. Le systeme est plus riche que l'owner ne le croit — Jak, une trainee de quatre echantillons espaces de 0,15 s, la prise de rebord, huit acteurs ecrasables et huit occultants, montee 0,25 s, descente 0,6 s, pierres tombales de 8 s — mais la FORME reste un disque. La direction du deplacement est connue par la trainee et n'est JAMAIS utilisee comme vecteur. PIEGE MATERIEL A RECONDUIRE : sur Adreno 618, les lectures de tableaux d'uniformes a index DYNAMIQUE rendent des ordures. Le code deroule a index litteral et plafonne a huit occulteurs pour cette raison. Ce bug NE SE VOIT PAS sur x86.

## Livrable
`grass_interaction_defects` = 0, somme de termes publies SEPAREMENT.
1. LA FLEXION SUIT LE MOUVEMENT : publier l'angle entre la direction de flexion moyenne et la direction de deplacement, sur une traversee scriptee, sous un plafond declare. Aujourd'hui cet angle est aleatoire par construction.
2. LE DEGAGEMENT LATERAL EXISTE : publier l'ecart entre la flexion au centre du contact et celle sur ses bords. Un ecart nul veut dire qu'on ecrase encore en rond.
3. RIEN NE REGRESSE DE L'ACQUIS : le relevement amorti, les pierres tombales, l'annulation a la casse d'une caisse et la distinction entre acteurs caches et acteurs aplatis gardent leurs grandeurs. Publier chacune.
4. LE DEROULAGE A INDEX L […suite dans le contrat]

## Preuve exigee
`grass_interaction_defects == 0` dans `reports/grass-interaction-direction/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-interaction-direction device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur le niveau d'entrainement : marche dans l'herbe et regarde devant les pieds de Jak. L'herbe doit se coucher devant lui et se degager sur les cotes, pas s'aplatir en disque..

## Hors perimetre
Ne change pas la portee ni le nombre d'interacteurs des paliers bas, qui gardent la loi radiale actuelle en repli. Tout ce qui n'est pas cet item.
