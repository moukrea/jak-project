> LIS D'ABORD `prompts/item-recharged-hud-jak1-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le HUD Recharged de jak1

## Defaut cite
- 2026-09-17 : « Sinon oui, let's go pour ce que tu propose, je veux le relancer ! Fais ce que tu suggérais ! »
- 2026-09-17 : « Alors c'est bien que tu puisse pousser des images, mais là tu vois tu me dis que tu m'a envoyé le coeur vide, sauf que non, tu m'a envoyé la endcap de la jauge d'eco rouge ! »
- 2026-09-17 : « Et du coup… le sujet va bien être repris ? T'as fait des tickets dédiés ? tu me laisse un peu dans le flou là, et relis le commentaire sur l'envoi d'image, tu t'es chié ! »

## Cause connue
17/09 : relance par l'owner (« let's go pour ce que tu propose, je veux le relancer ! Fais ce que tu suggérais ! »). SPEC prompts/SPEC-refonte-hud.md. Ce ticket est le PARENT : il ferme la refonte quand les quatre chantiers sont passes.

## Livrable
`hud_recharged_defects` = 0, somme de termes publies SEPAREMENT.

1. LE REGLAGE : Options > Recharged porte la ligne du HUD recharge, ALLUME par defaut quand le maitre Recharged l'est ; le choix survit au redemarrage (publie).

2. ETEINT = ORIGINE, BIT-IDENTIQUE : empreinte de l'image du HUD eteint contre le binaire sans la couche (`--off`), sur >= 300 images, egale.

3. LES QUATRE CHANTIERS SONT LIVRES ENSEMBLE sur le meme binaire : leurs quatre portes relues a 0 dans cette meme course.

4. LES POLICES : inchangees (empreinte des atlas de police identique avant/apres).

PREUVE : `FEATURE recharged-hud-jak1 armed=1 hits=<images avec le HUD recharge allume>` + la ligne `hud_recharged_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`hud_recharged_defects == 0` dans `reports/recharged-hud-jak1/proof.txt`.
Le proof se produit par `lib/proof_run.sh recharged-hud-jak1 device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le HUD rechargé est allumé ; en jeu, cœur, jauge d'éco, mécamouche, orbe, particule d'éco et pile sont les nouveaux, et tout se comporte comme l'original. Éteint : le HUD d'origine, à l'identique..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
