# Un checkpoint du constructeur n'emporte plus le travail d'un chantier

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signalement du worker lighting-legacy-purge (11/09) : la purge d'eclairage commandee par l'owner a ete emportee EN ENTIER par deux commits « [autoport/builder] checkpoint automatique » (2605a2f595, a2dcd34b3f). Aucun ne porte le prefixe du chantier : `git log --grep` ne retrouve pas le travail, et un revert ou une bisection d'un « checkpoint constructeur » defait en silence une suppression demandee par l'owner. Le superviseur a fait la MEME faute la meme nuit (d408802e22) en commitant l'index d'un worker.

## Livrable
`checkpoint_stolen_files` = 0 : un commit de checkpoint ne contient QUE ce que le constructeur a produit lui-meme. Il nomme ses chemins, il ne valide jamais l'index. Publier, sur les 50 derniers commits, le nombre de fichiers de chantier emportes par un checkpoint : il vaut 0. Meme regle pour tout script du harnais qui commite.

## Preuve exigee
`checkpoint_stolen_files == 0` dans `reports/builder-checkpoint-steals-work/proof.txt`.
Le proof se produit par `lib/proof_run.sh builder-checkpoint-steals-work x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : tracabilite ; owner_test=false.

## Hors perimetre
Ne pas reecrire l'historique. On empeche la recidive, on ne repare pas le passe.
