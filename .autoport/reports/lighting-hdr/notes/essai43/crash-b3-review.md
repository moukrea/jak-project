DIRECTIVES v8aed688f73
Verdict : B3 termine par SIGSEGV dans le voisinage du traitement joint-control/effect ; aucune signature existante n'implique le correctif handles ni ne reproduit le site hd-mtx-check-all du crash42.
Lecture seule, aucun appareil/build/rejeu/instrument/source modifié ; seule cette note est écrite.
coverage-b3/proof-coverage.txt : crash=1, frames=1500, duration_s=178 ; ces compteurs ne datent pas la dernière image effective (engine.log cite ensuite lf1546).
coverage-b3/android-exit-info.txt:6–15 : timestamp=2026-09-08 18:37:56.206, pid=29178, reason=2 (SIGNALED), status=11, importance=100.
PSS0,94GB/RSS1,0GB ne prouvent pas un LMK ; aucun LMK, SIGABRT ou assert fatal du PID29178 trouvé dans les artefacts examinés.
engine.log:35112 : 18:37:54.717 GAMEPLAY: enter swamp.
engine.log:35150–35157 : échecs kmalloc sur tas de processus, dont six allocations48octets ; kscheme.cpp:282–293 retourne0 lorsque allocEnd>=heapEnd. Ce sont des échecs de capacité locale, pas une preuve de pression Android globale.
engine.log:35159–35166 : quatre joint-control.effect=0 ; skel0x210d14/0x20fb34/0x20e954/0x20d774 ; fautes PCgoal0x1e752e0, fault0x7efffffffc, interceptées par GRV-NULLFG-REPAIR et redirigées vers0x1e75320.
Le handler existant borne ce chemin à l'évaluation des joints (android/gk_android_main.cpp:6270–6281) ; les quatre messages sont des récupérations, pas quatre arrêts.
engine.log:35167 : 18:37:54.801 libsigchain « reverting to SIG_DFL handler for signal 11 ».
engine.log:35172–35178 : pile ART/libsigchain → tgkill → frame#06 pc01e752dc, située4octets avant le site de récupération précédent. Le PC précis de l'accès fatal et ses registres ne sont pas fournis par cette pile.
engine.log:35214 et35222 : annonce du décès puis nettoyage du cgroup ; « Successfully killed process cgroup » suit le décès et ne démontre pas un LMK.
logcat-crash-pid29178.txt vide ; gk_crash-stat.txt/gk-crash-read-result.txt signalent files/gk_crash.txt absent. Recherche effectuée après les relances déjà engagées par le finaliseur/tester : aucun dump fatal récupéré.
Les échecs d'allocation et les effect nuls sont des antécédents observés ; la chaîne allocation→champ→accès fatal n'est pas établie faute de registres/dernier écrivain.
Aucune frame vector-matrix*!/hd-mtx-check-all ni valeur hd-mtxarea=FFFFFFFF observée ici. Le signal commun11 ne rattache pas B3 au crash42 ; il ne valide pas non plus globalement le correctif handles.
