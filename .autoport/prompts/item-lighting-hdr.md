# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-06 : « J'ai l'impression que même avec le Real Time lighting à off on a quand même les blancs brûlés, est ce que tu passe bien par ce paramètre pour gate nos effets ou tu les code en dur en remplaçant le vanilla, alors que la SPEC stipule qu'on peut rester au rendu d'origine si on le veut »
- 2026-09-07 : « le HDR brûle toujours les blanc de fou ! Je sais pas où tu teste mais le ciel est blanc, off le ciel est clairement coloré, c'est pas bon ! »

## Cause connue
LA PORTE MESURAIT UNE SCENE SANS CIEL. Mesure du 2026-09-07 sur les references elles-memes : les huit images de chaque jeu sont prises au seul point `village1-hut`, en 320x180. Le quart superieur y vaut RGB(137,94,57) et RGB(111,70,50) — du brun, pas du ciel — et il porte ZERO pixel sature. Les cinq verdicts pouvaient donc etre verts pendant que le ciel brulait : le defaut de l'owner n'etait pas dans le champ de la mesure. Voir aussi SPEC §8 item 2 pour le mecanisme (C/E gardent exposition et pow).

## Livrable
Les verdicts de courbe se mesurent LA OU L'OWNER VOIT LE DEFAUT : sur du CIEL. `hdr_sky_defects=N`, somme de verdicts publies un par un, sur des vues qui contiennent du ciel dans au moins trois niveaux exterieurs differents :
  (1) `hdr_sky_frames` >= 3 vues de ciel, et `hdr_sky_pixels_pct` >= 15 % de l'image — une vue sans ciel ne compte pas ;
  (2) `hdr_sky_clip_pct_x1000` <= celui de la reference ORIGINE-LUMIERE : le ciel ne doit pas SATURER plus qu'avec l'eclairage eteint ;
  (3) `hdr_sky_chroma_ratio_x1000` >= 900 — le ciel garde au moins 90 % de sa COULEUR : l'owner dit « off le ciel est clairement colore », donc un ciel qui blanchit est un defaut meme sans saturation franche ;
  (4) les cinq verdicts deja tenus le restent (saturation, contraste, courbe, jeu ORIGINE-LUMIERE, un seul site de compression dans les trois configurations).
Zero. Les references DOIVENT etre recapturees avec du ciel avant toute conclusion.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
La sortie HDR vers un ecran compatible appartient a hdr-display-output. La regle des deux origines et la hierarchie des interrupteurs : SPEC §0.2, §1.1, §6.2.
