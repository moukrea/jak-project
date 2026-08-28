# Gandroid-window-size — la taille de fenetre n'arrive JAMAIS au moteur sur Android

## Le symptome, signale DEUX FOIS par l'owner

2026-08-28, sur son HONOR (ratio d'ecran NON STANDARD), pendant les cinematiques :

> « Pourquoi avoir gardé les barres a gauche et à droite ?? Ça fait bizarre on dirait qu'on passe
> en 4:3 forcé »

puis, apres un premier correctif :

> « pour les cinématiques, toujours les barres noires à gauche et à droite hein ! »

Son reglage de format d'image **est en AUTO** et il l'a confirme. Ce n'est pas sa configuration.

## CAUSE RACINE — mesuree, pas supposee

`game/kernel/common/kmachine.cpp:656` :

    void pc_get_window_size(u32 w_ptr, u32 h_ptr) {
      if (!Display::GetMainDisplay()) {
        return;                      // <-- Android : sort SANS RIEN ECRIRE
      }

Sur Android la boucle de rendu n'est pas celle du `Display` PC. `framebuffer-width` et
`framebuffer-height` ne sont donc JAMAIS renseignes.

Consequence dans `pckernel-common.gc`, methode `update-from-os` :

    (unless (or (zero? (-> obj framebuffer-width)) (zero? (-> obj framebuffer-height)))
      ... (set-aspect-ratio! obj win-aspect) ...      ;; la branche AUTO est LA

La garde `unless (zero? ...)` saute **tout le bloc**. Donc :

1. **Le reglage « auto » de l'owner n'est pas ignore par un autre reglage : il n'est JAMAIS
   ATTEINT.** Il s'affiche dans le menu, il est coche, et il ne fait rien — sur tout appareil
   Android.
2. `framebuffer-scissor-width/height` gardent leur valeur initiale et partent telles quelles dans
   `pc-set-letterbox` (`pckernel-common.gc:346`), donc dans le decoupage et le centrage du
   renderer (`OpenGLRenderer.cpp:1363`). Ce qui depasse est peint en noir.
3. Un contournement historique force `masterConfig.aspect = SCE_ASPECT_169`
   (`game/kernel/jak1/kboot.cpp:88`, phase `Gaspect-unstub`) — il corrige la mise en page 2D du
   menu, **pas** `*pc-settings* aspect-ratio` que le recadrage de cinematique consomme.

## Pourquoi ca ne se voit que sur certains appareils

Mesure du 2026-08-28 sur le Redmi (2400x1080, ratio 2,222), MEME build que l'owner, quatre
captures pendant la cinematique `logo-intro`, dans les DEUX modes de visibilite :

    gauche=0  droite=0  haut=0  bas=0     image utile 2400x1080

Zero barre. Le contournement 16:9 place le jeu sur un cadre 16:9 ; sur un ecran proche du 16:9
l'ecart ne se voit pas. Sur un ratio **non standard**, cadre et ecran ne coincident pas et
l'ecart apparait en noir sur les cotes. **Le defaut depend de l'APPAREIL, pas du reglage.**

## Ce qu'il faut faire

1. **Renseigner la vraie taille de surface sur Android** la ou `pc-get-window-size` la lit. La
   surface est connue cote Android (`android_runtime_compat` / SDL) ; le probleme est qu'elle
   n'est jamais publiee vers le moteur.
2. **Retirer le contournement 16:9 en dur** une fois la vraie taille disponible — sinon deux
   sources de verite coexistent et la prochaine personne perdra une soiree dessus.
3. **Tracer les nombres au demarrage** : largeur et hauteur de fenetre vues par le moteur,
   `aspect-ratio` retenu, dimensions de decoupage. Sans elles ce defaut est indiagnosticable a
   distance, ce qui a deja coute plusieurs allers-retours a l'owner — dont deux ou je lui ai
   redemande de verifier une configuration qui etait correcte.

## Exige pour fermer

1. La trace publie une taille de fenetre NON NULLE sur appareil, et un `aspect-ratio` egal au
   ratio physique de l'ecran.
2. Mesure de barres noires sur DEUX appareils de ratios differents, par comptage de colonnes et
   de lignes quasi noires en bord d'image — pas a l'oeil. Attendu : 0 partout.
3. La garde de vacuite `unless (zero? ...)` ne peut plus desactiver silencieusement la branche
   auto : si la taille est nulle, le dire dans la trace au lieu de sauter sans bruit.
