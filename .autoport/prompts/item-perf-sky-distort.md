# Le ciel se melange sur le GPU et la distorsion ne recopie plus tout l'ecran

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
android_opengl_renderer.cpp:583 choisit SkyBlendCPU (blend CPU + glTexImage2D 32² et 64² realloues chaque image, SkyBlendCPU.cpp:193) alors que SkyBlendGPU existe cote PC. Sprite3_Distort.cpp:609-660 : glBlitFramebuffer de TOUTE la scene 2400x1080 vers une texture GL_RGB des qu'un sprite distort existe (tiler : resolve + copie + rechargement).

## Livrable
SkyBlend GPU sur Android (sortie bit-identique, refset), distorsion sur une copie de la region utile ou a demi-resolution. Le moteur publie fullscreen_copies_per_frame et skyblend_cpu_uploads_per_frame. refset_replay_maxdiff == 0.

## Preuve exigee
`fullscreen_copies_per_frame == 0` dans `reports/perf-sky-distort/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-sky-distort device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel ; la cadence quand un effet de distorsion est a l'ecran.

## Hors perimetre
Apres lighting-regimes, qui capture le dome de ciel (SPEC 4.10 P3) : la capture lit la sortie GPU. Ne touche a aucune feature validee.
