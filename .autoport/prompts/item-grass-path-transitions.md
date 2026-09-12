> LIS D'ABORD `prompts/item-grass-path-transitions-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'herbe s'arrete progressivement au bord des chemins, sans bande vide ni decoupe nette

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 9. La transition est aujourd'hui BINAIRE : une surface porte de l'herbe ou n'en porte pas, et la frontiere suit exactement des aretes de triangles. Il n'existe aucun champ de distance, aucun poids, aucune reduction a l'approche. Un correctif partiel existe deja et doit etre generalise : quand un triangle plat conserve partage son arete d'epaule avec une levre rejetee par le filtre de pente, cette arete est traitee comme INTERIEURE, si bien que l'herbe remplit jusqu'a l'epaule au lieu de s'arreter court. C'est exactement le remede au grief de bande vide de l'owner.

## Livrable
`grass_transition_defects` = 0, somme de termes publies SEPAREMENT.
1. PAS DE BANDE VIDE : la largeur entre le dernier brin et la limite reelle de la zone nue, mesuree sur des vantages NOMMES couvrant un chemin traversant et une zone de terre, reste sous un plafond DECLARE. Publier la largeur mesuree et le plafond.
2. PAS D'INVASION : le compte de brins dont la racine tombe sur une surface non herbeuse vaut zero, avec son denominateur — le compte de brins testes — publie a cote.
3. PAS DE DECOUPE PROCEDURALE PARFAITE : publier une mesure de rectitude du bord, sous un plafond declare. Une frontiere qui suit exactement les aretes de triangles est un defaut, pas une transition.
4. LA TRANSITION […suite dans le contrat]

## Preuve exigee
`grass_transition_defects == 0` dans `reports/grass-path-transitions/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-path-transitions device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur le niveau d'entrainement et a Sandover : le bord des chemins et des zones de terre. L'herbe doit couvrir jusqu'a la limite reelle, sans bande pelee laissant voir la texture, et le chemin doit rester degage..

## Hors perimetre
Ne touche pas au bord donnant sur le VIDE : c'est un autre sujet et il n'est pas dans cette campagne. Ne change ni la densite globale ni les distances d'affichage. Tout ce qui n'est pas cet item.
