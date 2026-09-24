# Deux astres, deux jeux d'ombres, et les acteurs qui en projettent — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Une seule cascade attribuee a « l'astre le plus haut », avec fondu et EMA pour cacher une bascule qui n'a pas lieu d'etre : les deux astres sont leves ENSEMBLE 3 h 30 par jour. Et aucun acteur n'entre dans la carte. SPEC 3.4 et 4.8.

RETOUR DE TEST DE L'OWNER (24/09, build 60d16fa6, sur telephone) : avec le reglage « vraies ombres », il voit TOUJOURS les aplats PS2 ; seul « Aucune » change quelque chose (les ombres disparaissent). « cable a moitie ». Il demande aussi : pas de reglage de qualite ? et les ombres des acteurs vont-elles s'empiler sur celles du monde comme un aplat ?
PISTE DEJA SIGNALEE PAR L'ESSAI PRECEDENT (reports/lighting-shadows/FINDINGS.txt) : `shadow_merc_min_dist_dm` vaut 0 sur l'APPAREIL et 93 sur le bureau dans la meme scene (distance camera de l'os racine vraisemblablement pas calculee sur appareil) ; la scene appareil village1-hut ne montrait AUCUNE ombre d'acteur (hits=0) et la preuve a ete deplacee sur village1-warp ; `shadow_actor_px` publie 0 sur les deux plateformes alors que la sonde compte ~56 000 px : cle morte ; kmachine.cpp:2445 ne logue que sur changement : aucune trace que le pack GOAL pousse le reglage a chaque image. La porte a donc ete tenue par une scene et des cles qui ne voyaient pas ce que l'owner voit.
CE QUE DIT LA SPEC (a respecter) : l'aplat PS2 ne SURVIT que comme repli hors portee des cascades et comme mode Original (§1.2 decision 2, ligne 178) ; « Jak n'a jamais deux ombres a la fois » ; l'ombre d'acteur est un maillage skinne DANS l'atlas partage avec le decor (§4.8, ligne 1109) : une seule visibilite, pas d'empilement.

## Livrable — le contrat, en entier

Atlas unique tuile, cascades stabilisees pour l'astre dominant, une tuile pour le second, les acteurs dans la passe de profondeur avec leur maillage skinne, ombres de contact sur la prepasse. L'aplat PS2 reste le repli et le mode Original. SPEC 4.8. PREUVE : `FEATURE lighting-shadows armed=1 hits=<pixels de sol ombres par un acteur>` + la ligne `shadow_caster_classes=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-shadows"), jamais armed(), et n'en ecris pas un second. AMENDEMENT 09-09 (perf) : une seule passe Z merc partagee entre prepasse (4.6), atlas (4.8) et aplat 47, VAO persistant par niveau (API setup_merc_vao conservee). Menu « Ombres d'acteurs » a trois crans vraies / aplat PS2 / aucune + fade-dist expose ; le cran « aucune » desactive la famille shadow-* cote GOAL.

AJOUT APRES LE RETOUR OWNER DU 24/09 (allege sur son ordre : « Te prends pas trop la tête avec les preuves visuelles ») :
A. Corriger la cause : sur l'APPAREIL, le reglage « vraies ombres » doit dessiner l'ombre atlas des acteurs au lieu de l'aplat PS2 (piste : distance camera de l'os racine a 0 sur appareil). UNE grandeur suffit, dans la course normale : par image, nombre d'aplats PS2 dessines et nombre d'ombres atlas dessinees pour les acteurs ; en « vraies ombres », aplats = 0 et atlas > 0.
B. Ajouter le reglage de qualite des ombres (Bas / Moyen / Haut) au menu.
C. PAS de campagne multi-scenes, PAS de comptage de pixels : l'OEIL, c'est l'owner. Des que A et B tiennent, livrer le build et passer en to-test.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle. L'aplat PS2 de shadow-geo n'est pas retire ici : il devient le repli et le mode original (decision owner 2026-09-03). Son remplacement en champ proche est lighting-actors.

## Ou l'owner regardera

l'ombre de Jak et des PNJ au sol, et le matin quand les deux astres sont leves

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

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

