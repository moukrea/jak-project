# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-07 : « demerdes toi pour HDR/Blanc brûlés, c'est la top priorité, la brise et la cadence c'est sensé être tout en bas de la pile, je t'ai jamais dit de reprendre ça ! La top priorité c'est la refonte du lighting, commençant par reprendre le HDR/blancs brûlés ! »
- 2026-09-07 : « Attention, on s'attend bien sûr a des différences entre on et off quand même hein ! C'est sensé être techniquement plus riche le rendu de base étant plus Riche (HDR) mais faut que le rendu final reste cohérent avec l'original, pas de blancs brûlés, une teinte/saturation similaire, le contraste est sensé être plus riche vu qu'on part du HDR mais voilà, faut éviter le brûlé, et avoir plus de richess… »
- 2026-09-07 : « Enfin j'y entend pas grand chose mais j'espère m'être fait comprendre »

## Cause connue
Les anciennes references ne montraient presque aucun ciel (village1-hut) : elles ont donne un faux vert malgre les blancs brules. Detail conserve dans notes et SPEC §8 item 2.

## Livrable
ON et OFF doivent differer : ne pas chercher une identite pixel a pixel entre eux. Preserver teinte, saturation et intention artistique de l'original, avec contraste plus riche et details des hautes lumieres conserves, sans blancs brules. Rendu interne HDR puis un seul tone map vers SDR pour cette etape. La sortie native HDR, detectee et activable/desactivable, vient apres. Comparer tous les niveaux interieurs/exterieurs aux huit heures fixes appariees.
Le moteur publie hdr_sky_defects=0 avec chaque verdict : au moins trois vues de ciel dans trois niveaux (minimum, pas couverture finale), hdr_sky_pixels_pct >= 15 %, hdr_sky_clip_pct_x1000 <= reference ORIGINE-LUMIERE, hdr_sky_chroma_ratio_x1000 >= 900. Conserver les cinq verdicts existants : saturation, contraste, courbe, ORIGINE-LUMIERE, compression unique dans les trois configurations. References recapturees avec ciel avant toute conclusion.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
La sortie HDR vers un ecran compatible appartient a hdr-display-output. La regle des deux origines et la hierarchie des interrupteurs : SPEC §0.2, §1.1, §6.2.
