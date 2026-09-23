# Les cascades tombent quelque part — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Les cascades sont UNIQUEMENT des sparticles devant une texture fixe ; la nappe est de la geometrie de niveau nommee par water_falls.txt (item 0). La brume ND (bigpuff) reste (SPEC 2.4, 5.7).

## Livrable — le contrat, en entier

Materiau W2c sur les prototypes CHUTE et JET : UV.y + t*vitesse, bruit etire x6, posterisation 5-6 bandes, flow a 2 phases decalees de 0,5, ecume basse par step, bord clair. A l'impact : anneau d'ecume radial, impulsion CONTINUE dans la RT de rides a position fixe (sans GOAL), brume ND conservee ; geysers/fontaines par periode. Jak sous la chute mouille via drip-wetness existant. SPEC 5.7. Publie falls_total, falls_bands, ripple_energy_at_impact (>0 sans Jak). PREUVE : `FEATURE water-falls armed=1 hits=<chutes dessinees avec anneau d'ecume ET impulsion a l'impact>` + la ligne `falls_without_impact=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-falls"), jamais armed(), et n'en ecris pas un second.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Pas de brume volumetrique hors cran Ultra.

## Ou l'owner regardera

les chutes de la jungle et la fontaine de Sandover : des bandes qui coulent, une base d'ecume, et la riviere qui ondule la ou ca tombe

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-09
> faire une spec de l'enfer pour l'eau, que ce soit la mer ou les points d'eau genre marres, flaques, fontaines, etc... Faudrait un truc moderne ou l'eau rend vraiment moderne, avec tous les effets attendus d'un jeu moderne mais en restant dans un esprit stylisé of course. Quand on marche dans l'eau ou tombe dedans, faut de la déformation (via tesselation je suppose) que ça soit impressionant, des costiques, de l'écume, des vagues distinctes sur le rivage (qui épouse le rivage avec l'écume et compagnie), ça c'est pour la mer mais il nous faut aussi repenser les points d'eau hors mer, puis les cascades d'eau et l'intéraction de ses dernières avec l'endroit où elles se jettent

### 2026-09-09
> bah je valide, beau boulot !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

