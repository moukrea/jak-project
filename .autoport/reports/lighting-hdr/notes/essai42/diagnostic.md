DIRECTIVES v708c60642a
Essai42 : aucune modification rendu, aucun build. Genou0.96/libab2f8019a399c9c1 conservés.
Recherche nuages et portail indépendante, lecture seule ; aucun correctif rendu causal établi.

Nuages : essai41/sky96/composition/composition-events.json, h12 after_cloud_draw :
ON LF1601..1661 deltaR33743.80224609375→34577.931884765625 ; OFF LF1675..1735 deltaR34756.19296336919→35716.848042070866.
Les fenêtres successives dérivent : différence moyenne ne sépare pas format et animation.
sky-tng.gc155..167 incrémente quatre offsets par update, appliqués793/798 aux deux couches.
Aucun repin offsets trouvé dans PC/refset ; aucun offset/STQ/empreinte texel dans ces témoins.
Une phase UV différente est plausible, pas causalité démontrée ; particle_age égal ne prouve pas UV identiques.
DirectRenderer.cpp590..616 : color_mult/alpha_mult1, blendCs*As+Cd ; draws1/96vertices, pas chemin double dessin.
Pas de gamma/mediump ou double alpha trouvé ; pas de gain compensatoire justifié.

Portail : essai41/portal96/native-summary.json ROI147,42,173,79/7020px.
RGB avant groupe sprites ON(.264256265,.243431969,.314548236),OFF(.374328540,.351834262,.456120903), ratios(.705947,.691894,.689616).
Déficit des trois canaux, pas preuve d'un violet amont ; shade.glsl371..388 module volontairement éclairage/ombre.
Bras changent HDR+lighting+rt_light ; pas d'attribution pixel au facteur rt_mod.
Ne pas utiliser moyenne acteur1395 composition-summary (ROI variable7020..73593px) pour le disque fixe.
Sol réel : essai32/hut-portal/view-correspondence.md caméra(-138.451,49.300,203.282), ancrage sage(-132.659409,46.197540,213.467712).
Cet ancrage acteur ne constitue pas une ROI sol ; HUT_VIEWS reste vide.

Jugement soleil : whiteOFF>0 retiré seulement pour ce cas, blancs réellement présents toujours conservés.
Disque+deux rayons distincts obligatoires ; luma/luma_p99 sans perte, saturation/violet sans excès dans enveloppe temporelle OFF.
Statistiques et aire ROI vérifiées ; référence noire non jugée ; échecs partiels jamais effacés.
Fractions HSB270..330° rapportées à aire commune ; ni attribution pixel soleil ni verdict esthétique.
Sources41 relues en diagnostic sun-judgment.json : échec luma192.025309<minOFF192.806790 et violet.176440>maxOFF.173457.
P99 ON247.667/OFF247..248 ; saturationON.300656/OFF.300243...300832. Pas de nouveau run image.
Tests : suite initiale271passés/80.29s, après garde aire/noir62tests soleil/ciel passés/12.60s,211désélectionnés.
Revue researcher : faiblesse aire ROI corrigée, référence noire refusée ; moyenne temporelle n'est pas garantie par instant.

Nouveau crash menu : menu-off/proof-engine.log, runtime nearest-fn PCvector-matrix*!+0x18,LRhd-mtx-check-all+0x51c.
LDRw3[obj+0x1dfc], hd-mtxarea déduit0xffffffff ; k20,p19 donnent X2=0x100000a7f,X3=0x1000009ff.
LDRq23 à ee_base+X2 produit faute0x8000000a7f ; objet pile0x1eb6c4. A16x16-clobber faux signal pour cet ADDobjet/LDR.
Seul producteur hd-draw-check reçoit DMA align64, incompatible avec-1 normal.
Init-jak-hd ne pose pas ce champ MAIS activate hérité gkernel1763..1766 efface les champs : défaut init non établi.
Cache hd-scan-companions pointeurs bruts, compacteur relocalise via ppointer ; spawns17:24:26.515/.527 avant crash17:24:27.067.
Pas de déplacement/libération de cet objet observé, ni dernier écrivain du champ : pas de garde-1 ni patch spéculatif.
MenuOFF/persistanceOFF/ombresOFF non atteints ; réglages exacts restaurés, PID14537 stable20s, cf menu-off/verdict.md.
