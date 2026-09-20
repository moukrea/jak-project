# L'herbe se couche dans la direction du pas, au lieu de s'ecraser en rond — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 11. Le systeme est plus riche que l'owner ne le croit — Jak, une trainee de quatre echantillons espaces de 0,15 s, la prise de rebord, huit acteurs ecrasables et huit occultants, montee 0,25 s, descente 0,6 s, pierres tombales de 8 s — mais la FORME reste un disque. La direction du deplacement est connue par la trainee et n'est JAMAIS utilisee comme vecteur. PIEGE MATERIEL A RECONDUIRE : sur Adreno 618, les lectures de tableaux d'uniformes a index DYNAMIQUE rendent des ordures. Le code deroule a index litteral et plafonne a huit occulteurs pour cette raison. Ce bug NE SE VOIT PAS sur x86.

COHERENCE HERBE (owner 20/09, sur les tickets variantes ET couleur : « a voir avec l'ensemble des tickets lies… j'aurais cru que c'etait compris depuis le debut ») : les chantiers d'herbe (silhouettes, couleur, vent, exposition, pas, biomes) forment UN SEUL rendu que l'owner juge d'un coup. Avant de coder : lire la SPEC-refonte-herbe EN ENTIER et TOUS les retours owner des items grass-* (owner_feedback de chacun) ; ne rien defaire de ce qu'un autre item d'herbe a livre ; si un choix ici contraint un autre item d'herbe, l'ecrire dans FINDINGS avec '-> item:<id>'. Les silhouettes par touffe (grass-blade-variants) sont le socle : couleur et vent s'y appuient et passent APRES.

## Livrable — le contrat, en entier

`grass_interaction_defects` = 0, somme de termes publies SEPAREMENT.
1. LA FLEXION SUIT LE MOUVEMENT : publier l'angle entre la direction de flexion moyenne et la direction de deplacement, sur une traversee scriptee, sous un plafond declare. Aujourd'hui cet angle est aleatoire par construction.
2. LE DEGAGEMENT LATERAL EXISTE : publier l'ecart entre la flexion au centre du contact et celle sur ses bords. Un ecart nul veut dire qu'on ecrase encore en rond.
3. RIEN NE REGRESSE DE L'ACQUIS : le relevement amorti, les pierres tombales, l'annulation a la casse d'une caisse et la distinction entre acteurs caches et acteurs aplatis gardent leurs grandeurs. Publier chacune.
4. LE DEROULAGE A INDEX LITTERAL EST CONSERVE : publier le compte de lectures de tableau d'uniformes a index dynamique dans les shaders du chemin herbe, qui vaut zero. Preuve sur l'APPAREIL, pas sur x86 : ce defaut y est invisible.
PREUVE : `FEATURE grass-interaction-direction armed=1 hits=<contacts dynamiques appliques>` + la ligne `grass_interaction_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Ne change pas la portee ni le nombre d'interacteurs des paliers bas, qui gardent la loi radiale actuelle en repli. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Sur le niveau d'entrainement : marche dans l'herbe et regarde devant les pieds de Jak. L'herbe doit se coucher devant lui et se degager sur les cotes, pas s'aplatir en disque.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

