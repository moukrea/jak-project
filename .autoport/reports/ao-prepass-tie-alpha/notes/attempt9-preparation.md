DIRECTIVES v775512c234
# Essai 9 — préparation numérique du raccord hutte

Le plan du15/09 autorise six courses ; aucune n'a été lancée dans cet essai.
Le défaut owner reste établi. La cause mur/toit n'est pas encore attribuée.
Ceci est un changement de code de préparation, pas un nouvel audit documentaire.

## Fichiers livrés
- ao_contact_geometry.h + LoaderStages.cpp : export village1 avant libération CPU.
  Les matrix_groups sont parcourus en indices dépaquetés ; les indices originaux sont
  reconstruits depuis runs/plain_indices puis appariés aux indices soudés effectifs.
  Niveau, LOD/arbre, catégories, prototypes, visgroups, groupes/matrices et sommets source
  restent nommés. Positions/normales/UV finales et SwayRecord8 sont archivés.
  Limites par arbre :4M sommets ; par draw :8M indices ; exceptions signalées.
  Un rechargement pose reload_untracked=1 : l'ancienne archive ne certifie plus la géométrie.
- ao_contact_archive.h : garde item exact + armé + capture explicite ; dossier exclusif
  user_home/ao-hut-archive-[OG_REFSET_RUN_ID-]pid-1400. Le suffixe1400 est le tick ciblé.
  Le hash geometry est refset_file (offset historique), pas un SHA256 du FR3.
- AmbientOcclusion.cpp : une tentative au tick1400 ; erreur si le tick est sauté.
  R8 brut, toutes jambes blur, quatre ridge, paramètres et matrices AO sont archivés.
  Les trois modes utilisent ce même chemin ; aucun changement du calendrier statique.
  Le manifest status=complete signifie écriture complète des stages AO seulement.
- frame_ubo.cpp : les224 octets effectivement liés, nommés par render_frame et hash.
  Le manifest AO donne le même render_frame ; plusieurs UBO restent possibles par image.
- ao_contact_readback.h : lecteur R8 sauvegardant FBO/readbuffer/PBO et PACK complet.
  Une erreur antérieure est enregistrée et refuse la lecture ; jamais un succès vidé.
- ao_contact_profile.h : diagnostic CPU indépendant exigeant labels ET identités non nulles
  ET arêtes de contact physiquement qualifiées par l'appelant. Seuil strict4/255 conservé.
  Marche8 pixels +référence ; plateaux sans contraste censurés, jamais verts par défaut.
  Reverse-Z : ciel<=1e-9 ; saut de profondeur compté, pas exclu sur contact qualifié.
  Résultat band_pixels cumule les largeurs par côté ; ce ne sont pas des pixels uniques.

## Vérifications exécutées
- test/test_ao_contact_geometry.cpp :28 vérifications ; provenance source/VBO, soudure,
  runs/plain/restarts, bornes, matrices/protos absents, frontières de visgroups.
- test/test_ao_contact_profile.cpp : largeurs1/3/8, seuil4/5, bande unilatérale,
  plateaux censurés, reverse-Z, NaN/données absentes, identités distinctes de même classe.
- test/test_ao_contact_readback.cpp : EGL surfaceless Intel/Mesa GLES3.2 ; pixels,
  dessin suivant et état identiques, READ_BUFFER=NONE restauré, PBO sentinelle intact.
  Aucune capture/inspection visuelle. Ce test local ne prouve pas le comportement Honor.
- Compilations strictes et exécutions :0 ; logs attempt9-test-*.log.
- Builds batch x86/Android :0 ; dernière identité dans attempt9-build-identities.txt.
  Second batch justifié par warning Android corrigé et identité render_frame ajoutée.
- USB sélectionné par pick_device :eae4df44 ; notes/attempt9-usb.txt.

## Avant la première course — travail restant, pas attente d'autorisation
1. Raccorder profondeur prépasse ET scène au même render_frame, normales par pixel,
   exclusions de chacun des estimateurs et contribution indirecte réelle à la couleur.
   Réutiliser export_depth avec état GL soigneusement préservé ; sa fonction initialise
   des objets avant snapshot et suppose PACK/PBO neutres : ne pas l'appeler naïvement.
2. Associer chaque draw/plage rendue à son UBO/viewport et aux primitives exportées.
   Raster CPU éventuel : tfrag3.vert utilise pc_camera/cam_trans et512/448, pas seulement
   camera_matrix AO. Reproduire clipping/restarts/alpha ou déclarer ambiguïté.
   Ne pas prendre un indice soudé comme identité originale, un draw comme surface,
   ou une simple adjacency écran pour un contact physique. Mur TFRAG possible, non établi.
3. Identifier instances/surfaces mur et toit, populations non vides et distance au contact ;
   brancher ao_contact_profile sur ces données, conserver les critères historiques séparés.
4. Vérifier neutralité de l'instrumentation complète et entrées exogènes comparables.
5. Épingler DANS LE BACKLOG le premier bras SSAO avant : actuellement proof_props est encore
   le bras beach historique. Retirer les anciens tie.campaign/view/reference, utiliser
   village1-hut, position -116 14 40, capture=1, mode1, timeout<=150. Ne pas relancer9/9.
   Les propriétés capture sont debug.opengoal.ao.contact.capture / OG_AO_CONTACT_CAPTURE.
6. Seulement ensuite consigner budget et lancer proof_run ; trio avant puis correction
   causale puis trio après. Si première archive manque, diagnostiquer sans répétition identique.
7. Le plan hutte ne ferme pas identité couleur/stabilité/acquis extérieurs du contrat complet.

Aucun correctif du rendu ni réglage alpha/biais/flou/seuil. Aucun déploiement explicite.
Aucun nouveau proof.txt, aucun chiffre historique revendiqué courant, aucun owner-ok.
