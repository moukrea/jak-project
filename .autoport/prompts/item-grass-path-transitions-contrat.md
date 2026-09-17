# L'herbe s'arrete progressivement au bord des chemins, sans bande vide ni decoupe nette — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

17/09 OWNER (Linear) : « c'est pas à tester, c'est pas validé du tout ! ». La mesure de l'essai 1 (0 defaut de transition) a ete faite sur Geyser Rock, qui n'a pas de chemin, et Sandover n'a pas encore d'herbe. Cet item se rejoue APRES grass-levels, sur Sandover et la jungle, la ou des chemins existent : la porte se mesure la, et c'est la que l'owner regardera.

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 9. La transition est aujourd'hui BINAIRE : une surface porte de l'herbe ou n'en porte pas, et la frontiere suit exactement des aretes de triangles. Il n'existe aucun champ de distance, aucun poids, aucune reduction a l'approche. Un correctif partiel existe deja et doit etre generalise : quand un triangle plat conserve partage son arete d'epaule avec une levre rejetee par le filtre de pente, cette arete est traitee comme INTERIEURE, si bien que l'herbe remplit jusqu'a l'epaule au lieu de s'arreter court. C'est exactement le remede au grief de bande vide de l'owner.

## Livrable — le contrat, en entier

`grass_transition_defects` = 0, somme de termes publies SEPAREMENT.
1. PAS DE BANDE VIDE : la largeur entre le dernier brin et la limite reelle de la zone nue, mesuree sur des vantages NOMMES couvrant un chemin traversant et une zone de terre, reste sous un plafond DECLARE. Publier la largeur mesuree et le plafond.
2. PAS D'INVASION : le compte de brins dont la racine tombe sur une surface non herbeuse vaut zero, avec son denominateur — le compte de brins testes — publie a cote.
3. PAS DE DECOUPE PROCEDURALE PARFAITE : publier une mesure de rectitude du bord, sous un plafond declare. Une frontiere qui suit exactement les aretes de triangles est un defaut, pas une transition.
4. LA TRANSITION EST PROGRESSIVE ET DETERMINISTE : densite et hauteur decroissent sur une distance declaree, et deux chargements donnent la MEME frontiere au brin pres.
PREUVE : `FEATURE grass-path-transitions armed=1 hits=<brins situes dans une bande de transition>` + la ligne `grass_transition_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Hors perimetre

Ne touche pas au bord donnant sur le VIDE : c'est le sujet de `grass-edge-truth` et `grass-edge-falloff`, deux items distincts de cette meme campagne. Ne change ni la densite globale ni les distances d'affichage. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Sur Sandover puis dans la jungle, une fois l'herbe posee (grass-levels) : le bord des chemins et des zones de terre, l'herbe couvre jusqu'a la limite reelle sans bande pelee, le chemin reste degage.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-17
> Pour l'herbe au bord des chemins... Bah sandover t'as pas mis l'herbe donc tu me dis de tester mais elle n'est pas là, sur geyser rock (niveau d'entrainement) c'était déjà bon avant qu'on décide re refaire l'herbe... Et il n'y a pas de chemin.

### 2026-09-17
> Bah du coup c'est pas à tester, c'est pas validé du tout ! Il suffit de lire le ticket pour voir que c'est pas à tester ! À moins qu'il y ait une info que j'ai loupé, un build spécifique que j'ai loupé… En tout cas c'est pas bon du tout !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

