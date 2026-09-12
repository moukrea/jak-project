# Une surface porte de l'herbe selon DEUX sources, pas selon trois noms de texture — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, et il porte le lien vers l'investigation complete que l'owner a validee le 12/09. SPEC sections 2 et 3. C'est la cle de toute la campagne. L'eligibilite tient aujourd'hui a TROIS noms de texture exacts — `tra-grass`, `bch-grassfringe`, `bch-leafyground-hang-2x1` — et c'est de la que vient la cause racine des onze rounds d'overhang : le detecteur de bord declare qu'une arete ouvre sur le vide quand aucun AUTRE TRIANGLE TEXTURE HERBE ne la partage, si bien qu'un changement de materiau est indiscernable d'un precipice. Or `pat-surface` porte, sur CHAQUE triangle de collision de CHAQUE niveau, un champ de materiau de 23 valeurs dont `grass`, `sand`, `dirt`, `stone`. Le bake lit ce champ et n'en utilise QUE les bits de mode. Aucun site du moteur ne lit les bits 6 a 11.

## Livrable — le contrat, en entier

`grass_surface_unclassified` = 0, somme de termes publies SEPAREMENT.
1. LES DEUX SOURCES SONT LUES ET PUBLIEES SEPAREMENT : pour chaque triangle de sol, la classification par nom de texture et celle par materiau de collision. Publier les deux comptes par niveau, et le compte de triangles qu'AUCUNE des deux ne classe — c'est lui qui doit valoir zero.
2. LE DESACCORD SE COMPTE, IL NE SE DEVINE PAS. Publier le compte de triangles ou les deux sources divergent, avec les noms de texture impliques. Un desaccord n'est pas un defaut de cet item : c'est une donnee que les items suivants utiliseront. Le cacher en serait un.
3. RIEN NE CHANGE ENCORE DANS LE PLACEMENT : le compte de brins poses et leurs positions sont IDENTIQUES a ceux d'avant. Cet item lit et publie, il ne place pas.
4. LA LECTURE MARCHE SUR LES DIX NIVEAUX qui portent des textures de sol herbeux, pas seulement sur celui qui a de l'herbe. Publier le recensement par niveau.
PREUVE : `FEATURE grass-surface-truth armed=1 hits=<triangles de sol classes par au moins une source>` + la ligne `grass_surface_unclassified=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

NE CHANGE AUCUN PLACEMENT. Ne touche ni au bord sur le vide (`grass-edge-truth`), ni aux transitions (`grass-path-transitions`), ni a la retombee (`grass-edge-falloff`) — ce sont les items suivants, et ils dependent de celui-ci. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Rien a voir dans le jeu. C'est une vue de debug : chaque triangle colore par son materiau de collision, et les desaccords en evidence.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

