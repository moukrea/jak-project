# Point superviseur — 14 septembre 2026

Etat courant relu, handoffs, report.txt, FINDINGS et validateurs des deux items rendus relus. Aucune validation owner posee.

- harness-suite-temporary-files-outside-quota : validated par le harnais. validator-002 confirme suite_tmp_defects=0 ; rapport 649 tests, aucun echec/ignore, dont 12 cas acquis avec 66 chemins hors /tmp, deux refus stockage et deux rouges propages.
- harness-delivery-stale-bake-recovery : validated par le harnais apres UN renouvellement essai 7 ; validator-007 confirme delivery_stale_bake_defects=0, 22 cas dans le banc. Ne prouve pas la cuisson/APK/publication reels du dernier moteur.
- shrub-trunk-contact : in-progress, activite recente lue dans attempt-002.jsonl ; modifications rattachements tronc/feuillage commitees par le worker. Le titre « retire le verdict non mesure » ne retire aucun critere du backlog : verification du diff, uniquement deux proof_props ajoutes ; livrable et gate intacts, prompt a jour. Pas encore de handoff ni de preuve-impossible dans son dossier au pointage.
- Demons 311261 et 59525 vivants, aucun redemarrage. Arbre moteur propre au pointage ; repere APK a3149676f834 anterieur au changement mini-palmiers 862796af95, donc celui-ci non presente comme livre.

Signalements lus :
1. PAUSE : main lit le depot reel via __file__ plutot que AUTOPORT_DIR du banc ; une pause de supervision peut interrompre les tests et donner un rouge parasite. Cause exacte du rouge test_loop historique non prouvee. Correction hors item, remontee a l owner pour arbitrage.
2. Fraicheur : verdict_sources exclut orchestrator.py et ne reconnait pas sa citation racine ; une edition de close_gate peut laisser une preuve ancienne paraitre actuelle. SHA publie par le census, mais recontrole generic non prouve. Correction hors item, remontee a l owner pour arbitrage.
3. Chargement : parent 492878 lance avant modification close_gate. Son TMPDIR hors quota protege la fermeture actuelle mais les trois variables explicites du nouveau code ne sont pas prouvees chargees. A reprendre lors du prochain arret naturel ; ne pas couper le travail mini-palmiers actif. La veille conserve l entretien Codex.
4. Deja remontes : faux adb du test direct masque des erreurs de stockage ; nettoyage proof_run tente /dev/null ; restauration ISO ARM64 apres echec et attente build de vingt minutes peuvent perturber les preuves. Aucune autorisation nouvelle supposee pour ces chantiers.

AO : plan trois vues ON/OFF toujours en attente de parole de l owner ; aucun changement de statut ni de campagne.

## Point periodique 21 h 28

Dernier handoff essai 3, rapport, 13 FINDINGS et validator-003 relus. Refus exact : shrub_trunk_squash_defects absent. Deux courses USB de 130 s montrent des classes et ancres CPU, pas les deplacements ni les jonctions du contrat. L essai 4 a corrige le moteur (3ab119cff3), puis annonce explicitement une nouvelle course ne mesurant toujours pas ces grandeurs. Suspension via scope_stamp, checkpoint c8267776f7 non compte ; item blocked avec plan PENDING non autorise. Aucun verdict affaibli ni preuve ecrite ; aucun appareil contacte par le superviseur.

Plan propose : instrumentation du mouvement reel et des paires de jonction dans le moteur, reference anterieure justifiee + ON + OFF, Geyser Rock uniquement, trois courses maximum de 130 s, criteres vent/herbe et OFF conserves. Si parcours comparable ou reference indisponibles, rendre le manque avant nouvelle course. Autorisation owner requise par DIRECTIVES, section Preuve ; aucune parole owner inventee.

Signalements regroupes : pivot de plan et bornes ne prouvent pas les jonctions ; excitation du contact et pivot etaient lies (nouveau correctif en cours, non prouve) ; aucun instrument de deplacement ; lexique manuel preexistant limite la population couverte ; recherche quadratique pouvant ralentir le chargement ; commentaire de jonction trompeur retouche dans le nouveau correctif ; OFF/vent/herbe non mesures. Ces manques fonctionnels restent attaches au contrat courant, sans clone. Hors perimetre : warnings override et tail Broken pipe brouillent le build ; apply_owner_tuning.py manque toujours (deja remonte) ; client Gradle reste bloque apres BUILD SUCCESSFUL, cout observe environ 97 s et verrou retenu, nouveau signalement a arbitrer.

Sante : demons build 311261 et livraison 59525 vivants, pas de relance. Aucun proof-impossible trouve. Arbre moteur propre apres commit worker ; repere APK toujours a3149676f834, ne prouve pas la livraison des nouveaux correctifs. La reprise naturelle suivante chargera aussi le close_gate corrige. Pas d ETA de livraison deduite des seules durees de courses.
