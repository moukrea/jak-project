# Fiabiliser les comparaisons ON/OFF pour corriger les blancs HDR

## Defaut cite
- 2026-09-07 : « Heuuu le framework devrait utiliser astra pas spark, spark est bête ! »
- 2026-09-07 : « avec une distribution intelligente du niveau d'effort comme on fait pour Claude code avec Fable 5.1 et Opus 5 par example »
- 2026-09-07 : « Attends attends... Le mouvement natif des buissons ? Qu'es-ce que ça vient foutre là ? On parlait du rendu (blancs brûlés, teinte/saturation) avec notre refonte de lighting en HDR vs OFF (donc éclairage par défaut) les textures, les modèles HD, l'herbe, la brise, etc. n'ont absolument rien à voir ! »

## Cause connue
Correction owner : comparaison HDR egaree vers master OFF historique. Isoler la refonte lumiere (phases2/3), master ON et tous les autres effets identiques. Baseline historique/master OFF ne sont plus des prerequis.

## Livrable
Adapter producteur, qualification et recettes aux DEUX bras du meme build : refonte lighting ON/HDR tonemappe SDR et lighting OFF/eclairage par defaut. Master Recharged ON constant ; textures, modeles HD, herbe, brise et autres options identiques, meme scene/camera/heure/etat. Attester les options effectives : seules les composantes de la refonte eclairage varient. Reutiliser outils acquis. Retirer phase1/master OFF et egalite avec baseline historique des portes de cette priorite ; archiver ces preuves sans les valider. Reproductibilite de chaque bras, aucune egalite imposee ENTRE ON/OFF. Premiere paire exploitable puis poursuivre HDR/blancs, teinte/saturation et details des hautes lumieres. Couvrir21niveaux,8heures,interieurs/exterieurs et vues de ciel ; cas manquants explicites. Preuve via proof_run.sh ; aucun verdict fabrique.

## Preuve exigee
`refset_replay_maxdiff == 0` dans `reports/lighting-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-census x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Aucune correction de textures, modeles HD, herbe, brise ou cadence dans cette priorite. Aucun nouveau travail sur master OFF/historique. Ne pas annuler aveuglement les corrections deja commitees. Pas de masque ni validation owner. HDR ecran natif ulterieur.
