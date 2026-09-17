# Une seule matiere d'eau, eclairee par shade() — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. L'eau n'a aucune lumiere : env map statique environment-ocean-alphamod, aucun Fresnel, aucune profondeur (SPEC 2.1). SURF_WATER=8 existe deja dans le contrat de shade() (spec eclairage 4.2). NOTE 09-09 (perf) : perf-fbo-passes invalide depth/stencil apres la derniere lecture : W0 se place AVANT ce point, marque par un commentaire nomme dans android_opengl_renderer.cpp et OpenGLRenderer.cpp. Porte water_scene_copies_per_frame == 1 inchangee.

## Livrable — le contrat, en entier

Le chunk shaders/water/water_surface.glsl (SPEC 5.6 : normales a deux cartes, Fresnel plafonne, paliers de couleur par profondeur, absorption, shade() avec SURF_WATER, SSS deux couleurs, etincelles) inclus par la clipmap ET par un programme merc2_water pour les buckets water 58/59. W0 en profondeur seule. Aucun dFdx pour construire N. Publie water_refract_front_reject et water_dfdx_sites=0. Shaders neufs dans kChunks. PREUVE : `FEATURE water-surface-material armed=1 hits=<fragments d'eau passes par shade()>` + la ligne `water_shade_calls_outside_shade=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-surface-material"), jamais armed(), et n'en ecris pas un second.

DECISION 2 DE LA SPEC (1.3), qu'aucun item ne portait (audit superviseur 17/09) : 4 a 8 ondes de GERSTNER de faible amplitude en vertex, par-dessus la houle ND conservee, plus les deux cartes de normales. Publier le nombre d'ondes actives, leur amplitude totale (en unites jeu) et le deplacement vertical crete a creux mesure sur la clipmap, bras ON et bras OFF ; OFF = houle ND nue. Owner 17/09 : « avant cette reprise les vagues ressemblaient plus a des vagues » : c'est ICI que les vagues reviennent, et la cible est la SPEC, pas l'ancien rendu.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Pas de refraction couleur ni de reflet planaire (item 5), pas de rivage (item 3).

## Ou l'owner regardera

la mer et la fontaine de Sandover : une lumiere, un ciel dedans, des couleurs par profondeur, un soleil en eclats

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-09
> faire une spec de l'enfer pour l'eau, que ce soit la mer ou les points d'eau genre marres, flaques, fontaines, etc... Faudrait un truc moderne ou l'eau rend vraiment moderne, avec tous les effets attendus d'un jeu moderne mais en restant dans un esprit stylisé of course. Quand on marche dans l'eau ou tombe dedans, faut de la déformation (via tesselation je suppose) que ça soit impressionant, des costiques, de l'écume, des vagues distinctes sur le rivage (qui épouse le rivage avec l'écume et compagnie), ça c'est pour la mer mais il nous faut aussi repenser les points d'eau hors mer, puis les cascades d'eau et l'intéraction de ses dernières avec l'endroit où elles se jettent

### 2026-09-09
> bah je valide, beau boulot !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

