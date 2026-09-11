> LIS D'ABORD `prompts/item-hdr-display-output-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Sortir un vrai signal HDR sur les ecrans qui le supportent

## Defaut cite
- 2026-09-11 : « C'est a chier ! On retombe litteralement sur le pas de diff… »

## Cause connue
QUATRE TOURS, ET LA PLAINTE DE FOND N'A JAMAIS ETE MESUREE. L'owner dit la MEME chose depuis le 10/09 : « on dirait qu'on traite le rendu tonemape a destination du SDR » et « on gagne pas de richesse dans les ombres parce que cette richesse n'est deja plus la dans l'image qu'on traite ». J'avais ecrit DEUX verdicts pour ca le 10/09 — SOURCE AVANT COMPRESSION et RICHESSE DANS LES OMBRES — et je les ai PERDUS en raccourcissant la consigne (commit c054ce9a48). L'item est donc passe 15/15 sans que ni l'un ni l'autre soit mesure, quatre fois de suite. Les verdicts sont retablis ci-dessous et cette liste NE DOIT PLUS JAMAIS RETRECIR : le contrat porte le detail, la consigne peut le resumer, mais a […suite dans le contrat]

## Livrable
`hdr_out_defects` = 0. Verdicts 1-8 : dans le fichier de contrat, a lire. (9) PAS D'ASSOMBRISSEMENT, sur du JEU REEL, plusieurs niveaux, images comptees. (10) ADAPTATION A L'ECRAN : seule reference = le pic ANNONCE, aucune constante ; prouve par l'EFFET a deux pics. (11) RETABLI apres perte — SOURCE AVANT COMPRESSION : la sortie HDR consomme la scene HDR AVANT le tone map vers SDR. Publier l'identite du tampon lu et le nombre de compressions SDR subies par ce chemin : il vaut 0. Elever le plafond d'un tone map qui a deja ecrase N'EST PAS lire la scene HDR. Lire une image deja compressee = DEFAUT, quel que soit le reste. (12) RETABLI apres perte — RICHESSE DANS LES OMBRES, mesuree sur du jeu […suite dans le contrat]

## Preuve exigee
`hdr_out_defects == 0` dans `reports/hdr-display-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-display-output device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Eclairage Recharge : la ligne « sortie HDR ». Activee sur le Redmi, les zones brillantes doivent vraiment ressortir, sans que le reste change..

## Hors perimetre
Ne pas regresser le SDR livre. Profils HDR distincts autorises, aucune egalite numerique SDR/HDR exigee. Pas de nouveau chemin LDR demande.
