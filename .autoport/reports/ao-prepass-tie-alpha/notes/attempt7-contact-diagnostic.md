DIRECTIVES v775512c234
# Essai 7 — diagnostic de la jonction mur/toit, 15 septembre 2026

## Conclusion et périmètre
La cause du défaut mur/toit n'est pas établie. Le diagnostic ci-dessous distingue
les traces historiques et les hypothèses tirées des sources. Aucun correctif moteur,
build, déploiement ou proof_run pendant cet essai. Le plan est épuisé (9/9) ; le
retour du 15/09 rouvre le contact, pas ce budget. La sélection USB exécutée par
`bash .autoport/lib/pick_device.sh` a réussi : sortie `eae4df44`, code 0.
L'indisponibilité d'un appareil n'est donc pas la raison de l'absence de course.

## Ce que les archives permettent de rattacher à la hutte
- `proof-engine.log:20282` : `TIE sway-cover lev=village1 tree=1 geo=0`,
  `proto_names_size=43`, `inst_total=870`, noms `vil1-hut-roofcap.mb`,
  `vil1-hut-beam-back.mb`, `vil1-hut-beam-front.mb`. Les lignes 20286/20289/20292
  publient les autres géométries. Cela nomme des candidats, pas les pixels du raccord.
- `notes/campaign/03-village1-hut-comparison/proof.txt:1516` :
  `ao_tie_campaign_position=-116_14_40`, vue/warp `village1-hut` (1517/1518).
  Population globale contact `106578` (355), crête `0` (1498),
  remplissage armé `1` et `5744` passes (497/498). Les six populations témoins
  contact sont nulles (349–354). Aucune attribution de ces plis au mur/toit.
- `notes/alpha-table.tsv` : 32 échantillons frame4, `color_id=pre_id=10`,
  alpha brut identique et profondeur identique. Cette table reste celle de l'ancien
  défaut d'alpha de MESURE ; aucune ligne n'identifie le mur et le toit.
- `ao_tie_alpha_probe.cpp:167` attribue l'ID à un couple adresse/index de draw ;
  `Meta` (36) décrit l'état GL, sans nom de prototype. L'ID10 ne donne donc pas
  l'attribution géométrique recherchée dans les archives consultées.
- La révision du build testé par l'owner reste inconnue (contrat/backlog).
- Aucun buffer brut AO/profondeur trouvé dans les archives hôte des deux rapports
  AO inspectés. Le complément en lecture seule USB (`attempt7-device-archives.txt`)
  retrouve deux références couleur et l'agrégat de campagne. L'en-tête de la référence
  hut identifie le tick1400, 800x600 et le binaire2510330782703692892 de l'essai5.
  Son producteur (`ao_tie_alpha_probe.cpp:439–440`) n'archive que RGBA et un masque
  TIE, sans profondeur/normales/IDs de surfaces. Aucune référence n'a été rejouée.

## Limites du contact existant — lecture des sources, pas mesure de la jonction
`AmbientOcclusion.cpp:1124` reçoit seulement AO, profondeur et dimensions.
Chaque échantillon est un couple pixel/axe horizontal ou vertical, sans ID d'objet.
Les triples contenant du ciel, un saut >2% ou une courbure insuffisante sont exclus.
La crête exige un centre plus clair de >4/255 que CHACUN des voisins immédiats
(1169). Une bande plate ou un éclaircissement unilatéral ne satisfait pas ce test.
La condition de largeur (1182) s'arrête nécessairement au premier voisin :
`ac > voisin+4` implique `voisin+1 < ac`. Sa valeur maximale est donc 1 lorsque
la crête est détectée, 0 sinon ; elle ne mesure pas une bande de plusieurs pixels.
Les états contact sont SSAO/GTAO seulement (686–690, 1686–1698, 2498) ; HBAO est absent.

`ao_blur.frag:87–107` remplit les maxima stricts avec les mêmes exclusions de
profondeur ; `AmbientOcclusion.cpp:2382` fixe quatre passes. Le zéro du compteur
ne prouve ni l'absence d'une bande large ni l'AO au contact géométrique demandé.

## Hypothèses à départager avant toute correction
1. Rejet d'occludeurs proches : `ao_ssao.frag:150–185` (biais, hauteur minimale,
   minr), `ao_hbao.frag:216–264`, `ao_gtao.frag:206,271,285` (rayons exclus).
2. Normale reconstruite incorrecte au raccord, renforçant ces exclusions.
3. Bande plate, contact en discontinuité de profondeur ou unilatéral, hors domaine
   du remplissage de crête (`ao_blur.frag:87–107`).
4. Différence entre l'AO produite et la couleur finale : `shade.glsl:435` lit l'AO
   à partir de gl_FragCoord. Aucune trace locale n'attribue le défaut à cette lecture.
Aucun échantillon mur/toit ne permet de choisir entre ces hypothèses. Modifier les
biais, le flou ou les seuils sur cette seule lecture serait un correctif spéculatif.

## Reprise concrète
Les noms de prototypes candidats et le vantage historique sont disponibles ; les
IDs des deux surfaces, leurs fragments de jonction, leurs profondeurs/normales et
l'AO avant/après filtrage ne sont pas identifiés ensemble. Cette attribution doit
précéder le correctif. Toute mesure supplémentaire demande un plan borné réautorisé
dans l'item ; ne pas relancer les neuf bras ni consommer une référence déjà utilisée.
Conserver les critères/acquis et la sonde statique. Non prouvé : correction du
contact mur/toit, identité couleur, stabilité et acquis des trois vues.
Les anciens rapport/handoff sont conservés dans `before-attempt7-*` ; l'empreinte
de la preuve historique et des sources lues figure dans `attempt7-audit.txt`.
