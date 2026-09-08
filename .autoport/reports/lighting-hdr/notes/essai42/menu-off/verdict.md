DIRECTIVES v708c60642a
Échec : crash du menu avant Lighting OFF ; persistanceOFF et ombresOFF non prouvées.
Aucune source, harnais ni validateur modifié ; aucun build, aucun second run.
source=device
serial=eae4df44
binary=build-android/lib/arm64-v8a/libgk.so
sha=ab2f8019a399c9c1
started_at=2026-09-08T15:21:48Z
duration_s=312
crash=1
frames=1680
Commande : proof_run.sh lighting-hdr device --timeout 300 ; exit0 (producteur), crash1.
Freshness : SHA lib locale/appareil ab2f8019a399c9c1b251714c3f118f8faae1d80e09efd8a52254ac8759e1f6e5 ; MD5 identiques 9ac9313606c09d35cad95afd3cf59c1e.
Boot normal wrapper historique : padreplay/lighting/rt.light/refset vides ; mode0 émis ; shadowdbg1 seulement.
Navigation lue en mémoire : titre27 →51 →27 →save-game-title18 →memcard-data-exists11.
Le chemin tactile présumé n’a pas atteint Options/Graphics/Recharged ; aucun bouton Lighting actionné.
17:24:27.066 PID12983 : GK-DIAG sig=11 fault=0x8000000a7f pc=0x7f004efe0c lr=0x7f020bde10.
crash.txt : sig11 si_code1 ; PC GOAL0x4efe0c, LR GOAL0x20bde10 ; instruction 0x3dc00217.
17:24:27.251 : GK-DIAG A36-TREE at-crash frame=1724 viol-total=0 first-viol-frame=0 armed=1.
Dernière page11, tap1336,867 d’acquittement ; causalité exacte du crash non établie.
Les fichiers crash.txt et logcat-crash.txt proviennent de l’appareil ; proof-engine.log complet conservé intact.
Shadow instrument existant background_common.cpp:1757 après early-return OFF: son absence ne prouve pas OFF.
Réglages avant/crash/restaurés identiques SHA78108670e26658496f33a2a0dc50c45fe16a0f2e59c774ea70499c7fefb52fd6.
Restauration : propriétés exactes (diff vide), PID14537 stable entre +8s et +20s ; aucun logcat concurrent survivant observé.
Wrapper notes utilise execv final pour que le PID logcat reste celui suivi et arrêté par le producteur.
Non prouvé : persistanceOFF, état effectif OFF, ombresOFF, cause du crash, qualité visuelle.
Owner : aucun nouveau résultat visuel à valider ; crash navigation transmis au manager.
