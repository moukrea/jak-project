# PHASE Grecharged-menu-overhaul — REFONTE COMPLÈTE DES MENUS (propal superviseur VALIDÉE par l'owner)

Owner : "les menus sont giga bordéliques, on sait même pas où chercher les infos" ; propal validée
2026-07-30 avec trois décisions : "Continuer on garde, c'est cool. Les catégories debug, on garde
mais on cache (pas supprime) dans les builds finaux (feature flag --debug pour montrer lors du
build). Les intitulés faut full support de toutes les langues supportées du jeu. Aussi faut vraiment
considérer déplacer n'importe quelle entrée de façon à ce que ce soit cohérent et fluide pour
l'utilisateur et qu'il soit pas perdu !"

## LA CIBLE (validée)

### Écran titre — conditionnel selon les sauvegardes
  Aucune sauvegarde :  Nouvelle partie / Options / Secrets / Quitter
  >=1 sauvegarde    :  CONTINUER (charge la + récente, 1 clic) / Charger une partie /
                       Nouvelle partie / Options / Secrets / Quitter
  "Charger" est CACHÉ quand il n'y a rien à charger. Le moteur sait déjà faire du conditionnel
  (Dynamic Render Scale cache/renomme ses voisines) — réutilise ce mécanisme.

### Quitter (titre ET pause)
  → [ Retour à l'écran titre | Quitter le jeu | Annuler ]   (au titre, pas de "retour titre")

### OPTIONS unifiées — 5 catégories, organisées PAR FONCTION (pas par origine)

PRINCIPE CARDINAL (owner 2026-08-01, RECADRAGE) : **on organise par FONCTION, JAMAIS par
origine.** Il est INTERDIT d'avoir une catégorie "options d'origine" d'un côté et une catégorie
"réglages Recharged" de l'autre. Les réglages Recharged sont des citoyens de PREMIÈRE CLASSE,
fondus au milieu des réglages d'origine correspondants, comme si le jeu était un VRAI remake natif
et pas un hack. Le mot "Recharged" ne sert PAS de critère de rangement. Chaque menu est cohérent,
intuitif, hiérarchique (sections → sous-sections), avec des hints — pas des listes à plat débiles.

  JOUABILITÉ   hints, sous-titres, 3 langues, auto-save

  GRAPHISMES   (UNE seule zone pour tout le rendu — l'ancien couple AFFICHAGE+RENDU est FUSIONNÉ ;
                les catégories séparées "AFFICHAGE" et "RENDU" N'EXISTENT PLUS)
     ⚙ tête    RENDU RECHARGED (MASTER) — coupe-circuit global, tout en haut de la zone
     Écran           aspect, résolution, plein écran, mode d'affichage*, moniteur*
     Performance     render scale dynamique, render scale, FPS min, V-Sync, MSAA, frame rate*
     Matériaux & détail  PBR, Relief (Off/Parallax/Tess), Specular, Textures Recharged
     Éclairage       ambient unifié, éclairage temps réel
     Végétation      herbe 3D, distances (le sous-menu Grass est DISSOUS ici)
     Interface       compteur FPS, HUD Recharged
                  * = lignes RÉTABLIES sur Android (inertes + hint "sans effet sur mobile")

  AUDIO        volumes, langue des voix
  COMMANDES    manette, caméra, souris, rebinds, overlay tactile
  DEBUG        presets PBR, isolate, damier, Freecam/Mesh Browser, gizmos

  Le sous-menu "Recharged Settings" DISPARAÎT en tant que tel ET NE réapparaît PAS déguisé en
  catégorie "RENDU" : ses réglages sont ventilés dans les sous-sections FONCTIONNELLES de
  GRAPHISMES (matériaux avec matériaux, éclairage avec éclairage, végétation avec végétation,
  textures avec l'écran/l'image). Le MASTER Recharged reste le coupe-circuit global, en tête de
  GRAPHISMES. L'outillage de mise au point va dans DEBUG.

  Ce principe FONCTION-pas-ORIGINE et la hiérarchie sections/sous-sections + hints s'appliquent à
  TOUTES les catégories, pas seulement GRAPHISMES.

## LES QUATRE MÉCANISMES UI À CONSTRUIRE
1. EN-TÊTES DE GROUPE : nouveau type de ligne non sélectionnable (saut au focus), style distinct.
2. VALEUR VISIBLE EN LIVE sur 100% des lignes : ON/OFF coloré, choix courant du carrousel,
   valeur numérique + mini-barre pour les sliders — sans ouvrir la ligne.
3. HINTS : une ligne d'aide en bas d'écran pour la ligne focalisée. Chaque option a son hint.
4. LIGNES CONDITIONNELLES : réutiliser le mécanisme existant (titre conditionnel, lignes Android).

## DÉCISIONS OWNER À RESPECTER À LA LETTRE
* ANDROID : les 3 lignes cachées (Display mode, Display/moniteur, Frame rate) REVIENNENT, même
  inertes, avec hint "(sans effet sur mobile)". Règle générale : on ne cache plus de menus sur
  Android.
* DEBUG : la catégorie existe dans TOUS les builds mais est CACHÉE par défaut dans les builds
  finaux. Nouveau flag build.sh `--debug` → defconstant FLAG_DEBUG_MENUS (+ define C++ si besoin)
  qui rend la catégorie VISIBLE. Caché ≠ supprimé : le code est toujours présent, seul l'affichage
  est conditionné. Les builds de test/damier passent --debug ; les release non.
* LANGUES : chaque nouvel intitulé/hint doit exister dans TOUTES les langues supportées du jeu
  (ENG, FRE, GER, ITA, JAP, SPA). Aucun texte anglais-seulement. Le rapport donne le compte de
  text-ids ajoutés × langues couvertes.
* LIBERTÉ DE DÉPLACEMENT TOTALE mais TRAÇABLE : n'importe quelle entrée peut bouger si c'est plus
  cohérent — le rapport DOIT contenir la table de correspondance ANCIEN EMPLACEMENT -> NOUVEAU pour
  CHAQUE ligne existante. Aucune option ne doit devenir orpheline/inatteignable ; les fusions
  délibérées sont documentées. C'est le garde-fou "l'utilisateur n'est pas perdu".

## CONTRAINTES
* NE PAS DÉMARRER tant que la phase Grecharged-mesh-browser (freecam v2) n'est pas fermée : mêmes
  fichiers (progress-pc.gc, text-h.gc, overlay). Le validator échoue si la v2 n'est pas passée.
* menu-tree.md ENTIÈREMENT réécrit sur la nouvelle arborescence (historique [SUPPR] conservé).
* Persistance : les réglages existants gardent leurs clés de sauvegarde (pas de reset des prefs).
* Mesure visuelle in-game interdite ; device = smoke ; livraison = deux APK, pré-vol obligatoire.
* Build : toujours ./build.sh android-arm64 --pbr (+ --debug pour les builds de test).

## ============================================================
## V2 — REDESIGN VISUEL COMPLET (owner 2026-08-02, réouverture)
## ============================================================
La STRUCTURE (5 catégories, GRAPHISMES par fonction) est VALIDÉE par l'owner ("beaucoup mieux").
Ce qui suit est un RE-SKIN AU SOL du menu : on ne garde PLUS le layout du menu d'origine.
"On peut complètement redesigner le menu pour que ce soit bien intégré et intégrable."

### 1. BUG BLOQUANT — hint hors écran
Sur le MENU PRINCIPAL (pause `*main-options-pc*` et/ou titre), la ligne de hint sort de l'écran.
La ligne de hint DOIT être visible et dans les bornes de l'écran sur TOUS les écrans qui l'affichent
(pause, titre, options, sous-catégories). Le placement doit être calculé par rapport au conteneur du
menu (voir hologramme ci-dessous), pas une constante origin-y héritée du menu d'origine.
PREUVE : la coordonnée Y de la ligne de hint est <= la limite basse de l'écran sur chaque écran, ET
la valeur est dérivée du cadre du conteneur (pas une constante magique 205-215).

### 2. HINTS SUR 100% DES ÉLÉMENTS
Chaque ligne sélectionnable a un hint compréhensible (pas seulement quelques-unes). Chaque en-tête de
groupe peut avoir un hint décrivant la section. Toutes langues (ENG/FRE/GER/ITA/JAP/SPA).
PREUVE : compteur "lignes avec hint / total lignes" == 100% par écran, dans le rapport.

### 3. VRAIES SECTIONS, pas des items
Les en-têtes de groupe ne doivent PAS ressembler à des entrées de menu. Hiérarchie visuelle nette :
titre de section distinct (couleur/taille/soulignement/retrait), les options en retrait dessous.
Le joueur voit immédiatement la section vs l'option. (Rendu — l'owner juge le visuel.)

### 4. FOND — abandonner hublot + overlay orange
Supprimer la texture "hublot" et l'overlay transparent orange du fond de menu. Le nouveau fond est
l'hologramme (ci-dessous). PREUVE : plus aucune référence à la texture hublot / au sprite overlay
orange dans le chemin de draw du menu (grep du draw code).

### 5. HOLOGRAMME VERTICAL BLEUTÉ (façon Jak 2) — le conteneur du menu
Tout le menu est contenu dans un pseudo-hologramme vertical bleuté (teinte cyan/bleu translucide,
scanlines/flicker léger optionnels), style holo-comm de Jak 2.
- OCCUPE la MOITIÉ GAUCHE de l'écran : largeur <= 50% de la largeur écran, aligné à gauche.
- MARGES par rapport aux bords (haut/bas/gauche) — jamais collé aux bords.
- Le texte du menu (sections, options, valeurs live, hints) vit À L'INTÉRIEUR de ce cadre holo.
PREUVE : constantes de géométrie du cadre (x, y, w, h) avec w <= 0.5*screen_w et marges > 0 ;
compteur de draw du cadre holo > 0 par frame quand le menu est ouvert.

### 6. LE VAISSEAU-DRONE PROJETTE L'HOLOGRAMME
Le petit vaisseau/drone qui flotte autour de Jak lors des comms distantes (Samos/Keira) est le
PROJECTEUR : il apparaît quand le menu s'ouvre, ORBITE lentement autour de l'hologramme, reste
ORIENTÉ VERS LE CENTRE de l'hologramme à une distance cohérente, et émet un FAISCEAU LUMINEUX vers
l'hologramme pour donner l'illusion qu'il le projette.
- Identifier l'entité/mesh du drone de comm dans jak1 ; s'il n'existe pas tel quel, réutiliser le
  mesh le plus proche (ou un drone simple) — DOCUMENTER le choix.
- Position/orientation du vaisseau dérivées du centre du cadre holo (cohérence géométrique).
- Le faisceau part de l'émetteur du vaisseau vers le cadre holo.
PREUVE : entité projecteur spawnée à l'ouverture du menu + despawn à la fermeture (compteur), sa
transform recalculée par frame (orbite), vecteur d'orientation pointant vers le centre du cadre,
faisceau dessiné (compteur de draw > 0). L'owner juge le rendu final.

### SÉQUENÇAGE / RISQUE
Ne PAS refaire de patch 2D jetable sur l'ancien layout : c'est un redesign au sol. Commite par
briques (fix hint -> hints 100% -> sections -> fond nettoyé -> cadre holo -> vaisseau+faisceau),
build x86 à chaque brique. Le device = smoke + preuve des compteurs render-thread (pas de mesure
visuelle). Livraison = deux APK + pré-vol. L'owner fait le jugement esthétique final.
