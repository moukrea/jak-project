# La lumiere danse sur le sable, jamais au-dessus de l'eau — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Aucune caustique n'existe : update-mood-caustics est un cycle de palette dans sunken (SPEC 2.4). floor_depth du .waterbake donne la profondeur du sol sans copie de profondeur.

## Livrable — le contrat, en entier

Dans shade(), bloc sous #if WATER_CAUSTICS : pour tout fragment sous le plan d'eau du niveau et dans sa boite, la caustique module LE SEUL terme direct du soleil, projetee en monde, 3 echantillons RGB decales, attenuee par floor_depth et par la visibilite de l'ombre. Crans : simple / RGB / correlees a la RT + rayons additifs sous l'eau. SPEC 5.1, 6. Publie caustic_sun_only=1 et caustic_levels. PREUVE : `FEATURE water-caustics armed=1 hits=<fragments sous le plan d'eau ayant recu la caustique>` + la ligne `caustic_above_water_px=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-caustics"), jamais armed(), et n'en ecris pas un second.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Jamais sur l'indirect, jamais au-dessus du plan.

## Ou l'owner regardera

le fond de la mer a la plage de Sandover et les rizieres : des caustiques lentes sur le sable, rien sur les rochers hors de l'eau

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-09
> faire une spec de l'enfer pour l'eau, que ce soit la mer ou les points d'eau genre marres, flaques, fontaines, etc... Faudrait un truc moderne ou l'eau rend vraiment moderne, avec tous les effets attendus d'un jeu moderne mais en restant dans un esprit stylisé of course. Quand on marche dans l'eau ou tombe dedans, faut de la déformation (via tesselation je suppose) que ça soit impressionant, des costiques, de l'écume, des vagues distinctes sur le rivage (qui épouse le rivage avec l'écume et compagnie), ça c'est pour la mer mais il nous faut aussi repenser les points d'eau hors mer, puis les cascades d'eau et l'intéraction de ses dernières avec l'endroit où elles se jettent

### 2026-09-09
> bah je valide, beau boulot !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

