> LIS D'ABORD `prompts/item-grass-surface-truth-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Une surface porte de l'herbe selon DEUX sources, pas selon trois noms de texture

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, et il porte le lien vers l'investigation complete que l'owner a validee le 12/09. SPEC sections 2 et 3. C'est la cle de toute la campagne. L'eligibilite tient aujourd'hui a TROIS noms de texture exacts — `tra-grass`, `bch-grassfringe`, `bch-leafyground-hang-2x1` — et c'est de la que vient la cause racine des onze rounds d'overhang : le detecteur de bord declare qu'une arete ouvre sur le vide quand aucun AUTRE TRIANGLE TEXTURE HERBE ne la partage, si bien qu'un changement de materiau est indiscernable d'un precipice. Or `pat-surface` porte, sur CHAQUE triangle de collision de CHAQUE niveau, un champ de materiau de 23 valeurs dont ` […suite dans le contrat]

## Livrable
`grass_surface_unclassified` = 0, somme de termes publies SEPAREMENT.
1. LES DEUX SOURCES SONT LUES ET PUBLIEES SEPAREMENT : pour chaque triangle de sol, la classification par nom de texture et celle par materiau de collision. Publier les deux comptes par niveau, et le compte de triangles qu'AUCUNE des deux ne classe — c'est lui qui doit valoir zero.
2. LE DESACCORD SE COMPTE, IL NE SE DEVINE PAS. Publier le compte de triangles ou les deux sources divergent, avec les noms de texture impliques. Un desaccord n'est pas un defaut de cet item : c'est une donnee que les items suivants utiliseront. Le cacher en serait un.
3. RIEN NE CHANGE ENCORE DANS LE PLACEMENT : le compte de brins poses et leur […suite dans le contrat]

## Preuve exigee
`grass_surface_unclassified == 0` dans `reports/grass-surface-truth/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-surface-truth x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu. C'est une vue de debug : chaque triangle colore par son materiau de collision, et les desaccords en evidence..

## Hors perimetre
NE CHANGE AUCUN PLACEMENT. Ne touche ni au bord, ni aux transitions, ni a l'overhang — ce sont les items suivants, et ils dependent de celui-ci. Tout ce qui n'est pas cet item.
