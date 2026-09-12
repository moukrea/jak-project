# Une touffe abritee bouge moins qu'une touffe exposee, et c'est cuit

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 8. L'amplitude du vent est aujourd'hui la meme partout : rien ne distingue une touffe en plein vent d'une touffe dans un recoin. L'owner veut cette difference, et elle ne peut pas etre calculee au chargement — ce serait une analyse de la geometrie environnante, exactement ce que le contrat interdit.

## Livrable
`grass_exposure_defects` = 0, somme de termes publies SEPAREMENT.
1. L'EXPOSITION EST CUITE, UN SCALAIRE PAR TOUFFE : publier sa distribution. Une distribution concentree sur une seule valeur veut dire que la mesure ne distingue rien.
2. LA DIFFERENCE EST MESUREE SUR DEUX POPULATIONS NOMMEES : un jeu de touffes exposees et un jeu de touffes abritees, choisis a la main dans le niveau. L'ecart d'amplitude entre les deux est au-dessus d'un plancher declare.
3. LE RUNTIME N'ANALYSE RIEN : publier le compte d'operations de lancer de rayon executees au chargement et par image, qui vaut zero. Le moteur multiplie une valeur lue, rien d'autre.
4. LE COUT DE CUISSON EST CHIFFRE, par niveau, et le fichier ne grossit pas au-dela d'un plafond declare.
PREUVE : `FEATURE grass-wind-exposure armed=1 hits=<touffes portant une exposition cuite>` + la ligne `grass_exposure_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`grass_exposure_defects == 0` dans `reports/grass-wind-exposure/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-wind-exposure x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur le niveau d'entrainement : une touffe en plein vent sur une plateforme degagee doit bouger nettement plus qu'une touffe coincee contre une paroi..

## Hors perimetre
Ne change pas la loi de vent elle-meme, qui est l'item precedent. Tout ce qui n'est pas cet item.
