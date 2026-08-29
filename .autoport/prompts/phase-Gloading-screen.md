# Gloading-screen — un ecran de chargement au lieu d'un ecran noir

## APPAREILS — CONTRAINTE ABSOLUE (owner 2026-08-28, 23h)

**LA SHIELD EST INTERDITE.** C'est la television de l'owner, dans son salon. Le 2026-08-28 un de
mes criteres de validation a envoye le framework y lancer le jeu sans son accord ; il l'a tolere
« car je suis seul ce soir » en precisant qu'il aurait prefere que non.

**Un seul appareil autorise : le Redmi `eae4df44`.** Toute mention de la Shield dans ce document
est un CONTRE-EXEMPLE historique, jamais une instruction.

## La demande (owner 2026-08-28), maquette fournie

Maquette : `.autoport/design/loading-screen-owner-mockup.png` (16:9).

- Silhouette blanche de Jak courant lateralement vers la DROITE, Daxter sur l'epaule, **~40 % de
  la hauteur d'ecran**, centree verticalement, a GAUCHE. Capturee depuis la **vraie animation**
  de course, vue de cote, convertie en blanc sur noir.
- En bas a droite : « Loading... » **localise**, en **Urbanist**.
- Sous le texte : les glyphes precurseurs disant « Loading », **a la largeur EXACTE du texte
  localise**.

Motif de l'owner : « ça empêcherait l'utilisateur de se poser des questions quand c'est en
chargement (le jeu a crash ? pourquoi cet écran noir ?) ».

Ca repond directement aux **6,7 s d'ecran noir** mesurees sur la Shield le 2026-08-28
(`LOADGATE open scene=logo-intro waited=6763ms reason=resident`).

## Ou ca se branche

`blackout()` — `goal_src/jak1/engine/game/main.gc:61` — dessine aujourd'hui un simple rectangle
noir plein ecran.

## PIEGE MESURE — ne pas le rater

L'ecran noir ne sert PAS qu'au chargement : il sert aussi aux coupes de camera
(`pov-camera.gc:103`, 0,035 s) et aux boutons (`basebutton.gc:348`, 0,05 s). Mettre le contenu
dans `blackout()` sans condition ferait CLIGNOTER « Loading... » a chaque coupe de camera.
=> Lier a la barriere de chargement precisement, et n'afficher qu'au-dela d'un seuil (~0,5 s).

## Point d'implementation sur les glyphes

« Chargement... » est nettement plus large que « Loading... ». La ligne de glyphes doit donc etre
**mise a l'echelle par langue** sur la largeur MESUREE du texte rendu, pas dessinee a taille
fixe. Le systeme de police sait mesurer une largeur.

**Aucun alphabet precurseur n'existe dans le jeu** : les textures « precursor » sont des murs de
la citadelle. Les glyphes sont un asset a creer (8 sur la maquette).

## Dependance

Le texte doit etre en Urbanist => **depend de `Gfont-urbanist`**. Livrer d'abord le branchement
et le seuil (qui ne dependent de rien et suppriment l'angoisse), la silhouette ensuite, le texte
et les glyphes en finition.

## Ordre impose

1. Branchement + seuil (supprime l'angoisse, zero dependance).
2. Silhouette fixe capturee depuis l'animation reelle.
3. Texte localise + glyphes precurseurs, apres Urbanist.

---

# RETOUR OWNER 2026-08-29 — l'ecran manque sur le CHARGEMENT D'UNE PARTIE

> « L'écran de chargement est bien là, mais pas quand on charge une partie. »

L'ecran s'affiche donc sur le chemin qui a ete cable, et **pas sur celui que le joueur emprunte
le plus souvent** : charger une sauvegarde depuis le menu.

## A faire

1. **Enumerer TOUS les chemins qui provoquent une attente** — demarrage, chargement d'une
   sauvegarde, changement de niveau, retour de cinematique — et publier, pour chacun, s'il
   declenche l'ecran ou non. La liste est le livrable ; sans elle, on rebouchera un trou a la
   fois pendant que l'owner en trouvera d'autres.
2. Brancher les chemins manquants sur le MEME mecanisme, pas sur une copie.
3. Le seuil reste : il ne doit pas clignoter sur une coupe de camera.

**Piege deja paye deux fois sur ce projet** : un mecanisme cable sur UN chemin et declare fait.
La barriere de chargement avait le meme defaut — elle couvrait `logo-intro` et pas le retour de
Geyser Rock, et c'est l'owner qui l'a decouvert.

---

# RETOUR OWNER 2026-08-29 (2) — TROIS CHEMINS DE CHARGEMENT, ET UN DEFAUT DE FOND

> « Ça n'apparaît pas avant l'écran titre (ça devrait, j'imagine charger le niveau de l'écran
> titre avant même de montrer Jak et Daxter et le logo Naughty Dog pour éviter un chargement entre
> cette séquence et l'écran titre) et ça n'apparaît pas non plus sur le chargement de partie alors
> que l'ÉCRAN NOIR y apparaît un moment (le temps de charger le niveau de la partie chargée). »

## 1. Le tell decisif : l'ecran noir est la, le contenu non

Sur le chargement d'une partie, **l'ecran noir s'affiche bien**. Le chemin passe donc par
`blackout` ; ce qui manque, c'est le CONTENU. Ce n'est pas « un chemin non cable », c'est la
condition d'affichage qui ne se declenche pas la.

C'est mesurable sans appareil : instrumenter `blackout` pour publier, a chaque declenchement, le
chemin appelant et l'etat du seuil. **Publier la liste des declenchements observes pendant un
demarrage complet plus un chargement de partie.** Cette liste est le livrable ; sans elle on
rebouchera un trou pendant que l'owner en trouvera trois.

## 2. Avant l'ecran-titre — et une DEMANDE DE CONCEPTION, pas seulement un correctif

L'owner ne demande pas seulement d'afficher l'ecran de chargement plus tot. Il propose de
**charger le niveau du titre AVANT de jouer la sequence Jak+Daxter et le logo Naughty Dog**, pour
supprimer le chargement qui s'intercale entre cette sequence et l'ecran-titre.

Mesure existante a reutiliser : `LOADGATE open scene=logo-intro waited=6763ms reason=resident` —
la barriere attend deja ~6,7 s a cet endroit. Deplacer ce chargement AVANT la sequence rend ces
secondes invisibles au lieu de les faire attendre entre deux ecrans.

A chiffrer avant de livrer : le temps total jusqu'au titre ne doit pas AUGMENTER. Publier
avant/apres.

## 3. LES COLLECTEURS D'ECO VERT — defaut deja documente, JAMAIS CORRIGE

> « la cinématique qui se déclenche quand on retourne à la hutte du Sage vert après avoir terminé
> Geyser Rock, toujours mes soucis de chargement des collecteurs d'Eco vert (pas chargés pendant
> le fly over, pop-in) parce qu'ils sont pas dans le nouveau Sandover Village mais à Sandover
> beach qui est le niveau juste à côté ! »

**L'owner a raison sur la cause et il la nomme : les collecteurs sont dans `beach`, pas dans
`village1`.**

Analyse deja faite le 2026-08-28, rapport
`.autoport/reports/OWNER-DEFECT-barriere-ne-couvre-PAS-les-acteurs-de-beach.md` :

- La scene est `sage-intro-sequence-e` (`goal_src/jak1/levels/village1/sage.gc:109`).
- Sa command-list : `(0 want-levels village1 beach)` puis `(937 display-level beach movie)`,
  `(937 want-force-vis beach #t)`, puis `(938 alive "ecoventrock-3..7")` et
  `(938 alive "harvester-87..91")` — **les collecteurs sont les `harvester-*`, ce sont des
  ACTEURS**, pas du decor.
- Balayage statique des 179 spool-anim : la scene EST dans les 18 retenues par
  `scene-load-gate!`, elle s'arme bien sur `beach`. Le mecanisme n'est donc pas contourne.

Deux causes candidates, non tranchees faute d'avoir pu atteindre la scene :
- **plafond de 20 s trop court** (`loader.gc:722`, ecrit en dur) -> ouverture sur delai ;
- **la barriere attend la GEOMETRIE, la scene a besoin des ACTEURS** : `mark_level_resident`
  (`Loader.cpp:1462`) est publie quand le fr3 est monte sur le GPU ; rien ne prouve que les
  acteurs sont lies et instanciables.

**La ligne qui tranche, et qui n'a jamais ete capturee :**

    LOADGATE open scene=sage-intro-sequence-e waited=<N>ms reason=<resident|timeout>

`reason=timeout missing=beach` -> c'est le plafond. `reason=resident` avec une attente courte ->
c'est les acteurs.

**NE PAS relever le plafond « au cas ou »** : si la cause est les acteurs, ca allonge l'ecran noir
sans rien reparer, et le prix est paye deux fois.

---

# RETOUR OWNER 2026-08-29 (3) — TROIS DEFAUTS SUR L'ECRAN LIVRE

## 1. Glyphes precurseurs inverses — CORRIGE cote asset, a reprendre

> « les glyphs precursor sont pixellisés et certains sont inversés (fond blanc glyph noir)
> pendant que d'autres sont bons »

Cause trouvee et corrigee dans `recharged_assets/font/precursor/` : la generation devinait la
polarite PAR GLYPHE avec la regle « l'encre est minoritaire », fausse pour les formes pleines.
**E, G, H, K, M, P, S** — exactement les sept dont l'encre couvre plus de 50 % de la boite —
etaient retournes. Atlas et fichiers individuels regeneres, polarite determinee une seule fois
depuis la planche source.

**A faire ici** : reprendre l'atlas corrige. Et traiter la PIXELLISATION : les glyphes source
font ~70 px de haut ; publier la taille a laquelle ils sont rendus a l'ecran et le filtrage
applique. Un agrandissement au plus proche voisin sur 70 px donne exactement ce que l'owner
decrit.

## 2. La ligne precurseur est PLUS LARGE que le texte — l'inverse de la demande

> « le texte "Chargement..." est moins large que son pendant en Precursor, ce que je voulais
> éviter, t'as pas réussi »

La demande d'origine est sans ambiguite : **la ligne precurseur fait la largeur EXACTE du texte
localise**. La preuve `.autoport/design/precursor-proof.png` l'obtient en mesurant la largeur
rendue du texte puis en mettant la ligne a l'echelle : 210 px / 310 px / 255 px pour anglais,
francais, espagnol, avec des facteurs 0,483 / 0,554 / 0,562.

**Le rendu du jeu ne fait pas cette mise a l'echelle.** Exiger : publier, pour au moins trois
langues, la largeur rendue du texte ET la largeur rendue de la ligne precurseur. **Elles doivent
etre egales a moins de 2 px.**

## 3. La silhouette doit etre ANIMEE — j'avais sous-specifie, c'est ma faute

> « la silhouette de Jak and Daxter en train de courir latéralement vers la droite... bah c'est
> pas animé ! J'avais explicitement demandé de capturer cette animation in game (mets un fond vert
> ou whatever) en haute résolution pour ensuite en faire une séquence d'images animées en haute
> définition où toute l'image extraite du fond vert est transformée en blanc plein (silhouette). »

Le brief initial disait « je propose une image fixe d'abord, une boucle animee est une extension
naturelle ». **C'etait une reduction de perimetre que l'owner n'avait pas demandee.** Sa demande
du 2026-08-28 disait deja « vraie animation, capturee d'une certaine facon in-game ».

**Le livrable est une SEQUENCE ANIMEE**, produite ainsi :
1. Capturer l'animation de course reelle en jeu, vue de cote, **sur fond uni contraste** (vert ou
   equivalent), en haute resolution.
2. Extraire le sujet du fond et le convertir en **blanc plein** — silhouette, pas un detourage
   avec des degrades de couleur.
3. En faire une sequence d'images, jouee en boucle.

Publier : nombre d'images, resolution, et la duree de la boucle.

---

# RETOUR OWNER 2026-08-29 (4) — LA SILHOUETTE LIVREE A CINQ DEFAUTS

> « Déjà c'est pas l'animation où Jak court vu de côté du tout, c'est plus de la marche... Et en
> plus la silhouette animée a l'air d'aller vers la gauche au lieu de la droite (et prise avec un
> angle bizarre) en plus de mal boucler et freeze par moment (quand ça charge des gros trucs je
> suppose) ça devrait être fluide ! »

Cinq defauts, tous a corriger. Le dernier est le plus grave.

## 1. Ce n'est pas la bonne animation
C'est de la MARCHE, pas de la COURSE. Il faut l'animation de course. **Publier le nom de
l'animation capturee** — pas « une animation de deplacement », son nom.

## 2. Le sens est inverse
Elle va vers la GAUCHE, la maquette de l'owner montre une course vers la DROITE.

## 3. L'angle de prise de vue est faux
« un angle bizarre ». La demande dit **vu de COTE**. Publier l'angle de camera utilise et
pourquoi il est de cote.

## 4. La boucle saute
Le cycle precedent avait publie un raccord a 0,0169 contre 0,0357 pour le pire depart — donc la
mesure existait et le raccord saute quand meme. **Cette metrique ne capture pas ce que l'oeil
voit.** Trouver ce qu'elle rate : un cycle de course n'est pas periodique sur une seule foulee
(gauche/droite), il l'est sur DEUX. Une boucle prise sur une demi-periode saute forcement.

## 5. ELLE SE FIGE PENDANT LES GROS CHARGEMENTS — le defaut de fond
« freeze par moment (quand ça charge des gros trucs je suppose) ça devrait être fluide »

**Une animation qui se fige pendant un chargement ne remplit plus sa fonction**, qui est
justement de montrer que le jeu n'est pas plante. C'est le defaut qui annule l'ecran entier.

Cause a chercher : l'avancement de l'animation est probablement pilote par l'horloge de LOGIQUE
du jeu, qui est ce qui se bloque pendant un chargement lourd. Il lui faut une horloge
INDEPENDANTE de la boucle de logique — la meme lecon que le seuil corrige au cycle precedent, ou
le front montant se replacait a chaque frame lente.

**Exige** : publier le nombre d'images affichees par seconde MESURE pendant un chargement lourd,
pas au repos. Une valeur mesuree au repos ne prouve rien sur le defaut signale.
