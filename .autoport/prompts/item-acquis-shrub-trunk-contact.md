# Proteger les mini-palmiers valides contre le retour du tronc qui se couche

## Defaut cite
- 2026-09-15 : « les mini palmiers j'ai déjà validé t'es relou et tu te fous de moi c'est pas possible ! Ensuite c'est obvious pour l'AO entre mur et toit que l'ombrage est pas pile a la jonction et qu'on voit un peu de blanc non ombré du mur pile entre le mur et le toit ! T'es relou ! »

## Cause connue
Mini-palmiers valides par l owner ; aucun acquis/shrub-trunk-contact.sh present. Les mesures historiques incompletes ne doivent pas annuler sa validation.

## Livrable
Ajouter acquis/shrub-trunk-contact.sh pour proteger les invariants locaux observables du correctif livre (separation tronc/feuillage et jonctions), avec echec sur regression pertinente. Reutiliser les instruments et tests existants ; annoncer explicitement ce que cette garde locale ne couvre pas. Aucun compteur appareil fabrique.

## Preuve exigee
`shrub_trunk_anchor_defects == 0` dans `reports/acquis-shrub-trunk-contact/proof.txt`.
Le proof se produit par `lib/proof_run.sh acquis-shrub-trunk-contact x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Pas de modification du jeu, pas de campagne ni de contact appareil ; ne pas rouvrir la validation owner.
