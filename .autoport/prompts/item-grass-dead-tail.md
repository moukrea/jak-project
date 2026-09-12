# L'herbe cesse de construire et de televerser ce que rien ne dessine

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, et il porte le lien vers l'investigation complete que l'owner a validee le 12/09. SPEC section 1. `expand()` emet a chaque chargement la queue des trois zones d'overhang — twins de comb, twins de lean, scatter de zone 2, cartes de zone 3 — et n'est gardee par AUCUN `#ifdef`. Or `OG_FEAT_GRASS_OVERHANG` est OFF dans les deux arbres livres, donc le compte de dessin retombe sur `nondroop_n` et cette queue n'est jamais dessinee. Un journal d'aout chiffre la queue a 110 472 instances sur 726 851, soit 15,2 % du tampon, construites, ecrites dans le bake, televersees au GPU, jamais dessinees. Sur beach c'etait 71 %. C'est le gain le moins risque de toute la campagne : rien de visible ne change.

## Livrable
`grass_dead_instances` = 0, somme de termes publies SEPAREMENT.
1. AUCUNE INSTANCE CONSTRUITE N'EST JAMAIS DESSINEE. Publier le compte d'instances emises par l'expansion et le compte d'instances atteintes par un appel de dessin, separement. L'egalite est le verdict.
2. LE GAIN EST CHIFFRE, AVANT ET APRES, sur la MEME course et le MEME palier : octets televerses, temps d'expansion, temps de chargement total. Un gain non chiffre n'est pas un gain.
3. RIEN DE VISIBLE NE CHANGE : l'image est IDENTIQUE AU BIT a celle d'avant, mesuree sur un vantage nomme. Si elle differe, l'item s'arrete et le DIT.
4. LE CHEMIN RESTE CONSTRUCTIBLE : publier un temoin qui dit que la queue est emise quand l'option est allumee a la compilation. On ne supprime pas, on conditionne.
PREUVE : `FEATURE grass-dead-tail armed=1 hits=<instances emises par l'expansion>` + la ligne `grass_dead_instances=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`grass_dead_instances == 0` dans `reports/grass-dead-tail/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-dead-tail device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir. Le gain se mesure en memoire et en temps de chargement..

## Hors perimetre
Ne rouvre PAS l'overhang : l'owner l'a parque sur un verdict de qualite. On conditionne la construction d'une queue que rien ne dessine, on ne touche ni a son code ni a son apparence. Tout ce qui n'est pas cet item.
