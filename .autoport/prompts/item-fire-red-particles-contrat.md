# Les aplats noirs et rouges qui recouvrent les feux et les portails — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

DEUX ESSAIS PASSES AU VERT SUR UN DEFAUT INTACT. Ce que l'owner voit n'est PAS « des particules rouges » — ses captures du 11/09 montrent de GRANDES FORMES POLYGONALES NOIRES ET ROUGES qui RECOUVRENT l'effet. LES DEUX CAPTURES SONT A SANDOVER VILLAGE : un feu dans une hutte, et le portail de la HUTTE DU SAGE VERT (pas la jungle — correction de l'owner). Et ce n'est pas local : « cet effet est visible sur TOUS les feux et portails de teleportation ». Le feu et le portail sont corrects DESSOUS : quelque chose se dessine par-dessus avec une texture qui ne se resout pas, ou un quad de sprite rempli d'une couleur de secours. Meme signature sur deux effets differents = une cause commune. La porte cherchait des « dessins rouges etrangers » (`fire_debug_particles`, `fire_pack_foreign_*`) et n'en trouvait aucun : elle mesurait la mauvaise chose. SECONDE PISTE : l'owner voit le defaut sur son HONOR, les deux preuves ont tourne sur le REDMI. Mais elles mesuraient la mauvaise grandeur, donc « ca ne se reproduit pas sur le Redmi » n'a JAMAIS ete etabli. Le Redmi est le seul appareil branche : on commence par y chercher le defaut avec la BONNE mesure.

## Livrable — le contrat, en entier

`fire_foreign_overdraw` = 0. (1) REPRODUIRE AVANT DE CORRIGER, sur le Redmi eae4df44 — le SEUL appareil branche. Les deux verts precedents ne prouvent rien : ils mesuraient l'armement d'un debug, pas ce qui est dessine. Si, avec la bonne mesure, le defaut N'APPARAIT PAS sur le Redmi : publier le constat, ecrire le handoff, et RENDRE LA MAIN TOUT DE SUITE. Ne brule aucun essai a chercher un defaut absent, ne tente aucune correction a l'aveugle. Owner 11/09 : « si le defaut se reproduit pas sur Redmi, passe a autre chose plutot que bloquer » — le superviseur parque l'item en attente du Honor et le harnais enchaine sur le chantier suivant. (2) CE QUI EST DESSINE, pas ce qui est arme : pour chaque dessin du chemin des particules et des sprites, publier l'etat de son echantillonneur — texture resolue, texture MANQUANTE, ou repli. Le compte de dessins a texture non resolue vaut 0. (3) COULEUR : publier la distribution des couleurs du seau particules contre la reference d'origine ; des aplats satures rouges ou noirs absents de l'origine sont un DEFAUT, quel que soit leur nombre. (4) CAUSE COMMUNE : TOUS les feux et TOUS les portails montrent la meme signature — l'owner l'a constate. Nommer le site partage et le corriger LA, jamais effet par effet ; une correction qui ne vaudrait que pour un feu est un DEFAUT. (5) Publier la liste des effets inspectes et le verdict de chacun.

## Hors perimetre

Ne pas retoucher les particules d'origine ni leur cadence : on retire ce qui n'a rien a faire la, on ne redessine pas le feu.

## Ou l'owner regardera

Sandover Village : le feu dans la hutte, et le portail de la hutte du Sage vert. Puis n'importe quel autre feu ou portail — l'effet est partout.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-10
> je sais pas pourquoi, mais que ce soit on ou off, on a un truc louche au dessus des feux, ca fait des particules rouges bizarres, probablement un des tests/debugs qui est reste la et qui maintenant reste... Faut degager ca c'est horrible

### 2026-09-11
> les warp gates aussi emettent les particules rouges degueulasses

### 2026-09-11
> Heuuuu tu te fous de ma gueule, la warp gate est pleine des particules rouges comme sur le feu ... Qui d'ailleurs n'est pas corrige !!! FOUTAGE DE GUEULE !!! [captures fournies : de GRANDES FORMES POLYGONALES NOIRES ET ROUGES par-dessus l'effet, dans la hutte de Sandover au-dessus du feu, et dans la hutte de la jungle par-dessus le portail]

### 2026-09-11
> c'est pas le portail de la jungle, c'est la hutte du Sage vert a Sandover Village ! et cet effet est visible sur tous les feux et portails de teleportation anyway

### 2026-09-11
> tu as le Redmi a disposition, pas le Honor, ne l'oublies pas !

### 2026-09-11
> si le defaut se reproduit pas sur Redmi, passe a autre chose plutot que bloquer

### 2026-09-11
> C'est bon pour les particules bizarres rouges et noires là, j'ai plus le soucis sur le Honor, validé !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

