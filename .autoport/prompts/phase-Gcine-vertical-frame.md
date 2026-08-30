# Gcine-vertical-frame — le cadre vertical d'auteur doit remplir la hauteur, a tout format

L'owner signale CE MEME defaut pour la CINQUIEME fois. Ses mots et l'analyse des quatre
echecs precedents sont dans `.autoport/reports/Gcine-vertical-frame/owner-defects.txt`.
LIS-LE EN ENTIER AVANT DE TOUCHER UNE LIGNE.

## Regle qui prime sur tout le reste
Les quatre tentatives precedentes ont echoue de la MEME maniere : la correction a ete
raisonnee sur la source, la formule se lisait juste, la phase a ete declaree passee.
La formule EST juste aujourd'hui et le defaut EST toujours la, sur un ecran 16:9.
=> Tu n'as PAS le droit de fermer cette phase sur une lecture de code.
=> La sonde de demarrage existante force elle-meme le bit `movie` et balaye des formats
   synthetiques : elle prouve la formule, pas le chemin livre. Ne t'appuie pas dessus.

## Premier livrable, avant toute correction
Une trace image-par-image du chemin REEL, pendant la cinematique que l'owner nomme
(teleporteur Geyser Rock -> Hutte du Sage Vert), publiant sur une seule ligne :
`use-vis? real-movie? aspect-ratio video-mode aspect-symbole x-ratio y-ratio viewport`
plus un CONTROLE NEGATIF hors cinematique qui doit differer.
Tant que cette trace n'existe pas, il n'y a rien a corriger : on ne sait pas quelle
branche s'execute.

## Criteres de fermeture
1. La trace ci-dessus existe et nomme la branche reellement prise.
2. La cause est designee par la mesure, pas par deduction.
3. Apres correction : la hauteur du cadre d'auteur EGALE la hauteur d'ecran, mesuree a au
   moins quatre formats (4:3, 16:9, 21:9, ultra-large), et ZERO pixel d'auteur hors ecran.
4. Le champ horizontal S'ELARGIT avec le format (on voit plus sur les cotes) — le
   verifier par un compte d'objets visibles, pas par une capture.
5. Controle negatif : hors cinematique, les valeurs different.
6. `letterbox` n'emet toujours aucun octet en mode natif, et le controle positif (use-vis?)
   en emet — un zero sans controle qui tire ne prouve rien.

## Preuve x86
L'owner, 2026-08-29 : « la plupart des choses sont testables sur x86 aussi, y compris les
divers aspect ratios ». La trace de format se prend au clavier. La verification sur
appareil se fait quand un appareil est libre, JAMAIS comme prerequis bloquant.

## Format des marqueurs (le validateur les LIT, ne les paraphrase pas)
Publie dans `.autoport/reports/Gcine-vertical-frame/report.txt` :

    RESULT: CINE VERTICAL FRAME MEASURED
    CINELIVE scene=<nom> frame=<n> usevis=<0|1> realmovie=<0|1> asp=<f> aspsym=<s> x=<f> y=<f> vp=<w>x<h>
    CINECTL  scene=<nom> frame=<n> usevis=<0|1> realmovie=<0|1> asp=<f> aspsym=<s> x=<f> y=<f> vp=<w>x<h>
    CINEBRANCH taken=<usevis|realmovie|else>
    CINEFIT asp=<f> authorh=<f> screenh=<f> offscreen=<n>      (une ligne par format, >= 4)
    CINEWIDE asp=<f> objets=<n>                                 (une ligne par format, >= 4)
    CINEBARS vis=0 bytes=<n>
    CINEBARS vis=1 bytes=<n>

Contraintes verifiees mecaniquement :
- au moins 8 lignes CINELIVE prises PENDANT la cinematique nommee ;
- au moins 1 ligne CINECTL, et son quadruplet (usevis,realmovie,x,y) DIFFERE de CINELIVE ;
- CINEBRANCH nomme la branche reellement executee ;
- >= 4 CINEFIT, chacune avec authorh == screenh (tolerance 0,5 %) et offscreen == 0 ;
- CINEWIDE : le nombre d'objets visibles CROIT avec le format (strictement) ;
- CINEBARS vis=0 -> bytes = 0 ; vis=1 -> bytes > 0 (controle positif, sinon le zero ne
  prouve rien).

## MESURE DU 30/08 12:35 — LIS CECI AVANT DE CONCLURE
Les trois candidats C1/C2/C3 sont REFUTES par la trace (usevis=0, realmovie=1,
branche=realmovie, asp=1.7777 juste). NE CONCLUS PAS « la formule est correcte » : la
sonde publie, depuis le debut, une perte de 25,0 % du champ VERTICAL a l'entree en
cinematique, a tous les formats (v 0.4686 -> 0.3514). C'est le defaut de l'owner.
Le code fige la coupe des barres PS2 en la prenant pour le cadre d'auteur.
Publie en plus, une ligne par format (>= 4) :
    CINEVLOSS asp=<f> v_cine=<f> v_jeu=<f>
La porte exige une perte <= 0,5 %.
