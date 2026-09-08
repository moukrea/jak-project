DIRECTIVES ve7fcbe0116

Reprise31 : nuages et soleil en premier ; aucune nouvelle campagne éco.
Chercheurs lecture seule : sky_sun_diagnostic, regions_contract, loading_diagnostic.
Implémenteurs : sun_attribution (Sprite3), sky_regions (helper/tests autorisés).
Tester : device_baseline (Redmi, build incrémental et preuve officielle).

Attribution bornée livrée libSHA cff81791ac7773bf865da7f1c5e7d891813ecffe49067063651cc35b915ab6a0.
DirectRenderer SKY_DRAW=3, PRIM.tme et hors offscreen : projection et query autour du draw inchangé.
Lectures avant/après nuages réutilisent OwnerComposition de Sprite3 dans contexte séparé.
Soleil : middot/starflash2 autour camera/4096+sun_direction brute, résidu<=0.05m.
Acteur0 étiqueté sunset-sun, quatrième ROI, deux rayons distingués par dimensions natives.
Association refusée tracée séparément, sans ROI inventée ni élargissement du rayon.
Helper raccorde captures/provenance/empreintes/ROI commune ; soleilh18 requis ; nuages partiels jamaispassed.
Tests finaux :210pass74.77s dans hdr-batches-tests.log ; tests synthétiques, pas preuvejeu.
Build :5objetsC++/liengk/repack19s/installRedmi, attribution/build-deploy.log.

Baseline essai31-sky-before/20260908T091700-3910575 (ancienbinaire04bbe8) rejetée :
24captures/61sources vérifiées ; duration235/crash0/frames6360 ; captures achromatiques2paires.
Aucun vi1VIS, l1VIS=0 ; LOADSCREEN-SHOW arm5 jusqueframes5760 ; TARGET masque4.
Portal27 vi1VIS8288 puis target-stance8694 ; essai30 vi1VIS8738 puis stance9121.
level.gc1230 chargeVIS seulement inside-boxes calculées depuis math-camera1253.
Caméra refset50m probablement horsboîtes ; ce prédicat lui-même n'a pas été directement tracé.
Donc attente prolongée non justifiée et aucune suppression de l'écranloading.
WANT-LEVELS=village1 invalide (need-two-levels), également présent27/30, pas causeunique.

Remplacement diagnostique déclaré attribution/view-correspondence.md :
village1-out caméra50m -> beach-start:7:-35:0:30 auxheures12/18.
Cap beach-143.1 mesuré lot19 engine6790 ; nouvellecaméra3m sansrecul = axe181.9 verssoleilh18.
Aucun effacement du lotnoir ; plage ne remplace pas couverturevillage1/intérieurhutte.
Run officiel attribué en cours au moment de cette note, tous réglages conservés dans son manifeste.

Fin essai31 : deux lots cff817 complets (attributed/visible) restent non jugés : décor occulte le disque solaire, et les blancs natifs des nuages ne sont pas attribuables à une région finale visible. Voir résumés JSON par lot.
Garde finale PRIM.abe ajoutée après découverte gradient8064 : lib243591 livrée,1objet recompilé, puis dernier lot crash frame431 avant captures. Preuve officielle rouge conservée ; final/tester-result.md et gk_crash.txt.
Aucun correctif photométrique livré, aucun bilan21niveaux exécuté faute de corrections ciblées établies. Sol/portail restent aux diagnostics30/27 ; pas de campagne éco.
