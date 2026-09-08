DIRECTIVES v708c60642a
Test alpha final GPU hôte : six cas précédents PASS + deux cas HDR actif/HUD vrai RGBA8 PASS, failures=0.
Instrument existant essai40/alpha_gpu.cpp étendu dans build-final/alpha_gpu.cpp ; sources jeu inchangées par tester.
Compilation rc0 : c++ -std=c++17 -O2 .autoport/reports/lighting-hdr/notes/essai40/build-final/alpha_gpu.cpp -lEGL -lGLESv2 -o .autoport/reports/lighting-hdr/notes/essai40/build-final/alpha_gpu
Exécution : EGL_PLATFORM=surfaceless .autoport/reports/lighting-hdr/notes/essai40/build-final/alpha_gpu .autoport/reports/lighting-hdr/notes/essai22/direct_basic.before.frag game/graphics/opengl_renderer/shaders/direct_basic.frag .autoport/reports/lighting-hdr/notes/essai22/sprite3_3d.before.frag game/graphics/opengl_renderer/shaders/sprite3_3d.frag
HDR+HUD additif : RGBA ancien/corrigé 0.878431,0.721569,0.262745,1 ; gl_error=0.
HDR+HUD DST : RGBA ancien/corrigé 0.980392,0.870588,0.462745,1 ; gl_error=0.
Pour chacun, glGetIntegerv confirme facteurs alpha GL_SRC_ALPHA ou GL_DST_ALPHA, et GL_ONE, donc état ancien.
Audit hud-call-audit.json : signature bool uses_hud explicite sans défaut, trois appels hud/true/true, trois gardes chain_active && !uses_hud.
GPU : Intel UHD Graphics CML GT2, Mesa 25.3.6 ; ne vaut pas preuve jeu ni image OFF complète.
