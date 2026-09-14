# Préparation campagne — essai9
DIRECTIVES vab39193976

Campagne fc71d41e3c : 0/3 consommée au total ; trois bras130s maximum restent disponibles.
Aucun lancement du jeu, aucune preuve de cet essai. Les bancs sous notes sont synthétiques.
La configuration initiale du témoin est refusée par le hook : voir attempt-9-reference-configure-rejection.txt.
Ne pas réessayer une autre syntaxe pour contourner cette garde ; correction du harnais à traiter par superviseur.

## Sources et binaires

- Témoin : checkout /home/emeric/code/jak-shrub-reference-602cd, commit f54ea18c485ca156816824522d2e67ece9bc3992,
  parent602cd72eb7. Instrumentation seule portée ; Loader, dépaquetage, lois et LUT historiques conservés.
- Patch complet incluant nouveaux fichiers : attempt-9-reference-instrumentation.patch.
  Empreintes : attempt-9-reference-overlay-manifest.json et attempt-9-reference-original-manifest.json.
- Les deux scripts prepare-reference puis port-overlay permettent de reconstruire cet overlay depuis602cd72eb7.
  Ils réécrivent exclusivement les fichiers listés du checkout dédié ; ne pas les relancer sur un autre chantier.
- Le témoin n'a pas été compilé : aucun cache Android, refus avant exécution de CMake.
- Le correctif courant est compilé par cmake --build build-android --target gk -j8 ; logs build/final/repack/deploy.
- Pour lancer la référence via proof_run, le checkout devra porter l'item courant et le producteur de preuve
  compatible. Ne pas mesurer le .so témoin sous une identité de sources du correctif : proof_run résout ROOT
  par git et impose build-android/lib/arm64-v8a/libgk.so. Préparer cette livraison après résolution du refus.

## Protocole machine préparé

L'ordre proposé est référence, OFF, ON, pour que la dernière course ON puisse lire et comparer elle-même
les archives OFF/référence et publier le total dans proof.txt. Ce sont les trois bras déjà autorisés.
La première course doit rencontrer la population/contact ; si elle échoue, conserver son résultat et le compter.
Clip inchangé : attempt-6-contact.inputs (120ticks neutres,130marche,puis neutres), SHA aafa00f05f2e73011710e0733839f3392b05ff0d9ebd08ba63ebc483f768b31a.
Fenêtre GPU :120,180,…600, neuf frames logiques attendues, une image rendue par frame logique.
La fermeture de600 se produit après600 ; fenêtre absente/incomplète => aucun total.
SHRUB/TIE : positions pré/post, index/EBO, attributs GPU, uniformes et lignes de LUT sémantiques.
Herbe : toutes les coordonnées des sommets procéduraux d'une instance sur256, buffers GPU compacts privés.
Le programme couleur d'herbe conserve sa source sans macro ; programme mesure séparé sous rasterizer discard.
NaN/Inf, données manquantes, erreurs GL, mauvais schéma, écrasement d'archive : rejet, aucune équivalence supposée.

## Réglages à poser dans proof_props de l'item avant CHAQUE bras

Conserver les7 réglages déjà épinglés (warp training-warp, clip, fixed_tick, foliage.force, trace).
Chemins ci-dessous sont des exemples pour une campagne neuve ; ne jamais écraser une archive existante.
- Référence : debug.opengoal.shrub.inputs_mode=record,
  debug.opengoal.shrub.inputs_path=/data/data/org.opengoal.gk.jak1/files/shrub9-inputs.bin,
  debug.opengoal.shrub.archive=/data/data/org.opengoal.gk.jak1/files/shrub9-reference.
- OFF : mode=replay, même inputs_path, archive=.../shrub9-off, reference=.../shrub9-reference ; proof_run --off.
- ON : mode=replay, même inputs_path, archive=.../shrub9-on, reference=.../shrub9-reference,
  debug.opengoal.shrub.off_reference=/data/data/org.opengoal.gk.jak1/files/shrub9-off.
Les préfixes courts /data/data/org.opengoal.gk.jak1/files/ sont nécessaires à l'accès de l'app et à la limite des props.
Ne pas poser ces props à la main par adb : teardown les efface. Aucun réglage de bras n'a été posé cet essai.
Avant chaque lancement, consigner la consommation dans proof_plan ; chaque bras est lancé exclusivement par proof_run.
Conserver immédiatement chaque preuve produite, archives/entrées et sha des binaires ; aucun champ proof.txt écrit à la main.

## Limites restantes

Le rejeu des sources keyed wind_time tolère les répétitions ; les horloges/contact ordinaires conservent
leurs comptes pré-ancre par canal. Des états pré-ancre différents sont rejetés, jamais réinitialisés pour réussir.
La référence conserve aussi sa prépasse/vent natifs antérieurs : le changement AO TIE entre602cd et courant
peut produire une vraie différence OFF ; l'instrument ne la masque pas.
Neutralité GLES locale mesurée (bancs) ; appareil, contact réel du clip, jonctions, mobilité, acquis et OFF non prouvés.
Aucune comparaison source/identité de texte ne remplace une comparaison des sorties GPU.
