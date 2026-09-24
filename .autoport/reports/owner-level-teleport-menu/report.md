# owner-level-teleport-menu — essai 2

DIRECTIVES v28786981ef

Verdict : le menu de téléportation se pilote maintenant au tactile — tant qu'il est ouvert, la
commande de gauche de la surcouche devient une croix (haut/bas/gauche/droite, un cran par poussée).

## Ce qui a changé (commit 93fc9abc90)
- `android/gk_android_main.cpp` : le publieur « sélecteur de warp » (g_overlay_in_warp) lève aussi
  le drapeau quand `*tpm-open*` est vrai → même bascule stick→croix et même glyphe que le warp.
  JNI neuf `isTeleportBenchArmed` (vrai seulement sous `debug.opengoal.costprobe=owner-level-teleport-menu`).
- `TouchOverlayView.java` : pilote de banc (armé par cette seule propriété) qui rejoue 4 gestes du
  pouce (bas, haut, droite, gauche) par `dispatchTouchEvent`, le chemin exact d'un doigt.
- `pc/teleport-menu.gc` : compteur des HAUT/BAS/GAUCHE/DROITE reçus menu ouvert ; phase « tactile »
  du banc avant les 3 sauts ; `teleport_menu_defects` = sauts ratés + (navigation tactile nulle).

## Preuve (proof.txt, appareil USB eae4df44, essai owner-level-teleport-menu@2)
    proof_binary_decision=deploye (apk-du-constructeur-installe, md5 8b5d40d3… des deux côtés)
    crash=0  frames=4260
    teleport_menu_defects=0
    teleport_menu_touch_nav=4   teleport_menu_touch_planned=4
    teleport_menu_done=3        teleport_menu_save_changed=0
    teleport_menu_0_level=beach     ok=1 dist_cm=0 hour=7
    teleport_menu_1_level=village2  ok=1 dist_cm=0 hour=12
    teleport_menu_2_level=jungle    ok=1 dist_cm=0 hour=23
Journal moteur : « Gwarp-dpad: … OPEN -> … acts as D-PAD », 4 × « menu-dpad latch -> onPadButton(sdl=12/11/14/13) »
(isInMenu=false isInWarp=true), « TELEPORT-MENU bench touch-nav=4/4 », puis « restored to analog stick ».

## Ce que l'owner doit regarder
Sur le téléphone : SELECT + L1/R1 maintenus (deux doigts) ouvrent le menu ; le rond de gauche
affiche une croix ; pousser haut/bas choisit, gauche/droite sur la ligne « Heure » change l'heure,
X ouvre / y va, O revient. À la fermeture le stick redevient analogique.

## Non prouvé
- non prouvé : le confort (c'est l'owner qui juge) ; toucher directement une ligne n'est pas fait.
- non prouvé : l'ouverture à deux doigts n'est pas rejouée par le banc (l'owner l'a constatée le 24/09).
- Capture : aucune capture postée (le crochet refuse `screencap`) ; ticket commenté en `--no-capture`.
