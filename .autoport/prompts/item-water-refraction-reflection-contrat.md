# Voir a travers l'eau, et voir le ciel dedans — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. DepthCue fait deja la seule copie couleur de l'ecran, au bucket 64 apres ocean-near (SPEC 2.5) ; sur GPU a tuiles chaque copie coute deux resolves (SPEC 10). Le cube de ciel capture est la passe P3 de l'eclairage (item lighting-regimes). NOTE 09-09 (perf) : perf-fbo-passes invalide depth/stencil apres la derniere lecture : W0 se place AVANT ce point, marque par un commentaire nomme dans android_opengl_renderer.cpp et OpenGLRenderer.cpp. Porte water_scene_copies_per_frame == 1 inchangee.

## Livrable — le contrat, en entier

W0 avec couleur : UNE copie apres les alphas, partagee avec DepthCue (qui cesse de blitter la sienne). Refraction avec REJET des echantillons devant la surface. Reflet du cube P3 via env_specular de shade(). Echelle a 4 crans reglable : ciel / cube / planaire 1/4 sur les plans immobiles listes / SSR sur toute l'eau avec repli cube. SPEC 5.6, 6. Publie water_fresnel_max (<= plafond) et water_env_source. PREUVE : `FEATURE water-refraction-reflection armed=1 hits=<pixels d'eau refractes>` + la ligne `water_scene_copies_per_frame=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-refraction-reflection"), jamais armed(), et n'en ecris pas un second.

DECISION 5 DE LA SPEC (1.3), qu'aucun item ne portait (audit 17/09) : l'eau se dessine APRES tous les opaques et les alphas, a la place du bucket 63, avec UNE copie unique de couleur + profondeur de scene ; le mid ecrit la profondeur en GL_ALWAYS au bucket 4, donc la profondeur lue AVANT est illisible (SPEC 2.x). Publier le bucket effectif de dessin de l'eau, le nombre de copies couleur/profondeur par image (= 1) et leur taille.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Pas de caustiques (item 6).

## Ou l'owner regardera

la fontaine de Sandover et la mer : le fond deforme a travers l'eau, le ciel du moment reflete, et un reflet net sur les bassins immobiles

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-09
> faire une spec de l'enfer pour l'eau, que ce soit la mer ou les points d'eau genre marres, flaques, fontaines, etc... Faudrait un truc moderne ou l'eau rend vraiment moderne, avec tous les effets attendus d'un jeu moderne mais en restant dans un esprit stylisé of course. Quand on marche dans l'eau ou tombe dedans, faut de la déformation (via tesselation je suppose) que ça soit impressionant, des costiques, de l'écume, des vagues distinctes sur le rivage (qui épouse le rivage avec l'écume et compagnie), ça c'est pour la mer mais il nous faut aussi repenser les points d'eau hors mer, puis les cascades d'eau et l'intéraction de ses dernières avec l'endroit où elles se jettent

### 2026-09-09
> tu pense encore et toujours que la target c'est le Redmi. non ça va aller sur PC, des devices hyper puissantes, des devices faibles... donc faut pas focus sur le pire, le pire sert de test et on peut avoir des réglages variables avec plus ou moins de techno embarquées et qualité d'effets a guise avec des options customisables !

### 2026-09-09
> bah je valide, beau boulot !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

