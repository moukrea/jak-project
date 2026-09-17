# L'herbe pousse en touffes coherentes, plus en bruit blanc de brins independants — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 6. Il n'existe AUCUNE touffe. Le placement est un tirage barycentrique uniforme par triangle, graine par triangle, et chaque brin tire ses cinq proprietes d'un hachage independant. Une recherche exhaustive ne trouve aucune structure de regroupement : le mot « tuft » du code designe une decoupe de fragment a l'interieur d'une carte, et `D_TARGET = 150 tufts/m^2` est un abus de langage pour brins/m^2.

## Livrable — le contrat, en entier

`grass_clump_defects` = 0, somme de termes publies SEPAREMENT.
1. LE REGROUPEMENT EST MESURE, pas affirme : publier une statistique de dispersion spatiale des racines, comparee a celle du tirage uniforme actuel sur la MEME surface. Elle doit s'ecarter d'un plancher declare. Une touffe qu'aucune mesure ne distingue d'un tirage uniforme n'existe pas.
2. LES TOUFFES NE SE RESSEMBLENT PAS : publier la dispersion du nombre de brins par touffe et celle de leur rayon. Deux touffes identiques cote a cote sont un defaut.
3. LES PALIERS RESTENT IMBRIQUES : un palier inferieur retire des brins DANS les memes touffes, il ne redistribue rien. Publier le compte de touffes dont l'origine bouge entre deux paliers : zero.
4. LE DETERMINISME TIENT : deux chargements donnent les memes touffes aux memes endroits. Publier une empreinte de l'ensemble des origines.
PREUVE : `FEATURE grass-clumps armed=1 hits=<touffes effectivement montees>` + la ligne `grass_clump_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Ne change ni la densite moyenne, ni la couleur, ni le vent — ce sont les items suivants, qui dependent de celui-ci. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Rien a juger a l'oeil pour l'instant : cette brique pose la STRUCTURE des touffes de la SPEC §6 (origine cuite, graine, rayon 110 mm ±21 %, 4,9 brins en moyenne, 2,5 x plus de voisins proches qu'un tirage uniforme, stable entre paliers). Le rendu qui change l'aspect vient avec les variantes de brins, le shading, le vent et les profils par biome : c'est LA que l'owner regardera l'herbe.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-17
> Mhhhh ouais OK je vois bien le truc de touffes… mais j'ai l'impression que c'est juste l'ancienne herbe en touffe… J'ai pas l'impression que ce soit raccord avec la SPEC que tu as à portée de main, ni si c'est raccord avec le reste de la refonte ou pas… Faut que tu vérifies là !

### 2026-09-17
> Alors je peux très bien valider cet item du coup, l'herbe est bien en touffe, c'est terminé pour moi

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

