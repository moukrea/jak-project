> LIS D'ABORD `prompts/item-cutscene-npc-flicker-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Les PNJ clignotent pendant les cinematiques

## Defaut cite
- 2026-09-06 : « Validé »

## Cause connue
LE DEFAUT EST ENFIN CAPTURE SUR L'APPAREIL DE L'OWNER. Fichier tire de son Honor le 2026-09-05 : reports/cutscene-npc-flicker/owner-honor/npc_flicker-honor-2026-09-05.txt (1044 lignes, sa session de 14h44).
SCENE DU MAIRE : NPCSCENE cycles=6 sur 3564 images, plateforme=honor. Deux mecanismes DISTINCTS, ce qui explique pourquoi quatre correctifs successifs n'ont jamais suffi — chacun n'en visait qu'un :
  * mayor-lod0 : 210 images / 3825 ms, cause=modele-absent (le modele n'est pas la au moment de dessiner)
  * sidekick-lod0 (Daxter) : 390 images / 6856 ms, cause=soumis-mais-non-dessine (soumis au rendu, rien ne sort)
  * hutlamp-lod0 : 421 images / 7463 ms, meme cause que Daxter
TOUTES SCENES CONFONDUES, les causes comptees chez lui : soumis-mais-non-dessine 210, modele-absent 130, cull-aveugle 40, hidden 23, culled 2, clone-desynchronise 1. Le clone — la cause corrigee le 2026-09-03 — ne represente donc QU'UNE occurrence sur 406.
Daxter recidive : 6 episodes longs a lui seul (390, 382, 328, 324, 322, 51 images). windspinner-lod0 tient 1959 images (35 s) invisible. warp-gate-switch-lod0 : 4 episodes.
NPCPLAT de la scene du maire : nullfg=0 bareret=0 dblee=0 kerncode=0 enterstate=0 rftd=0 suspend=0 precopy=0 chainloop=0 malformed=0 hd_failopen=0 hd_gap=0 — AUCUN des mecanismes arm64 soupconnes n'a tire. La cause est ailleurs : chercher pourquoi un modele est ABSENT et pourquoi une soumission ne DESSINE pas.

## Livrable
Sur la scene du maire, sur un appareil : zero cycle et zero episode long. Les deux causes dominantes doivent tomber a zero et etre EXPLIQUEES : `modele-absent` (130 occurrences) et `soumis-mais-non-dessine` (210). Le moteur emet `npc_flicker_episodes` = somme des episodes longs toutes causes.

## Preuve exigee
`npc_flicker_episodes == 0` dans `reports/cutscene-npc-flicker/proof.txt`.
Le proof se produit par `lib/proof_run.sh cutscene-npc-flicker device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la premiere cinematique avec le Maire.

## Hors perimetre
Jak et Daxter ne sont pas concernes : l'owner parle des PNJ. Pas de refonte du culling general. Aucune capture d'ecran ne vaut preuve.
