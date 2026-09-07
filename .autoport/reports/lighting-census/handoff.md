# Handoff — lighting-census, essai39
DIRECTIVES v6fca51fe40
## ÉTABLI
- Nouveau contrat deux bras phases 2/3, master ON constant dès bootstrap ; pas de baseline/phase 1/cinq rejeux.
- Binaire final f73702d7a009088a ; source.json et qualification-plan.json sous notes/essai39-lighting-pair/final/.
- Captures et rejeux finaux propres :8 cas par bras,16 comparaisons, maxdiff0/diffpx0, state_bad0, crash0.
- Village1-out8 heures : états8/8 égaux, autres options8/8 égales, ressources2461/2461 égales ; pair-capture-audit.json.
- Porte actuelle254/incomplete,434 manques dont432 cas ; aucun artefact d’adoption.
- Producteur atteste master/lighting/RT/HDR/others ; qualification exige aussi assets ON/OFF identiques.
- Test négatif pair-assets avec captures/replays individuellement propres passe ;26 tests Python et C++stricts OK, NPC 47.
- Sources absorbées par constructeur dans6d8fd414ed puis8d14e4721f ; aucun rollback, aucun appareil par worker.
## TENTÉ
- Premier binaire 3c50ae6265162571 avait16 comparaisons exactes ; archivé, aucun crédit au binaire final.
- Revue a trouvé le trou assets interbras et le flag wind incomplet ; contrôle/lecture corrigés sans changer la brise.
- Constructeur extérieur a bloqué un OFF avant moteur 60 s ; aucun reçu moteur créé, entrées inchangées, relance exacte.
- Android extérieur a échoué au lien boot_replay_native_rng ; ni build ni déploiement Android demandé ici.
## RESTE
- Couvrir432 cas/27 vues restantes,20 niveaux non couverts,4 intérieurs ; détails final/missing.txt ; Sunkenb reste exigé.
- Réutiliser final/on-replay.json et off-replay.json via refset_campaign.py ; 80 s, --data custom_assets --data managed_assets.
- Les captures doivent rester mono-phase avec même calendrier : LF 2282,2465,2648,2831,3014,3197,3380,3563.
- Nouveau lot/niveau exige ses recettes/bootstrap acquis ; aucune campagne visuelle ni retour masterOFF/historique.
- Reprise HDR : measure_step ne collecte que la vue legacy et ses stats sont locales au processus ; hdr-next.md nomme la limite.
- Réutiliser ses mesures sur pièces appariées pour blancs/détails ; aucune correction de courbe justifiée par hdr_tonemap_defects seul.
- Le contrôle HDR de trois configurations ne doit pas redevenir un prérequis ; pas de baseline indépendante à relancer.
- Toute source/binaire/donnée/entrée modifiée invalide les reçus ; commit seul sans changement source ne les invalide pas.
- Non prouvé : blancs/teinte/saturation/détails corrigés, couverture complète, état privé exhaustif, Android/HDR natif.
