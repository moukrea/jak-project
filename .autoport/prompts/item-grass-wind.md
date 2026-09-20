> LIS D'ABORD `prompts/item-grass-wind-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Un vent qui a une direction, et qui courbe le brin au lieu de le faire pivoter

## Defaut cite
- 2026-09-20 : « C'est vraiment bof bof, j'ai l'impression que tout bouge par… »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 8. L'herbe a UN SEUL SINUS a 0,271 Hz, sans rafale, et surtout SANS DIRECTION DE VENT : chaque brin oscille le long de son propre lacet aleatoire, donc le champ n'a aucun cap commun. ATTENTION, ORDRE DE L'OWNER DU 12/09 : « le shader breeze.glsl est tres peu satisfaisant aussi, tres rigide, pas ouf du tout, donc attention ». L'item `foliage-wind` porte DEUX REFUS COMPLETS. On reprend sa CHARPENTE TEMPORELLE — plusieurs bandes de frequence, un cap commun qui derive, un front de rafale — et PAS sa loi de flexion, qui fait pivoter l'element autour d'un point d'ancrage, mouvement d'objet dur. […suite dans le contrat]

## Livrable
`grass_wind_defects` = 0, somme de termes publies SEPAREMENT.
1. LE CHAMP A UN CAP : publier la dispersion angulaire des directions de flexion sur une scene et une camera fixes. Elle est maximale aujourd'hui ; elle doit s'effondrer sous un plafond declare autour du cap du vent.
2. LE BRIN SE COURBE, IL NE PIVOTE PAS : publier le retard de phase entre la base et la pointe d'un meme brin, aujourd'hui nul, au-dessus d'un plancher declare. C'est la grandeur qui separe cette loi de celle que l'owner a refusee deux fois.
3. LA TOUFFE BOUGE ENSEMBLE SANS BOUGER PAREIL : publier la correlation des phases a l'interieur d'une touffe et entre touffes voisines. La premiere haute, la seconde basse, toute […suite dans le contrat]

## Preuve exigee
`grass_wind_defects == 0` dans `reports/grass-wind/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-wind device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Niveau d'entrainement. Deux oui/non : (1) deux touffes voisines bougent-elles avec un decalage visible (phase, amplitude), au lieu de bouger ensemble ? (2) une rafale traverse-t-elle la zone en se voyant PASSER (les touffes se couchent l'une apres l'autre), au lieu d'un mouvement d'ensemble ?.

## Hors perimetre
Ne touche pas au vent du feuillage, qui est un autre item. Ne reprend PAS sa loi de flexion. Tout ce qui n'est pas cet item.
