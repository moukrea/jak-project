# Sortir un vrai signal HDR sur les ecrans qui le supportent

## Defaut cite
- 2026-09-11 : « donc ca veut dire que pour le chantier HDR, on peut garder le Redmi, a 500 nits c'est top ! Donc on l'utilisera pour l'HDR aussi ! »
- 2026-09-11 : « pour le chantier HDR, on peut garder le Redmi, a 500 nits c'est top ! Donc on l'utilisera pour l'HDR aussi ! »

## Cause connue
Refus 10/09. L'owner voit une MINI difference ON/OFF — « quasi 0 diff », « un yota sur les trucs qui brillent » : l'interrupteur agit, l'effet est trop faible. Sur le HONOR : marge accordee 2251, hautes lumieres livrees 1445 — on n'utilise pas la marge obtenue ; et les compteurs de NIVEAUX (17->128) montaient quand meme, compter des paliers n'est pas mesurer une amplitude. Second grief : courbe STATIQUE, la meme partout. APPAREIL CHANGE le 11/09 : le Redmi annonce 500 nits, 3 formats HDR et les extensions EGL. Les chiffres ci-dessus sont ceux du Honor : les remesurer.

## Livrable
`hdr_out_defects` = 0. Verdicts 1-8 : voir SPEC 4.5. (9) Pas d'assombrissement, mesure sur du JEU REEL, plusieurs niveaux, nombre d'images publie. (10) ADAPTATION A L'ECRAN : la SEULE reference est le pic ANNONCE, quel qu'il soit ; aucune constante de calibrage. Prouve par l'EFFET : a deux pics annonces, la meme radiance sort differemment, et au pic reel l'image n'est pas plus sombre qu'a 1000. (11) AMPLITUDE, PAS COMPTAGE : `hdr_out_hl_max_x1000` atteint une fraction majoritaire de la marge REELLEMENT accordee (`hdr_out_ratio_max_x1000`) sur du jeu reel. Un compteur de niveaux ne vaut plus verdict. (12) ADAPTATION AU CONTENU, distincte de (10) : la courbe suit la scene dans le TEMPS, facon Dolby Vision / HDR10+, jamais un filtre unique. Publier la SERIE des parametres sur un parcours plein jour / interieur / grotte : ils CHANGENT, transition lissee. Courbe constante = DEFAUT. Preuve sur le Redmi eae4df44. ANNONCER N'EST PAS ACCORDER : si le systeme ne rend aucune marge, le verdict 11 sort ROUGE et on le DIT.

## Preuve exigee
`hdr_out_defects == 0` dans `reports/hdr-display-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-display-output device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Eclairage Recharge : la ligne « sortie HDR ». Activee sur le Redmi, les zones brillantes doivent vraiment ressortir, sans que le reste change..

## Hors perimetre
Ne pas regresser le SDR livre. Profils HDR distincts autorises, aucune egalite numerique SDR/HDR exigee. Pas de nouveau chemin LDR demande.
