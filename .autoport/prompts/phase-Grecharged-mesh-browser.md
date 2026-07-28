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
