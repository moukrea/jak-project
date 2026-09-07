# Handoff — lighting-census, essai 8
DIRECTIVES v6fca51fe40
## ÉTABLI
- Moteur checkpointé par builder cdfe2b997c ; gk incrémental OK, sha=bccef39f94505979.
- Preuve unique 180 s (durée181) : crash=0, frames=9823, draws=4139021, residual=0, rb_mismatch=0.
- Phase ORIGINE-LUMIÈRE active : lc_orig_light_un=1047023 ; gpu_ms_buckets=7.3552.
- 44/672 comparaisons publiées ; 45 brutes ; écart réel maximum255 dans chacun des trois jeux.
- refset_replay_maxdiff=254 (plan incomplet), refset_census_replay_runs=0.
- Zéro ligne glReadBuffer après correction FBO/attachement et restauration des deux états de lecture.
- Capture sur dossier existant refusée code1 ; 575 SHA inchangés : 572PNG+3captured-by.txt.
- Dernière capture complète reste .autoport/refset/refset-capture.log : 564 étapes,21 niveaux,13 intérieurs.
- Plan neuf672 : 100 PNG absents+8 anciens non qualifiés ; listes essai7 dans notes/ inchangées.
- Ciel historique : huit manques sunkenb. Start y=-249m, helix y=-448.97m, deux ancres déclarées.
## TENTÉ
- Readbuffer corrigé : erreurs GL disparues ; écarts legacy identiques à essai7 subsistent.
- Deux courses essai7 avaient déjà origine/h00=202/794px et origine-lumiere/h00=200/716px.
- Audit sunkenb : aucune nouvelle caméra justifiée ; sortie du palais affiche village2, pas sunkenb.
- Capture désormais réservée dans un dossier neuf ; lanceur candidat+REFSET_DIR, bash-n OK seulement.
- Pas de nouvelle capture/tournée complète : ≥38min/tour à60fps, >3h pour cinq ; cause des écarts inconnue.
- Builder concurrent a imposé attente/restauration x86 ; repris Ss PID2541075 après test, aucun appareil touché.
## RESTE
- Moteur liste21 jouables ; 22e du contrat non identifié, ne pas inventer de donneur.
- Identifier la cause des écarts legacy avant cinq tours ; ne pas écraser les anciennes origines.
- Préparer séparément les108 étapes supplémentaires, vérifier leur provenance avant adoption.
- Trouver un cadrage sunkenb ≥150‰ sans le retirer de la liste ; impossibilité générale non établie.
- Accélérer sans changer les instants : réduire settle change vent/herbe ; UNCAP change aussi vblank_hz.
- Refaire preuve complète par lib/proof_run.sh ; generic.sh appartient à l'orchestrateur.
- non prouvé : cinq rejeux exacts, couverture tous niveaux, bit-identité origines, non-régression globale.
- Nouveau dossier capture et lanceur runtime non testés ; notes/tests-essai8.md et diagnostic-essai8.md.
