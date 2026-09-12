> LIS D'ABORD `prompts/item-recharged-grass-wear-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'usure et la hauteur variable de l'herbe

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md (contrat) PUIS prompts/phase-Grecharged-grass-wear.md — 11 274 octets, la SPEC VERBATIM de l'owner du 2026-07-12 et les quatorze criteres qu'il a poses. SPEC section 12.
POURQUOI CET ITEM ETAIT VIDE. Il portait un spike de conception de 402 lignes — architecture en quatre couches, quatorze criteres d'acceptation, budget chiffre, decoupage en treize etapes — et ZERO ligne de code. Une regeneration de son prompt le 11/09 a efface tout ce contenu : l'item n […suite dans le contrat]

## Livrable
`grass_wear_defects` = 0, somme de termes publies SEPAREMENT. Les quatorze criteres de l'owner sont dans le spike et font foi ; les quatre termes ci-dessous sont la facon dont la machine les juge.
1. LE CHAMP EXISTE ET IL EST SPATIAL : publier la correlation entre la hauteur d'un brin et celle de ses voisins, aujourd'hui nulle par construction, au-dessus d'un plancher declare. Un bruit blanc a la correlation d'un bruit blanc, et c'est exactement ce que l'owner refuse.
2. LES REGLES SE VERIFIENT […suite dans le contrat]

## Preuve exigee
`grass_wear_defects == 0` dans `reports/recharged-grass-wear/proof.txt`.
Le proof se produit par `lib/proof_run.sh recharged-grass-wear device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur le niveau d'entrainement et a Sandover : l'herbe doit etre plus courte la ou on passe et plus haute dans les recoins, sans qu'on voie ni bande ni couloir dessine. Les collectibles restent visibles..

## Hors perimetre
Ne modifie ni la collision, ni le gameplay, ni la position des collectibles. Ne remplace aucun mesh ni aucune texture de chemin : les vraies surfaces de chemin restent des zones d'exclusion explicites, traitees par grass-path-transitions. Tout ce qui n'est pas cet item.
