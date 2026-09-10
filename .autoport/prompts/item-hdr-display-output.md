# Sortir un vrai signal HDR sur les ecrans qui le supportent

## Defaut cite
- 2026-09-10 : « le dernier build je trouve pas trop sombre, mais on retombe sur le quasi 0 diff entre off vs on... je trouve pas ca plus riche, ou vraiment juste un yota au niveau des trucs qui brillent. Aussi, c'est statique non ? le H… »

## Cause connue
Refus 10/09. L'owner voit une MINI difference ON/OFF — « quasi 0 diff », « un yota au niveau des trucs qui brillent » : l'interrupteur agit, l'effet est trop faible. Marge accordee `hdr_out_ratio_max_x1000` = 2251, hautes lumieres livrees `hdr_out_hl_max_x1000` = 1445 : on n'utilise pas la marge obtenue. Les compteurs de NIVEAUX (17->128) montaient quand meme — compter des paliers n'est pas mesurer une amplitude.

## Livrable
`hdr_out_defects` = 0. Verdicts 1-8 : voir SPEC 4.5. (9) Pas d'assombrissement mesure sur du JEU REEL, plusieurs niveaux et ambiances, nombre d'images publie. (10) ADAPTATION A L'ECRAN : la SEULE reference de sortie est le pic ANNONCE, quel qu'il soit (480, 600, 1000...) ; aucune constante de calibrage dans le chemin. Prouve par l'EFFET, pas par un nombre publie : a deux pics annonces, la meme radiance sort a des valeurs differentes, et a 480 l'image n'est pas plus sombre qu'a 1000. (11) AMPLITUDE, PAS COMPTAGE : `hdr_out_hl_max_x1000` atteint une fraction majoritaire de la marge REELLEMENT accordee (`hdr_out_ratio_max_x1000`) sur du jeu reel — 1445 pour 2251 accordes est un DEFAUT. Un compteur de niveaux distincts ne vaut plus verdict. (12) ADAPTATION AU CONTENU, distincte de (10) : la courbe suit la scene dans le TEMPS, facon Dolby Vision / HDR10+, jamais un filtre unique applique partout facon HDR10 statique. Publier la SERIE des parametres effectifs sur un parcours plein jour / interieur sombre / grotte : ils doivent CHANGER, transition lissee, aucun pompage. Courbe constante = DEFAUT. Preuve sur le Honor.

## Preuve exigee
`hdr_out_defects == 0` dans `reports/hdr-display-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-display-output device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Eclairage Recharge : la ligne « sortie HDR ». Activee sur ton Honor, les zones brillantes doivent vraiment ressortir, sans que le reste change..

## Hors perimetre
Ne pas regresser le SDR livre. Profils HDR distincts autorises, aucune egalite numerique SDR/HDR exigee. Pas de nouveau chemin LDR demande.
