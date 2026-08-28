# Gloading-screen — un ecran de chargement au lieu d'un ecran noir

## APPAREILS — CONTRAINTE ABSOLUE (owner 2026-08-28, 23h)

**LA SHIELD EST INTERDITE.** C'est la television de l'owner, dans son salon. Le 2026-08-28 un de
mes criteres de validation a envoye le framework y lancer le jeu sans son accord ; il l'a tolere
« car je suis seul ce soir » en precisant qu'il aurait prefere que non.

**Un seul appareil autorise : le Redmi `eae4df44`.** Toute mention de la Shield dans ce document
est un CONTRE-EXEMPLE historique, jamais une instruction.

## La demande (owner 2026-08-28), maquette fournie

Maquette : `.autoport/design/loading-screen-owner-mockup.png` (16:9).

- Silhouette blanche de Jak courant lateralement vers la DROITE, Daxter sur l'epaule, **~40 % de
  la hauteur d'ecran**, centree verticalement, a GAUCHE. Capturee depuis la **vraie animation**
  de course, vue de cote, convertie en blanc sur noir.
- En bas a droite : « Loading... » **localise**, en **Urbanist**.
- Sous le texte : les glyphes precurseurs disant « Loading », **a la largeur EXACTE du texte
  localise**.

Motif de l'owner : « ça empêcherait l'utilisateur de se poser des questions quand c'est en
chargement (le jeu a crash ? pourquoi cet écran noir ?) ».

Ca repond directement aux **6,7 s d'ecran noir** mesurees sur la Shield le 2026-08-28
(`LOADGATE open scene=logo-intro waited=6763ms reason=resident`).

## Ou ca se branche

`blackout()` — `goal_src/jak1/engine/game/main.gc:61` — dessine aujourd'hui un simple rectangle
noir plein ecran.

## PIEGE MESURE — ne pas le rater

L'ecran noir ne sert PAS qu'au chargement : il sert aussi aux coupes de camera
(`pov-camera.gc:103`, 0,035 s) et aux boutons (`basebutton.gc:348`, 0,05 s). Mettre le contenu
dans `blackout()` sans condition ferait CLIGNOTER « Loading... » a chaque coupe de camera.
=> Lier a la barriere de chargement precisement, et n'afficher qu'au-dela d'un seuil (~0,5 s).

## Point d'implementation sur les glyphes

« Chargement... » est nettement plus large que « Loading... ». La ligne de glyphes doit donc etre
**mise a l'echelle par langue** sur la largeur MESUREE du texte rendu, pas dessinee a taille
fixe. Le systeme de police sait mesurer une largeur.

**Aucun alphabet precurseur n'existe dans le jeu** : les textures « precursor » sont des murs de
la citadelle. Les glyphes sont un asset a creer (8 sur la maquette).

## Dependance

Le texte doit etre en Urbanist => **depend de `Gfont-urbanist`**. Livrer d'abord le branchement
et le seuil (qui ne dependent de rien et suppriment l'angoisse), la silhouette ensuite, le texte
et les glyphes en finition.

## Ordre impose

1. Branchement + seuil (supprime l'angoisse, zero dependance).
2. Silhouette fixe capturee depuis l'animation reelle.
3. Texte localise + glyphes precurseurs, apres Urbanist.
