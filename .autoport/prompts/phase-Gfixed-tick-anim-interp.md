# Gfixed-tick-anim-interp — les ANIMATIONS ne sont pas interpolees

Retour owner, 2026-09-01 :
  « Le pas de temps fixe a l'air bon, mais les animations sont quand même très jittery hein ! »

## Constat MESURE par le superviseur (ne pas re-deriver)
Le facteur d'interpolation de rendu (`*fixed-tick-alpha*`) n'est lu qu'a UN SEUL endroit du
moteur : `engine/camera/cam-update.gc:245`. Aucune consommation cote animation.
Pire, `engine/draw/drawable.gc:1070` fait `(if (nonzero? *fixed-tick-armed*) (set! time-ratio 1.0))`
— le rapport de temps est FIGE A 1,0 des que le pas fixe est arme. Les poses ne sont donc
pas melangees entre deux pas de simulation : elles sautent. C'est le jitter decrit.

=> La moitie « pas fixe » du chantier fonctionne (l'owner l'a validee).
=> La moitie « interpolation de rendu » ne couvre que la CAMERA. Il manque les ANIMATIONS.

## Ce qu'il faut faire
Interpoler les poses de squelette entre le pas de simulation precedent et le courant, avec
le meme facteur alpha que la camera. Le moteur sait deja melanger deux poses : voir
`create-interpolated-joint-animation-frame` et les champs `frame-interp` de
`engine/anim/joint-h.gc` — reutiliser ce chemin plutot qu'en ecrire un autre.

## Pieges
- A 60 images par seconde et pas fixe a 1/60, alpha vaut toujours 1 : le comportement doit
  rester IDENTIQUE AU BIT. C'est la reference, ne pas la deplacer.
- Le jitter doit etre MESURE, pas juge a l'oeil : ecart image a image de la position d'un
  joint pendant une animation, a plusieurs cadences d'affichage.
- Ne pas interpoler les poses de CINEMATIQUE si elles sont deja cadencees autrement :
  verifier avant, sinon on ajoute un flou la ou il n'y en avait pas.

## Format des marqueurs
    RESULT: ANIM INTERPOLATED
    ANIMJIT fps=<f> arme=<0|1> ecart_moyen=<f> ecart_max=<f>
    ANIMSITES consommateurs_alpha_avant=<n> apres=<n>
    ANIM60 identique_au_bit=<0|1>
Verifie : ANIMJIT a >= 3 cadences ; a cadence haute l'ecart_max arme doit etre au moins
DEUX FOIS plus petit qu'avant ; ANIMSITES apres > avant ; ANIM60 identique_au_bit == 1.
