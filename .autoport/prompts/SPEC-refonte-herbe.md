# SPEC — refonte de l'herbe 3D

Contrat de la campagne `grass-*`. Chaque item de la campagne cite les sections qui le concernent
dans ses `notes`. Ce document fait foi ; un item ne le contredit jamais.

Investigation complete, lisible par l'owner :
https://claude.ai/code/artifact/47d25dae-00d2-497a-9e03-a21390359968

Valide par l'owner le 2026-09-12 : « je valide la refonte de l'herbe tu peux passer a la suite ».

---

## 0. CE QUI EST DEJA ACQUIS ET NE SE ROUVRE PAS

Cinq items portent le feu vert de l'owner. Aucun item de cette campagne ne rouvre leur surface, et
aucun ne doit les remettre dans sa liste de test.

* `recharged-grass-poc` — le placement, le rendu, le contact. « At last, c'est tout bon ! Valide ! »
* `recharged-grass-precompute-mode` — le `.grassbake`. Chargement 12 s -> 84 ms.
* `recharged-grass-object-clip` — l'exclusion des objets poses au sol. « TERMINE », 2026-09-11.
* `grass-crash` — le plantage. « Herbe: Valide, ca fonctionne bien ».
* `grass-density-presets` — les cinq paliers. « Les palliers d'herbe, j'ai deja valide ! »

CE QUI SURVIT TEL QUEL, et qu'aucun item n'a le droit de casser :

* Le placement barycentrique deterministe, graine par triangle, re-enumere a l'expansion.
* L'exclusion d'objets a la cuisson : sommets des draws TIE non-herbe, densifies par empreinte au
  pas de 0,35 m, testes par brin a 0,45 m dans la bande [0,05 ; 1,00] m au-dessus du sol. Les
  plateformes texturees herbe ne s'occultent pas elles-memes.
* La distinction CULL / TRAMPLE : acteurs statiques incassables caches, acteurs cassables aplatis
  donc repoussant a la casse. Clip par l'empreinte de contact au sol, jamais par le volume.
* Les correctifs Adreno 618 : deroulage a index litteral des tableaux d'uniformes (plafond 8),
  repack de `u_trample_str`, pas de `normalize(mix(...))` dans la branche brin, repli `nearf`,
  barriere `glFenceSync`. Ils sont INVISIBLES sur x86 et structurants sur l'appareil.
* La table des cinq paliers (`game/graphics/grass_density_presets.h`) est la SEULE source, lue par
  le moteur, l'outil de cuisson et l'empaqueteur. Un slug qui change casse la resolution du bake.
* Le determinisme du bake : aucun aleatoire, aucune horloge, aucun fil, `-ffp-contract=off` dans
  les trois arbres, controle de round-trip integre qui sort en 1 sur ecart.

---

## 1. LE CHIFFRE QUI COMMANDE LA CAMPAGNE

Mesure archivee, Redmi Note 9 Pro, douze courses contre deux :

    herbe ON  : 4,6 a 6,0 images/s
    herbe OFF : 20,0 a 21,1 images/s

Facteur 3,5, pour 726 851 instances. Le rapport qui livre ce chiffre le dit : « Ce cout existait
avant, il etait simplement invisible parce que le jeu mourait d'abord. »

CONSEQUENCE DE CONTRAT : aucun item d'enrichissement visuel n'est accepte avant que le cout par
image soit mesure (item 1) et que le culling existe (item 3). Un item qui ajoute de la richesse
sans cela aggrave un defaut deja inacceptable.

Second gisement, du meme ordre : 110 472 instances sur 726 851 — 15,2 % — sont la queue d'overhang,
calculee a chaque chargement, televersee au GPU, et JAMAIS dessinee puisque
`OG_FEAT_GRASS_OVERHANG` est OFF dans les deux arbres livres.

---

## 2. LA CAUSE RACINE DES ONZE ROUNDS D'OVERHANG

Le detecteur de bord declare qu'une arete ouvre sur le vide lorsqu'AUCUN AUTRE TRIANGLE TEXTURE
HERBE ne la partage (`GrassBakeCore.cpp:596-680`). Il n'existe aucun test geometrique du vide.

L'eligibilite tenant a trois noms de texture exacts, un changement de materiau — pelouse vers
terre, roche ou sable — produit exactement la meme signature qu'un vrai precipice : le triangle
voisin existe, mais il n'est pas dans la population.

Les terrasses de Sandover ont des faces de chute EN TERRE. Les rounds 1 a 4 ne posaient donc aucun
brin la ou l'owner regardait, pendant que les metriques passaient sur les zones de frange — le
round 4 est un faux vert documente. Le round 5 a bascule dans l'autre sens, placant le long des
aretes de levre quelle que soit la texture : l'owner a eu de l'herbe poussant depuis la terre.

LES DEUX REGIMES SONT FAUX PARCE QUE LA DONNEE NE DISTINGUE PAS UN BORD DE PELOUSE D'UNE FRONTIERE
DE MATERIAU. CE TEST N'A JAMAIS ETE ECRIT, DANS AUCUN DES ONZE ROUNDS.

Deja resolu et a conserver : les coutures d'UV et les frontieres de fragments, fermees au round 16
du socle par une soudure canonique a 3 cm avec sonde des 27 cellules voisines.

---

## 3. LA DONNEE QUE PERSONNE NE LIT

`goal_src/jak1/engine/collide/pat-h.gc:5-27` definit `pat-material` : stone, ice, quicksand,
waterbottom, tar, sand, wood, GRASS(=7), pcmetal, snow, deepsnow, hotcoals, lava, crwood, gravel,
DIRT(=15), metal, straw, tube, swamp, stopproj, rotate, neutral.

Ce champ est packe dans `pat-surface` (bits 6..11 = materiau, bits 3..5 = mode) et porte par CHAQUE
TRIANGLE DE COLLISION de CHAQUE `.fr3` (`common/custom_data/Tfrag3Data.h:736-748`).

`GrassBakeCore.cpp:816` lit ce champ et n'en utilise QUE le mode :

    if (((a.pat >> 3) & 0x7u) != 0) continue;   // mode 0 = sol marchable

Aucun site de `game/` ni de `common/` ne lit les bits 6..11. Le classement du sol fait par les
auteurs originaux est disponible hors ligne, par triangle, sur les 26 niveaux, et ne sert a rien.

REGLE DE CONTRAT : la classification d'une surface se fait par DEUX SOURCES INDEPENDANTES, le nom
de texture de rendu et le materiau de collision. L'accord vaut confiance. Le DESACCORD SE COMPTE ET
SE PUBLIE, il ne se devine jamais.

---

## 4. CE QUI EST PRECALCULE, CE QUI NE L'EST PAS

Frontiere actuelle, a conserver et a etendre :

AU BAKE (hors ligne) : selection des triangles, aire, graine, couleur de texture, normale de face,
normales de sommet soudees, 8 images-cles de lumiere, nombre de candidats a la densite du palier,
verdict de plancher, verdict d'occlusion, distance au rim quantifiee.

AU CHARGEMENT : re-enumeration des positions par hachage, cinq hachages par brin (hauteur, teinte,
courbure, phase, lacet), decodage du rim. 103 a 281 ms selon le palier, ASYNCHRONE, 0 ms bloques.

AUCUNE POSITION DE BRIN N'EST STOCKEE. C'est ce choix qui rend les paliers imbriques par
construction : un palier bas est le PREFIXE EXACT du tableau de candidats. IL EST CONSERVE.

INTERDIT : toute analyse statique au chargement. Detection de bord, exposition au vent, distance a
une zone nue, estimation de frequentation, classification de surface — tout cela est cuit.

A AJOUTER AU BAKE : index de chunks et bounds, identifiant de touffe et graine, distance a la zone
nue, distance au bord reel et direction sortante, exposition au vent, influence de passage, profil
de biome. Tout le reste reste DERIVE d'une graine.

---

## 5. INVALIDATION ET REBAKE

Defaut connu : l'invalidation compare la TAILLE du `.fr3` (`GrassRenderer.cpp:1032-1036`), pas une
empreinte de contenu. Un `.fr3` reconstruit a taille identique mais contenu different passe la
garde. A corriger.

Le producteur `scripts/shell/build_grass_bakes.sh` n'est appele par AUCUN script de build : la
cuisson est manuelle et recuit tout a chaque appel. A corriger : declenchement automatique et
rebake cible par niveau et par categorie de donnees.

---

## 6. BRINS, TOUFFES, BIOMES

GEOMETRIE : quatre a six variantes simples, toutes generees depuis `gl_VertexID` comme aujourd'hui,
aucun asset de maillage. Elles different par le nombre de segments, le profil de largeur et la
courbure de base. Le palier le plus bas n'en utilise qu'une, le plus haut les six.

HORS PERIMETRE, ORDRE DE L'OWNER : la modelisation de vegetaux complexes. Pas de fleurs, pas de
fougeres, pas de plantes detaillees. La diversite vient de brins simples, de leur regroupement, de
leur shading, de leurs parametres et de leur distribution.

TOUFFE : un point d'origine cuit, une graine, un rayon, un compte de brins de 3 a 9 selon le
palier, une composition tiree des proportions du profil. Les brins d'une touffe partagent une part
de leur phase de vent et de leur reponse a l'interaction, avec une dispersion controlee.

Etat actuel a corriger : il n'existe AUCUNE touffe. Le placement est un tirage barycentrique
uniforme par triangle. Le mot « tuft » du code designe une decoupe de fragment a l'interieur d'une
carte, et `D_TARGET = 150 tufts/m^2` est un abus de langage pour brins/m^2.

BIOME : un profil par niveau et par sous-zone, nommant les proportions de variantes, les plages de
hauteur, la palette de degrade, la raideur au vent et le comportement de bord.

---

## 7. COULEUR ET SHADING

Etat actuel : le degrade racine-pointe existe et il est correct. Ce qui manque est la variation
spatiale. `inst_gcol` n'est PAS un echantillonnage du terrain sous le brin : c'est la moyenne de la
TEXTURE ENTIERE du draw source, mise en cache par identifiant. Avec trois noms admis, il existe au
plus TROIS couleurs de sol dans tout le champ, et UNE seule en pratique sur Geyser Rock. Le
commentaire de `grass.vert:462-468` qui annonce « per-location » est FAUX.

La seule variation spatiale reelle est `inst_light`, la lumiere cuite du centroide du TRIANGLE :
11 080 valeurs pour 847 000 brins.

A ajouter, sans cout geometrique : une teinte par TOUFFE en plus de la teinte par brin ; un
assombrissement de base proportionnel a la densite locale ; une differenciation face eclairee /
face opposee par la normale du brin dans le plan. Et porter la lumiere cuite a une valeur par
touffe plutot que par triangle.

Direction artistique : stylisee, coherente avec Jak and Daxter. Pas de photorealisme.

---

## 8. VENT

Etat actuel : UN SEUL SINUS a 1,7 rad/s = 0,271 Hz (`grass.vert:256,284`). Propagation spatiale
reelle mais courte, 4,38 m de longueur d'onde. AUCUNE rafale. AUCUNE DIRECTION DE VENT : chaque
brin oscille le long de son propre `fwdv`, donc de son lacet aleatoire. Le champ n'a pas de cap.

CE QUI EST REPRIS du modele de feuillage (`shaders/breeze.glsl`) : la CHARPENTE TEMPORELLE.
Plusieurs bandes de frequence, un cap commun qui derive lentement, un front de rafale traversant.

CE QUI N'EST PAS REPRIS, ORDRE DE L'OWNER DU 2026-09-12 : « le shader breeze.glsl est tres peu
satisfaisant aussi, tres rigide, pas ouf du tout, donc attention ». L'item `foliage-wind` porte
DEUX REFUS COMPLETS (03/09 et 04/09). Sa loi de flexion fait PIVOTER l'element autour d'un point
d'ancrage : c'est le mouvement d'un objet dur qui tourne.

LOI EXIGEE POUR L'HERBE : un brin SE COURBE, il ne pivote pas. La deflexion s'accumule le long de
la tige, quasi nulle a la racine, maximale a la pointe, et LA POINTE RETARDE SUR LA BASE. Le shader
d'herbe a deja la courbure et une flexion en `t*t` : le squelette est bon, il lui manque la reponse
temporelle et le retard de pointe.

EXPOSITION : un scalaire par touffe, cuit, obtenu par lancer de quelques rayons courts dans le plan
depuis le sommet de la touffe. Le runtime MULTIPLIE, il n'analyse jamais la geometrie environnante.

RISQUE A MESURER : `grass_occ::publish()` est partage avec `foliage-wind`, item ouvert et deja au
bord du rejet definitif. Partager du code avec lui est un risque, pas une economie evidente.

---

## 9. PLACEMENT, EXCLUSIONS, CHEMINS, BORDS

Quatre questions, dans cet ordre, pour chaque candidat :

1. Cette surface porte-t-elle de l'herbe ? Croisement texture + materiau (section 3).
2. Un objet la recouvre-t-il ? Mecanisme actuel, reconduit sans changement (section 0).
3. A quelle distance de la zone nue la plus proche ? Transformee de distance, qui pilote densite
   et hauteur.
4. A quelle distance du bord REEL, et dans quelle direction ? Le bord est etabli par SONDE DE
   PLANCHER vers l'exterieur — une question geometrique — jamais par absence de voisin texture.

Chaque racine porte l'identifiant de son triangle support. Une racine dont le support ne contient
pas sa position est un DEFAUT COMPTE : la classe d'erreur « brin flottant » devient impossible a
livrer sans qu'une porte la voie.

TRANSITIONS : jamais binaires. Reduction progressive de densite et de hauteur, irregularite du bord
par bruit coherent. Ne pas laisser de bande vide entre le dernier brin et la limite du chemin : le
correctif d'epaule existe deja au socle (une arete partagee avec une levre rejetee est traitee
comme INTERIEURE) et doit etre generalise. Le chemin reste degage, les collectibles lisibles.

MESHES SUPERPOSES : un triangle de collision de materiau `grass` recouvert d'un triangle de rendu
texture sable ou terre EST une zone d'exclusion posee par-dessus. Deux sources qui ne se copient
pas. Statut actuel : INDETERMINE, aucune mesure ne le confirme ni ne l'infirme.

---

## 10. CHUNKING, CULLING, LOD

Etat actuel : DEUX appels de dessin, AUCUN frustum, AUCUN chunk au dessin. Le vertex shader
s'execute pour les 727 000 instances a chaque image ; les hors-portee sont repliees sur un point
degenere. Aucun dithering, aucune hysteresis. Les seuls « chunks » sont instrumentaux.

CIBLE : grille XZ dont la taille se derive de la densite pour viser un nombre d'instances par chunk
a peu pres constant, bounds cuits. Une touffe traversant une frontiere appartient au chunk de son
ORIGINE — aucune duplication. Culling par distance, puis frustum, puis hierarchie de bounds. Un
appel de dessin par lot de chunks contigus visibles.

LOD : quatre niveaux par DECIMATION DE PREFIXE, le meme mecanisme que les paliers de densite, donc
aucune redistribution. Transitions par fondu croise sur une plage, avec hysteresis sur le seuil.

REGLE DE CONTRAT : un changement de preset ne redistribue JAMAIS l'herbe. Les memes touffes restent
aux memes positions. Un preset inferieur simplifie, regroupe ou masque ; il ne retire pas au hasard.

---

## 11. INTERACTIONS

Etat actuel, a conserver : Jak, une trainee de 4 echantillons espaces de 0,15 s decroissant sur
0,6 s, la prise de rebord, 8 acteurs ecrasables et 8 acteurs occultants, montee 0,25 s, descente
0,6 s, pierres tombales 8 s, duree de vie adaptative a la cadence. Positions publiees depuis GOAL
(`pc-grass-occ-*`), pas depuis Merc2, dont le chemin est mort.

CE QUI MANQUE : la DIRECTION. Le deplacement est connu par la trainee et n'est jamais utilise comme
vecteur. La forme reste un disque.

CIBLE : flexion orientee dans la direction du mouvement, glissement lateral proportionnel a la
distance au centre du contact, memoire du vecteur. La loi radiale actuelle devient le repli des
paliers bas. La fidelite est limitee spatialement : les touffes lointaines ne paient pas le cout
maximal.

---

## 12. PASSAGE ET CARTES DE CROISSANCE

Donnees reellement disponibles hors ligne : 1 233 orbes posees, 26 cellules posees et 28 declarees,
110 mouches eclaireuses portees par des caisses, 553 acteurs portant un champ `path` (points de
controle), la collision complete par triangle, et la praticabilite par `pat.mode == 0`.

NON DISPONIBLE : le maillage de navigation. Le champ existe dans la structure d'acteur
(`decompiler/level_extractor/BspHeader.h:167`) mais `extract_actors.cpp:97` ne l'exporte pas —
seules des REFERENCES le sont (494 `nav-mesh-actor`). Ne pas le supposer disponible.

CIBLE : une carte de frequentation cuite, combinant par UNION PROBABILISTE des taches irregulieres
autour des collectibles, des couloirs le long des trajectoires, une transformee de distance depuis
les entrees et sorties de zone, et un bruit coherent. Jamais un masque binaire. Un plancher de
lisibilite garantit que l'herbe ne masque jamais un collectible.

CE TRAVAIL RECOUVRE LE SPIKE DE L'OWNER DU 12/07 : `.autoport/prompts/phase-Grecharged-grass-wear.md`
(11 274 o), qui contient deja l'architecture en quatre couches et QUATORZE criteres d'acceptation.
Il se reprend, il ne se refait pas.

---

## 13. REGLAGES ET PRESETS

A conserver : la table des cinq paliers et son unicite, les deux distances (`near`, `card`),
l'interrupteur principal.

A ajouter : un palier de qualite global pilotant les axes de la matrice ci-dessous, chaque axe
restant ecrasable en mode avance. MEME FORME que `lighting-presets` et `water-presets` — l'herbe s'y
conforme, elle n'invente pas sa propre echelle.

A retirer : le mode precalcule comme reglage. Le chemin en direct n'est plus un repli, il coute
1 436 ms contre 220, et il n'est atteignable que par un fichier de configuration. Sa seule valeur
est d'etre une jambe de mesure.

Matrice des axes (valeurs provisoires, a confirmer par mesure) :

    axe                  tres bas   bas    moyen   haut   ultra
    densite (brins/m2)      15       30      45      60     75+
    distance brins          12 m     20 m    30 m    45 m   70 m
    variantes de brin        1        2       4       6      6
    brins par touffe         3        4       5       7      9
    composantes de vent      1        3       6      10     10
    interacteurs             2        4       8      16     16
    overhang                non      non   silhouette complet complet
    lointain             texture  texture  cartes  cartes cartes

---

## 14. VALIDATION

Chaque item porte UNE grandeur, publiee par le moteur, jugee par une porte. Familles exigees :

* Determinisme : deux cuissons identiques au bit ; deux chargements, memes positions.
* Integrite des racines : compte de racines hors de leur triangle support declare = 0.
* Orientation : compte de brins dont la normale de base pointe vers le bas = 0.
* Bords : sur des vantages NOMMES couvrant coins convexes, coins concaves, plateformes etroites et
  surfaces empilees, compte de brins sans plancher sous leur racine = 0.
* Transitions : largeur de la bande nue sous plafond declare ; compte de brins sur le chemin = 0.
* Stabilite de LOD : compte de changements de representation sur une traversee de seuil aller-retour,
  borne par l'hysteresis.
* Neutralite : chaque option eteinte rend une image IDENTIQUE AU BIT a un binaire-temoin ou la
  couche n'est pas COMPILEE.
* Performance : temps par image sur l'appareil, ON et OFF, par palier, a un vantage fixe.

VUES DE DEBUG exigees, affichables separement : eligibilite, surface support, materiau de collision,
desaccord entre les deux sources, distance a la zone nue, distance au bord, direction de retombee,
identifiant de touffe, variante, profil de biome, exposition au vent, influence de passage, chunk,
niveau de detail actif, raison de rejet.

---

## 15. DEPLOIEMENT

Geyser Rock seul ne suffit pas comme pilote : il n'a ni chemin traversant, ni biome multiple, ni
falaise franche. Trois zones pilotes complementaires :

* `training` (Geyser Rock) — la reference de non-regression, seul niveau cuit et valide.
* `village1` (Sandover) — terrasses a faces de chute EN TERRE, c'est-a-dire le cas exact qui a fait
  echouer onze rounds, plus des chemins traversants.
* `jungle` — deux textures d'overhang dont une longue, une texture de chemin listee parmi les sols
  herbeux, et un biome franchement different.

Dix niveaux portent des textures de sol herbeux : training, beach, village1, village2, jungle,
rolling, ogre, swamp, finalboss, firecanyon. Un seul a de l'herbe aujourd'hui
(`background_common.h:110`, `kGrassLevels[] = {"training"}`).

Chaque ajout de niveau est un changement de DONNEES, pas de code, une fois le socle en place. Le
repli est immediat : retirer un niveau de la liste le ramene a son rendu d'origine.

---

## 16. CE QUI N'EST PAS DANS CETTE CAMPAGNE

L'OVERHANG. L'owner a precise le 2026-09-12 : « sur le hang, j'ai parke parce que c'etait pas bon,
donc attention ». Le parcage du 2026-07-15 est un VERDICT DE QUALITE, pas un report de file.

Aucun item de cette campagne ne le rouvre. La correction de l'oracle de bord (section 9) rend un
douzieme round POSSIBLE, elle ne le declenche pas. Et corriger l'oracle ne repond pas a la question
de la PRIMITIVE : quatre ont ete rejetees de pres — plaques de couleur unie, ficelles, mousse,
cartes texturees — et la lecon ecrite au parcage est qu'un quad de couleur unie ne se lit jamais
comme de l'herbe a cette resolution. Le repli honnete, si la primitive echoue encore, est de garder
la bande peinte d'origine et de la rendre en deux ou trois couches de parallaxe animees.

DECISION DU SUPERVISEUR, 2026-09-12, sur delegation de l'owner (« ce qui attend ma decision sur
l'herbe, tranche pour moi »).

**L'overhang ne fait pas partie de cette campagne, et il n'y entrera pas de lui-meme.** Raisons,
dans l'ordre de poids :

1. Onze rounds, aucun accepte, et un parcage prononce sur la QUALITE.
2. Quatre primitives rejetees a distance de jugement — plaques de couleur unie, ficelles, mousse,
   cartes texturees. La lecon ecrite au parcage est qu'un quad de couleur unie ne se lit JAMAIS
   comme de l'herbe sur ce moteur a cette resolution. Corriger l'oracle de bord repond a la question
   « ou poser des brins », pas a la question « a quoi doit ressembler un brin la-bas ».
3. Les quatorze items de la campagne livrent tous quelque chose que l'owner peut voir. Un
   quinzieme, avec cet historique et cette question ouverte, serait le pari le moins probable du lot.

**CE QUI LE FERAIT REVENIR, ET SOUS QUELLE FORME.** Quand `grass-surface-truth`,
`grass-path-transitions` et `grass-clumps` sont valides par l'owner, la donnee de bord est juste et
il existe enfin des touffes a faire retomber. Le premier geste ne sera alors PAS des brins : ce sera
le repli que le journal de parcage nomme lui-meme — garder la bande peinte d'origine et la rendre
en deux ou trois couches de parallaxe animees. C'est bon marche, ce n'est aucune des quatre
primitives rejetees, et cela se juge en un regard.

Un item d'overhang ne sera propose qu'a ce moment-la, et avec un accord explicite de l'owner.
