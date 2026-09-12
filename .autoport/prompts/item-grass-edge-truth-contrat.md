# Le bord qui donne sur le vide, etabli par la geometrie et non par l'absence de voisin — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC sections 2 et 16. Le detecteur actuel (`GrassBakeCore.cpp:596-680`) declare qu'une arete ouvre sur le vide quand AUCUN AUTRE TRIANGLE TEXTURE HERBE ne la partage. Il n'existe aucun test geometrique du vide. Une frontiere de materiau — pelouse vers terre — produit donc la meme signature qu'un precipice. Les terrasses de Sandover ont des faces de chute EN TERRE : c'est la cause racine des onze rounds, et le round 4 est un faux vert documente pour cette raison exacte. Cet item etablit la donnee, il ne dessine rien.

## Livrable — le contrat, en entier

`grass_edge_misclassified` = 0, somme de termes publies SEPAREMENT.
1. LES HUIT CLASSES SONT SEPAREES ET COMPTEES. Pour chaque arete de triangle de sol, publier laquelle des huit classes de la SPEC la reclame : limite de triangle, couture d'UV, separation de materiau, rupture de normale, limite de chunk, limite de mesh superpose, transition vers un chemin, VERITABLE BORD SUR LE VIDE. Le defaut compte les aretes qu'AUCUNE classe ne reclame et celles que DEUX reclament. Publier la table par niveau.
2. LA SONDE EST GEOMETRIQUE ET SE VERIFIE SUR DES CAS NOMMES. Publier le verdict de la sonde de plancher sur les dix cas de la SPEC — plateforme etroite, coin convexe, coin concave, ilot, pente proche d'une falaise, surfaces empilees, pont, surplomb, cavite, bord partiellement masque. Chaque cas porte une reponse ATTENDUE declaree AVANT la course. Tout desaccord compte.
3. LE FAUX VERT DU ROUND 4 DEVIENT IMPOSSIBLE. Publier le compte de vrais bords sur le vide trouves sur les terrasses dont la face de chute est en TERRE — le cas exact qui rendait zero brin pendant que les metriques passaient. Ce compte doit etre NON NUL, et publie par niveau a cote du compte que l'ancienne regle trouvait.
4. AUCUN PLACEMENT NE CHANGE ENCORE. Le compte de brins poses et leurs positions sont IDENTIQUES a ceux d'avant, sur un vantage nomme. Cet item cuit et publie une donnee ; il ne place pas un brin.
PREUVE : `FEATURE grass-edge-truth armed=1 hits=<aretes de sol classees>` + la ligne `grass_edge_misclassified=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

NE DESSINE AUCUN BRIN et n'en deplace aucun. La retombee elle-meme est `grass-edge-falloff`, qui depend de cet item. Ne touche ni aux chemins ni aux zones nues. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Rien a voir dans le jeu. Vue de debug : chaque arete de sol coloree par sa classe, et les vrais bords sur le vide en evidence.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

