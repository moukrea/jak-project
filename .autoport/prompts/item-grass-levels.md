# L'herbe existe ailleurs que sur Geyser Rock

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 15. `background_common.h:110` porte `kGrassLevels[] = {"training"}`. Dix niveaux portent des textures de sol herbeux : training, beach, village1, village2, jungle, rolling, ogre, swamp, finalboss, firecanyon. Un seul a de l'herbe. `beach` y a ete ajoute puis RETIRE le 31/08 sur la parole de l'owner. Aucun item du backlog ne porte cet elargissement, et il n'entre en collision avec rien.

## Livrable
`grass_level_defects` = 0, somme de termes publies SEPAREMENT, PAR NIVEAU ajoute.
1. LA CLASSIFICATION TIENT SUR LE NIVEAU : publier le compte de triangles eligibles et le compte de desaccords entre les deux sources. Un niveau dont le desaccord depasse une proportion declaree n'est PAS ajoute, et l'item le dit.
2. LE COUT EST CHIFFRE AVANT D'AJOUTER : temps de cuisson, taille des cinq bakes, temps de chargement, cadence sur l'appareil, herbe allumee et eteinte. Un niveau qui fait tomber la cadence sous un plancher declare n'est pas ajoute.
3. LE REPLI EST IMMEDIAT : retirer un niveau de la liste le ramene a son rendu d'origine, identique au bit. Le prouver sur un niveau retire.
4. GEYSER ROCK NE REGRESSE PAS : reprendre ses grandeurs et montrer qu'elles gardent leurs valeurs. C'est le seul niveau valide par l'owner, il sert de non-regression.
ORDRE DE DEPLOIEMENT : village1 d'abord — ses terrasses a faces de chute en terre sont le cas exact qui a fait echouer onze rounds — puis jungle, qui a deux textures d'overhang et une texture de chemin listee parmi les sols herbeux.
PREUVE : `FEATURE grass-levels armed=1 hits=<brins poses hors de training>` + la ligne `grass_level_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`grass_level_defects == 0` dans `reports/grass-levels/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-levels device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : A Sandover puis dans la jungle : il doit y avoir de l'herbe, et elle doit ressembler a celle de Geyser Rock sans en etre la copie..

## Hors perimetre
N'ajoute aucun niveau sans que son cout soit chiffre. Ne touche pas au rendu, qui est fixe par les items precedents. Tout ce qui n'est pas cet item.
