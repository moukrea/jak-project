DIRECTIVES ve7fcbe0116

Essai32 : diagnostic ciblé nuages/soleil, puis vraie hutte/portail. Aucun build ni réglage photométrique.
Sources31 conservées ; chercheurs natifs crash_diagnostic, sky_curve, ground_portal ; tester device_sky.

Crash31 localisé dans spawn-bird, premier appel init-from-entity! seagullflock (seagull.gc889/913).
Source : batches/essai31-sky-final/20260908T094715-3936986/engine.log7039 warp1lf300 ;11173 seagullflock initialize ;12814 crash431.
PC0x268920c instr b85fc209 LDUR W9,[X16,#-4], fault=ee_base-4 ; valeur symbole *default-dead-pool*=0 dansW7.
Relocation BEA.DGO objet seagull (offset0x83c10), symbole offsetobjet0xf6b cible main0xa19c/0xa1a0 : ADRP/ADD PC-32/-28, LDR W7 PC-24.
Ce n'est pas un retour nul get-process : son BLR suit àPC+44. Pool gkernel déjà lié ; cause initiale inconnue.
Warpat900 est un contrôle configuration, pas un correctif de ce pointeur. OG_LEVEL_WARP_DELAY ignoré sous refset (kmachine6655).

Ciel32 : lot essai32-sky-before/20260908T100132-3950103, preuve officielle conservée notes/essai32/sky/proof-sky-before.txt.
36captures/85fichiers SHAOK/432compositions/crash0/frames2160/durée146s ; lib243591 inchangée.
h9cam3m chargeVIS ; h12/18cam500m maintenant atteints. Refset bg h9=162pm, h12/h18=583pm ; ce n'est PAS ciel pur plein cadre.
Soleil h18 trois composants passent sur12samples/36queries erreurassociation0m. Roi finale[142,67,178,112], aucun blanc/quasi-blancOFF niON.
ImageMagick soleil : lumaON192.001646/OFF193.183128 ; detailON8.263528/OFF8.040476 ; flatON.136688/OFF.131385. Comparaison statistique, pas frame exacte.
Nuages région finale[0,0,320,106]h12 : blancON92.333/OFF105.167 ; nearwhiteON270.833/OFF262.833 ; luma154.358/155.539 ; detail3.773633/3.791984 ; flat.205359/.199378.
La résolution native varie h12ON (pixels moyens290400) contreOFF244800 : ne pas comparer les sommes natives comme populations identiques.
ABE31 n'exclut PAS le gradient : témoins32 TBP8064 et8096 portent tous prim_abe=true, 12vertices vs96. Avant/après séparés dans native-summary.json.
Code sky-tng.gc721 : gradient ALPHA b=DEST,d=DEST ; clouds776 : b=ZERO,d=DEST. PRIM.abe n'est donc pas un discriminant gradient/nuages.
Les deux textures sont nommées par la donnée : gradient base-block742, cloud base-block+32 à780. Ne pas prétendre garde31 validée.
La courbe C1 k=.95 fait1→.9875, perte de blanc255 attendue ; sources31 ne montrent que -.47% quasi-blanc. Aucun nouveau genou justifié par le compteur255 seul.
Soleil blancOFF absent malgré trois couches visibles : le helper reste nonjugé selon contrat actuel. Ce fait ne démontre ni échec ni réussite de préservation de son éclat.

Hutte/portail : source de la caméra de contrôle : village1-actors.json6794 camera-start15 et6975 sage23 (champtrans, pasbsphere).
Cam existing village1-out:-10:-108:152:33, capspawn163°, C=(-138.451,49.300,203.282), distance6.3cm caméra native10345.
Ancre portail1395(-123.10158,50.40380,214.22531), harddot mode3. Résultats du contrôle dans hut-portal/tester-result.md.
Les sources27 ont3801SPRITE et0COMPOSITION ; les48COMPOSITIONportail30 sont no_visible_roi/pixels0. Pas de mélange natif avant32 pour cette zone.
Éco29/30 : acquis du handoff conservés, aucune répétition de campagnes ORB/clamps/quantification/nommage. Chaîne slot→DMA→soumission/culling/TBP non résolue.

Non prouvé : correctif rendu des5cas, couverture21niveaux×8h/ciels/intérieurs/vraie hutte, acquis, HDRnatif.
Aucun changement harnais/validateurs/owner-ok ni validation owner. Les états partiels restent en échec.

Agrégat32 : copies octet-identiques des deux lots sous batches/essai32-compatible, originaux préservés (aggregate-lineage.json).
Entrée officielle proof_run --hdr-aggregate-only20260908T100652-3955392 :2lots/5paires/5cellules/errors0/missing336/ownerfailed2missing5/defects4 ; horodatage original125s conservé par producteur.
Borne analytique de courbe àexposure1/knee.95 : max(clamp(x)-f(x))*255 =3.1875 atteintx1 (curve-bound.json). Sur même entrée elle ne peut expliquer écart luma portail h12=20.367810,h18=15.182779.
Inférence bornée : rechercher composition/éclairage/populations/rééchantillonnage en amont ; pas de nouveau genou compensatoire. Aucune résolution causale de ces facteurs n’est affirmée.
