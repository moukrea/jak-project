# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-06 : « J'ai l'impression que même avec le Real Time lighting à off on a quand même les blancs brûlés, est ce que tu passe bien par ce paramètre pour gate nos effets ou tu les code en dur en remplaçant le vanilla, alors que la SPEC stipule qu'on peut rester au rendu d'origine si on le veut »
- 2026-09-07 : « le HDR brûle toujours les blanc de fou ! Je sais pas où tu teste mais le ciel est blanc, off le ciel est clairement coloré, c'est pas bon ! »
- 2026-09-07 : « Du coup tu es sur les blancs brûlés du HDR hein ? C'est là que Claude Code était... Je crois qu'il était en capture sur tous les niveaux a des heures différentes avec la refonte on/off pour s'assurer que les blanc n'étaient pas brûlés et que ça reste proche du rendu à off (artistic, tout en étant probablement plus riche car ça se fait en HDR maintenant, puis tonemappé pour le rendu final... avant… »

## Cause connue
Les anciennes references ne montraient presque aucun ciel (village1-hut) : elles ont donne un faux vert malgre les blancs brules. Detail conserve dans notes et SPEC §8 item 2.

## Livrable
Comparer refonte ON/OFF sur tous les niveaux et vues interieures/exterieures de lighting-census, aux huit heures fixes appariees. Corriger les blancs brules en preservant couleurs et intention artistique du rendu OFF. Rendu interne HDR, un seul tone map vers SDR ; sortie ecran HDR ensuite.
Le moteur publie hdr_sky_defects=0 avec chaque verdict : au moins trois vues de ciel dans trois niveaux (minimum, pas couverture finale), hdr_sky_pixels_pct >= 15 %, hdr_sky_clip_pct_x1000 <= reference ORIGINE-LUMIERE, hdr_sky_chroma_ratio_x1000 >= 900. Conserver les cinq verdicts existants : saturation, contraste, courbe, ORIGINE-LUMIERE, compression unique dans les trois configurations. References recapturees avec ciel avant toute conclusion.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
La sortie HDR vers un ecran compatible appartient a hdr-display-output. La regle des deux origines et la hierarchie des interrupteurs : SPEC §0.2, §1.1, §6.2.
