> LIS D'ABORD `prompts/item-grass-lod-popin-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'herbe lointaine change de representation sans que rien apparaisse ni saute

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 17. Section 11 du prompt de mission, sautee par la premiere redaction de la SPEC et ajoutee le 12/09. ATOUT DEJA EN MAIN : les paliers sont IMBRIQUES PAR CONSTRUCTION (section 4) — un palier bas est le PREFIXE EXACT du tableau de candidats — donc « aucune redistribution des positions » est deja vrai entre paliers. Ce qui reste a prouver, c'est le franchissement de seuil : apparition, disparition, rotation, saut de couleur, oscillation autour du seuil.

## Livrable
`grass_popin_defects` = 0, somme de termes publies SEPAREMENT.
1. AUCUNE REDISTRIBUTION, AUCUNE ROTATION, AUCUN SAUT DE COULEUR AU SEUIL. Sur un travelling qui franchit chaque seuil de LOD declare, publier le compte de brins dont la position, le lacet ou la couleur bougent au-dela d'une tolerance declaree entre les deux images qui encadrent le seuil : zero, avec le compte de brins suivis comme denominateur.
2. AUCUNE APPARITION NI DISPARITION BRUTALE. Publier la plus grande variation du compte de brins dessines d'une image a la suivante sur ce meme travelling, en fraction des brins presents, sous un plafond DECLARE. Un palier qui ajoute ou retire un bloc en une image est le defaut.
3. PAS D'OSCILLATION AUTOUR D'UN SEUIL. Camera tenue a la distance de seuil avec un tremblement declare, publier le nombre de transitions de LOD par seconde, sous un plafond declare. L'hysteresis se MESURE : p […suite dans le contrat]

## Preuve exigee
`grass_popin_defects == 0` dans `reports/grass-lod-popin/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-lod-popin device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Avancer et reculer vers une grande etendue d'herbe : rien ne doit apparaitre d'un coup, rien ne doit disparaitre d'un coup, et l'herbe ne doit pas clignoter quand on s'arrete pile a la distance de bascule..

## Hors perimetre
Ne change ni le culling par chunk (`grass-chunk-cull`) ni la densite des paliers, qui est un acquis. Ne touche pas au bord sur le vide. Tout ce qui n'est pas cet item.
