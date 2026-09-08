DIRECTIVES v708c60642a
Tests ciblés alpha sur GPU hôte : six cas PASS, aucune preuve jeu ni image OFF entière.
Instrument essai22/alpha_gpu.cpp étendu uniquement dans notes/essai40/alpha_gpu.cpp.
GPU : Intel UHD Graphics (CML GT2), Mesa 25.3.6, OpenGL ES 3.2, EGL 1.5.
Compilation : c++ -std=c++17 -O2 .autoport/reports/lighting-hdr/notes/essai40/alpha_gpu.cpp -lEGL -lGLESv2 -o .autoport/reports/lighting-hdr/notes/essai40/alpha_gpu (rc 0).
Exécution : EGL_PLATFORM=surfaceless .autoport/reports/lighting-hdr/notes/essai40/alpha_gpu .autoport/reports/lighting-hdr/notes/essai22/direct_basic.before.frag game/graphics/opengl_renderer/shaders/direct_basic.frag .autoport/reports/lighting-hdr/notes/essai22/sprite3_3d.before.frag game/graphics/opengl_renderer/shaders/sprite3_3d.frag (rc 0 après adaptation attente historique décrite ci-dessous).
Cas additif/DST/reverse × RGBA8/RGBA16F : source identique, même destination remise avant chaque draw.
HDR alpha ancien→corrigé : 1.89941→1 ; 1.7998→1 ; -0.100098→0. RGB identiques sur chaque paire, gl_error=0.
OFF : RGBA identiques sur trois paires. Audit statique off-source-audit.json : branches OFF des quatre gardes restituent HEAD hors whitespace et include hdr.h.
Le premier passage complet rend rc 1 sur une attente historique essai22 « RGB_headroom_preserved » : shader actuel normalise déjà les RGB sources, sortie 1,1,1 contre ancienne attente 2.5,3,4. Trace conservée dans alpha_gpu.initial-historical-expectation.log.
Shader direct_basic.frag SHA256 58ac09aa5041225bd93f50c5b9b367213f45cc593cb9078f0355408a63fe99b7, identique HEAD. Seule cette attente de l'instrument notes est alignée sur le clamp source existant ; la suite essai22 originelle n'est pas déclarée passée.
Non prouvé : effet scène jeu, accumulation multidraw, autres valeurs sources/destinations, image OFF entière.
