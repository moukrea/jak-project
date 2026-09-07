# Handoff — lighting-census, essai 9
DIRECTIVES v6fca51fe40
## ÉTABLI
- Build incrémental gk réussi ; sha=c5872fcb023087e0 ; preuve unique150s durée151, crash0 frames8581.
- Census total3517130, residual0, rb_mismatch0, lc_orig_light_un604632 ; gpu_ms_buckets6.9000.
- 38/672 comparaisons ; brut max255 ; refset_replay_maxdiff254, census_replay_runs0.
- 24/24 PNG legacy essai8→9 ont exactement les mêmes SHA ; référence ORIGINE/h00 reste202/794px.
- Tous les écarts legacy des24 images sont dans x285..315/y13..72 ; zéro pixel différent ailleurs.
- 575 SHA références inchangés ; builder2541075 repris Ss ; aucun appareil touché.
- GL_INVALID_OPERATION sprite7839 ; même signature essai8(8784), aucun glReadBuffer.
- Historique conservé :564 étapes,21 niveaux,13 intérieurs,8 manques ciel sunkenb ; plan actuel672.
## TENTÉ
- Empreinte configuration complétée avec overrides caméra/flags ; build OK, fin de tour non exécutée.
- README corrigé ; mesures locales dans notes/ecarts-legacy-essai9.txt et tests-essai9.md.
- HUD habituel et engrenages du maire ne correspondent pas à la région selon projection/source.
- Piste hutlamp : village-obs.gc:765–766 clock.output=rand-vu à naissance, période900, oscillation joint3.
- GECHO-MERC montre hutlamp pendant la course ; aucune position/projection ne l’associe aux pixels.
- Réancrage actuel ne touche que part ; pas de correction spéculative ni recapture des origines.
- Sunkenb : sky=#t propre confirmé ; sky-tng.gc:901 prépare une texture globale, pas preuve de visibilité.
- Aucun cadrage nouveau justifié ; émersion du palais affiche village2, ne qualifie pas sunkenb.
## RESTE
- Identifier l’objet des pixels legacy puis corriger sa cause sans masquer, figer ni remplacer les origines.
- Résoudre incompatibilité temporelle564→672 : heures ajoutées décalent lf absolue vent/herbe après legacy.
- Préparer séparément108 étapes supplémentaires (listes essai7) avec provenance et compatibilité explicites.
- Trouver vue sunkenb≥150‰ ou faire arbitrer l’impossibilité ; conserver8 manques jusque-là.
- 22e jouable non trouvé : index22=intro ; halfpipe/test-zone sans DGO livré identifié.
- Refset lit encore current_logic_frame depuis renderer : course possible, non démontrée.
- non prouvé : cinq rejeux, couverture complète, bit-identité origines, non-régression globale.
- Prochaine preuve via lib/proof_run.sh ; pas de campagne de plusieurs heures ; generic.sh orchestrateur.
