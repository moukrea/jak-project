# L'herbe lointaine change de representation sans que rien apparaisse ni saute — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 17. Section 11 du prompt de mission, sautee par la premiere redaction de la SPEC et ajoutee le 12/09. ATOUT DEJA EN MAIN : les paliers sont IMBRIQUES PAR CONSTRUCTION (section 4) — un palier bas est le PREFIXE EXACT du tableau de candidats — donc « aucune redistribution des positions » est deja vrai entre paliers. Ce qui reste a prouver, c'est le franchissement de seuil : apparition, disparition, rotation, saut de couleur, oscillation autour du seuil.

## Livrable — le contrat, en entier

`grass_popin_defects` = 0, somme de termes publies SEPAREMENT.
1. AUCUNE REDISTRIBUTION, AUCUNE ROTATION, AUCUN SAUT DE COULEUR AU SEUIL. Sur un travelling qui franchit chaque seuil de LOD declare, publier le compte de brins dont la position, le lacet ou la couleur bougent au-dela d'une tolerance declaree entre les deux images qui encadrent le seuil : zero, avec le compte de brins suivis comme denominateur.
2. AUCUNE APPARITION NI DISPARITION BRUTALE. Publier la plus grande variation du compte de brins dessines d'une image a la suivante sur ce meme travelling, en fraction des brins presents, sous un plafond DECLARE. Un palier qui ajoute ou retire un bloc en une image est le defaut.
3. PAS D'OSCILLATION AUTOUR D'UN SEUIL. Camera tenue a la distance de seuil avec un tremblement declare, publier le nombre de transitions de LOD par seconde, sous un plafond declare. L'hysteresis se MESURE : publier les deux seuils, celui qui monte et celui qui descend.
4. LA LECTURE LOINTAINE GARDE CE QUI COMPTE. Au palier le plus lointain, publier la presence des chemins, des zones nues, des transitions principales et des differences de biome, chacune comme une grandeur mesuree et comparee a la MEME grandeur au palier proche, dans une tolerance declaree.
PREUVE : `FEATURE grass-lod-popin armed=1 hits=<franchissements de seuil observes>` + la ligne `grass_popin_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Ne change ni le culling par chunk (`grass-chunk-cull`) ni la densite des paliers, qui est un acquis. Ne touche pas au bord sur le vide. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Avancer et reculer vers une grande etendue d'herbe : rien ne doit apparaitre d'un coup, rien ne doit disparaitre d'un coup, et l'herbe ne doit pas clignoter quand on s'arrete pile a la distance de bascule.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

