> LIS D'ABORD `prompts/item-hdr-display-output-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Sortir un vrai signal HDR sur les ecrans qui le supportent

## Defaut cite
- 2026-09-11 : « bah ca devrait aussi avoir pour impact d'avoir plus de detai… »

## Cause connue
L'ETUDE hdr-study DOIT ETRE LUE AVANT TOUTE CORRECTION : cet item en depend. Refus 11/09, cinquieme. L'owner ne voit toujours AUCUN gain dans les ombres. Le code dit pourquoi, en toutes lettres : `hdr_out_shadow_gain_x100` compare des NOMBRES DE PALIERS (10 bits contre 8), et son commentaire l'assume — « le SEUL gain que ce chemin livre quand l'ecran n'accorde aucune marge : la finesse ». 17 -> 127 niveaux est un effet de profondeur de quantification, PAS du detail visible. C'est exactement le piege « compter des paliers n'est pas mesurer une amplitude » que j'avais ferme pour les hautes lumieres et JAMAIS applique aux ombres. L'owner demande aussi si l'espace de couleur du calcul est assez […suite dans le contrat]

## Livrable
`hdr_out_defects` = 0. Verdicts 1-8 : dans le fichier de contrat, a lire. (9) PAS D'ASSOMBRISSEMENT, sur du JEU REEL, plusieurs niveaux, images comptees. (10) ADAPTATION A L'ECRAN : seule reference = le pic ANNONCE, aucune constante ; prouve par l'EFFET a deux pics. (11) RETABLI apres perte — SOURCE AVANT COMPRESSION : la sortie HDR consomme la scene HDR AVANT le tone map vers SDR. Publier l'identite du tampon lu et le nombre de compressions SDR subies par ce chemin : il vaut 0. Elever le plafond d'un tone map qui a deja ecrase N'EST PAS lire la scene HDR. Lire une image deja compressee = DEFAUT, quel que soit le reste. (12) RICHESSE DANS LES OMBRES — DURCI apres le 5e refus : compter des PA […suite dans le contrat]

## Preuve exigee
`hdr_out_defects == 0` dans `reports/hdr-display-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-display-output device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Eclairage Recharge : la ligne « sortie HDR ». Activee sur le Redmi, les zones brillantes doivent vraiment ressortir, sans que le reste change..

## Hors perimetre
Ne pas regresser le SDR livre. Profils HDR distincts autorises, aucune egalite numerique SDR/HDR exigee. Pas de nouveau chemin LDR demande.
