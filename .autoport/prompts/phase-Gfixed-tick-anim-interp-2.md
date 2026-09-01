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

## RETOUR 2 — OWNER 2026-09-01. LE CAS QUI COMPTE EST LA BASSE CADENCE.
« Quand le framerate est dans les 20 FPS, je trouve que c'est jittery, PLUS QUE LE
FRAMERATE... L'interpolation doit pas bien fonctionner. et of course faut que ça marche
dans les deux sens ! »

Le cycle 1 a ameliore la haute cadence (180 img/s : 7,58 -> 2,56) et LAISSE la basse
cadence intacte, voire pire (30 img/s : 17,04 -> 20,14). La porte precedente exigeait une
mesure > 60 et reléguait les basses en « hors verdict » : elle regardait ailleurs.

PISTE A INSTRUIRE : a 20 img/s d'affichage avec simulation a 60 Hz, il faut ~3 pas de
logique par image, et ce nombre VARIE (2, 3, 4) selon le temps ecoule. Si le rendu montre
la pose de FIN DE RAFALE sans interpoler, l'avance apparente change d'une image a l'autre
— tremblement PIRE qu'un pas variable simple. Verifier ce que vaut le facteur alpha quand
l'affichage est PLUS LENT que la simulation : est-il seulement calcule ?

La porte exige desormais une amelioration MESUREE DES DEUX COTES : au moins une cadence
<= 30 et une > 60, chacune avec sa paire arme/desarme. Une seule cote ne prouve rien.
