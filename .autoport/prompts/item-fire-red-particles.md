> LIS D'ABORD `prompts/item-fire-red-particles-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Les aplats noirs et rouges qui recouvrent les feux et les portails

## Defaut cite
- 2026-09-11 : « Heuuuu tu te fous de ma gueule, la warp gate est pleine des… »

## Cause connue
DEUX ESSAIS PASSES AU VERT SUR UN DEFAUT INTACT. Ce que l'owner voit n'est PAS « des particules rouges » — ses captures du 11/09 montrent de GRANDES FORMES POLYGONALES NOIRES ET ROUGES qui RECOUVRENT l'effet. Le feu et le portail sont corrects DESSOUS : quelque chose se dessine par-dessus avec une texture qui ne se resout pas, ou un quad de sprite rempli d'une couleur de secours. Meme signature sur deux effets differents = une cause commune. La porte cherchait des « dessins rouges etrangers » (`fire_debug_particles`, `fire_pack_foreign_*`) et n'en trouvait aucun : elle mesurait la mauvaise chose. SECONDE PISTE, AU MOINS AUSSI FORTE : les deux preuves ont tourne sur le REDMI (eae4df44), l'own […suite dans le contrat]

## Livrable
`fire_foreign_overdraw` = 0. (1) SUR L'APPAREIL OU L'OWNER LE VOIT : reproduire d'abord. Si le defaut n'apparait pas sur le Redmi, le DIRE et mesurer sur le Honor (AREE026206000788) — deux preuves passees au vert sur le mauvais telephone valent zero. (2) CE QUI EST DESSINE, pas ce qui est arme : pour chaque dessin du chemin des particules et des sprites, publier l'etat de son echantillonneur — texture resolue, texture MANQUANTE, ou repli. Le compte de dessins a texture non resolue vaut 0. (3) COULEUR : publier la distribution des couleurs du seau particules contre la reference d'origine ; des aplats satures rouges ou noirs absents de l'origine sont un DEFAUT, quel que soit leur nombre. (4) C […suite dans le contrat]

## Preuve exigee
`fire_foreign_overdraw == 0` dans `reports/fire-red-particles/proof.txt`.
Le proof se produit par `lib/proof_run.sh fire-red-particles device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la hutte de Sandover au-dessus du feu, et la hutte de la jungle par-dessus le portail : plus aucune forme noire ou rouge par-dessus l'effet.

## Hors perimetre
Ne pas retoucher les particules d'origine ni leur cadence : on retire ce qui n'a rien a faire la, on ne redessine pas le feu.
