# Proteger automatiquement la suppression des passes plein ecran superflues

## Defaut cite
- 2026-09-14 : « validé du coup »

## Cause connue
Validation owner du 14/09 : « validé du coup ». Aucun acquis/*.sh ne protege perf-fbo-passes (recherche du 14/09). La feature reste validee ; il manque son filet de regression.

## Livrable
Ajouter acquis/perf-fbo-passes.sh en reutilisant les compteurs livres fb_extra_passes_per_frame, fb_frames_measured, fb_ui_direct_frames et fb_pass_ends_no_invalidate_max. Le controle exige une population non vide du chemin direct, distingue les regimes de repli declares et refuse une preuve absente ou perimee. Banc isole : chemin livre accepte ; passe superflue, absence d invalidate et population vide refuses. Aucun compteur moteur neuf, aucune campagne. Preuve par lib/proof_run.sh puis validators/generic.sh.

## Preuve exigee
`fbo_acquis_defects == 0` dans `reports/acquis-perf-fbo-passes/proof.txt`.
Le proof se produit par `lib/proof_run.sh acquis-perf-fbo-passes x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Protection automatique seulement ; rien a retester par l owner..

## Hors perimetre
Aucun code jeu, aucune modification de la validation owner ni de la porte de perf-fbo-passes. Pas de nouveau test visuel a demander.
