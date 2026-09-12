# Cinq cles publiees de plus qui ne mesurent rien — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

CINQ SIGNALEMENTS DU 12/09 (reports/dead-cover-and-legends/FINDINGS.txt), tous du meme genre que les 24 que l'item vient de retirer, mais hors de son perimetre.
1. `refset.cpp:2352` : `grass_overhang` est PUBLIEE et le binaire livre ne peut pas la faire bouger — initialisee `false` a :2338, reaffectee uniquement sous un `#ifdef` absent du build.
2. `refset.cpp:3859,3866,3871` : trois cles publiees a valeur de CHAINE LITTERALE dans le bras `lighting-hdr` (`profile=sdr`, `method=...`, `particle_st...`). Une constante publiee se lit comme une mesure.
3. Les captures de qualification faites AVANT ce commit portent `subdivision` et `subdivision_rounds` dans leurs options effectives : comparer une capture ancienne a une neuve conclura a une derive la ou seul le champ a disparu.
4. `pbr_fused.glsl:220-221` et son miroir CPU : la porte du POM a quatre termes cote shader, et le miroir CPU n'en reflete pas autant. Un miroir partiel se lit comme un accord.
5. `background_common.cpp` (~2530-2636) : le bloc `lgtmath::kPbrParams` reste GARDE au motif qu'il alimente `pbr_cover_publish_gates`, fonction qui vient de passer de quatre atomiques a deux. Le motif de la garde a maigri de moitie sans etre reexamine ; seul `height_scale` la justifie encore.

## Livrable — le contrat, en entier

`dead_keys_r2_defects` = 0, somme de termes publies SEPAREMENT, un par signalement.
1. Chaque cle retiree est d'abord RETROUVEE par le meme detecteur sur le commit d'avant : publier le compte trouve avant et le compte trouve apres. Un zero apres sans un non-nul avant ne prouve rien.
2. Une valeur litterale cesse d'etre publiee comme une mesure, ou elle est renommee pour dire qu'elle est une constante. Publier laquelle des deux voies a ete prise, cle par cle.
3. Le miroir CPU du POM reflete EXACTEMENT les termes du shader : publier le compte de termes de chaque cote, l'egalite est le verdict.
4. Le motif de la garde de `kPbrParams` est reexamine et publie : ce qui la justifie encore, et ce qui n'y est plus.
5. Les captures anciennes sont marquees comme portant un champ disparu, pour qu'une comparaison ne conclue pas a une derive.

## Hors perimetre

Ne change aucun rendu. Priorite 33 volontaire : les chantiers d'eclairage passent AVANT.

## Ou l'owner regardera

Invisible. Ce sont des mesures publiees dans les preuves.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

