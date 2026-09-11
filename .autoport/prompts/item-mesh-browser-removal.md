# Le navigateur de mesh quitte le jeu, entrees de menu et raccourcis compris

## Defaut cite
- 2026-09-11 : « TERMINÉ, MAIS IL FAUT SUPPRIMER CETTE FEATURE ELLE SERT A RIEN, Y COMPRIS SES ENTRÉES MENU ET BOUTON SUR OVERLAY TACTILE, ET RACCOURCI MANETTE IL ME SEMBLE »

## Cause connue
Owner 11/09, en validant l'item qui l'a livre : « TERMINÉ, MAIS IL FAUT SUPPRIMER CETTE FEATURE ELLE SERT A RIEN, Y COMPRIS SES ENTRÉES MENU ET BOUTON SUR OVERLAY TACTILE, ET RACCOURCI MANETTE IL ME SEMBLE ».

## Livrable
`mesh_browser_sites` = 0 : la fonction est SUPPRIMEE du code, pas debranchee. Recenser et retirer TOUS ses points d'entree — rangee(s) de menu, bouton de l'overlay tactile, raccourci manette, commande console, ressources et shaders qui ne servent qu'a elle. Publier le recensement avant/apres et prouver que rien du navigateur n'est plus compile dans le binaire livre. Aucune renumerotation de menu qui deplacerait d'autres lignes.

## Preuve exigee
`mesh_browser_sites == 0` dans `reports/mesh-browser-removal/proof.txt`.
Le proof se produit par `lib/proof_run.sh mesh-browser-removal device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options et overlay tactile : plus aucune trace du navigateur de mesh, et aucune autre ligne de menu deplacee au passage.

## Hors perimetre
Ne pas toucher aux autres outils de debug. On retire celui-la, entierement.
