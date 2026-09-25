# Deux astres, deux jeux d'ombres, et les acteurs qui en projettent — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Une seule cascade attribuee a « l'astre le plus haut », avec fondu et EMA pour cacher une bascule qui n'a pas lieu d'etre : les deux astres sont leves ENSEMBLE 3 h 30 par jour. Et aucun acteur n'entre dans la carte. SPEC 3.4 et 4.8.

RETOUR DE TEST DE L'OWNER (24/09, build 60d16fa6, sur telephone) : avec le reglage « vraies ombres », il voit TOUJOURS les aplats PS2 ; seul « Aucune » change quelque chose (les ombres disparaissent). « cable a moitie ». Il demande aussi : pas de reglage de qualite ? et les ombres des acteurs vont-elles s'empiler sur celles du monde comme un aplat ?
PISTE DEJA SIGNALEE PAR L'ESSAI PRECEDENT (reports/lighting-shadows/FINDINGS.txt) : `shadow_merc_min_dist_dm` vaut 0 sur l'APPAREIL et 93 sur le bureau dans la meme scene (distance camera de l'os racine vraisemblablement pas calculee sur appareil) ; la scene appareil village1-hut ne montrait AUCUNE ombre d'acteur (hits=0) et la preuve a ete deplacee sur village1-warp ; `shadow_actor_px` publie 0 sur les deux plateformes alors que la sonde compte ~56 000 px : cle morte ; kmachine.cpp:2445 ne logue que sur changement : aucune trace que le pack GOAL pousse le reglage a chaque image. La porte a donc ete tenue par une scene et des cles qui ne voyaient pas ce que l'owner voit.
CE QUE DIT LA SPEC (a respecter) : l'aplat PS2 ne SURVIT que comme repli hors portee des cascades et comme mode Original (§1.2 decision 2, ligne 178) ; « Jak n'a jamais deux ombres a la fois » ; l'ombre d'acteur est un maillage skinne DANS l'atlas partage avec le decor (§4.8, ligne 1109) : une seule visibilite, pas d'empilement.

RETOUR DE TEST DE L'OWNER N°2 (24/09, build f215fd, telephone) : l'ombre atlas est LA et la projection est juste (soleil et astre de nuit), MAIS elle est a peine visible, « de l'ordre du pixel peeping », meme curseurs au maximum, meme HDR coupe. En l'etat : tres couteux pour un effet que personne ne verra. Les PNJ du village sont en interieur (eclairage interieur encore cuit, pas d'ombre) : Jak est le seul vrai temoin.
PISTE (non prouvee) : l'ombre n'assombrit que le terme DIRECT ; depuis lighting-bake, l'eclairage peint par ND est rendu comme INDIRECT (ambiante + art) et porte l'essentiel de la luminosite du sol ; le direct temps reel ne pese alors presque rien et son ombre non plus. Voir SPEC « Dosage du direct (Fidelite) » et §5.2 (decomposition baked).

RETOUR OWNER DU 25/09 (sur lighting-regimes, build 16773c) : l'ombre de Jak se voit enfin, MAIS a village1 elle DISPARAIT COMPLETEMENT sur les PONTS, alors qu'elle reste sur les sols et les murs. Piste : les ponts sont probablement des TIE (instances) et ne recoivent pas l'atlas d'ombre des acteurs, ou leur chemin de rendu ne lit pas la visibilite.

RETOUR DE TEST N°3 DE L'OWNER (25/09, build f79a20) : l'ombre est la sur les ponts, « C'est déjà très stylé hein, mais c'set pas encore bon ». Defauts : (1) l'ombre de Jak CLIGNOTE (« blink in and out ») ; (2) des ombres APPARAISSENT SOUDAIN (pop-in) a Sandover, devant la hutte du maire ; (3) une image de l'ancien aplat PS2 a transpire le temps d'une frame ; (4) la LUNE verte ne projette presque pas d'ombre, meme force au maximum.

## Livrable — le contrat, en entier

Atlas unique tuile, cascades stabilisees pour l'astre dominant, une tuile pour le second, les acteurs dans la passe de profondeur avec leur maillage skinne, ombres de contact sur la prepasse. L'aplat PS2 reste le repli et le mode Original. SPEC 4.8. PREUVE : `FEATURE lighting-shadows armed=1 hits=<pixels de sol ombres par un acteur>` + la ligne `shadow_caster_classes=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-shadows"), jamais armed(), et n'en ecris pas un second. AMENDEMENT 09-09 (perf) : une seule passe Z merc partagee entre prepasse (4.6), atlas (4.8) et aplat 47, VAO persistant par niveau (API setup_merc_vao conservee). Menu « Ombres d'acteurs » a trois crans vraies / aplat PS2 / aucune + fade-dist expose ; le cran « aucune » desactive la famille shadow-* cote GOAL.

AJOUT APRES LE RETOUR OWNER DU 24/09 (allege sur son ordre : « Te prends pas trop la tête avec les preuves visuelles ») :
A. Corriger la cause : sur l'APPAREIL, le reglage « vraies ombres » doit dessiner l'ombre atlas des acteurs au lieu de l'aplat PS2 (piste : distance camera de l'os racine a 0 sur appareil). UNE grandeur suffit, dans la course normale : par image, nombre d'aplats PS2 dessines et nombre d'ombres atlas dessinees pour les acteurs ; en « vraies ombres », aplats = 0 et atlas > 0.
B. QUALITE DES OMBRES = CE QUE LA SPEC DEFINIT DEJA, pas un nouveau reglage invente (owner 24/09 : « attention à ce que les réglages de qualité pour les ombres collide pas avec d'autres chantiers [...] faudrait pas refaire deux fois le même travail »). Livrer les lignes « Ombres » de la SPEC §6.2 qui relevent de CE chantier (resolution d'atlas 2048/4096/8192 selon les paliers 0/1/2 de §4.8, cascades 2/3/4, distance 40..200 m, force, ombres d'acteurs vraies/aplat PS2/aucune, ombre du second astre), chacune ecrasable dans le menu. L'echelle globale Tres bas -> Ultra qui POSE ces valeurs appartient a lighting-presets (SPEC §6.3) : ne pas la refaire ici, exposer les valeurs pour que lighting-presets les pilote. Les ombres de contact (§6.2) attendent la prepasse des acteurs (lighting-actors).
C. PAS de campagne multi-scenes, PAS de comptage de pixels : l'OEIL, c'est l'owner. Des que A et B tiennent, livrer le build et passer en to-test.

AJOUT APRES LE RETOUR N°2 : RENDRE L'OMBRE VISIBLE. Trouver pourquoi l'ombre est si faible (mesurer la part du direct dans la luminance du sol ensoleille sous Jak) la part du direct se corrige dans lighting-regimes (dependance ajoutee le 24/09, owner : ne pas faire le travail deux fois) ; ICI seulement l'application de la visibilite d'ombre, pas un noircissement artificiel. UNE grandeur : rapport de luminance sol-a-l'ombre-de-Jak / sol-au-soleil juste a cote, de jour au village, au reglage PAR DEFAUT ; publier aussi sa valeur a Force max. Viser une ombre nettement lisible (ordre de grandeur : le sol ombre au moins 35 % plus sombre au reglage par defaut) ; l'owner juge a l'oeil ensuite. Pas de campagne multi-scenes.

AJOUT DU 25/09 : l'ombre des acteurs est recue par TOUTES les familles du decor (sol, murs, ponts/TIE, buissons). UNE grandeur : pour chaque famille visible sous Jak au village1, part de pixels a l'ombre de Jak ; une famille a 0 alors que Jak est au-dessus = defaut nomme.

AJOUT APRES LE RETOUR N°3 (preuve legere, une grandeur par defaut, l'oeil c'est l'owner) : (1) clignotement : nombre d'images ou l'ombre atlas de Jak manque alors qu'il est a portee, sur une course de jour ; doit valoir 0 ; (2) pop-in : pas de coupure franche a une distance ou a un changement de cascade (fondu entre cascades et en bout de portee) ; (3) aucune image avec l'aplat PS2 dessine en mode « vraies ombres » (compteur par image) ; (4) lune : de nuit, rapport sol-a-l'ombre / sol-eclaire sous la lune a la force par defaut, lisible comme celui du soleil. Puis livrer.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle. L'aplat PS2 de shadow-geo n'est pas retire ici : il devient le repli et le mode original (decision owner 2026-09-03). Son remplacement en champ proche est lighting-actors.

## Ou l'owner regardera

l'ombre de Jak et des PNJ au sol, et le matin quand les deux astres sont leves ; et dans le marais et le tube de lave : l'ombre doit montrer que la lumiere ne vient plus d'un soleil invisible (verification reportee de lighting-regimes, owner 25/09).

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-03
> quand les deux overlap... Bah ca doit etre pris en compte, ca l'est pour nous aussi quand on a la lune et le soleil visibles en meme temps !

### 2026-09-05
> Ça fait une éternité qu'on bosse sur des trucs de merde sans changements majeurs, j'aimerais un truc qui a un vrai effet Waouw next round du worker j'aimerais que ça parte sur le realtime lighting histoire d'avoir un réel sujet vraiment intéressant. Laisse finir le travail en cours et on passe sur l'intégralité du realtime lighting !

### 2026-09-24
> Alors j'ai activé les vraies ombres… ça reste les à plats PS2… le seul truc qui marche c'est "Aucune" mais du coup ça enlève juste les ombres. J'ai comme l'impression que le truc est câblé à moitié, d'ailleurs pas de réglage de qualité ? Quid des ombres avec les ombres du monde, elles vont se stacker les unes au dessus des autres comme un vulgaire a plat d'image ?

### 2026-09-24
> La scène où je joues… c'est juste partout… en plein jour

### 2026-09-24
> Te prends pas trop la tête avec les preuves visuelles, t'es toujours assi mauvais pour ça et tu perds un temps monstre et gaspille une quantité de tokens colossale pour soit des preuves bidons, soit des blockers qui n'en sont pas parce que t'es à chier sur le visuel, c'est pas la première fois que je te le dis et ça me casse les couilles de te le réexpliquer chaque fois !

### 2026-09-24
> attention à ce que les réglages de qualité pour les ombres collide pas avec d'autres chantiers sur les ombres qui s'appuient sur la même spec hein. faudrait pas refaire deux fois le même travail, ou ignorer des aspect importants de ça juste parce que je l'ai mentionné

### 2026-09-24
> Alors en faisant trééééééés attention de l'ordre du pixel peeping oui l'ombre est là, avec le soleil et l'astre de nuit…. C'est tellement faible même en poussant les curseurs au maximum que c'est barely noticeable. Déjà quasiment impossible à remarquer avec Jak que je peux bouger partout, alors avec le seul autre PNJ en extérieur c'est impossible à voir. Les autres PNJs du village sont en intérieur et l'éclairage intérieur est encore baked il me semble donc pas d'ombre du tout. Sinon oui ça a l'air juste la projection, mais en l'état c'est inutile car extrêmement coûteux alors que personne ne verra l'effet, j'ai pensé que c'était dû au HDR peut-être mais il n'en est rien, c'est barely noticeable même HDR off

### 2026-09-24
> Si ça collide avec un autre chantier lié il faut faire attention hein ! Mais dans ce cas c'est pas validable en l'état et faut que les autres chantiers liés avancent

### 2026-09-25
> Top donc comme j'ai dit dans l'autre commentaire pour le soucis des faces qui était mal orientés sur village3 il faut s'assurer (via ticket dédié) que ce soucis est règlé partout. Pour les ombres de Jak, on les voit maintenant c'est super ! Mais bizarrement par exemple dans village1 (Sandover Village), sur les ponts, l'ombre disparaît complètement, alors que sur les sols et les murs non, bizarre non ?

### 2026-09-25
> "Capture impossible : la capture d'écran est refusée par le garde-fou du harnais" c'est débile, certes je préfères vérifier l'aspect visuel moi même, mais tu devrais pouvoir prendre des captures, surtout si c'est pour les joindre à la conversation sur Linear !

### 2026-09-25
> ça peut servir de mesure dans certains cas… faut pas non plus être débile. Mais je veux pas que ça parte dans des mesures visuelles complexes à fumer X millions tokens et prendre 4h de capture (j'exaggère) pour du faux vert ou du faux rouge alors que ça me prendrait 5 minutes de vérifier moi même ! Deux poids deux mesures !

### 2026-09-25
> Alors ça fonctionne, on a bien l'ombre sur les ponts et compagnie, mais l'ombre de Jak a tendance a blink in and out, et on a des ombres qui pop-in à sandover village par example (devant la hutte du maire). J'ai même vu le temps d'une frame l'ancien ombrage a plat PS2 transpiré étrangement. La lune (astre vert de la nuit) ne semble pas/plus cast de shadow aussi, poussé au maximum (la force) on voit un peu en pixel peeping mais du coup pas ouf.  C'est déjà très stylé hein, mais c'set pas encore bon !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

