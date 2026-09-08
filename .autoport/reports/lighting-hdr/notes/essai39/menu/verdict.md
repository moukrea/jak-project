DIRECTIVES v708c60642a
Menu normal neuf : OFF/retourON effectifs, ombres retourON actives et persistanceON au redémarrage établis ; état ombresOFF non prouvé.
source=device
serial=eae4df44
binary=build-android/lib/arm64-v8a/libgk.so
sha=b58734a565c15f3b
started_at=2026-09-08T13:39:47Z
duration_s=313
crash=0
frames=3720
Commande : proof_run.sh lighting-hdr device --timeout 300 ; wrapper avant-boot essai38, pkill exporté refusant motif ; exit0.
OFF : proof-engine.log 15:42:53.140 PID23965 hdr_lighting_on=0 ; settings-off.ini recharged-lighting?=#f.
RetourON : proof-engine.log 15:43:40.283 PID23965 hdr_lighting_on=1 ; settings-on.ini recharged-lighting?=#t.
Ombres retourON :15:43:44.840 frame2760 cast_idx886502 write0 read_valid1 legacy.35 ; write est un index ping-pong, aucune anomalie déduite.
Normal : before-boot.jsonl overrides vides, mode0-confirmed.txt et props-button.json ; aucune écriture mémoire GOAL.
Navigation tactile : Graphics idx9→Recharged écran67 ; [RCH-MENU] mis0 fw10 ; Lighting idx14 dans lighting-real.json ; tap1336,852.
Persistance hors fenêtre : restart.json PID23965→25421 ; settings_equal_ON=true ; restart-engine.log15:45:45.938 hdr_lighting_on=1, mode0.
Restauration : settings SHA78108670e26658496f33a2a0dc50c45fe16a0f2e59c774ea70499c7fefb52fd6 exact ; propriétés exactes ; PID25797 stable20s.
Logcat enfant survivant au teardown identifié PID4144939 puis kill exact ; proof-engine.log contient donc aussi continuation hors fenêtre, distinguée par PID/temps.
Non prouvé : état runtime ombresOFF (absence de log insuffisante), qualité visuelle, persistanceOFF.
Aucune source ni validateur modifié ; proof.txt fourni intact par producteur.
