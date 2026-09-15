DIRECTIVES v775512c234
# Source livrée — commandes locales, toutes exit0

```sh
python3 .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-run-invariants.py --shader game/graphics/opengl_renderer/shaders/ao_blur.frag --output .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-delivered-invariants
.autoport/reports/ao-prepass-tie-alpha/notes/attempt11-desktop-compile game/graphics/opengl_renderer/shaders/ao_blur.vert .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-reference.frag game/graphics/opengl_renderer/shaders/ao_blur.frag > .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-delivered-invariants/desktop-compile.log
cmake --build build-android --target gk -j > .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-build-delivered.log 2>&1
```

SHA256 calculé par hashlib du shader source réel et de sa copie testée identiques : ca400d609b07cfc53ff464ba125ce524b70fed3e68ed03ffe5c498fb0eef6b05.

GLES3.2 Intel/Mesa25.3.6 :16comparaisons de480000pixels, zéro différence référence/candidat. Phases4x4 R8/R32F sur plans horizontal/incliné : range0. Constantes erreur R8=0,R32F<=1.19209289551e-7 ; ciel erreur0,terrain<=5.96046447754e-8. Silhouette finie : mélange préexistant ~0.502 versus step idéal, identique référence/candidat. GLSL410 exact compilé/lié dans contexte EGL OpenGL4.6 Core, gl_errors0. Build arm64 incrémental : lien lib/arm64-v8a/libgk.so, garde npc-flicker47propriétés, exit0.

Diagnostic local uniquement ; ni appareil, ni proof_run, ni verdict owner, ni validation globale. Aucun test élargi après ce cycle.
