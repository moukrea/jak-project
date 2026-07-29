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

### OPTIONS unifiées — un seul écran, 6 catégories, groupes internes
  JOUABILITÉ   hints, sous-titres, 3 langues, auto-save
  AFFICHAGE    groupe Écran (aspect, résolution, display mode*, moniteur*, plein écran)
               groupe Performance (dynamic render scale, render scale, min FPS, frame rate*, V-Sync, MSAA)
               groupe HUD (compteur FPS, HUD Recharged)          * = lignes RÉTABLIES sur Android
  RENDU        groupe Général (RECHARGED MASTER en tête, Textures Recharged)
               groupe Matériaux (PBR, Relief, Specular, Displacement Off/Parallax/Tess)
               groupe Éclairage (ambient unifié, éclairage temps réel)
               groupe Végétation (herbe + distances — le sous-menu Grass est DISSOUS ici)
  AUDIO        volumes, langue des voix
  COMMANDES    manette, caméra, souris, rebinds, overlay tactile
  DEBUG        presets PBR, isolate, damier, Freecam/Mesh Browser, gizmos
  Le sous-menu "Recharged Settings" DISPARAÎT en tant que tel : réglages joueur dans
  Affichage/Rendu, outillage dans Debug. Le master reste le coupe-circuit global, en tête de RENDU.

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
