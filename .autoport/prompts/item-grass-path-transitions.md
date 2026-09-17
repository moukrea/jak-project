> LIS D'ABORD `prompts/item-grass-path-transitions-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'herbe s'arrete progressivement au bord des chemins, sans bande vide ni decoupe nette

## Defaut cite
- 2026-09-17 : « Tu dis "Le ticket se rejouera après « l'herbe sur Sandover e… »

## Cause connue
17/09 OWNER (Linear) : « c'est pas à tester, c'est pas validé du tout ! ». La mesure de l'essai 1 (0 defaut de transition) a ete faite sur Geyser Rock, qui n'a pas de chemin, et Sandover n'a pas encore d'herbe. Cet item se rejoue APRES grass-levels, sur Sandover et la jungle, la ou des chemins existent : la porte se mesure la, et c'est la que l'owner regardera.

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 9. La transition est aujourd'hu […suite dans le contrat]

## Livrable
`grass_transition_defects` = 0, somme de termes publies SEPAREMENT.
1. PAS DE BANDE VIDE : la largeur entre le dernier brin et la limite reelle de la zone nue, mesuree sur des vantages NOMMES couvrant un chemin traversant et une zone de terre, reste sous un plafond DECLARE. Publier la largeur mesuree et le plafond.
2. PAS D'INVASION : le compte de brins dont la racine tombe sur une surface non herbeuse vaut zero, avec son denominateur — le compte de brins testes — publie a cote.
3. PAS DE DECOUP […suite dans le contrat]

## Preuve exigee
`grass_transition_defects == 0` dans `reports/grass-path-transitions/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-path-transitions device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur Sandover puis dans la jungle, une fois l'herbe posee (grass-levels) : le bord des chemins et des zones de terre, l'herbe couvre jusqu'a la limite reelle sans bande pelee, le chemin reste degage..

## Hors perimetre
Ne touche pas au bord donnant sur le VIDE : c'est le sujet de `grass-edge-truth` et `grass-edge-falloff`, deux items distincts de cette meme campagne. Ne change ni la densite globale ni les distances d'affichage. Tout ce qui n'est pas cet item.
