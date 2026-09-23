# Marcher, tomber, nager : la surface repond — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Tout existe pour les EVENEMENTS (water-control, splash-spawn, 2 groupes sparticle) mais la SURFACE ne bouge pas (SPEC 2.3). Le fil GOAL du Redmi est le goulot : rien de nouveau par image sur ce fil (regle 4).

## Livrable — le contrat, en entier

La RT de rides W1 en espace monde centree sur Jak (equation d'onde ping-pong, re-projection par texel entier, canal ecume), la file d'impulsions sur le fil de rendu, le sillage derive de la position de Jak, UN appel FFI pc-water-impulse! pose au site existant de splash-spawn (water.gc:776) — un appel par evenement, zero par image —, le maillage d'eclaboussure, lecture en vertex (clipmap et merc) et en fragment. Les PNJ a water-control passent par le meme site. Palier Tres bas : RT statique. SPEC 5.4. Publie ripple_energy avant/apres un pas force (causal), ripple_reproject_slips=0, splash_mesh_spawned. GOAL neuf (pc/water-pc.gc) liste dans game.gd et engine.gd. PREUVE : `FEATURE water-interaction armed=1 hits=<impulsions injectees dans la RT de rides>` + la ligne `ripple_impulses_dropped=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-interaction"), jamais armed(), et n'en ecris pas un second.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Aucune force en retour, aucune flottabilite, aucun courant qui pousse : la surface reagit, elle n'agit sur rien.

## Ou l'owner regardera

patauger dans les rizieres de Sandover et tomber dans la mer : un sillage derriere Jak, une gerbe et des anneaux qui s'eloignent

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-09
> faire une spec de l'enfer pour l'eau, que ce soit la mer ou les points d'eau genre marres, flaques, fontaines, etc... Faudrait un truc moderne ou l'eau rend vraiment moderne, avec tous les effets attendus d'un jeu moderne mais en restant dans un esprit stylisé of course. Quand on marche dans l'eau ou tombe dedans, faut de la déformation (via tesselation je suppose) que ça soit impressionant, des costiques, de l'écume, des vagues distinctes sur le rivage (qui épouse le rivage avec l'écume et compagnie), ça c'est pour la mer mais il nous faut aussi repenser les points d'eau hors mer, puis les cascades d'eau et l'intéraction de ses dernières avec l'endroit où elles se jettent

### 2026-09-09
> ça n'a aucun rapport avec la physique de Keira, ni peut-être même la physique tout court.. avec la physique peut-être mais dans le sens ou Jak interagit avec l'eau, et on y est pas encore du tout ! [...] en attendant simuler "pour de faux"

### 2026-09-09
> bah je valide, beau boulot !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

