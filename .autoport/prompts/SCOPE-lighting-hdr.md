# Périmètre corrigé par le superviseur — 8 septembre 2026

La campagne a été explicitement demandée par l'owner. `proof_plan` du backlog est
le contrat de couverture : plusieurs processus, tous niveaux/heures, vues comparables.
Cette autorisation remplace ici la restriction générale aux seuls runs courts.
Le raccordement des lots est livré. Le retour owner du 8 septembre refuse le rendu :
priorité aux cinq régressions de proof_plan, avant toute nouvelle infrastructure.
La reprise42 suit proof_plan.recovery_attempt_42 : correction causale bornée du crash
hd-mtxarea/cache compagnons/compaction autorisée, sans suppression des modèles/effets.
La navigation OFF ne conditionne plus les corrections visuelles ; sa vérification
et crash0 restent nécessaires avant livraison. Sol vraie hutte et pièce du portail
passent en priorité avec cadrages jouables et détails lisibles via proof_run.
Nuages/soleil puis sol/portail restent indépendants de l’éco. Les cinq cas restent obligatoires.

## Autorisation de modification du harnais

Exception bornée à la restriction `.autoport/lib/` des rôles implementer :
- `.autoport/lib/proof_run.sh`
- `.autoport/lib/hdr_batches.py`
- `.autoport/tests/harness/test_hdr_batches.py`

Ces fichiers peuvent être modifiés pour exploiter les séquences/régions déjà produites,
implémenter leur jugement dans owner_regressions et tester les erreurs et régressions.
Le cumul est livré : ne pas le reconstruire. Le jugement doit distinguer présence de
mesures et réussite ; les cas absents restent en échec. Les critères finaux restent inchangés.
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

## Retour owner : préserver les blancs attendus

Les cinq cas `owner_regression_cases` du backlog font partie des critères courants.
La seule absence d'excès white/nearwhite/clipped ne suffit plus au verdict qualité.
Démontrer que les régions lumineuses attendues ne sont pas supprimées et que les zones
signalées ne virent pas au violet. Éco : séquence courte, comparaison statistique temporelle,
pas synchronisation exacte des éclairs. Conserver les sources avant/après et les cas non jugés.
Diagnostic technique avant réglage ; ne pas ajouter un effet artistique nouveau pour compenser.
