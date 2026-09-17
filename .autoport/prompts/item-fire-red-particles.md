> LIS D'ABORD `prompts/item-fire-red-particles-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Les aplats noirs et rouges qui recouvrent les feux et les portails

## Defaut cite
- 2026-09-11 : « C'est bon pour les particules bizarres rouges et noires là,… »

## Cause connue
DEUX ESSAIS PASSES AU VERT SUR UN DEFAUT INTACT. Ce que l'owner voit n'est PAS « des particules rouges » — ses captures du 11/09 montrent de GRANDES FORMES POLYGONALES NOIRES ET ROUGES qui RECOUVRENT l'effet. LES DEUX CAPTURES SONT A SANDOVER VILLAGE : un feu dans une hutte, et le portail de la HUTTE DU SAGE VERT (pas la jungle — correction de l'owner). Et ce n'est pas local : « cet effet est visible sur TOUS les feux et portails de teleportation ». Le feu et le portail sont corrects DESSOUS : quelque chose se dessine par-dessus avec une texture qui ne se resout pas, ou un quad de sprite rempli d'une couleur de secours. Meme signature sur deux effets differents = une cause commune. La porte […suite dans le contrat]

## Livrable
`fire_foreign_overdraw` = 0. (1) REPRODUIRE AVANT DE CORRIGER, sur le Redmi eae4df44 — le SEUL appareil branche. Les deux verts precedents ne prouvent rien : ils mesuraient l'armement d'un debug, pas ce qui est dessine. Si, avec la bonne mesure, le defaut N'APPARAIT PAS sur le Redmi : publier le constat, ecrire le handoff, et RENDRE LA MAIN TOUT DE SUITE. Ne brule aucun essai a chercher un defaut absent, ne tente aucune correction a l'aveugle. Owner 11/09 : « si le defaut se reproduit pas sur Redmi, passe a autre chose plutot que bloquer » — le superviseur parque l'item en attente du Honor et le harnais enchaine sur le chantier suivant. (2) CE QUI EST DESSINE, pas ce qui est arme : pour chaq […suite dans le contrat]

## Preuve exigee
`fire_foreign_overdraw == 0` dans `reports/fire-red-particles/proof.txt`.
Le proof se produit par `lib/proof_run.sh fire-red-particles device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sandover Village : le feu dans la hutte, et le portail de la hutte du Sage vert. Puis n'importe quel autre feu ou portail — l'effet est partout..

## Hors perimetre
Ne pas retoucher les particules d'origine ni leur cadence : on retire ce qui n'a rien a faire la, on ne redessine pas le feu.
