# Implémentation de la séquence éco

DIRECTIVES va841fb32b6

Implémentation terminée ; fonctionnement à l'exécution non prouvé dans ce sous-travail.

- Sources modifiées : `game/graphics/refset.cpp`, documentation API dans `refset.h`.
- Vue `village1-eco-blue` sélectionnable uniquement par son id explicite.
- Continue `village1-hut`, niveau `village1`, toutes heures ; Jak à `9.3109 19.2490 3.2525`.
- Centre acteur aid10012 fourni par le manager : `9.3109 19.2490 11.2525`, distinct du spawn.
- Caméra pitch -14, yaw -163, distance 0, hauteur 20 dm ; cadrage non mesuré ici.
- `OG_REFSET_TEMPORAL_SAMPLES` / `debug.opengoal.refset.temporal` : entier 2..16,
  réservé au mode capture de la feature lighting-hdr ; absence = 1, entrée invalide = abort.
- Chaque phase/heure/vue contient N samples consécutifs. Sample0 conserve nom et mesure HDR ;
  suivants suffixés `-t01` à `-t15`, sans réappliquer configuration, arrivée ou warp.
- Échéances suivantes espacées de `g_step_settle` depuis l'échéance précédente ;
  les écarts de frame effectivement capturée restent observables via le compteur de slip.
- PNG, relecture aller-retour, sidecar provenance, probes et effective settings sont communs.
- En opt-in, effective settings et REFSET sample publient index, taille et cadence.
- La configuration temporelle rejoint l'empreinte seulement lorsque N>1.
- L'avance des particules garde le dédoublonnage par frame logique sans gel global en opt-in.
  Le mécanisme de repin n'est pas modifié.
- `refset_temporal_samples` publie N effectif. `refset_temporal_captured` compte les écritures
  réussies avec relecture et provenance, sample0 inclus, seulement en mode temporel.
- `kNumSelectableVantages` étend trois boucles : sélection explicite, calibrage caméra,
  et comptage des paires HDR réellement mesurées (autorisation manager).
- Le stockage caméra utilise cette taille ; statistiques par vue déjà dimensionnées par plan.
- `kNumVantages` conserve la taille historique pour parcours par défaut, dénominateurs,
  portes et univers de qualification. Vue ajoutée en fin de table : indices anciens préservés.

Vérification effectuée : `git diff --check -- game/graphics/refset.cpp game/graphics/refset.h`,
code de sortie 0. Aucun build, appareil, validateur, harnais ou proof.txt modifié ici.
Non prouvé : compilation, cadence réelle, présence/visibilité éco, qualité HDR, état exact entre bras.
La compilation groupée, preuve programmatique et analyse des ROIs reviennent au manager.
