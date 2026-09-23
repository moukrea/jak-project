# Chaque techno d'eau a son reglage, son echelle, et un OFF prouve — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Le pire appareil est un banc d'essai, pas la cible (regle 6) : un palier ne pose que des defauts, chaque reglage est libre. lod-force-ocean etait un reglage mort (SPEC 2.5).

## Livrable — le contrat, en entier

Les 12 reglages de SPEC 7 au menu Recharged avec leurs echelles, le palier auto-deduit (= palier eclairage par defaut) qui ne verrouille rien, l'integration aux prereglages Original / Recharged. Pour CHAQUE reglage : un binaire-temoin ou la couche n'est pas compilee et la preuve que OFF lui est bit-identique (refset_replay_maxdiff=0), et la preuve que chaque cran intermediaire est pose. Budgets SPEC 6 mesures sur les quatre classes. Libelles selon recharged-settings-case-l10n. PREUVE : `FEATURE water-presets armed=1 hits=<reglages d'eau effectivement poses par le prereglage>` + la ligne `water_preset_apply_mismatch=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-presets"), jamais armed(), et n'en ecris pas un second.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Aucun reglage de menu remplace par une propriete de debug dans le build livre.

## Ou l'owner regardera

Options > Recharged : la ligne Eau Rechargee, la qualite de l'eau, et chaque reglage individuel (tessellation, rides, rivage, refraction, reflets, caustiques, eclaboussures, cascades, resolution)

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-09
> faire une spec de l'enfer pour l'eau, que ce soit la mer ou les points d'eau genre marres, flaques, fontaines, etc... Faudrait un truc moderne ou l'eau rend vraiment moderne, avec tous les effets attendus d'un jeu moderne mais en restant dans un esprit stylisé of course. Quand on marche dans l'eau ou tombe dedans, faut de la déformation (via tesselation je suppose) que ça soit impressionant, des costiques, de l'écume, des vagues distinctes sur le rivage (qui épouse le rivage avec l'écume et compagnie), ça c'est pour la mer mais il nous faut aussi repenser les points d'eau hors mer, puis les cascades d'eau et l'intéraction de ses dernières avec l'endroit où elles se jettent

### 2026-09-09
> tu pense encore et toujours que la target c'est le Redmi. non ça va aller sur PC, des devices hyper puissantes, des devices faibles... donc faut pas focus sur le pire, le pire sert de test et on peut avoir des réglages variables avec plus ou moins de techno embarquées et qualité d'effets a guise avec des options customisables !

### 2026-09-09
> la refonte de l'eau doit pouvoir être toggled off individuellement aussi, ou on retrouve l'eau vanilla.

### 2026-09-09
> bah je valide, beau boulot !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

