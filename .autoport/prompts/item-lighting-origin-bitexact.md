# Maitre eteint, l'image doit etre identique au bit au jeu d'origine

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Maitre Recharged ETEINT, la sortie doit etre identique AU BIT a la reference ORIGINE-TOTAL figee par lighting-census. Le moteur emet `origin_bitexact_defects` = nombre d'images qui different. Zero. Mesure le 2026-09-06 : `hdr_defect_4_master_off_bitexact=1` — quelque chose fuit alors que tout devrait etre desarme. L'owner l'avait soupconne (« tu passe bien par ce parametre pour gate nos effets ou tu les code en dur en remplacant le vanilla, alors que la SPEC stipule qu'on peut rester au rendu d'origine ») : la reponse de lecture de code etait rassurante, la MESURE ne l'est pas. Nommer ce qui fuit, ne pas ajouter de tolerance.

## Preuve exigee
`origin_bitexact_defects == 0` dans `reports/lighting-origin-bitexact/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-origin-bitexact x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Ne pas toucher a la courbe de compression : c'est lighting-hdr.
