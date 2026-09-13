# Les paliers et le menu des surfaces meubles

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 12. `recharged_soft` : Auto / Tres bas / Bas / Moyen / Haut / Ultra, matrice de depart de l'artifact section 25 ; Tres bas = coque NON CHARGEE ; un palier inferieur reduit resolution, portee, interacteurs, JAMAIS le profil. Menu : recharged_master -> recharged_soft, masquer pas griser, vrai sous-menu (owner 10/09). Chaque OFF bit-identique a l'absence par binaire-temoin.

## Livrable
`soft_preset_apply_mismatch` = 0, somme de termes publies SEPAREMENT.
1. REGLAGE DEMANDE = REGLAGE APPLIQUE : pour chaque axe et chaque palier, valeur demandee et valeur lue publiees, compte d'ecarts = zero.
2. TRES BAS EST L'ABSENCE : image bit-identique a OFF et a l'absence de la couche compilee ; compagnon non charge.
3. LE PROFIL NE BOUGE PAS AVEC LE PALIER : valeurs de profil identiques en Bas et Ultra (compte d'ecarts = zero).
4. LE MENU EST CONFORME : sous-menu present sous recharged_master, entrees masquees quand le maitre est eteint (compte d'entrees grisees = zero).
PREUVE : `FEATURE soft-presets armed=1 hits=<axes de reglage appliques>` + la ligne `soft_preset_apply_mismatch=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_preset_apply_mismatch == 0` dans `reports/soft-presets/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-presets device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Surfaces meubles : Auto, Tres bas, Bas, Moyen, Haut, Ultra — et rien de grise..

## Hors perimetre
Pas de mesure de budget : items suivants. Tout ce qui n'est pas cet item.
