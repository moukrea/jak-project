# Une seule passe plein ecran par image, et le depth n'est plus stocke pour rien

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
android_opengl_renderer.cpp:1520-1536 : clear complet de FB0 puis de la scene (le quad final recouvre FB0 entierement). Aucun glInvalidateFramebuffer dans le renderer : le depth/stencil 2400x1080 (10 Mo) est stocke en tuiles a chaque fin de passe puis recharge. Des que l'echelle dynamique descend sous 100 % (defaut ON), une passe UI native s'ajoute (:1585-1660) : FBO plein ecran, glBlitFramebuffer LINEAR de toute la scene, UI rasterisee, puis quad. PC : idem sans le cout tiler.

## Livrable
Sur Android et PC : depth/stencil de la scene invalides apres leur DERNIERE lecture (apres la copie de scene W0/W2 de l'eau quand elle existera : la position est un commentaire nomme dans le code), clear FB0 supprime quand le quad couvre tout, UI rendue directement dans FB0 apres le quad de scene (un blit de moins). Le moteur compte les clears, blits plein ecran et fins de passe sans invalidate et publie fb_extra_passes_per_frame. refset_replay_maxdiff == 0 sur ORIGINE et RECHARGED (le tone map P9 de lighting-hdr et la sortie hdr-display-output inchanges).

## Preuve exigee
`fb_extra_passes_per_frame == 0` dans `reports/perf-fbo-passes/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-fbo-passes device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la cadence a 100 % d'echelle ; image identique au pixel.

## Hors perimetre
Pas de changement du tone map ni de la sortie HDR (SPEC lumiere 4.1 P9/P10, 4.5). Ne touche a aucune feature validee.
