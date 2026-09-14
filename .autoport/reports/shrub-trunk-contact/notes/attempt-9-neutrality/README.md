# Banc synthétique EGL/GLES — neutralité instrument shader
DIRECTIVES vab39193976

Sources témoins : git 602cd72eb7. Aucun moteur bâti, aucun appareil utilisé, aucune source moteur/jeu modifiée par ce banc.
Contexte : EGL_PLATFORM_SURFACELESS_MESA, pbuffer 1x1, Intel UHD CML GT2, OpenGL ES 3.2 Mesa 25.3.6.
Sans pbuffer le premier essai a produit une capture vide ; le banc final exige une vraie capture.

Commandes (depuis dépôt) :
- `bash .autoport/reports/shrub-trunk-contact/notes/attempt-9-neutrality/run.sh`
- `python3 .autoport/reports/shrub-trunk-contact/notes/attempt-9-neutrality/decode.py`
- `bash .autoport/reports/shrub-trunk-contact/notes/attempt-9-neutrality/run-grass.sh`

`prepare.py` lit le git historique et injecte uniquement les déclarations/affectations probe aux quatre vertex shaders, avec #ifdef. Toutes les lois historiques incluses sont conservées intégralement. Conversion GLSL ES highp et substitutions Jak1 (SCISSOR_ADJUST=512/448, HEIGHT_SCALE=1) communes aux deux bras. OG_PBR non défini. Transform feedback de gl_Position et pré/post/index instrumenté, points synthétiques documentés dans bench.cpp. Contact Jak, ledge et trample actif ; vent natif shrub et brise actifs dans bras wind1. Aucun calcul CPU ne remplace la déformation GLSL.

`run.log` rc=0 : shrub/tfrag3/etie/etie_base, 16 paires (contact0/1 × wind0/1), 12 sommets chacune, 192 octets gl_Position égaux dans chaque paire. Pré/post différent sur 12/12 sommets contact actif, identique sur 12/12 contact inactif. `capture.csv` décode les sorties de ces captures binaires. Vent modifie pré de 12/12 sommets dans les quatre shaders.

Grass : témoin vertex original git 602cd72eb7 contre shader courant sous OG_GRASS_CONTACT_PROBE. Includes contact historiques communs. TF interleaved capture gl_Position, v_color, v_alpha, v_uv, v_is_card, v_seed (48 octets/sommet), puis pré/post vec4 et ids uvec2 pour bras instrumenté. 10 sommets near complets ou 10 premiers sommets card, une instance synthétique. Scénarios : 0 near normal, 1 tail card cull, 2 tagged collapse, 3 debug cull, 4 LOD cull, 5 object cull, 6 rim zéro, 7 card émis, 8 hash card cull ; chacun contact0/1.

État initial `grass-full.log` rc=1 : 16/18 paires égales toutes sorties, deux paires card émis diffèrent sur v_alpha (0.31290191411972046 historique, 0.3129018545150757 instrumenté ; 2 ULP). gl_Position égaux même dans ces deux paires. Les six familles early-cull sont égales. Contact actif change pré/post de 8/10 near et 5/10 card. Différence signalée au manager/implementer.

Les .bin sont de vraies lectures GPU transform feedback. Les SHA256 des shaders compilés figurent dans sources.log et grass-sources.log. Ce banc est local/synthétique, pas une preuve appareil et pas un verdict global. Portée limitée aux entrées et macros testées ; aucune validation owner produite.

## Retest correction : programme mesure séparé
Commande : `bash .autoport/reports/shrub-trunk-contact/notes/attempt-9-neutrality/run-grass-separate.sh` ; rc=0, `grass-separate.log` et `grass-separate-sources.log`.
Lecture Shader.cpp: programme couleur conserve source sans macro, programme mesure séparé macro OG_GRASS_CONTACT_PROBE. Lecture GrassRenderer.cpp capture: GL_RASTERIZER_DISCARD, uniforme u_probe_grass_no_contact=1 pour pré, puis =0 pour post, restauration programme couleur. Banc reproduit cet ordre avec glDrawArraysInstanced (une instance), queries primitives exigeant exactement 10 sorties et vérification GL_RASTERIZER_DISCARD actif pour chaque capture.
Sur les 18 mêmes cas : toutes sorties couleur actuelle sans macro versus historique strictement identiques (480 octets par cas), gl_Position programme mesure contact-switch=0 versus couleur identique aussi, indépendamment de contact actif/inactif. Alpha mesure désormais identique également (information mesurée, pas un critère requis puisque programme mesure ne rasterise pas).
Deux captures uniformes1→0 fournissent pré/post : 8/10 sommets changent au contact near, 5/10 au contact card ; 0/10 sans contact. Six early-culls gardent w=0 ; sorties normales égales. Captures `.bin` nommées grass-separate-s<scenario>-c<contact>-historical/color/before/after.
L'échec de l'ancienne architecture est conservé sous grass-initial-*. Le nouveau résultat ne constitue aucune validation appareil ou globale.
