# Audit ciblé : intégration particules 3D
DIRECTIVES vaff5c1afea
Recherche native Codex, rôle researcher/high, sans édition ni build.
Objet : build-android/android/CMakeFiles/android_kernel.dir/__/game/mips2c/jak1_functions/sparticle.cpp.o.
Symbole sp_process_block_3d::execute : 0xe9c = 3740 octets.
Bloc sparticle.cpp:247–278 : offsets [0x6c4,0x8fc), 568 octets, 142 instructions statiques.
Déjà vectorisé/inliné : 0x744 fmul v2.2s ; 0x760 fadd v0.2s ; 0x834 fmul v3.4s ; 0x840 fadd v18.4s.
Clamp : 0x868/0x880 fcmlt puis bic. Aucun appel aux helpers VU dans le bloc.
Piste : sept str q0 entre 0x6e8 et 0x728, relectures/assemblages ld1/zip1 ; stockage contexte0x888 relu0x8e8/0x8f0.
Des vecteurs locaux pourraient réduire ces transferts : hypothèse, aucune réduction compilée ni rentabilité établie.
Il faudrait préserver lanes masquées, registres intermédiaires, fade bitwise, ordre, clamp et alignement.
Trace HISTORIQUE proof-engine.log:686932 : 3d=0.88ms/180c/7680it 2d=10.13ms/1620c/96000it.
Totaux par60 images : android_opengl_renderer.cpp:1420–1437 ; les slots invalides comptent aussi (spart_prof.h:15–16).
Les slots invalides sautent l’intégration à0x264. La trace prouve des appels3D, pas la population du bloc.
Le chronométrage inclut callbacks/quaternion/slots/instrumentation : coût propre du bloc non isolé.
Les compteurs historiques de parité particules mesurent le launcher, pas cette intégration.
Conclusion : trois cibles optimisables non établies ; aucun ajout SIMD ni nouvelle course autorisable.
