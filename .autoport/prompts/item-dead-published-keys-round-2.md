> LIS D'ABORD `prompts/item-dead-published-keys-round-2-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Cinq cles publiees de plus qui ne mesurent rien

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
CINQ SIGNALEMENTS DU 12/09 (reports/dead-cover-and-legends/FINDINGS.txt), tous du meme genre que les 24 que l'item vient de retirer, mais hors de son perimetre.
1. `refset.cpp:2352` : `grass_overhang` est PUBLIEE et le binaire livre ne peut pas la faire bouger — initialisee `false` a :2338, reaffectee uniquement sous un `#ifdef` absent du build.
2. `refset.cpp:3859,3866,3871` : trois cles publiees a valeur de CHAINE LITTERALE dans le bras `lighting-hdr` (`profile=sdr`, `method=...`, `particle_st...`). Une constante publiee se lit comme une mesure.
3. Les captures de qualification faites AVANT ce commit portent `subdivision` et `subdivision_rounds` dans leurs options effectives : comparer une […suite dans le contrat]

## Livrable
`dead_keys_r2_defects` = 0, somme de termes publies SEPAREMENT, un par signalement.
1. Chaque cle retiree est d'abord RETROUVEE par le meme detecteur sur le commit d'avant : publier le compte trouve avant et le compte trouve apres. Un zero apres sans un non-nul avant ne prouve rien.
2. Une valeur litterale cesse d'etre publiee comme une mesure, ou elle est renommee pour dire qu'elle est une constante. Publier laquelle des deux voies a ete prise, cle par cle.
3. Le miroir CPU du POM reflete EXACTEMENT les termes du shader : publier le compte de termes de chaque cote, l'egalite est le verdict.
4. Le motif de la garde de `kPbrParams` est reexamine et publie : ce qui la justifie encore, et ce qu […suite dans le contrat]

## Preuve exigee
`dead_keys_r2_defects == 0` dans `reports/dead-published-keys-round-2/proof.txt`.
Le proof se produit par `lib/proof_run.sh dead-published-keys-round-2 x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. Ce sont des mesures publiees dans les preuves..

## Hors perimetre
Ne change aucun rendu. Priorite 33 volontaire : les chantiers d'eclairage passent AVANT.
