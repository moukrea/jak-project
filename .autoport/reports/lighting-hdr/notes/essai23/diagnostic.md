DIRECTIVES va841fb32b6

# Essai 23 — compression indépendante des canaux

## Mécanisme isolé

Le diagnostic `curve_gpu.cpp` charge le texte des shaders avant/après dans un contexte GLES Mesa et lit le framebuffer flottant. Il ne simule pas les équations en remplacement du shader.
Trace `curve_gpu.log` : entrée (2,1,2,0.5), avant (0.997727,0.498864,0.997727,0.5), après (0.997727,0.975,0.997727,0.5).
L'ancien facteur f(maxRGB)/maxRGB diminuait le vert d'un facteur deux alors que son entrée valait déjà un. L'épaule appliquée séparément conserve davantage cette contribution. Ce mécanisme produit un violet dans le test ; son attribution aux petites zones de terrain ou au portail du jeu n'est pas établie.
Trace sur (8,2,8,1) : vert 0.249912 avant, 0.997727 après. Trace sur blanc unitaire : (0.975,0.975,0.975) avant et après. La correction n'a donc pas pour objectif un nombre de pixels à 255.
Les 27 cas couvrent trois genoux, gris inchangés, Filmique inchangé, alpha inchangé, absence d'atténuation des canaux faibles par leurs voisins et sorties bornées sans ajout de luminosité par rapport à l'entrée. `samples=27 failures=0`.
Ce test hors appareil ne vaut ni preuve jeu ni verdict artistique.

## Modification bornée

`tonemap.frag` applique l'épaule rationnelle C1 existante à chaque canal dans le domaine d'affichage. Genou, exposition, option Filmique et alpha inchangés. Aucun bloom, aucune particule ajoutée.
`hdr.cpp::probe_scene` calcule le diagnostic de différence contre l'écrêtage avec la même épaule par canal ; seuils/verdicts inchangés. Le test scalaire de continuité/monotonie reste inchangé.
Le diagnostic de code ne justifie pas une OETF supplémentaire : `shade.glsl` décode puis réencode le PBR avant composition, tandis que les chemins directs transmettent déjà des couleurs d'affichage. Cette lecture n'est pas une preuve exhaustive de tous les chemins.

## Ancres des cinq cas et limites de mesure

Lecture seule des données `decompiler_out/jak1/entities/village1-actors.json` : portail aid22318=(-123.1058,46.1975,214.2314)m ; émetteur aid1395 group-village1-sagehut-warpgate=(-123.1016,50.4038,214.2253)m. Groupe140 dans village1-part2.gc.
Éco bleue : aid10012=(9.3109,19.2490,11.2525)m et aid10013=(6.6918,19.3725,20.4516)m, eco-info=[3,1], type3=eco-blue (fact-h.gc). Leur présence effectivement rendue dans une ROI n'est pas mesurée.
La vue `legacy` est ancrée en (-116,14,40)m, à environ178m des acteurs sagehut. Son commentaire ne permet pas d'en faire la région « sol devant la hutte » ; les petites zones visées restent non identifiées.
Le soleil possède une direction sémantique accessible via *sky-parms* upload-data sun 0 pos (hud-classes-pc.gc), mais aucune région projetée/cadrée n'est enregistrée dans les lots courants. Un rectangle supérieur ne prouverait pas à lui seul la présence des nuages attendus ou du soleil.
`refset.cpp::particle_step_mode` retourne zéro après g_plan_base+g_step_settle : les captures courantes figent les particules et ne constituent pas une séquence électrique. Une seule image par vue/heure/phase est produite. Il faut une courte fenêtre temporelle avec présence effective de l'éco, sans restauration à la frame près.
Les coordonnées seules ne prouvent ni visibilité, ni absence d'occlusion, ni présence des particules. Aucun verdict régional n'est fabriqué à partir de ces coordonnées.
La garde existante `hdr_owner_regressions_measured=0/missing=5` reste nécessaire ; le cumul par lots et generic ne sont pas modifiés.

## Avant/après

AVANT conservé : lot officiel essai22-alpha/20260908T052020-3705704 ; shader avant et proof avant copiés dans ce dossier, binaire/APK avant sauvegardés par build-deploy.sh.
La comparaison entre binaires est diagnostique : les lots avant ne seront pas agrégés comme preuve du nouveau rendu. Aucun chiffre global ne sera présenté comme correction des cinq régions.

## Revue indépendante

Le cas GPU (8,2,8) devient presque blanc après compression par canal. Le rapprochement du blanc ressemble à l'écrêtage OFF, mais ce résultat synthétique ne permet pas de décider si une partie intentionnellement violette d'un effet a conservé sa couleur : les régions restent à juger.
Le diagnostic `ldr_ref_delta` continue à comparer une épaule Fidélité d'exposition1 au clamp du même pixel. Il ne représente ni la différence ON/OFF ni le mode Filmique. Avec genou0.95, son maximum analytique est0.025, environ6 unités arrondies sur255 ; sa diminution ne peut valider les cinq régressions.

## Mesures appareil après livraison

Source : after-analysis.json, images décodées de nouveau par ImageMagick et hashes vérifiés contre chaque manifeste. Comparaison image entière, sans synchronisation exacte exigée et sans attribution régionale.
h12: OFF après quasi-blancs=3, ON avant=0 après=2; blancs ON=0; luma ON 70.986354→71.346406; aplats ON 0.040402→0.034588.
h18: OFF après quasi-blancs=0, ON avant=0 après=0; blancs ON=0; luma ON 73.341319→73.547170; aplats ON 0.037337→0.033712.
village1-out-h12: OFF après quasi-blancs=1340, ON avant=0 après=1264; blancs ON=0; luma ON 123.473993→128.986372; aplats ON 0.038791→0.033047.
village1-out-h18: OFF après quasi-blancs=3, ON avant=0 après=1; blancs ON=0; luma ON 95.518125→98.228837; aplats ON 0.061873→0.050595.
Lot essai23-channel/20260908T053521-3717470 : quatre paires, zéro erreur de lot, zéro LOADSCREEN-SHOW. Proof officiel : durée120s, crash0, frames1200, hits672253, tonemap_sites1, hdr_tonemap_defects4. Les deux cellules village1 à12/18 ne couvrent pas21niveaux×8h ; les cinq cas restent absents.
À midi en extérieur, les quasi-blancs ON remontent de0 à1264 face à1340 OFF. Les blancs exacts ON restent0 face à768 OFF. Ces comptes ne prouvent ni restauration des nuages ni préservation des petites régions lumineuses.
