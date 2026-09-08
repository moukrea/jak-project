# Périmètre corrigé par le superviseur — 8 septembre 2026

La campagne a été explicitement demandée par l'owner. `proof_plan` du backlog est
le contrat de couverture : plusieurs processus, tous niveaux/heures, vues comparables.
Cette autorisation remplace ici la restriction générale aux seuls runs courts.
Le manager implémente le raccordement des lots avant de répéter une preuve incomplète.

## Autorisation de modification du harnais

Exception bornée à la restriction `.autoport/lib/` des rôles implementer :
- `.autoport/lib/proof_run.sh`
- `.autoport/lib/hdr_batches.py`
- `.autoport/tests/harness/test_hdr_batches.py`

Ces fichiers peuvent être créés/modifiés pour brancher le cumul à proof_run et le tester.
Le superviseur autorise cette implémentation, pas seulement une proposition.
Aucun accès aux autres composants harnais, aucun changement de generic/owner-ok.
L'entrée officielle reste proof_run.sh ; le helper n'écrit pas de preuve à la main.

## Données et critères

mode: multi_process_batches
owner_authorized: true
required_levels: 21
hours:
- 0
- 3
- 6
- 9
- 12
- 15
- 18
- 21
required_views:
- ciel visible pour chaque niveau exterieur
- interieurs representatifs
- hutte Sandover
exact_frame_required: false
single_process_224_pairs_required: false
replacement_views: autorisees avec correspondance explicite vue originale/remplacement
  et meme couverture, jamais effacement silencieux
source_policy: manifestes de lots proof_run, hashes sources brutes et captures, version
  schema/config/rendu compatibles ; donnees anciennes conservees pour diagnostic,
  reutilisation comme preuve seulement si compatibilite demontree
failure_policy: absent/incompatible/illisible/crash non remplace ou region non couverte
  = defaut, doublons detectes, pas de somme des verdicts per-processus ni zero force
quality_policy: mesures ImageMagick blancs/quasi-blancs/couleur/luma/aplats ; poids
  niveau/heure equilibres ; aucun seuil contraste95%, aucune identite ON/OFF

Tester hors appareil les erreurs de manifeste, doublons, fichiers modifiés/absents,
configurations ou versions incompatibles, couverture partielle et ensemble complet synthétique.
Ces tests ne valent jamais preuve jeu. Les lots doivent porter provenance et réglages effectifs.
Préserver les défauts d'image et de chaîne ; remplacer seulement le calcul de couverture
monoprocessus par celui du plan. Ne pas additionner des flags historiques pour fabriquer
le verdict global ; chaque défaut doit dériver de mesures compatibles identifiées.
Ne pas exiger d'identité ON/OFF des pixels ni des profils SDR/HDR.
