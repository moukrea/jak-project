# Le pilote GL ne valide plus chaque appel et ne fait plus de sondes en production

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
android_gfx.cpp:355-380 arme KHR_debug en mode SYNCHRONE a chaque lancement (le pilote valide chaque appel sur le fil appelant). Sondes non gatees : glGetIntegerv apres chacun des 69 buckets (android_opengl_renderer.cpp:1795), sonde F1e a chaque flush merc (Merc2.cpp:5038-5048 : glIsTexture, 2 glGetIntegerv, glCheckFramebufferStatus, glGetError), sonde A42 avec glReadPixels toutes les 300 images (TFragment.cpp:1062-1066, 1452-1480), __system_property_get par image dans setup_frame (:1469), glFinish a chaque fin de chargement (Loader.cpp:2173). PC : glGetIntegerv(GL_MAX_SAMPLES) par image (opengl.cpp:702), ImGui rendu meme invisible (:847-851, 977-981).

## Livrable
KHR_debug non synchrone et OFF par defaut (prop debug.opengoal.gldebug=1 pour rearmer) ; toutes les sondes ci-dessus derriere une prop eteinte ; glFinish de chargement remplace par un glFenceSync/wait ; PC : MAX_SAMPLES lu une fois, ImGui saute quand aucune fenetre n'est ouverte. Le moteur compte par image les glGetError/glGetIntegerv/glReadPixels/glFinish/glMapBufferRange emis hors armement et publie gl_unarmed_driver_queries_per_frame. Les sondes de spec (hdr.cpp hdr_overbright_px, capture refset de lighting_census) restent, gatees sur leur armed_for. refset_replay_maxdiff == 0 sur ORIGINE.

## Preuve exigee
`gl_unarmed_driver_queries_per_frame == 0` dans `reports/perf-gl-waits/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-gl-waits device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : la cadence en jeu monte, l'image est identique au pixel.

## Hors perimetre
Ne supprime aucun instrument de spec (SPEC lumiere 4.5, 7.3). Ne touche pas au defuse Merc2 (item suivant). Ne touche a aucune feature validee.
