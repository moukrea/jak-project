# L'audit du recensement voit aussi les drapeaux d'hote et les tables de surveillance — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

QUATRE SIGNALEMENTS DU 12/09 (reports/census-false-reds/FINDINGS.txt). L'audit qui vient de retirer trois cles infalsifiables garde quatre angles morts.
1. `hdr.cpp:296` : `RT_KNEE` est le dernier jeton de `kCompressionTokens` et n'a plus AUCUNE occurrence dans le CODE des shaders, une seule en commentaire. `tonemap_sites_shader` ne peut monter que si quelqu'un REMET l'identifiant : c'est une table de SURVEILLANCE, pas une mesure de l'etat courant, et un relecteur lit son zero comme « aucun shader ne compresse ».
2. L'audit juge les PORTES (uniformes) et les JETONS (tables de texte), pas les DRAPEAUX D'HOTE. `s_host_legacy` et `s_host_shade` selectionnent les seaux C et E : un seau rendu inatteignable par un drapeau d'hote fige ne serait pas compte. Meme classe que ce qu'on vient de retirer.
3. `lib/census/census-false-reds.sh` lit UNE ligne par site d'appel : un appel etale sur plusieurs lignes, ou deux appels sur la meme ligne, ne rendent qu'un site, et un argument illisible est classe NON litteral, donc vers le VERT.
4. `lighting_census.cpp:120` prend `u_pbr_mode` comme temoin « survit a la purge », alors que `lib/census/lighting-legacy-purge.sh` le liste parmi les 36 uniformes que cet item doit SUPPRIMER. Le jour ou la purge aboutit, le temoin tombe de moitie sans que personne l'ait voulu.

## Livrable — le contrat, en entier

`census_blind_spot_defects` = 0, somme de termes publies SEPAREMENT.
1. Une table de SURVEILLANCE est nommee comme telle et ne se lit plus comme une mesure : publier separement « jetons surveilles » et « jetons observes dans le code », et dire quand les deux divergent.
2. Les drapeaux d'hote entrent dans l'audit : publier le compte de seaux rendus inatteignables par un drapeau fige. Semer un drapeau fige et verifier que le compte monte.
3. Le detecteur de site d'appel cesse de raisonner a la ligne : publier le compte de sites trouves et le compte d'arguments illisibles, separement. Un argument illisible ne tombe plus vers le vert.
4. Un temoin ne peut plus etre un uniforme qu'un autre item doit supprimer : publier l'intersection entre les temoins de survie et les listes de suppression des items ouverts. Elle doit etre vide, ou le defaut est compte.

## Hors perimetre

Ne change aucun critere d'item. Priorite 34 volontaire : les chantiers d'eclairage passent AVANT.

## Ou l'owner regardera

Invisible. C'est l'instrument qui juge les instruments d'eclairage.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

