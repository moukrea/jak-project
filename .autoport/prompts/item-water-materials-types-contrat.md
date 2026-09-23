# Boue, eco noir, lave, eau electrifiee : quatre matieres, pas une eau teintee — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. 48 looks water-anim en 13 sous-classes ND (mud, dark-eco-pool, *-lava, sunken-water...) tous rendus par le meme chemin (SPEC 2.2, annexe A).

## Livrable — le contrat, en entier

Les 7 matieres non-mer de SPEC 4 posees sur leurs looks via water_materials.txt et water_overrides.txt : boue mate opaque a amortissement x4 sans reflet ni caustique ; eco noir opaque a emissif violet en bord de rides ; lave emissive HDR a flow lent et croute Voronoi qui ECLAIRE (lumiere locale de lighting-local-lights si validee, sinon emissif seul) ; arcs pulses par deadly-fade de ND pour sunken. Branches par #define de matiere, jamais un if uniforme. Publie lava_emissive_lumens, mud_reflection_px=0, eco_caustic_px=0. PREUVE : `FEATURE water-materials-types armed=1 hits=<surfaces d'eau rendues avec leur matiere declaree>` + la ligne `water_look_unmapped=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-materials-types"), jamais armed(), et n'en ecris pas un second.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Les sources ND des sous-classes ne se reecrivent pas : la matiere se lit dans une table.

## Ou l'owner regardera

la boue de Misty Island et son bassin d'eco noir, puis la lave d'Ogre et l'eau electrifiee de Sunken

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-09
> faire une spec de l'enfer pour l'eau, que ce soit la mer ou les points d'eau genre marres, flaques, fontaines, etc... Faudrait un truc moderne ou l'eau rend vraiment moderne, avec tous les effets attendus d'un jeu moderne mais en restant dans un esprit stylisé of course. Quand on marche dans l'eau ou tombe dedans, faut de la déformation (via tesselation je suppose) que ça soit impressionant, des costiques, de l'écume, des vagues distinctes sur le rivage (qui épouse le rivage avec l'écume et compagnie), ça c'est pour la mer mais il nous faut aussi repenser les points d'eau hors mer, puis les cascades d'eau et l'intéraction de ses dernières avec l'endroit où elles se jettent

### 2026-09-09
> bah je valide, beau boulot !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

