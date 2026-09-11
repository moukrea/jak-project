> LIS D'ABORD `prompts/item-hdr-plan-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le plan de la sortie HDR, avant d'y toucher une ligne de plus

## Defaut cite
- 2026-09-11 : « mais attention planifies de fou avant en prenant tout en com… »

## Cause connue
LIS D'ABORD `reports/hdr-study/ETUDE.md`. Cinq refus de l'owner sur hdr-display-output, chacun corrige a l'aveugle. Owner 11/09 : « planifie de fou avant en prenant tout en compte, on va arreter de tourner en rond pendant des jours... je prefere des heures de planification pour un resultat beton que 45 iterations qui echouent ». Et il a corrige TROIS erreurs de lecture de l'etude, toutes retenues ici : (a) « la sortie HDR est l'identite du SDR par construction » est FAUX — c'est ce que fait la courbe actuelle, pas une loi ; si on calcule en HDR on peut sortir du HDR sans passer par la compression SDR. (b) Les entrees 8 bits (AO en GL_R8, ciel et palettes en RGBA8) sont NOS choix, pas des con […suite dans le contrat]

## Livrable
Un PLAN, pas une correction : `reports/hdr-plan/PLAN.md`. Aucun changement de rendu, aucune option ajoutee. Il doit contenir, chacun argumente et chiffre : (1) LE CHEMIN CIBLE, etage par etage, du calcul d'eclairage au pixel : ou la scene reste lineaire, ou elle est encodee, quelle precision a chaque etage, et OU SE BRANCHE la sortie HDR — qui ne passe PAS par la compression SDR. Dire ce qui change par rapport au chemin actuel, fichier par fichier. (2) LES ENTREES A ENRICHIR : pour chaque source aujourd'hui en 8 bits (occlusion ambiante, ciel, palettes de cycle jour/nuit, et toute autre trouvee), ce qu'elle devient, ce que ca coute en memoire et en cadence sur le Redmi, et ce que ca rapporte […suite dans le contrat]

## Preuve exigee
`hdr_plan_sections_open == 0` dans `reports/hdr-plan/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-plan device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : c'est un plan, il ne change pas le rendu ; owner_test=false.

## Hors perimetre
AUCUNE correction, aucun changement de rendu, aucune option. Ce chantier produit un document. Corriger avant d'avoir planifie est precisement ce qui a coute cinq refus.
