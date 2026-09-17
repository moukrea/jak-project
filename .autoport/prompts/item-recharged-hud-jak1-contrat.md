# Le HUD Recharged de jak1 — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

17/09 : relance par l'owner (« let's go pour ce que tu propose, je veux le relancer ! Fais ce que tu suggérais ! »). SPEC prompts/SPEC-refonte-hud.md. Ce ticket est le PARENT : il ferme la refonte quand les quatre chantiers sont passes.

## Livrable — le contrat, en entier

`hud_recharged_defects` = 0, somme de termes publies SEPAREMENT.

1. LE REGLAGE : Options > Recharged porte la ligne du HUD recharge, ALLUME par defaut quand le maitre Recharged l'est ; le choix survit au redemarrage (publie).

2. ETEINT = ORIGINE, BIT-IDENTIQUE : empreinte de l'image du HUD eteint contre le binaire sans la couche (`--off`), sur >= 300 images, egale.

3. LES QUATRE CHANTIERS SONT LIVRES ENSEMBLE sur le meme binaire : leurs quatre portes relues a 0 dans cette meme course.

4. LES POLICES : inchangees (empreinte des atlas de police identique avant/apres).

PREUVE : `FEATURE recharged-hud-jak1 armed=1 hits=<images avec le HUD recharge allume>` + la ligne `hud_recharged_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

(non precise)

## Ou l'owner regardera

Options > Recharged : le HUD rechargé est allumé ; en jeu, cœur, jauge d'éco, mécamouche, orbe, particule d'éco et pile sont les nouveaux, et tout se comporte comme l'original. Éteint : le HUD d'origine, à l'identique.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-17
> Bon en gros t'avais tous les éléments pour le HUD rechargé, c'est une refonte du HUD plus moderne… Ça tu le sais, on avait fait des essais…  En gros pour le coeur on avit ces assets :  ![jak_heart_0.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/d15cd9d3-3f7b-4413-8cb7-87a1cfb4726b/f07343cd-ecde-4199-88f3-df1e0b2ab893)  ![jak_heart_33.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/c87a9906-74ce-47cc-ba66-ed862d577526/8a93dc9a-591a-4e72-8452-65dac5716f56)  ![jak_heart_66.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/09cdf7f6-dfe7-47f2-b75e-184a72e242e7/e24b7395-0dea-4b60-9dd0-e65a5acfdc1a)  ![jak_heart_100.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/60b7b7fb-2374-4956-a658-637757630acb/eeafee5d-bea8-4ac4-b43c-fae5abb84c27)  C'est pas comme ça que ça fonctionne en l'état dans le jeu mais en on a du coeur vide au coeur plein, faut remplacer l'asset entier à chaque fois. Et faut que les comportements de clignotement/affichage soient identiques à l'original (du moins dans un premier temps.  Pour la jauge d'Eco, on avait tout un tas de trucs… Déjà la jauge vide:  ![jak_gauge_empty.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/b1fff085-d031-457a-8249-41cd99ed2ed1/7ebaa6f7-f0b9-4614-9465-582f62320edf)  Et les diverses jauges pleines :  ![jak_gauge_blue_full.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/6713650b-85ae-4f32-afda-95a16fcdc592/251b6be3-c1b1-4aaf-a558-e910a6b674cf)  ![jak_gauge_red_full.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/3d65184f-6e11-47fc-b4b4-19edbb78e87b/e014b249-f94c-466e-8807-84188cba2509)  ![jak_gauge_yellow_full.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/dbc16bc3-68f7-4c15-851d-8a43c8fb7e84/169083fe-6a29-46e6-afc5-c26ee41bf65f)  Bleue, Rouge et Jaune respectivement.  Évidemment ces jauges, comme dans le jeu d'origine, deplete au fil du temp et se remplissent pas à 100% systématiquement, ça c'est le quand elles sont à 100%, supperposé à la jauge vide et faut masquer la jauge pleine de la couleur d'Eco active en raccord (c'est une rotation, donc une sorte de masque en forme de camenbert) avec la fin de la jauge masquée supperposée par les end-caps de jauge que voici (qui doivent suivre la "rotation"):  ![jak_gauge_blue_end.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/e37b4b51-f9eb-4236-9a39-35d24c720d33/175c0c56-3129-4e4b-8871-4982a9c265c0)  ![jak_gauge_red_end.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/1d3cf130-fd2b-435f-a253-9a552e402351/3cc6db45-06f2-4184-a03d-5d34e37e9ffb)  ![jak_gauge_yellow_end.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/aa371203-447c-4bdd-9b48-ef5a546c07a7/c9c888cc-d984-4a4d-80b9-d673b4d7fe85)  M'enfin tu sais tout ça je pense  !  Pour la mecamouche du HUD, on utilise la vraie mecamouche du jeux et plus un sprite dégueu, pour l'orbe, on utilise une vraie orbe et plus un sprite dégue, pour la particule d'éco verte qui flotte à côté du coeur une vraie particule d'eco verte comme celles qu'on ramasse in game (et pas un truc hacky comme c'est dans le jeu original) et pour la pile d'énergie, idem !  Mais je crois que c'était déjà ce que le HUD rechargé essayait de faire quand on l'a parké, en tout cas c'était pas bon… Ah et aussi on a changé les fonts du jeu, donc la partie font ça devrait déjà être bon ! [images enregistrees : .autoport/owner-feedback/recharged-hud-jak1/20260917T0000-1.png ; .autoport/owner-feedback/recharged-hud-jak1/20260917T0000-2.png ; .autoport/owner-feedback/recharged-hud-jak1/20260917T0000-3.png ; .autoport/owner-feedback/recharged-hud-jak1/20260917T0000-4.png ; .autoport/owner-feedback/recharged-hud-jak1/20260917T0000-5.png ; .autoport/owner-feedback/recharged-hud-jak1/20260917T0000-6.png ; .autoport/owner-feedback/recharged-hud-jak1/20260917T0000-7.png ; .autoport/owner-feedback/recharged-hud-jak1/20260917T0000-8.png ; .autoport/owner-feedback/recharged-hud-jak1/20260917T0000-9.png ; .autoport/owner-feedback/recharged-hud-jak1/20260917T0000-10.png ; .autoport/owner-feedback/recharged-hud-jak1/20260917T0000-11.png]

### 2026-09-17
> Bon je sais pas si tu sais récupérer les images de Linear (tu devrais, c'est un bon endroit pour avoir des feedbacks visuels !) et tu pourrais même t'en servir pour poster des preuves et compagnie, super utile ! à voir si tu dois en fair eun ticket dédié

### 2026-09-17
> Sinon oui, let's go pour ce que tu propose, je veux le relancer ! Fais ce que tu suggérais !

### 2026-09-17
> Alors c'est bien que tu puisse pousser des images, mais là tu vois tu me dis que tu m'a envoyé le coeur vide, sauf que non, tu m'a envoyé la endcap de la jauge d'eco rouge !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

