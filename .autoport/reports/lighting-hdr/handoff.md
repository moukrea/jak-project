DIRECTIVES v708c60642a
## ÉTABLI
- Aucun correctif comportemental livré. Traces bornées kscheme.cpp/klink.cpp ajoutées, gate OG_HDR_LOAD_DIAG=1 ou debug.opengoal.hdr.load_diag=1 ; défaut off. Instr et sources conservées notes/essai37/diagnostic/.
- Crash36 intern nommé lurkerworm-strike : portail36/engine.log18227–28 tampon X0=X19=0x7f001a7be0. Faute toujours STUR àlib+0x721584, slot nul ; cause non établie.
- Crash36 oiseaux lit cellule0x1490ec ; pool nk demeure0x1dcb44. Boot gkernel conservé initialise default via ADRP/ADD/STR X16 : piste NOP X14 rejetée, ne pas la repatcher.
- Run officiel37 loading-diag/20260908T124303-4094917 : duration281s,crash0,2700frames,320événements symboles,0anomalie scratch. Les deux signatures ne sont pas reproduites ; absence de concurrence non démontrée.
- engine.log1193–94 : après gkernel, default(slot1490e4,hashc3bdb278)=nk(slot146984,hashfa196d8c)=1dcb44. Seagull18858–59 : ADRP90fed610+ADD91039210→1490e4 exact ; post18874–75 mêmes valeurs/identités.
- lurkerworm-strike18768–84 : slot14c874,hash1fd53968,identité correcte ; lien finit18789. Écart default37/36 de8octets ne prouve ni doublon ni corruption entre exécutions.
- Portail37 repin14:46:20.446 lf1862→échantillon14:47:15.488 lf2521 :55,042s murales,âge659pas,animation once-per-logic-frame. Une captureON/4,aucune paire ; déficit coverage conservé.
- Portail acteur1395 harddot,ROI[147,42,173,79] ; after_world_sprites event11 RGBmax3.2598/2.4668/17.1719,white334→tonemap314,nearwhite352→352. OFF absent : aucun verdict qualité.
- Build incrémental gk réussi + repack isolé52s, sans GOAL. Libdiagbd3b227da476…/APK3d796fd7c256… conservés, jamais publiés. APK/lib/jni normaux restaurés, packs inchangés.
- Dernier proof officiel = menu normal219s : sha dbc383605d0125ed,crash0,1020frames/HDRdraws/site1,hits59136,defects5,ownermeasured0/missing5. Props lighting/rt.light/refset vides.
- OmbresON normales attestées menu/proof-engine.log24676 : frame900 cast_idx2502208 read_valid1 ;1020 idem26466. Geste OFF/retourON et ombresOFF pas observés.
- Redmi final PID15556 stable12s,settings exact78108670e26658496f33a2a0dc50c45fe16a0f2e59c774ea70499c7fefb52fd6,debug vides,lock absent. APKnormal9767b7…/libdbc383… (identités36 conservées).
- Tests HDR249pass76,16s ; Kernel.HashTable ancien binaire build/goalc-test1pass43ms. Pas tests de correction ni preuve esthétique.
## TENTÉ
- Instrumentation scratch observe candidat local/TLS et dernier écrivain atomique best effort ; le global original reste consommé. Aucun épisode anomalie sur l’unique run : aucune correction préventive présentée comme causale.
- Portail timeout240 avec loadsettle660+settle660/temporal2 : première capture à2521, fenêtre insuffisante pour OFF. Aucun retry,hausse settle,skip oiseaux/portail ni ablation éco.
- Menu normal210 : START transmis(log15317/15326), mais chargement occupe fenêtre et OFF jamais attesté. Capture navigation refusée par garde preuve visuelle ; lecture mémoire ciblée menu sans écriture retrouve0ligne, recherche progress non concluante. Ne pas présenter ce run comme test du bouton.
## RESTE
- Obtenir événement causal des crashes avant correction : candidat/consommé divergents, vraie identité ancienne cellule1490ec, mauvaise relocation ou transition anormale. Sources36/37 préservées ; ne pas rejouer identiquement ni ajouter un diagnostic général.
- Finir bouton Lighting normal : OFF/retourON/persistance, ombresOFF et retour ; instrumentation normaleON seule maintenant attestée.
- Comparaison portailON/OFF après chaque purge≥10s animées : captureON37 existe ; prévoir durée du protocole réel sans perdre les absences du lot37 ni recycler ancien binaire comme preuve sans compatibilité.
- Nuages/soleil puis sol/portail restent indépendants éco. Toutes les notes36 sur soleil orange, plateau1.05,sol glTF paletteTOD,éco29/30 non résolue restent valides ; voir previous-handoff.md.
- non prouvé : cinq corrections,21niveaux×8h/ciels/intérieurs/vraie hutte/acquis. Aucun réglage courbe,artifice bloom ni seuil modifié ; HDR natif ensuite. Aucun generic/owner-ok exécuté/écrit.
