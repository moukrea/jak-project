# Les reglages d'eclairage de l'ancien monde ne cohabitent plus avec la refonte

## Defaut cite
- 2026-09-10 : « Modele d'ambiance, Materiaux PBR, Force de l'ambiance, Distance des ombres, Qualite des ombres, Relief des textures, Intensite des reflets, Profondeur de surface, Subdivision du maillage, Materiaux avances... C'est des trucs anciens qui n'ont aucun rapport avec la refonte de l'eclairage actuel non ? Pourquoi on les garde ? C'est une question mais j'ai peur que ca rentre en collision avec notre nou… »

## Cause connue
Owner 10/09 : « Modele d'ambiance, Materiaux PBR, Force de l'ambiance, Distance des ombres [...] c'est des trucs anciens [...] j'ai peur que ca rentre en collision avec notre nouvelle approche ». Sa crainte est fondee : lighting-ao-indirect a trouve un verrou safe-boot herite qui epinglait l'AO a zero en silence, ligne de menu sur HBAO et moteur a zero.

## Livrable
`lighting_legacy_sites` = 0. Recenser CHAQUE reglage d'eclairage anterieur a la refonte, avec pour chacun : le chemin de code qu'il pilote, s'il s'execute encore, et l'item de la refonte qui le remplace. Puis, pour chacun, soit il est SUPPRIME du code (pas debranche), soit il est explicitement rattache au chemin unique de la refonte. Publier la table avant/apres et le compte d'execution de chaque chemin herite : tous a 0. Un binaire ou l'ancien chemin n'est PAS COMPILE vaut mieux qu'un drapeau a zero.

## Preuve exigee
`lighting_legacy_sites == 0` dans `reports/lighting-legacy-purge/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-legacy-purge device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Recharged Lighting : plus aucune ligne qui pilote l'ancien monde, et ce qui reste agit vraiment.

## Hors perimetre
Ne pas livrer les features de la refonte elles-memes : chacune a son item. Ici on retire l'ancien et on dit ce qui le remplace.
