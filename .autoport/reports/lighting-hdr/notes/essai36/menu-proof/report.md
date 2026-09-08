Build GOAL seul et livraison réussis ; preuve courte sans crash, retour ON final et ombres non prouvés.
DIRECTIVES ve7fcbe0116
Commandes : python3 notes/essai36/menu-build/build-deploy.py puis python3 notes/essai36/menu-proof/run.py, rc0/0.
Build unique make-group iso force arm64 ; Gradle assembleJak1Debug exclusions configureNativeLibs/buildNativeLibs/bundleJak1CustomPack.
Temps build/livraison108.161s, Gradle28s ; iso/obj x86 restaurés, aucun NDK/Cmake.
Identités complètes : ../menu-build/delivery-identity.json ; libdbc383605d0125ed inchangée sur local/APK/device.
GAME/ENGINE nouveaux vérifiés stage/APK/device, marqueur ogflags:435df2141670:android-arm64 présent.
Entrées changées : GAME pckernel+hud-classes-pc ; ENGINE pckernel seul (cgo-entry-changes.json).
crash=0
frames=480
duration_s=54
hdr_cfg_frames_recharged=451
hdr_cfg_frames_origine_lumiere=29
hdr_chain_frames=451
tonemap_draws=451
hdr_owner_regressions_measured=0
rt.light vide à toutes étapes ; lighting retiré à7.198s, OFF35.465s, retiré43.567s (events.json).
Trace override OFF preuve-engine.log9415 ; derniers compteurs lighting0 à frame480.
Chargement après frame480 ; aucun nouveau compteur après retrait override, retour ON non prouvé.
Loader normal : global-weld village1 stitched1131612 ; sidecar PRECOMPUTED APPLIED verts1867939 md527b41d1cc5da5e6725649663d2bac541, lignes10628/10788-90.
Aucune trace de rendu ombre trouvée ; activation ombres non prouvée malgré shadowdbg1.
Acquis observables : hd_fr3_enhanced2, hd_retarget_fills2 ; tick_locked_pct100, tick_lock_err_pct_x10000.
hd_gpu_cmd_judged0, hd_game_seconds0, npc_level_evictions0 : mouvement/animation/éviction non prouvés.
Restauration PID7324 stable12s, propriétés debug vides ; settings inchangés 78108670e26658496f33a2a0dc50c45fe16a0f2e59c774ea70499c7fefb52fd6.
Non prouvé : cinqcas owner, 21×8, retour ON, ombres ; aucun validateur ni commit.
