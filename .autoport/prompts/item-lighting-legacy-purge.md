> LIS D'ABORD `prompts/item-lighting-legacy-purge-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Les reglages d'eclairage de l'ancien monde ne cohabitent plus avec la refonte

## Defaut cite
- 2026-09-11 : « les reglages anciens sont bien supprimes du menu lighting...… »

## Cause connue
Owner 10/09 : « Modele d'ambiance, Materiaux PBR, Force de l'ambiance, Distance des ombres [...] c'est des trucs anciens [...] j'ai peur que ca rentre en collision avec notre nouvelle approche ». Sa crainte est fondee : lighting-ao-indirect a trouve un verrou safe-boot herite qui epinglait l'AO a zero en silence, ligne de menu sur HBAO et moteur a zero.

## Livrable
`lighting_legacy_sites` = 0. Recenser CHAQUE reglage d'eclairage anterieur a la refonte, avec pour chacun : le chemin de code qu'il pilote, s'il s'execute encore, et l'item de la refonte qui le remplace. Puis, pour chacun, soit il est SUPPRIME du code (pas debranche), soit il est explicitement rattache au chemin unique de la refonte. Publier la table avant/apres et le compte d'execution de chaque chemin herite : tous a 0. Un binaire ou l'ancien chemin n'est PAS COMPILE vaut mieux qu'un drapeau a zero. S'AJOUTE (refus 11/09, LE PLUS GRAVE) : RETIRER LA LIGNE SANS RETIRER LE CODE EST PIRE QUE NE RIEN FAIRE. L'owner avait le PBR actif sur son Honor ; la ligne de menu a disparu, l'effet est TOUJOURS LA, et il n'a plus aucun moyen de l'eteindre. Pour CHAQUE reglage herite retire du menu, prouver que son chemin n'est plus EXECUTE : compteur d'execution publie, a 0, sur une course reelle — et s […suite dans le contrat]

## Preuve exigee
`lighting_legacy_sites == 0` dans `reports/lighting-legacy-purge/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-legacy-purge device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Recharged Lighting : plus aucune ligne de l'ancien monde, ET plus aucun de leurs effets visibles en jeu — verifie nommement le PBR, que tu avais actif..

## Hors perimetre
Ne pas livrer les features de la refonte elles-memes : chacune a son item. Ici on retire l'ancien et on dit ce qui le remplace.
