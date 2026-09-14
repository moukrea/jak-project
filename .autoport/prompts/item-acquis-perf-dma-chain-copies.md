# Proteger la reduction des parcours DMA validee par l owner

## Defaut cite
- 2026-09-15 : « pour les perfs DMA truc muche, c'est validepour les perfs DMA truc muche, c'est validé »

## Cause connue
Validation owner15/09 : controle acquis absent pour perf-dma-chain-copies. Le chemin DMA Android est distinct du zero-copie PC ; une preuve x86 seule ne couvre pas cet acquis.

## Livrable
Ajouter acquis/perf-dma-chain-copies.sh reutilisant les compteurs Android existants et une preuve fraiche/scellee du producteur autorise. Refuser plus de deux parcours par image, population vide, incoherence de comptage, donnees perimees, erreur de copie ou crash. Banc isole avec temoins faux/vides/perimes et cas valide ; publier dma_acquis_defects=0 et populations non vides via proof_run puis generic. Ne pas presenter ces compteurs comme une identite pixel ou un gain FPS. Acquisition via proof_run et gardes USB existantes uniquement.

## Preuve exigee
`dma_acquis_defects == 0` dans `reports/acquis-perf-dma-chain-copies/proof.txt`.
Le proof se produit par `lib/proof_run.sh acquis-perf-dma-chain-copies device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Protection automatique, rien a retester par l owner..

## Hors perimetre
Aucun compteur ou code moteur neuf, aucune modification du verdict owner ni des autres acquis. Pas de campagne supplementaire ni de test visuel a demander.
