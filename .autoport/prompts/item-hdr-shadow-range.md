> LIS D'ABORD `prompts/item-hdr-shadow-range-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le bas de la plage : du detail dans les ombres, pas seulement dans les hautes lumieres

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
RETOUR DE L'OWNER DU 12/09, teste sur le HONOR, mot pour mot : « scRGB display HDR c'est ce que ca dit pour le HDR on/off sur HONOR, en effet toggled on on a plus de details/pop dans les hauts blanc/zones brillantes, peut-etre un chouille plus de saturation globale (vraiment un chouilla) et pas plus de detail dans les ombres.... peut etre que c'est vraiment le max de ce qu'on peut esperer en l'etat ? je sais pas »
LA REPONSE EST NON, ET ELLE EST MESUREE. Les ombres ne bougent pas PAR CONTRAT : le livrable de `hdr-output-regime` exige « aucun pixel ne passe sous le niveau SDR » et « aucun pixel sous le seuil declare n'est modifie ». Sa preuve rend `hdr_regime_below_sdr_px` = 0. Le chantier a […suite dans le contrat]

## Livrable
`hdr_shadow_defects` = 0, somme de termes publies SEPAREMENT.
1. LE BAS DE LA PLAGE EST MESURE AVANT D'ETRE TOUCHE : publier, sur une scene sombre nommee, le nombre de paliers distincts rendus entre le noir et le premier dixieme de la plage, en sortie SDR et en sortie HDR. L'ecart est la grandeur qui compte. Si le compte est deja identique, l'item le DIT et s'arrete la : le defaut serait ailleurs.
2. LE GAIN EST DANS LE RENDU, PAS DANS LE CONTENEUR : publier separement les paliers que le conteneur PEUT porter et ceux que l'image porte REELLEMENT. Un conteneur plus large avec le meme nombre de paliers utilises n'est pas un gain.
3. RIEN NE S'ASSOMBRIT GLOBALEMENT. C'est le retour de l'owner d […suite dans le contrat]

## Preuve exigee
`hdr_shadow_defects == 0` dans `reports/hdr-shadow-range/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-shadow-range device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur le HONOR, sortie HDR allumee : une scene sombre — interieur, grotte, nuit — et les zones d'ombre. Il doit y avoir plus de detail qu'en SDR, sans que l'image s'assombrisse globalement..

## Hors perimetre
Ne touche pas au placement du blanc ni au choix du regime : `hdr-output-regime` les a tranches. Ne fabrique aucune difference sur un ecran qui n'accorde pas de marge.
