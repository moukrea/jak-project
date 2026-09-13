# Le compagnon .softbake : la coque imbriquee, ses chunks, son outil deterministe

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 3. Subdivision IMBRIQUEE L0 12,5 cm / L1 25 cm / L2 50 cm / L3 triangle d'origine, niveaux bas = sous-ensembles d'index des niveaux hauts ; sommets de frontiere partages a l'identique avec les voisins. En-tete de la famille des compagnons avec EMPREINTE DE CONTENU du .fr3 (jamais la taille : defaut connu du .grassbake, GrassRenderer.cpp:1032-1036) ; version du compagnon INDEPENDANTE de TFRAG3_VERSION (44, que lighting-bake bumpera).

## Livrable
`soft_bake_roundtrip_defects` = 0, somme de termes publies SEPAREMENT.
1. DEUX CUISSONS SONT BIT-IDENTIQUES et le round-trip integre relit le fichier et compare a zero ecart ; aucun aleatoire, aucune horloge, aucun fil ; `-ffp-contract=off` dans les trois arbres.
2. L'INVALIDATION LIT LE CONTENU : un .fr3 reconstruit a taille identique et contenu different declenche le recuit (temoin fabrique dans un bac a sable) ; un changement de la table des profils ou du .waterbake aussi.
3. LA CHAINE DE LOD EST IMBRIQUEE PAR CONSTRUCTION : compte d'index de L_k absents de L_k+1 = zero ; compte de sommets de frontiere de chunk presents dans les deux chunks avec le meme index = tous.
4. LE COUT EST CHIFFRE : taille du compagnon par niveau et par LOD, temps de cuisson par niveau, sections adressables par chunk ; declenchement automatique par la chaine de build prouve par un temoin.
PREUVE : `FEATURE soft-bake-format armed=1 hits=<chunks serialises>` + la ligne `soft_bake_roundtrip_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_bake_roundtrip_defects == 0` dans `reports/soft-bake-format/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-bake-format x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu..

## Hors perimetre
Ne charge rien dans le moteur, ne dessine rien : c'est soft-shell-renderer. Tout ce qui n'est pas cet item.
