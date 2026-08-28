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

## APPAREILS — CONTRAINTE ABSOLUE (owner 2026-08-28, 23h)

**LA SHIELD EST INTERDITE DANS CETTE PHASE.** C'est la television de l'owner, dans son salon.
Mon propre critere « mesurer sur deux appareils de ratios differents » a envoye le framework la
lancer chez lui sans son accord. L'erreur est dans le critere, pas dans le worker.

**Un seul appareil autorise : le Redmi `eae4df44`.**

La variete de ratios se prend sur x86, pas sur un second appareil : le build de bureau se lance
a la taille de fenetre qu'on veut, donc autant de ratios qu'on veut, sans toucher a un appareil.

## Exige pour fermer

1. **Sur le Redmi UNIQUEMENT** : la trace publie une taille de fenetre NON NULLE et un
   `aspect-ratio` egal au ratio physique de l'ecran (2400x1080, soit 2,222). C'est la preuve que
   la valeur arrive enfin au moteur.
2. **Sur x86, au moins cinq ratios differents** couvrant le 4:3, le 16:9 et au moins deux ratios
   non standards au-dela de 2,0 : comptage de colonnes et de lignes quasi noires en bord d'image.
   Attendu : 0 partout. C'est la preuve que le correctif ne depend pas du ratio.
3. La garde de vacuite `unless (zero? ...)` ne peut plus desactiver silencieusement la branche
   auto : si la taille est nulle, le dire dans la trace au lieu de sauter sans bruit.
4. Le contournement 16:9 en dur de `kboot.cpp` est retire, ou son maintien est justifie.
