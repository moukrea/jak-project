# Le nom des jeux et de la collection Recharged

## Defaut cite
- 2026-09-11 : « JE SAIS PAS DE QUOI IL S'AGIT VRAIMENT... « Jak and Daxter: The Precursor Legacy » doit etre nomme « Jak and Daxter: Recharged » (sans mention d'OpenGOAL) »
- 2026-09-11 : « le jeu doit etre nomme « Jak and Daxter: Recharged » dans toutes les langues hein ! pas de « Jak et Daxter: Recharges » en francais par exemple, non, pour toutes les langues c'est « Jak and Daxter: Recharged », la fenetre de jeu sur PC doit etre titree « Jak and Daxter: Recharged », l'APK Android pareil, etc etc. Pas de mention de OpenGoal dans les titres ou autres. »
- 2026-09-11 : « Le nom du jeu c'est validé aussi »

## Cause connue
L'owner ne reconnait pas l'item ; il pose l'exigence en clair le 11/09 : « Jak and Daxter: The Precursor Legacy » doit s'appeler « Jak and Daxter: Recharged », sans aucune mention d'OpenGOAL.

## Livrable
`naming_wrong_sites` = 0. LE NOM EST UN NOM PROPRE : la chaine exacte « Jak and Daxter: Recharged », IDENTIQUE AU CARACTERE PRES DANS TOUTES LES LANGUES. Il ne se traduit pas — pas de « Jak et Daxter: Recharges » en francais, ni d'equivalent dans aucune autre langue. Recenser CHAQUE endroit ou le jeu se nomme : nom de l'application au lanceur Android, libelle de l'APK, TITRE DE LA FENETRE sur PC, ecran-titre, menus, ecrans de credits, description du paquet, notification. Publier, pour chaque site ET chaque langue installee, la chaine effectivement affichee ; toute chaine differente de l'exacte est un site FAUX, qu'elle soit traduite ou non. Aucune occurrence de « The Precursor Legacy » ni de « OpenGOAL » dans un titre, un libelle ou un nom affiche. Publier aussi le compte de langues inspectees : un recensement qui n'en couvre qu'une ne prouve rien.

## Preuve exigee
`naming_wrong_sites == 0` dans `reports/recharged-naming/proof.txt`.
Le proof se produit par `lib/proof_run.sh recharged-naming x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : partout ou le jeu se nomme — icone du lanceur, titre de la fenetre PC, ecran-titre, menus, credits : « Jak and Daxter: Recharged », le MEME texte dans toutes les langues..

## Hors perimetre
Ne pas renommer le paquet Android ni casser les sauvegardes existantes.
