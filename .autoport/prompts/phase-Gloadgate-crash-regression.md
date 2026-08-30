# Gloadgate-crash-regression — LE JEU NE CHARGE PLUS UNE PARTIE. Priorite absolue.

Retour owner mot pour mot dans
`.autoport/reports/Gloadgate-crash-regression/owner-defects.txt`. Lis-le en entier.

## Ce que tu dois savoir avant tout
C'est NOTRE regression. Le build de 14h07 chargeait une sauvegarde ; celui de 16h38 ne
charge plus. Le seul chantier entre les deux est Gloading-screen-window. L'owner ne
peut plus jouer. Rien d'autre ne passe avant.

## Acquis a ne pas casser
« le look est nickel bravo » — l'APPARENCE de l'ecran est validee par l'owner : taille
du texte a la moitie, position basse a droite, blanc plein, silhouette. Republie la
preuve qu'elle est inchangee dans le lot correctif.

## COMPLEMENT OWNER — LIS CECI AVANT TOUT (2026-08-30, meme build)
Sandover Village CHARGE. Le repere de Gol et Maia CHARGE. Seule Geyser Rock plante.
ET un SECOND chemin plante sans rien charger : depuis Sandover Village, pause -> OPTIONS,
le jeu meurt avant meme d'atteindre le menu de chargement.
=> Le point commun n'est PAS le chargement. Le mandat initial etait trop large.
=> Le chemin pause -> OPTIONS se reproduit en quelques secondes au clavier sur x86, sans
   charger quoi que ce soit : c'est LA reproduction a tenter EN PREMIER.
=> Si OPTIONS plante, la barriere de chargement n'est pas la cause (elle ne tourne pas
   dans ce chemin) et le repli « desarmer la barriere » NE SUFFIRA PAS. Le verifier.
=> Deux populations a expliquer : niveaux qui chargent (Sandover, Gol et Maia) contre
   celui qui plante (Geyser Rock). Publier ce qui les distingue.

## Ordre de travail
1. REPRODUIRE avant de theoriser, en commencant par pause -> OPTIONS sur x86.
   La Shield est INTERDITE — c'est la television de l'owner. La garde
   `.autoport/shield_guard.sh` echoue si quoi que ce soit la vise.
2. Capturer la trace COMPLETE du plantage : signal, pile d'appels, fil fautif.
   Un resume ne suffit pas.
3. Nommer la cause PAR LA MESURE. La relecture de code a coute 5 tentatives sur les
   cinematiques cette semaine ; ne recommence pas.
4. Corriger sans perdre l'encadrement de la fenetre ni le look.

## Indice fourni par la sequence decrite
« l'animation freeze, puis reprend, puis le jeu crash complet ». Un gel, une reprise,
puis la mort : quelque chose survit au gel et meurt apres. Le gel est le premier
symptome visible, pas forcement la cause. Le correctif livre a introduit dans
`game/system/load_gate.cpp` un mutex partage, un budget de temps par tranche et
`load_gate::scene_ready(...)` — c'est-a-dire un etat partage entre le fil de rendu et
le fil GOAL, exactement la ou le symptome apparait. A CONFIRMER, pas a presupposer.

## Repli explicitement autorise
Si la cause resiste, DESARME le correctif de barriere et reviens au comportement
d'avant sur ce seul point, en gardant l'apparence de l'ecran. Un jeu qui charge avec un
ecran imparfait vaut infiniment mieux qu'un jeu qui plante. Dans ce cas, publie
clairement ce qui est desarme pour que le chantier soit repris proprement.

## Format des marqueurs (le validateur les LIT)
Dans `.autoport/reports/Gloadgate-crash-regression/report.txt` :

    RESULT: LOAD SAVE NO CRASH
    CRASHREPRO plateforme=<x86|redmi> tentatives=<n> plantages=<n>
    CRASHTRACE signal=<...> fil=<...> frame0=<...>
    CRASHCAUSE nommee=<...> methode=<mesure|ablation>
    LOADOK plateforme=<x86|redmi> chargements=<n> plantages=0 scene=geyser-rock
    LSWIN transition=save-geyser t_up=<ms> t_first_draw_in=<ms> t_last_active=<ms> t_down=<ms>
    LOOKUNCHANGED scale=<f> xfrac=<f> yfrac=<f> couleur=<RRGGBB> identique=<0|1>

Verifie mecaniquement :
- CRASHREPRO avec plantages >= 1 AVANT correction (sans reproduction, rien n'est prouve) ;
- CRASHTRACE non vide ;
- LOADOK avec chargements >= 10 et plantages == 0, sur AU MOINS x86 ;
- LSWIN toujours encadrante (t_up <= t_first_draw_in et t_down >= t_last_active) ;
- LOOKUNCHANGED identique == 1.

## Marqueurs ajoutes suite au complement owner
    CRASHREPRO plateforme=<x86|redmi> chemin=<options|load-geyser> tentatives=<n> plantages=<n>
    POPULATIONS charge=<niveaux qui chargent> plante=<niveaux qui plantent> difference=<ce qui les separe>
Le validateur exige au moins une ligne CRASHREPRO avec `chemin=options`, et une ligne
POPULATIONS. Traiter Geyser Rock comme un cas isole n'est pas acceptable : c'est deja le
niveau du gel et du pop-in signales plus tot — trois symptomes au meme endroit.

## ETAT 2026-08-30 18h40 — LE DEFAUT NE SE REPRODUIT NI SUR x86 NI SUR LE REDMI
Mesure : x86, chemin options ET chargement Geyser Rock -> 0 plantage, chemins verifies
empruntes. Redmi eae4df44, deux courses, cycles geyser/sandover avec menu options et
menu de chargement atteints (captures T6 a T9) -> 0 plantage, le moteur va jusqu'au bout.
L'owner plante sur sa SHIELD, appareil INTERDIT depuis le 2026-08-30 (« Interdit de
toucher a la SHIELD a nouveau »). Nous n'avons donc AUCUN acces a la seule machine ou le
defaut existe.

DEUX HYPOTHESES RESTANTES, ET AUCUNE NE SE TRANCHE ICI :
  H1. Specifique a la SHIELD (Tegra, pilote graphique, memoire, ordonnancement des fils).
  H2. Specifique aux DONNEES DE SAUVEGARDE de l'owner — sa save Geyser Rock precisement,
      alors que Sandover et le repere de Gol et Maia chargent chez lui. Nos courses
      utilisent nos propres sauvegardes, pas les siennes.

CONSEQUENCE — LA PRIORITE CHANGE. Dans cet ordre :
  1. RENDRE LE JEU JOUABLE. Livrer un build ou le chantier Gloading-screen-window est
     DESARME sur sa partie risquee (l'etat partage de la barriere : mutex, budget par
     tranche, scene_ready), en CONSERVANT l'apparence validee par l'owner (« le look est
     nickel bravo »). Publier exactement ce qui est desarme.
  2. INSTRUMENTER POUR LA SHIELD. Puisqu'on ne peut pas y mesurer, le build doit ecrire
     lui-meme, dans un fichier lisible par l'owner ou dans le journal systeme, de quoi
     nommer la cause au prochain plantage : etat de la barriere, fil courant, derniere
     etape franchie, et une trace de pile si le moteur meurt.
  3. NE PAS declarer la cause tant qu'elle n'est pas mesuree. Un defaut absent sur deux
     machines et present sur une troisieme n'est PAS explique par une relecture de code.

CRITERE DE FERMETURE REVISE : la porte accepte desormais un lot qui DESARME et
INSTRUMENTE, a condition de publier CRASHREPRO (avec plantages=0 sur nos deux machines,
en le disant honnetement comme une NON-reproduction), DESARME (ce qui est retire),
LOOKUNCHANGED, et l'encadrement LSWIN peut etre perdu si c'est le prix de la jouabilite —
mais il faut le DIRE.
