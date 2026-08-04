# Gmenu-flag-off — sortir la refonte menu (cassée) des builds, derrière un flag OFF par défaut

## LE PROBLÈME (owner, répété 2 fois — 2026-08-04)
La refonte menu (Grecharged-menu-overhaul) est CASSÉE et pourtant SANS GARDE (elle a remplacé le menu
directement dans progress-pc.gc) :
- elle a **inventé des paramètres qui n'existent pas** ;
- elle en a **redéfini d'autres différemment** → ils ne fonctionnent plus ;
- elle en a **retiré qui fonctionnaient** — concrètement : **plus aucun choix de displacement
  (parallax / tessellation / none) possible** ;
- des réglages « entrent en collision » (bindings par indices décalés qui s'écrasent entre eux).
La refonte sera retravaillée dans sa propre phase (déjà au backlog, avec l'esthétique holo parquée).
EN ATTENDANT, les builds livrés à l'owner doivent revenir à **l'ancien menu fonctionnel**.

## LA MISSION
1. Introduire `FLAG_MENU_OVERHAUL` (+ `_N`), généré par build.sh comme les autres flags (arg
   `--menu-overhaul`, défaut **OFF**), fan-out complet du flag-universe (les 4 sites de hash —
   voir feedback_ogflags_flag_universe_fanout).
2. **OFF (défaut)** = l'ANCIEN menu complet d'avant la refonte : structure d'origine, chaque ligne
   pilote le BON réglage, le sélecteur displacement opérationnel, zéro paramètre fantôme. Récupérer
   l'ancien code par archéologie git (l'état de progress-pc.gc avant la refonte) et le remettre comme
   chemin par défaut ; la refonte est compilée-out (#when FLAG_MENU_OVERHAUL).
3. **ON** = la refonte actuelle telle quelle (pour sa future phase de rework).
4. Les features récentes restent accessibles depuis l'ANCIEN menu : le toggle ENHANCED MODELS (HD),
   PBR, etc. — vérifier leurs lignes dans l'ancienne structure (elles y étaient avant la refonte).
5. ATTENTION aux dépendances prises sur la refonte depuis : le drone/holo (parkés), les zones
   tactiles, mesh-browser-update, les compteurs FLAG_*_N dans les indices de lignes. Compile OFF et
   ON doivent tous deux builder proprement (all-code + iso).

## PREUVE (pas de visuel — bindings/state dumps, règle owner)
- Build OFF : dump de la table des lignes (nom → value-to-modify) prouvant chaque binding correct et
  unique ; le displacement pilote réellement le mode (lire la valeur runtime après toggle) ;
  état HD/PBR togglables. deploy_verify sur eae4df44.
- Aucun capture-gate. L'owner juge le menu en jouant.
