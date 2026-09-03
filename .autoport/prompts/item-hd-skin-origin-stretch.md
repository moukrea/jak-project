# Les modeles HD qui s'etirent vers un point lointain

## Defaut cite
- 2026-09-02 : « pas les transitions, le MOUVEMENT ; comparer l'os RENDU a l'os COMMANDE »
- 2026-09-02 : « ça arrive un peu at random en bougeant beaucoup, courant, faisant des demis tours, des sauts, des coups de poing, etc »
- 2026-09-03 : « en effet il s'étire plus, mais j'ai l'impression que maintenant c'est le modèle qui (en glitch) est transposé visuellement dans la direction ou l'étirement se faisait (voir, c'est difficile à constater parce que ça glitch, t-pose dans cette direction) »

## Cause connue
L'etirement vaut (1 - w3) x distance camera-origine : la ligne de translation des os du PILOTE porte w3 = 0,9982, que `bones-mtx-calc` multiplie par l'origine du monde en camera. Le correctif `hd-mat-affine!` est ecrit et debrayable. Le residu Redmi est attribue au squelette du pilote, pas a la chaine HD.

## Livrable
`hd-mat-affine!` livre et arme par defaut, zero os etire et zero saut de racine sur au moins 10 minutes de jeu en mouvement sur le Redmi.

## Preuve exigee
`hd_bones_stretched == 0` dans `reports/hd-skin-origin-stretch/proof.txt`.
Le proof se produit par `lib/proof_run.sh hd-skin-origin-stretch device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : loin de Sandover (village3, boss final) : les modeles HD pendant un saut ou un demi-tour.

## Hors perimetre
Ne touche pas a la chaine de peau stock, ni aux modeles HD eux-memes. Le residu du squelette pilote se traite ici, pas dans hd-models.
