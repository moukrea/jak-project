# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-07 : « Mais t'es con ou quoi ? L'orchestration, le harnais le framework doit être sous codex ! C'est n'importe quoi ! Il devrait pas être en pause là, tu te fous de ma gueule ! »
- 2026-09-07 : « Sur la brise ? What the Fuck il était pas sensé bosser sur les blancs brûlés et compagnie ? Comment je retrouve la bonne session du superviseur sous codex du coup ? CTRL+B puis 7 c'est ça ? »
- 2026-09-07 : « demerdes toi pour HDR/Blanc brûlés, c'est la top priorité, la brise et la cadence c'est sensé être tout en bas de la pile, je t'ai jamais dit de reprendre ça ! La top priorité c'est la refonte du lighting, commençant par reprendre le HDR/blancs brûlés ! »

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
