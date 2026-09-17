# Deux astres, deux jeux d'ombres, et les acteurs qui en projettent — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Une seule cascade attribuee a « l'astre le plus haut », avec fondu et EMA pour cacher une bascule qui n'a pas lieu d'etre : les deux astres sont leves ENSEMBLE 3 h 30 par jour. Et aucun acteur n'entre dans la carte. SPEC 3.4 et 4.8.

## Livrable — le contrat, en entier

Atlas unique tuile, cascades stabilisees pour l'astre dominant, une tuile pour le second, les acteurs dans la passe de profondeur avec leur maillage skinne, ombres de contact sur la prepasse. L'aplat PS2 reste le repli et le mode Original. SPEC 4.8. PREUVE : `FEATURE lighting-shadows armed=1 hits=<pixels de sol ombres par un acteur>` + la ligne `shadow_caster_classes=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-shadows"), jamais armed(), et n'en ecris pas un second. AMENDEMENT 09-09 (perf) : une seule passe Z merc partagee entre prepasse (4.6), atlas (4.8) et aplat 47, VAO persistant par niveau (API setup_merc_vao conservee). Menu « Ombres d'acteurs » a trois crans vraies / aplat PS2 / aucune + fade-dist expose ; le cran « aucune » desactive la famille shadow-* cote GOAL.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle. L'aplat PS2 de shadow-geo n'est pas retire ici : il devient le repli et le mode original (decision owner 2026-09-03). Son remplacement en champ proche est lighting-actors.

## Ou l'owner regardera

l'ombre de Jak et des PNJ au sol, et le matin quand les deux astres sont leves

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-03
> quand les deux overlap... Bah ca doit etre pris en compte, ca l'est pour nous aussi quand on a la lune et le soleil visibles en meme temps !

### 2026-09-05
> Ça fait une éternité qu'on bosse sur des trucs de merde sans changements majeurs, j'aimerais un truc qui a un vrai effet Waouw next round du worker j'aimerais que ça parte sur le realtime lighting histoire d'avoir un réel sujet vraiment intéressant. Laisse finir le travail en cours et on passe sur l'intégralité du realtime lighting !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

