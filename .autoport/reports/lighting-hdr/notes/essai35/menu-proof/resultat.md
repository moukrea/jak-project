DIRECTIVES ve7fcbe0116
Livraison GOAL seule réussie ; garde HDR partiellement mesurée par propriété, ombres et geste UI non prouvés.
Build arm64 make-group iso :force #t :1325cibles/42.957s/rc0 ; iso et obj x86 sauvegardés/restaurés.
GAME SHA c303f9cc2e52859c0f99831677ad3b20fa352aa89c892110585347ae1a3467a4 stage/APK/device ; ENGINE2080b539… identique avant/après, commentaire seulement.
APK b2b4eb7b50cc46a39501f9c7432420af342d29129aba0c75efe279ab5d93fdcb ; lib dbc38360… inchangée ; pack c4251f531cd32,74fichiers.
Arrêt initial du driver après build : assertion interne exigeait ENGINE changé ; corrigé par reprise repack sans rebuild, aucune modification validateur.
Unique proof_run.sh device --timeout48 rc0 ; durée producteur54s,frames480/crash0/hits2354 ; copie preuve officielle intacte.
Overrides lighting backlog vidé àt7.215, shadowdbg1 àt7.283 ; lighting0 àt35.444, vidé àt43.552. rt.light vide toujours, PBR#f, settings jamais édités.
HDR420/420 à13:21:33 ; aprèsOFF463/480 à13:21:35,17frames origine_lumiere. Aucun témoin PBR-SHADOW-DBG (cast_idx/read_valid/bind_receiver non prouvés).
Pause chargement ensuite :90lignes A37-HANG,Loader::update_blocking13:21:43/50,consolidation/tangentes puis textures13:21:54. Reprise HDR aprèsON non observée pendant cette fenêtre.
Nettoyage producteur sans kill motif via fonction pkill exportée qui retourne1 ; seules terminaisons PID du harnais restent actives.
Normal relancé PID26357 identique après8+12s ; settings SHA78108670e26658496f33a2a0dc50c45fe16a0f2e59c774ea70499c7fefb52fd6 identique ; debug vides/verrou absent.
Lecture ultérieure normale :A37-HANG chargement jusqu’à13:22:49 puis target-pos f780/f795 master-mode=game13:23:12/13,PID26357 encore présent. Reprise après chargement attestée, stabilité générale non prouvée.
Aucun generic,aucune campagne/refset,capture,census ou instrument ajouté ; Redmi rendu au manager pour suite éventuelle.
