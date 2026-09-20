# L'herbe se couche dans la direction du pas, au lieu de s'ecraser en rond — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 11. Le systeme est plus riche que l'owner ne le croit — Jak, une trainee de quatre echantillons espaces de 0,15 s, la prise de rebord, huit acteurs ecrasables et huit occultants, montee 0,25 s, descente 0,6 s, pierres tombales de 8 s — mais la FORME reste un disque. La direction du deplacement est connue par la trainee et n'est JAMAIS utilisee comme vecteur. PIEGE MATERIEL A RECONDUIRE : sur Adreno 618, les lectures de tableaux d'uniformes a index DYNAMIQUE rendent des ordures. Le code deroule a index litteral et plafonne a huit occulteurs pour cette raison. Ce bug NE SE VOIT PAS sur x86.

COHERENCE HERBE (owner 20/09, sur les tickets variantes ET couleur : « a voir avec l'ensemble des tickets lies… j'aurais cru que c'etait compris depuis le debut ») : les chantiers d'herbe (silhouettes, couleur, vent, exposition, pas, biomes) forment UN SEUL rendu que l'owner juge d'un coup. Avant de coder : lire la SPEC-refonte-herbe EN ENTIER et TOUS les retours owner des items grass-* (owner_feedback de chacun) ; ne rien defaire de ce qu'un autre item d'herbe a livre ; si un choix ici contraint un autre item d'herbe, l'ecrire dans FINDINGS avec '-> item:<id>'. Les silhouettes par touffe (grass-blade-variants) sont le socle : couleur et vent s'y appuient et passent APRES.

20/09 13:45 RETOUR OWNER (JAK-124) : « toujours tres fake et pas vraiment correle au mesh du personnage… tu le mets en review alors que tu dis toi-meme qu'il reste des trucs a faire ! Quand on saute l'herbe se releve et quand on atterrit ca passe d'un etat a l'autre instant sans transition. Quand on spin ou punch en avant, on voit clairement que c'est fake et que ca prend pas en compte le mesh de Jak (ou ses collisions) ». DEUX FAUTES DE CADRAGE : (1) la porte mesurait une DIRECTION de couchage a partir de la position et du cap de Jak (un point + un vecteur), pas l'empreinte de son CORPS ; (2) l'item est passe en test avec un RESTE declare — une brique qui dit elle-meme qu'il manque quelque chose ne va pas au test de l'owner (regle Refonte de DIRECTIVES), le superviseur aurait du le retenir. PERIMETRE DE LA REPRISE : (a) la source du couchage est l'ensemble des SPHERES DE COLLISION de Jak (collide-shape : pieds, corps, et les volumes d'attaque du spin et du punch quand ils sont actifs), projetees au sol, PAS un point+cap ; (b) dynamique par brin/touffe : un ressort amorti (temps de retour 0,6-1,2 s), pousse par la vitesse des spheres, jamais un etat binaire ; a l'atterrissage, l'impact couche et le ressort rend ; (c) spin = couronne, punch = lobe devant le bras, chute = disque d'impact puis recuperation. PORTE : correlation entre la carte de couchage et l'empreinte au sol des spheres actives >= 0,8 sur une course scriptee (marche, saut, spin, punch) ; aucune variation de couchage > 30 % entre deux images consecutives hors impact ; temps de retour mesure dans [0,6 ; 1,2] s ; ablation : sans spheres = 0 couchage. Capture ou courte sequence jointe.

## Livrable — le contrat, en entier

`grass_interaction_defects` = 0, somme de termes publies SEPAREMENT.
1. LA FLEXION SUIT LE MOUVEMENT : publier l'angle entre la direction de flexion moyenne et la direction de deplacement, sur une traversee scriptee, sous un plafond declare. Aujourd'hui cet angle est aleatoire par construction.
2. LE DEGAGEMENT LATERAL EXISTE : publier l'ecart entre la flexion au centre du contact et celle sur ses bords. Un ecart nul veut dire qu'on ecrase encore en rond.
3. RIEN NE REGRESSE DE L'ACQUIS : le relevement amorti, les pierres tombales, l'annulation a la casse d'une caisse et la distinction entre acteurs caches et acteurs aplatis gardent leurs grandeurs. Publier chacune.
4. LE DEROULAGE A INDEX LITTERAL EST CONSERVE : publier le compte de lectures de tableau d'uniformes a index dynamique dans les shaders du chemin herbe, qui vaut zero. Preuve sur l'APPAREIL, pas sur x86 : ce defaut y est invisible.
PREUVE : `FEATURE grass-interaction-direction armed=1 hits=<contacts dynamiques appliques>` + la ligne `grass_interaction_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Ne change pas la portee ni le nombre d'interacteurs des paliers bas, qui gardent la loi radiale actuelle en repli. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Niveau d'entrainement, dans l'herbe. Quatre oui/non : (1) l'herbe se couche-t-elle la ou le corps de Jak passe REELLEMENT (pieds, jambes, et le bras sur un coup de poing, la roue sur un spin), et pas dans un disque ou un cone devant lui ? (2) quand il saute, l'herbe se releve-t-elle progressivement (ressort), et a l'atterrissage se couche-t-elle avec une transition, sans passer d'un etat a l'autre d'un coup ? (3) un spin couche l'herbe en couronne autour de lui, un coup de poing en avant la couche devant le bras ? (4) l'ensemble a-t-il l'air vrai ou fake ?

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-20
> Alors j'ai l'impression que c'est toujours très fake et pas vraiment corrélé au mesh du personnage… puis tu le mets en review alors que tu dis toi même qu'il reste des trucs à faire ! Et aussi, quand on saute l'herbe se relève et quand on atterrit bah ça passe d'un état à l'autre instant sans transition. Quand on spin ou punch en avant, on voit clairement que c'est fake et que ça prend pas en compte le mesh de Jak (ou ses collisions) pour influencer la façon dont l'herbe se couche!

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

