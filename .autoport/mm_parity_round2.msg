[autoport/Grecharged-materials-modern-parity] LES TROIS NOMBRES QUI PORTAIENT LE VERDICT ETAIENT FAUX, ET LE QUATRIEME MESURAIT UN DRAPEAU

La tentative 1 (2026-08-08) avait bati toute la pile de materiaux modernes puis s'etait
arretee sur `RESULT: WIP`. En reprenant ses artefacts sans rien reconstruire, les quatre
chiffres sur lesquels un verdict aurait repose se refutent l'un apres l'autre.

1. « pbr binding lines with mm_flags!=0: 2090 » en jambe OFF — FAUX ROUGE.
   `mm_device_proof.sh:130` comptait `grep -cav 'mm_flags=0x0 '` sur TOUTES les lignes
   'pbr binding'. Or 2090 d'entre elles sont des `maps=NONE (same-source pairing / no maps)`
   qui ne portent AUCUN champ `mm_flags=` : elles passaient le grep INVERSE quoi qu'il
   arrive. Recompte a la CLE : 8 lignes portent le champ, et en OFF les 8 sont a `0x0`
   (en ON, 0 sur 8). La jambe OFF etait PARFAITE. Le controle par ABSENCE est le meme piege
   que le grep « Appuie sur start » devenu prefixe.

2. « shader compile/link errors: 1 », identique dans LES DEUX jambes — FAUX ROUGE.
   Le motif `shader (compile|link)` en `-i` matchait la banniere du pilote :
   `I AdrenoGLES-0: OpenGL ES Shader Compiler Version: EV031.32.02.16`.
   Zero echec reel (`Failed to compile|link` = 0), et le jeu imprime lui-meme la
   contre-preuve : `A35-RENDER all 52 shaders compiled under GLES 3.20`. Le garde-fou
   « budget de samplers » que cette ligne pretendait surveiller n'a donc JAMAIS ete exerce.

3. « [cover] disp_pom=0 disp_none=22 coverage_pct=0.0 » — MESURE D'UN MODE DEBUG.
   Le `settings.ini` VIVANT de l'appareil porte encore, au 2026-08-31 :
       pbr-displacement = 0   (defaut livre 1 = PARALLAX)
       pbr-isolate      = 3   (defaut livre 0 = BOTH ; 3 = NEITHER)
   soit la bisection DEBUG en menu forcant la carte de normales ET la parallaxe a OFF.
   `pom_disp` exige `(bisect & 128) == 0` : avec 192, il est faux pour TOUS les draws. Le
   POM n'etait pas casse, il etait DESARME — et les deux clips livres montrent en plus la
   scene SANS cartes de normales. Une salle qui mesure a un niveau EPINGLE, encore.

4. « ACTIVE DRAWS total=7212 » — UN MIROIR DU DRAPEAU, PAS UNE MESURE DE L'EFFET.
   `mm_note_active_draw` est appele DEPUIS la garde de changement d'etat de PbrDrawBinder :
   il compte les RE-POUSSEES du bloc d'uniformes (transitions de matiere), pas des draws.
   50 draws sur la meme matiere comptent 1. L'arithmetique le montre seule : 22 draws PBR
   par image x 601 images = 13 222, pas 7 212. Et `energy` et `specocc` sont EGAUX au total
   PAR CONSTRUCTION (le parseur les met a `true` par defaut et aucun des 172 enregistrements
   de surfaces.json ne les surcharge) : ces deux nombres ne portent aucune information.
   L'en-tete affirmait « every time a draw really enters the modern chunk » — faux deux fois.

CE QUE CE COMMIT CHANGE, ET RIEN D'AUTRE : de l'INSTRUMENT. Aucun pixel ne bouge.
  - le compte de `mm_flags` se fait a la CLE et publie ses trois nombres ;
  - le compte d'erreurs de shader compte des ECHECS, et publie la contre-preuve positive ;
  - le harnais RETABLIT les defauts livres (`pbr-displacement`, `pbr-isolate`) avant la
    course, publie l'avant/apres, et refuse de juger la parallaxe si un controle est epingle
    — le correctif est pose au PRODUCTEUR de la course, pas en note de bas de page ;
  - `mm_note_bind` compte les binds REELS a cote des transitions, la ligne de synthese est
    emise MEME A ZERO (une jambe OFF publie des zeros au lieu de se taire, une absence
    n'etant pas distinguable d'un bloc non compile), et elle publie `u_pbr_debug` — la porte
    de `pbr_modern.glsl:40` qui peut sauter tout le chunk PENDANT que les compteurs montent.

CE QUI RESTE OUVERT ET N'EST PAS LIVRE (nomme, pas tu) :
  - IBL / ambiant image-based : CANAL MORT. `u_rt_probe_on` est ecrit a 0 en dur
    (`FollowProbe.cpp:224`) et nulle part ailleurs ; tous les sites d'echantillonnage du
    cubemap sont gardes dessus. Et meme leve, `eval_env()` evalue un CIEL PROCEDURAL, il ne
    rend aucune geometrie du monde — « l'ambiant reagit a l'environnement » est faux dans
    les deux sens. Cout paye pour rien : rafraichissement de face + mipmap par image.
  - tonemap ACES / calibration d'exposition : le bit 64 ne peut pas se lever avec les
    donnees livrees (0 des 172 enregistrements ne porte la cle `filmic`), et
    `u_mm_exposure` n'a de source que debug/env. Code vivant, donnee absente.
