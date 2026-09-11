> LIS D'ABORD `prompts/item-hdr-display-output-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Sortir un vrai signal HDR sur les ecrans qui le supportent

## Defaut cite
- 2026-09-11 : « HDR10+ on drop complet alors ! »

## Cause connue
LIS D'ABORD `prompts/item-hdr-display-output-contrat.md` — OBLIGATOIRE. Cette consigne est un resume plafonne ; le contrat complet, les verdicts 1-8 detailles, les quinze refus de l'owner et les chiffres deja mesures (et sur QUEL ecran) y sont. Resume : l'owner voit une MINI difference ON/OFF ; il decrit un filtre pose APRES le tone map SDR. Courbe STATIQUE. Preuve sur le Redmi eae4df44.

## Livrable
`hdr_out_defects` = 0. Verdicts 1-8 : dans le fichier de contrat. (9) Pas d'assombrissement, sur du JEU REEL, plusieurs niveaux, images comptees. (10) La SEULE reference est le pic ANNONCE, aucune constante ; prouve par l'EFFET a deux pics. (11) AMPLITUDE, PAS COMPTAGE : `hdr_out_hl_max_x1000` atteint l'essentiel de la marge REELLEMENT accordee. (12) La courbe suit la scene dans le TEMPS ; serie publiee sur plein jour / interieur / grotte ; constante = DEFAUT. (13) NEUF, refus 11/09 — LE FORMAT SE CHOISIT SEUL, POUR TOUT ECRAN : le jeu tournera sur des centaines d'appareils. Preference scRGB > HDR10 > HLG. HDR10+ ECARTE par decision de l'owner du 11/09 : aucune API publique ne laisse une application poser des metadonnees DYNAMIQUES ; notre courbe (verdict 12) en tient lieu, replis automatiques sur ce que l'ecran annonce, aucun appareil code en dur. Publier le format RETENU et la liste annoncee. Plusieurs formats disponibles ET choix a incidence mesurable : l'offrir en reglage ; sinon le dire. Dolby Vision HORS PERIMETRE (licence) : le constater. ANNONCER N'EST PAS ACCORDER : aucune marge rendue = verdict 11 ROUGE, et on le DIT.

## Preuve exigee
`hdr_out_defects == 0` dans `reports/hdr-display-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-display-output device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Eclairage Recharge : la ligne « sortie HDR ». Activee sur le Redmi, les zones brillantes doivent vraiment ressortir, sans que le reste change..

## Hors perimetre
Ne pas regresser le SDR livre. Profils HDR distincts autorises, aucune egalite numerique SDR/HDR exigee. Pas de nouveau chemin LDR demande.
