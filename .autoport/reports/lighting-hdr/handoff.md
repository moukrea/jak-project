DIRECTIVES va841fb32b6
## ÉTABLI
- Alpha2,0078125 observé auparavant ; test Mesa shader réel source-over : RGB négatifs avant, alpha1 et contribution corrigée après (notes/essai22/alpha_gpu.log, failures=0).
- Correctif livré :19frag clamp alpha final après discard ; DirectRenderer/DirectRenderer2/background_common reverse alpha ZERO,ZERO. Courbe/exposition intactes.
- Build/APK SHA256 lib5e525e7ca2ca6f248b354ad9b3a50632566411ba1ff8356c7c4520a642aaee32 ; MD5 installé b5fcc76756a9d12bd1cc40875bd3b0a4.
- Proof officiel lot essai22-alpha/20260908T052020-3705704 :157s, crash0, frames1200, hits672253, tonemap_sites1, quatre paires qualifiées, erreurs0.
- Huit sondes A42 float alpha0..1 ; aucun LOADSCREEN-SHOW pendant ce run. Traces/hashes notes/essai22/after-analysis.json.
- hdr_tonemap_defects=4 : groupes1/2/4=1 pour couverture incomplète ; groupe7=1 car cinq cas owner manquants ; groupes3/5/6=0.
- Garde fail-closed ajoutée helper+proof_run normal/batches : cas requis tirés du contrat, aucune ROI/séquence admissible dans schéma actuel ; aucune assertion moteur admise en remplacement.
- Tests test_hdr_batches.py :120 passés ; tests Mesa RGBA8 avant/après et tests alpha brut inchangés. Aucun test synthétique ne vaut preuve jeu.
## TENTÉ
- AVANT village1-out seul h12/18 : quatre captures, deux paires refusées noires/achromatiques, crash0, frames6420 ; lot conservé essai22-before/20260908T051058-3695478.
- LOADSCREEN-SHOW arm6 traverse captures h18 ; want.levels=village1,beach est appliqué APRÈS captures, donc pas cause démontrée du premier noir.
- APRÈS reprend ancien ordre legacy,village1-out h12/18, warp village1-hut, loadsettle240/orderhour1/settle12/warpat300, want.display=village1,display ; want.levels=village1 est inopérant need-two-levels.
- Arrivée directe extérieure non corrigée ; ancien parcours réussit. Commande complète relisible dans historique outil et réglages manifestes, log notes/essai22/after-alpha.log.
- Correction alpha isolée : aucune attribution aux cinq régions ni calibration de la courbe ; aucune nouvelle campagne21niveaux qui ferait croire ces cas résolus.
## RESTE
- Priorité cinq cas owner : identifier régions nuages/soleil/sol hutte/warp et séquence courte éco OFF/ON ; schema actuel ne porte aucune observation sémantique, measured0/missing5 honnêtes.
- Courbe maxRGB conserve ratios : (2,1,2)→environ(.998,.499,.998), ancienne cible blanche. Hypothèse distincte à isoler ; blancs OFF6719→ON0 dans essai21, mesure globale insuffisante.
- Generic2 alpha Ad-As² et autres mélanges accumulatifs peuvent encore produire hors[0,1] : ne pas appliquer ZERO,ZERO sans préserver la sémantique OFF.
- Implémenter mesures régionales avant/après compatibles, puis équilibre21niveaux/8h par lots ; anciens lots essai21 désormais diagnostic seulement (binaire changé).
- non prouvé : cinq corrections artistiques, tous acquis, tout alpha destination borné, HDR écran natif. Aucun owner-ok ni generic exécuté.
- Redmi relancé normalement, propriétés debug vides/verrou absent ; notes/essai22/device-restored.json. Binaires AVANT conservés dans notes/essai22/before-build.
