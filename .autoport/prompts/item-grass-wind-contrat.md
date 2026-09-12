# Un vent qui a une direction, et qui courbe le brin au lieu de le faire pivoter — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 8. L'herbe a UN SEUL SINUS a 0,271 Hz, sans rafale, et surtout SANS DIRECTION DE VENT : chaque brin oscille le long de son propre lacet aleatoire, donc le champ n'a aucun cap commun. ATTENTION, ORDRE DE L'OWNER DU 12/09 : « le shader breeze.glsl est tres peu satisfaisant aussi, tres rigide, pas ouf du tout, donc attention ». L'item `foliage-wind` porte DEUX REFUS COMPLETS. On reprend sa CHARPENTE TEMPORELLE — plusieurs bandes de frequence, un cap commun qui derive, un front de rafale — et PAS sa loi de flexion, qui fait pivoter l'element autour d'un point d'ancrage, mouvement d'objet dur. Un brin SE COURBE : la deflexion s'accumule le long de la tige et LA POINTE RETARDE SUR LA BASE.

## Livrable — le contrat, en entier

`grass_wind_defects` = 0, somme de termes publies SEPAREMENT.
1. LE CHAMP A UN CAP : publier la dispersion angulaire des directions de flexion sur une scene et une camera fixes. Elle est maximale aujourd'hui ; elle doit s'effondrer sous un plafond declare autour du cap du vent.
2. LE BRIN SE COURBE, IL NE PIVOTE PAS : publier le retard de phase entre la base et la pointe d'un meme brin, aujourd'hui nul, au-dessus d'un plancher declare. C'est la grandeur qui separe cette loi de celle que l'owner a refusee deux fois.
3. LA TOUFFE BOUGE ENSEMBLE SANS BOUGER PAREIL : publier la correlation des phases a l'interieur d'une touffe et entre touffes voisines. La premiere haute, la seconde basse, toutes deux sous plafond et plancher declares.
4. L'ANIMATION EST STABLE : aucun scintillement. Publier la variation image a image de la position d'une pointe, camera et scene immobiles, sous un plafond declare.
RISQUE A MESURER, PAS A SUPPOSER : `grass_occ::publish()` est partage avec `foliage-wind`, item ouvert et deja au bord du rejet definitif. Publier un temoin disant que ses grandeurs ne bougent pas.
PREUVE : `FEATURE grass-wind armed=1 hits=<brins animes par le champ de vent>` + la ligne `grass_wind_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Ne touche pas au vent du feuillage, qui est un autre item. Ne reprend PAS sa loi de flexion. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Sur le niveau d'entrainement : l'herbe doit onduler dans UNE direction qui change lentement, avec des rafales qui traversent la zone, et les brins d'une meme touffe doivent bouger ensemble sans bouger exactement pareil.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

