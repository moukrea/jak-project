> LIS D'ABORD `prompts/item-grass-edge-truth-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le bord qui donne sur le vide, etabli par la geometrie et non par l'absence de voisin

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC sections 2 et 16. Le detecteur actuel (`GrassBakeCore.cpp:596-680`) declare qu'une arete ouvre sur le vide quand AUCUN AUTRE TRIANGLE TEXTURE HERBE ne la partage. Il n'existe aucun test geometrique du vide. Une frontiere de materiau — pelouse vers terre — produit donc la meme signature qu'un precipice. Les terrasses de Sandover ont des faces de chute EN TERRE : c'est la cause racine des onze rounds, et le round 4 est un faux vert documente pour cette raison exacte. Cet item etablit la donnee, il ne dessine rien.

## Livrable
`grass_edge_misclassified` = 0, somme de termes publies SEPAREMENT.
1. LES HUIT CLASSES SONT SEPAREES ET COMPTEES. Pour chaque arete de triangle de sol, publier laquelle des huit classes de la SPEC la reclame : limite de triangle, couture d'UV, separation de materiau, rupture de normale, limite de chunk, limite de mesh superpose, transition vers un chemin, VERITABLE BORD SUR LE VIDE. Le defaut compte les aretes qu'AUCUNE classe ne reclame et celles que DEUX reclament. Publier la table par niveau.
2. LA SONDE EST GEOMETRIQUE ET SE VERIFIE SUR DES CAS NOMMES. Publier le verdict de la sonde de plancher sur les dix cas de la SPEC — plateforme etroite, coin convexe, coin concave, ilot, pente proche d'une falaise, surfaces empilees, pont, surplomb, cavite, bord partiellement masque. Chaque cas porte une reponse ATTENDUE declaree AVANT la course. Tout desaccord compte.
3. LE FAUX VERT DU ROUND […suite dans le contrat]

## Preuve exigee
`grass_edge_misclassified == 0` dans `reports/grass-edge-truth/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-edge-truth x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu. Vue de debug : chaque arete de sol coloree par sa classe, et les vrais bords sur le vide en evidence..

## Hors perimetre
NE DESSINE AUCUN BRIN et n'en deplace aucun. La retombee elle-meme est `grass-edge-falloff`, qui depend de cet item. Ne touche ni aux chemins ni aux zones nues. Tout ce qui n'est pas cet item.
