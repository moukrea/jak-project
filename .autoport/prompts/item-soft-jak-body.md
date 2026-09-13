# Jambes, receptions, glissades et roulades dans la neige profonde : un sillon continu

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 5. Capsules hanche->genou->cheville actives seulement si l'epaisseur disponible depasse les chevilles ; reception = disque a la racine selon ground-impact-vel ; glissade = capsule allongee selon transv ; roulade = sphere de la racine balayee ; accroche de rebord = rien.

## Livrable
`soft_body_defects` = 0, somme de termes publies SEPAREMENT.
1. LE SILLON EST CONTINU : longueur de trace mesuree / distance parcourue ≥ 0,98 sur une course scriptee dans une congere ; compte de trous = zero.
2. LA LARGEUR SUIT L'ETAT : largeur de trace publiee par classe d'etat (marche, course, glissade, roulade, reception) ; l'ordre declare est respecte.
3. LES JAMBES NE TRAVAILLENT QUE LA OU IL Y A DE LA MATIERE : compte de tampons de jambe sur une epaisseur < hauteur de cheville = zero.
4. RIEN EN ACCROCHE NI EN L'AIR : compte de tampons de corps en edge-grab, jump, falling = zero.
PREUVE : `FEATURE soft-jak-body armed=1 hits=<tampons de corps appliques>` + la ligne `soft_body_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_body_defects == 0` dans `reports/soft-jak-body/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-jak-body device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Dans une congere de Snowy Mountain : la neige s'ouvre autour des jambes, un sillon suit Jak, une glissade laisse une trace allongee..

## Hors perimetre
Pas d'ennemi, pas d'objet, pas de bourrelet fin. Tout ce qui n'est pas cet item.
