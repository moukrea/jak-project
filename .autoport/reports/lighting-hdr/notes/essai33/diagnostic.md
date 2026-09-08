DIRECTIVES ve7fcbe0116

Essai33 : reprise32, recherches natives sky_diagnostic, portal_diagnostic, eco_diagnostic ; implémenter cloud_attribution_fix ; tester device_verification.

Ciel : témoins32 lf1453 TBP8064/12vertices et8096/96vertices tous ABE, mais sky-tng.gc721 gradient (Cs-Cd)*As+Cd,776 nuages Cs*As+Cd.
Correction d’attribution DirectRenderer : sélection ALPHA(0,2,0,1,0) et enregistrement des cinq composantes ; aucun shader/courbe réglé.
Soleil32 lf1749 : middot vertexRGB(1,.50196,0), rayons(.24706,.12549,0),36/36queries h18 passent sur12samples, deltaB nul.
weather-part.gc470-478 suit current-sun.sun-color puis divise rayons par quatre ; bleu absent de la source observée, blancsOFF absents ne prouvent pas disparition des rayons.
L’exigence actuelle helper de blancsOFF dans sky_sequence_judgment laisse ce soleil non jugé ; aucune modification du helper ni prétention à l’éclat validé.

Portail32 : portal-source32.json conserve SHA source et statistiques des couleurs modulées envoyées au shader, pas une décomposition de l’image.
Harddot1973 village1-part2.gc1763 : R/G aléatoires0+32, B64+64, A0+64, vie.035s ; shader sans branche éclairage, mode2 additif SRC_ALPHA,ONE.
Terme maxtexture sourceG*alpha h12 ON.035494/OFF.063360 ; B*alpha.316781/.315243. Limite : événements par sprite, h18ON7événements sur6frames.
La ROI native32 union variait : comparaison en lumaRec709x255 avant sprites h12ON62.559/OFF71.014,h18ON51.376/OFF61.056 ; sprites réduisent cet écart moyen, sans décomposition disque fixe.
Correction attribution Sprite3 : conserver union1395 et calculer une5e région pour harddot1395mode3 supported/passed dans les mêmes snapshots ; aucune lectureGPU en plus.
Limite conservée : delta groupe entier dans bornes du disque, inclut halos superposés ; jamais décrit comme contribution isolée de harddot.

Éco : ablation29 et traces30 exploitées sans run neuf. HDR0 suffit encore à reproduire déficit natif10012h18(543.67/1148.33).
REFSET provenance-init déclare actor_rng_state=not-restored-by-sidecars (refset.cpp2000), repin libère particules mais ne restaure pas tout état lanceur.
Après ORBPOST, sparticle.cpp907-963 peut libérer particule, Sprite3.cpp1860-1880 cull rayon/frustum,1908-1928 ADGIF,1930-2012 bucketTBP/instance.
SPR3-CULL filtre blue==0&&green>=100 et exclut bleu observé ; GORBSKIP0 sous horloge différente ne prouve pas un chemin complet. Pas de nouvelle répétitionORB/clamps/quantification/nommage.

Hutte : candidat géométrique extrait dans decompiler_out/jak1/levels/village1/village1-background.glb SHA479edc590f5362289efdb4aa3ad5e6c0fa56619d48d9b9d2b326a92d2877f028.
Mesh0/primitive6/material7/texture6 vil1-jng-leafyground ; indices1104-1135 (32triangles), bounds x[-127.484856,-118.609596],y[47.187000,47.374992],z[200.327759,209.203018].
Accessors POSITION0,TEXCOORD_0=1,COLOR_0=2,indices9 ; aucun transformnode ; MASKalpha.149019614,doubleSided,goal_draw_mode=-116513187.
Cinq triangles proches du sage :1111 indices9829/9828/9827 distance9.175347m ;1110 9828/9826/9827 9.217224m ;1119 9839/9829/9837 10.214653m ;1118 9829/9827/9837 10.221731m ;1109 9827/9826/9825 10.294255m.
Normales géométriques de winding vers-Y≈-.999, pas normales shader ; nomtexture/coordonnées ne suffisent PAS à qualifier ces triangles comme région du défaut owner.
COLOR_0 triangle1108 aB>R>G, export seul ne désigne aucune heure12/18 ; ne pas défendre violet attendu à partir de cela.
Sable nommé vil-beach-01 le plus proche y≈34m sous plateforme, aucune projection/occlusion runtime ou correspondanceFR3chargé établie.

non prouvé : correctif rendu des5cas, attribution définitive sol, bilan21niveaux8heures, acquis complets, HDRnatif. Aucun generic/owner-ok ni validationowner.
