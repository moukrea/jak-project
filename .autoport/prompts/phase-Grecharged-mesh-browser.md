# PHASE Grecharged-mesh-browser — NAVIGATEUR DE MESH DE DEBUG (demande directe de l'owner)

Owner, mot pour mot :
  "Tu crois qu'on pourrait avoir un menu de debug qui nous permettrait de warp dans n'importe quel
   niveau pour prévisualiser n'importe quel mesh avec ses textures et compagnie, son PBR 'Rechargé'
   si existant, avec un toggle pour le damier en place de sa texture pour voir si le PBR rend bien,
   totalement contrôlable au tactile sur mobile et à la manette ? Ça me permettrait en tant
   qu'humain de vérifier tous les mesh dans des conditions multiples et réelles du jeu"

POURQUOI CETTE PHASE COMPTE PLUS QUE SON APPARENCE D'OUTIL : l'owner est le seul juge visuel du
projet (règle permanente : l'agent ne mesure JAMAIS le visuel in-game). Aujourd'hui il ne peut juger
que les quelques surfaces qu'il croise en jouant, et six rounds de PBR ont été dépensés sur cinq
surfaces nommées à la main. Ce navigateur transforme sa capacité de vérification : il pourra
balayer les 3613 mesh d'un niveau lui-même, dans les conditions réelles du jeu. C'est le
démultiplicateur du seul instrument fiable dont le projet dispose.

## CE QUI EXISTE DÉJÀ — NE LE RÉINVENTE PAS
* LE CATALOGUE : tools/tess_sign produit un CSV de 3613 lignes par niveau avec, par mesh, son
  système (TIE/TFRAG), son matériau, son tex_id, son centroïde monde, et ses notes A_sign% /
  B_disp%. C'est l'index du navigateur, il est déjà calculé. Il faut l'exporter dans un format
  compact que le jeu charge, et l'embarquer dans l'APK (règle owner : le dérivé va dans l'APK).
* LE DAMIER : game/graphics/opengl_renderer/loader/PbrTestPattern.{h,cpp}, déjà commutable par mode.
* LE WARP : debug.opengoal.level.warp et level.warp.pos placent le joueur à des coordonnées exactes.
* LE MENU : la page Recharged Settings et son système de lignes/carrousels (voir .autoport/menu-tree.md).
* L'ENTRÉE : couche tactile SDL + manette déjà opérationnelles.

## LIVRABLE
1. INDEX EMBARQUÉ : par niveau, la liste des mesh avec matériau, centroïde, boîte englobante,
   présence de maps PBR "recharged", et la note du test hors-ligne. Format compact, chargé à la
   demande, embarqué dans l'APK.
2. ÉCRAN DE NAVIGATION, atteignable depuis le menu de debug :
   * choix du niveau, puis liste des mesh, AVEC FILTRES : seulement ceux qui portent des maps PBR,
     seulement ceux notés fautifs par le test hors-ligne, recherche par nom de matériau.
   * TRI PAR PIRE NOTE D'ABORD : l'owner doit tomber sur les cas cassés sans les chercher.
3. CADRAGE AUTOMATIQUE : sélectionner un mesh warpe dans son niveau et place la caméra pour le
   cadrer proprement (distance déduite de la boîte englobante), avec orbite libre autour, zoom, et
   possibilité de reprendre le contrôle normal du personnage.
4. BASCULES, à portée immédiate pendant l'observation :
   * texture réelle <-> damier de debug ;
   * displacement : tessellation <-> parallax <-> aucun ;
   * curseur de relief ;
   * afficher à l'écran LA NOTE que le test hors-ligne donne à ce mesh. C'est capital : ça permet à
     l'owner de CONFIRMER OU RÉFUTER le verdict de l'outil. Si l'outil dit 100% et que l'owner voit
     une inversion, c'est l'OUTIL qui est faux — ce croisement est la boucle de contrôle qui a manqué
     à tous les rounds précédents.
5. CONTRÔLE TACTILE ET MANETTE, les deux, complets. L'owner n'a pas adb : tout doit être atteignable
   au doigt sur le téléphone. Pas de fonction accessible seulement par setprop.
6. Le navigateur est un mode DEBUG : il ne doit rien coûter ni rien changer quand il est éteint, et
   ne doit pas fuir dans un build de sortie. Mais il doit être ACCESSIBLE SANS ADB dans les builds
   de test, comme le damier.

## GARDE-FOUS
* Aucune régression de rendu : le chemin normal doit être inchangé quand le navigateur est fermé.
* Ne touche pas aux lois de displacement : cette phase OBSERVE, elle ne corrige pas.
* Mets à jour .autoport/menu-tree.md (règle owner permanente sur toute entrée de menu).
* Mesure visuelle in-game toujours interdite pour l'agent : c'est l'owner qui regarde, l'outil ne
  fait que l'amener devant le mesh.

## COMPLÉMENTS OWNER (validation du lancement en parallèle)
Owner : "Lancé en parallèle. On doit pouvoir tourner autour du mesh, le faire tourner, voir le nom du
mesh/fichier que je puisse report à toi s'il faut corriger un truc et faire varier le temps dans le
jeu pour varier les conditions d'éclairage aussi."

4 exigences supplémentaires, toutes obligatoires :
a) ORBITE LIBRE AUTOUR DU MESH — déjà au livrable 3, mais c'est confirmé comme indispensable :
   rotation complète autour, élévation, zoom, au doigt et à la manette.
b) FAIRE TOURNER LE MESH LUI-MÊME, indépendamment de la caméra. C'est différent de l'orbite : ça
   change l'orientation de l'objet par rapport à la lumière et par rapport au regard, donc ça révèle
   les défauts qui dépendent de l'angle (le "displacement qui s'étale à plat", l'orbite des motifs).
   Un mesh qu'on peut tourner sous une lumière fixe est le test le plus dur pour un displacement.
c) AFFICHER LE NOM identifiant du mesh À L'ÉCRAN, et de façon UTILISABLE POUR UN RAPPORT : nom du
   matériau, nom du niveau, identifiant de mesh/shell, et le fichier source dont il vient. L'owner
   doit pouvoir lire ça et me le citer tel quel pour qu'on cible une correction. Prévoyez que ce
   soit lisible sur un écran de téléphone. Si un moyen simple de l'exporter (fichier dans files/,
   comme asset_route.txt) est possible, faites-le : l'owner n'a pas adb et recopier à la main un
   identifiant long est pénible.
d) FAIRE VARIER L'HEURE DU JEU depuis l'écran, pour changer les conditions d'éclairage sans quitter
   le navigateur : heure fixée librement, et bascule jour/nuit rapide. Le PBR se comporte
   différemment à l'ombre et de nuit — l'owner l'a signalé plusieurs fois ("à l'ombre c'est
   toujours plat", "le PBR est complètement invisible la nuit") — donc pouvoir balayer l'heure sur
   un mesh donné est une condition de test de premier ordre, pas un gadget.

## CONTRAINTE D'EXÉCUTION (phase menée EN PARALLÈLE du round PBR)
Le round PBR en cours utilise le Redmi. Cette phase NE PREND PAS LE DEVICE : itère sur le build
DESKTOP (build/gk) pour toute la mise au point, et câble le tactile + la manette sans les valider sur
appareil. Le superviseur fera la validation device et la livraison de l'APK quand le round PBR aura
libéré le téléphone. Toute tentative de prendre le device en parallèle casserait le round PBR.

--------------------------------------------------------------------------------
CONDITION DE LIVRAISON (owner) — LE NAVIGATEUR PART AVEC LES CORRECTIONS, ET TOUS LES NIVEAUX
--------------------------------------------------------------------------------
Owner : "faudrait que le navigateur soit inclus avec les corrections de tous les mesh pour que ce
soit pertinent que je puisse tout prévisualiser hein !"

Deux conséquences fermes :
1. PAS DE LIVRAISON DU NAVIGATEUR SEUL sur un arbre en milieu de round. Il part dans le MÊME APK que
   les corrections d'orientation/displacement, sinon l'owner parcourrait des mesh encore fautifs et
   son balayage ne prouverait rien. Le garde-fou de fraîcheur du packaging impose déjà ce couplage
   (il refuse un pack dont les données cuites sont plus anciennes que la logique de bake) : la règle
   owner et le garde-fou disent la même chose, on ne contourne ni l'un ni l'autre.
2. L'INDEX DOIT COUVRIR TOUS LES NIVEAUX, pas seulement village1. "Tout prévisualiser" veut dire les
   26 niveaux de jak1. La génération est mécanique (le même outil, une passe par niveau) : il n'y a
   aucune raison de livrer un navigateur qui ne montre qu'un niveau sur 26. Chiffre le poids total de
   l'index et embarque-le dans l'APK comme le reste du dérivé.

--------------------------------------------------------------------------------
OWNER 2026-07-29 — LE NAVIGATEUR N'EST PAS UTILISABLE AU TACTILE
--------------------------------------------------------------------------------
Owner : "C'est impossible à parcourir via le tactile (le mesh browser)"

C'était une exigence explicite dès la demande initiale ("totalement contrôlable au tactile sur
mobile et à la manette"), et le gate la réclamait — mais il se contentait du mot "touch" dans le
rapport, ce qui ne prouve rien. Le navigateur est donc livré inutilisable sur le seul appareil où
l'owner s'en sert : il n'a PAS de manette branchée en permanence, et PAS d'adb.

CE QU'IL FAUT, concrètement, au doigt et sans aucune manette :
1. FAIRE DÉFILER la liste des mesh : glissement vertical, avec inertie, et une poignée de
   défilement utilisable quand la liste fait des milliers d'entrées (village1 en a 3613 — parcourir
   ça d'un cran à la fois est inutilisable par construction).
2. SÉLECTIONNER un mesh en le touchant directement, pas en amenant un curseur dessus.
3. NAVIGUER dans la vue 3D : glisser pour orbiter, pincer pour zoomer, et un geste distinct pour
   l'élévation. Ce sont les gestes que tout le monde attend ; ne réinvente rien.
4. TOUTES LES BASCULES atteignables au doigt : damier/texture, tessellation/parallax/aucun, relief,
   heure du jour. Aucune fonction ne doit exiger une manette.
5. SORTIR du navigateur au doigt.

PREUVE EXIGÉE, et le gate sera durci en conséquence : ce n'est plus le mot "touch" dans le rapport,
c'est la démonstration que des ÉVÉNEMENTS TACTILES pilotent réellement chaque action — par exemple
en injectant des gestes (input swipe / input tap) sur le device et en montrant que l'état du
navigateur change (mesh sélectionné différent, caméra déplacée, bascule commutée). Une capture
d'écran ne prouve rien ici ; c'est l'ENCHAÎNEMENT geste -> changement d'état qui compte.

RAPPEL DE MÉTHODE, appris à mes dépens sur ce projet : "la fonctionnalité est dans le code" et
"la fonctionnalité marche sur l'appareil" sont deux choses différentes, et seule la seconde compte.

--------------------------------------------------------------------------------
OWNER 2026-07-29 — CE N'EST PAS UN WARP DU JOUEUR, C'EST UNE CAMÉRA LIBRE
--------------------------------------------------------------------------------
Owner : "J'ai l'impression que le warp to model warp toujours au même endroit, et warp le joueur,
mais même pas au bon endroit du coup... Moi je voulais pouvoir tourner en free cam autour dudit mesh
(origine au centre du modèle) pour pouvoir le voir sous toutes les coutures"

L'implémentation actuelle TÉLÉPORTE JAK, et apparemment toujours au même endroit. C'est une mauvaise
lecture de la demande, et c'est inutilisable : le joueur atterrit où le sol le permet, pas où le mesh
se trouve, et on ne peut pas faire le tour d'un objet en marchant autour — un toit, une corniche, une
face sous un surplomb sont inaccessibles à pied. Or c'est précisément ces surfaces-là que l'owner doit
inspecter, ce sont elles qui portent les défauts.

CE QU'IL FAUT :
1. UNE CAMÉRA LIBRE, DÉTACHÉE DU JOUEUR. Sélectionner un mesh ne doit PAS déplacer Jak. Le personnage
   reste où il est ; c'est la CAMÉRA qui va au mesh. À la sortie du navigateur, elle revient au
   joueur et le jeu reprend normalement.
2. L'ORIGINE DE L'ORBITE EST LE CENTRE DU MESH — son centroïde, celui que l'index contient déjà pour
   chaque entrée. La caméra tourne AUTOUR de ce point, elle ne pivote pas sur elle-même.
3. DISTANCE INITIALE DÉDUITE DE LA BOÎTE ENGLOBANTE, pour que le mesh remplisse l'écran quelle que
   soit sa taille — un poteau et une falaise doivent tous deux être cadrés correctement.
4. TOUR COMPLET : azimut sur 360°, élévation du dessous au dessus (y compris à la verticale, pour
   voir la face inférieure d'un surplomb), zoom libre. "Sous toutes les coutures" est la spécification.
5. LE NIVEAU DOIT ÊTRE CHARGÉ, évidemment : si le mesh appartient à un autre niveau que le niveau
   courant, il faut y aller — mais c'est un changement de niveau + placement de CAMÉRA, pas un warp
   du joueur à un point de spawn.
6. VÉRIFIER QUE ÇA VISE JUSTE : l'owner dit que ça warp "toujours au même endroit". Prouve, sur au
   moins 5 mesh de centroïdes très différents (dont un toit, une falaise, un objet minuscule), que la
   caméra se retrouve effectivement CENTRÉE sur chacun — en comparant la position de caméra obtenue
   au centroïde attendu de l'index. Un écart constant entre les cinq trahirait un point fixe.

================================================================================
V2 — REFONTE OWNER (2026-07-30) : FREECAM + RÉTICULE, LA LISTE EST ABANDONNÉE COMME UI PRINCIPALE
================================================================================
Owner, mot pour mot :
  "C'est vraiment pas intuitif le mesh browser... On devrait plutôt avoir un bouton (genre L3 ou R3
   du gamepad et un bouton en overlay UI) qui nous passe en freecam (plus du tout lié à Jak) avec le
   viseur première personne qu'on puisse contrôler intégralement à la manette (left stick to move in
   all directions including air, right stick or current touch area to control camera), R1/R2 pour
   target un modèle (montre son nom en plain text) avec possibilité via L1/L2 de le toggle on/off
   (montrer/cacher) ou de le passer en damier tesselation via... Square ? Beaucoup beaucoup plus
   simple pour identifier et remonter les problèmes. Le mesh browser actuel est à chier, ce serait
   bien mieux ! Par contre le mesh browser actuel le toggle on/off du checker tesselation marche pas
   du tout, si on implémente ça, faut le faire bien. Idem pour le toggle on off du modèle, et via
   Circle on devrait pouvoir mettre en lumière les orientations des normales avec des gizmos qui
   montrent bien (toggle on/off) et bien sûr on doit pouvoir defocus via triangle par ex."

DEUX BUGS CONSTATÉS DANS LE BUILD ACTUEL, à corriger dans la refonte et à prouver :
  * le toggle damier-tessellation NE FAIT RIEN ;
  * le toggle montrer/cacher du modèle NE FAIT RIEN.
Un toggle qui ne fait rien est pire qu'absent. La preuve exigée pour chacun est un CHANGEMENT D'ÉTAT
RUNTIME OBSERVABLE (voir plus bas), jamais un menu qui s'anime.

LA SPEC V2, FIDÈLE AU MESSAGE :
1. ENTRÉE/SORTIE DU MODE : L3 ou R3 (au choix, documenté) + UN BOUTON dans l'overlay tactile.
   Le mode détache TOTALEMENT la caméra de Jak (le jeu continue, Jak reste où il est) et affiche un
   VISEUR première personne au centre de l'écran.
2. DÉPLACEMENT : stick gauche = translation dans TOUTES les directions, y compris monter/descendre
   dans les airs (vol libre). Stick droit = orientation caméra. Au tactile : la zone caméra
   existante pilote l'orientation, et l'overlay virtuel fournit les sticks/boutons (il existe déjà —
   phases Gtouch-controls). Tout doit être faisable sans adb et sans manette.
3. CIBLAGE : R1/R2 ciblent le modèle sous le viseur (R1/R2 = choix précédent/suivant si plusieurs
   candidats sur le rayon, sinon simple pick). Le NOM du mesh s'affiche EN CLAIR à l'écran
   (matériau + niveau + identifiant, celui de l'index), et reste exporté dans files/ pour que
   l'owner puisse le citer.
4. ACTIONS SUR LA CIBLE :
   * L1/L2 : montrer/cacher le modèle ciblé ;
   * Square : basculer le modèle ciblé en damier tessellation (le vrai matériau de debug) ;
   * Circle : GIZMOS DE NORMALES sur le modèle ciblé — des flèches par face/vertex qui montrent
     clairement l'orientation, toggle on/off. C'est l'outil rêvé pour les défauts d'orientation
     qu'on chasse depuis des jours : l'owner pourra VOIR une normale rentrante.
   * Triangle : defocus (déselectionne la cible, les toggles de cible redeviennent inertes).
5. LA LISTE ACTUELLE N'EST PLUS L'UI PRINCIPALE. Elle peut survivre en écran secondaire (elle sait
   sauter vers un mesh lointain), mais le livrable de la phase est le mode freecam+réticule.

PREUVES EXIGÉES (le validator les vérifie, mesure visuelle in-game toujours interdite) :
  * ENTRÉE INJECTÉE -> ÉTAT : chaque action (entrée freecam, vol, ciblage, chaque toggle, defocus)
    prouvée par une injection (cpad_inject pour la manette — le harnais existe, tokens l3/r3/r1/l1/
    square/circle/triangle — et input tap/swipe pour l'overlay) suivie d'un CHANGEMENT D'ÉTAT écrit
    dans un fichier de diag (files/…), pas d'une capture. Exemples d'états observables : position
    caméra qui bouge (vol), identifiant de cible non nul (pick), compteur de draws du mesh qui tombe
    à zéro (hide), flag matériau damier du draw ciblé (Square), compteur de gizmos rendus (Circle),
    cible redevenue nulle (Triangle).
  * LES DEUX TOGGLES AUJOURD'HUI MORTS (hide et damier) doivent chacun montrer l'aller ET le retour
    (on -> off -> on) dans le fichier d'état.
  * PICK CORRECT : sur >=5 mesh de centroïdes très différents, viser le mesh au réticule et vérifier
    que l'identifiant ciblé est le bon (rayon caméra vs bbox de l'index). Réutilise la preuve
    centroïdes du round précédent.
  * menu-tree.md à jour (nouvelle entrée/le bouton overlay), et tout atteignable sans adb.
NOTE : le "gap rotation du mesh" documenté au round précédent devient SANS OBJET — en freecam on
vole autour du modèle, ce qui couvre le besoin "le voir sous toutes les coutures" mieux qu'une
rotation d'objet.

--------------------------------------------------------------------------------
OWNER 2026-07-30 — PLACEMENT DU BOUTON FREECAM DANS L'OVERLAY TACTILE
--------------------------------------------------------------------------------
Owner : "La place du bouton freecam à côté de start et select je dirais"

Le bouton overlay d'entrée/sortie freecam se place DANS LE GROUPE START/SELECT de l'overlay tactile
existant — même zone, même taille et style que ces deux boutons, pour qu'il soit trouvable sans
réfléchir. Pas ailleurs à l'écran, pas flottant. Étiquette courte et lisible (ex. "CAM"). Documente
son emplacement dans menu-tree.md (section overlay) comme toute entrée d'UI.

================================================================================
V2.1 — RETOUR OWNER (2026-07-30) : AXES INVERSÉS, ET TOUS LES TOGGLES CIBLE SONT MORTS
================================================================================
Owner, mot pour mot : "Left/Right Up/Down/Pan left/Pan Right sont inversés. Cacher/Montrer le mesh
ne fonctionne pas, passer en mode damier tesselation fonctionne pas, montrer les Gizmos fonctionne
pas, activer/désactiver le relief fonctionne pas."

LEÇON SUR LA PREUVE, à graver : le round précédent a "prouvé" les toggles par le basculement de
VARIABLES (on->off->on dans un fichier d'état). L'owner constate zéro effet à l'écran. Une variable
qui bascule pendant que le renderer ne la lit jamais est exactement ce que ce genre de preuve ne
peut pas distinguer. LA PREUVE DOIT DÉSORMAIS ÊTRE CÔTÉ RENDU : des compteurs écrits PAR LE
RENDERER lui-même, par frame, montrant ce qui a réellement été soumis au GPU.

1. AXES : left/right, up/down ET pan gauche/droite sont inversés. Convention attendue, standard FPS:
   stick gauche vers la droite = la caméra TRANSLATE vers sa droite ; stick droit vers la droite =
   la caméra TOURNE vers la droite ; haut = avant/monter selon l'axe. Corrige les signes, documente
   la convention dans le rapport, et prouve-la : injection d'un input +X -> le yaw/position delta
   loggé a le signe attendu, pour CHACUN des 4 axes incriminés.
2. TOGGLES — preuve au niveau du RENDERER, pour chacun :
   * CACHER (L1/L2) : compteur de draws réellement soumis pour le mesh ciblé, écrit par le code de
     rendu par frame -> N>0 visible, 0 caché, N>0 re-montré. Si le compteur ne tombe pas à zéro,
     c'est que le flag n'est pas consommé sur le chemin de draw — trouve OÙ le draw est émis et
     applique le flag LÀ.
   * DAMIER (Square) : compteur de binds du matériau damier sur les draws du mesh ciblé -> 0 puis
     >0 puis 0. Le damier PbrTestPattern existe et marche globalement ; ici c'est le ciblage
     PAR MESH qui doit être branché sur le chemin de bind.
   * GIZMOS (Circle) : compteur de primitives gizmo réellement dessinées -> 0 / >0 / 0. Si le
     renderer de gizmos n'existe pas encore côté draw, C'EST le travail : des flèches de normales
     visibles, pas un flag.
   * RELIEF : idem — la valeur effectivement poussée à l'uniform du shader pour les draws du mesh,
     pas la variable de menu.
3. Ces compteurs de rendu rejoignent le fichier de diag existant (files/…), lus après injection —
   la boucle injection -> compteur RENDU est la nouvelle définition de "ça marche".
4. Le vol lui-même fonctionne (l'owner a volé) : ne touche pas à ce qui marche, corrige les signes.
