# Reprise après restart/start — essai 17
DIRECTIVES v6fca51fe40

## État avant cet essai
Handoff16 repris sans refaire la recherche historique. Aucun changement renderer/GOAL.
Le build Android concurrent a fini ; son démon2541075 a été vérifié idle puis suspendu
par une session shell longue (trap EXIT / timeout1800s), pour protéger les entrées x86.
Les cinq SHA binaire/CGO/input de l'essai16 étaient encore identiques après cette passe.

## Frontière actors-sweep
Nouvelle option OG_BOOT_REPLAY_BOUNDARY=actors-sweep ; formats avant-play/first-dispatch conservés.
Après chaque dispatch : PID target, spawn, sweep et état actif du niveau sont comparés,
pas restaurés. Il faut avoir observé spawn désactivé puis réactivé, un dispatch ET une
frame logique supplémentaires et le vrai signal actors-sweep-complete. Plafond600dispatches
avec échec explicite, jamais un succès sur délai. Ce drapeau constate un parcours,
pas toutes les naissances réussies (pression mémoire possible dans entity.gc1186).
À la frontière : RNG/display/next-pid, permanences game-info, tables entity-links des
niveaux, aid/status/task/position initiale, présence/pid/type/status/états des processus.
Symboles/types/états sont nommés ; aucune adresse ni union user-object n'est transférée.
Ce sont des checkpoints passifs, pas une restauration complète de chaque acteur.
Inputs supplémentaires : slot+résultat de tranche de login ; paquet manette20octets
et état de connexion avant transformation par la démo. Les SHA de la démo restent nécessaires.

## Mesures et correction de frontière
Build initial rc0, garde npc-flicker47 ; revue corrige #f, borne trois niveaux et progression
frame ; build final rc0. Test autonome bootstrap rc0, fingerprint b6ede934ecf3e6a1.
Premier run : capture20s/proof60s,577records6bf862c8fdcf1b24 identiques au dispatch8/PID12.
Mais décodage : title actif, village1 loading, target-title ; seulement2entity-links sans
processus, et target présent. Ce succès ne prouvait PAS les acteurs de la scène de référence.
Proof archivée dans essai17-title : crash0 frames3394 maxdiff202 diffpx794, GPU8,1273ms.

Correction : OG_BOOT_REPLAY_CONTINUE=village1-hut est enregistré et transmis comme argument
initialize! AVANT restart/start, jamais comme reset tardif. Build c456d782bdc4fbb5 rc0.
Capture village20s : dispatch10/PID12,4376records fb4b23a8c8e63032,178entity-links,
51processus présents,294permanences aid ; village1 et beach identifiés.
Rejeu officiel : échec à index2255 goal-slice-slot (capture slot0 après slot1),6s crash1 frames97.
Le flux capture1333décisions de tranche mais pas les disponibilités RPC ; la boucle slot1
attend le statut loading/login à level.gc1175, dépendant de la fin asynchrone des données.
Capture et rejeu ne franchissent donc pas la même transition vers login malgré tranche rejouée.
Cette preuve rouge reste archivée avant correction RPC ; aucune sentinelle n'est masquée.

## Qualification indépendante : obstacle vérifié
Pristine /home/emeric/code/jak-original-v033 HEAD c4bc4d3ff4691902ff023319cb33df71c0040501,
binaire615f120e4e0de8f625d0111a173417ba89f45e9ded6ca544ce052ee53f976fe5 inchangé.
Audit agents :141exports fork absents pristine,117référencés statiquement dans GOAL PC
(pas117appels exécutés). Les sept pc-refset ne suffisent pas à faire tourner les CGO livrés.
Pristine ne publie pas actors-sweep-complete ; observer le vrai retour actors-update
(méthode15 de level-group) demanderait un crochet d'appel original, sans stub ni second appel.
L'override continue existe déjà dans initialize! pristine ; le protocole pad/frame ne l'est pas.
Le port bootstrap isolé ne serait donc toujours pas une qualification des données livrées.
refset.cpp1680 publie missing-state-and-baseline pour v2 ;1919 réserve census_ok à v1 ;
1980 refuse v2 et moins de cinq rejeux. Aucun consommateur d'attestation indépendante n'existe.
Il faut un vrai adaptateur ABI et un producteur/consommateur qualification avant adoption ;
l'inventaire actuel ne certifie toujours pas les octets réellement ouverts/textures/obj loose.
Aucune référence candidate capturée ni adoptée, aucun PNG historique remplacé.

## Correction RPC et état final
ksound.cpp : wrapper GOAL rpc-busy? uniquement sous actors-sweep actif. Canal checkpointé,
booléen de disponibilité rejoué. Un prêt enregistré attend un vrai prêt avant de rendre
le tampon accessible : poll natif1ms, plafond5s avec abort. Les polls de cette attente
ne consomment pas de records ; aucun changement RpcBusy natif ni rendu hors protocole.
Build final rc0 :1e505342c58a9875 ; garde npc-flicker47. Pas de reconfiguration CMake manuelle.
Run final run-rpc-essai17.sh : capture20s puis unique preuve de cet état60s.
5880records capture/replay, empreinte79fb964dc17507ec, dispatch10/PID12.
1115disponibilités RPC,970décisions de tranche,44paquets pad,39EE-timer rejoués.
178entity-links et51processus présents,294aid (116tâches +178liens) contrôlés.
La frontière voit village1 active et beach loading : les chargements/acteurs APRÈS celle-ci
ne sont pas certifiés. Ni snapshot complet d'acteur, ni déterminisme de toutes les images.
Proof finale produite par proof_run : crash0 frames3294, compared1 maxdiff195 diffpx57581,
replay_flaky254 census_replay_runs0. Cet écart à l'historique ne mesure pas une amélioration
HDR : l'état initial a changé. Draws1685650 stock/classifiés0, résiduel0, rb_mismatch0,
GPU9,3062ms ; data56f0364a8789c816, config6ab6da1dcc8defb1.
575SHA historiques avant/après OK ; cinq SHA binaire/CGO/input avant/après OK.
Registre append-only : lignes titre et village distinctes, aucune ancienne ligne effacée.
Pas de campagne complète/candidat/cinq rejeux sur un état non qualifié ; aucun HDR corrigé.
Generic inchangé, réservé à l'orchestrateur. Aucun appareil ni owner-ok.
