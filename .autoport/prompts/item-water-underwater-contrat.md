# Sous la surface, on est sous l'eau — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. ND cache deja le maillage water-anim quand la camera passe sous surface - 2 m (water-anim.gc:571) ; rien d'autre n'existe (SPEC 2.2).

## Livrable — le contrat, en entier

Quand la camera est sous un plan : face arriere de la surface (fenetre de Snell, reflet interne total au-dela de 48 deg), brouillard teinte par la matiere applique avant le tone map (hdr.cpp), caustiques renforcees, rayons au cran Haut+. L'etat moteur « sous l'eau » est derive de la camera et du plan, publie et compare a la hauteur de jeu poussee. SPEC 5.1, 9. Publie snell_window_deg et underwater_fog_applied. PREUVE : `FEATURE water-underwater armed=1 hits=<images rendues avec la camera sous un plan d'eau>` + la ligne `underwater_state_mismatch=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-underwater"), jamais armed(), et n'en ecris pas un second.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Pas de simulation de plongee, pas de gameplay.

## Ou l'owner regardera

plonger dans la mer a Sandover, et Sunken City : la surface vue par-dessous, la fenetre de Snell, un brouillard teinte

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-09
> faire une spec de l'enfer pour l'eau, que ce soit la mer ou les points d'eau genre marres, flaques, fontaines, etc... Faudrait un truc moderne ou l'eau rend vraiment moderne, avec tous les effets attendus d'un jeu moderne mais en restant dans un esprit stylisé of course. Quand on marche dans l'eau ou tombe dedans, faut de la déformation (via tesselation je suppose) que ça soit impressionant, des costiques, de l'écume, des vagues distinctes sur le rivage (qui épouse le rivage avec l'écume et compagnie), ça c'est pour la mer mais il nous faut aussi repenser les points d'eau hors mer, puis les cascades d'eau et l'intéraction de ses dernières avec l'endroit où elles se jettent

### 2026-09-09
> bah je valide, beau boulot !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

